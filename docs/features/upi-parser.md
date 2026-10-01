# UPI parser

[lib/services/upi_parser.dart](../../lib/services/upi_parser.dart) — a pure-regex,
dependency-free engine that turns notification/SMS text into a structured `ParsedUpi`.
All methods are static.

## `ParsedUpi`

Nullable fields: `amount`, `type`, `counterpartyName`, `counterpartyUpiId`,
`upiTransactionId`, `bankReference`, `accountInfo`, `description`, `upiApp`,
`balanceAfter`, `embeddedDate` (+ `embeddedDateHasTime`, default `false`).

`balanceAfter` and `embeddedDate` exist for the dedup fuzzy tier: two otherwise
identical messages with different remaining balances (consecutive wallet payments) or
different embedded timestamps are distinct payments; equal values identify the same
event re-reported.

```dart
bool get isValid => amount != null && amount! > 0 && type != null;
```

Only records with a positive amount **and** a detected direction are ingested.

## Entry points

- `parseNotification({packageName, title, text})` — app resolved from the Android
  package (falls back to `'unknown'`); parses `'$title $text'`.
- `parseSms({sender, body})` — app resolved from the SMS sender id (falls back to
  `'bank_sms'`).
- Both delegate to `_parseText(text, app)`, which runs every extractor and sets
  `upiTransactionId = txnId ?? ref` and `description` = text truncated to 200 chars.
