# Navigation & theme

## Navigation shell

[lib/app.dart](../../lib/app.dart) — `AppShell`, a `StatefulWidget` holding
`_currentIndex` over an **`IndexedStack`**, so every tab keeps its state (scroll
positions, filters, tab controllers) across switches. No router; tab switches are
`setState`, and all deeper navigation is `Navigator.push(MaterialPageRoute(...))` on
top of the shell.

Material 3 `NavigationBar` destinations (outlined/filled icon pairs):

| Tab | Screen |
|---|---|
| Home | `DashboardScreen` |
| Transactions | `TransactionsScreen` |
| Debts | `DebtsScreen` (handshake icons) |
| Settings | `SettingsScreen` |

Detail screens receive **ids/names, not objects** (`TransactionDetailScreen(transactionId)`,
`_PersonDetailScreen(name)`) and re-resolve from the provider so they live-update.
Everything else is modal: bottom sheets (filters, debt form, manual transaction),
`AlertDialog`s (all deletions), `showDatePicker` (start date, filter range, due date).

## Theme

[lib/config/theme.dart](../../lib/config/theme.dart) — static `AppTheme` exposing
`lightTheme` / `darkTheme`. Both are registered in `MaterialApp`, but
[lib/main.dart](../../lib/main.dart) pins `themeMode: ThemeMode.light`, so dark theme
is currently unreachable.

**Palette:**

- Seed/primary `0xFF0D47A1` (deep blue), secondary `0xFF00897B` (teal),
  error `0xFFD32F2F`; schemes via `ColorScheme.fromSeed`.
- Semantic colors used app-wide: `AppTheme.debitColor = 0xFFE53935` (red, money out)
  and `AppTheme.creditColor = 0xFF43A047` (green, money in).

**Component theming** (`useMaterial3: true`, `fontFamily: 'Roboto'`; light/dark differ
only in card border alpha 0.5 vs 0.3):

- AppBar: left-aligned title, elevation 0, `scrolledUnderElevation: 1`.
- Cards: elevation 0, 16px radius, hairline `outlineVariant` border (flat outlined look).
- Inputs: filled `surfaceContainerLow`, 12px radius, borderless.
- Chips 8px radius; NavigationBar `primaryContainer` indicator, labels always shown;
  FAB in `primaryContainer`, 16px radius; bottom sheets with drag handle + 20px top
  radius; floating snackbars, 8px radius.

**Visual language across screens:** debit red / credit green everywhere, gradient
primary-tinted hero cards (Dashboard, Debts), tinted circle avatars with directional
arrows, Indian number formatting (`NumberFormat('#,##,###.##')`). One inconsistency:
Settings uses hardcoded `Colors.green` for the granted-permission state instead of
`AppTheme.creditColor`.
