#!/usr/bin/env bash
#
# Take this droplet from "running behind an IP address" to "a shop can use it".
#
# The steps here are individually trivial and have been deferred for weeks,
# which is the usual fate of work that is fiddly rather than hard. Collecting
# them into one script is the whole point: the cost of doing them becomes
# answering two prompts instead of remembering seven things in the right order.
#
# It is safe to re-run. Every step either checks first or is idempotent, so a
# half-finished attempt can be resumed rather than unpicked.
#
# Usage, on the droplet:
#   sudo bash go-live.sh app.yourdomain.com api.yourdomain.com
#
set -euo pipefail

APP_DOMAIN="${1:-}"
API_DOMAIN="${2:-}"
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.demo.yml}"
PROJECT_DIR="${PROJECT_DIR:-/opt/bhub}"

if [[ -z "$APP_DOMAIN" || -z "$API_DOMAIN" ]]; then
  echo "Usage: sudo bash go-live.sh <app-domain> <api-domain>" >&2
  echo "  e.g. sudo bash go-live.sh app.amburax.com api.amburax.com" >&2
  exit 2
fi

say() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }
warn() { printf '\033[33m    %s\033[0m\n' "$1"; }
die() { printf '\033[31mSTOP: %s\033[0m\n' "$1" >&2; exit 1; }

cd "$PROJECT_DIR" || die "$PROJECT_DIR not found. Set PROJECT_DIR."

# ---------------------------------------------------------------------------
say "1/6  Checking DNS actually points here"
# ---------------------------------------------------------------------------
# Done first because certbot's HTTP challenge fails confusingly when DNS has
# not propagated, and the resulting error blames the certificate rather than
# the A record.
MY_IP="$(curl -fsS https://api.ipify.org || echo '')"
for domain in "$APP_DOMAIN" "$API_DOMAIN"; do
  resolved="$(getent hosts "$domain" | awk '{print $1}' | head -1 || true)"
  if [[ -z "$resolved" ]]; then
    die "$domain does not resolve yet. Add an A record pointing at $MY_IP and wait."
  fi
  if [[ -n "$MY_IP" && "$resolved" != "$MY_IP" ]]; then
    die "$domain resolves to $resolved but this droplet is $MY_IP."
  fi
  echo "    $domain -> $resolved"
done

# ---------------------------------------------------------------------------
say "2/6  Installing the nginx site"
# ---------------------------------------------------------------------------
command -v nginx >/dev/null || die "nginx is not installed. apt install nginx"
SITE_SRC="$(dirname "$0")/nginx-business-hub.conf"
[[ -f "$SITE_SRC" ]] || die "nginx-business-hub.conf not found next to this script."

install -m 644 "$SITE_SRC" /etc/nginx/sites-available/business-hub
sed -i "s/APP_DOMAIN/$APP_DOMAIN/g; s/API_DOMAIN/$API_DOMAIN/g" \
  /etc/nginx/sites-available/business-hub
ln -sf /etc/nginx/sites-available/business-hub /etc/nginx/sites-enabled/business-hub
# The packaged default catches any hostname not matched above, which would
# otherwise serve the nginx welcome page on the real domain.
rm -f /etc/nginx/sites-enabled/default
nginx -t || die "nginx rejected the config; nothing was reloaded."
systemctl reload nginx

# ---------------------------------------------------------------------------
say "3/6  Tightening the Django environment"
# ---------------------------------------------------------------------------
[[ -f .env ]] || die ".env not found in $PROJECT_DIR"
cp .env ".env.backup.$(date +%Y%m%d%H%M%S)"

set_env() {
  local key="$1" value="$2"
  if grep -q "^${key}=" .env; then
    # The value can contain slashes and commas, so use | as the delimiter.
    sed -i "s|^${key}=.*|${key}=${value}|" .env
  else
    printf '%s=%s\n' "$key" "$value" >> .env
  fi
  echo "    $key set"
}

set_env DJANGO_DEBUG "False"
set_env DJANGO_ENV "production"
set_env DJANGO_ALLOWED_HOSTS "$APP_DOMAIN,$API_DOMAIN,127.0.0.1,localhost"
set_env DJANGO_CSRF_TRUSTED_ORIGINS "https://$APP_DOMAIN,https://$API_DOMAIN"
set_env DJANGO_CORS_ALLOWED_ORIGINS "https://$APP_DOMAIN"

if ! grep -q "^BLIND_INDEX_PEPPER=" .env; then
  # Generated once, here, and never again. Rotating it makes every encrypted
  # customer phone permanently unsearchable, so the only safe moment to set it
  # is before a shop has entered any customers.
  pepper="$(openssl rand -hex 32)"
  printf 'BLIND_INDEX_PEPPER=%s\n' "$pepper" >> .env
  warn "Generated BLIND_INDEX_PEPPER. Back it up now - it can never be changed."
fi

# ---------------------------------------------------------------------------
say "4/6  Restarting and running preflight"
# ---------------------------------------------------------------------------
docker compose -f "$COMPOSE_FILE" up -d
# A moment for gunicorn to bind before the check tries to reach it.
sleep 8
if ! docker compose -f "$COMPOSE_FILE" exec -T api python manage.py preflight; then
  die "preflight found blocking problems. Fix them and re-run this script."
fi

# ---------------------------------------------------------------------------
say "5/6  Scheduling the daily alerts"
# ---------------------------------------------------------------------------
# Hourly, not twice daily: shops sit in different timezones, the container
# clock is UTC, and the command works out from each shop's local time whether
# it is due. Running it more often than necessary sends nothing twice.
CRON_LINE="0 * * * * cd $PROJECT_DIR && docker compose -f $COMPOSE_FILE exec -T api python manage.py send_scheduled_alerts >> /var/log/bhub-alerts.log 2>&1"
if crontab -l 2>/dev/null | grep -qF "send_scheduled_alerts"; then
  echo "    Already scheduled."
else
  (crontab -l 2>/dev/null || true; echo "$CRON_LINE") | crontab -
  echo "    Hourly alert run installed."
fi

# ---------------------------------------------------------------------------
say "6/6  Issuing certificates"
# ---------------------------------------------------------------------------
if ! command -v certbot >/dev/null; then
  warn "certbot is not installed. Run: apt install -y certbot python3-certbot-nginx"
  warn "Then: certbot --nginx -d $APP_DOMAIN -d $API_DOMAIN"
else
  certbot --nginx -d "$APP_DOMAIN" -d "$API_DOMAIN" --non-interactive --agree-tos \
    --register-unsafely-without-email --redirect || \
    warn "certbot did not complete. Run it by hand to see why."
fi

say "Done"
cat <<EOF

Still yours to do, because no script should:

  1. Rotate the two passwords that were exposed in screenshots and chat:
       ENSURE_PLATFORM_ADMIN_PASSWORD, and the platform admin login.
  2. Clear the shell history that holds POSTGRES_PASSWORD:
       history -c && rm -f ~/.bash_history
  3. Back up .env somewhere off this droplet. SECRET_KEY and
     BLIND_INDEX_PEPPER cannot be regenerated - losing them makes every
     encrypted customer record permanently unreadable.
  4. Confirm the alerts really fire, rather than assuming:
       docker compose -f $COMPOSE_FILE exec -T api \\
         python manage.py send_scheduled_alerts --slot=morning

Then: https://$APP_DOMAIN
EOF
