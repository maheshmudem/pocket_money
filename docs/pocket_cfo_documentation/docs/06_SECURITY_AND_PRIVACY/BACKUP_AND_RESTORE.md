# Backup and Restore Specification

## Scope decisions required
Choose local export, user-controlled cloud backup, server sync copy or a combination. Define who controls encryption keys, how a user restores on a new device and what happens if the key is lost. A server backup must not silently imply the server can decrypt end-to-end encrypted user data.

## Backup requirements
- Encrypt backup with a reviewed scheme and protect key material.
- Include schema version, creation time, app version, profile scope and integrity metadata.
- Exclude ephemeral caches and secrets that should not be backed up.
- Decide whether attachments are included and how they are verified.
- Never overwrite a good backup with a partial failed backup.

## Restore requirements
- Authenticate/authorize user where required.
- Verify integrity and supported schema version before import.
- Preview profile/data impact and prevent accidental cross-profile merge.
- Restore into a safe staging DB or transaction and validate ledger balance/profile links before activation.
- Preserve or reconcile sync cursors/outbox to avoid replay duplicates.
- Show actionable errors without exposing key material.

## Verification tests
Wrong password/key; corrupted file; old schema; partial download; low storage; app termination; duplicate restore; existing local data; missing attachment; revoked account; successful cross-device restore. Perform periodic real restore drills.
