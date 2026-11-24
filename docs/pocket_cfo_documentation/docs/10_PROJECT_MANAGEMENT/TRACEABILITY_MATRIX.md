# Requirements Traceability Matrix (Implemented Baseline)

Updated: 2026-11-19 — Every P0, P1, and P2 functional requirement mapped to implemented modules, screens, database/API components, and verified automated tests.

| Requirement | Priority | Screens (`SCR-*`) | Mobile Implementation | Backend / API | Automated Verification |
|---|---|---|---|---|---|
| `FR-001` Auth & sessions | P0 | `SCR-ONB-001/002`, `SCR-AUTH-001/002/003` | `features/authentication/` + `core/network/api_client.dart` | `apps/accounts/` (`/api/v1/auth/*`) | `test_api_enterprise.py`, `widget_test.dart` |
| `FR-002` Multi-profile isolation | P0 | `SCR-PRO-001/002/003` | `features/profiles/` + `ProfileScopeController` | `apps/profiles/`, `apps/memberships/` | `database_integrity_test.dart`, `repository_end_to_end_test.dart`, `bloc_concurrency_and_isolation_test.dart`, `test_api_enterprise.py` |
| `FR-003` Base currency & FX | P0 | `SCR-PRO-002`, `SCR-SET-001` | `core/financial_engine/{currency,fx_rate}.dart`, `profile_currency_history` | `ProfileCurrencyHistory` | `financial_vectors_test.dart` (`TC-FIN-012..016`) |
| `FR-004` Financial accounts | P0 | `SCR-ACC-001/002/003` | `features/accounts/` (derived balances only) | `apps/ledger/` | `repository_end_to_end_test.dart` |
| `FR-005` Opening balance | P0 | `SCR-ACC-002` | `DoubleEntryEngine.buildOpeningBalance` + `DriftAccountRepository` | Server ledger mirror | `repository_end_to_end_test.dart` |
| `FR-006` Record income | P0 | `SCR-TRAN-002` | `DoubleEntryEngine.buildIncome` + `DriftTransactionRepository` | `/api/v1/sync/push/` | `financial_vectors_test.dart` (`TC-FIN-002`), `repository_end_to_end_test.dart` |
| `FR-007` Record expense & splits | P0 | `SCR-TRAN-002` | `DoubleEntryEngine.buildExpense` + `transaction_splits` | `/api/v1/sync/push/` | `financial_vectors_test.dart` (`TC-FIN-001/004/006/007`) |
| `FR-008` Transfers & card repayment | P0 | `SCR-TRAN-002` | `DoubleEntryEngine.buildTransfer` | `/api/v1/sync/push/` | `financial_vectors_test.dart` (`TC-FIN-003/005/016`), `repository_end_to_end_test.dart` |
| `FR-009` Search/filter/pagination | P0 | `SCR-TRAN-001/003` | `TransactionsBloc` (`restartable()`, `droppable()`) | — | `repository_end_to_end_test.dart` |
| `FR-010` Draft edit & posted reversal | P0 | `SCR-TRAN-003` | `DoubleEntryEngine.buildReversal`, SQLite immutability triggers | `IMMUTABLE_POSTED_RECORD` guard | `database_integrity_test.dart`, `financial_vectors_test.dart` (`TC-FIN-010/011`), `test_api_enterprise.py` |
| `FR-011` Categories | P1 | `SCR-CAT-001` | `features/categories/` (1:1 ledger account) | Synced entity | `repository_end_to_end_test.dart` |
| `FR-012` Dashboard & analytics | P1 | `SCR-DASH-001`, `SCR-ANA-001/002` | `features/dashboard/`, `features/analytics/` | — | `repository_end_to_end_test.dart`, `performance_and_a11y_test.dart` (`TC-FIN-019`) |
| `FR-013` Budgets | P1 | `SCR-BUD-001/002` | `features/budgets/` (refund-netted, transfer-excluded) | Synced entity | `repository_end_to_end_test.dart` |
| `FR-014` Savings goals | P1 | `SCR-GOAL-001/002` | `features/savings_goals/` (allocated + transfer) | Synced entity | `repository_end_to_end_test.dart` |
| `FR-015` CSV import & dedup | P1 | `SCR-IMP-001/002/003` | `features/import_export/` (`CsvImportEngine`) | — | `repository_end_to_end_test.dart` (`AC-CSV-001`, `TC-FIN-018`) |
| `FR-016` CSV & PDF reports | P1 | `SCR-REP-001` | `features/reports/data/report_exporter.dart` | — | `repository_end_to_end_test.dart` (formula-injection check) |
| `FR-017` Recurring rules & alerts | P2 | `SCR-REC-001`, `SCR-NOT-001` | `features/recurring/` (idempotent occurrence keys) | Synced entity | `repository_end_to_end_test.dart` |
| `FR-018` Loans & EMI schedules | P2 | `SCR-LOAN-001` | `LoanAmortizer` + `features/loans/` | Synced entity | `financial_vectors_test.dart`, `repository_end_to_end_test.dart` |
| `FR-019` Durable sync outbox | P2 | `SCR-SYNC-001` | `core/sync/sync_coordinator.dart` + `sync_outbox` | `apps/sync/` | `bloc_concurrency_and_isolation_test.dart`, `test_api_enterprise.py` |
| `FR-020` Sync status & conflicts | P2 | `SCR-SYNC-001` | `SyncBackupPage` + `sync_conflicts` | `/api/v1/sync/{push,pull,status}/` | `bloc_concurrency_and_isolation_test.dart`, `test_api_enterprise.py` |
| `FR-021` Devices & revocation | P2 | `SCR-SET-002` | `AuthRepository.listDevices/revokeDevice` | `apps/devices/` (`/api/v1/devices/*`) | `test_api_enterprise.py` |
| `FR-022` Light/Dark/System themes | P1 | `SCR-SET-001` | `app/theme/{app_theme,app_tokens}.dart`, `SettingsCubit` | — | `performance_and_a11y_test.dart` |
| `FR-023` Privacy & biometric lock | P0 | `SCR-SEC-001`, `SCR-SET-002` | `AppLockService`, `AppLockCubit`, `PrivacyScreenService` | — | `bloc_concurrency_and_isolation_test.dart` (`AC-SEC-001`), `security_and_redaction_test.dart` |
| `FR-024` Encrypted backup/restore | P2 | `SCR-BKP-001` | `BackupCrypto`, `BackupRestoreService` (staging DB check) | `infra/scripts/backup_and_verify_postgres.sh` | `security_and_redaction_test.dart`, `repository_end_to_end_test.dart` |
