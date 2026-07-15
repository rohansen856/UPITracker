# Analytics

All aggregates are computed by SQL in
[lib/database/local_database.dart](../../lib/database/local_database.dart) and exposed
through [lib/providers/transaction_provider.dart](../../lib/providers/transaction_provider.dart).
There is no separate analytics screen — the former one was absorbed into the
Transactions screen (Overview card + period chips); the Dashboard shows the 24-hour view.

## SQL aggregates

- `getSummary({fromDate, toDate})` → `{total_spent, total_received, net}` — two
  `SUM(amount)` queries split by `transaction_type`; `net = credit − debit`.
- `getSpendingByApp({fromDate, toDate})` — debit-only, `GROUP BY upi_app`, descending.
- `getDailyTotals({fromDate, toDate})` — `GROUP BY DATE(transaction_date),
  transaction_type`, ascending.

## Provider-level windows

Loaded together by `loadSummary()` (which ends by refreshing the home-screen widget):

| Getter | Window |
|---|---|
| `summary` | Current filter range (clamped to the tracking start date). |
| `last24hSummary` / `todaySummary` | Rolling `now − 24h → now` (todaySummary is an alias). |
| `prev24hSummary` | `now − 48h → now − 24h`. |
| `spendingDeltaPct` | Percent change of 24h spend vs the prior window; **null when the prior window's spend ≤ 0** (rendered as "no prior data"). |
| `last7dSpending` | 7 daily debit buckets, oldest → today, zero-filled for missing days (`_bucketDailySpending`) — feeds the Dashboard sparkline and the widget. |
| `last24hCount` / `recent24hTransactions` | Count and list for the Dashboard. |
| `spendingByApp` | Per-app debit totals. |

## Filters

`setFilters({typeFilter, appFilter, fromDate, toDate, searchQuery})` /
`clearFilters()` drive `getAllTransactions`, which builds a dynamic AND WHERE; search
is `LIKE %q%` across `counterparty_name`, `note`, `tags`, `description`; results are
ordered `transaction_date DESC`.

The effective lower date bound is always the **later** of the user's `fromDate` filter
and the global tracking start date (`_effectiveFromDate`) — so a "Month" period chip on
a two-week-old install only shows those two weeks.

## Presentation

- **Dashboard hero card** — 24h spent (red) / received (green), a trend badge
  ("±N% vs yday", "flat" when |pct| < 0.5, "no prior data" when null; up = red,
  down = green — deliberately inverted for spending), and a hand-rolled 7-bar
  sparkline (tallest bar highlighted). No chart package.
- **Transactions Overview card** — Total Spent / Total Received / Net for the selected
  period chip (Week 7 / Month 30 / 3 Months 90 / Year 365 / All).
- Currency formatting is Indian-style lakh grouping via
  `NumberFormat('#,##,###.##')` throughout.
