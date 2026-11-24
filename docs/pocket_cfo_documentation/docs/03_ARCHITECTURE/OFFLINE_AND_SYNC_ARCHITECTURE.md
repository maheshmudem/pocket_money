# Offline-First and Synchronization Architecture
- Document ID: ARCH-004 · Status: Proposed; protocol required before multi-device release.

## Local write sequence
1. Validate command in domain.
2. Begin local DB transaction.
3. Write business record and required ledger rows.
4. Write stable-ID outbox operation in same DB transaction.
5. Commit.
6. Report local success.
7. Sync worker pushes when connectivity/policy permits.
8. Server validates membership, idempotency and invariants.
9. Client stores acknowledgement/server version and marks operation synced.

If local commit fails, report failure. If network fails after commit, preserve local record and show pending/failed sync.

## Outbox and pull cursor
Outbox: operation UUID, profile ID, entity type/ID, operation type, payload version, timestamp, base version, retry count, next attempt, error category, status and idempotency key. Avoid secrets in payload/logs. Pull uses opaque cursor/monotonic change sequence, is paginated/resumable, and advances cursor atomically with received changes.

## Idempotency
Retry the same logical operation with the same stable ID. Server persists the outcome for a defined retention period; a retry returns the prior result/equivalent acknowledgement without a second financial effect.

## Conflict rules
- Never blind last-write-wins for posted journals.
- Posted history is append-only; correct by compensating entry.
- Preferences may use documented last-write-wins.
- Drafts may use version checks and explicit conflict resolution.
- Membership changes are server-authoritative.
- Conflict UI shows record/context and safe choices without discarding data silently.

## Deletion/retry
Use tombstones and define purge/retention. Deletion cannot erase immutable posted history without approved accounting treatment. Retry transient failures with exponential backoff+jitter; do not loop tightly. Permanent validation/authorization failures should stop and present an actionable status.

## Profile switching
Tag operations with profile ID; invalidate profile-scoped in-memory state and reject late responses from old profile. Never mix cursors/outbox authorization between profiles.

## Sync states
`local_only`, `pending`, `syncing`, `synced`, `retryable_error`, `permanent_error`, `conflict`. UX must distinguish local save from remote sync.

## Required tests
Offline creation, process termination with queued ops, lost acknowledgement retry, duplicate push, out-of-order/partial pull, cursor recovery, membership revocation, simultaneous edits, tombstone replay and server validation errors.
