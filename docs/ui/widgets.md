# Reusable widgets

Four components under [lib/widgets/](../../lib/widgets/).

## TransactionCard

[transaction_card.dart](../../lib/widgets/transaction_card.dart) — the list row used by
Dashboard and Transactions. `Card` → `InkWell` (caller supplies `onTap`) → `Row`:

- Leading `CircleAvatar`: up-arrow red for debits, down-arrow green for credits
  (10% alpha background).
- Middle: counterparty name (ellipsized, "Unknown" fallback); app badge pill
  (`upiAppDisplayName` on 50%-alpha `secondaryContainer`) + `dd MMM, hh:mm a`
  timestamp; optional single-line note.
- Trailing: signed `₹` amount in the debit/credit color, and a small `cloud_off` icon
  when `synced` is false (pending cloud sync).

## FilterSheet

[filter_sheet.dart](../../lib/widgets/filter_sheet.dart) — modal bottom sheet for the
Transactions filters. Copies the provider's current filters into local state in
`initState`, so edits are **uncommitted until Apply**.

- **Type** — `SegmentedButton<String?>`: All / Spent (`'debit'`) / Received (`'credit'`).
- **App** — single-select `FilterChip` wrap: All, GPay, PhonePe, Paytm, BHIM,
  Bank (`bank_sms`), Other.
- **Date range** — From/To `showDatePicker` buttons (2020..now) plus quick-pick
  `ActionChip`s: Today, This Week (Monday-based), This Month.
- **Footer** — "Clear All" (`clearFilters()` + pop) and "Apply" (`setFilters(...)` + pop).

## BrandLogo

[brand_logo.dart](../../lib/widgets/brand_logo.dart) — squircle app-icon avatar
(primary tint at 10% alpha, 15%-alpha border, radius `size * 0.26`) wrapping
`assets/branding/app_icon.png`. Params: `size` (default 28), optional `margin`,
`padding` (default 3). Used as the AppBar leading on Dashboard, Transactions and Debts,
and at size 72 in the Dashboard empty state. Purely decorative.

## SummaryCard (currently unused)

[summary_card.dart](../../lib/widgets/summary_card.dart) — generic stat card (tinted
icon avatar, title, ₹ amount in a given color). **No screen uses it** — Dashboard and
Transactions have their own private `_HeroHeader`/`_OverviewCard`. It is still covered
by `test/widgets/summary_card_test.dart`; treat it as legacy/deletable.
