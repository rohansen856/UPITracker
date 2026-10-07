# ML training

The Python side of the ML stack lives in [scripts/](../scripts/). It trains the three
model JSON blobs shipped under `assets/` and generates the parity fixtures the Dart
tests assert against. Runtime inference is documented in
[features/ml-pipeline.md](features/ml-pipeline.md).

## Retrain workflow

```bash
python3 -m pip install scikit-learn pandas numpy
python3 scripts/train_all_models.py        # writes assets/*_model.json
python3 scripts/generate_ml_fixtures.py    # writes test/fixtures/*_fixtures.json
flutter test                               # verify Dart↔Python parity + accuracy
```

The shipped `assets/*_model.json` blobs are committed, so the app works out-of-the-box
without the datasets.

## `ml_core.py` — shared preprocessing, loaders, trainer

- `preprocess(text)` — lowercase → URLs→`<url>` → currency amounts→`<amt>` →
  4+ digit runs→`<num>` → remaining digits→`<d>` → strip non-word chars. **Must stay
  byte-identical** to `TfidfLogReg.preprocess` in
  [lib/services/ml/tfidf_logreg.dart](../lib/services/ml/tfidf_logreg.dart); the
  fixture tests enforce this.
- `load_spam_corpus()` — merges `data/spam.csv` (Kaggle, latin-1) and
  `data/spam_ham_india.csv`, normalized to 0=ham / 1=spam.
- `load_upi_corpus()` — parses `data/upi*.csv` by splitting each row on the
  **rightmost comma** (message bodies contain unquoted commas, so new rows can be
  curated without escaping); derives direction from "debited"/"credited" keywords.
- Curated augmentation lists (version-controlled in code since the real data isn't):
  - `SYNTHETIC_DEBITS` (28) / `SYNTHETIC_CREDITS` (20) — HDFC, ICICI, Axis, Kotak,
    PNB, BoB, Canara, IOB, Federal, GPay, PhonePe, Paytm, BHIM, Amazon Pay, NEFT
    formats, **PhonePe wallet / gift-card confirmations** ("Not you? Call us …
    To top-up click <url>" — earlier models mistook these for spam and dropped real
    payments) and **IT-refund credits** (both SBI wordings). Without these, the
    user's SBI-only data biases the spam model to mislabel them.
  - `NON_TRANSACTIONAL_BANKING` (~34) — OTPs, balance enquiries, bill reminders, card
    statements, declined/failed transactions, **UPI-mandate creation** (money hasn't
    moved yet — the actual debit arrives as a separate SMS), **KYC updates, branch
    feedback surveys, merchant-device fee offers, telecom recharge confirmations**.
    HAM for the spam filter but NEGATIVES for the transactional classifier (they
    survive layer 1 and die at layer 2, where they belong).
- `train_tfidf_logreg(...)` → `TrainedModel` (vocab, idf, weights, bias, threshold).
  `TfidfVectorizer`: 1–2 grams, `min_df=2`, `max_features=3000`, sublinear TF, L2
  norm, token pattern `\S+`. `LogisticRegression`: `C=4.0`, class-balanced,
  liblinear. Prints precision/recall at thresholds 0.3–0.9.
- `export_model(...)` — compact JSON (vocab/idf/weights/bias/threshold + preprocessing
  metadata) matching the format the Dart loader expects.
- `score_manual(payload, text)` — pure-Python inference mirroring the Dart path; used
  by the fixture generator.

## `train_all_models.py` — trainer CLI

Trains and exports all three models:

| Model | Output | Threshold | Training mix |
|---|---|---|---|
| Spam filter | `assets/spam_model.json` | **0.85** (precision-biased) | Public spam corpora + real UPI ham ×3 + synthetic bank ham ×5 + non-transactional banking ham ×7 + `CURATED_SPAM` (18 scam/promo messages that mimic payment wording, incl. "You've earned …" coupon promos) ×2 |
| Transactional | `assets/transactional_model.json` | 0.5 | Positives: real + synthetic transactions. Negatives: non-transactional banking ×5, 800 conversational ham, 400 promo/spam |
| Direction | `assets/direction_model.json` | 0.5 (`max_features=1500`; 731 survive `min_df`) | Label 1=credit, 0=debit; credits oversampled to balance |

## `generate_ml_fixtures.py` — parity fixtures

Scores hardcoded case lists (`SPAM_CASES` 17, `TRANSACTIONAL_CASES` 24,
`DIRECTION_CASES` 16) through `score_sklearn` (sklearn's own TF-IDF transform rebuilt
from the exported vocab/idf) and cross-checks each against `score_manual` (aborting on
drift > 1e-6), then writes
`test/fixtures/{spam,transactional,direction}_fixtures.json` as
`{"cases": [{text, label, probability}, …]}`. The Dart suites assert
`|dart_prob − sklearn_prob| < 1e-4` on every case. Requires `scikit-learn` and `numpy`
(audited with 1.9.0 / 2.5.1; versions are not pinned in the repo). The script also prints any cases the
model misclassifies at its own threshold.

## `seed_db.dart` — remote DB bootstrap

```bash
dart run scripts/seed_db.dart
```

Reads `DATABASE_URL` from the environment or by parsing `.env` directly, connects to
Postgres (SSL required), creates the `transactions` table if missing (same columns as
the app's remote schema) plus indexes `idx_remote_dedup`, `idx_remote_date`,
`idx_remote_type`, `idx_remote_app`, prints the row count, and exits.

## Datasets (`data/`)

Gitignored (real personal SMS); tracked only through `data/.gitkeep` and
[data/README.md](../data/README.md). Download the files from Google Drive into `data/`:
https://drive.google.com/drive/folders/19AV_DytumoGD7GLs9f--FxPwHfm7nSax

| File | Rows | Labels |
|---|---|---|
| `spam.csv` | 5,572 | ham/spam (Kaggle English SMS) |
| `spam_ham_india.csv` | 2,268 | ham/spam (India-specific) |
| `upi1.csv` / `upi2.csv` / `upi3.csv` | 134 / 115 / 133 | all ham (real UPI SMS, direction derived from text) |

To add data: append rows to a new `upi4.csv` as `<message>,ham`, or extend
`CURATED_SPAM` / `NON_TRANSACTIONAL_BANKING` in `ml_core.py`, then rerun the workflow.

## Shipped model metrics

Held-out metrics at default thresholds (from the top-level README):

| Model | Thr | P | R | F1 |
|---|---|---|---|---|
| Spam filter | 0.85 | 1.000 | 0.921 | 0.959 |
| Transactional | 0.50 | 1.000 | 1.000 | 1.000 |
| Direction | 0.50 | 0.980 | 1.000 | 0.990 |

Corpus-wide sweep on 382 real UPI SMS: **381/381 ingested (100%)**, 380/381
direction-confident, max P(spam) on real UPI SMS 0.132 (threshold 0.85), min
P(transactional) 0.615 (threshold 0.5) — comfortable retraining headroom on both sides.
