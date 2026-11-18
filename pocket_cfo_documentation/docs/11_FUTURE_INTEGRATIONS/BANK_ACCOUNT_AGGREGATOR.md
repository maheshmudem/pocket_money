# Future Bank Data Integration — Discovery and Control
- Document ID: INT-001 · Status: Future/gated; not an MVP commitment.

## Intent
Allow users to retrieve eligible account information through an authorized, consent-based route.

## Initial approach
Manual entry and CSV import. Never collect bank usernames/passwords, ATM PINs, card PINs or UPI PINs. Do not build screen scraping or credential-sharing.

## India Account Aggregator considerations
The AA ecosystem is consent-based and includes regulated roles. Do not assume a general consumer app can directly act as an FIU. Obtain legal/compliance advice to determine whether the business can act in the required role or needs an eligible regulated entity/authorized provider partner. Verify current RBI directions and partner obligations at integration time.

## Discovery questions
- Which regulated entity acts as FIU, if required?
- Which authorized AA/provider partners are available?
- Consent flow, data scope, duration and refresh frequency?
- Supported financial institutions/account types?
- What happens on expiry, revocation, outages and stale data?
- What data may be stored locally/server-side and for how long?
- Who handles support, disputes, deletion and audit evidence?
- What contracts, security assessments and regulatory requirements apply?

## Controls
Explain purpose/data/frequency/duration; explicit revocable consent through approved ecosystem; immediate respect for expiry/revocation; secure server-side provider secrets; no tokens in ordinary local finance tables; minimize stored data; show status, last refresh, error and disconnect control.

## Release gate
No bank integration ships before legal/compliance approval, partner due diligence, security review, consent UX approval, retention approval, support plan and full integration test.
