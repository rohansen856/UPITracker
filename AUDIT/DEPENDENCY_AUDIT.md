# Dependency / Supply-Chain Audit

## Dart / Flutter

Toolchain: Flutter 3.41.6 stable, Dart 3.11.4 (`pubspec.yaml` constrains the SDK to
`^3.11.4`). `pubspec.lock` is committed.

`flutter pub outdated` output for direct dependencies at audit time:

| Package | Locked | Latest | Notes |
|---------|--------|--------|-------|
| postgres | 3.5.9 | 3.5.19 | **Security-relevant** (TLS, SCRAM auth). Upgradable within the current constraint |
| permission_handler | 11.4.0 | 13.0.2 | Major version behind |
| geolocator / geocoding | 13.0.4 / 3.0.0 | 14.1.1 / 5.0.0 | Major versions behind |
| flutter_dotenv | 5.2.1 | 6.0.1 | Major version behind; `isOptional` is used by the fix and exists in 5.2 |
| connectivity_plus | 6.1.5 | 7.3.2 | Major version behind |
| sqflite, path_provider, shared_preferences, intl, uuid | patch/minor behind | — | Routine |

74 packages, including transitive ones, have newer versions. **No CVE lookup was
possible**, because no vulnerability database or `osv-scanner` was available here. These
are outdated-package observations, not confirmed vulnerabilities (D2).

Usage check: every direct dependency is imported by `lib/`. `crypto`, `connectivity_plus`,
`geocoding` and `permission_handler` are each used by exactly one file. `mockito` is a dev
dependency imported by one test file that uses nothing from it (the analyzer flags the
import as unnecessary), and `build_runner` has no `@GenerateMocks` to process. Both are
removable. No suspicious or typosquat-like package names were found. All packages come
from pub.dev.

Gradle: AGP 8.11.1, Kotlin 2.2.20, Gradle 8.14. The app module declares no extra
dependencies.

## Python (training)

`scripts/` imports scikit-learn and numpy. There is **no `requirements.txt` or
`pyproject.toml`** (D1). The local `.venv-ml` (gitignored) has scikit-learn 1.9.0 and
numpy 2.5.1. Retraining on another machine could produce different weights without anyone
noticing. The new sklearn-referenced fixtures will detect *inference* drift, but not
*training* drift.

## Risk summary

- The highest supply-chain-adjacent risk is not a package. It is the **agent-transcript
  branch** (`entire/checkpoints/v1`) being pushed to a public remote with secrets and
  personal data inside (S1, S11). The tooling that produces `.entire/` needs an explicit
  "never push" policy.
- Upgrade `postgres` within its constraint first. Schedule the major upgrades with
  on-device regression runs, since `permission_handler`, `geolocator` and
  `connectivity_plus` have Android-behaviour changes between majors.
