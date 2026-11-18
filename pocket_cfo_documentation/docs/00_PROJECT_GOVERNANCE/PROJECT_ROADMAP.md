# Project Roadmap
**Status:** Proposed; sequence and release gates require team approval.

## Phase 0 — Product discovery
Approved PRD, scope, personas, journeys, screen inventory, risk register, metrics and design direction. Exit: every P0 requirement has an ID, owner and acceptance criteria.

## Phase 1 — Technical foundation (target 0.1)
Flutter shell, environments, routing, theme, DI, BLoC conventions, Drift schema/migrations, encryption proof-of-concept on Android+iOS, profile isolation, currency/money value objects, accounts/ledger foundation, CI. Exit: encryption, migration, restore, profile-isolation and ledger invariant tests pass.

## Phase 2 — Core finance (target 0.2)
Manual income/expense/transfer, categories, transaction history, account detail, dashboard backed by domain calculations, budgets. Exit: financial cases reconcile and offline core entry works.

## Phase 3 — Planning/reporting (target 0.3)
Savings goals, recurring rules/reminders, CSV import/export with preview/dedup, reports. Exit: import is idempotent and reports reconcile.

## Phase 4 — Identity/backup/sync (target 0.4)
Backend identity, device registration, push/pull sync, outbox, tombstones, conflicts, secure backup/restore and observability. Exit: no silent overwrite or duplicate effects in multi-device tests.

## Phase 5 — Advanced (target 0.5+)
Loans/installments, role-based profile sharing, advanced analytics, subscription entitlements if needed. Exit: authorization and operations review.

## Future discovery
Automatic bank data is not a launch dependency. Establish legal eligibility, regulated FIU/partner route, consent lifecycle, institution coverage, retention, support and security before committing it.

Every release requires passing acceptance criteria, migration tests, financial accuracy tests, security/privacy review, accessibility/performance/regression checks and a support/rollback plan.
