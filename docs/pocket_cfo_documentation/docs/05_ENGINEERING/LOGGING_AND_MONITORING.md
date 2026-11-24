# Logging, Monitoring and Observability

## Goals
Detect crashes, sync backlog, API instability, migration failures and performance regressions without collecting unnecessary financial data.

## Allowed diagnostic fields
Event name, severity, timestamp, app version/build, platform/OS version, coarse feature/module, request correlation ID, error category, retry count and non-sensitive performance duration.

## Prohibited by default
Passwords, access/refresh tokens, encryption keys, bank credentials, full account numbers, transaction descriptions, raw CSV rows, exact monetary values, raw financial payloads and biometric data.

## Mobile signals
Crash rate, startup time, local DB open/migration failures, transaction-save failure category, outbox size/age, sync attempts/failures and UI performance. User-facing diagnostics should allow copying a support ID without exposing transaction content.

## Backend signals
API latency/error rate, authorization failures, rate limits, DB connection/slow query signals, worker queue depth, idempotency replay count, sync rejection/conflict count and backup job/restore verification.

## Alerting and response
Set thresholds and owners before production. Alert on critical ledger validation failures, profile authorization anomalies, sudden crash increases, sustained sync backlog and backup/restore failure. Each alert needs a runbook, severity and escalation owner.

## Third-party SDK review
Inventory analytics/crash/push SDKs, data collected, retention, processors, opt-out settings and data residency. Verify configuration with network/log inspection.
