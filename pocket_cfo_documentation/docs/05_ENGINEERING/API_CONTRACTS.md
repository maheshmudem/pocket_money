# API Contracts — Proposed v1

All paths and payloads are proposals; backend/mobile owners must agree exact schemas, auth, idempotency retention and error codes.

## Conventions
Base `/api/v1/`; JSON; bearer token only if approved identity design uses it; profile routes validate membership; retryable mutations accept stable operation ID/`Idempotency-Key`; collections paginated; stable error codes and safe messages.

## Endpoint baseline
| Method | Endpoint | Purpose |
|---|---|---|
| POST | `/auth/register/` | Create account |
| POST | `/auth/login/` | Start session |
| POST | `/auth/refresh/` | Refresh/rotate session |
| POST | `/auth/logout/` | Revoke session |
| POST | `/auth/password-reset/` | Start recovery |
| GET/POST | `/profiles/` | List/create profiles |
| GET/PATCH | `/profiles/{profile_id}/` | Read/update profile |
| GET | `/profiles/{profile_id}/members/` | List members (permission-gated) |
| POST/GET | `/devices/` | Register/list devices |
| DELETE | `/devices/{device_id}/` | Revoke device |
| POST | `/sync/push/` | Submit outbox operations |
| GET | `/sync/pull/?cursor=...` | Pull incremental changes |
| GET | `/sync/status/` | Sync status if needed |

## Sync push request example
```json
{
  "device_id": "uuid",
  "operations": [{
    "operation_id": "uuid", "profile_id": "uuid",
    "entity_type": "transaction", "entity_id": "uuid",
    "operation_type": "create", "payload_version": 1,
    "base_version": null, "payload": {}
  }]
}
```

## Success envelope
```json
{"data":{"accepted":["operation-uuid"],"rejected":[],"next_cursor":"opaque-cursor"},"meta":{"request_id":"request-uuid"}}
```

## Error envelope
```json
{"error":{"code":"PROFILE_ACCESS_DENIED","message":"You do not have access to this profile.","field_errors":{}},"meta":{"request_id":"request-uuid"}}
```

## Contract requirements
Document type, required/optional, format, validation, max length, null-vs-omitted, date/timezone, money minor units/currency, pagination order/cursor, idempotency replay, version/conflict and retryability. Never return provider/bank tokens. Add contract tests and backward-compatibility policy.
