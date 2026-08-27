#!/usr/bin/env bash
#
# Ship the current main branch to the droplet.
#
# Run ON the droplet:
#   cd /opt/bhub && bash scripts/go-live/deploy.sh
#
# Migrations are not run separately: the api service's compose command already
# runs `manage.py migrate --noinput` before gunicorn starts, so a rebuild
# applies them. Running them here as well would race that.
#
# The api and web containers are rebuilt together on purpose. The access token
# now lasts 12 hours instead of a year, and the browser only survives that
# because of the renewal middleware in the web app — deploying the backend
# alone would leave every signed-in browser dead after twelve hours with no way
# back but signing out by hand.
set -euo pipefail

PROJECT_DIR="${PROJECT_DIR:-/opt/bhub}"
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.demo.yml}"

# The env file's name was taken from the docs and turned out not to match the
# droplet, which stopped the deploy with a message blaming the directory the
# operator was already standing in. Find it instead of assuming, and if it
# cannot be found, say what IS there.
ENV_FILE="${ENV_FILE:-}"

say()  { printf '\n\033[1m==> %s\033[0m\n' "$1"; }
die()  { printf '\033[31mSTOP: %s\033[0m\n' "$1" >&2; exit 1; }

cd "$PROJECT_DIR" || die "$PROJECT_DIR not found."

if [[ -z "$ENV_FILE" ]]; then
  for candidate in .env.demo .env .env.production .env.prod; do
    if [[ -f "$candidate" ]]; then ENV_FILE="$candidate"; break; fi
  done
fi
if [[ -z "$ENV_FILE" || ! -f "$ENV_FILE" ]]; then
  printf '[31mSTOP: no environment file found in %s[0m
' "$PWD" >&2
  echo "Looked for: .env.demo .env .env.production .env.prod" >&2
  echo "What is actually here:" >&2
  ls -a | grep -iE '^\.?env' | sed 's/^/  /' >&2 || echo "  (nothing matching env)" >&2
  echo "Re-run naming it explicitly, e.g.:" >&2
  echo "  ENV_FILE=.env.whatever bash scripts/go-live/deploy.sh" >&2
  exit 1
fi
echo "    using env file: $ENV_FILE"

# Likewise the compose file, so a differently-named deployment is not a dead end.
if [[ ! -f "$COMPOSE_FILE" ]]; then
  for candidate in docker-compose.demo.yml docker-compose.yml docker-compose.prod.yml compose.yml; do
    if [[ -f "$candidate" ]]; then COMPOSE_FILE="$candidate"; break; fi
  done
fi
[[ -f "$COMPOSE_FILE" ]] || die "No compose file found in $PWD. Set COMPOSE_FILE=..."
echo "    using compose file: $COMPOSE_FILE"

COMPOSE=(docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE")

say "1/5  Where this pulls from"
git remote -v | head -2
BEFORE="$(git rev-parse --short HEAD)"
echo "    currently at $BEFORE"

say "2/5  Pulling"
git pull --ff-only || die "Pull failed. If the remote is the old BUSINESS-HUB repo, retarget it:
  git remote set-url origin https://github.com/MurtazaJ53/amburax-pos.git"
AFTER="$(git rev-parse --short HEAD)"
if [[ "$BEFORE" == "$AFTER" ]]; then
  echo "    already up to date at $AFTER"
else
  echo "    $BEFORE -> $AFTER"
fi

say "3/5  Rebuilding api and web together"
# Migrations run inside the api container's start command.
"${COMPOSE[@]}" up -d --build

say "4/5  Waiting for the api to come back"
for i in $(seq 1 30); do
  if "${COMPOSE[@]}" exec -T api python -c "print('ok')" >/dev/null 2>&1; then
    echo "    api responding after ${i}0s"
    break
  fi
  sleep 10
  [[ $i -eq 30 ]] && die "api did not come back. Check: ${COMPOSE[*]} logs --tail=80 api"
done

say "5/5  Preflight"
"${COMPOSE[@]}" exec -T api python manage.py preflight || \
  die "preflight reported blocking problems. The containers are running; fix and re-run."

say "Deployed"
cat <<TXT

Check the two things that were broken:

  1. Complete a sale on the website. It used to answer
     "Failed to save sale to cloud backend".
  2. Sign out all devices, then confirm the signed-out device really is
     locked out rather than carrying on.

Everyone signed in on the website stays signed in — the renewal middleware
that shipped in this same deploy keeps their session alive.
TXT
