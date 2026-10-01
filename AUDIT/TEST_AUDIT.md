# Test Audit

## Baseline

- `flutter test` at the start of the audit: **286 passed, 0 failed**. The accuracy
  suites ran because `data/*.csv` exist locally; they skip on a fresh clone.
- `flutter analyze`: 6 infos, no warnings or errors.
- No CI configuration exists (T4).

## What the suite covered well

- `UpiParser`, with about 85 tests across two files. It is the most thorough suite.
- The `TfidfLogReg` maths on hand-built models.
- Dedup tiers, run against real in-memory SQLite.
- Model behaviour on curated examples, using the real model JSON.

## How the suite passed while the app was broken

| Gap | Consequence | Status |
|-----|-------------|--------|
| No test called `TfidfLogReg.load()` or `rootBundle` (T1) | Asset-declaration and load regressions were invisible | **Fixed:** `test/services/ml/model_asset_loading_test.dart`; proven to fail when an asset entry is removed from `pubspec.yaml` |
| Parity fixtures came from `score_manual`, a Python copy of the Dart code (T2) | Drift shared by both sides would pass | **Fixed:** fixtures now come from sklearn's own transform; the generator aborts if the mirror drifts by more than 1e-6. The new fixtures differ from the old by at most 2.2e-16 |
| Ingestion orchestration untested (T5) | C1 (capture never started), C7 (sent SMS ingested) and C8 (dead stream) were invisible | Open |
| Database tests target a copied class (T3) | Production SQL changes go untested | Open |
| Accuracy guarantees only measured on the training corpus | "100% ingested" did not hold on an independent real inbox (C2) | Rule fixed; corpus diversity still open (M1) |
| `tfidf_logreg_test.dart` asserts silent fail-open as intended behaviour | Load failure looked like normal operation | Behaviour kept (fail-open is reasonable), now surfaced in the UI (C5) |
| No Kotlin or instrumentation tests | S3, S4 and C18 were invisible | Open |

## Tests added in this audit (13)

| File | Tests | Proves |
|------|-------|--------|
| `test/services/ml/model_asset_loading_test.dart` | 3 | Real `rootBundle` load; a missing asset stays unloaded; a corrupt model is rejected |
| `test/services/ml/message_pipeline_test.dart` (group added) | 5 | Settlement-evidence rule: bypasses for registered headers, not for raw numbers; notifications; RRN without a verb; short refs |
| `test/services/upi_parser_test.dart` (group added) | 3 | Direction precedence (2 of the 3 fail on the old parser) |
| `test/models/debt_entry_test.dart` | 2 | `settledAt` keep vs clear |

Final run: **299 passed** without the temporary harness (300 with it).

## On-device validation performed

| Check | Result |
|-------|--------|
| Model assets present in the APK | Yes (refutes the "models not bundled" hypothesis) |
| `.env` present in the APK | Yes (S1) |
| Model load time on a cold start | 161 ms, all three loaded (C4 latent) |
| Live Monitoring state after launch | OFF; dashboard showed ₹0 for a day with real debits (C1) |
| App database contents | 118 rows from a single scan; 0 from notifications; all synced (C1, S2) |
| Two app packages installed | Yes (O1) |
| Real-inbox sweep, before and after the fixes | 12 real transactions recovered with 0 new drops (C2); 26 sign corrections (C3) |
| `ALLOW_BACKUP` flag | Present on the old build, absent after the fix (S6) |
| Fixed build installed on the device | Yes (background install, data kept) |
| End-to-end on the device after the fix (auto-start, catch-up, live SMS, widget, revoking READ_SMS) | **Not run.** The phone was in active use; injecting taps or foregrounding the app would have disrupted the owner |

## Recommended next tests

1. Extract ingestion into a service with injectable channels and test C1, C7 and C8
   directly.
2. Test `LocalDatabase` itself through an injected FFI factory.
3. Build a synthetic real-world-format corpus (no personal data), checked into the repo
   and run in CI, so the accuracy guarantees hold on fresh clones.
4. Add an instrumentation test asserting the capture broadcasts are package-scoped.
