#!/usr/bin/env bash
#
# Restore a Business Hub Postgres backup.
#
#   ./scripts/restore_db.sh /var/backups/bhub/daily/bhub-20260804-020000.dump
#   ./scripts/restore_db.sh --dry-run <file>    # verify only, change nothing
#
# THIS REPLACES THE CURRENT DATABASE. It takes a safety dump first and asks for
# an explicit typed confirmation before touching anything.
#
set -Eeuo pipefail
umask 077

PROJECT_DIR="${PROJECT_DIR:-/opt/bhub}"
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.demo.yml}"
# Compose reads .env by default when no --env-file is passed, so look there
# first and fall back to .env.demo. Getting this wrong used to be silent: the
# script simply used built-in defaults, which would target the wrong database
# on any shop that customised POSTGRES_DB.
ENV_FILE="${ENV_FILE:-}"
if [[ -z "$ENV_FILE" ]]; then
  for candidate in "$PROJECT_DIR/.env" "$PROJECT_DIR/.env.demo"; do
    if [[ -f "$candidate" ]]; then ENV_FILE="$candidate"; break; fi
  done
fi
BACKUP_DIR="${BACKUP_DIR:-/var/backups/bhub}"

log() { printf '%s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }
fail() { log "ERROR: $*"; exit 1; }

DRY_RUN=0
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=1
  shift
fi

DUMP="${1:-}"
[[ -n "$DUMP" ]] || fail "usage: $0 [--dry-run] <dump-file>"
[[ -f "$DUMP" ]] || fail "no such file: $DUMP"

cd "$PROJECT_DIR" || fail "project dir $PROJECT_DIR not found"
# Read, NOT sourced — see the same note in backup_db.sh. `source` executes the
# env file as shell, and RESEND_FROM contains an unquoted `<` that bash reads
# as a redirect. That broke the backup script outright. It mattered more here:
# this is the script you reach for during an incident, and discovering it will
# not start is the worst possible moment to find out.
env_value() {
  local key="$1"
  [[ -n "$ENV_FILE" && -f "$ENV_FILE" ]] || return 0
  sed -n "s/^${key}=//p" "$ENV_FILE" | tail -n 1 | sed -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'$/\1/"
}

if [[ -n "$ENV_FILE" && -f "$ENV_FILE" ]]; then
  POSTGRES_USER="$(env_value POSTGRES_USER)"
  POSTGRES_DB="$(env_value POSTGRES_DB)"
else
  log "WARNING: no env file found in $PROJECT_DIR (.env / .env.demo);"
  log "         falling back to default database name and user."
fi
PG_USER="${POSTGRES_USER:-bhub}"
PG_DB="${POSTGRES_DB:-business_hub}"

compose() { docker compose -f "$COMPOSE_FILE" "$@"; }

log "checking the archive is readable..."
compose exec -T db pg_restore --list < "$DUMP" >/dev/null 2>&1 \
  || fail "this file is not a valid pg_dump archive"
TABLES="$(compose exec -T db pg_restore --list < "$DUMP" 2>/dev/null | grep -c 'TABLE DATA' || true)"
log "archive is valid — contains $TABLES table(s) of data"

if [[ "$DRY_RUN" == "1" ]]; then
  log "dry run: nothing was changed"
  exit 0
fi

cat <<WARN

  ****************************************************************
   This will REPLACE every row in database '$PG_DB'.
   Current data will be dumped to a safety file first, but any
   writes made after that point are lost.

   Stop the API before restoring so nothing writes mid-restore:
     docker compose -f $COMPOSE_FILE stop api
  ****************************************************************

WARN
read -r -p "Type RESTORE to continue: " CONFIRM
[[ "$CONFIRM" == "RESTORE" ]] || fail "cancelled"

mkdir -p "$BACKUP_DIR/pre-restore"
SAFETY="$BACKUP_DIR/pre-restore/before-restore-$(date '+%Y%m%d-%H%M%S').dump"
log "taking a safety dump of the CURRENT database first..."
compose exec -T db pg_dump -U "$PG_USER" -d "$PG_DB" -Fc --no-owner > "$SAFETY" \
  || fail "safety dump failed — refusing to restore"
chmod 600 "$SAFETY"
log "safety dump written to $SAFETY"

log "restoring..."
# --clean --if-exists drops existing objects first; --no-owner avoids role
# mismatches between machines. Single transaction so a mid-way failure rolls
# back rather than leaving a half-restored database.
if compose exec -T db pg_restore -U "$PG_USER" -d "$PG_DB" \
     --clean --if-exists --no-owner --single-transaction < "$DUMP"; then
  log "restore complete"
else
  fail "restore FAILED — the database was rolled back. Your safety dump is at $SAFETY"
fi

log "run migrations and start the API again:"
log "  docker compose -f $COMPOSE_FILE up -d --build"
