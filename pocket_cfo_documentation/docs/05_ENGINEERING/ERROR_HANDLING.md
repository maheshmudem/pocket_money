# Error Handling Standard

## Principles
- Errors are typed and actionable; do not expose raw exceptions, SQL or server tracebacks.
- Preserve entered form data after recoverable failures.
- Distinguish validation, authentication, authorization, not-found, conflict, rate-limit, network, timeout, storage, parsing and unexpected failures.
- Retry only transient failures and only when the operation is safe/idempotent.
- A committed local save remains saved when cloud sync fails.

## Suggested failure categories
| Category | User treatment | Retry policy |
|---|---|---|
| Validation | Inline field message; retain input | No automatic retry |
| Authentication expired | Re-authenticate/refresh securely | One controlled refresh attempt |
| Authorization denied | Explain access unavailable; do not retry blindly | No |
| Not found/deleted | Refresh list or show unavailable state | Maybe refresh |
| Conflict | Show conflict-resolution flow | Only after user/merge decision |
| Network/timeout | Offline/pending state; preserve local data | Backoff if idempotent |
| Rate limited | Explain retry timing where safe | Respect server retry-after |
| Database/storage | Do not claim save; preserve form and diagnostics | User retry after recovery |
| Import parsing | Row/column-specific feedback | Correct mapping/file |
| Unexpected | Generic safe message + correlation ID | Controlled only |

## BLoC guidance
Map data exceptions to domain failures in repository boundaries. BLoC translates failure into state and UI message; it does not parse low-level exception strings. Avoid catch-all silent fallbacks that turn failures into empty success.

## Error response contract
Use stable `code`, safe `message`, optional `field_errors`, retryability metadata and request/correlation ID. Do not send stack traces or sensitive payloads to the client.
