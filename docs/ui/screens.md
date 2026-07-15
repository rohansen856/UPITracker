# Screens

Five screens under [lib/screens/](../../lib/screens/). All transaction screens watch
`TransactionProvider`; Debts watches `DebtProvider`.

## Dashboard (`dashboard_screen.dart`)

Home tab: 24-hour spending hero + recent transactions.

- **Data:** `recent24hTransactions`, `last24hSummary`, `spendingDeltaPct`,
  `last7dSpending`, `last24hCount`, `totalCount`, `isSyncing`, `isListening`.
- **Structure:** `RefreshIndicator` (reloads transactions + summary) →
  `CustomScrollView`:
  - Pinned `SliverAppBar` — `BrandLogo` leading; a green "Live" pill while
    `isListening`; a sync `IconButton` that spins (800 ms `RotationTransition`)
    while `isSyncing`, calls `triggerSync()` and shows the result in a snackbar.
  - `_HeroHeader` — gradient card: "Last 24 hours" + `_TrendBadge`; spent figure
    (30px bold, debit red); received line (green) with txn count; 44px `_Sparkline`
    with "7d ago"/"Today" axis labels.
  - `_TrendBadge` — "no prior data" / "flat vs yday" (|pct| < 0.5) / "±N% vs yday";
    spending up = red, down = green (intentionally inverted).
  - `_Sparkline`/`_Bar` — hand-rolled 7-bar chart; tallest bar full primary, others at
    35% alpha; bar width clamped 4–16px.
  - Body: empty state (faded 72px `BrandLogo` + hint to grant access) or a
    `SliverList` of `TransactionCard`s → tap pushes `TransactionDetailScreen`.

## Transactions (`transactions_screen.dart`)

Full history with search, period chips, an Overview totals card, and a filter sheet
(this screen absorbed the former Analytics screen).

- **Local state:** `_showSearch`, `_searchController`, `_selectedDays` (default **30**,
  applied post-first-frame). `_applyPeriod(days)` sets a `now − days → now` date filter,
  clamping to `provider.startDate`; `null` = All time.
- **Structure:** AppBar (title swaps to an autofocused live-search `TextField`) →
  `_PeriodChips` (Week 7 / Month 30 / 3 Months 90 / Year 365 / All) → `_OverviewCard`
  ("Overview · {period}": Total Spent red / Total Received green / Net signed) →
  list of `TransactionCard`s (loading spinner / empty state variants).
- **AppBar actions:** search toggle (closing clears only the query); filter icon with a
  `Badge` when type/app/from/to filters are set → opens
  [FilterSheet](widgets.md#filtersheet); a clear-filters icon (only when active).

## Transaction detail (`transaction_detail_screen.dart`)

Read/edit view resolved by id from `provider.transactions` (`firstWhere`); shows
"Transaction not found" if absent (deleted or filtered out).

- **Header:** direction avatar (red up / green down arrow), signed amount (32px),
  "PAID"/"RECEIVED" caption, `DateFormat('EEEE, dd MMM yyyy • hh:mm a')`.
- **Info rows** (conditional): counterparty name/UPI id, app display name, source,
  txn id, bank reference, account mask, synced ("Yes"/"Pending"), location name.
- **Note editor** — 3-line `TextField`; saves via a naive 500 ms `Future.delayed`
  debounce (every keystroke schedules a save; not cancelled).
- **Tags editor** — comma-separated field (same debounce) + deletable `Chip` wrap
  (chip deletion saves immediately).
- **Original Message** — `ExpansionTile` revealing `rawText`, when present.
- **Delete** — confirm `AlertDialog` → `deleteTransaction(id)` → pops back.

## Debts (`debts_screen.dart`)

Covered feature-first in [../features/debts.md](../features/debts.md). UI summary:
3-tab layout (All / Owes me / I owe), gradient `_TotalsHeader` (net + mini-stats),
`_PersonCard` list → `_PersonDetailScreen` → `_DebtEntryTile`s with a settle/delete
popup menu; add/edit via the `_DebtFormSheet` modal bottom sheet; FABs on both the main
screen and the person detail screen.

## Settings (`settings_screen.dart`)

`ListView` with section headers: Permissions / Tracking / Cloud Sync / Data / About.
The only screen with platform integrations; uses `WidgetsBindingObserver` to re-check
permissions on app resume (so returning from system settings updates the tiles).

- **Permissions:**
  - Notification Access — checked via
    `NotificationService.isNotificationAccessGranted()`; "Grant" opens the Android
    notification-listener settings page (cannot be requested as a dialog).
  - SMS Access and Location Access (optional) — `permission_handler`
    (`Permission.sms`, `Permission.location`).
  - Tiles show a green check when granted or a "Grant" `OutlinedButton`.
- **Tracking:**
  - Start Date — `showDatePicker` (2016..now, "Ignore transactions before this date")
    → `setStartDate`, with an inline clear button.
  - Live Monitoring — `SwitchListTile` bound to `isListening`
    (`startListening`/`stopListening`).
  - Scan SMS History — `scanSmsHistory()`; trailing spinner while loading.
- **Cloud Sync:** read-only status tile (last sync time + count, or "Not synced yet")
  and a Sync Now tile (disabled while syncing or when `SYNC_ENABLED` is false —
  subtitle "Sync is disabled in .env").
- **Data:** Add Manual Transaction — modal bottom sheet with Paid/Received
  `SegmentedButton`, amount, counterparty, app dropdown (Google Pay / PhonePe / Paytm /
  BHIM / Other), optional note → `addManualTransaction`. Plus a read-only Local Records
  count.
- **About:** static "v1.0.0" tile.
