# Architecture Audit

Reconstructed from the code; documentation was compared afterwards
([DOCUMENTATION_AUDIT.md](DOCUMENTATION_AUDIT.md)).

## Components

| Component | Files | Responsibility |
|-----------|-------|----------------|
| Native capture | `SmsReceiver.kt`, `UpiNotificationListener.kt` | Receive SMS (manifest receiver, `BROADCAST_SMS`) and allowlisted notifications (bound listener service); re-broadcast to the activity |
| Channel host | `MainActivity.kt` | Method channel (`isNotificationAccessGranted`, `openNotificationAccessSettings`, `readSmsHistory`, `updateWidget`) and two event channels backed by dynamically registered receivers |
| Widget | `SpendingWidgetProvider.kt` | Renders a SharedPreferences snapshot pushed from Dart |
| Orchestrator | `lib/providers/transaction_provider.dart` | Capture subscription, ML gate, parsing, dedup, location, persistence, history scan, sync scheduling, widget push, UI state |
| ML gate | `lib/services/ml/*` | Three TF-IDF/LogReg models loaded from bundled JSON |
| Parser | `lib/services/upi_parser.dart` | Regex extraction of amount, direction, counterparty, refs, balance, embedded dates |
| Dedup | `lib/services/dedup_service.dart` | Hash chain + fuzzy candidate matching against SQLite |
| Storage | `lib/database/local_database.dart` | SQLite schema v2 (`transactions`, `debts`) |
| Sync | `lib/services/sync_service.dart`, `lib/database/remote_database.dart` | Push-only upsert into Postgres over a direct connection |
| Debts | `lib/providers/debt_provider.dart`, `lib/services/debt_backup_service.dart` | Manual ledger, JSON export/restore |
| Trainer | `scripts/ml_core.py`, `train_all_models.py`, `generate_ml_fixtures.py` | Offline training and parity fixtures |

## Primary data flow (as found)

```
SMS ──► SmsReceiver ─┐                         (implicit broadcast — S3, fixed)
Notif ─► Listener ───┴─► MainActivity receiver ─► EventChannel ─► TransactionProvider
                          (exists only while the activity is alive and Dart subscribed)
TransactionProvider: [isUpiRelated (SMS only)] → MessagePipeline.evaluate
   → UpiParser → (start-date filter) → Dedup → Location (≤10 s, inline) → SQLite
   → loadTransactions + loadSummary (full reload) → widget snapshot push
Periodic: SyncService → RemoteDatabase.upsert (row by row) → shared Postgres
```

The capture chain had two independent breaks (C1): Dart only subscribed after a manual
Settings toggle each launch, and the native side drops events whenever the activity is
not alive. The first is fixed; the second remains (no persistent native queue, no
foreground service, no boot receiver despite the declared permission — S12).

## Architectural issues

- **No server tier (S2).** The most consequential design decision: credentials on the
  client, shared table, no per-user isolation. Not fixable by client changes.
- **God object (A1).** `TransactionProvider` mixes I/O, business rules and view state;
  record construction is duplicated between the live and history paths (and they had
  already diverged: only the live path tags location). Its untestability is why C1, C7
  and C8 went unnoticed (T5).
- **Two serialisation paths (C14).** `toMap()` for SQLite (naive local ISO strings) vs a
  hand-built parameter map for Postgres (`DateTime` into `TIMESTAMPTZ`).
- **Widget is push-only (C20).** Correct choice for reliability ("never open SQLite from a
  receiver"), but with no staleness handling.
- **Package directory mismatch (A2).** Cosmetic.
- **Multi-platform scaffolding** (iOS/macOS/web/Windows/Linux) exists but capture is
  Android-only; those targets would compile without any data source. INFO.

## Cross-layer contract check

The Kotlin ↔ Dart channel contract (channel names, method names, argument and payload
keys) matches exactly; the only unused field is `subText` on notification events. The
SQLite schema matches `TransactionRecord.toMap`/`fromMap`; the remote schema lacks
`synced` (harmless because the sync path does not use `toMap`). The seed script creates
two remote indexes that the app's lazy `_ensureTables` does not.
