# Financial Engine and Double-Entry Ledger
- Document ID: DATA-003 · Status: Proposed; finance-domain review required.

## Purpose
The financial engine is the source of truth for transaction effects, balances, income/expense reporting, transfers, budgets and net worth. UI/BLoC request domain operations; they do not invent financial calculations.

## Money representation
Use `(integer minor units, currency code)`. Currency defines minor-unit precision. Never use IEEE-754 `double` for persisted or authoritative money. Display formatting is separate. FX uses a documented fixed-point scale or rational numerator/denominator, explicit rate direction, rounding mode and rounding point; persist rate snapshot and derived base amount.

## Ledger account types
| Type | Normal side | Examples |
|---|---|---|
| Asset | Debit | Cash, bank, wallet |
| Liability | Credit | Credit card payable, loan payable |
| Equity | Credit | Opening equity |
| Income | Credit | Salary, business income |
| Expense | Debit | Food, rent, utilities |

## Posting examples
**500 INR expense from cash:** Debit Expense 500; Credit Cash/Asset 500.  
**10,000 INR salary into bank:** Debit Bank/Asset 10,000; Credit Income 10,000.  
**2,000 INR own-account transfer:** Debit destination Asset 2,000; Credit source Asset 2,000; not income/expense.  
**Card purchase:** Debit Expense; Credit Credit-card Liability.  
**Card repayment:** Debit Card Liability; Credit Bank Asset; not a second expense.

## Opening balance and balances
Opening balance is a journal against opening equity/opening-balance account. Do not maintain a separate balance override. Derive balances from posted postings according to account normal side. Any cached balance must be rebuildable and reconciled.

## Lifecycle and immutability
Draft → validated → posted. Posted entries cannot be silently edited/deleted. Correct using reversal/compensating entries linked to original. Define any pre-posting void behaviour and audit policy.

## Splits/refunds
Split amounts must reconcile exactly to parent under specified currency rule; category type must match. Refunds link to original where possible; define full/partial refund treatment in net/gross reports and budgets. Reversals compensate rather than mutate history.

## Multi-currency
A profile has one reporting base currency at a time. Store original amount/currency, base amount/currency, rate snapshot/source/time and rounding metadata. Cross-currency transfer stores source amount, destination amount and applied rate; explicit FX gain/loss treatment is required where applicable. Historical reporting uses captured transaction rate; current net-worth revaluation is a separately labelled as-of view. Base-currency changes require a formal policy and must not rewrite history.

## Net worth and budgets
Net worth = assets − liabilities at a stated valuation time and conversion policy. Declare treatment of investments, receivables and pending items. Budgets must specify statuses, period boundaries/timezone, category rollups, refunds, splits, transfers, rollover and overspend. Internal transfers do not inflate spending.

## Loans
Before implementation specify fixed/variable interest, compounding, schedule, fees, rounding, early repayment and overdue policy. Do not use an undisclosed simplified formula.

## Invariants
Every posted journal balances in base currency; postings reference same-profile ledger account; posted history immutable; transfer alone does not change net worth except fees/FX; transaction and ledger effect commit atomically; cached balances reconcile; FX snapshots immutable after posting unless corrected with audit/reversal.

## Required vectors
Zero/negative/large amounts; currency precision 0/2/3/4; rounding ties; cross-currency transfer; refund/reversal; liability normal balance; split rounding; duplicate operation; account closure; base-currency change.
