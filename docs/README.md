# UPI Tracker — Documentation

UPI Tracker is an offline-first Flutter app (Android-only in practice) that consolidates
UPI payments across apps (GPay, PhonePe, Paytm, BHIM, …) and banks (SBI, HDFC, ICICI, …)
into a single ledger by reading **notifications and SMS in real time**. A stacked
three-layer on-device ML gate filters spam, OTPs and other non-transactional noise before
anything is parsed and stored. SQLite is the source of truth; an optional Postgres (Neon)
backup is kept in sync. The app also ships a manual **Debts & Lending** ledger and a
home-screen widget.

## Index

### Overview

- [Architecture](architecture.md) — system overview, ingestion data flow, project layout, environment variables
- [Setup](setup.md) — prerequisites, `.env`, running, seeding, permissions

### Features

- [Transaction capture](features/transaction-capture.md) — notification + SMS ingestion pipeline end-to-end
- [UPI parser](features/upi-parser.md) — regex engine, app/sender identification, supported formats
- [ML pipeline](features/ml-pipeline.md) — the 3-layer spam → transactional → direction cascade
- [Deduplication](features/deduplication.md) — tiered hashes + fuzzy candidate matching
- [Cloud sync](features/sync.md) — push-only sync with remote-integrity recovery
- [Debts & lending](features/debts.md) — manual IOU ledger (not covered by the top-level README)
- [Analytics](features/analytics.md) — summaries, 24-hour windows, 7-day spending buckets
- [Home-screen widget](features/home-widget.md) — snapshot-based Android widget
- [Location tagging](features/location-tagging.md) — best-effort geotagging

### UI

- [Navigation & theme](ui/navigation-and-theme.md) — `AppShell`, Material 3 theme, semantic colors
- [Screens](ui/screens.md) — Dashboard, Transactions, Transaction Detail, Debts, Settings
- [Widgets](ui/widgets.md) — reusable UI components

### Data

- [Database](data/database.md) — SQLite and Postgres schemas, indexes, DAO methods
- [Models](data/models.md) — `TransactionRecord`, `DebtEntry`, enums, serialization

### Android native

- [Native layer](android/native-layer.md) — manifest, permissions, Kotlin classes, Gradle config
- [Platform channels](android/platform-channels.md) — channel names, methods, event payloads

### Engineering

- [ML training](ml-training.md) — Python trainer, datasets, augmentation, retraining workflow
- [Testing](testing.md) — test layers, parity fixtures, corpus guarantees
