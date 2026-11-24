#!/usr/bin/env bash
# Encrypted PostgreSQL Backup + Automated Restore Verification Drill (`RELEASE_OPERATIONS.md`)
# Requires: pg_dump, pg_restore, psql, openssl, PGHOST, PGUSER, PGDATABASE, BACKUP_ENC_KEY

set -euo pipefail

TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/pocket_cfo}"
mkdir -p "$BACKUP_DIR"

RAW_DUMP="${BACKUP_DIR}/pocket_cfo_${TIMESTAMP}.dump"
ENC_DUMP="${RAW_DUMP}.enc"
VERIFY_DB="pocket_cfo_restore_drill_${TIMESTAMP}"

trap 'rm -f "$RAW_DUMP"' EXIT

echo "[1/4] Creating compressed PostgreSQL dump..."
pg_dump --format=custom --no-owner --no-privileges -f "$RAW_DUMP" "$PGDATABASE"

echo "[2/4] Encrypting backup with AES-256-CBC + PBKDF2..."
openssl enc -aes-256-cbc -pbkdf2 -iter 200000 -salt -in "$RAW_DUMP" -out "$ENC_DUMP" -pass env:BACKUP_ENC_KEY
sha256sum "$ENC_DUMP" > "${ENC_DUMP}.sha256"

echo "[3/4] Running automated restore verification drill into ephemeral DB ${VERIFY_DB}..."
openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -in "$ENC_DUMP" -pass env:BACKUP_ENC_KEY | \
  (createdb "$VERIFY_DB" && pg_restore --no-owner --dbname="$VERIFY_DB")

psql -d "$VERIFY_DB" -c "SELECT count(*) AS profiles_restored FROM profiles;"
dropdb "$VERIFY_DB"

echo "[4/4] Backup & restore verification drill SUCCEEDED: ${ENC_DUMP}"
