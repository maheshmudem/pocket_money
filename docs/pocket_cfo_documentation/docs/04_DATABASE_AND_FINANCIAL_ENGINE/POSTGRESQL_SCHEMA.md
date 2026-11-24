# PostgreSQL Server Schema — Logical Baseline

Status: Proposed logical model; backend and security review required. Do not treat this as a final migration.

## Server-owned tables
| Table | Important fields / purpose | Key rules |
|---|---|---|
| `users` | id, email/phone identifier, auth provider, status, created_at | unique normalized identifier; never store plaintext passwords |
| `profiles` | id, name, type, base_currency, owner reference, timestamps | profile lifecycle and base-currency policy |
| `profile_memberships` | id, profile_id, user_id, role, status, invited_at, accepted_at | unique `(profile_id,user_id)`; role constrained |
| `devices` | id, user_id, device fingerprint metadata, platform, push token reference, last_seen, revoked_at | avoid collecting unnecessary device identifiers; token protected |
| `sessions` | id, user_id, device_id, refresh-token hash/reference, expires_at, revoked_at | store refresh token hash if architecture supports; rotate and revoke |
| `sync_operations` | operation_id, profile_id, device_id, entity_type, entity_id, payload_version, result/status, received_at | unique operation ID; idempotent replay |
| `sync_changes` | sequence/cursor, profile_id, entity_type, entity_id, version, change type, timestamp | cursor pagination; tombstones retained by policy |
| `audit_events` | actor, profile, action, target type/id, result, timestamp, request_id | minimize payload; immutable append-only access-controlled log |
| `integration_consents` | profile/user, provider, consent reference, scope, status, expiry, timestamps | no provider secrets in ordinary app tables |
| `subscription_entitlements` | user/profile, product, status, validity, provider reference | verify purchases server-side |

## Synced financial records
If the backend stores transaction, journal and posting records, mirror the local domain with server constraints and independent server validation. A server transaction must not trust a client-calculated balance. Define whether sync payloads are commands (preferred where feasible) or entity snapshots, and define the server canonicalization/acknowledgement model.

## Database controls
Use foreign keys, unique constraints, CHECK constraints, appropriate numeric types, transaction isolation appropriate to each write, indexes on profile/date and membership lookups, encrypted transport, encrypted backups, restricted DB roles and tested migrations. Avoid storing secrets in the same schema as normal application data.

## Important design decisions
1. Define server authority for shared profiles and concurrent writes.
2. Define retention of idempotency records and sync tombstones.
3. Define whether user deletion cascades, anonymizes or retains legally required audit records.
4. Define data residency and backup policy with business/legal owners.
