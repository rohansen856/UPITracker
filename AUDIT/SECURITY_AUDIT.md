# Security Audit

Finding detail lives in [FINDINGS.md](FINDINGS.md); this document gives the threat model,
what was examined, and the conclusions per area. Secret values and personal data are
deliberately not reproduced.

## Assets and trust boundaries

| Asset | Where it lives |
|-------|----------------|
| Bank SMS bodies (incl. OTPs), payment-app notification text | Android SMS provider → app process → SQLite `raw_text` |
| Parsed transactions, counterparties, balances | SQLite; synced to shared Postgres |
| Precise location + place name per purchase | SQLite; synced to shared Postgres |
| Debt ledger (names, amounts, notes) | SQLite; JSON export file |
| Postgres credential | `.env` → Flutter asset → every APK; also public git branch |

Boundaries: (1) other apps on the device ↔ this app's components and broadcasts;
(2) the device ↔ the Postgres server (no API in between); (3) the repository ↔ the public
internet (GitHub repository is public).

There is no user authentication anywhere: the app has no accounts, and the database has
a single shared role. Authorization therefore reduces to "whoever holds the credential
can do anything" (S1, S2).

## Area-by-area conclusions

**Authentication / authorization.** None exists. Every install uses the same database
role; the remote schema has no owner column; any holder of the credential can read,
modify or delete all rows of all users (S2). Not mitigable on the client.

**Secrets.** `.env` is gitignored but declared as a Flutter asset, so it is packaged into
every build (verified in the debug APK). Independently, two agent-transcript commits on
`entire/checkpoints/v1` contain the connection string; that branch is live on the public
GitHub remote (S1). `.gitignore`'s `.entire` entry only hides the working directory, not
the branch. No other credentials were found in tracked files or `main` history
(`git log -S` for the host/role name only matched those two commits).

**Personal data in the repository.** Real bank SMS were copied into tests, fixtures,
docs and parser comments on public `main`, and raw SMS appear in the checkpoint
transcripts (S11). This is the same data the `.gitignore` comment says must never be
committed.

**Inter-app exposure on the device.** Captured SMS and notifications were re-broadcast
with implicit intents (S3) and logged verbatim (S4); the notification allowlist includes
WhatsApp, so chat messages took the same path (C21). Both fixed: broadcasts are
package-scoped and logs carry only lengths. The dynamic receivers in `MainActivity` are
registered `RECEIVER_NOT_EXPORTED`; `SmsReceiver` requires `BROADCAST_SMS` and the
listener requires `BIND_NOTIFICATION_LISTENER_SERVICE` — correct. The widget provider
accepts an unprotected custom action (S10, low impact).

**Data at rest / backup.** SQLite is unencrypted (normal for app-private storage), but
`allowBackup` defaulted to true, exporting it to cloud backup (S6, verified and fixed on
device). Debt export went to public storage with All-files access (S7, fixed by moving to
app-specific storage; trade-off documented).

**Transport.** `SslMode.require` encrypts without verifying the server certificate, and
URL query options such as `channel_binding` are discarded by the hand-rolled parser (S9).
Sync errors (including driver messages) are shown in a snackbar — LOW, not separately
listed.

**Injection.** No SQL injection found. Local queries use `whereArgs`; dynamic `WHERE`
fragments are assembled only from literals; the remote driver uses named parameters.
The native `readSmsHistory` puts `LIMIT $limit` into the sort order, but `limit` is an
integer from the channel. The user-supplied search term is passed as a bound `LIKE`
argument (wildcards in the user's own search are cosmetic).

**Cryptography.** MD5 is used only for dedup keys (non-security use); acceptable. UUIDs
are v4. No custom crypto.

**Build / distribution.** Release signed with the debug key (S5); no R8/minification
(O2); unused `RECEIVE_BOOT_COMPLETED` / `FOREGROUND_SERVICE` permissions (S12).

**Device state.** A stale pre-rename build (`com.example.receipt`) still holds SMS and
notification-listener access with backup enabled (O1).

**Logging / monitoring.** No security events are recorded and there is no remote
telemetry; abuse of the shared database would be undetectable from the app's side.

## Exploitability summary

| ID | Precondition | Demonstrated? |
|----|--------------|---------------|
| S1 | Obtain any APK, or browse the public branch | Credential presence verified in APK and on the public remote; the database was **not** accessed during this audit |
| S2 | Credential from S1 | Inferred from schema + client design; no remote access performed |
| S3 | Malicious app installed and running | Static only |
| S4 | adb/logcat or bug-report access | Static |
| S6 | Backup transport / device transfer | Flag confirmed via `dumpsys` |
| S11 | Internet access | Verified with `git grep` on `origin/main` |

## Verified-not-vulnerable checks

Manifest component guards (above), SQL parameterization, absence of WebViews / dynamic
code loading / deep links, `PendingIntent` uses `FLAG_IMMUTABLE`
(`SpendingWidgetProvider.kt:189-198`), no cleartext HTTP (no HTTP client at all).
