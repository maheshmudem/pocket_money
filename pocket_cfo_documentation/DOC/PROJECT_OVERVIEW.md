# Project Overview
- Document ID: GOV-001 · Version: 1.0 · Status: Draft baseline
- Owner: Product + Engineering

## Product summary
Pocket CFO is a mobile personal-finance management application. One login account can manage separate profiles such as Personal, Family and Business. Core financial records are stored locally first so the app remains useful offline. Server services provide identity, profile membership, backup/synchronization and future integrations.

## Goals
1. Record and understand income, expenses and transfers.
2. Provide trustworthy account balances and net-worth reporting.
3. Separate profiles with strict data isolation.
4. Support multiple currencies with INR as the initial default base currency.
5. Work offline and synchronize without duplicates or silent data loss.
6. Protect sensitive records through encryption, authorization and secure session handling.
7. Add budgets, savings goals, recurring records, reports and explainable insights.

## Baseline technology choices
| Area | Baseline | Status |
|---|---|---|
| Mobile | Flutter/Dart, Android + iOS | Proposed |
| State | `flutter_bloc` (Bloc/Cubit) | Proposed |
| Architecture | Feature-first Clean Architecture | Proposed |
| Local DB | SQLite through Drift | Proposed |
| Backend | Django REST Framework | Proposed |
| Server DB | PostgreSQL | Proposed |
| Networking | Dio behind repository/data-source boundaries | Proposed |
| Navigation | GoRouter | Proposed |
| Default currency | INR | Requirement |
| Initial input | Manual entry + CSV import | Requirement |
| Bank data | Automatic integration later, consent/eligibility gated | Future |
| Security | Account login + optional biometric app lock | Requirement |

Package versions are not frozen. Resolve compatible stable versions at implementation start and commit `pubspec.lock`.

## Principles
- Accuracy over decoration; all financial numbers come from domain calculations.
- Local-first, not local-only; sync is a separate observable subsystem.
- Every profile-owned read/write is scoped to an authorized profile.
- Privacy by default; collect only data needed for documented features.
- Explain assumptions and data coverage in insights.
- Support reduced motion; animation must not delay critical actions.

## Primary users
Individuals managing personal money; household coordinators; freelancers/small operators needing separate business records.

## Product boundaries
Initial releases do not execute payments, initiate UPI, provide brokerage/trading, originate loans, file taxes or capture bank credentials. Future bank data access must use an authorized consent-based route after legal/compliance review.

## Success measures
Activation (profile + first account), weekly transaction activity, CSV import success, duplicate-import rate, sync conflict rate, reconciliation failures, crash-free sessions, migration/restore success, dashboard latency and support incidents involving missing/duplicated/incorrect records. Define targets before launch.

## Open decisions
Identity provider and verification; profile collaboration release; encrypted SQLite choice; backup ownership/retention/recovery; analytics provider/privacy; eligible bank integration partner.
