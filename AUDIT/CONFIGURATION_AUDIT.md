# Configuration / Deployment Audit

The project has no server-side deployment: no Dockerfile, Compose, Kubernetes, Terraform
or CI. "Deployment" here means building and side-loading the Android APK, plus the
externally hosted Neon Postgres instance.

## Environment variables (`.env`, bundled as a Flutter asset)

| Variable | Read by | Behaviour |
|----------|---------|-----------|
| `DATABASE_URL` | `remote_database.dart:16` | Hand-parsed; query options are ignored; credentials are now URL-decoded (C12) |
| `SYNC_ENABLED` | `sync_service.dart:21` | Sync runs only if it is exactly `true` (case-insensitive) |
| `SYNC_INTERVAL_MINUTES` | `sync_service.dart:23` | Defaults to 15. Values ≤ 0 used to spin the timer and are now clamped (C9) |

"Secure in theory vs as deployed": the docs treat `.env` as local configuration, but the
asset declaration ships it inside every build (S1). `.env` is now loaded with
`isOptional: true` (C13), so dropping it from `assets:` leaves the app working with sync
disabled. That is the minimum safe deployment until an API exists (S2).

## Android build (`android/app/build.gradle.kts`)

| Setting | Value | Assessment |
|---------|-------|------------|
| `applicationId` / `namespace` | `com.upitracker.app` | Consistent with the Kotlin `package` declarations; the source directory is stale (A2) |
| `minSdk` | 26 | Fine |
| `targetSdk` / `compileSdk` | inherited from Flutter (36) | Unpinned; changes with Flutter upgrades (O2) |
| Release signing | debug keystore | S5 |
| Minify / shrink | off | O2. Before the S4 fix, this also meant logs with message content shipped in release builds |

## Manifest (after fixes)

- Permissions: `READ_SMS`, `RECEIVE_SMS`, fine and coarse location, `INTERNET`,
  `ACCESS_NETWORK_STATE`, and the unused `RECEIVE_BOOT_COMPLETED` and
  `FOREGROUND_SERVICE` (S12). The staged `WRITE_EXTERNAL_STORAGE` and
  `MANAGE_EXTERNAL_STORAGE` were removed (S7).
- `allowBackup="false"`, `fullBackupContent="false"`, and `dataExtractionRules` excluding
  every domain (S6). Verified on the device.
- No `usesCleartextTraffic`. There is no HTTP; Postgres traffic is raw TCP/TLS (S9).

## Device / installation state

Two builds are installed side by side (O1). The pre-rename `com.example.receipt` keeps
SMS permissions, notification-listener access and backup enabled. Uninstall it.

## Repository configuration

- `.gitignore` correctly excludes `.env`, `data/*`, `.venv-ml/`, `.entire`, build
  outputs, and (now) `__pycache__/`.
- The `.entire` ignore rule does not stop the tool's own **branch** from being pushed (S1).
- No CI (T4); no branch protection could be inspected.
