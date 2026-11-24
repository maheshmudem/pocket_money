# Currency and Foreign Exchange Specification

Store ISO currency code, display name, minor-unit precision, symbol and active status. INR is the initial default, but do not assume every currency has two decimal places.

Exchange rate fields: base currency, quote currency, fixed-point rate or numerator/denominator, source/provider, effective timestamp, retrieval timestamp, validity and required profile scope. Retain the exact snapshot used for a posted transaction.

Document rate direction, arithmetic precision, rounding mode and when rounding occurs. Use integer/fixed-point calculations and avoid repeated conversion that compounds rounding.

Historical transaction reports use the stored transaction snapshot. Current net-worth revaluation may use a current rate but must be labelled with its valuation timestamp. Do not mix the two methods silently.

If rate is unavailable, define whether the transaction must remain draft, require manual rate or use a clearly disclosed last-known rate. Never silently use 1:1.

Changing a profile base currency requires confirmation, effective date and historical treatment. Preserve original records; do not mutate posted values in place.
