# UPI Tracker

A unified UPI payment tracker that consolidates transactions from multiple UPI apps (GPay, Paytm, PhonePe, BHIM, etc.) into a single, organized record by reading your phone's notifications and SMS messages.

## Features

- **Multi-App Tracking** — Captures payments from Google Pay, PhonePe, Paytm, BHIM, Amazon Pay, and bank SMS
- **Notification Listener** — Real-time capture via Android's NotificationListenerService
- **SMS Parsing** — Reads bank transaction SMS with intelligent UPI pattern matching
- **Deduplication** — Same payment from notification + SMS is only recorded once (hash-based on amount, time window, UPI ref, and counterparty)
- **Offline-First** — All data stored locally in SQLite; works without internet
- **Cloud Sync** — Syncs to PostgreSQL (Neon) when online; configurable interval
- **Location Tagging** — Optionally tags each transaction with GPS location
- **Editable Notes & Tags** — Add personal notes and comma-separated tags to any transaction
- **Analytics** — Total spent/received, net balance, daily trend charts, spending by app (pie chart)
- **Filters** — By type (spent/received), app, date range, and text search
- **Manual Entry** — Add transactions manually when auto-capture misses one
- **Material 3 UI** — Clean, professional design with light/dark theme support

## Architecture

```
lib/
├── main.dart                    # App entry point
├── app.dart                     # Navigation shell
├── config/theme.dart            # Material 3 theme
├── models/transaction_record.dart
├── database/
│   ├── local_database.dart      # SQLite (offline-first)
│   └── remote_database.dart     # PostgreSQL (Neon) sync
├── services/
│   ├── upi_parser.dart          # UPI message parsing engine
│   ├── dedup_service.dart       # Duplicate detection
│   ├── notification_service.dart
│   ├── sms_service.dart
│   ├── sync_service.dart
│   └── location_service.dart
├── providers/
│   └── transaction_provider.dart
├── screens/
│   ├── dashboard_screen.dart
│   ├── transactions_screen.dart
│   ├── transaction_detail_screen.dart
│   ├── analytics_screen.dart
│   └── settings_screen.dart
└── widgets/
    ├── transaction_card.dart
    ├── summary_card.dart
    └── filter_sheet.dart
```

## Setup

### Prerequisites

- Flutter SDK 3.11+
- Android Studio / VS Code
- An Android device (notification listener is Android-only)

### Environment Variables

Create a `.env` file in the project root:

```env
DATABASE_URL=postgresql://user:pass@host:5432/dbname?sslmode=require
SYNC_ENABLED=true
SYNC_INTERVAL_MINUTES=15
```

### Install & Run

```bash
flutter pub get
flutter run
```

### Seed the Remote Database

```bash
dart run scripts/seed_db.dart
```

## Permissions

The app requests these Android permissions:

| Permission | Required | Purpose |
|---|---|---|
| Notification Access | Yes | Read UPI app payment notifications |
| READ_SMS | Yes | Read bank transaction SMS |
| RECEIVE_SMS | Yes | Capture incoming bank SMS in real-time |
| Location | Optional | Tag transactions with where you paid |
| Internet | For sync | Push records to cloud database |

## Deduplication Strategy

A single payment often generates multiple signals (UPI app notification + bank SMS). The dedup engine prevents double-counting:

1. If a UPI transaction ID or bank reference number is found, it's used as the unique key
2. Otherwise, a hash is computed from: `amount + 10-minute time window + counterparty`
3. New transactions are checked against this hash before insertion

## Offline-First Flow

1. Transaction is captured (notification/SMS/manual)
2. Parsed and deduplicated locally
3. Stored in SQLite with `synced = false`
4. When online, unsynced records are pushed to PostgreSQL
5. On success, local records are marked `synced = true`
