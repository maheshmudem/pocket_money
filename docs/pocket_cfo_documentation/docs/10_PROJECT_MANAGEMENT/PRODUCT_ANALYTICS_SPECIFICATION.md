# Product Analytics Specification

## Purpose
Measure activation, usability and reliability while minimizing collection of financial and personal data. Analytics is opt-in/consent-aware according to product and legal policy.

## Candidate events
| Event | Trigger | Allowed properties (minimized) |
|---|---|---|
| `onboarding_completed` | Setup complete | app version, platform |
| `profile_created` | Profile created | profile type only; no profile name |
| `account_created` | Account setup | account type/currency code only where approved; no account name/number/balance |
| `transaction_saved` | Local commit succeeds | transaction kind, currency code, entry method; no amount/description |
| `csv_import_completed` | Batch outcome | row count bands, accepted/rejected count bands, file type; no row content |
| `sync_completed` | Sync batch ends | duration, success/failure category, operation count band |
| `app_error` | Recoverable/unexpected error | stable error category and request ID |

## Prohibited analytics properties by default
Exact amount, account number, transaction description, payee, bank credentials, auth tokens, precise location and raw file contents.

## Governance
For every event document purpose, owner, trigger, properties, retention, consent basis and destination. Review SDK behaviour and user controls. Delete/disable events that no longer serve an approved purpose.
