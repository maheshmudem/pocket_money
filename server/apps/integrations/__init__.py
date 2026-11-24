"""Future compliance-gated integration boundary (`INT-001`, `ADR-013`).

IMPORTANT:
- No bank credential capture, ATM/UPI PIN storage, or screen scraping is permitted.
- Automatic bank data access (e.g., India Account Aggregator / RBI FIU) requires
  legal/compliance sign-off, authorized partner contracts, and explicit consent UX
  before any provider client may be activated here.
"""
