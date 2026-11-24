# User Acceptance Testing Checklist

## Setup and security
- [ ] New user can register/sign in and recover access under approved flow.
- [ ] Biometric/app lock and fallback behave correctly.
- [ ] User can create/select multiple profiles without data leakage.

## Core finance
- [ ] Add cash/bank/card account and opening balance.
- [ ] Add income, expense and transfer.
- [ ] Check account balances and monthly totals against expected values.
- [ ] Split transaction and handle refund/correction.
- [ ] Confirm transfers do not inflate income/expense.

## UX and reliability
- [ ] Loading, empty, error, offline and pending-sync states are understandable.
- [ ] Large text, screen reader and reduced-motion behaviour are usable.
- [ ] Light/dark themes have correct contrast.
- [ ] No stale profile data appears during profile switch.

## Import, backup and sync
- [ ] CSV columns map correctly and duplicate review is clear.
- [ ] Offline transaction remains after app restart.
- [ ] Retry does not create duplicates.
- [ ] Backup/restore passes approved recovery process.

UAT sign-off records tester, build, device, date, defects, evidence and accepted known limitations.
