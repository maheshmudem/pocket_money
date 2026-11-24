# Glossary
| Term | Meaning |
|---|---|
| User account | Login identity that can access profiles. |
| Financial profile | Isolated workspace such as Personal, Family or Business. |
| Membership | User role and permission within a profile. |
| Financial account | Real-world bank/cash/card/wallet account tracked by the app. |
| Ledger account | Accounting account used for debit/credit postings. |
| Transaction | User-facing financial event. |
| Journal entry | Accounting event containing balanced posting lines. |
| Posting | Debit or credit line against a ledger account. |
| Minor unit | Smallest currency unit, e.g. paise for INR. |
| Base currency | Currency for consolidated profile reporting. |
| FX snapshot | Exact exchange rate retained with a historical transaction. |
| Local-first | Local DB handles immediate reads/writes; sync happens separately. |
| Outbox | Durable queue of local changes waiting to synchronize. |
| Tombstone | Sync marker for a deleted record. |
| Idempotency | Repeating an operation does not create a second effect. |
| Conflict | Concurrent changes cannot safely be merged automatically. |
| ADR | Architecture Decision Record. |
| RPO / RTO | Recovery Point Objective / Recovery Time Objective. |
| UAT / DoD | User Acceptance Testing / Definition of Done. |
