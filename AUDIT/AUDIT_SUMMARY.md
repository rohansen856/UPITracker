# Audit Summary — UPI Tracker

Forensic audit of the repository at HEAD `8475ac2` plus the staged working-tree changes,
performed 2026-10-06. Evidence comes from source review, the test suite, artifact
inspection, git/GitHub queries, and testing on a physical Android 16 (SDK 36) device,
including a sweep of the owner's real 3,901-message SMS inbox through the shipped models.
The inbox corpus was kept outside the repository and is not reproduced here; all personal
data in these reports is redacted.

This report does **not** declare the repository secure or production ready.

## What the system is

An offline-first Flutter app, Android-only in practice. It reads bank SMS and the
notifications of an allowlist of payment apps, filters them through three on-device
TF-IDF + logistic-regression classifiers (spam → transactional → direction), parses them
with a regex engine, deduplicates them, and stores them in SQLite. An optional push-only
sync writes every row **directly into a shared Postgres database from the phone**. It also
has a manual debts ledger with JSON export, and a home-screen widget fed by snapshots from
the running app.

Major components: `lib/providers/transaction_provider.dart` (orchestrates almost
everything), `lib/services/ml/*`, `lib/services/upi_parser.dart`,
`lib/services/dedup_service.dart`, `lib/database/{local,remote}_database.dart`, four
Kotlin classes (SMS receiver, notification listener, activity/channels, widget), and the
Python trainer in `scripts/`. See [ARCHITECTURE_AUDIT.md](ARCHITECTURE_AUDIT.md).

## Why the app looked "broken" on the device

The models are not the main problem. The Dart inference maths matches sklearn to 2.2e-16
(M4), and all three models load on the device in 161 ms. The real causes, all confirmed on
the device:

1. **Capture never runs (C1, CRITICAL).** Live Monitoring was a non-persisted, per-session
   switch in Settings, and nothing was captured or caught up while the app was closed. The
   app's database held 118 rows, all from one manual history scan about 2.5 months earlier,
   and **none ever came from notifications**. The dashboard showed ₹0 for a day with real
   debits in the inbox.
2. **Whole bank templates were dropped by the classifiers (C2, HIGH).** On the real inbox,
   every Indian Bank "is credited with … RRN" credit (7/7) and every "added to your UPI Lite
   on npci App" top-up (5/5) was discarded. That is 12 transactions worth ₹14,146.07, against
   the docs' "100% ingested" claim.
3. **UPI Lite top-ups were stored as income (C3, HIGH).** 26 messages, ₹36,951.46 counted
   as received instead of spent, caused by keyword-order precedence in the parser.
4. **A stale pre-rename build is still installed (O1).** It holds SMS and notification
   access and runs older, leakier code.

All four are fixed (C1 partially) or have an owner action listed.

## Major security findings

| ID | Severity | Summary |
|----|----------|---------|
| S1 | CRITICAL | The production database credential ships in every APK **and** is committed on a branch of a **public** GitHub repository. Rotate now. |
| S2 | CRITICAL | No server tier: clients write straight into one shared, unpartitioned table. The owner's real transactions are already in it. |
| S11 | HIGH | Real bank SMS (account suffix, PAN fragment, balances, reference numbers, third-party names) committed as test fixtures and docs on public `main`. |
| S3 | HIGH | Every captured SMS and payment notification was broadcast to all apps on the device (**fixed**). |
| S4 | HIGH | Full message bodies were logged to logcat, including WhatsApp chats via the allowlist (**fixed**). |
| S5 | HIGH | Release builds are signed with the debug key. |
| S6 | HIGH | Android backup was enabled for raw SMS and geotags; confirmed on the device (**fixed and re-verified on the device**). |
| S7 | HIGH | Debt ledger exported in plaintext to public storage behind the Play-restricted `MANAGE_EXTERNAL_STORAGE` (**fixed**). |
| S13 | HIGH | The Entire CLI git hooks commit AI-session transcripts to a branch and push them with every `git push`. That is how S1 happened, and unpushed local branches already hold this session's SMS-derived content. **Delete them before your next push.** |

Confirmed security findings: 11. Highly likely but not demonstrated: 2 (S3, the inter-app
broadcast leak, which is now fixed; S9, TLS without certificate verification). Full detail:
[SECURITY_AUDIT.md](SECURITY_AUDIT.md).

## Counts

| Severity | Count |
|----------|-------|
| CRITICAL | 3 |
| HIGH | 13 |
| MEDIUM | 30 |
| LOW | 21 |
| INFO | 2 |
| **Total** | **69** |

Status: 27 fixed, 2 partially fixed, 38 open, 1 accepted, 1 verified-correct.
Documentation mismatches: 10 (DOC1–DOC10). Important undocumented behaviours: 12
([DOCUMENTATION_GAPS.md](DOCUMENTATION_GAPS.md)). Major test gaps: 5 (T1–T5).
Architectural issues: 3 (A1–A3, plus S2).

## What was fixed in this pass

Each fix is small, covered by tests, and kept separate in its own commit. 300 tests pass,
up from 286 (13 new tests plus 1 temporary audit harness that is removed before commit).

- Capture: persisted Live Monitoring (default on), models awaited before capture starts,
  SMS catch-up from a persisted watermark, inbox-only history, stream-error handling,
  truthful Settings copy (C1, C4, C5, C7, C8).
- ML gate: settlement-evidence rule (12-digit RRN/UTR plus a settlement verb, from a
  DLT-registered header or an allowlisted notification). Re-sweeping the real inbox
  recovered exactly the 12 real transactions, with 0 new drops (C2).
- Parser: `debited`/`credited` take precedence, earliest wins (C3).
- Android: package-scoped broadcasts, content-free logs, backup disabled, storage
  permissions removed (S3, S4, S6, S7).
- Smaller fixes: sync interval clamp, optional `.env`, URL-decoded credentials, clearable
  `settledAt`, widget count from the database (C9–C13).
- Tests: production `rootBundle` load path, sklearn-referenced parity fixtures, settlement
  rule, parser precedence, `DebtEntry` (T1, T2).

## Top remediation priorities

1. **Rotate the database credential**, then remove the public checkpoint branch or rewrite
   its history (S1). **Before your next `git push`**, disable the Entire hooks' push and
   delete the local `entire/*` branches (S13). The audit commits were made with hooks
   disabled.
2. Disable sync, or put it behind an authenticated API, before anyone else installs the
   app (S2, S8, S9).
3. Replace real SMS in tests, fixtures and docs with synthetic data; decide on history
   rewrite or repository visibility (S11).
4. Uninstall `com.example.receipt` from the device (O1).
5. Persist notification events natively so they survive the app being closed (C1
   remainder), and fix the allowlist (C21).
6. Add CI; test `LocalDatabase` and the ingestion path directly (T3–T5).

See [REMEDIATION_PLAN.md](REMEDIATION_PLAN.md).

## What remains uncertain

- S3 was not demonstrated with a third-party receiver app; none was built.
- The widget's historical "can't load widget" error (commit `db4fc0a`) was not reproduced.
  The device was in use, so widget placement was not tested. C20 (staleness) is static.
- C19 (SMS permission denial message) was not exercised on the device for the same reason.
- No vulnerability database was available, so D2 reports outdated packages, not CVEs.
- The held-out metrics in the docs (DOC7) were not recomputed. That requires retraining or
  rebuilding the exact split.
- The C1 fix was installed on the device and verified by build and tests. The end-to-end
  run on the device (auto-start, catch-up, live SMS) is still pending phone time; see the
  status in [TEST_AUDIT.md](TEST_AUDIT.md).
