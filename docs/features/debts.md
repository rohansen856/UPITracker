# Debts & lending

A manual IOU ledger, fully separate from UPI transactions — a first-class bottom-nav
tab, though absent from the top-level README. Deliberately independent of
`TransactionProvider` because manual IOUs have a different lifecycle: **local-only**
(never synced to Postgres), no dedup, no ML, no parsing.

Files: [lib/models/debt_entry.dart](../../lib/models/debt_entry.dart),
[lib/providers/debt_provider.dart](../../lib/providers/debt_provider.dart),
[lib/screens/debts_screen.dart](../../lib/screens/debts_screen.dart), `debts` table in
[lib/database/local_database.dart](../../lib/database/local_database.dart)
(added in schema v2 — see [../data/database.md](../data/database.md)).

## Model

`DebtEntry` (all fields final): `id` (UUID), `direction`, `counterparty` (person name),
`amount`, `reason?`, `note?`, `createdAt`, `dueDate?`, `settled` (default false),
`settledAt?`, `updatedAt`. Settled entries stay in the list as history.

```dart
enum DebtDirection { owedToMe('owed_to_me'), iOwe('i_owe') }
```

`fromValue` defaults to `owedToMe`; `label` renders "Owes me" / "I owe".

Known quirk: `copyWith` uses `?? this.settledAt`, so passing `settledAt: null` cannot
clear it — un-settling an entry corrects the `settled` flag but the stale `settledAt`
timestamp survives.

## `DebtProvider`

State: `debts`, `isLoading`, `error`. Aggregates:

- `outstanding` — unsettled entries only.
- `totalOwedToMe` / `totalIOwe` — sums of unsettled amounts per direction.
- `net` — `totalOwedToMe − totalIOwe` (positive = you are a net lender).
- `peopleBalances` — groups **unsettled** entries by trimmed counterparty name into
  `PersonBalance { name, entries, netAmount }` (signed: + for owed-to-me, − for I-owe),
  entries newest-first, people sorted by `|net|` descending. `PersonBalance.settled`
  uses a 0.01 float tolerance.
- `entriesFor(name)` — all entries (settled + outstanding) for one person,
  case-insensitive match, newest first. (Note: grouping in `peopleBalances` is
  case-sensitive, unlike this lookup.)

Mutations (each persists then reloads): `add({direction, counterparty, amount, reason,
note, dueDate})` (UUID v4, trims name, empty reason/note → null),
`update(entry)` (stamps `updatedAt`), `toggleSettled(id)` (sets `settledAt = now` when
settling; see the quirk above for un-settling), `remove(id)`.

Persistence goes through the `LocalDatabase` debts DAO — `insertDebt` is an upsert
(`ConflictAlgorithm.replace`); `getAllDebts` orders `settled ASC, created_at DESC` so
outstanding entries come first.

## UI flow

`DebtsScreen` — three tabs (**All / Owes me / I owe**) over per-person cards, a gradient
totals header (net amount + "Owes me"/"I owe" mini-stats), pull-to-refresh, and an
"Add entry" FAB opening `_DebtFormSheet`.

- **`_PersonCard`** → tap → `_PersonDetailScreen`: per-person net summary (recomputed
  locally so it stays correct while settling/removing with the screen open), entry
  tiles, and an "Add for this person" FAB (pre-fills the counterparty).
- **`_DebtEntryTile`** — strikethrough + 55% opacity when settled; shows reason (or
  "Lent to X"/"Borrowed from X" fallback), created/due/settled dates, note, signed
  amount. Tap opens the form in edit mode; a popup menu offers
  "Mark settled/unsettled" and "Delete" (confirm dialog).
- **`_DebtFormSheet`** — direction `SegmentedButton` ("They owe me" / "I owe"),
  required person + amount (> 0), optional reason/note, due-date picker (2 years back
  to 5 years ahead) with inline clear, plus Delete in edit mode.

## JSON backup

`DebtBackupService` (`lib/services/debt_backup_service.dart`) exports every entry to
`UPITracker/debts_ledger.json` as pretty-printed JSON
`{version: 1, exported_at, debts: [DebtEntry.toMap()…]}`.

- **Location:** on Android the app-specific external directory
  (`getExternalStorageDirectory()` → `Android/data/com.upitracker.app/files/`); elsewhere
  the app documents directory. No storage permission is needed and other apps cannot read
  it. The file is **plaintext** and is **deleted when the app is uninstalled** — copy it
  elsewhere to keep it.
- **Export** — the download icon in the Debts app bar. Write failures surface as a
  snackbar (`DebtBackupException`).
- **Restore** — when the backup contains ids missing locally, the Debts screen shows a
  restore banner. `DebtProvider.restoreFromBackup()` upserts by id: unknown ids are
  inserted, existing ids are **overwritten by the backup version** without comparing
  `updated_at`. Entries are written one by one (no transaction).
- A backup that exists but cannot be parsed raises `DebtBackupException` ("Backup file is
  unreadable") instead of being treated as "no backup".
