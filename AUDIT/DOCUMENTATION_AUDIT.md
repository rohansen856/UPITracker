# Documentation ↔ Implementation Audit

The `docs/` tree is unusually accurate overall: the schema DDL, index names, conflict
clauses, channel names and payload keys, dedup tiers, and the documented quirks all matched
the code. The discrepancies below matter more because of that, since readers will trust
the rest.

Classification uses the taxonomy from the brief. "Fixed" means the code or the doc was
changed in this audit; the earlier text is preserved in git history.

| ID | Claim (location) | Reality | Classification | Resolution |
|----|------------------|---------|----------------|------------|
| DOC1 | "Sync is bidirectional-safe" (`README.md:27-29`, `:214`) | Strictly push-only; nothing is ever read back (`docs/features/sync.md` is correct) | DOCUMENTATION IS INCORRECT | README corrected |
| DOC2 | Dedup key = hash of "amount + 10-minute window + counterparty" (`README.md:24-26`) | md5 of `txn:` → `ref:` → normalised body; amount/window/counterparty belong to the separate fuzzy tier | DOCUMENTATION IS OUTDATED | README corrected |
| DOC3 | Capture broadcasts are "internal" (`docs/android/native-layer.md:38-39,59`; `platform-channels.md:68-74`) | They were implicit, system-wide broadcasts (S3) | IMPLEMENTATION DIFFERED FROM DOCUMENTATION (security property) | Code fixed to match the docs; wording made explicit |
| DOC4 | App "reads notifications and SMS in real time" (`docs/README.md`, README overview) | Capture was off after every launch, and nothing is received while the app is closed (C1) | IMPLEMENTATION DIFFERED FROM DOCUMENTATION | Code fixed for SMS (auto-start + catch-up); the notification gap is documented |
| DOC5 | "381/381 real UPI SMS ingested (100%)" (`README.md:131-141`, `docs/ml-training.md:109-111`) | Holds on the training corpus only; an independent real inbox lost 12 real transactions (C2) | DOCUMENTATION IS INCORRECT (overclaim) | Qualified; settlement rule added |
| DOC6 | Direction model 33.7 KB / 641 features; transactional 157.0 KB; payload 344 KB (`README.md:58,67`; `ml-pipeline.md:4`) | 38.1 KB / 731 features; 158.9 KB; ~350 KB | DOCUMENTATION IS OUTDATED | Corrected |
| DOC7 | Held-out metrics (`README.md:126-128,141` vs `docs/ml-training.md:105-111`) | The two documents disagree with each other (e.g. spam recall 0.917 vs 0.921, min P(tx) 0.571 vs 0.615, "382" vs "381/381") | BOTH REQUIRE CLARIFICATION | **Marked for human decision.** Not recomputed: that requires a pinned retraining run |
| DOC8 | SYNTHETIC_CREDITS = 21; CURATED_SPAM ×3; ~255 tests; fixtures 13/15/12 (`ml-training.md:33,60`; `testing.md`) | 20; ×2; 286 (now 299); 17/24/16 | DOCUMENTATION IS OUTDATED | Corrected |
| DOC9 | "~98% of decisions short-circuit at layer 1 (~5 µs/message)" (`ml-pipeline.md:26-27`) | No benchmark exists; most UPI messages pass all three layers | DOCUMENTATION IS AMBIGUOUS | Removed |
| DOC10 | Debts docs and the setup permission table | `DebtBackupService`, its file location and (former) storage permissions were undocumented | IMPLEMENTATION HAS UNDOCUMENTED BEHAVIOR | Documented |

## Claims verified as correct (sample)

Schema version 2 and the `oldVersion < 2` migration; all seven local index names;
`ConflictAlgorithm.ignore`/`replace`; `ON CONFLICT (id) DO UPDATE SET note, tags,
updated_at`; the 15-minute default sync interval; `SslMode.require`; manual-entry
`manual:<uuid4>` hashes; `TransactionType.fromValue` defaulting to debit; location tagging
only on the live path; the 0.85 / 0.5 / 0.65 thresholds; the model biases and feature
counts in `ml-pipeline.md:59-61`; the preprocessing order; the fail-open semantics; the
parser being authoritative over the direction model; the widget prefs file name and payload
keys; release builds signed with the debug key (documented as a fact, but not as a risk).

## Related inaccuracies in the UI

The Settings screen read "Notification Access: Granted — listening to UPI app
notifications" while Live Monitoring was off. The text now says capture is *possible*, and
the Live Monitoring line shows whether the spam filter loaded.
