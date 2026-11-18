# Database Design
- Document ID: DATA-001 · Status: Proposed logical model; physical schema review required.

## Storage split
**Mobile SQLite:** profile cache/membership metadata, currencies/rates, financial accounts, categories, transactions/splits, journals/postings, budgets, goals, recurring rules, import staging, outbox/cursors and local preferences. Use approved encrypted database implementation.

**Server PostgreSQL:** users, profiles, memberships/authorization, devices, sync metadata, server copies of authorized synced records, audit events, consent metadata and subscription entitlements if needed. Finalize canonical authority for shared profile data before collaboration.

## Entity groups
Identity: users/devices/sessions. Workspace: profiles/memberships. Monetary: currencies/exchange_rates. Accounts: ledger_accounts/financial_accounts. Classification: categories. Transactions: transactions/splits. Accounting: journal_entries/ledger_postings. Planning: budgets/budget_categories/savings_goals/contributions. Credit: loans/installments/payments. Automation: recurring_rules/reminders. Import/integration: import_batches/imported_transactions/bank_connections/consent metadata. Operations: attachments/audit_logs/sync_outbox/sync_cursors/app_settings.

## Rules
- Client-generated UUIDs enable offline creation.
- Every profile-owned entity carries `profile_id`.
- Use composite foreign keys/constraints to enforce same-profile relationships where supported.
- Money is integer minor units; currency controls precision.
- Store original amount/currency, base amount/currency and exact FX snapshot.
- Persist timestamps in UTC; separate transaction-date semantics from server audit timestamps.
- Use explicit constrained statuses.
- Posted history is append-only; correct with reversals/adjustments.
- Index profile/date, profile/account/date, profile/category/date, sync status and import fingerprints.

## Balance model
Balances derive from opening-balance journals plus subsequent posted entries. A cached/materialized balance is only an optimization, rebuildable and periodically reconciled against ledger.

## Relationships
One user has many profile memberships; one profile has memberships/accounts/categories/transactions; each financial account maps to one same-profile ledger account; a transaction may have splits; posted transactions generate journals; each journal has at least two postings; budgets have allocations or explicit overall limit; outbox operation belongs to a profile and stable entity ID.

## Migration policy
Drift `schemaVersion`, explicit migrations, never edit released migration, test every supported upgrade path with realistic data and interruption scenarios, have verified backup/recovery before destructive change, coordinate backend compatibility windows.

## Retention
Define export, account closure, profile deletion, tombstones, audit/attachment/backup retention. Distinguish soft delete from immutable accounting history and obtain local legal review for retention rules.
