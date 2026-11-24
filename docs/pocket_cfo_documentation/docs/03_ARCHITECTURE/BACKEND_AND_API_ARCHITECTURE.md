# Backend and API Architecture
- Document ID: ARCH-003 · Status: Proposed.

## Proposed stack
Django + Django REST Framework; PostgreSQL; Redis only where cache/queue is justified; background workers for async jobs; HTTPS reverse proxy; managed secrets, backups and monitoring.

## Suggested Django apps
```text
server/config/                  # settings, urls, ASGI/WSGI
server/apps/accounts/            # identity
server/apps/profiles/            # profile records
server/apps/memberships/         # roles/authorization
server/apps/devices/             # registered devices/sessions
server/apps/sync/                # push, pull, cursors, idempotency
server/apps/audit/               # security/admin audit events
server/apps/notifications/       # notification preferences/jobs
server/apps/imports/             # import metadata if needed
server/apps/subscriptions/       # future entitlements
server/apps/integrations/        # future partner boundary
server/common/                   # errors, permissions, pagination
```

## API rules
Version under `/api/v1/`; HTTPS only; stable JSON envelopes/error codes; server-side validation; pagination; idempotency key/operation ID for retryable mutations; profile authorization on every profile route; avoid returning secrets; do not trust client balance values.

## Authentication lifecycle
Short-lived access token; refresh credential protected in platform secure storage and rotated/revoked per identity design. Never store passwords in local finance DB. Define device revocation, logout, expiry, recovery and offline-session behaviour.

## Authorization
Every profile route verifies authenticated user membership and permission for that exact profile. UI hiding is not authorization. Add cross-profile read/write tests.

## Operations
Rate limits, request size limits, timeouts, health checks, redacted structured logs, DB migration discipline, backup verification, worker monitoring and dependency vulnerability management before production.
