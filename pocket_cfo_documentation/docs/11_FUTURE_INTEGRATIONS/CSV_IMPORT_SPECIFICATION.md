# CSV Import Specification

## User flow
Select file → inspect file → map columns → choose amount/debit-credit convention and date format → preview normalized rows → validation and duplicate review → user confirmation → import batch → result summary/export of rejected rows.

## Parsing requirements
- Support explicitly documented delimiters, encodings and quote escaping.
- Handle header/no-header files and common date formats with user confirmation.
- Support either signed amount or separate debit/credit columns.
- Require or infer currency only when unambiguous; show the inferred value in preview.
- Enforce file size and row-count limits; process large files in bounded batches.
- Never trust CSV formulas or treat imported content as executable. Sanitize fields when exporting to spreadsheet formats.

## Normalized row fields
Import batch ID, source row number, transaction date, description, amount in integer minor units, currency code, debit/credit direction, external reference if present, source account mapping, normalized fingerprint, validation status and user decision.

## Duplicate detection
Use provider reference when available. Otherwise create a probable-match fingerprint using profile/account/date/amount/currency and normalized description, with clear caveat that similarity is not proof. Do not auto-delete or silently skip without reporting. Let user choose import/skip for ambiguous matches.

## Atomicity and recovery
Persist the import batch and staged rows. Confirmed rows are committed with related ledger entries in bounded, transaction-safe units. Interrupted imports must resume safely or roll back according to documented policy. Re-importing the same batch must not create duplicate effects.

## Acceptance
Test malformed/large files, alternate date/decimal separators, debit/credit columns, duplicate files, repeated confirmation, invalid currency, empty rows, partial rejection, interrupted import and spreadsheet formula injection on export.
