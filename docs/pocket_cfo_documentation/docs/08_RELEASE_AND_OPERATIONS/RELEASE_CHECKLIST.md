# Production Release Checklist

## Product and design
- [ ] Release scope and PRD acceptance approved.
- [ ] Screens/wireframes and copy match implemented behaviour.
- [ ] Privacy notice, support and account deletion paths reviewed.

## Engineering and data
- [ ] `flutter analyze` and required tests pass.
- [ ] Android and iOS release builds verified.
- [ ] DB migration tested from every supported version.
- [ ] Encryption and key lifecycle verified in release builds.
- [ ] Backup/restore drill completed.
- [ ] No sensitive secrets/logs or debug endpoints in build.
- [ ] API compatibility and idempotency verified.

## Quality and security
- [ ] Financial accuracy test suite passes.
- [ ] Profile isolation and authorization tests pass.
- [ ] Security/privacy review completed.
- [ ] Accessibility, performance and regression testing completed.
- [ ] No unresolved S0/S1 issue without documented risk acceptance.

## Operations and stores
- [ ] Version/build number and release notes correct.
- [ ] Signing assets accessed securely.
- [ ] Store metadata, screenshots, permissions and privacy declarations accurate.
- [ ] Monitoring/alerts and support runbook ready.
- [ ] Rollout, rollback/forward-fix and incident owners assigned.
- [ ] Post-release smoke test and monitoring window assigned.
