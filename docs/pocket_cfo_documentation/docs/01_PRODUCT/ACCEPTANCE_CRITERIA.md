# Acceptance Criteria Catalogue
Use Given/When/Then style. These are baseline examples for critical flows.

## AC-PROFILE-001 — Profile isolation
Given a user has Personal and Business; when Business is selected; then only Business data is shown; and all reads/writes are profile-scoped; and no Personal record can be returned through Business repositories.

## AC-TRAN-001 — Save expense
Given a valid active profile, source account and category; when a positive expense is saved; then transaction and journal commit atomically; correct expense/source postings are created; and the record appears exactly once.

## AC-TRAN-002 — Transfer
Given two distinct accounts in one profile; when a transfer is saved; then balanced source/destination postings are created; transfer is excluded from income/expense totals; and cross-currency rate/rounding data is retained.

## AC-DB-001 — Atomicity
Given a multi-table transaction save; when any posting/validation fails; then the entire operation rolls back with no partial rows.

## AC-CSV-001 — Duplicate review
Given a CSV row resembles an existing transaction; when preview is shown; then it is marked as a possible duplicate and not silently imported twice.

## AC-SYNC-001 — Idempotent retry
Given a push reached server but acknowledgement was lost; when the client retries the same operation ID; then the server returns the previous result or equivalent acknowledgement without a second financial effect.

## AC-SEC-001 — Biometric failure
Given app lock is enabled; when biometric auth fails/unavailable; then secure fallback is shown and protected data remains hidden until successful authorization.
