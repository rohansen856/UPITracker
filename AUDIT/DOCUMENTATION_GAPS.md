# Documentation Gaps

Behaviour that exists in the code (or now exists after the fixes) that a developer,
operator, security reviewer or user needs to know about, and that the documentation did
not cover. Items marked **documented** were written up in `docs/` during this audit,
based only on verified behaviour.

| # | Behaviour | Audience | Status |
|---|-----------|----------|--------|
| G1 | The remote database is **one shared table for every install**, with no user or device column, and the client holds full write access | Security, operators | Documented (`docs/features/sync.md` trust model) |
| G2 | Live Monitoring is a persisted preference that defaults to on. Capture starts at launch after the models load; SMS received while the app was closed are recovered from a timestamp watermark; the first full import still needs the user to run *Scan SMS History* | Users, developers | Documented (`docs/features/transaction-capture.md`) |
| G3 | **Notifications that arrive while the app is not running are lost.** There is no native queue or foreground service | Users, developers | Documented as a known limitation |
| G4 | Settlement-evidence rule: a 12-digit RRN/UTR/UPI Ref plus a settlement verb, from a DLT-registered SMS header or an allowlisted notification, cannot be vetoed by the classifiers | Developers, ML | Documented (`docs/features/ml-pipeline.md`) |
| G5 | History scans read at most the 500 most recent SMS from **all** senders, and use the device's SMS timestamp, not the date in the message | Users, developers | Documented |
| G6 | Only received (inbox) SMS are ingested; sent, draft and outbox rows are skipped | Developers | Documented |
| G7 | Location lookup runs inline, for up to 10 s, before a live capture is stored; the coordinates are synced | Privacy, developers | Documented (`docs/features/location-tagging.md`) |
| G8 | The widget only updates while the app process is running; its "last 24 hours" can be stale | Users | Documented (`docs/features/home-widget.md`) |
| G9 | Android backup and device transfer are disabled, so transactions are **not** restored on a new phone except via cloud sync | Users | Documented (`docs/android/native-layer.md`) |
| G10 | The debt backup JSON is in app-specific storage (`Android/data/<pkg>/files/UPITracker/debts_ledger.json`), is plaintext, needs no permission, and is **deleted on uninstall** | Users | Documented (`docs/features/debts.md`) |
| G11 | The Python training environment versions (scikit-learn 1.9.0, numpy 2.5.1 locally) are not pinned anywhere | ML maintainers | Recorded (D1); pinning left to owner |
| G12 | Notification allowlist contents and their known gaps (installed SBI, super.money, Navi and Amazon apps not covered; WhatsApp included) | Developers | Recorded (C21); list not changed |

## Still undocumented (needs owner input)

- Which held-out metrics describe the shipped models (DOC7).
- Data-handling policy for test fixtures. `data/README.md` forbids committing real SMS, but
  the fixtures contain them (S11).
- Operational runbook for credential rotation and remote-database recovery. There is
  currently no procedure.