- `isUpiRelated(text)` — the cheap prefilter used before the ML gate. Keywords:
  `upi, paid, received, debited, credited, payment, transaction, ₹, rs., inr, gpay,
  phonepe, paytm, bhim, trf to, transfer from, refno, ref no, neft, imps, credit,
  debit, refund, wallet`. The last four admit refund credits ("has credit for ITDTAX
  REFUND") and wallet payments; the ML gate handles precision.

## App identification

`identifyAppFromPackage` (notification path):

| Package | Code |
|---|---|
| `com.google.android.apps.nbu.paisa.user` | `gpay` |
| `net.one97.paytm` | `paytm` |
| `com.phonepe.app` | `phonepe` |
| `in.org.npci.upiapp` | `bhim` |
| `com.whatsapp` | `whatsapp` |
| `com.amazon.mShop.android.shopping` | `amazon` |
| `com.mobikwik_new` | `mobikwik` |
| `com.freecharge.android` | `freecharge` |
| `com.myairtel.myairtelapp` | `airtel` |
| `com.jio.myjio` | `jio` |

`identifyAppFromSender` (SMS path) — uppercase substring checks, in order:
GPAY/GOOGLE → `gpay`, PAYTM, PHONEPE/**PHONPE**/**PHNEPE** (real sender ids are
`JM-PHONPE-S`, `VA-PHONPE-S`, …), BHIM,
AMAZON, then banks: SBI, HDFC, ICICI, AXIS, BOB/BARODA → `bob`, PNB, KOTAK, UNION,
CANARA, INDIAN → `indianbank`. Unknown senders → `null` → caller uses `bank_sms`.

## Extraction rules

### Direction (`_detectType`)

Lowercased keyword scan. The account settlement verbs come first: if `debited` and/or
`credited` occur, **the earlier one decides** ("A/c debited and Rs.X added to your UPI
Lite" is a debit; "Rs.X credited to a/c … debited from VPA …" is a credit). Otherwise
the weaker keyword lists apply, **credit checked first** ("credited" is more specific
than "credit"):

- credit: `credited, received, credit, refund, cashback, received from,
  money received, you received, added to`
- debit: `debited, paid, sent, debit, transferred, payment of, spent, charged,
  purchase, you paid, you sent, payment successful, money sent, sent to, trf to`

Returns `null` if neither matches → record invalid.

### Amount (`_extractAmount`)

Ordered most-specific first; first match with a positive parse wins (commas stripped):

```dart
RegExp(r'₹\s*([\d,]+\.?\d{0,2})')                                                  // ₹1,200.50
RegExp(r'Rs\.?\s*([\d,]+\.?\d{0,2})', caseSensitive: false)                        // Rs.20.00
RegExp(r'INR\s*([\d,]+\.?\d{0,2})', caseSensitive: false)                          // INR 500
RegExp(r'(?:debited|credited)\s+by\s+(?:Rs\.?\s*)?([\d,]+\.?\d{0,2})', ...)        // SBI "debited by 50.00"
RegExp(r'Rupees\s*([\d,]+\.?\d{0,2})', caseSensitive: false)                       // Rupees 500
```

Handles Indian comma grouping (`1,50,000.00`).

### Counterparty (`_extractCounterparty`)

App/bank-specific patterns first (most precise):

```dart
RegExp(r'trf\s+to\s+(.+?)\s+(?:Refno|Ref\s*No|If\s+not)', ...)        // SBI debit: "trf to M S SURINDER KUM Refno …"
RegExp(r'transfer\s+from\s+(.+?)\s+(?:Ref\s*No|Refno|-SBI|$)', ...)   // SBI credit: "transfer from TUMULURI ABHIRAM Ref No …"
// PhonePe wallet / gift card: "via PhonePe gift card to SWIGGY on May 29 …",
// "via PhonePe wallet for City Mens Parlour. Not you? …". Names may contain
// dots ("Mr.Sharma", "H.A Associates"), so termination is " on <date>" or
// a period followed by whitespace/end.
RegExp(r'via\s+PhonePe\s+(?:gift\s*card|wallet)\s+(?:to|for)\s+(.+?)(?:\s+on\s+|\.\s|\.$|$)', ...)
```

Then generic patterns, chosen by direction — debit: `paid/sent … to <name>` and
`to <Capitalized Name>`; credit: `from <Capitalized Name>` — each terminated by
`.` / end / ` on ` / ` via ` / ` UPI` / ` using` / ` Ref`. Extracted names are scrubbed
of currency *amounts* as whole tokens (`₹500`, `Rs. 1,200.50` — not a character class,
which would eat the R/s from names like "Rohit"), and must be non-empty and shorter
than 60 chars.

### References and IDs

```dart
// Bank reference: 10–15 digits, three variants
RegExp(r'Ref\s*(?:No|no|NO)?\.?\s*(\d{10,15})', caseSensitive: false)
RegExp(r'Refno\s*(\d{10,15})', caseSensitive: false)          // SBI style
RegExp(r'UPI\s*Ref[:\s.#No]*\s*(\d{10,15})', caseSensitive: false)

// Transaction ID
RegExp(r'(?:txn\s*(?:id|ID|Id)[:\s]*|Transaction\s*ID[:\s]*)([A-Za-z0-9]+)', ...)
```

### UPI / VPA id (`_extractUpiId`)

Candidate pattern `([a-zA-Z0-9._-]+@[a-zA-Z]{2,})`, accepted **only** if the handle
contains a known UPI suffix — `@ok`, `@ybl`, `@paytm`, `@upi`, `@icici`, `@sbi`,
`@axl`, `@ibl`, `@apl` — filtering out email false-positives like `@gmail.com`.

### Account mask (`_extractAccount`)

```dart
RegExp(r'A/[Cc]\s*[Xx]*(\d{4,})', caseSensitive: false)              // "A/C X0587"
RegExp(r'(?:a/c|ac|account)\s*[*Xx]*(\d{4,})', caseSensitive: false) // "a/c **1234"
```

Rendered as `****<digits>`.

### Balance after transaction (`_extractBalance`)

Most specific first; commas stripped:

```dart
RegExp(r'Remaining\s+balance\s*:?\s*(?:Rs\.?|₹|INR)\s*([\d,]+(?:\.\d+)?)', ...)  // PhonePe wallet/gift card
RegExp(r'Avl\s+Bal(?:ance)?\s*:?\s*(?:Rs\.?|₹|INR)\s*([\d,]+(?:\.\d+)?)', ...)   // SBI "Avl Bal Rs 79,593.25"
RegExp(r'\bBal(?:ance)?\s*:?\s*(?:Rs\.?|₹|INR)\s*([\d,]+(?:\.\d+)?)', ...)       // generic "Bal INR 23,456.78"
```

### Embedded transaction date (`_extractEmbeddedDate`)

Returns `(DateTime, hasTimePrecision)`. The with-time pattern is checked first:

- `on May 29, 2026 at 9:38:00 PM` (PhonePe gift card, 12-hour clock) → second
  precision, `hasTime = true`
- date-only, first match wins: `on date 12Jul26` (SBI debit), `on 10-Apr-26` (ICICI),
  `on 2026-07-11` (ISO), `on 11/07/26` (dd-mm-yy) → midnight, `hasTime = false`

## Supported formats

Regression-tested against the real corpus in `data/upi*.csv` (382 SMS) and curated
samples: SBI debits/credits ("debited by", "trf to", "transfer from"), SBI IT-refund
credits (both wordings), HDFC ("Sent Rs. …"), ICICI, Axis, Kotak, PNB,
GPay/PhonePe/Paytm notifications and SMS, PhonePe wallet and gift-card payments,
NEFT receipts. See [../testing.md](../testing.md) for the corpus guarantees
(100% of real UPI SMS ingested).
