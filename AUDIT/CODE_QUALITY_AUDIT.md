# Code Quality Audit

Separated as the brief requires: (A) actual defects, (B) maintainability concerns,
(C) stylistic preferences. Defects are listed by ID only; detail is in
[FINDINGS.md](FINDINGS.md).

## A. Actual defects

C1–C23, M1–M2, S3–S12 (see FINDINGS). The ones rooted in code quality rather than design:

- **Order-dependent keyword matching** in `UpiParser._detectType` (C3) — substring checks
  in a fixed list order decide direction; fixed by giving the account settlement verbs
  precedence.
- **Silent `catch (_)` used as control flow** — `SmsService.readSmsHistory`,
  `NotificationService.isNotificationAccessGranted`, `TfidfLogReg.load`,
  `SyncService._verifyRemoteIntegrity`, `DebtBackupService.readBackup`,
  `_refreshWidget`'s `.catchError((_) => null)`. Each turns a distinguishable failure into
  a normal-looking empty result (C5, C16, C19, S7). Two of them are fixed.
- **`copyWith` with `?? this.x`** cannot express "set to null" (C10, C23).
- **Fire-and-forget initialisation** (`unawaited(load())`) next to code that assumes the
  result (C4).

## B. Maintainability concerns

- `TransactionProvider` (~550 lines) owns nine responsibilities (A1); duplicated
  `TransactionRecord` construction in two ingestion paths.
- Success messages stored in `_error` (A3).
- `TestableLocalDatabase` duplicates production SQL in the test tree (T3).
- Two parser test files with overlapping content (T6).
- Hand-rolled `postgresql://` URL parsing repeated five times in `remote_database.dart`
  (each helper re-parses the URL).
- Magic numbers without names: direction confidence `0.65` in `MessagePipeline`, `500`
  history limit, `±10 min` dedup window.
- Training script mixes data loading, augmentation lists, training and export in one
  file; synthetic sample counts drifted from the docs (DOC8).
- Kotlin sources under a directory that does not match their package (A2).

## C. Stylistic (no engineering cost; not acted on)

- Repository is not `dart format`-clean at HEAD (formatting the provider alone changes
  111 lines). The audit fixes were deliberately applied without reformatting, so diffs
  stay reviewable.
- Six analyzer infos (unnecessary imports in tests, braces in interpolation, one
  `use_build_context_synchronously` in `settings_screen.dart:137`).

## Positive observations

Comments explain *why* in most non-trivial places (widget snapshot rationale, dedup tiers,
preprocessing parity). The ML engine is small, pure and well covered. The parser test
suite is extensive. Parameterised SQL is used consistently.
