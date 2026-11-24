# Security and Privacy Architecture
- Document ID: SEC-001 · Status: Proposed; security review required.

## Objectives
Protect identity/session, financial records, profile boundaries, local DB, sync traffic, backups, attachments and operational credentials. Minimize data collection/exposure.

## Authentication/session
Use reviewed identity/session design. Keep access token in memory where practical; protect refresh credential using platform secure storage; rotate/revoke as designed. Never store passwords in SQLite/logs. Define offline access after token expiry separately from server authorization. Provide device/session revocation and account recovery.

## Biometric app lock
Biometrics are a local access gate, not DB encryption. Define fallback, device credential fallback, lock timeout, app-background behaviour, recent-app masking where appropriate and handling of biometric enrollment changes. App must not store biometric templates.

## Local database protection
- Select encrypted SQLite only after Drift compatibility PoC on Android+iOS.
- Protect DB key using platform-backed KeyStore/Keychain through reviewed abstraction.
- Define key generation, rotation, reset, restore and device migration.
- Verify DB, WAL/journal, temporary files and backups are protected.
- Verify release builds cannot silently create plain SQLite.
- Test app uninstall, device backup/restore and key invalidation.

`flutter_secure_storage` alone does not encrypt the DB file.

## Network
HTTPS/TLS; platform certificate validation; explicit timeouts and retry policy; replay protection with idempotency/session controls; credentials never in URLs. Certificate pinning requires a rotation/recovery plan.

## Authorization/profile isolation
Every profile operation checks membership/role; repository methods require profile context; schema enforces same-profile links where possible; backend re-authorizes every request; profile switch clears scoped caches; cross-profile adversarial tests are mandatory.

## Privacy/logging
Collect only documented data. Define purpose, retention, export, deletion, consent and sharing. Do not send descriptions, exact amounts or full account details to analytics by default. Structured redacted logs must exclude passwords, tokens, bank credentials, encryption keys, full account numbers and raw transaction payloads. Review third-party SDK collection.

## Backup and verification
Backups are encrypted, integrity-checked and versioned. Define whether user-controlled, cloud or server-managed. Restore validates schema and ledger before exposure. Security testing includes threat model, static/dependency scan, API auth, local data inspection, network, backup, log redaction, revocation and incident rehearsal.
