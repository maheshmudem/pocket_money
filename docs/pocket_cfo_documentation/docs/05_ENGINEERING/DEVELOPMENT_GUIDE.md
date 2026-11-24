# Engineering Development Guide

## Project setup
- Install supported Flutter stable and matching Dart; run `flutter doctor -v`.
- Create Android/iOS targets and configure app IDs, environments, signing and CI.
- Resolve compatible package versions with `flutter pub add`; commit `pubspec.lock`.
- Generate Drift/serialization code with build_runner.

Typical commands:
```bash
flutter --version
dart --version
flutter doctor -v
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test
flutter run
```

## Proposed package categories
State: `flutter_bloc`, `equatable` or Freezed. Persistence: `drift`, `drift_flutter` plus an encrypted executor chosen after PoC. Routing: `go_router`. Networking: `dio` behind data sources. Security: `flutter_secure_storage`, `local_auth` after threat-model review. Utilities: `intl`, `uuid`, `path_provider`, CSV/PDF packages as needed. Tests: `bloc_test`, `mocktail`, Flutter testing. Verify maintenance, license, platform support and advisories; this is not a frozen manifest.

## Feature workflow
1. Read requirement/user story.
2. Confirm acceptance criteria and screen spec.
3. Review ADR, data/API and security impact.
4. Define domain entities/value objects and repository contract.
5. Implement migration/DAO and tests.
6. Implement repository/use cases.
7. Implement BLoC/Cubit and state tests.
8. Implement UI and all states.
9. Add accessibility/motion.
10. Add offline/sync behaviour if in scope.
11. Run tests, analysis and device checks.
12. Update docs/traceability and submit PR.

## Coding conventions
Null safety; immutable entities/states; explicit public types; focused widgets; repository contracts in domain; Drift/Dio in data; avoid giant BLoCs/widgets and utility dumping grounds; map exceptions to typed failures; no sensitive logs; design tokens instead of magic numbers.

## Git and PR
Use short-lived branches, PRs and required CI. Protect default branch. Never commit `.env`, signing keys, service-account files, production credentials or user data. Migrations and tests ship in the same PR. PR checklist: IDs included; data/migration impact explained; tests pass; no secrets; loading/empty/error/offline considered; accessibility/reduced motion checked; Android/iOS impact reviewed; docs/ADRs updated.

## Environments
Separate dev/staging/production endpoints and credentials. Inject secrets from protected CI/environment configuration. Do not switch production endpoints via a hidden public-build flag.
