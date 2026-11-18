# Initial Sprint Plan — Foundation
Suggested order, not a fixed estimate. Confirm capacity and dates with the team.

## Sprint 0 — Discovery/setup
Approve PRD/scope/IDs; confirm screen inventory/design direction; create Flutter repo/environments/CI; create backend skeleton if parallel; create ADR review tickets.

## Sprint 1 — Architecture vertical slice
Bootstrap, theme, routing, DI; implement one end-to-end feature via BLoC → use case → repository → Drift; lint/unit/BLoC/DB tests; Android/iOS build pipeline.

## Sprint 2 — Storage/security proof
Core Drift tables/migrations; compare encrypted DB options; validate key lifecycle, release build, backup/restore; profile-scoped repositories/isolation tests.

## Sprint 3 — Profile/account
Profile create/select; money value object and currency catalogue; account creation/opening-balance journal; profile switch race tests.

## Sprint 4 — Ledger/transaction
Posting service/invariants; income/expense/transfer; atomic persistence/financial vectors; transaction history UI/error states.

## Sprint 5 — Hardening/dashboard groundwork
Reconciliation/performance; dashboard aggregation use cases; accessibility/dark/responsive review; release readiness check.
