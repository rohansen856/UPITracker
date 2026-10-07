# UPI Tracker

Offline-first Android app that consolidates UPI payments across apps (GPay,
PhonePe, Paytm, BHIM, Amazon Pay, …) and banks (SBI, HDFC, ICICI, Axis,
Kotak, …) into a single ledger by reading **notifications + SMS** in
real time.

A three-layer on-device ML stack filters promotional junk, OTPs, balance
alerts, failed transactions and the like **before** anything touches the
database, so the ledger stays clean.

---

## Features

- **Multi-app capture** — live notification listener + SMS receiver cover
  every major UPI app and bank.
- **Stacked ML gate** — spam → transactional → direction classifiers run
  on-device on every inbound message (see [ML stack](#ml-stack)).
- **Robust UPI parser** — regex engine tolerant of every SMS format in the
  provided `data/upi*.csv` files (SBI debits/credits, HDFC "Sent Rs.", ICICI,
  Axis, Kotak, PNB, GPay, PhonePe, Paytm, Paytm, NEFT receipts, etc.).
- **Deduplication** — same payment from notification + SMS is recorded
  once. The stored key is an MD5 of the UPI transaction id, else the bank
  reference, else the normalised message body; a separate fuzzy tier
  compares amount, direction, counterparty and a ±10-minute window
  (see `docs/features/deduplication.md`).
- **Offline-first** — SQLite is authoritative; Postgres (Neon) is a
  push-only backup: rows are upserted to the remote and never read back,
  and local deletes are not propagated (see `docs/features/sync.md`).
- **Location tagging** (optional), **editable notes + tags**, **start-date
  gate** (ignore SMS before a user-configured cutoff).
- **Analytics** — daily trend, totals, category / merchant breakdown,
  filters by type / app / date / text.
- **Home-screen widget** — today's spent vs received, full-width.
- **Material 3 UI**, light-mode default.

---

## ML stack

The ML gate is a **stacked cascade of three tiny logistic-regression
classifiers** sharing the same preprocessing and TF-IDF (1–2 gram, L2,
sublinear-TF) feature space. Total on-disk payload **≈ 344 KB**.

```
incoming SMS / notification
   │
   │  UpiParser.isUpiRelated   (cheap keyword prefilter)
   │
   ▼
┌───────────────── Layer 1 : spam filter ──────────────────┐
│  assets/spam_model.json — 152.7 KB, 3 000 features       │
│  Threshold 0.85 (P=1.000, R=0.917 on held-out)           │
│  Drops promotional / scam / phishing messages.           │
└───────────────────────────┬──────────────────────────────┘
                            │ passes
                            ▼
┌────────────── Layer 2 : transactional classifier ────────┐
│  assets/transactional_model.json — 158.9 KB              │
│  Threshold 0.5 (P=1.000, R=1.000 on held-out)            │
│  Drops OTPs, balance alerts, bill reminders, card spend  │
│  alerts, declined / failed transactions, non-finance     │
│  chatter.                                                │
└───────────────────────────┬──────────────────────────────┘
                            │ passes
                            ▼
┌──────────────── Layer 3 : direction classifier ──────────┐
│  assets/direction_model.json — 38.1 KB, 731 features     │
│  P(credit) vs P(debit). Used as a second opinion —       │
│  parser stays authoritative; disagreements are logged.   │
└───────────────────────────┬──────────────────────────────┘
                            ▼
                   UpiParser.parseSms
                            ▼
                    SQLite (+ sync)
```

Each layer **fails open**: a missing / corrupt model never drops a real
message. Worst case the app degrades to its regex-only behaviour.

### Why stacked, not one big model?

- **Separation of concerns** — spam, "not a completed tx" and direction are
  three different problems. One model couldn't pick thresholds that suit
  all of them simultaneously.
- **Short-circuit cost** — 98 % of decisions are made at layer 1, at ~5 µs
  per message.
- **Independent retraining** — adding more OTP samples only rebuilds
  `transactional_model.json`; the other two stay frozen.

### Inference (Dart side)

The engine is 180 lines of pure Dart in [`lib/services/ml/tfidf_logreg.dart`](lib/services/ml/tfidf_logreg.dart).
No heavy ML runtime, no isolates, no TFLite / ONNX. Preprocessing mirrors
the Python trainer byte-for-byte; fixture tests assert
`|dart_prob − python_prob| < 1e-4` for every model.

```dart
final decision = MessagePipeline.instance.evaluate(body);
if (!decision.shouldIngest) return;   // dropped by layer 1 or 2
// proceed to UpiParser.parseSms(...), with decision.directionHint
// available as a cross-check against parser output.
```

Classifiers: [`SpamFilter`](lib/services/ml/classifiers.dart) /
[`TransactionalClassifier`](lib/services/ml/classifiers.dart) /
[`DirectionClassifier`](lib/services/ml/classifiers.dart).

### Training (Python side)

Shared preprocessing + feature engineering + trainer live in
[`scripts/ml_core.py`](scripts/ml_core.py). The orchestrator
[`scripts/train_all_models.py`](scripts/train_all_models.py) loads the
datasets, trains all three models, prints a metrics table at multiple
thresholds, and writes the JSON blobs under `assets/`.

```bash
pip install scikit-learn pandas numpy
python3 scripts/train_all_models.py
python3 scripts/generate_ml_fixtures.py   # regenerate Dart parity fixtures
```

### Current held-out metrics (at model-default thresholds)

| Model                                  | Thr    | P      | R      | F1     | FP | FN | test N |
|----------------------------------------|:------:|--------|--------|--------|----|----|--------|
| Spam filter                            | 0.85   | 1.000  | 0.917  | 0.957  | 0  | 19 | 1 396  |
| Transactional classifier               | 0.50   | 1.000  | 1.000  | 1.000  | 0  | 0  | 260    |
| Direction classifier                   | 0.50   | 0.958  | 1.000  | 0.979  | 2  | 0  | 97     |
| Direction classifier                   | 0.70   | 1.000  | 1.000  | 1.000  | 0  | 0  | 97     |

### Corpus-wide sweep on 382 real UPI SMS (`data/upi*.csv`)

Measured by `test/accuracy/corpus_accuracy_test.dart` and
`test/accuracy/model_consistency_test.dart`. These figures are on the
**training** corpus. On an independent real inbox the classifiers alone
dropped two bank templates entirely (12 real transactions); the
settlement-evidence rule in `MessagePipeline` now prevents that. The
held-out numbers above and those in `docs/ml-training.md` disagree and
need regenerating from a pinned training run.

| Metric                                                      | Value        |
|-------------------------------------------------------------|--------------|
| Real UPI SMS ingested by the full pipeline                  | **381 / 381 (100%)** |
| Direction-confident (parser agrees with model)              | 380 / 381 (99.7%) |
| Max `P(spam)` on any real UPI SMS (threshold 0.85)          | **0.206**    |
| Min `P(transactional)` on any real UPI SMS (threshold 0.5)  | **0.571**    |
| Max `P(transactional)` on 13 curated non-tx samples         | **0.114**    |

Headroom is ~0.6 on the spam side and ~0.5 on the transactional side,
which means the stack has plenty of margin for retraining without
degradation.

---

## Datasets

The training data lives under `data/` — a **gitignored** folder tracked
only through `data/.gitkeep` and `data/README.md`. The CSVs are
distributed separately because `upi*.csv` contains real SMS with personal
data.

**Download the datasets from Google Drive:**
> https://drive.google.com/drive/folders/19AV_DytumoGD7GLs9f--FxPwHfm7nSax

Put every file **into `data/`** (if you download the whole folder as a zip,
extract it there) and you should end up with:

| File                        | Rows   | Label    | Notes                                                             |
|-----------------------------|--------|----------|-------------------------------------------------------------------|
| `data/spam.csv`             | 5 572  | spam/ham | Kaggle English SMS collection (base spam corpus).                 |
| `data/spam_ham_india.csv`   | 2 268  | spam/ham | India-specific SMS, shifts priors toward the target distribution. |
| `data/upi1.csv`             | 134    | ham      | Real UPI SMS from the user's phone (SBI debit + credit).          |
| `data/upi2.csv`             | 115    | ham      | Real UPI SMS (batch 2).                                           |
| `data/upi3.csv`             | 133    | ham      | Real UPI SMS (batch 3).                                           |

All UPI rows are labeled `ham` because every one of them is a genuine
completed transaction. The trainer derives debit / credit from the text
itself ("debited by" vs "credited by") to feed the direction model.

The `upi*.csv` files deliberately keep commas inside message bodies
unquoted — the loader in `scripts/ml_core.py` splits on the **rightmost**
comma so you can curate new rows without escaping anything.

See [`data/README.md`](data/README.md) for the per-file schema and
instructions on adding your own SMS / spam / non-transactional samples.

### Training-time augmentation

[`scripts/ml_core.py`](scripts/ml_core.py) ships two curated lists used
only at train time, kept in code so they are version-controlled even
though the real data isn't:

- `SYNTHETIC_DEBITS` / `SYNTHETIC_CREDITS` — HDFC, ICICI, Axis, Kotak, PNB,
  BoB, Canara, IOB, Federal, GPay, PhonePe, Paytm, BHIM, Amazon Pay, NEFT
  formats. Without these, the user's SBI-only data biases the spam model
  to mislabel HDFC "Sent Rs. …" as spam.
- `NON_TRANSACTIONAL_BANKING` — OTPs, balance enquiries, bill reminders,
  card statements, declined / failed transactions. These are HAM for the
  spam filter but NEGATIVES for the transactional classifier, so they
  survive layer 1 and get dropped at layer 2 (where they belong).

---

## Project layout

```
lib/
├── main.dart                                  # entrypoint
├── app.dart                                   # navigation shell
├── config/theme.dart                          # Material 3 theme
├── models/transaction_record.dart
├── database/
│   ├── local_database.dart                    # SQLite (authoritative)
│   └── remote_database.dart                   # Postgres / Neon (sync target)
├── services/
│   ├── upi_parser.dart                        # regex parsing engine
│   ├── dedup_service.dart                     # hash-based dedup
│   ├── notification_service.dart              # NotificationListenerService bridge
│   ├── sms_service.dart                       # SMS receiver + history scan
│   ├── sync_service.dart                      # push-only sync to Postgres
│   ├── location_service.dart
│   └── ml/
│       ├── tfidf_logreg.dart                  # shared inference engine
│       ├── classifiers.dart                   # 3 classifier wrappers
│       └── message_pipeline.dart              # stacked orchestrator
├── providers/transaction_provider.dart        # ChangeNotifier, reads from pipeline
├── screens/                                   # dashboard / tx list / detail / analytics / settings
└── widgets/                                   # reusable UI components

assets/
├── spam_model.json                            # layer 1 weights
├── transactional_model.json                   # layer 2 weights
└── direction_model.json                       # layer 3 weights

scripts/
├── ml_core.py                                 # shared preprocessing + trainer
├── train_all_models.py                        # trains all 3 models
├── generate_ml_fixtures.py                    # Dart parity fixtures
└── seed_db.dart                               # Postgres seeder

data/                                          # gitignored — see data/README.md
├── .gitkeep                                   # tracked placeholder
└── README.md                                  # dataset schema & Drive link

test/
├── services/ml/                               # engine + 3 classifier suites + pipeline
├── integration/message_pipeline_integration_test.dart
├── accuracy/                                  # corpus sweep + consistency audit
└── fixtures/                                  # Python-generated parity fixtures
```

---

## Setup

### Prerequisites
- Flutter SDK 3.11+
- Android device (notification listener is Android-only)
- Python 3.10+ if you want to retrain the ML models

### Environment variables

Create `.env` in the project root:

```env
DATABASE_URL=postgresql://user:pass@host:5432/dbname?sslmode=require
SYNC_ENABLED=true
SYNC_INTERVAL_MINUTES=15
```

### Install & run

```bash
flutter pub get
flutter run
```

### Seed the remote database

```bash
dart run scripts/seed_db.dart
```

### Retrain the ML stack

Download the datasets first (see [Datasets](#datasets)) and place
the CSVs under `data/`. Then:

```bash
python3 -m pip install scikit-learn pandas numpy
python3 scripts/train_all_models.py            # writes assets/*_model.json
python3 scripts/generate_ml_fixtures.py        # writes test/fixtures/*.json
flutter test                                   # verify parity + accuracy
```

The shipped `assets/*_model.json` blobs are kept committed so the app
ships out-of-the-box even without the datasets.

---

## Permissions

| Permission                          | Required | Purpose                                         |
|-------------------------------------|:--------:|-------------------------------------------------|
| Notification Access                 |    ✓     | Read UPI app payment notifications.             |
| `READ_SMS` / `RECEIVE_SMS`          |    ✓     | Read bank / UPI SMS in real time.               |
| Location (coarse + fine)            |   opt    | Tag transactions with where you paid.           |
| Internet                            |   opt    | Sync to Postgres.                               |

---

## Testing

The test suite is big and deliberately strict — **255 tests** total,
organised into four layers:

**Unit tests** — individual components in isolation.
- `test/services/ml/tfidf_logreg_test.dart` — preprocessing correctness,
  hand-computed inference math, empty / OOV / fail-open paths.
- `test/services/ml/spam_filter_test.dart` — Python↔Dart parity < 1e-4,
  threshold behaviour, full batch of real bank SMS must survive layer 1.
- `test/services/ml/transactional_classifier_test.dart` — OTPs / balance
  alerts / failed tx are dropped; real completed transactions survive.
- `test/services/ml/direction_classifier_test.dart` — confident debits /
  credits map to the right enum, abstention honoured on wide bands.
- `test/services/ml/message_pipeline_test.dart` — stage short-circuiting,
  direction-hint wiring, disagreement detection.

**Integration tests** — components wired together.
- `test/integration/message_pipeline_integration_test.dart` — end-to-end:
  `isUpiRelated → MessagePipeline.evaluate → UpiParser.parseSms`.

**Accuracy tests** — whole-corpus guarantees against training regressions.
- `test/accuracy/corpus_accuracy_test.dart` — every row of
  `data/upi*.csv` must pass the pipeline with the correct direction.
- `test/accuracy/model_consistency_test.dart` — max `P(spam)` on real UPI
  SMS stays well below 0.85, min `P(transactional)` stays above 0.5,
  non-transactional curated samples stay below 0.5.

Both accuracy suites **gracefully skip** with `markTestSkipped` when the
gitignored CSVs aren't present, so CI and fresh clones stay green.

**Parity fixtures** are regenerated from the Python trainer so any drift
between the two preprocessing / inference paths is caught immediately.

```bash
flutter test                          # full suite (255 tests)
flutter test test/accuracy            # just the corpus sweeps
flutter test test/services/ml         # just the ML unit tests
```

---

## Deduplication & offline-first flow

1. Capture (notification, SMS, or manual entry).
2. Cheap keyword prefilter (`isUpiRelated`).
3. Stacked ML gate (spam → transactional → direction).
4. Parse → `UpiParser` → structured record.
5. Dedup: UPI / bank ref → exact match, otherwise `hash(amount, counterparty, 10-min window)`.
6. Insert into SQLite with `synced = false`.
7. When online, push unsynced rows to Postgres, then mark `synced = true`.
8. "Sync now" also cross-checks remote row count against local to detect
   out-of-band remote deletions and force a re-push.
