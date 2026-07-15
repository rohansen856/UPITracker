# Testing

~255 tests under [test/](../test/), organized in four layers. Run with:

```bash
flutter test                    # full suite
flutter test test/accuracy      # corpus sweeps only
flutter test test/services/ml   # ML unit tests only
```

Database-backed suites run against in-memory SQLite via `sqflite_common_ffi` — no
device needed.

## Layer 1: unit tests

### ML (`test/services/ml/`)

- `tfidf_logreg_test.dart` — the engine in isolation with hand-crafted tiny models:
  preprocessing correctness (`<url>`/`<amt>`/`<num>`/`<d>` substitutions), load
  validation (`StateError` on vocab/idf/weights length mismatch), fail-open paths
  (unloaded → 0.0, empty vocab → 0, all-OOV → sigmoid(bias)), hand-computed inference
  math.
- `spam_filter_test.dart` — real shipped model + fixtures: **Python↔Dart parity
  < 1e-4** on all 13 cases; the original "Rs 3,000 bonus / cutt.ly" scam scores > 0.9;
  a batch of 11 real bank/app SMS all stay below the 0.85 threshold; `setUpAll` fails
  with a retrain hint if models/fixtures are missing.
- `transactional_classifier_test.dart` — parity on 15 cases; OTPs / balance alerts /
  bill reminders / failed transactions rejected; real completed transactions pass;
  documents the unloaded-→-true fail-open contract.
- `direction_classifier_test.dart` — parity on 12 cases; confident debits/credits map
  to the right `TxDirection`; `confidence: 0.99` on gibberish abstains (`null`).
- `message_pipeline_test.dart` — stage short-circuiting (scam drops at `'spam'`; OTPs
  drop at `'transactional'`, not spam), direction-hint wiring (SBI debit → p_credit
  < 0.35, credit → > 0.65), `disagreesWithParser` null-safety; PhonePe wallet /
  gift-card payments and IT-refund credits pass the full stack while mandate
  creation, KYC updates, coupon promos, fee offers and recharge confirmations drop.

### Non-ML services (`test/services/`)

- `upi_parser_test.dart` (~70 tests) — the most thorough suite: app identification
  from 10 packages and all sender ids, real SBI debit/credit full-field extraction,
  GPay/PhonePe notifications, all type keywords, amount formats (₹ / Rs. / bare /
  Indian commas `1,50,000.00` / INR; zero → invalid), reference and account-mask
  variants, UPI-id suffix filtering (rejects `@gmail.com`), counterparty extraction
  (incl. PhonePe wallet/gift-card names with dots), balance-after and embedded-date
  extraction (12-hour AM/PM conversion, all date formats), IT-refund credits,
  `isUpiRelated` coverage, 200-char description truncation.
  (`test/upi_parser_test.dart` at the test root is an older, fully-overlapping subset.)
- `dedup_service_test.dart` (~20 tests, against real in-memory SQLite) — the stored
  hash chain (`txn:` → `ref:` → normalized body), and every fuzzy-tier scenario:
  consecutive identical wallet payments with different balances stay distinct,
  identical bodies from other sender ids dedup, second-precision embedded timestamps
  discriminate, cross-format IT-refund duplicates collapse, the ±10-minute sliding
  window catches pairs straddling bucket boundaries, differing refs never dedup,
  incoming SMS dedup against matching manual entries.
- `location_service_test.dart` / `sync_service_test.dart` — trivial value-object tests
  (`LocationData`, `SyncResult`).

### Database, models, provider

- `test/database/local_database_test.dart` (~25 tests) — a `TestableLocalDatabase`
  mirroring the exact schema + indexes: conflict-ignore inserts, all
  `getAllTransactions` filter combinations, summary/spending-by-app/daily-totals SQL,
  `markSynced`/`markAllUnsynced`, first/last id.
- `test/models/transaction_record_test.dart` (~25 tests) — enum defaults, map
  roundtrips, `copyWith` immutability, `tagList`, `formattedAmount`, all 11
  `upiAppDisplayName` mappings.
- `test/providers/transaction_provider_logic_test.dart` — the `_effectiveFromDate`
  rule (later of filter-from and start date wins), filter combinations, analytics date
  clamping, daily-totals grouping. (The provider itself touches native channels, so
  only its query logic is tested, against real SQLite.)

## Layer 2: integration (`test/integration/`)

- `message_pipeline_integration_test.dart` — mirrors the provider's exact gate:
  `isUpiRelated → MessagePipeline.evaluate → parseSms → isValid`. Proves in-test that
  the original bug message would pass keyword filter + parser alone but is dropped at
  the spam stage; real SBI/HDFC/ICICI/Axis/Kotak/GPay/PhonePe/Paytm formats ingest end
  to end.
- `transaction_pipeline_test.dart` — parse → dedup → insert → query against in-memory
  SQLite: dedup of the same SMS from two sender ids (JD-/VA-), four consecutive
  identical PhonePe wallet payments all kept (Rs 4,000 total), gift-card payment
  end-to-end, IT refund in two formats inserted once, OTP/no-amount rejection,
  start-date filtering, summary ranges, batch ordering.

## Layer 3: accuracy (`test/accuracy/`) — corpus guarantees

Both suites **gracefully skip** via `markTestSkipped` when the gitignored
`data/upi*.csv` files are absent, so CI and fresh clones stay green.

- `corpus_accuracy_test.dart` — sweeps every real UPI SMS (382 rows, rightmost-comma
  parsing like `ml_core.py`) through the full pipeline. Hard guarantees: **zero drops
  at any stage (100% ingested)** and confident-direction accuracy > 0.90 with zero
  direction mismatches (abstentions allowed).
- `model_consistency_test.dart` — drift audit: every real UPI SMS must score below the
  spam threshold **and** above the transactional threshold (zero violations); 20
  curated non-transactional samples (OTPs, alerts, mandates, KYC, surveys, fee offers,
  recharge confirmations) must all score below the transactional threshold.
  Catches "fix" attempts that quietly lower thresholds.

## Layer 4: widget tests (`test/widgets/`)

- `transaction_card_test.dart` (12 tests) — name/"Unknown" fallback, `-₹`/`+₹` signs,
  app badge, note visibility, `cloud_off` tied to `synced`, tap callback, direction
  arrows.
- `summary_card_test.dart` (3 tests) — covers the currently unused `SummaryCard`.
- `widget_test.dart` — placeholder ("real tests live in subdirectories").

## Parity fixtures (`test/fixtures/`)

`spam_fixtures.json` (13 cases), `transactional_fixtures.json` (15),
`direction_fixtures.json` (12) — each case is `{text, label, probability}` where
`probability` is Python's output, regenerated by `scripts/generate_ml_fixtures.py`.
Any drift between the Python and Dart preprocessing/inference paths fails the 1e-4
parity assertions immediately.
