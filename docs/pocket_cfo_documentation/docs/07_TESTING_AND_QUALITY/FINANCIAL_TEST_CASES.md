# Financial Accuracy Test Catalogue
Examples are illustrative; independently review expected postings and expand before release.
| ID | Scenario | Expected result |
|---|---|---|
| TC-FIN-001 | 500 INR cash expense | Debit Expense 500; Credit Cash 500; cash falls 500 |
| TC-FIN-002 | 10,000 INR salary into bank | Debit Bank 10,000; Credit Income 10,000; bank rises 10,000 |
| TC-FIN-003 | 2,000 INR bank-to-cash transfer | Bank down/cash up; income/expense unchanged |
| TC-FIN-004 | 1,250 INR credit-card purchase | Expense up; credit-card liability up |
| TC-FIN-005 | Repay card 1,250 INR | Bank and card liability decrease; no duplicate expense |
| TC-FIN-006 | Split 1,000 into 600 + 400 | Split sum equals parent |
| TC-FIN-007 | Split mismatch | Reject atomically; no partial rows |
| TC-FIN-008 | Debit 1,000 / credit 999 | Journal cannot post |
| TC-FIN-009 | Duplicate sync operation | Exactly one financial effect |
| TC-FIN-010 | Linked partial/full refund | Original reference and approved net/gross reporting behaviour |
| TC-FIN-011 | Reverse posted journal | Original unchanged; compensating entry balances |
| TC-FIN-012 | Currency with 0 minor units | Validation/display precision correct |
| TC-FIN-013 | Currency with 3 minor units | Validation/display precision correct |
| TC-FIN-014 | FX rounding tie | Documented rounding mode applied exactly |
| TC-FIN-015 | Missing FX rate | Draft/manual-rate/blocked UX; never silent 1:1 |
| TC-FIN-016 | Cross-currency transfer | Amounts, base postings and FX reconcile |
| TC-FIN-017 | Profile switch during pending request | Old response cannot overwrite new state |
| TC-FIN-018 | Import same file twice | Duplicate candidates detected; no accidental duplicate |
| TC-FIN-019 | Large history | Cached balance matches ledger recalculation |
| TC-FIN-020 | Interrupted migration | Safe recovery or explicit failure without partial/corrupt exposure |

Retain fixture, expected postings, actual result, build/environment and evidence. Expected values must be reviewed independently of implementation.
