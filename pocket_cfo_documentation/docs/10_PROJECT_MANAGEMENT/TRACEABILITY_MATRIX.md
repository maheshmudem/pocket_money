# Requirements Traceability Matrix
Starter mappings only; populate actual PR/task/test IDs as delivery progresses.
| Requirement | User story | Screen | Data/API | Task | Test | Release |
|---|---|---|---|---|---|---|
| FR-002 Profiles | US-PRO-001 | SCR-PRO-001/002 | Profile/Membership | TASK-PRO-001 | TC-PRO-001 | 0.1 |
| FR-004 Accounts | US-ACC-001 | SCR-ACC-001/002 | FinancialAccount/LedgerAccount | TASK-ACC-001 | TC-ACC-001 | 0.1 |
| FR-005 Opening balance | US-ACC-002 | SCR-ACC-002 | Journal/Posting | TASK-LED-001 | TC-FIN-OPEN-001 | 0.1 |
| FR-006 Income | US-TRAN-001 | SCR-TRAN-002 | Transaction/Journal | TASK-TRAN-001 | TC-FIN-002 | 0.1 |
| FR-007 Expense | US-TRAN-002 | SCR-TRAN-002 | Transaction/Journal | TASK-TRAN-002 | TC-FIN-001 | 0.1 |
| FR-008 Transfer | US-TRAN-003 | SCR-TRAN-002 | Transaction/Journal/FX | TASK-TRAN-003 | TC-FIN-003/016 | 0.1 |
| FR-009 History | US-TRAN-004 | SCR-TRAN-001/003 | Transaction queries | TASK-TRAN-004 | TC-UI-TRAN-001 | 0.1 |
| FR-012 Dashboard | US-DASH-001 | SCR-DASH-001 | Aggregation use cases | TASK-DASH-001 | TC-DASH-001 | 0.2 |
| FR-015 CSV import | US-IMP-001 | SCR-IMP-001/002/003 | ImportBatch/Transaction | TASK-IMP-001 | TC-CSV-001 | 0.3 |
| FR-019 Sync outbox | US-SYNC-001 | SCR-SYNC-001 | Outbox/API | TASK-SYNC-001 | TC-SYNC-001 | 0.4 |

Rules: every P0 requirement maps to at least one acceptance test; every screen maps to requirements; every entity maps to feature/operations requirement; every security requirement maps to threat/control/test; every release item maps to passing evidence and owner approval. A changed requirement triggers review of all linked artefacts.
