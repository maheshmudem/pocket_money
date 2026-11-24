# Data Retention and Privacy Specification

## Data inventory
Maintain an inventory of identity data, profile/membership data, transaction/ledger data, device/session metadata, diagnostics, attachments, imports, consent metadata and backups. For each field record purpose, source, access, storage, retention and deletion behaviour.

## Privacy lifecycle
Explain collection and purposes; collect minimum required data; obtain consent where required; allow export and account/profile deletion where applicable; honour consent withdrawal; define third-party processors and cross-border transfers; document retention/deletion and backup expiry.

## Deletion considerations
Separate account identity deletion, profile membership removal, profile deletion, local-device data wipe, synced record deletion, audit retention and backup expiry. Do not promise immediate physical deletion from encrypted backups if the operational policy cannot guarantee it; disclose timelines and legal exceptions.

## Sensitive data handling
Transaction data is sensitive even if it is not a password. Restrict internal access, redact logs, minimize analytics, encrypt storage/transfers/backups and restrict support tooling.

## Approval gate
Privacy notice, consent text, retention schedules, data subject workflows and processor agreements require legal/privacy owner review before launch.
