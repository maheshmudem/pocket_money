# Non-Functional Requirements
Initial targets are budgets, not measured claims; validate on agreed physical devices and realistic data.

| ID | Attribute | Initial rule/target | Verification |
|---|---|---|---|
| NFR-001 | Startup | Usable shell target <3 s on agreed mid-range device | Profile release build |
| NFR-002 | Dashboard | Cached dashboard target <1 s after local DB ready | Performance test |
| NFR-003 | Lists | Smooth scrolling; paginate large histories | Device profiling |
| NFR-004 | Offline | Core profile/account/transaction reads and writes work offline | Airplane-mode tests |
| NFR-005 | Integrity | No partial financial operation | DB transaction/fault tests |
| NFR-006 | Precision | Integer minor units/fixed-point; no float money | Static review/test vectors |
| NFR-007 | Availability | Core local use independent of backend | Network isolation tests |
| NFR-008 | Security | Encrypted local DB, TLS, no secrets in logs | Security review/release check |
| NFR-009 | Privacy | Minimal collection, retention/export/delete controls | Privacy review |
| NFR-010 | Accessibility | Semantics, text scaling, contrast, screen reader | Automated + manual tests |
| NFR-011 | Motion | Reduced motion; never blocks critical actions | UI review |
| NFR-012 | Compatibility | Publish supported Android/iOS/device matrix | Device testing |
| NFR-013 | Maintainability | Enforced layer boundaries and tests | CI/code review |
| NFR-014 | Recovery | Migrations and restore tested before release | Recovery drill |
| NFR-015 | Observability | Redacted diagnostic events | Log inspection |
| NFR-016 | Scalability | Pagination, indexes, background work for expensive tasks | Load test |

Never include tokens, passwords, bank credentials, full account IDs, descriptions or exact amounts in routine logs/analytics without explicit privacy/security approval and minimization.
