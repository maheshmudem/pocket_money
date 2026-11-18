# Functional Requirements
| ID | Requirement | Priority | Acceptance summary |
|---|---|---|---|
| FR-001 | Register/sign in and securely end session | P0 | Valid identity flow; errors safe; tokens never logged |
| FR-002 | Create, rename and select profiles | P0 | Data isolated; switch resets scoped state |
| FR-003 | Configure profile base currency | P0 | Posted historical values retained; base-currency change has explicit revaluation policy |
| FR-004 | Create/manage financial accounts | P0 | Profile-owned; mapped to ledger account |
| FR-005 | Enter opening balance | P0 | Creates balanced journal, not shadow balance |
| FR-006 | Record income | P0 | Destination account, amount/currency/date validated |
| FR-007 | Record expense | P0 | Source account, amount/currency/date validated |
| FR-008 | Transfer between accounts | P0 | Distinct accounts; not income/expense; FX snapshot as needed |
| FR-009 | View/filter transactions | P0 | Period/account/category/type/status; stable pagination |
| FR-010 | Correct eligible records | P0 | Draft edit/delete; posted correction via reversal/adjustment |
| FR-011 | Manage categories | P1 | Profile-scoped; history remains interpretable |
| FR-012 | View dashboard | P1 | Documented calculation and selected profile/period |
| FR-013 | Create/monitor budgets | P1 | Clear period/category/rollover semantics |
| FR-014 | Create goals/contributions | P1 | Contribution model reconciles to actual money movement |
| FR-015 | Import CSV | P1 | Mapping, preview, validation, duplicate review and confirmation |
| FR-016 | Export records/reports | P1 | Scope, dates, currency and privacy warning |
| FR-017 | Define recurring rules | P2 | No silent duplicate generation |
| FR-018 | Track loans/installments | P2 | Principal, interest and fees distinguished |
| FR-019 | Queue local changes | P2 | Durable, retryable and idempotent outbox |
| FR-020 | See sync state/resolve conflicts | P2 | No silent last-write-wins for posted financial records |
| FR-021 | Manage devices/sessions | P2 | Revocation/session expiry visible |
| FR-022 | Light/dark/system theme | P1 | Contrast and chart semantics in each theme |
| FR-023 | Configure privacy/app lock | P0 | Clear explanation and fallback behaviour |
| FR-024 | Backup and restore | P2 | Protected, versioned and tested |

Decompose every requirement into user stories, Given/When/Then criteria, design and test links before implementation.
