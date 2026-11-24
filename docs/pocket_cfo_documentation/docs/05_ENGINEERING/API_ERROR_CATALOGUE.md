# API Error Catalogue — Initial Codes

| Code | HTTP | Meaning | Client handling |
|---|---:|---|---|
| `VALIDATION_ERROR` | 400 | Invalid payload/field | Show field-specific error; do not retry unchanged |
| `AUTHENTICATION_REQUIRED` | 401 | Missing/expired/invalid session | Controlled refresh or sign-in |
| `PROFILE_ACCESS_DENIED` | 403 | No permission for profile/action | Stop; refresh memberships if appropriate |
| `RESOURCE_NOT_FOUND` | 404 | Resource absent/not visible | Refresh safe list state |
| `VERSION_CONFLICT` | 409 | Base version mismatch | Explicit conflict flow |
| `IDEMPOTENCY_REPLAY` | 200/409 by contract | Same operation ID seen before | Treat as prior result; never reapply |
| `RATE_LIMITED` | 429 | Rate limit exceeded | Respect retry-after |
| `PAYLOAD_TOO_LARGE` | 413 | Request/file exceeds limit | Explain limit; user can reduce file |
| `SERVER_UNAVAILABLE` | 503 | Temporary service issue | Retain local change; backoff retry |
| `INTERNAL_ERROR` | 500 | Unexpected server failure | Safe message + request ID; no blind repeat for non-idempotent operation |

Error code semantics must be stable across API versions. Error bodies must not include stack traces, SQL or secrets.
