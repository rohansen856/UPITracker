# Findings

All findings with full evidence. Generated from `FINDINGS.json`; locations refer to the pre-fix tree (HEAD `8475ac2` plus the staged working-tree changes). Personal data (account numbers, names, reference numbers, phone numbers, hosts, credentials) is redacted throughout.

| ID | Severity | Confidence | Status | Title |
|----|----------|------------|--------|-------|
| [C1](#c1) | CRITICAL | CONFIRMED | PARTIALLY FIXED | Live capture is never running: Live Monitoring is a non-persisted per-session switch, and nothing is captured or caught up while the app is closed |
| [S1](#s1) | CRITICAL | CONFIRMED | OPEN — requires owner action (rotation, history rewrite) | Production Postgres credential is public: bundled in every APK and committed to a public GitHub branch |
| [S2](#s2) | CRITICAL | CONFIRMED | OPEN — architectural decision | No server tier: the mobile client connects directly to Postgres; all installs write one shared, unpartitioned table |
| [C2](#c2) | HIGH | CONFIRMED | FIXED | Classifiers silently drop entire real-world bank SMS templates (incoming credits, UPI Lite top-ups) |
| [C3](#c3) | HIGH | CONFIRMED | FIXED | UPI Lite top-ups recorded as income (wrong sign) |
| [DOC3](#doc3) | HIGH | CONFIRMED | FIXED | Docs asserted capture broadcasts were 'internal' when they were system-wide |
| [DOC4](#doc4) | HIGH | CONFIRMED | FIXED | 'Reads notifications and SMS in real time' — capture was off after every launch |
| [O1](#o1) | HIGH | CONFIRMED | OPEN — owner action | A stale pre-rename build is still installed and capturing on the owner's device |
| [S11](#s11) | HIGH | CONFIRMED | OPEN — requires owner decision (history rewrite) | Real bank SMS (account suffix, PAN fragment, balances, reference numbers, third-party names) committed to the public repository |
| [S13](#s13) | HIGH | CONFIRMED | OPEN — owner action before next push | Entire CLI git hooks copy session transcripts into a branch and push them with every push |
| [S3](#s3) | HIGH | HIGH | FIXED | Captured SMS bodies and payment notifications were broadcast to every app on the device |
| [S4](#s4) | HIGH | CONFIRMED | FIXED | Full SMS and notification text written to logcat in all build types |
| [S5](#s5) | HIGH | CONFIRMED | OPEN — needs owner keystore | Release builds are signed with the debug keystore |
| [S6](#s6) | HIGH | CONFIRMED | FIXED | Android backup enabled for a database of raw SMS text and geotags |
| [S7](#s7) | HIGH | CONFIRMED | FIXED (behaviour change: no uninstall survival) | Debt ledger exported unencrypted to world-readable shared storage, requiring the Play-restricted MANAGE_EXTERNAL_STORAGE |
| [T1](#t1) | HIGH | CONFIRMED | FIXED | Production model-load path had no test coverage |
| [A1](#a1) | MEDIUM | CONFIRMED | OPEN | TransactionProvider is a god object with duplicated ingestion code |
| [C14](#c14) | MEDIUM | HIGH | OPEN | Local and remote disagree on transaction instants |
| [C15](#c15) | MEDIUM | HIGH | OPEN | Dedup can merge genuinely distinct payments |
| [C16](#c16) | MEDIUM | HIGH | OPEN | Sync integrity check has blind spots and swallows errors |
| [C17](#c17) | MEDIUM | HIGH | OPEN | Dead Postgres connection is cached forever; no timeout or retry |
| [C18](#c18) | MEDIUM | HIGH | OPEN | MainActivity leaks receivers and orphans them on re-subscribe |
| [C19](#c19) | MEDIUM | CONFIRMED | OPEN | SMS permission denial is reported as 'No new transactions found' |
| [C20](#c20) | MEDIUM | HIGH | OPEN | Home widget shows stale figures with no staleness signal |
| [C21](#c21) | MEDIUM | MEDIUM | OPEN | Notification allowlist misses installed payment apps and includes WhatsApp |
| [C5](#c5) | MEDIUM | CONFIRMED | FIXED | Classifier load failure is completely silent |
| [C6](#c6) | MEDIUM | CONFIRMED | PARTIALLY FIXED | SMS history scan only reaches the 500 most recent SMS of any sender |
| [C8](#c8) | MEDIUM | CONFIRMED | FIXED | EventChannel errors silently kill capture while the UI still reports 'listening' |
| [C9](#c9) | MEDIUM | CONFIRMED | FIXED | SYNC_INTERVAL_MINUTES of 0 or less spins Timer.periodic |
| [D1](#d1) | MEDIUM | CONFIRMED | OPEN | Python training environment is not reproducible |
| [DOC1](#doc1) | MEDIUM | CONFIRMED | FIXED | README claims sync is 'bidirectional-safe' |
| [DOC10](#doc10) | MEDIUM | CONFIRMED | FIXED | Debt backup feature and its storage/permissions were undocumented |
| [DOC5](#doc5) | MEDIUM | CONFIRMED | FIXED | '100% of real UPI SMS ingested' holds only on the training corpus |
| [DOC7](#doc7) | MEDIUM | CONFIRMED | OPEN — human decision | Held-out metrics conflict between README and docs/ml-training.md |
| [M1](#m1) | MEDIUM | CONFIRMED | OPEN — modelling decision | Spam model is trained mostly on an unrelated SMS-chat corpus |
| [O2](#o2) | MEDIUM | CONFIRMED | OPEN | No code shrinking/obfuscation and unpinned targetSdk |
| [P1](#p1) | MEDIUM | CONFIRMED | OPEN | Every refresh loads the entire filtered transaction table |
| [P2](#p2) | MEDIUM | HIGH | OPEN | SMS history is read on the platform main thread |
| [P4](#p4) | MEDIUM | HIGH | OPEN | Location lookup blocks live ingestion for up to 10 seconds |
| [P5](#p5) | MEDIUM | HIGH | OPEN | Sync uploads row by row with no batching or transaction; full re-push after integrity miss |
| [S8](#s8) | MEDIUM | CONFIRMED | OPEN | Precise per-purchase geolocation is synced to the shared, credential-exposed database |
| [S9](#s9) | MEDIUM | HIGH | OPEN | TLS to Postgres does not verify the server certificate; channel_binding is dropped |
| [T2](#t2) | MEDIUM | CONFIRMED | FIXED | Parity fixtures were circular (Dart vs a Python copy of Dart) |
| [T3](#t3) | MEDIUM | CONFIRMED | OPEN | Database tests exercise a hand-copied class, not LocalDatabase |
| [T4](#t4) | MEDIUM | CONFIRMED | OPEN | No CI; strictest accuracy suites only run where gitignored data exists |
| [T5](#t5) | MEDIUM | CONFIRMED | OPEN | Ingestion orchestration and Kotlin layer are untested |
| [A2](#a2) | LOW | CONFIRMED | OPEN | Kotlin sources live under com/example/receipt but declare package com.upitracker.app |
| [A3](#a3) | LOW | CONFIRMED | OPEN | Status/success messages are carried in the `error` field |
| [C10](#c10) | LOW | CONFIRMED | FIXED | Un-settling a debt leaves a stale settled_at |
| [C11](#c11) | LOW | CONFIRMED | FIXED | Widget 24h transaction count used the filtered list while amounts were unfiltered |
| [C12](#c12) | LOW | HIGH | FIXED | Percent-encoded credentials in DATABASE_URL were not decoded |
| [C13](#c13) | LOW | CONFIRMED | FIXED | Startup crashes if .env is absent |
| [C22](#c22) | LOW | CONFIRMED | OPEN | TransactionType/DebtDirection silently default unknown values |
| [C23](#c23) | LOW | CONFIRMED | OPEN | TransactionRecord.copyWith cannot clear nullable fields |
| [C24](#c24) | LOW | HIGH | FIXED | Labelled sparkline bars overflow the dashboard card |
| [C4](#c4) | LOW | CONFIRMED | FIXED | Model load was fire-and-forget (latent race with fail-open classifiers) |
| [C7](#c7) | LOW | CONFIRMED | FIXED | History scan also ingests sent/outbox SMS |
| [D2](#d2) | LOW | CONFIRMED | OPEN | Direct Dart dependencies behind latest, incl. the database driver |
| [DOC2](#doc2) | LOW | CONFIRMED | FIXED | README describes the dedup key wrongly |
| [DOC6](#doc6) | LOW | CONFIRMED | FIXED | Stale model sizes/feature counts |
| [DOC8](#doc8) | LOW | CONFIRMED | FIXED | Training-mix and test-count details are wrong |
| [DOC9](#doc9) | LOW | CONFIRMED | FIXED | Unverifiable performance claim |
| [M2](#m2) | LOW | MEDIUM | OPEN | Notification text is scored by SMS-trained models |
| [P3](#p3) | LOW | HIGH | OPEN | Fuzzy dedup re-parses every candidate's raw text per incoming message |
| [S10](#s10) | LOW | CONFIRMED | OPEN | Widget provider exported without a permission |
| [S12](#s12) | LOW | CONFIRMED | OPEN | Unused privileged permissions declared |
| [T6](#t6) | LOW | CONFIRMED | OPEN | Duplicate parser test file |
| [M3](#m3) | INFO | CONFIRMED | ACCEPTED | Empty input scores 0.0 where sklearn gives sigmoid(bias) |
| [M4](#m4) | INFO | CONFIRMED | VERIFIED | Dart inference is numerically identical to sklearn (negative finding) |

## C1

**Live capture is never running: Live Monitoring is a non-persisted per-session switch, and nothing is captured or caught up while the app is closed**

- **Category:** correctness  ·  **Severity:** CRITICAL  ·  **Confidence:** CONFIRMED  ·  **Status:** PARTIALLY FIXED
- **Component:** TransactionProvider / native capture
- **Locations:** `lib/providers/transaction_provider.dart:49,108-116,138-153`; `lib/screens/settings_screen.dart:143-159`; `android/app/src/main/kotlin/com/example/receipt/MainActivity.kt:63-117`

**Evidence**

- startListening() is only called from the Settings switch; _isListening defaults to false and is not persisted
- Native receivers forward to Dart only while MainActivity's dynamic receivers are registered; no queue
- Device: app database holds 118 rows, all source=sms, all created in a single manual history scan; latest transaction ~2.5 months old; zero notification-sourced rows ever
- Device: after launch the dashboard shows ₹0 / 0 transactions for the last 24h while the inbox has bank debits from the same day; Settings shows Live Monitoring OFF directly under 'Notification Access: Granted — listening to UPI app notifications'

**Why it matters:** The core feature — automatic capture — does not work in normal use; this is the primary cause of the reported 'broken' behaviour.

**Actual behavior:** Capture only while the user has manually flipped the switch in the current process; everything else lost.

**Expected behavior:** Capture enabled by default and resumed after restarts; missed SMS recovered.

**Validation:** Device database inspection, UI dump, code trace.

**Recommended fix:** APPLIED: persisted Live Monitoring preference (default on), auto-start on launch after models load, silent SMS catch-up from a persisted timestamp watermark, onError handling, truthful settings copy. REMAINING: notifications that arrive while the app is not running are still lost (needs a native persistent queue or a foreground service).

**Documentation impact:** docs/features/transaction-capture.md and README 'real time' claim updated.

## S1

**Production Postgres credential is public: bundled in every APK and committed to a public GitHub branch**

- **Category:** security  ·  **Severity:** CRITICAL  ·  **Confidence:** CONFIRMED  ·  **Status:** OPEN — requires owner action (rotation, history rewrite)
- **Component:** build config / git history
- **Locations:** `pubspec.yaml:40 (.env declared as a Flutter asset)`; `lib/main.dart:13`; `lib/database/remote_database.dart:16`; `commits 15627bb, e4abb6f (files a2/dbdc585fbd/0/full.jsonl, 4d/fbcc6b6e68/0/full.jsonl) on refs/heads/entire/checkpoints/v1`

**Evidence**

- `unzip -l build/app/outputs/flutter-apk/app-debug.apk` lists assets/flutter_assets/.env (206 bytes) — reproduced this session
- `git merge-base --is-ancestor <c> origin/entire/checkpoints/v1` true for both commits; `git ls-remote origin` shows the branch live
- `gh repo view` reports the repository visibility as PUBLIC
- `git grep` on those commits finds the database host and owner role name inside agent-transcript JSONL

**Why it matters:** Anyone who downloads the APK or browses the public branch obtains owner-level read/write access to the shared production database containing every user's transactions, raw SMS text and geolocation.

**Actual behavior:** DATABASE_URL (with password) ships in plaintext inside the APK and is readable on GitHub.

**Expected behavior:** No database credential reaches the client or version control.

**Validation:** Static + artifact inspection + git/GitHub queries. Secret value deliberately not reproduced in this report.

**Recommended fix:** 1) Rotate the Neon password/role immediately. 2) Delete or rewrite refs/heads/entire/checkpoints/v1 on origin (requires force-push; owner decision) and purge caches. 3) Stop shipping .env as an asset; move sync behind an authenticated API (see S2). 4) Stop committing agent transcripts (.entire) to pushed branches.

**Documentation impact:** docs/setup.md acknowledges credentials ship in the APK but presents it as a note, not a vulnerability; must be reworded once fixed.

## S2

**No server tier: the mobile client connects directly to Postgres; all installs write one shared, unpartitioned table**

- **Category:** security  ·  **Severity:** CRITICAL  ·  **Confidence:** CONFIRMED  ·  **Status:** OPEN — architectural decision
- **Component:** lib/database/remote_database.dart
- **Locations:** `lib/database/remote_database.dart:13-40 (direct Connection.open)`; `lib/database/remote_database.dart:68-102 (schema: no user/device column)`

**Evidence**

- Remote `transactions` DDL has no user_id/device_id column; upsert keyed only on record UUID
- On-device DB pulled via `run-as`: all 118 local rows have synced=1 — the owner's real transactions are in the shared database

**Why it matters:** Any install can read, modify or delete every other install's financial records; credential cannot be revoked per device.

**Actual behavior:** Shared DB credential embedded in client; no authentication or authorization layer.

**Expected behavior:** Per-user authenticated API with server-side authorization; database never reachable from clients.

**Validation:** Static review + device database inspection.

**Recommended fix:** Introduce an API (e.g. serverless function) with per-user auth and row ownership; until then disable sync (SYNC_ENABLED=false) and remove .env from assets.

**Documentation impact:** docs/architecture.md and docs/features/sync.md should state the trust model explicitly.

## C2

**Classifiers silently drop entire real-world bank SMS templates (incoming credits, UPI Lite top-ups)**

- **Category:** correctness  ·  **Severity:** HIGH  ·  **Confidence:** CONFIRMED  ·  **Status:** FIXED
- **Component:** ML pipeline
- **Locations:** `lib/services/ml/message_pipeline.dart:80-105`; `assets/transactional_model.json`; `assets/spam_model.json`

**Evidence**

- Sweep of the owner's 3,901-message inbox through the shipped models (corpus kept outside the repo): 1,781 UPI-related, 287 dropped at spam, 206 at transactional
- Ground truth via DLT service headers + RRN: 12 real transactions dropped (₹14,146.07): every 'Your A/c *XXXX is credited with Rs.Y … RRN …' credit (7/7, p_tx 0.42–0.44) and every 'debited and Rs.Y added to your UPI Lite on npci App. RRN…' top-up (5/5, p_spam = 0.85 exactly at threshold)
- Docs/README claim '100% ingested' — true only on the 382-message training corpus
- Recall on bank/UPI service-header transactions was 98.8% overall, so the failure is template-specific, not global

**Why it matters:** Incoming money in the affected formats never appears in the ledger.

**Actual behavior:** Model veto overrides hard settlement evidence.

**Expected behavior:** Messages proving a settled payment are never dropped by a probabilistic gate.

**Validation:** Real-inbox sweep before/after (harness outside the repo).

**Recommended fix:** APPLIED: settlement-evidence rule — 12-digit RRN/UTR/UPI Ref + settlement verb from a DLT-registered header (or an allowlisted notification) bypasses the model veto. Re-sweep: exactly the 12 real transactions rescued, 0 previously-ingested messages dropped, no scam/mandate/collect message rescued. Retraining on real-inbox data was rejected because it would embed personal tokens in shipped weights.

**Documentation impact:** docs/features/ml-pipeline.md documents the rule; README '100%' claim qualified.

## C3

**UPI Lite top-ups recorded as income (wrong sign)**

- **Category:** correctness  ·  **Severity:** HIGH  ·  **Confidence:** CONFIRMED  ·  **Status:** FIXED
- **Component:** UpiParser
- **Locations:** `lib/services/upi_parser.dart:159-181 (_detectType)`

**Evidence**

- Credit keywords are matched first by substring; 'added to' (credit list) fires before 'debited' in 'A/c debited and Rs.X added to your UPI Lite'
- Inbox sweep: 26 ingested messages flipped from credit to debit after the fix, all UPI Lite top-ups, ₹36,951.46 previously counted as received
- Direction-model disagreements fell from 5 to 1 after the fix

**Why it matters:** Spending under-reported and income over-reported by the top-up amounts.

**Actual behavior:** First matching credit keyword wins.

**Expected behavior:** 'debited'/'credited' (account settlement verbs) take precedence, earliest wins.

**Validation:** Inbox sweep before/after; 3 regression tests, 2 of which fail on the old parser.

**Recommended fix:** APPLIED.

**Documentation impact:** docs/features/upi-parser.md direction section updated.

## DOC3

**Docs asserted capture broadcasts were 'internal' when they were system-wide**

- **Category:** documentation  ·  **Severity:** HIGH  ·  **Confidence:** CONFIRMED  ·  **Status:** FIXED
- **Component:** docs/android
- **Locations:** `docs/android/native-layer.md:38-39,59`; `docs/android/platform-channels.md:68-74`

**Evidence**

- See S3

**Why it matters:** A security property was documented that the code lacked.

**Actual behavior:** Unscoped.

**Expected behavior:** Scoped.

**Validation:** Code trace.

**Recommended fix:** Code fixed so the docs are now accurate; wording made explicit.

**Documentation impact:** IMPLEMENTATION DIFFERED FROM DOCUMENTATION

## DOC4

**'Reads notifications and SMS in real time' — capture was off after every launch**

- **Category:** documentation  ·  **Severity:** HIGH  ·  **Confidence:** CONFIRMED  ·  **Status:** FIXED
- **Component:** docs/README
- **Locations:** `docs/README.md:3-6`; `README.md (overview)`

**Evidence**

- See C1

**Why it matters:** Users and maintainers believe capture is automatic.

**Actual behavior:** Manual per session.

**Expected behavior:** Automatic.

**Validation:** Device.

**Recommended fix:** Code fixed; docs describe persistence, catch-up and the remaining notification gap.

**Documentation impact:** IMPLEMENTATION DIFFERED FROM DOCUMENTATION

## O1

**A stale pre-rename build is still installed and capturing on the owner's device**

- **Category:** configuration  ·  **Severity:** HIGH  ·  **Confidence:** CONFIRMED  ·  **Status:** OPEN — owner action
- **Component:** device
- **Locations:** `com.example.receipt (installed 2026-04-19)`

**Evidence**

- Holds READ_SMS/RECEIVE_SMS, notification-listener access and ALLOW_BACKUP; runs the old code with S3/S4 leaks

**Why it matters:** Duplicate capture, old vulnerable code active, possible confusion about which app is current.

**Actual behavior:** Two apps.

**Expected behavior:** One app.

**Validation:** adb dumpsys / settings.

**Recommended fix:** Uninstall com.example.receipt (owner action).

**Documentation impact:** README upgrade note.

## S11

**Real bank SMS (account suffix, PAN fragment, balances, reference numbers, third-party names) committed to the public repository**

- **Category:** security  ·  **Severity:** HIGH  ·  **Confidence:** CONFIRMED  ·  **Status:** OPEN — requires owner decision (history rewrite)
- **Component:** tests / fixtures / docs
- **Locations:** `test/services/upi_parser_test.dart`; `test/upi_parser_test.dart`; `test/fixtures/*.json`; `scripts/generate_ml_fixtures.py`; `test/integration/*.dart`; `test/services/dedup_service_test.dart`; `docs/features/upi-parser.md`; `lib/services/upi_parser.dart (comments)`; `refs/heads/entire/checkpoints/v1 (agent transcripts)`

**Evidence**

- `git grep` on origin/main finds the owner's account-suffix pattern in 17 files and real 12-digit reference numbers in 13
- Full names of real counterparties with amounts appear in 10 files on main
- The checkpoint branch contains further raw SMS content
- .gitignore explicitly excludes data/*.csv 'because they contain real SMS / personal data' — the same content was copied into fixtures

**Why it matters:** Personal financial data of the owner and identifying data of third parties is publicly readable.

**Actual behavior:** Real messages used as test data.

**Expected behavior:** Synthetic test data only.

**Validation:** git grep against origin/main and the checkpoint branch.

**Recommended fix:** Replace fixtures with synthetic messages preserving format; rewrite history or make the repository private (owner decision).

**Documentation impact:** data/README.md should state the rule applies to fixtures too.

## S13

**Entire CLI git hooks copy session transcripts into a branch and push them with every push**

- **Category:** security  ·  **Severity:** HIGH  ·  **Confidence:** CONFIRMED  ·  **Status:** OPEN — owner action before next push
- **Component:** repository tooling
- **Locations:** `.git/hooks/prepare-commit-msg`; `.git/hooks/post-commit`; `.git/hooks/pre-push`; `refs/heads/entire/checkpoints/v1`; `refs/heads/entire/8475ac2-e3b0c4`

**Evidence**

- post-commit condenses session data into the checkpoint branch when a commit carries an Entire-Checkpoint trailer; pre-push pushes those logs alongside the user's push
- This mechanism produced S1 and part of S11
- Unpushed local entire branches already contain this audit session's transcripts with the owner's account-suffix pattern (122 matches) and real reference numbers (67)

**Why it matters:** Every future push can republish secrets and personal data from AI-assisted sessions to the public repository.

**Actual behavior:** Transcripts committed and pushed automatically.

**Expected behavior:** Session logs never leave the machine, or are scrubbed first.

**Validation:** Hook scripts read; git grep on local entire branches.

**Recommended fix:** Owner: uninstall or reconfigure the Entire hooks (or disable its push); delete the local entire/* branches before the next push. Audit commits were made with hooks disabled.

**Documentation impact:** None.

## S3

**Captured SMS bodies and payment notifications were broadcast to every app on the device**

- **Category:** security  ·  **Severity:** HIGH  ·  **Confidence:** HIGH  ·  **Status:** FIXED
- **Component:** android native capture
- **Locations:** `android/app/src/main/kotlin/com/example/receipt/SmsReceiver.kt:32`; `android/app/src/main/kotlin/com/example/receipt/UpiNotificationListener.kt:67`

**Evidence**

- Both use `sendBroadcast(Intent(ACTION))` with no setPackage() and no receiver permission
- MainActivity.kt:53 already uses setPackage() for the widget broadcast, so the safe pattern was known
- The notification allowlist includes com.whatsapp, so WhatsApp chat notifications were included

**Why it matters:** Any installed app registering a runtime receiver for com.upitracker.app.SMS_RECEIVED/NOTIFICATION_RECEIVED receives every SMS (incl. OTPs) without READ_SMS.

**Actual behavior:** Implicit, system-wide broadcast of message content.

**Expected behavior:** Package-scoped delivery to the app's own receiver only.

**Validation:** Static. Not demonstrated with a third-party receiver (deliberately not built). Runtime-registered receivers still receive implicit broadcasts on Android 8+.

**Recommended fix:** setPackage(packageName) on both intents — APPLIED.

**Documentation impact:** docs/android/native-layer.md and platform-channels.md described these as 'internal' broadcasts; that is now accurate.

## S4

**Full SMS and notification text written to logcat in all build types**

- **Category:** security  ·  **Severity:** HIGH  ·  **Confidence:** CONFIRMED  ·  **Status:** FIXED
- **Component:** android native capture
- **Locations:** `SmsReceiver.kt:25`; `UpiNotificationListener.kt:58`; `android/app/build.gradle.kts (no minify / log stripping)`

**Evidence**

- `Log.d(TAG, "SMS from $sender: $body")` with no debug guard; release build has no R8/ProGuard rules

**Why it matters:** Bank SMS, OTPs and (via the WhatsApp allowlist entry) chat messages are exposed to anyone with adb/logcat access and to bug-report captures.

**Actual behavior:** Message bodies logged verbatim.

**Expected behavior:** No message content in logs.

**Validation:** Static review.

**Recommended fix:** Log only lengths/package names — APPLIED.

**Documentation impact:** None.

## S5

**Release builds are signed with the debug keystore**

- **Category:** security  ·  **Severity:** HIGH  ·  **Confidence:** CONFIRMED  ·  **Status:** OPEN — needs owner keystore
- **Component:** android build
- **Locations:** `android/app/build.gradle.kts:29-33`

**Evidence**

- `release { signingConfig = signingConfigs.getByName("debug") }`

**Why it matters:** Release artifacts are not distributable and can be re-signed/replaced by anyone holding the public debug key.

**Actual behavior:** Debug signing for release.

**Expected behavior:** Dedicated release keystore kept out of the repo.

**Validation:** Static.

**Recommended fix:** Add a release signingConfig reading keystore path/passwords from local properties or CI secrets.

**Documentation impact:** docs/android/native-layer.md states this; keep until fixed.

## S6

**Android backup enabled for a database of raw SMS text and geotags**

- **Category:** security  ·  **Severity:** HIGH  ·  **Confidence:** CONFIRMED  ·  **Status:** FIXED
- **Component:** android manifest
- **Locations:** `android/app/src/main/AndroidManifest.xml:14-18 (no allowBackup / dataExtractionRules)`

**Evidence**

- `dumpsys package com.example.receipt` shows ALLOW_BACKUP on the device
- After the fix, the reinstalled com.upitracker.app no longer reports ALLOW_BACKUP

**Why it matters:** Transaction history, raw bank SMS and locations are copied to cloud backup / device transfer outside the app's control.

**Actual behavior:** allowBackup defaulted to true.

**Expected behavior:** Backup disabled or explicitly scoped.

**Validation:** Verified on device before and after.

**Recommended fix:** allowBackup=false, fullBackupContent=false, dataExtractionRules excluding all domains — APPLIED.

**Documentation impact:** docs/android/native-layer.md updated.

## S7

**Debt ledger exported unencrypted to world-readable shared storage, requiring the Play-restricted MANAGE_EXTERNAL_STORAGE**

- **Category:** security  ·  **Severity:** HIGH  ·  **Confidence:** CONFIRMED  ·  **Status:** FIXED (behaviour change: no uninstall survival)
- **Component:** debt backup (staged, uncommitted feature)
- **Locations:** `lib/services/debt_backup_service.dart:11-29 (/storage/emulated/0/Documents)`; `android/app/src/main/AndroidManifest.xml:11-12 (staged)`; `lib/screens/debts_screen.dart:53`

**Evidence**

- Hard-coded public Documents path; plaintext JSON of names, amounts, reasons, notes
- Restore banner reads the same file on every Debts visit; after reinstall Android 11+ no longer treats the app as owner, so restore also depends on the restricted permission
- export() had no error handling; readBackup() returned null for corrupt files (indistinguishable from 'no backup')

**Why it matters:** Other apps with storage access can read the ledger; the permission is likely to block Play publication.

**Actual behavior:** Public storage + All-files access.

**Expected behavior:** App-private storage, no broad storage permission, explicit error reporting.

**Validation:** Static review.

**Recommended fix:** Moved to getExternalStorageDirectory() (app-specific, no permission), removed both storage permissions, added DebtBackupException for write/corrupt-read failures — APPLIED. Trade-off: the backup no longer survives uninstall; SAF (user-chosen location) is the alternative if that matters.

**Documentation impact:** docs/features/debts.md: backup section added.

## T1

**Production model-load path had no test coverage**

- **Category:** test  ·  **Severity:** HIGH  ·  **Confidence:** CONFIRMED  ·  **Status:** FIXED
- **Component:** tests
- **Locations:** `test/services/ml/*`

**Evidence**

- Every test used loadFromJsonStringForTest via dart:io; TfidfLogReg.load()/rootBundle never called

**Why it matters:** Asset declaration or load regressions are invisible.

**Actual behavior:** Untested.

**Expected behavior:** Tested.

**Validation:** grep of test/.

**Recommended fix:** APPLIED: test/services/ml/model_asset_loading_test.dart (proven to fail when an asset declaration is removed).

**Documentation impact:** docs/testing.md.

## A1

**TransactionProvider is a god object with duplicated ingestion code**

- **Category:** architecture  ·  **Severity:** MEDIUM  ·  **Confidence:** CONFIRMED  ·  **Status:** OPEN
- **Component:** TransactionProvider
- **Locations:** `lib/providers/transaction_provider.dart`

**Evidence**

- Owns capture, ML gating, parsing, dedup, persistence, location, sync, widget push and UI state; record construction duplicated between live and history paths

**Why it matters:** Hard to test (T5) and easy to diverge (location only on one path).

**Actual behavior:** Monolith.

**Expected behavior:** Separate ingestion service.

**Validation:** Code review.

**Recommended fix:** Extract an IngestionService.

**Documentation impact:** docs/architecture.md.

## C14

**Local and remote disagree on transaction instants**

- **Category:** correctness  ·  **Severity:** MEDIUM  ·  **Confidence:** HIGH  ·  **Status:** OPEN
- **Component:** models / sync
- **Locations:** `lib/models/transaction_record.dart:50-75`; `lib/database/remote_database.dart:148-150`

**Evidence**

- SQLite stores naive local ISO strings; Postgres receives DateTime into TIMESTAMPTZ

**Why it matters:** Timestamps shift if the device time zone changes; local date filters use lexicographic string comparison.

**Actual behavior:** Two serialisation paths.

**Expected behavior:** One UTC-normalised representation.

**Validation:** Static.

**Recommended fix:** Store UTC (or epoch ms) locally.

**Documentation impact:** docs/data/models.md.

## C15

**Dedup can merge genuinely distinct payments**

- **Category:** correctness  ·  **Severity:** MEDIUM  ·  **Confidence:** HIGH  ·  **Status:** OPEN
- **Component:** DedupService
- **Locations:** `lib/services/dedup_service.dart:39,102-117`

**Evidence**

- Body-hash fallback for ref-less messages; fuzzy tier treats an empty counterparty as compatible; same-day path ignores time

**Why it matters:** Two identical small payments (same amount/day, unparsed counterparty) can collapse into one.

**Actual behavior:** Possible false merges.

**Expected behavior:** No false merges.

**Validation:** Static; not measured on device.

**Recommended fix:** Require a discriminator (time, balance, ref) before merging.

**Documentation impact:** docs/features/deduplication.md.

## C16

**Sync integrity check has blind spots and swallows errors**

- **Category:** correctness  ·  **Severity:** MEDIUM  ·  **Confidence:** HIGH  ·  **Status:** OPEN
- **Component:** SyncService
- **Locations:** `lib/services/sync_service.dart:95-122`

**Evidence**

- Count comparison masked by other devices' rows; only first/last ids probed; catch(_) returns 'ok'

**Why it matters:** Remote data loss can go undetected.

**Actual behavior:** Weak verification.

**Expected behavior:** Robust verification.

**Validation:** Static.

**Recommended fix:** Compare per-id checksums in pages; surface errors.

**Documentation impact:** docs/features/sync.md.

## C17

**Dead Postgres connection is cached forever; no timeout or retry**

- **Category:** correctness  ·  **Severity:** MEDIUM  ·  **Confidence:** HIGH  ·  **Status:** OPEN
- **Component:** RemoteDatabase
- **Locations:** `lib/database/remote_database.dart:14-40,171-175`

**Evidence**

- _connection reused until close(); no reset on error

**Why it matters:** After a server-side disconnect every sync fails until restart. (Settings showed 'Syncing…' with 'Not synced yet' right after launch on device; root cause not isolated.)

**Actual behavior:** No recovery.

**Expected behavior:** Reconnect with backoff.

**Validation:** Static; device observation inconclusive.

**Recommended fix:** Reset _connection on error; add timeouts.

**Documentation impact:** None.

## C18

**MainActivity leaks receivers and orphans them on re-subscribe**

- **Category:** correctness  ·  **Severity:** MEDIUM  ·  **Confidence:** HIGH  ·  **Status:** OPEN
- **Component:** MainActivity
- **Locations:** `MainActivity.kt:63-117`

**Evidence**

- Receivers unregistered only in onCancel; no onDestroy cleanup; second onListen overwrites the field

**Why it matters:** IntentReceiverLeaked / duplicate deliveries.

**Actual behavior:** Leak-prone.

**Expected behavior:** Cleanup in cleanUpFlutterEngine/onDestroy.

**Validation:** Static.

**Recommended fix:** Unregister in cleanUpFlutterEngine and before re-registering.

**Documentation impact:** None.

## C19

**SMS permission denial is reported as 'No new transactions found'**

- **Category:** correctness  ·  **Severity:** MEDIUM  ·  **Confidence:** CONFIRMED  ·  **Status:** OPEN
- **Component:** SmsService / MainActivity
- **Locations:** `lib/services/sms_service.dart:22-24`; `MainActivity.kt:140-162`

**Evidence**

- SecurityException → PlatformException → catch(_) → []

**Why it matters:** Users cannot distinguish a permission problem from an empty inbox.

**Actual behavior:** Silent.

**Expected behavior:** Explicit permission error.

**Validation:** Static; on-device revoke test not run (device was in use).

**Recommended fix:** Propagate a typed error.

**Documentation impact:** None.

## C20

**Home widget shows stale figures with no staleness signal**

- **Category:** correctness  ·  **Severity:** MEDIUM  ·  **Confidence:** HIGH  ·  **Status:** OPEN
- **Component:** widget
- **Locations:** `SpendingWidgetProvider.kt:97-119,200-223`; `lib/providers/transaction_provider.dart:512-528`

**Evidence**

- Data is pushed only while the Dart isolate runs; updatedAt stored but never rendered

**Why it matters:** After a day without opening the app the widget presents old 'Last 24 hours' totals as current.

**Actual behavior:** Stale.

**Expected behavior:** Marked stale or refreshed.

**Validation:** Static. The 'can't load widget' error from commit db4fc0a was not reproduced (device in use).

**Recommended fix:** Render updatedAt / hide when older than 24h.

**Documentation impact:** docs/features/home-widget.md.

## C21

**Notification allowlist misses installed payment apps and includes WhatsApp**

- **Category:** correctness  ·  **Severity:** MEDIUM  ·  **Confidence:** MEDIUM  ·  **Status:** OPEN
- **Component:** UpiNotificationListener
- **Locations:** `UpiNotificationListener.kt:15-38`

**Evidence**

- Device: SBI (com.sbi.lotusintouch), super.money, Navi, PhonePe Business and Amazon are installed but not allowlisted
- Three allowlisted ids look wrong (net.csam.hdfc, com.canaaborb, com.myairtel.myairtelapp) — not verified against the Play Store
- com.whatsapp is allowlisted, so chat notifications enter the pipeline without the SMS-path isUpiRelated pre-gate

**Why it matters:** Missed notification transactions; possible false transactions from chats.

**Actual behavior:** Incomplete/over-broad list.

**Expected behavior:** Accurate list.

**Validation:** Device package list; static.

**Recommended fix:** Fix ids; drop WhatsApp or gate it on payment-specific text.

**Documentation impact:** docs/android/native-layer.md.

## C5

**Classifier load failure is completely silent**

- **Category:** correctness  ·  **Severity:** MEDIUM  ·  **Confidence:** CONFIRMED  ·  **Status:** FIXED
- **Component:** ML pipeline
- **Locations:** `lib/services/ml/tfidf_logreg.dart:54-56`; `lib/services/ml/message_pipeline.dart:71-77`

**Evidence**

- Exceptions (incl. StateError for corrupt models) are caught and only debugPrinted; no UI anywhere showed load state

**Why it matters:** If loading ever fails the app ingests spam/OTPs as transactions with no signal.

**Actual behavior:** Silent fail-open.

**Expected behavior:** Fail-open is reasonable, but must be visible.

**Validation:** Static; new tests prove missing/corrupt assets leave the engine unloaded.

**Recommended fix:** APPLIED: MessagePipeline.isLoaded / provider.filtersLoaded surfaced in Settings.

**Documentation impact:** docs/features/ml-pipeline.md.

## C6

**SMS history scan only reaches the 500 most recent SMS of any sender**

- **Category:** correctness  ·  **Severity:** MEDIUM  ·  **Confidence:** CONFIRMED  ·  **Status:** PARTIALLY FIXED
- **Component:** TransactionProvider / MainActivity
- **Locations:** `lib/providers/transaction_provider.dart:269`; `MainActivity.kt:128-164`

**Evidence**

- readSmsHistory(limit: 500) without `since`; inbox on device has 3,901 messages

**Why it matters:** Older transactions can never be imported.

**Actual behavior:** Fixed 500-row window.

**Expected behavior:** Paged import or date-bounded import.

**Validation:** Device inbox size + code.

**Recommended fix:** Partially mitigated by the persisted catch-up watermark (C1); full-history import still needs paging off the main thread (see P2).

**Documentation impact:** docs/features/transaction-capture.md.

## C8

**EventChannel errors silently kill capture while the UI still reports 'listening'**

- **Category:** correctness  ·  **Severity:** MEDIUM  ·  **Confidence:** CONFIRMED  ·  **Status:** FIXED
- **Component:** TransactionProvider
- **Locations:** `lib/providers/transaction_provider.dart:142-143`

**Evidence**

- listen() without onError

**Why it matters:** Capture stops permanently with no indication.

**Actual behavior:** Dead subscription, _isListening stays true.

**Expected behavior:** State reflects reality.

**Validation:** Static.

**Recommended fix:** APPLIED: onError stops listening and reports the error.

**Documentation impact:** None.

## C9

**SYNC_INTERVAL_MINUTES of 0 or less spins Timer.periodic**

- **Category:** correctness  ·  **Severity:** MEDIUM  ·  **Confidence:** CONFIRMED  ·  **Status:** FIXED
- **Component:** SyncService
- **Locations:** `lib/services/sync_service.dart:23-34`

**Evidence**

- int.tryParse('0') returns 0, so the `?? 15` fallback never applies

**Why it matters:** Tight sync loop hammering the database and battery.

**Actual behavior:** 0/negative accepted.

**Expected behavior:** Clamped to a sane default.

**Validation:** Static.

**Recommended fix:** APPLIED.

**Documentation impact:** docs/features/sync.md.

## D1

**Python training environment is not reproducible**

- **Category:** dependency  ·  **Severity:** MEDIUM  ·  **Confidence:** CONFIRMED  ·  **Status:** OPEN
- **Component:** scripts
- **Locations:** `scripts/*.py`; `(no requirements.txt / pyproject)`

**Evidence**

- Local .venv-ml has scikit-learn 1.9.0, numpy 2.5.1; nothing pinned in the repo

**Why it matters:** Retraining may silently produce different models.

**Actual behavior:** Unpinned.

**Expected behavior:** Pinned.

**Validation:** Repo inspection.

**Recommended fix:** Add requirements.txt with pinned versions.

**Documentation impact:** docs/ml-training.md.

## DOC1

**README claims sync is 'bidirectional-safe'**

- **Category:** documentation  ·  **Severity:** MEDIUM  ·  **Confidence:** CONFIRMED  ·  **Status:** FIXED
- **Component:** README
- **Locations:** `README.md:27-29`; `README.md:214`

**Evidence**

- Sync is push-only (docs/features/sync.md is correct)

**Why it matters:** Readers assume remote→local recovery exists.

**Actual behavior:** Push-only.

**Expected behavior:** Doc states push-only.

**Validation:** Code trace.

**Recommended fix:** Corrected.

**Documentation impact:** DOCUMENTATION IS INCORRECT

## DOC10

**Debt backup feature and its storage/permissions were undocumented**

- **Category:** documentation  ·  **Severity:** MEDIUM  ·  **Confidence:** CONFIRMED  ·  **Status:** FIXED
- **Component:** docs
- **Locations:** `docs/features/debts.md`; `docs/setup.md`

**Evidence**

- No mention of DebtBackupService, file location or permissions

**Why it matters:** —

**Actual behavior:** —

**Expected behavior:** —

**Validation:** grep.

**Recommended fix:** Documented.

**Documentation impact:** IMPLEMENTATION HAS UNDOCUMENTED BEHAVIOR

## DOC5

**'100% of real UPI SMS ingested' holds only on the training corpus**

- **Category:** documentation  ·  **Severity:** MEDIUM  ·  **Confidence:** CONFIRMED  ·  **Status:** FIXED
- **Component:** README / docs
- **Locations:** `README.md:131-141`; `docs/ml-training.md:109-111`; `docs/testing.md:91-95`

**Evidence**

- See C2: 12 real transactions dropped on an independent real inbox before the fix

**Why it matters:** Overstated guarantee.

**Actual behavior:** Overclaim.

**Expected behavior:** Qualified claim.

**Validation:** Inbox sweep.

**Recommended fix:** Qualified in README.

**Documentation impact:** DOCUMENTATION IS INCORRECT

## DOC7

**Held-out metrics conflict between README and docs/ml-training.md**

- **Category:** documentation  ·  **Severity:** MEDIUM  ·  **Confidence:** CONFIRMED  ·  **Status:** OPEN — human decision
- **Component:** README / docs
- **Locations:** `README.md:126-128,141`; `docs/ml-training.md:105-111`

**Evidence**

- Spam recall 0.917 vs 0.921; direction precision 0.958 vs 0.980; min P(transactional) 0.571 vs 0.615; '382 SMS' vs '381/381'

**Why it matters:** Unknown which numbers describe the shipped models.

**Actual behavior:** Conflict.

**Expected behavior:** One reproducible set.

**Validation:** Text comparison; not recomputed (would require retraining or rebuilding the exact split).

**Recommended fix:** Marked for human decision; regenerate from a pinned training run.

**Documentation impact:** BOTH REQUIRE CLARIFICATION

## M1

**Spam model is trained mostly on an unrelated SMS-chat corpus**

- **Category:** ml  ·  **Severity:** MEDIUM  ·  **Confidence:** CONFIRMED  ·  **Status:** OPEN — modelling decision
- **Component:** training
- **Locations:** `scripts/train_all_models.py:90-110`; `assets/spam_model.json (vocab)`

**Evidence**

- Vocabulary dominated by Singlish chat tokens from the 5,572-row Kaggle set; real UPI data is 382 rows
- On the owner's inbox a legitimate Indian Bank UPI Lite template scores exactly the 0.85 threshold

**Why it matters:** Fragile on real bank formats; correctness depends on the high threshold.

**Actual behavior:** Domain mismatch.

**Expected behavior:** In-domain training data.

**Validation:** Vocab inspection + inbox sweep.

**Recommended fix:** Retrain with more Indian bank/UPI data (synthetic or consented), re-validate on real inboxes.

**Documentation impact:** docs/ml-training.md.

## O2

**No code shrinking/obfuscation and unpinned targetSdk**

- **Category:** configuration  ·  **Severity:** MEDIUM  ·  **Confidence:** CONFIRMED  ·  **Status:** OPEN
- **Component:** android build
- **Locations:** `android/app/build.gradle.kts`

**Evidence**

- No isMinifyEnabled; targetSdk = flutter.targetSdkVersion (36 with Flutter 3.41.6)

**Why it matters:** Larger attack surface; target SDK changes silently with Flutter upgrades.

**Actual behavior:** —

**Expected behavior:** Explicit.

**Validation:** Static.

**Recommended fix:** Enable R8 for release; pin targetSdk.

**Documentation impact:** docs/android/native-layer.md.

## P1

**Every refresh loads the entire filtered transaction table**

- **Category:** performance  ·  **Severity:** MEDIUM  ·  **Confidence:** CONFIRMED  ·  **Status:** OPEN
- **Component:** LocalDatabase / TransactionProvider
- **Locations:** `lib/database/local_database.dart:133-178`; `lib/providers/transaction_provider.dart:343-357`

**Evidence**

- getAllTransactions is called without limit/offset after every insert, filter change and summary reload

**Why it matters:** Linear growth of memory and refresh time with history size (each row carries raw SMS text).

**Actual behavior:** Unbounded.

**Expected behavior:** Paged.

**Validation:** Static.

**Recommended fix:** Paginate the list; load summaries via SQL only.

**Documentation impact:** None.

## P2

**SMS history is read on the platform main thread**

- **Category:** performance  ·  **Severity:** MEDIUM  ·  **Confidence:** HIGH  ·  **Status:** OPEN
- **Component:** MainActivity
- **Locations:** `MainActivity.kt:45,128-164`

**Evidence**

- ContentResolver cursor loop runs synchronously inside the method-call handler (up to 500 rows)

**Why it matters:** UI jank/ANR risk during scans, now also during startup catch-up (bounded by the watermark).

**Actual behavior:** Main thread.

**Expected behavior:** Background thread.

**Validation:** Static; not profiled.

**Recommended fix:** Run the query on a background executor and post the result.

**Documentation impact:** None.

## P4

**Location lookup blocks live ingestion for up to 10 seconds**

- **Category:** performance  ·  **Severity:** MEDIUM  ·  **Confidence:** HIGH  ·  **Status:** OPEN
- **Component:** TransactionProvider / LocationService
- **Locations:** `lib/providers/transaction_provider.dart:231-234`; `lib/services/location_service.dart:36-39`

**Evidence**

- getCurrentLocation awaited inline with a 10 s timeLimit before insert

**Why it matters:** Captured transactions appear late; may prompt for permission from a background event.

**Actual behavior:** Blocking.

**Expected behavior:** Insert first, enrich later.

**Validation:** Static.

**Recommended fix:** Insert immediately and attach location asynchronously.

**Documentation impact:** docs/features/location-tagging.md.

## P5

**Sync uploads row by row with no batching or transaction; full re-push after integrity miss**

- **Category:** performance  ·  **Severity:** MEDIUM  ·  **Confidence:** HIGH  ·  **Status:** OPEN
- **Component:** RemoteDatabase / SyncService
- **Locations:** `lib/database/remote_database.dart:108-153`; `lib/services/sync_service.dart:95-122`; `lib/database/local_database.dart:207-215,329-332`

**Evidence**

- One round trip per row; markAllUnsynced re-uploads the whole table; getUnsyncedTransactions has no LIMIT

**Why it matters:** Slow, battery-heavy sync and partial remote writes on failure.

**Actual behavior:** —

**Expected behavior:** Batched, paged, transactional.

**Validation:** Static.

**Recommended fix:** Batch inserts in a transaction, page uploads.

**Documentation impact:** docs/features/sync.md.

## S8

**Precise per-purchase geolocation is synced to the shared, credential-exposed database**

- **Category:** security  ·  **Severity:** MEDIUM  ·  **Confidence:** CONFIRMED  ·  **Status:** OPEN
- **Component:** sync
- **Locations:** `lib/database/remote_database.dart:84-86,142-144`; `lib/providers/transaction_provider.dart:231-253`

**Evidence**

- latitude/longitude at full precision plus reverse-geocoded place name are in the remote upsert parameter map

**Why it matters:** Combined with S1/S2, a public location history of the user's purchases.

**Actual behavior:** Location synced by default.

**Expected behavior:** Location kept local or coarsened, and only synced with consent.

**Validation:** Static.

**Recommended fix:** Exclude or coarsen location fields in sync; make location tagging opt-in.

**Documentation impact:** docs/features/location-tagging.md should state it is synced.

## S9

**TLS to Postgres does not verify the server certificate; channel_binding is dropped**

- **Category:** security  ·  **Severity:** MEDIUM  ·  **Confidence:** HIGH  ·  **Status:** OPEN
- **Component:** sync
- **Locations:** `lib/database/remote_database.dart:31`; `lib/database/remote_database.dart:42-66`

**Evidence**

- SslMode.require (encrypt, no verification) is used; the hand-written URL parser ignores query parameters such as channel_binding=require

**Why it matters:** A network attacker can MITM the database connection and capture the credential.

**Actual behavior:** Encrypted but unauthenticated TLS.

**Expected behavior:** verify-full semantics.

**Validation:** Static review of package:postgres settings.

**Recommended fix:** Use SslMode.verifyFull; better, remove direct DB access (S2).

**Documentation impact:** None.

## T2

**Parity fixtures were circular (Dart vs a Python copy of Dart)**

- **Category:** test  ·  **Severity:** MEDIUM  ·  **Confidence:** CONFIRMED  ·  **Status:** FIXED
- **Component:** scripts
- **Locations:** `scripts/generate_ml_fixtures.py:36`; `scripts/ml_core.py:358-399`

**Evidence**

- Expected probabilities came from score_manual

**Why it matters:** Shared drift from sklearn would pass.

**Actual behavior:** Circular.

**Expected behavior:** Reference = sklearn.

**Validation:** Code review.

**Recommended fix:** APPLIED: score_sklearn reference; generator fails if score_manual drifts by more than 1e-6.

**Documentation impact:** docs/testing.md, docs/ml-training.md.

## T3

**Database tests exercise a hand-copied class, not LocalDatabase**

- **Category:** test  ·  **Severity:** MEDIUM  ·  **Confidence:** CONFIRMED  ·  **Status:** OPEN
- **Component:** tests
- **Locations:** `test/database/local_database_test.dart:8`

**Evidence**

- TestableLocalDatabase duplicates schema and queries

**Why it matters:** Production query changes are untested (e.g. the new getTransactionCount range).

**Actual behavior:** Copy drift.

**Expected behavior:** Test the real class against FFI SQLite.

**Validation:** Code review.

**Recommended fix:** Inject the DatabaseFactory into LocalDatabase and test it directly.

**Documentation impact:** docs/testing.md.

## T4

**No CI; strictest accuracy suites only run where gitignored data exists**

- **Category:** test  ·  **Severity:** MEDIUM  ·  **Confidence:** CONFIRMED  ·  **Status:** OPEN
- **Component:** repo
- **Locations:** `(no .github/)`; `test/accuracy/*`

**Evidence**

- Accuracy suites markTestSkipped without data/*.csv

**Why it matters:** Regressions land unnoticed.

**Actual behavior:** Manual only.

**Expected behavior:** CI on every push with synthetic accuracy corpus.

**Validation:** Repo inspection.

**Recommended fix:** Add CI (analyze + test).

**Documentation impact:** docs/testing.md.

## T5

**Ingestion orchestration and Kotlin layer are untested**

- **Category:** test  ·  **Severity:** MEDIUM  ·  **Confidence:** CONFIRMED  ·  **Status:** OPEN
- **Component:** tests
- **Locations:** `lib/providers/transaction_provider.dart`; `android/app/src/main/kotlin/**`

**Evidence**

- Only copied query logic of the provider is tested; no Kotlin tests

**Why it matters:** C1, C7, C8 class defects are invisible to the suite.

**Actual behavior:** Untested.

**Expected behavior:** Covered.

**Validation:** Repo inspection.

**Recommended fix:** Extract ingestion into a testable service with injected channels.

**Documentation impact:** docs/testing.md.

## A2

**Kotlin sources live under com/example/receipt but declare package com.upitracker.app**

- **Category:** architecture  ·  **Severity:** LOW  ·  **Confidence:** CONFIRMED  ·  **Status:** OPEN
- **Component:** android
- **Locations:** `android/app/src/main/kotlin/com/example/receipt/*.kt`

**Evidence**

- Commit 8475ac2 changed package statements, namespace and applicationId but not the directory

**Why it matters:** Cosmetic; misleading paths in docs.

**Actual behavior:** Mismatch.

**Expected behavior:** Directory matches package.

**Validation:** Build verified.

**Recommended fix:** git mv to com/upitracker/app.

**Documentation impact:** docs/android/*.

## A3

**Status/success messages are carried in the `error` field**

- **Category:** architecture  ·  **Severity:** LOW  ·  **Confidence:** CONFIRMED  ·  **Status:** OPEN
- **Component:** TransactionProvider
- **Locations:** `lib/providers/transaction_provider.dart:331-337`

**Evidence**

- 'Found N new transactions' assigned to _error

**Why it matters:** Confusing API.

**Actual behavior:** —

**Expected behavior:** —

**Validation:** Code review.

**Recommended fix:** Separate status field.

**Documentation impact:** None.

## C10

**Un-settling a debt leaves a stale settled_at**

- **Category:** correctness  ·  **Severity:** LOW  ·  **Confidence:** CONFIRMED  ·  **Status:** FIXED
- **Component:** DebtEntry / DebtProvider
- **Locations:** `lib/models/debt_entry.dart:57`; `lib/providers/debt_provider.dart:123-134`

**Evidence**

- copyWith treats null as 'keep'

**Why it matters:** Inconsistent rows (settled=0 with settled_at set).

**Actual behavior:** Stale timestamp.

**Expected behavior:** Cleared.

**Validation:** New test.

**Recommended fix:** APPLIED: explicit clearSettledAt flag.

**Documentation impact:** docs/data/models.md listed it as a quirk.

## C11

**Widget 24h transaction count used the filtered list while amounts were unfiltered**

- **Category:** correctness  ·  **Severity:** LOW  ·  **Confidence:** CONFIRMED  ·  **Status:** FIXED
- **Component:** TransactionProvider
- **Locations:** `lib/providers/transaction_provider.dart:381-383`

**Evidence**

- _last24hCount derived from _transactions (user filters applied)

**Why it matters:** Widget count disagrees with its own totals when filters are active.

**Actual behavior:** Mismatch.

**Expected behavior:** Consistent.

**Validation:** Static.

**Recommended fix:** APPLIED: count from the database for the same window.

**Documentation impact:** docs/features/home-widget.md.

## C12

**Percent-encoded credentials in DATABASE_URL were not decoded**

- **Category:** correctness  ·  **Severity:** LOW  ·  **Confidence:** HIGH  ·  **Status:** FIXED
- **Component:** RemoteDatabase
- **Locations:** `lib/database/remote_database.dart:57-66`

**Evidence**

- userInfo used raw

**Why it matters:** Passwords containing %XX fail to authenticate.

**Actual behavior:** Raw.

**Expected behavior:** Decoded.

**Validation:** Static.

**Recommended fix:** APPLIED.

**Documentation impact:** None.

## C13

**Startup crashes if .env is absent**

- **Category:** correctness  ·  **Severity:** LOW  ·  **Confidence:** CONFIRMED  ·  **Status:** FIXED
- **Component:** main
- **Locations:** `lib/main.dart:13`

**Evidence**

- dotenv.load without isOptional

**Why it matters:** Removing the bundled .env (S1/S2 fix) would crash the app.

**Actual behavior:** Throws.

**Expected behavior:** App runs with sync disabled.

**Validation:** Static.

**Recommended fix:** APPLIED: isOptional: true.

**Documentation impact:** docs/setup.md.

## C22

**TransactionType/DebtDirection silently default unknown values**

- **Category:** correctness  ·  **Severity:** LOW  ·  **Confidence:** CONFIRMED  ·  **Status:** OPEN
- **Component:** models
- **Locations:** `lib/models/transaction_record.dart:181-186`; `lib/models/debt_entry.dart:106-111`

**Evidence**

- Unknown → debit / owedToMe

**Why it matters:** Corrupt rows flip sign silently.

**Actual behavior:** Silent default.

**Expected behavior:** Error or explicit unknown.

**Validation:** Static.

**Recommended fix:** Throw or log.

**Documentation impact:** docs/data/models.md documents it.

## C23

**TransactionRecord.copyWith cannot clear nullable fields**

- **Category:** correctness  ·  **Severity:** LOW  ·  **Confidence:** CONFIRMED  ·  **Status:** OPEN
- **Component:** models
- **Locations:** `lib/models/transaction_record.dart:124-128`

**Evidence**

- `note ?? this.note`

**Why it matters:** A note cannot be cleared to null (empty string works).

**Actual behavior:** Cannot null.

**Expected behavior:** Clearable.

**Validation:** Static.

**Recommended fix:** Same pattern as C10.

**Documentation impact:** None.

## C24

**Labelled sparkline bars overflow the dashboard card**

- **Category:** correctness  ·  **Severity:** LOW  ·  **Confidence:** HIGH  ·  **Status:** FIXED
- **Component:** DashboardScreen (staged change)
- **Locations:** `lib/screens/dashboard_screen.dart (_Bar.build)`

**Evidence**

- The tallest bar takes the full 56 px LayoutBuilder height and the amount label is stacked above it in a Column

**Why it matters:** Debug builds show an overflow stripe and release builds clip the bar whenever the week has spending.

**Actual behavior:** Overflow.

**Expected behavior:** Bar plus label fit the fixed height.

**Validation:** Layout arithmetic; not yet observed on device (no spending in the current window).

**Recommended fix:** APPLIED: reserve a fixed 12 px label slot and size bars from the remaining height.

**Documentation impact:** None.

## C4

**Model load was fire-and-forget (latent race with fail-open classifiers)**

- **Category:** correctness  ·  **Severity:** LOW  ·  **Confidence:** CONFIRMED  ·  **Status:** FIXED
- **Component:** TransactionProvider
- **Locations:** `lib/providers/transaction_provider.dart:112`; `lib/main.dart:33`

**Evidence**

- `unawaited(MessagePipeline.instance.load())`; unloaded classifiers return spam=0.0, tx=true
- Device measurement: all three models load in 161 ms (debug build) — unreachable in practice while capture required a manual toggle, but reachable once capture auto-starts (C1 fix)

**Why it matters:** Messages evaluated during the window would bypass all filtering.

**Actual behavior:** Race window ~161 ms.

**Expected behavior:** Models resident before any evaluation.

**Validation:** Instrumented on-device timing (instrumentation reverted).

**Recommended fix:** APPLIED: initialize() awaits load() before starting capture.

**Documentation impact:** None.

## C7

**History scan also ingests sent/outbox SMS**

- **Category:** correctness  ·  **Severity:** LOW  ·  **Confidence:** CONFIRMED  ·  **Status:** FIXED
- **Component:** TransactionProvider
- **Locations:** `MainActivity.kt:130 (Telephony.Sms.CONTENT_URI)`; `lib/providers/transaction_provider.dart:263-330`

**Evidence**

- Query covers all SMS types; the Dart side never checked `type`

**Why it matters:** User's own outgoing messages can be parsed as transactions.

**Actual behavior:** All SMS types.

**Expected behavior:** Inbox (type 1) only.

**Validation:** Static.

**Recommended fix:** APPLIED: skip non-inbox rows.

**Documentation impact:** None.

## D2

**Direct Dart dependencies behind latest, incl. the database driver**

- **Category:** dependency  ·  **Severity:** LOW  ·  **Confidence:** CONFIRMED  ·  **Status:** OPEN
- **Component:** pubspec
- **Locations:** `pubspec.yaml`; `pubspec.lock`

**Evidence**

- `flutter pub outdated`: postgres 3.5.9 → 3.5.19 (resolvable), permission_handler 11 → 13, geolocator 13 → 14, flutter_dotenv 5 → 6; 74 packages total have newer versions

**Why it matters:** Missed fixes; no specific CVE was verified (no vulnerability database was available in this environment).

**Actual behavior:** Behind.

**Expected behavior:** Current.

**Validation:** pub outdated.

**Recommended fix:** Upgrade postgres within constraints first; schedule majors.

**Documentation impact:** None.

## DOC2

**README describes the dedup key wrongly**

- **Category:** documentation  ·  **Severity:** LOW  ·  **Confidence:** CONFIRMED  ·  **Status:** FIXED
- **Component:** README
- **Locations:** `README.md:24-26`

**Evidence**

- Key is md5 of txn id → ref → normalised body; amount/window/counterparty is the separate fuzzy tier

**Why it matters:** Misleads maintainers.

**Actual behavior:** —

**Expected behavior:** —

**Validation:** Code trace.

**Recommended fix:** Corrected.

**Documentation impact:** DOCUMENTATION IS OUTDATED

## DOC6

**Stale model sizes/feature counts**

- **Category:** documentation  ·  **Severity:** LOW  ·  **Confidence:** CONFIRMED  ·  **Status:** FIXED
- **Component:** README / docs
- **Locations:** `README.md:58,67`; `docs/features/ml-pipeline.md:4`

**Evidence**

- direction model is 38.1 KB / 731 features (README: 33.7 KB / 641); payload ~350 KB (doc: 344 KB)

**Why it matters:** —

**Actual behavior:** —

**Expected behavior:** —

**Validation:** File sizes and JSON.

**Recommended fix:** Corrected.

**Documentation impact:** DOCUMENTATION IS OUTDATED

## DOC8

**Training-mix and test-count details are wrong**

- **Category:** documentation  ·  **Severity:** LOW  ·  **Confidence:** CONFIRMED  ·  **Status:** FIXED
- **Component:** docs
- **Locations:** `docs/ml-training.md:33,60`; `docs/testing.md:3,113-114`

**Evidence**

- SYNTHETIC_CREDITS is 20 (doc 21); CURATED_SPAM weighted ×2 (doc ×3); ~255 tests (actual 286 before this audit, 299 after); fixture counts 13/15/12 (actual 17/24/16)

**Why it matters:** —

**Actual behavior:** —

**Expected behavior:** —

**Validation:** Code/fixture inspection.

**Recommended fix:** Corrected.

**Documentation impact:** DOCUMENTATION IS OUTDATED

## DOC9

**Unverifiable performance claim**

- **Category:** documentation  ·  **Severity:** LOW  ·  **Confidence:** CONFIRMED  ·  **Status:** FIXED
- **Component:** docs/features/ml-pipeline.md
- **Locations:** `docs/features/ml-pipeline.md:26-27`

**Evidence**

- '~98% of decisions short-circuit at layer 1 (~5 µs/message)' — no benchmark exists; the inbox sweep shows most UPI messages pass all layers

**Why it matters:** —

**Actual behavior:** —

**Expected behavior:** —

**Validation:** Inbox sweep.

**Recommended fix:** Removed.

**Documentation impact:** DOCUMENTATION IS AMBIGUOUS

## M2

**Notification text is scored by SMS-trained models**

- **Category:** ml  ·  **Severity:** LOW  ·  **Confidence:** MEDIUM  ·  **Status:** OPEN
- **Component:** ML pipeline
- **Locations:** `lib/providers/transaction_provider.dart:162`

**Evidence**

- evaluate('$title $text') on app notifications; training data is SMS only

**Why it matters:** Out-of-distribution scoring; unvalidated (zero notification transactions ever captured on device).

**Actual behavior:** Unvalidated.

**Expected behavior:** Validated or separate thresholds.

**Validation:** Static + device DB.

**Recommended fix:** Collect consented notification samples and evaluate.

**Documentation impact:** docs/features/ml-pipeline.md.

## P3

**Fuzzy dedup re-parses every candidate's raw text per incoming message**

- **Category:** performance  ·  **Severity:** LOW  ·  **Confidence:** HIGH  ·  **Status:** OPEN
- **Component:** DedupService
- **Locations:** `lib/services/dedup_service.dart:48-81`

**Evidence**

- UpiParser.parseSms on each candidate row; no index on (amount, transaction_type)

**Why it matters:** O(candidates) regex work per message on the UI isolate.

**Actual behavior:** —

**Expected behavior:** Store parsed discriminators.

**Validation:** Static.

**Recommended fix:** Persist balance/embedded time columns; add index.

**Documentation impact:** None.

## S10

**Widget provider exported without a permission**

- **Category:** security  ·  **Severity:** LOW  ·  **Confidence:** CONFIRMED  ·  **Status:** OPEN
- **Component:** android manifest
- **Locations:** `android/app/src/main/AndroidManifest.xml:57-67`

**Evidence**

- Accepts com.upitracker.app.UPDATE_WIDGET from any app

**Why it matters:** Any app can force widget re-renders (no data exposure).

**Actual behavior:** Unprotected exported receiver.

**Expected behavior:** Restricted to the app.

**Validation:** Static.

**Recommended fix:** Drop the custom action from the exported filter (MainActivity already sends it package-scoped) or protect it with a signature permission.

**Documentation impact:** None.

## S12

**Unused privileged permissions declared**

- **Category:** security  ·  **Severity:** LOW  ·  **Confidence:** CONFIRMED  ·  **Status:** OPEN
- **Component:** android manifest
- **Locations:** `android/app/src/main/AndroidManifest.xml:9-10`

**Evidence**

- RECEIVE_BOOT_COMPLETED and FOREGROUND_SERVICE are declared; no boot receiver or foreground service exists

**Why it matters:** Larger permission surface than needed.

**Actual behavior:** Declared but unused.

**Expected behavior:** Least privilege.

**Validation:** grep of manifest and Kotlin sources.

**Recommended fix:** Remove both, or implement the boot/foreground capture they imply (see C1).

**Documentation impact:** docs/android/native-layer.md lists them.

## T6

**Duplicate parser test file**

- **Category:** test  ·  **Severity:** LOW  ·  **Confidence:** CONFIRMED  ·  **Status:** OPEN
- **Component:** tests
- **Locations:** `test/upi_parser_test.dart`

**Evidence**

- Fully overlaps test/services/upi_parser_test.dart

**Why it matters:** Maintenance cost.

**Actual behavior:** Duplicate.

**Expected behavior:** One suite.

**Validation:** Docs say so.

**Recommended fix:** Delete the root-level copy.

**Documentation impact:** docs/testing.md.

## M3

**Empty input scores 0.0 where sklearn gives sigmoid(bias)**

- **Category:** ml  ·  **Severity:** INFO  ·  **Confidence:** CONFIRMED  ·  **Status:** ACCEPTED
- **Component:** TfidfLogReg
- **Locations:** `lib/services/ml/tfidf_logreg.dart:94`; `scripts/ml_core.py:369`

**Evidence**

- Deliberate shared guard; unreachable in practice

**Why it matters:** None in practice.

**Actual behavior:** Guard.

**Expected behavior:** —

**Validation:** Static.

**Recommended fix:** None; documented.

**Documentation impact:** docs/features/ml-pipeline.md.

## M4

**Dart inference is numerically identical to sklearn (negative finding)**

- **Category:** ml  ·  **Severity:** INFO  ·  **Confidence:** CONFIRMED  ·  **Status:** VERIFIED
- **Component:** TfidfLogReg
- **Locations:** `lib/services/ml/tfidf_logreg.dart:91-124`

**Evidence**

- Fixtures regenerated from sklearn's own TfidfVectorizer.transform differ from the previous ones by at most 2.2e-16

**Why it matters:** The models themselves are not 'broken'.

**Actual behavior:** Correct.

**Expected behavior:** Correct.

**Validation:** sklearn reference scoring.

**Recommended fix:** Do not change the inference maths.

**Documentation impact:** None.
