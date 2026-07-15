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
"Live Monitoring" switch in Settings). `initialize()` — called eagerly at app start —
loads the tracking start date, kicks off the ML model load (fire-and-forget, fail-open),
loads transactions and summaries, and starts periodic sync.

## Pipeline stages (live SMS/notification)

1. **Keyword prefilter** (SMS only) — `UpiParser.isUpiRelated(body)`: cheap lowercase
   substring scan (`upi`, `debited`, `₹`, `trf to`, `refno`, `neft`, `imps`, …).
2. **ML gate** — `MessagePipeline.instance.evaluate(text)`. Drops spam (layer 1) and
   non-transactional messages like OTPs/balance alerts (layer 2). Every layer fails
   open, so a missing model never drops a real payment. Dropped messages are
   `debugPrint`ed with stage + reason. See [ml-pipeline.md](ml-pipeline.md).
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
over up to 500 historical SMS, without the location lookup. It tallies
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
