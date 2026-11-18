# Screen Specifications

## Mandatory template
```markdown
# SCR-<MODULE>-### — Screen Name
- Owner / Status / Related requirements / Figma frame
## Purpose
## Entry points and exit destinations
## Layout and visual hierarchy
## Components and data bindings
## User actions and interaction rules
## Validation and business rules
## BLoC/Cubit owner and states
## Loading / empty / error / offline / permission states
## Accessibility and text scaling
## Motion and haptics
## Privacy-reviewed analytics events
## Acceptance criteria
## Open questions
```

## Example: SCR-DASH-001 — Dashboard
**Purpose:** display trustworthy overview for the active profile and reporting period. Entry: onboarding, unlock, profile selector, bottom navigation. Destinations: accounts, transactions, analytics, budgets, goals, settings.

**Hierarchy:** (1) profile + period, (2) net worth/total balance with definition and hide toggle, (3) income/expense/cash-flow, (4) account balances, (5) budget progress, (6) recent transactions, (7) savings-goal progress and contextual insights.

**Interactions:** changing profile invalidates previous scoped data; period changes update all period-based aggregates consistently; account tap opens details in same profile; chart segment tap filters only if visually communicated; hide-balance masks values without changing data.

**BLoC:** `DashboardBloc` coordinates profile/period and requests domain use cases. Domain calculates totals; widgets format/display only.

**States:** initial, loading, loaded, empty, partial-data, offline-cached, failure. Loaded state may contain `isStale` and `lastUpdatedAt`. On refresh failure, preserve useful cached content when safe.

**Motion/accessibility:** animate values only after confirmed data update; chart reveal 180–300 ms; reduced motion supported; chart has text summary; semantic totals include currency and period; colour is not the only signal.

**Acceptance:** profile isolation, date calculations, cached load, refresh failure and empty states pass.

## Example: SCR-TRAN-002 — Add Transaction
Capture income/expense/transfer. Fields: type, amount, currency, source/destination account, category where applicable, date/time policy, note and optional attachment. Validate positive amount/precision, active accounts in current profile, different transfer accounts and known/approved FX handling. Save transaction, journal and outbox operation in one local DB transaction. On failure preserve inputs. Disable repeat submission but also enforce data-layer idempotency. A local save does not require cloud sync.
