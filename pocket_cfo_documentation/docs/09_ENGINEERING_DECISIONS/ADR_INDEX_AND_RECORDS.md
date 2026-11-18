# Architecture Decision Records — Index and Initial Decisions
The following are recommendations, not accepted decisions until owners review them.

## ADR-001 — Flutter/Dart (Proposed)
Android+iOS share a product and domain. Use Flutter/Dart. Consequence: native integration and release verification on both platforms.

## ADR-002 — BLoC (Proposed)
Use `flutter_bloc`; Bloc for event-rich/concurrent workflows and Cubit for simple state coordination. Consequence: conventions and BLoC tests.

## ADR-003 — Feature-first Clean Architecture (Proposed)
Presentation/domain/data layers, dependency direction inward. Consequence: more abstractions but testable boundaries.

## ADR-004 — Drift (Proposed)
Use Drift for typed SQLite access/migrations. Validate query, migration, transaction and performance behaviour.

## ADR-005 — Encrypted local DB (Needs validation)
Compare Drift-compatible encrypted SQLite options (including SQLCipher-compatible implementations and SQLite3MultipleCiphers according to current support). Prove Android+iOS release build, WAL/temp files, migrations, backup, restore and key lifecycle before approval.

## ADR-006 — Local-first data entry (Proposed)
Persist locally and sync asynchronously. Consequence: outbox, idempotency, tombstones and conflicts are first-class.

## ADR-007 — Double-entry ledger (Proposed; finance review required)
Represent posted financial effects with balanced journals and postings. Stronger integrity/auditability but increased domain complexity.

## ADR-008 — Multi-profile workspace (Proposed)
Separate login identity from financial profiles; each profile-owned record carries profile scope. Enforce in repository, DB and server authorization.

## ADR-009 — Integer minor-unit money (Proposed)
Use integer minor units and fixed-point/rational FX. Specify precision and rounding.

## ADR-010 — Django REST Framework + PostgreSQL (Proposed)
Backend identity, membership and sync services; APIs and server-side authorization require contracts/tests.

## ADR-011 — GoRouter (Proposed)
Declarative routes/guards; test deep links, auth redirects, profile and app-lock states.

## ADR-012 — Sync conflict strategy (Proposed)
Never silently last-write-wins posted financial records. Use append/reversal semantics and explicit draft conflicts.

## ADR-013 — Bank integration boundary (Future/gated)
No credential scraping. Investigate authorized consent-based provider/AA route after legal/partner validation. Not an MVP dependency.

Use `ADR_TEMPLATE.md` for future decisions. Each accepted ADR records alternatives, trade-offs, owner/date, consequences, validation and review triggers.
