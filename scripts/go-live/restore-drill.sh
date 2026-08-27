#!/usr/bin/env bash
#
# Rehearse a restore without touching the live database.
#
#   bash scripts/go-live/restore-drill.sh                # newest backup
#   bash scripts/go-live/restore-drill.sh <dump-or-sql>  # a specific one
#
# scripts/restore_db.sh already exists and does the real thing — it REPLACES
# production. That is exactly why it cannot be rehearsed: nobody practises a
# procedure whose practice run destroys the data. So this restores into a
# throwaway database instead, counts what came back, and drops it.
#
# The point is not that the file exists. It is that the file RESTORES, and
# that you have done it before, timed, rather than reading the runbook for the
# first time during an incident.
set -Eeuo pipefail

PROJECT_DIR="${PROJECT_DIR:-/opt/bhub}"
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.demo.yml}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/bhub}"

say()  { printf '\n\033[1m==> %s\033[0m\n' "$1"; }
warn() { printf '\033[33m    %s\033[0m\n' "$1"; }
die()  { printf '\033[31mSTOP: %s\033[0m\n' "$1" >&2; exit 1; }

cd "$PROJECT_DIR" || die "$PROJECT_DIR not found."

# Same detection as deploy.sh — the env file's name has been wrong twice.
ENV_FILE="${ENV_FILE:-}"
if [[ -z "$ENV_FILE" ]]; then
  for c in .env .env.demo .env.production .env.prod; do
    [[ -f "$c" ]] && { ENV_FILE="$c"; break; }
  done
fi
[[ -n "$ENV_FILE" && -f "$ENV_FILE" ]] || die "No env file found in $PWD."
COMPOSE=(docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE")

PG_USER="$(grep '^POSTGRES_USER=' "$ENV_FILE" | cut -d= -f2-)"
PG_DB="$(grep '^POSTGRES_DB=' "$ENV_FILE" | cut -d= -f2-)"
PG_USER="${PG_USER:-postgres}"
[[ -n "$PG_DB" ]] || die "POSTGRES_DB not set in $ENV_FILE."

say "1/6  Choosing a backup"
BACKUP="${1:-}"
if [[ -z "$BACKUP" ]]; then
  BACKUP="$(ls -t "$BACKUP_DIR"/**/*.dump "$BACKUP_DIR"/*.dump ~/bhub-db-*.sql 2>/dev/null | head -1 || true)"
fi
[[ -n "$BACKUP" && -f "$BACKUP" ]] || die "No backup found. Pass one explicitly, or set BACKUP_DIR."
printf '    %s (%s bytes, %s)\n' "$BACKUP" "$(stat -c%s "$BACKUP")" "$(stat -c%y "$BACKUP" | cut -d. -f1)"

# A backup small enough to be an error message rather than a database.
[[ "$(stat -c%s "$BACKUP")" -gt 10240 ]] || die "That file is under 10 KB. It is not a database."

DRILL_DB="bhub_drill_$(date +%s)"
cleanup() {
  "${COMPOSE[@]}" exec -T db psql -U "$PG_USER" -d postgres \
    -c "DROP DATABASE IF EXISTS $DRILL_DB;" >/dev/null 2>&1 || true
}
trap cleanup EXIT

say "2/6  Creating a scratch database"
# Never the live one. Everything below happens inside $DRILL_DB.
"${COMPOSE[@]}" exec -T db psql -U "$PG_USER" -d postgres \
  -c "CREATE DATABASE $DRILL_DB;" >/dev/null || die "Could not create $DRILL_DB."
echo "    $DRILL_DB"

say "3/6  Restoring into it (timed)"
START=$(date +%s)
case "$BACKUP" in
  *.sql)
    "${COMPOSE[@]}" exec -T db psql -U "$PG_USER" -d "$DRILL_DB" < "$BACKUP" >/dev/null 2>&1 \
      || die "Restore failed. THIS IS THE FINDING — the backup does not restore." ;;
  *)
    "${COMPOSE[@]}" exec -T db pg_restore -U "$PG_USER" -d "$DRILL_DB" --no-owner < "$BACKUP" >/dev/null 2>&1 \
      || die "Restore failed. THIS IS THE FINDING — the backup does not restore." ;;
esac
ELAPSED=$(( $(date +%s) - START ))
echo "    restored in ${ELAPSED}s"

