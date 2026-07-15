# Database

## Local SQLite (authoritative)

[lib/database/local_database.dart](../../lib/database/local_database.dart) — singleton
`sqflite` wrapper. File `upi_tracker.db` at `getDatabasesPath()`, **schema version 2**.
`onCreate` builds both tables; `onUpgrade` adds `debts` when `oldVersion < 2`.

### `transactions`

```sql
CREATE TABLE transactions (
  id TEXT PRIMARY KEY,
  amount REAL NOT NULL,
  transaction_type TEXT NOT NULL,
  upi_app TEXT,
  upi_transaction_id TEXT,
  bank_reference TEXT,
  counterparty_name TEXT,
  counterparty_upi_id TEXT,
  account_info TEXT,
  description TEXT,
  note TEXT,
  tags TEXT DEFAULT '',
  latitude REAL,
  longitude REAL,
  location_name TEXT,
  source TEXT NOT NULL,
  raw_text TEXT,
  dedup_hash TEXT NOT NULL,
  transaction_date TEXT NOT NULL,
  synced INTEGER DEFAULT 0,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
)
```

Indexes: `idx_dedup(dedup_hash)`, `idx_date(transaction_date)`, `idx_synced(synced)`,
`idx_type(transaction_type)`. Note `dedup_hash` is indexed but **not UNIQUE** —
uniqueness is enforced in app code (`existsByDedupHash` before insert). Dates are
ISO-8601 strings; `source` is `'notification' | 'sms' | 'manual'`.

### `debts` (added in v2)

```sql
CREATE TABLE debts (
  id TEXT PRIMARY KEY,
  direction TEXT NOT NULL,
  counterparty TEXT NOT NULL,
  amount REAL NOT NULL,
  reason TEXT,
  note TEXT,
  created_at TEXT NOT NULL,
  due_date TEXT,
  settled INTEGER DEFAULT 0,
  settled_at TEXT,
  updated_at TEXT NOT NULL
)
```

Indexes: `idx_debts_counterparty(counterparty)`, `idx_debts_direction(direction)`,
`idx_debts_settled(settled)`.

### Transaction DAO

| Method | Behavior |
|---|---|
| `insertTransaction(record)` | `ConflictAlgorithm.ignore` — silent skip on PK collision. |
| `existsByDedupHash(hash)` | LIMIT-1 indexed lookup. |
| `findDedupCandidates({amount, type, from, to})` | Same amount + direction, `transaction_date` in `[from, to]` — feeds the fuzzy dedup tier. |
| `getAllTransactions({typeFilter, appFilter, fromDate, toDate, searchQuery, limit, offset})` | Dynamic AND WHERE; search is `LIKE %q%` across `counterparty_name`, `note`, `tags`, `description`; ordered `transaction_date DESC`. |
| `getTransactionById(id)` / `updateTransaction(record)` / `deleteTransaction(id)` | By primary key. |
| `getUnsyncedTransactions()` | `synced = 0` ordered `created_at ASC`. |
| `markSynced(ids)` | Batch `synced = 1` + fresh `updated_at`. |
| `markAllUnsynced()` | `synced = 0` for every row (sync integrity recovery). |
| `getSummary({fromDate, toDate})` | `{total_spent, total_received, net}` via two `SUM(amount)` queries. |
| `getSpendingByApp({fromDate, toDate})` | Debit-only `GROUP BY upi_app ORDER BY total DESC`. |
| `getDailyTotals({fromDate, toDate})` | `GROUP BY DATE(transaction_date), transaction_type`, ascending. |
| `getTransactionCount()` / `getFirstTransactionId()` / `getLastTransactionId()` | Count; oldest/newest by date (used by the sync integrity probe). |

### Debts DAO

`insertDebt` (upsert via `ConflictAlgorithm.replace`), `updateDebt`, `deleteDebt`,
`getDebtById`, `getAllDebts({settledOnly})` — ordered `settled ASC, created_at DESC`
(outstanding first, newest first).

## Remote Postgres (backup)

[lib/database/remote_database.dart](../../lib/database/remote_database.dart) — singleton
client (`package:postgres`). **Transactions only; debts are never synced.**

- Connection is lazy from `dotenv.env['DATABASE_URL']` (throws if unset), SSL forced
  (`SslMode.require`). URL parsing rewrites `postgresql://` → `http://` and uses `Uri`;
  port defaults 5432; database name defaults to `neondb`; passwords containing colons
  are handled.
- `_ensureTables()` runs once per connection: `CREATE TABLE IF NOT EXISTS transactions`
  mirroring SQLite but with `DOUBLE PRECISION` for amounts/coordinates, `TIMESTAMPTZ`
  for the three date columns, and **no `synced` column** (sync state is local-only).
  Indexes: `idx_remote_dedup(dedup_hash)`, `idx_remote_date(transaction_date)`.
- `syncTransactions(records)` — per-record named-parameter INSERT with
  `ON CONFLICT (id) DO UPDATE SET note = EXCLUDED.note, tags = EXCLUDED.tags,
  updated_at = EXCLUDED.updated_at` (only user-editable fields refresh on re-push).
- `getRemoteCount()`, `existsById(id)` — used by the sync integrity probe.
- `close()` — closes and resets the connection + table-created flag.

`scripts/seed_db.dart` creates the same remote table standalone (plus two extra
indexes `idx_remote_type` / `idx_remote_app`) — see
[../ml-training.md](../ml-training.md#seed_dbdart) for usage.
