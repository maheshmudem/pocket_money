# Pocket CFO — Documentation Pack

**Version:** 0.1.0 · **Status:** Draft baseline · **Platforms:** Android and iOS

Pocket CFO is a local-first personal-finance app with multiple financial profiles, manual transactions, CSV import, multi-currency support (INR default), biometric app lock, offline operation and a future server-sync/bank-integration path.

## Start here
1. `docs/00_PROJECT_GOVERNANCE/PROJECT_OVERVIEW.md`
2. `docs/01_PRODUCT/PRD.md`
3. `docs/01_PRODUCT/FEATURE_SCOPE.md`
4. `docs/02_UI_UX_DESIGN/SCREEN_INVENTORY.md`
5. `docs/02_UI_UX_DESIGN/DESIGN_SYSTEM.md`
6. `docs/03_ARCHITECTURE/SYSTEM_ARCHITECTURE.md`
7. `docs/03_ARCHITECTURE/FLUTTER_BLOC_ARCHITECTURE.md`
8. `docs/04_DATABASE_AND_FINANCIAL_ENGINE/DATABASE_DESIGN.md`
9. `docs/04_DATABASE_AND_FINANCIAL_ENGINE/FINANCIAL_ENGINE.md`
10. `docs/06_SECURITY_AND_PRIVACY/SECURITY_ARCHITECTURE.md`
11. `docs/07_TESTING_AND_QUALITY/TEST_STRATEGY.md`

## Conventions
- Keep documents in Git; update the revision history and traceability links when requirements change.
- IDs: `FR-###`, `NFR-###`, `SEC-###`, `SCR-<MODULE>-###`, `API-###`, `DB-###`, `TC-###`, `ADR-###`, `TASK-###`.
- Persist timestamps in UTC; localize only for display.
- Do not calculate authoritative balances in widgets or BLoCs.
- Review every proposed decision before treating it as approved.

## Important caveats
- The SQLite schema is an illustrative starting point, not a production migration. Convert to Drift definitions and add triggers, constraints, migration tests and validation before release.
- `flutter_secure_storage` protects stored key material; it does not encrypt SQLite by itself. Prove a Drift-compatible encrypted database implementation in Android and iOS release builds.
- Automatic bank integration is future/gated. Obtain legal/compliance approval and an authorized partner/FIU route; never collect bank passwords, ATM PINs or UPI PINs.
- AI insights must be explainable and must not be presented as guaranteed returns or regulated financial advice.

The full catalogue and ownership are in `docs/00_PROJECT_GOVERNANCE/DOCUMENTATION_INDEX.md`.
