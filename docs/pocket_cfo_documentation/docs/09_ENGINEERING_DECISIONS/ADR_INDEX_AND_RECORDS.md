# Architecture Decision Records — Index and Accepted Decisions
Status: Baseline ADRs (`ADR-001`..`ADR-013`) approved on 2026-11-19 for implementation.

## ADR-001 — Flutter/Dart (Accepted)
Android+iOS+Tablet share a single product and deterministic Pure Dart financial domain. Use Flutter 3.44+ / Dart 3.12+. Display name: Pocket CFO; production application ID: `com.pocketcfo.app`.

## ADR-002 — BLoC (Accepted)
Use `flutter_bloc` + `bloc_concurrency` + `equatable`; Bloc for event-rich/concurrent workflows (debounced search, serialized writes, profile-switch epoch cancellation) and Cubit for simple command-oriented state.

## ADR-003 — Feature-first Clean Architecture (Accepted)
Strict Presentation / Pure-Dart Domain / Data layer boundaries, enforced by automated import-boundary fitness tests in CI.

## ADR-004 — Drift (Accepted)
Use Drift for typed SQLite access, composite foreign keys `(id, profile_id)`, SQLite immutability/balance triggers, and versioned migrations.

## ADR-005 — Encrypted local DB (Accepted)
Use Drift with `sqlite3` v3 native build hook (`source: sqlite3mc` — SQLite3MultipleCiphers, superseding the EOL `sqlcipher_flutter_libs 0.7.0+eol` package) configured in `sqlcipher` v4 / ChaCha20-Poly1305 authenticated encryption mode across Android, iOS, and desktop test hosts. The CSPRNG 256-bit DEK is stored exclusively in hardware-backed Keystore/Keychain (`flutter_secure_storage`), with `android:allowBackup="false"`, `PRAGMA cipher_memory_security = ON`, and a fail-closed runtime cipher check refusing unencrypted SQLite creation in release builds.

## ADR-006 — Local-first data entry (Accepted)
Core records commit atomically to local encrypted SQLite together with a durable `sync_outbox` record. Users may begin in an immediate Local-First Workspace and seamlessly link to a cloud account.

## ADR-007 — Double-entry ledger (Accepted)
Every posted financial transaction generates an immutable balanced `journal_entry` with `>= 2` `ledger_postings` (`SUM(debit) == SUM(credit)` in base currency). Opening balances post against `Opening Balance Equity`. Linked refunds net category spend in budgets while preserving gross reporting. Loans use Reducing-Balance EMI splitting Principal/Interest/Fees.

## ADR-008 — Multi-profile workspace (Accepted)
Separate login identity from financial profiles (`personal`, `family`, `business`). Four-layer isolation enforced across UI epoch cancellation, mandatory `ProfileId` repository APIs, composite DB FKs, and Django RBAC (`Owner`, `Admin`, `Editor`, `Viewer`; `Editor` posting enabled by default, configurable per profile).

## ADR-009 — Integer minor-unit money (Accepted)
Use 64-bit integer minor units `(amountMinor, currencyCode)` supporting 0–4 decimal places (`INR` default). FX uses fixed-point scale `10^8` with `BigInt` intermediate arithmetic and Banker's Rounding (`HALF_EVEN`) at posting time. Missing FX rates require explicit manual entry or `draft` status (never silent `1:1`).

## ADR-010 — Django REST Framework + PostgreSQL (Accepted)
Django 5.2 LTS + DRF + `djangorestframework-simplejwt` + `drf-spectacular` + PostgreSQL 16 modular monolith under `server/`. Argon2id password hashing, rotating hashed refresh tokens, server-side ledger verification, and append-only audit logs.

## ADR-011 — GoRouter (Accepted)
Declarative routes and guards coordinating Splash → Onboarding/Auth → Biometric/PIN App Lock → Profile Selection → Adaptive App Shell.

## ADR-012 — Sync conflict & Backup strategy (Accepted)
Posted journals are append-only (never blind last-write-wins); corrections use compensating reversals. Drafts/metadata use optimistic `version` locking with explicit conflict resolution UI. Backups support both local passphrase-encrypted `.pcfo` archives (PBKDF2/Argon2id + AES-256-GCM + SHA-256 manifest + staging-DB verification) and server sync.

## ADR-013 — Bank integration boundary (Accepted — Future/Gated)
No bank credential capture or screen scraping. `server/apps/integrations/` remains a gated boundary pending RBI FIU / authorized AA partner approval.
