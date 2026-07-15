# Deduplication

The same payment often surfaces multiple times — as a UPI app notification plus a bank
SMS, as the same SMS re-delivered from different sender ids (`JD-PHONPE-S`,
`VA-PHONPE-S`, `JM-PHONPE-S`…), or as two differently-worded SMS about the same event
(e.g. an IT refund reported by two SBI systems).
[lib/services/dedup_service.dart](../../lib/services/dedup_service.dart) guarantees the
payment is recorded once — while making sure genuinely distinct back-to-back payments
(four identical wallet debits in a row) are all kept.

## Stored hash: `generateDedupHash(ParsedUpi parsed, String rawText)`

The MD5 hex digest stored on the record, chosen by the first available identifier:

1. **UPI transaction id** present → `md5('txn:<id>')`
2. else **bank reference** present → `md5('ref:<ref>')`
3. else → `md5('body:<normalized body>')` where the body is lowercased and
   whitespace-collapsed (`normalizeBody`)

Reference-bearing hashes ignore time entirely, so the same SMS delivered from two
sender ids produces the same hash. The body hash catches ref-less messages (PhonePe
wallet payments) re-delivered verbatim from another sender id.

## Decision: `isDuplicate(parsed, timestamp, dedupHash)`

Tiered — cheap exact checks first, then a fuzzy candidate comparison:

1. **Exact hash match** — `LocalDatabase.existsByDedupHash` (indexed LIMIT-1 lookup).
   Covers tiers 1–3 above.
2. **Fuzzy candidate scan** — `LocalDatabase.findDedupCandidates` fetches stored
   records with the *same amount and direction* whose transaction date falls in the
   incoming message's day ± 10 minutes. Each candidate is compared by `_isSameEvent`:
   - **Differing refs → distinct.** Two payments with different UPI txn ids / bank
     references are never collapsed.
   - **Balance-after** (`Remaining balance Rs.X`, `Avl Bal Rs X`): if both sides carry
     one, equal balance → duplicate, different balance → distinct. This is what keeps
     four consecutive identical wallet payments apart — only the balance differs.
   - **Second-precision embedded timestamps** (`on May 29, 2026 at 9:38:00 PM`): if
     both sides carry one, equality decides.
   - **Date-only embedded dates** (`on 11/07/26`, `on 2026-07-11`): same day + a
     compatible counterparty → duplicate. This collapses cross-format duplicates like
     the two SBI IT-refund wordings.
   - **Fallback sliding window**: within ±10 minutes of the candidate's stored time
     and a compatible counterparty → duplicate (notification + SMS pair). Unlike the
     old 10-minute *bucket*, this is a true window — events at :09 and :11 dedup.

   "Compatible counterparty" means equal after lowercasing/trimming, or either side
   missing one. Candidates' balance / embedded date are recovered by re-parsing their
   stored `raw_text` (they are not columns).

## Caveats

- `dedup_hash` is indexed (`idx_dedup`) but **not UNIQUE** in SQLite — uniqueness is
  enforced only in app code before insert.
- Manual entries use `manual:<uuid4>` as their dedup hash, so they never hash-collide;
  the fuzzy tier can still dedup an incoming SMS against a matching manual entry.
- Hashing is MD5 via `package:crypto` — fine here since it's a dedup key, not a
  security primitive.
