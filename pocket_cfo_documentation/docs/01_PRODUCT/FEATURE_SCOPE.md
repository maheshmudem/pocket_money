# Feature Scope and Release Priorities

**P0:** foundation for a trustworthy first usable product. **P1:** next useful product capability. **P2:** advanced capability after core stability. **Future:** commercial/legal/partner discovery required.

| Feature | Priority | Scope / dependency |
|---|---|---|
| App shell, themes, routing | P0 | Android/iOS foundation |
| Registration/login/session | P0 | Identity API decision |
| Biometric app lock | P0 | Threat model and fallback design |
| Multiple profiles/isolation | P0 | Data model and RBAC |
| Currency/money value object | P0 | INR default; minor-unit precision |
| Accounts/opening balances | P0 | Ledger mapping |
| Income/expense/transfers | P0 | Ledger engine |
| Transaction history/details | P0 | Query/migration design |
| Offline core operations | P0 | Encrypted local DB |
| Dashboard/analytics | P1 | Verified calculation rules |
| Categories and budgets | P1 | Transaction aggregation |
| Savings goals | P1 | Contribution/accounting model |
| CSV import/export | P1 | Preview, dedup, mapping and confirmation |
| Reports/PDF export | P1 | Reconciliation and privacy |
| Recurring/reminders | P2 | Schedule and notification policy |
| Loans/installments | P2 | Interest and repayment rules |
| Multi-device sync | P2 | Outbox, server protocol, conflict policy |
| Profile sharing | P2 | RBAC and security review |
| Subscription/entitlements | P2 | Business model |
| Automatic bank data | Future | Legal eligibility and authorized partner |
| AI financial insights | Future | Data quality, privacy and governance |

## MVP exclusions
Payment execution, UPI initiation, bank credentials, lending, brokerage, portfolio trading, tax filing and automatic bank scraping.

## Change control
A scope change must state user value, data/security/design impact, dependencies, effort, test impact and release trade-off. P0 scope requires Product + Engineering approval to change.
