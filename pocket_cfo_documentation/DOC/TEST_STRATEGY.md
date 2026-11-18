# Test Strategy and Quality Plan
- Document ID: QA-001 · Status: Proposed.

## Quality objectives
Financial correctness, profile isolation, durability, offline reliability, secure storage, accessible UI and safe upgrades. A visually complete feature is not releasable without data-integrity and error-path evidence.

## Test layers
| Layer | Scope | Approach |
|---|---|---|
| Unit | Money/FX, use cases, validators | flutter_test / Dart tests |
| BLoC/Cubit | Event-to-state, concurrency | bloc_test, fakes/mocks |
| Repository | Mapping, error handling, data source | contract tests + test DB/API |
| Database | DAOs, FK, transactions, migrations | isolated SQLite DBs |
| API | Auth, permissions, validation, idempotency | backend + contract tests |
| Widget | Components, forms, screen states | widget tests |
| Golden | Visual regression | controlled fonts/device scale |
| Integration | Mobile/DB/API boundaries | integration runner + staging |
| E2E | Full user journeys | representative Android/iOS devices |
| Security | Storage, network, authorization, logs | automated + manual |
| Performance | Startup, DB, scrolling, memory, animation | profile builds/devices |
| Accessibility | Semantics, contrast, scale, reduced motion | automated + assistive tech |
| Recovery | Migration, backup/restore, interruption | fault injection + device tests |

## Test data
Synthetic only. Cover multiple profiles, currency precisions, large values, refunds, long history, duplicate imports, missing FX, timezone boundaries and concurrency. Never use production user data as fixtures.

## Critical paths
Profile isolation; account/opening journal; income/expense/transfer/refund; splits; multi-currency; budgets; CSV mapping/dedup; offline save/reconnect; duplicate sync/conflicts; every supported migration; encrypted backup/restore; device revoke/biometric fail.

## CI gates
Format/analyze; unit/BLoC; DB/migration; relevant widget/golden; API/contract; dependency/security scan; Android/iOS build; no critical/high security issue without recorded risk acceptance.

## Release exit criteria
All P0 acceptance passes; no critical financial defect or profile leak; migration/restore proven; performance/accessibility baselines met; store/privacy declarations reviewed; release notes and support runbook ready.

## Severity
S0: data loss, profile leak, incorrect posted ledger or exploitable compromise. S1: core flow blocked, repeatable duplicate effect, major privacy/security issue. S2: degraded with safe workaround. S3: minor visual/copy issue without financial impact. Severity differs from Product priority.
