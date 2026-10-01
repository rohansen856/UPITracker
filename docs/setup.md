# Setup

## Prerequisites

- Flutter SDK 3.11+ (Dart SDK constraint `^3.11.4` in [pubspec.yaml](../pubspec.yaml))
- An Android device or emulator — the notification listener and SMS receiver are
  Android-only, `minSdk 26`
- Python 3.10+ only if retraining the ML models
  (see [ml-training.md](ml-training.md))

## Environment

Create `.env` in the project root. It is declared as a Flutter asset (so the build
fails without the file) and loaded at startup by `flutter_dotenv` with
`isOptional: true`:

```env
DATABASE_URL=postgresql://user:pass@host:5432/dbname?sslmode=require
SYNC_ENABLED=true
SYNC_INTERVAL_MINUTES=15
```

- `DATABASE_URL` — Postgres/Neon connection string; SSL is always required by the
  client regardless of the query string.
- `SYNC_ENABLED=false` disables cloud sync entirely (the app stays fully functional
  offline; the Settings "Sync Now" tile shows "Sync is disabled in .env").
- `SYNC_INTERVAL_MINUTES` — periodic sync interval (default 15).

`.env` is gitignored, but because it is a Flutter asset **the database credentials ship
in plaintext inside every APK** (`assets/flutter_assets/.env`). Anyone with the APK has
full access to the shared remote database. Do not distribute builds with a real
`DATABASE_URL`; set `SYNC_ENABLED=false` (or remove `.env` from `pubspec.yaml` assets) for
any build that leaves your hands. See `AUDIT/SECURITY_AUDIT.md` (S1/S2).

## Install & run

```bash
flutter pub get
flutter run
```

## Seed the remote database (optional)

```bash
dart run scripts/seed_db.dart
```

Creates the remote `transactions` table and indexes; the app also does this lazily on
first sync, so seeding is a convenience/verification step.

## Permissions

Requested/managed from the Settings screen:

| Permission | Required | Purpose |
|---|:---:|---|
| Notification Access | yes | Read UPI app payment notifications. Granted via the system notification-listener settings page (opened by the "Grant" button) — cannot be a runtime dialog. |
| `READ_SMS` / `RECEIVE_SMS` | yes | Read bank/UPI SMS in real time and scan history. |
| Location (coarse + fine) | optional | Tag transactions with where you paid. |
| Internet | optional | Cloud sync only. |

After granting, enable **Live Monitoring** in Settings to start the listeners, and
optionally run **Scan SMS History** to import past transactions (respects the
configurable tracking **Start Date**, which ignores anything older).

## Retrain the ML stack (optional)

Download the dataset bundle into `data/` first (see
[ml-training.md](ml-training.md#datasets-data)), then:

```bash
python3 -m pip install scikit-learn pandas numpy
python3 scripts/train_all_models.py
python3 scripts/generate_ml_fixtures.py
flutter test
```

## Tests

```bash
flutter test
```

No device needed — database suites use `sqflite_common_ffi`, and the accuracy suites
skip automatically when the gitignored CSVs are absent. See [testing.md](testing.md).
