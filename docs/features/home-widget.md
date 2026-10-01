# Home-screen widget

A 4x2 Android widget showing the last-24-hours spending snapshot with a 7-day
sparkline. Native side:
[SpendingWidgetProvider.kt](../../android/app/src/main/kotlin/com/example/receipt/SpendingWidgetProvider.kt);
Dart side: `TransactionProvider._refreshWidget()`.

## Design: push, don't pull

The widget **never opens SQLite** from its `BroadcastReceiver` (doing so previously
caused "Can't load widget"). Instead, Flutter pushes a self-contained snapshot whenever
summaries reload:

1. `_refreshWidget()` invokes method `updateWidget` on
   `com.upitracker.app/methods` with the payload below (errors swallowed).
2. `MainActivity` persists it via `SpendingWidgetProvider.saveSnapshot()` into the
   SharedPreferences file **`receipt_widget`**, then fires the package-scoped broadcast
   `com.upitracker.app.UPDATE_WIDGET`.
3. `onReceive` triggers `onUpdate` for all widget instances, which re-render from the
   stored snapshot.

## Snapshot payload

| Key | Meaning |
|---|---|
| `spent24h` / `received24h` | Rolling 24h totals |
| `spentPrev24h` | Prior 24h window spend |
| `deltaPct` (+ stored `hasDelta`) | Percent change vs yesterday, may be absent |
| `count24h` | Transaction count in the same 24h window, read from the DB (independent of list filters) |
| `spark7d` | 7 daily debit values (stored as a JSON array string) |
| `updatedAt` | Snapshot timestamp (stored, not rendered) |

## Rendering

`renderWidget` fills `RemoteViews(R.layout.spending_widget_layout)`:

- INR-formatted spent (26sp, red) and received (green), transaction count, date.
- Trend chip: swaps drawables `widget_chip_up` / `widget_chip_down` /
  `widget_chip_neutral` with red/green/gray text.
- 7-bar sparkline drawn onto a size-capped ARGB bitmap (`drawSparkline`, gradient bars,
  max bar highlighted) into the `widget_spark` ImageView.
- Whole card tap opens the app via a launch `PendingIntent`.
- Every external-state path is try/catch-wrapped with a `buildFallback` minimal view
  ("—" / "tap to open").

## Configuration

`res/xml/spending_widget_info.xml`: min 250x150dp (4x2 cells), resizable both axes,
`updatePeriodMillis = 1800000` (30 min system refresh). The system refresh only
re-renders the **last pushed snapshot**: new figures arrive only while the app process is
running. After a day without opening the app the widget still shows the old "last 24
hours" totals, and `updatedAt` is not displayed, so there is no staleness signal. Background: white → light-blue 135°
gradient with 22dp corners (`widget_background.xml`).
