# Threat Model

## Assets
Identity/session credentials; local financial records/database key; server data; profile role/membership; backups/attachments; future provider consent metadata/tokens; signing keys and CI secrets.

| Threat | Example | Control |
|---|---|---|
| Lost/stolen device | Attacker copies app files | Encrypted DB, platform key store, app lock, session revoke |
| Profile escape | User requests another profile's data | Profile authorization, composite constraints, isolation tests |
| Network attacker/replay | Intercept/replay API mutation | TLS, session controls, idempotency, server validation |
| Stolen credential | Reuse password/token | MFA/verification options, short-lived access, refresh rotation, rate limits, revocation |
| Insider misuse | Staff views user finance data | Least privilege, audit, restricted access, minimization |
| Malicious CSV | Huge/invalid file or formula injection | File/row limits, safe parser, preview, validation, export sanitization |
| Dependency compromise | Vulnerable package | Lockfile, dependency review/scanning and updates |
| Backup exposure | Unencrypted export | Encryption, integrity, user warning and controlled storage |
| Sync replay | Retry duplicates expense | Stable operation IDs and server idempotency |
| Corruption | Process dies during migration | Transactions, migration tests, backup and restore drills |

Review data flows/trust boundaries; data at rest/in transit/logs; server-side auth; key lifecycle; WAL/temp/backup handling; revocation; malformed imports; third-party SDKs; residual risks and owners.