say "4/6  Comparing against the live database"
count_in() {
  "${COMPOSE[@]}" exec -T db psql -U "$PG_USER" -d "$1" -tAc \
    "SELECT COALESCE((SELECT count(*) FROM $2), -1);" 2>/dev/null | tr -d '\r' || echo "-1"
}
FAILED=0
for table in shops_shop customers_customer inventory_inventoryitem sales_sale; do
  LIVE="$(count_in "$PG_DB" "$table")"
  DRILL="$(count_in "$DRILL_DB" "$table")"
  if [[ "$DRILL" == "-1" ]]; then
    printf '    \033[31m%-32s missing from the restore\033[0m\n' "$table"; FAILED=1
  elif [[ "$LIVE" != "$DRILL" ]]; then
    printf '    \033[33m%-32s live %s / restored %s\033[0m\n' "$table" "$LIVE" "$DRILL"
    warn "A difference is expected if the backup predates recent writes."
  else
    printf '    %-32s %s rows, matching\n' "$table" "$DRILL"
  fi
done

say "5/6  Product photos"
#
# Checked separately because they are stored separately, and that separation
# is recent. Photos used to sit in the products table and came back with the
# dump; they now live in a volume, so a database restore alone returns every
# product with a broken picture. Counting rows would not notice - the rows are
# all there, each pointing at a file nothing has saved.
PHOTO_SQL="SELECT count(*) FROM inventory_inventoryitem WHERE image_key <> '';"
# Errors are NOT discarded. The first version sent this query with a broken
# argument, psql failed, the failure was swallowed and the empty result read
# as "no photos" - so the check reported nothing to verify on a backup that
# had a photo in it. A check that cannot tell must say so, not reassure.
if PHOTO_KEYS="$("${COMPOSE[@]}" exec -T db psql -U "$PG_USER" -d "$DRILL_DB" -tAc "$PHOTO_SQL" 2>&1 | tr -dc '0-9')" && [[ -n "$PHOTO_KEYS" ]]; then
  PHOTO_QUERY_OK=1
else
  PHOTO_QUERY_OK=0
  PHOTO_KEYS=0
fi

MEDIA_ARCHIVE="$(ls -1t "$BACKUP_DIR"/daily/bhub-media-*.tar.gz 2>/dev/null | head -1 || true)"
FILES=0
if [[ -n "$MEDIA_ARCHIVE" ]]; then
  FILES="$(tar tzf "$MEDIA_ARCHIVE" 2>/dev/null | grep -c '[^/]$' || true)"
  FILES="${FILES:-0}"
fi

if [[ "$PHOTO_QUERY_OK" -eq 0 ]]; then
  echo "    could not count product photos in the restored database"
  warn "This check could not run, which is not the same as passing."
  warn "Query used: $PHOTO_SQL"
  FAILED=1
elif [[ "$PHOTO_KEYS" -eq 0 ]]; then
  # Still worth saying when an archive exists anyway: photos nothing points
  # at are usually a migration half-done, not an empty catalogue.
  if [[ "$FILES" -gt 0 ]]; then
    echo "    no product references a photo, but $FILES file(s) are archived"
    warn "Expected if photos were only just migrated. Otherwise, check why."
  else
    echo "    no product photos in this backup - nothing to check"
  fi
elif [[ -z "$MEDIA_ARCHIVE" ]]; then
  echo "    $PHOTO_KEYS product(s) reference a photo, and no media archive exists"
  warn "Restoring this backup would give every one of them a broken picture."
  warn "Check scripts/backup_db.sh is archiving the media volume."
  FAILED=1
else
  echo "    $PHOTO_KEYS product(s) reference a photo; $FILES file(s) in $(basename "$MEDIA_ARCHIVE")"
  if [[ "$FILES" -eq 0 ]]; then
    warn "The media archive is empty. The photos are not being saved."
    FAILED=1
  fi
fi

say "6/6  Result"
if [[ "$FAILED" -eq 1 ]]; then
  die "The backup restored incompletely. Treat that as an incident, not a warning."
fi
cat <<TXT
    The backup restores, in ${ELAPSED}s, with the expected tables present.

    Run this monthly, and after any change to the schema or the backup job.
    Knowing the file exists is not the same as knowing it restores — and an
    incident is a bad time to find out which one you had.
TXT
