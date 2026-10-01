# Performance & Reliability Audit

Only risks with direct code evidence are listed here. Nothing was profiled except the model
load time on the device.

## Measured

| Metric | Value | Method |
|--------|-------|--------|
| Cold-start load of all three models (debug build) | 161 ms | Temporary on-device instrumentation (reverted) |
| Inference over 3,901 real SMS (host JIT) | < 1 s total | Audit harness |
| Debug APK size | 158 MB | Build output. Debug builds include the JIT; release would be far smaller |

ML inference is not a bottleneck.

## Performance risks

| ID | Risk | Severity |
|----|------|----------|
| P1 | Every insert or filter change reloads the full filtered transaction table, including raw SMS text | MEDIUM |
| P2 | SMS history cursor walk (up to 500 rows) runs on the Android main thread; it now also runs at startup catch-up, though bounded by the watermark | MEDIUM |
| P3 | Fuzzy dedup re-parses every candidate row's raw text with the regex parser for each incoming message | LOW |
| P4 | Live ingestion waits up to 10 s for a GPS fix before inserting | MEDIUM |
| P5 | Sync uploads one row per round trip, with no batching or transaction; an integrity miss re-pushes the entire table; the unsynced query is unbounded | MEDIUM |

## Reliability / failure modes

| Failure | Behaviour | Ref |
|---------|-----------|-----|
| App process not running | SMS: recovered at next launch (fixed). Notifications: lost | C1 |
| Event-channel error | Used to kill capture silently; now stops and reports | C8 |
| Models fail to load | Pipeline fails open (spam passes); now visible in Settings | C5 |
| Postgres connection dropped | Cached dead connection; every sync fails until restart | C17 |
| Partial sync failure | Already-upserted rows stay `synced=0` and are re-sent. Idempotent on `id`, but no rollback | C16 |
| Remote data loss | Count-based check masked by other devices; errors swallowed | C16 |
| SMS permission revoked | Reported as "No new transactions found" | C19 |
| Corrupt debt backup | Used to look like "no backup"; now raises an explicit error | S7 |
| Activity destroyed with active subscriptions | Leaked receivers; a re-subscribe orphans the previous one | C18 |
| `SYNC_INTERVAL_MINUTES=0` | Used to cause a tight loop; now clamped | C9 |

## Observability

The only diagnostics are `debugPrint` calls (stripped from release logs) and snackbars.
There is no crash reporting, no telemetry, and no persisted log of pipeline drops. That is
why the C1 and C2 failures went unnoticed for months. The cheapest improvement is a local
"capture health" panel in Settings: last captured time, drops by stage over the last 7
days, and model load state (load state is now shown).
