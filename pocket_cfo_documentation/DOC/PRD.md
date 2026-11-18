# Product Requirements Document (PRD)
- Document ID: PRD-001 · Version: 1.0 · Status: Draft — product approval required

## 1. Executive summary
Pocket CFO helps people record, organize and understand finances across multiple profiles and accounts. It is a secure, local-first Android/iOS app. Initial focus: manual financial records, profile separation, accounts, income, expenses, transfers and useful summaries. CSV import, budgets, goals, reports and synchronization follow in phased releases. Automatic bank data is a future, compliance-gated capability.

## 2. Problem
People track money across separate bank apps, cash, cards, spreadsheets and notes. They lack one consolidated view, reliable spending categories, planning tools and a clear separation between personal, household and business finance. They need a dependable record-keeping app that remains usable offline.

## 3. Vision and goals
Create a trusted financial command centre with accurate and explainable information. Users can record transactions quickly, view account/profile balances, separate profiles, preserve historical FX, work offline, synchronize safely, create budgets/goals and export reports.

## 4. Non-goals for initial launch
No payment execution, UPI initiation, brokerage/trading, investment order execution, loan origination, credit underwriting, tax filing, bank credential collection or bank scraping. Future bank-data access must use an authorized consent-based route after compliance review.

## 5. Users and access model
A login identity can access multiple profiles. Each profile owns its base currency, accounts, categories, transactions, budgets, goals and reports. Membership is profile-scoped. Proposed roles: Owner, Admin, Editor, Viewer. Define and approve a permission matrix before collaboration ships.

## 6. Core modules
Authentication/device security; profiles/memberships; financial accounts/opening balances; categories/transactions; ledger/financial calculations; dashboard/analytics; budgets; savings goals; recurring rules/reminders; loans/installments; CSV import/export/reports; backup/sync; settings/privacy/support.

## 7. Primary journeys
### First-time setup
Open → onboarding → sign in/register → verify if required → create profile → choose base currency (INR default) → create account → enter opening balance → dashboard.

### Expense
Add → Expense → amount/currency → source account → category → date/note → review/save → local DB commit → history/dashboard refresh → sync pending indicator as needed.

### Transfer
Add → Transfer → source + destination → amount/date → validate same profile and currency/rate rules → save balanced ledger operation. It must not count as income or expense.

### Profile switch
Select profile → validate membership → invalidate old profile work/caches → load target profile → show no old-profile data during transition.

### CSV import
Select file → map columns → preview normalized rows → validate → identify duplicates → user confirms → import batch → show imported/skipped/rejected summary.

## 8. Functional requirements
See `FUNCTIONAL_REQUIREMENTS.md`. Each requirement needs a unique ID, priority, owner, dependency and acceptance criteria.

## 9. Core business rules
- Every profile-owned record belongs to one profile.
- Every profile-owned read/write is scoped and authorized.
- Balances derive from posted ledger activity plus opening-balance journals; no editable shadow balance as source of truth.
- Transfer is not income/expense.
- Split totals reconcile exactly.
- Posted journal entries are immutable; corrections are reversals/compensating entries.
- Historical FX rate is retained with the transaction.
- CSV imports require review and duplicate detection.

## 10. Non-functional requirements
Financial precision; atomic local writes; offline core flows; encrypted local storage; minimum data collection; accessible text/semantics/contrast/reduced motion; performance budgets; feature-first architecture; Android/iOS release verification. See `NON_FUNCTIONAL_REQUIREMENTS.md`.

## 11. Metrics
Activation, weekly finance activity, transaction-save completion, CSV success, duplicate-import rate, sync conflict rate, crash-free sessions, migration/restore success, dashboard latency and financial-data support incidents. Do not send raw amounts, descriptions or account identifiers to analytics by default.

## 12. Dependencies
Native database encryption and key management; backend identity/profile/sync contracts; migration/backup design; Figma screen designs; legal/privacy review for sharing and bank integration.

## 13. Open decisions
Registration/verification; profile sharing release; subscription/free limits; attachments and backup quota; currency catalog and FX provider; pending/reconciled transaction semantics; export/deletion/account closure policy.

## 14. PRD approval gate
All P0 requirements have testable acceptance; in/out scope is clear; journeys reviewed; ownership/profile boundaries agreed; compliance dependencies assigned; Product Owner signs release scope.
