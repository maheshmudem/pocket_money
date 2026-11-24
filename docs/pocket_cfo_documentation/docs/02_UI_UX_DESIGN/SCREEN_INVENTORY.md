# Screen Inventory
Screen IDs are stable. Add screens through design review.

| ID | Module | Screen | Priority | Key states/notes |
|---|---|---|---|---|
| SCR-ONB-001 | Onboarding | Splash / initialization | P0 | startup/update required/init failure |
| SCR-ONB-002 | Onboarding | Welcome | P0 | first run |
| SCR-AUTH-001 | Auth | Sign in | P0 | validation/loading/offline |
| SCR-AUTH-002 | Auth | Create account | P0 | validation/password policy |
| SCR-AUTH-003 | Auth | Recovery | P0 | rate limit/success |
| SCR-SEC-001 | Security | Biometric/app lock setup | P0 | permission/unavailable/fallback |
| SCR-PRO-001 | Profiles | Profile selector | P0 | current profile/role |
| SCR-PRO-002 | Profiles | Create/edit profile | P0 | profile type/base currency |
| SCR-PRO-003 | Profiles | Members and roles | P2 | gated by authorization |
| SCR-DASH-001 | Dashboard | Overview | P1 | cached/empty/offline/data coverage |
| SCR-ACC-001 | Accounts | Account list | P0 | type/currency grouping |
| SCR-ACC-002 | Accounts | Add/edit account | P0 | type/currency/opening balance |
| SCR-ACC-003 | Accounts | Account details | P0 | balance/activity/filters |
| SCR-TRAN-001 | Transactions | Transaction list | P0 | search/filters/pagination |
| SCR-TRAN-002 | Transactions | Add transaction | P0 | income/expense/transfer |
| SCR-TRAN-003 | Transactions | Transaction details | P0 | posted/reversal/edit rules |
| SCR-CAT-001 | Categories | Manage categories | P1 | system/custom |
| SCR-BUD-001 | Budgets | Overview | P1 | period/progress |
| SCR-BUD-002 | Budgets | Create/edit budget | P1 | category/period rules |
| SCR-GOAL-001 | Savings | Goals overview | P1 | progress/contributions |
| SCR-GOAL-002 | Savings | Create goal | P1 | target/date/account mapping |
| SCR-REC-001 | Recurring | Recurring rules | P2 | next due/status |
| SCR-LOAN-001 | Loans | Overview/details | P2 | principal/interest/repayment |
| SCR-ANA-001 | Analytics | Spending analysis | P1 | period/category |
| SCR-ANA-002 | Analytics | Cash flow/net worth | P1 | valuation method |
| SCR-REP-001 | Reports | Builder/export | P1 | scope/period/currency |
| SCR-IMP-001 | Import | CSV file selection | P1 | permission/format |
| SCR-IMP-002 | Import | Mapping and preview | P1 | validation/duplicates |
| SCR-IMP-003 | Import | Import result | P1 | imported/skipped/rejected |
| SCR-SYNC-001 | Sync | Status/conflicts | P2 | pending/failed/conflict |
| SCR-SET-001 | Settings | Preferences | P0 | theme/locale/display currency |
| SCR-SET-002 | Settings | Security/privacy | P0 | app lock/sessions/export/delete |
| SCR-BKP-001 | Backup | Backup/restore | P2 | encryption/integrity/warnings |
| SCR-NOT-001 | Notifications | Notification centre | P2 | read/unread/routing |

Each screen has an approved detailed spec and Figma frame before implementation.
