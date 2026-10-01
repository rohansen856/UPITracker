# Models

## `TransactionRecord`

[lib/models/transaction_record.dart](../../lib/models/transaction_record.dart)

| Field | Type | Notes |
|---|---|---|
| `id` | `String` | UUID v4 |
| `amount` | `double` | |
| `type` | `TransactionType` | debit / credit |
| `upiApp` | `String?` | app code (`gpay`, `phonepe`, `bank_sms`, …) |
| `upiTransactionId` | `String?` | txn id, or bank ref as fallback |
| `bankReference` | `String?` | 10–15 digit ref |
| `counterpartyName` / `counterpartyUpiId` | `String?` | |
| `accountInfo` | `String?` | masked, e.g. `****0587` |
| `description` | `String?` | source text truncated to 200 chars |
| `note` | `String?` | **mutable**, user-editable |
| `tags` | `String` | **mutable**, comma-separated, default `''` |
| `latitude` / `longitude` | `double?` | |
| `locationName` | `String?` | reverse-geocoded |
| `source` | `String` | `'notification' \| 'sms' \| 'manual'` |
| `rawText` | `String?` | original message |
| `dedupHash` | `String` | required — see [deduplication](../features/deduplication.md) |
| `transactionDate` | `DateTime` | |
| `synced` | `bool` | **mutable**, default false |
| `createdAt` / `updatedAt` | `DateTime` | `updatedAt` mutable |

**Serialization:** `toMap()` uses snake_case keys matching the SQLite columns, ISO-8601
dates, `synced` as 1/0. `fromMap()` is the inverse and accepts `synced` as int `1` or
bool `true`.

**`copyWith({note, tags, synced, updatedAt, locationName, latitude, longitude})`** —
only mutable/user-editable fields; identity fields are fixed.

**Helpers:**

- `tagList` — splits `tags` on commas, trims, drops empties.
- `formattedAmount` — `'₹' + amount.toStringAsFixed(2)`.
- `upiAppDisplayName` — code → display name: gpay→Google Pay, phonepe→PhonePe,
  paytm→Paytm, bhim→BHIM, whatsapp→WhatsApp Pay, amazon→Amazon Pay, mobikwik→MobiKwik,
  freecharge→Freecharge, airtel→Airtel Payments, jio→Jio Pay, bank_sms→Bank SMS;
  unknown codes pass through raw; null → "Unknown".

```dart
enum TransactionType { debit('debit'), credit('credit') }
```

`TransactionType.fromValue(String)` defaults to **debit** on unknown values.

## `DebtEntry`

[lib/models/debt_entry.dart](../../lib/models/debt_entry.dart) — one borrow/lend (IOU)
record; settled entries remain as history.

| Field | Type | Notes |
|---|---|---|
| `id` | `String` | UUID v4 |
| `direction` | `DebtDirection` | `owedToMe` / `iOwe` |
| `counterparty` | `String` | person's name (trimmed on add) |
| `amount` | `double` | |
| `reason` / `note` | `String?` | empty strings normalized to null |
| `createdAt` | `DateTime` | |
| `dueDate` | `DateTime?` | |
| `settled` | `bool` | default false |
| `settledAt` | `DateTime?` | set when settling |
| `updatedAt` | `DateTime` | |

All fields are final; `copyWith` allows replacing everything except `id`/`createdAt`.
`copyWith` treats `settledAt: null` as "keep the current value"; pass
`clearSettledAt: true` to remove it. `DebtProvider.toggleSettled` does this when
un-settling, so `settled = 0` rows no longer keep a stale `settled_at`.

Serialization mirrors `TransactionRecord` (snake_case, ISO-8601, `settled` as 1/0;
`fromMap` treats null as 0).

```dart
enum DebtDirection { owedToMe('owed_to_me'), iOwe('i_owe') }
```

`fromValue` defaults to `owedToMe`; `label` is "Owes me" / "I owe".

## Value objects

- `ParsedUpi` ([lib/services/upi_parser.dart](../../lib/services/upi_parser.dart)) —
  parser output; `isValid` requires positive amount + non-null type.
- `LocationData { latitude, longitude, name? }`
  ([lib/services/location_service.dart](../../lib/services/location_service.dart)).
- `SyncResult { success, message, count = 0 }`
  ([lib/services/sync_service.dart](../../lib/services/sync_service.dart)).
- `PersonBalance { name, entries, netAmount }`
  ([lib/providers/debt_provider.dart](../../lib/providers/debt_provider.dart)) — with
  `theyOweMe` (net > 0), `iOweThem` (net < 0), `settled` (|net| < 0.01).
- `PipelineDecision`
  ([lib/services/ml/message_pipeline.dart](../../lib/services/ml/message_pipeline.dart)) —
  see [ML pipeline](../features/ml-pipeline.md).
