# Risk Register
| ID | Risk | Impact | Mitigation | Owner | Status |
|---|---|---|---|---|---|
| R-001 | Incorrect ledger/FX calculation | Critical | Reviewed domain rules, independent vectors, reconciliation invariants | Finance/QA | Open |
| R-002 | Encrypted SQLite incompatible on target platforms | High | Compare candidates; Android/iOS release PoC; migration/restore test | Mobile lead | Open |
| R-003 | Cross-profile data leakage | Critical | Scoped repositories, composite constraints, server authorization, adversarial tests | Eng/Security | Open |
| R-004 | Sync retry duplicates a record | High | Stable IDs, idempotency, outbox and replay tests | Backend/Mobile | Open |
| R-005 | Concurrent edit overwrites posted history | Critical | Immutable ledger, explicit conflicts and compensating entries | Engineering | Open |
| R-006 | Lost device exposes financial data | High | Encrypted DB, platform key storage, app lock, revocation plan | Security | Open |
| R-007 | CSV imports invalid/duplicate transactions | High | Mapping, preview, validation, import batch and duplicate review | Product/QA | Open |
| R-008 | Bank integration not legally/commercially available | High | Exclude from MVP; legal and authorized-partner discovery | Product/Legal | Open |
| R-009 | Scope expansion before ledger stability | High | P0 scope lock and change control | Product | Open |
| R-010 | Dashboard query performance | Medium | Indexes, query plans, pagination, measured caching | Mobile lead | Open |
| R-011 | Sensitive data leaks in logs/analytics | High | Redaction, SDK review, automated log tests | Security | Open |
| R-012 | Migration damages user data | Critical | Upgrade tests, backups and recovery drills | Mobile/QA | Open |
| R-013 | AI insight is misleading | High | Evidence-linked explanations, uncertainty, opt-in and governance | Product/Legal | Open |

Review every sprint and before release. Assign owner, due date and residual risk to all high/critical items.
