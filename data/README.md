# Training datasets

The ML stack in this repo (see `../README.md#ml-stack`) is trained on the
five CSVs below. They are **not checked in** — `data/.csv` is gitignored
because the `upi*.csv` files contain real UPI SMS with personal names and
account numbers.

## Get the bundle

Download the dataset files and put them **into this folder** (if you download
the whole Drive folder as a zip, extract it here):

- **Google Drive:** https://drive.google.com/drive/folders/19AV_DytumoGD7GLs9f--FxPwHfm7nSax

Afterwards, running `ls data/` should show:

```
README.md          <- this file, committed
.gitkeep           <- committed placeholder
spam.csv           <- 5 572 rows, Kaggle English SMS (spam/ham)
spam_ham_india.csv <- 2 268 rows, Indian SMS (spam/ham)
upi1.csv           <- real UPI SMS, batch 1 (ham)
upi2.csv           <- real UPI SMS, batch 2 (ham)
upi3.csv           <- real UPI SMS, batch 3 (ham)
```

## File contents

| File                  | Rows  | Columns      | Label convention        |
|-----------------------|-------|--------------|-------------------------|
| `spam.csv`            | 5 572 | `v1,v2,…`    | `ham` / `spam`          |
| `spam_ham_india.csv`  | 2 268 | `Msg,Label`  | `ham` / `spam`          |
| `upi1.csv`            |   134 | `Msg,Label`  | all `ham` (real UPI tx) |
| `upi2.csv`            |   115 | `Msg,Label`  | all `ham` (real UPI tx) |
| `upi3.csv`            |   133 | `Msg,Label`  | all `ham` (real UPI tx) |

The `upi*.csv` files can contain **unquoted commas inside the message
text** (they are hand-curated). The loader in `scripts/ml_core.py` splits
on the **rightmost** comma to cope with that — if you curate more data,
there's no need to re-quote anything.

## Retrain the ML stack

From the project root after placing the files here:

```bash
python3 -m pip install scikit-learn pandas numpy
python3 scripts/train_all_models.py        # writes assets/*_model.json
python3 scripts/generate_ml_fixtures.py    # updates test/fixtures/*.json
flutter test                               # verifies parity + accuracy
```

## Optional: run the corpus-wide accuracy check

If the `data/upi*.csv` files are present, `flutter test` also runs
`test/accuracy/corpus_accuracy_test.dart`, which passes **every** real UPI
SMS through the live stacked pipeline and asserts:

1. the message is ingested (not dropped at any stage),
2. the direction hint (debit/credit) matches the "debited"/"credited"
   keyword in the raw text.

If the files are absent, this test gracefully short-circuits with a
`skip` so CI / new contributors don't break.

## Adding your own data

- **Your own UPI SMS** → append rows to `upi{1,2,3}.csv` or a new
  `upi4.csv` with format `<message text>,ham`.
- **Fresh spam examples** → extend the `CURATED_SPAM` list in
  `scripts/train_all_models.py`.
- **New non-transactional edge cases** (OTPs, declines, bill reminders
  from your bank) → extend `NON_TRANSACTIONAL_BANKING` in
  `scripts/ml_core.py`.

Then rerun the retrain block above.
