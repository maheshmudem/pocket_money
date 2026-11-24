# User Personas and Journeys

## Persona A — Personal finance organizer
Goal: understand monthly spending and balances. Needs quick expense entry, categories, recurring expenses, budgets and comparisons. Pain points: multiple apps and forgotten cash spending.

## Persona B — Household coordinator
Goal: keep household finances separate from personal records. Needs Family profile, shared visibility and role controls. Key risk: accidental exposure of personal profile data.

## Persona C — Freelancer / small operator
Goal: separate business from personal finance. Needs separate accounts/categories, cash flow and exports. Reports are record-keeping aids, not certified accounting/tax advice.

## First-run journey
Open → welcome → sign in/register → verify if required → create profile → select base currency (INR default) → add first account → opening balance → dashboard. If setup cannot sync, preserve local data and show its sync state under the approved offline policy.

## Expense journey
Dashboard/Transactions → Add Expense → amount/currency → source account → category → date/note → save → atomic local DB commit → history/dashboard refresh → pending-sync marker if applicable. Preserve form input after recoverable validation errors.

## Profile switch
Open selector → validate membership → invalidate old profile requests and caches → load target scope → show no stale old-profile data during transition.

## CSV import
Select file → inspect encoding/headers → map fields → preview normalized rows → display validation errors and probable duplicates → confirm → import batch → show imported/skipped/rejected rows.

## Offline/reconnect
Create transaction offline → commit transaction + outbox atomically → show local saved/pending sync → reconnect → push stable operation ID → server acknowledgement → mark synced. Retry must not create a duplicate.
