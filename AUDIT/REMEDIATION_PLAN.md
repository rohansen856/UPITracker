# Remediation Plan

Items already fixed during the audit are marked **done**, with each fix kept in its own
commit. "Owner" marks decisions or actions that cannot be taken from inside the
repository.

## Phase 0 — Immediate security and production risks

| Finding | Problem | Change | Files | Fix risk | Depends on | Validation |
|---------|---------|--------|-------|----------|------------|------------|
| S1 | Database credential is public | **Owner:** rotate the Neon role password now. Delete `refs/heads/entire/checkpoints/v1` on origin (or rewrite it), and ask GitHub to purge cached views. Stop pushing `.entire` branches | remote only | Low: the app keeps working once the new `.env` is used | — | Old credential rejected; `git ls-remote` no longer lists the branch |
| S13 | Entire hooks push session transcripts | **Owner:** run `entire` uninstall or disable its pre-push behaviour, and delete the local `entire/*` branches **before the next `git push`** | `.git/hooks/*` (untracked) | None | — | `git ls-remote` shows no new `entire/*` refs after a push |
| S2 / S8 / S9 | Clients write straight into a shared database | Short term: set `SYNC_ENABLED=false` and remove `.env` from `pubspec.yaml` assets (the app now tolerates a missing `.env`, C13). Long term: an authenticated API with per-user rows | `pubspec.yaml`, `.env`; new service | Medium: sync stops until the API exists | S1 | APK no longer contains `assets/flutter_assets/.env` |
| S11 | Real SMS on public `main` | Replace fixtures, tests and doc examples with synthetic messages in the same formats. **Owner:** history rewrite or making the repository private | `test/**`, `scripts/generate_ml_fixtures.py`, `docs/features/upi-parser.md`, parser comments | Medium: large test edit; formats must be preserved exactly | — | `git grep` for the account-suffix and name patterns returns nothing |
| O1 | Stale build still capturing | **Owner:** `adb uninstall com.example.receipt` | device | None | — | `pm list packages` |
| S3, S4, S6, S7 | Inter-app leak, logs, backup, public storage | **Done** | Kotlin, manifest, debt backup | Low | — | Tests and on-device flags |
| S5 | Debug-key release signing | **Owner:** create a keystore and configure `signingConfigs.release` from local properties | `android/app/build.gradle.kts` | Low | Keystore | `apksigner verify --print-certs` |

## Phase 1 — High-impact correctness

| Finding | Change | Files | Status |
|---------|--------|-------|--------|
| C1 | Persisted capture, auto-start, SMS catch-up, stream errors | `transaction_provider.dart`, `settings_screen.dart` | **Done** |
| C1 (remainder) | Persist notification events natively while Flutter is not running (SharedPreferences/file queue drained on launch), or run a foreground service | `UpiNotificationListener.kt`, `MainActivity.kt` | Open. Medium risk: lifecycle and battery behaviour |
| C2 | Settlement-evidence rule | `message_pipeline.dart` | **Done** |
| C3 | Direction precedence | `upi_parser.dart` | **Done** |
| C4, C5 | Await model load; surface load state | provider, pipeline | **Done** |
| C21 | Fix wrong package ids, add installed payment apps, remove or gate WhatsApp | `UpiNotificationListener.kt` | Open. Verify ids against the Play Store |
| C15 | Require a discriminator before fuzzy-merging | `dedup_service.dart` | Open |
| C14 | Store UTC (epoch ms) locally; add a migration | models, DB | Open. Needs a schema migration |
| C17, C16 | Reset the connection on error; page-wise integrity check | sync | Open |
| C19 | Typed permission error from `readSmsHistory` | Kotlin, `sms_service.dart` | Open |

## Phase 2 — Architecture and maintainability

- A1: extract an `IngestionService` (capture → gate → parse → dedup → store) with injectable
  channels and database; this also unlocks T5.
- S2: an API tier (see Phase 0).
- C20: show `updatedAt` on the widget and blank figures older than 24 h.
- P1/P5: paginate the transaction list; batch and page sync uploads.
- P2: run the SMS query off the main thread. P4: insert first, attach location later.
- A2: move the Kotlin sources to `com/upitracker/app`.

## Phase 3 — Documentation and testing

- **Done:** T1 (rootBundle load tests), T2 (sklearn-referenced fixtures), docs corrections
  DOC1–DOC6 and DOC8–DOC10.
- DOC7: regenerate metrics from a pinned training run (**owner decision** on which numbers
  are authoritative).
- T3: test `LocalDatabase` directly. T4: add CI (`flutter analyze`, `flutter test`).
  T5: provider/ingestion tests. Add a synthetic real-world-format corpus to the repo.
- D1: `scripts/requirements.txt` with pinned scikit-learn/numpy.

## Phase 4 — Lower-priority debt

S10, S12, O2, C22, C23, A3, T6, D2 (upgrade `postgres` first), M1 (retrain with in-domain
data), M2 (evaluate on notification samples), analyzer infos, `dart format` baseline as a
standalone commit.
