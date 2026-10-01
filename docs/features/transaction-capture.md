# Transaction capture

How a UPI payment on the phone becomes a row in the ledger. Orchestrated by
[lib/providers/transaction_provider.dart](../../lib/providers/transaction_provider.dart).

## Sources

| Source | Entry point | Native origin |
|---|---|---|
| `notification` | `_handleNotification` via `NotificationService.notificationStream` | `UpiNotificationListener` (Kotlin), package-allowlisted |
| `sms` | `_handleSms` via `SmsService.incomingSmsStream` | `SmsReceiver` (Kotlin), `SMS_RECEIVED` broadcast |
| `sms` (historical) | `scanSmsHistory()` — reads up to **500** past SMS through the `readSmsHistory` method channel | SMS content provider query |
| `manual` | `addManualTransaction(...)` from the Settings screen | — |

Listening starts/stops via `startListening()` / `stopListening()` (bound to the
"Live Monitoring" switch in Settings). The switch is a **persisted preference**
(SharedPreferences `live_monitoring_enabled`, default `true`). `initialize()` — run when
the provider is first read — loads the tracking start date, **awaits** the ML model load
(so nothing is evaluated by unloaded, fail-open models), loads transactions and
summaries, starts listening if the preference is on, starts the SMS catch-up (below) and
starts periodic sync.

Stream errors from either event channel stop listening and set the provider's `error`
text instead of leaving a dead subscription that still reports "listening".

### What is and is not captured while the app is closed

The Kotlin receivers forward events to Dart only while `MainActivity` is alive and Dart
is subscribed; there is no native queue.

- **SMS** remain in the system SMS provider. On every launch `_catchUpSms()` reads SMS
  newer than the last scan watermark (SharedPreferences `sms_scan_watermark_ms`, set by
  every history scan) and runs them through the normal pipeline. The watermark only
  exists after the first manual *Scan SMS History*.
- **Notifications** that arrive while the app is not running are **lost**. Most UPI
  payments also produce a bank SMS, which the catch-up recovers.

## Pipeline stages (live SMS/notification)

1. **Keyword prefilter** (SMS only) — `UpiParser.isUpiRelated(body)`: cheap lowercase
   substring scan (`upi`, `debited`, `₹`, `trf to`, `refno`, `neft`, `imps`, …).
2. **ML gate** — `MessagePipeline.instance.evaluate(text, sender: smsSender)`. Drops spam
   (layer 1) and non-transactional messages like OTPs/balance alerts (layer 2), unless the
   message carries settlement evidence (a 12-digit RRN/UTR next to a settlement verb from
   a registered sender — see [ml-pipeline.md](ml-pipeline.md)). Every layer fails open.
   Dropped messages are `debugPrint`ed with stage + reason.
3. **Regex parse** — `UpiParser.parseNotification(...)` / `parseSms(...)`. Dropped if
   `!parsed.isValid` (needs positive amount + detected type).
   See [upi-parser.md](upi-parser.md).
4. **Direction cross-check** — if the ML direction hint disagrees with the parser's
   debit/credit, the mismatch is logged only; **the parser always wins**.
5. **`_processTransaction(parsed, timestamp, source, rawText)`**:
   - Skip if `timestamp` is before the user-configured tracking start date
     (SharedPreferences key `tracking_start_date`, set in Settings).
   - Compute the dedup hash and skip duplicates
     (see [deduplication.md](deduplication.md)).
   - Best-effort geolocation (live capture only —
     see [location-tagging.md](location-tagging.md)).
   - Build a `TransactionRecord` (UUID v4 id, `synced = false`), insert into SQLite,
     reload the list and summaries (which also refreshes the home-screen widget).

## SMS history scan

`scanSmsHistory()` runs the same filter → ML gate → parse → start-date → dedup pipeline
over the **500 most recent SMS from all senders** (older messages are not reachable),
without the location lookup. Only received messages (`Telephony.Sms.TYPE` = 1) are
ingested; sent/draft/outbox rows are skipped. The transaction date is the SMS delivery
timestamp. Each scan advances the catch-up watermark. It tallies
added / spam-filtered / non-transactional counts and reports them through the provider's
`error` field, which the Settings screen surfaces as a status message
(e.g. "Found 12 new transactions • filtered 3 spam").

## Manual entries

`addManualTransaction({amount, type, counterpartyName, upiApp, note, tags, date})`
inserts with `source: 'manual'` and dedup hash `manual:<uuid4>` — guaranteed unique, so
manual entries can never collide with captured ones.

## Edits and deletes

- `updateNote(id, note)` / `updateTags(id, tags)` — `copyWith` + `synced: false` so the
  edit re-syncs (the remote upsert only refreshes note/tags/updated_at).
- `deleteTransaction(id)` — local delete only; a previously synced row persists remotely.
