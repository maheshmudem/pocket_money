# Release, Deployment and Operations

## Environments
Local developer; shared development; production-like staging with synthetic data; production with protected user data. Each has separate endpoints, credentials, DB and third-party configuration.

## Versioning
Use semantic versioning where appropriate: MAJOR incompatible changes, MINOR backward-compatible features, PATCH fixes. Keep store build number monotonic. Maintain changelog and release notes.

## CI/CD minimum
1. Checkout/install dependencies.
2. Format/static analysis.
3. Unit and BLoC tests.
4. Database/migration tests.
5. Backend/API tests and contracts.
6. Dependency/security scan.
7. Android build.
8. iOS build on macOS runner.
9. Sign with protected secrets.
10. Staging deployment/smoke tests.
11. Manual release approval.
12. Store submission and monitoring.

## Database safety
Never ship destructive migration without tested backup/recovery. Test all supported schema upgrades. Maintain compatibility with old clients during rollout. Remove API fields only after supported clients migrate. Feature flags must never bypass financial validation.

## Store checklist
App ID/signing/entitlements; privacy policy and declarations; justified permissions; accurate screenshots/descriptions; subscription claims/pricing if applicable; device smoke test; support/contact/account deletion paths; release notes and reviewer instructions.

## Monitoring
Crash rate, API error rate, sync backlog, migration/restore failures, query latency and background job health. Product analytics must be privacy-reviewed and exclude raw finance data by default.

## Incident response
Define severity, owner, containment, evidence preservation, user communication, recovery, regulatory notification review and post-incident action. Never expose user financial details in public logs.

## Backup/disaster recovery
Set RPO/RTO with business owner. Encrypt and restrict backups; perform restore drills. A successful backup job is not proof that restore works.

## Rollback
Mobile releases cannot always be rolled back after install; prefer forward-fix and API compatibility. Use expand/migrate/contract for schema/API changes where multiple client versions coexist.
