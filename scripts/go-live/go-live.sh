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
#   sudo bash go-live.sh app.yourdomain.com
#
# The API hostname defaults to api.indianwasteportal.com and should stay that
# way: it is compiled into every Android build already installed in a shop, and
# those cannot be repointed remotely. Pass a second argument only if you are
# deliberately moving it and have a plan for the phones.
#
set -euo pipefail

APP_DOMAIN="${1:-}"
# The API keeps answering on api.indianwasteportal.com permanently. Every
# Android build already compiled that hostname in, so retiring it would break
# phones that are already in shops — and those cannot be updated remotely.
API_DOMAIN="${2:-api.indianwasteportal.com}"
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.demo.yml}"
PROJECT_DIR="${PROJECT_DIR:-/opt/bhub}"
# This deployment keeps its secrets in .env.demo, and compose only reads them
# when pointed at it explicitly.
ENV_FILE="${ENV_FILE:-.env.demo}"
COMPOSE=(docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE")

if [[ -z "$APP_DOMAIN" ]]; then
  echo "Usage: sudo bash go-live.sh <app-domain> [api-domain]" >&2
  echo "  e.g. sudo bash go-live.sh app.amburax.com" >&2
  echo "  The API defaults to api.indianwasteportal.com, which is the" >&2
  echo "  hostname already compiled into every Android build." >&2
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
[[ -f "$ENV_FILE" ]] || die "$ENV_FILE not found in $PROJECT_DIR"
cp "$ENV_FILE" "${ENV_FILE}.backup.$(date +%Y%m%d%H%M%S)"

set_env() {
  local key="$1" value="$2"
  if grep -q "^${key}=" "$ENV_FILE"; then
    # The value can contain slashes and commas, so use | as the delimiter.
    sed -i "s|^${key}=.*|${key}=${value}|" "$ENV_FILE"
  else
    printf '%s=%s\n' "$key" "$value" >> "$ENV_FILE"
  fi
  echo "    $key set"
}

# DJANGO_DEBUG is hardcoded False in the compose file, so it is not set here —
# writing it would imply a switch that does nothing.
#
# DJANGO_ENV=production makes settings.py refuse to boot without DATABASE_URL
# and RESEND_API_KEY. That guard is the point of it, but flipping the switch
# before the key exists would leave a container that will not start and an
# operator with no obvious way back, so check first.
if grep -q "^RESEND_API_KEY=." "$ENV_FILE"; then
  set_env DJANGO_ENV "production"
else
  warn "RESEND_API_KEY is empty, so DJANGO_ENV stays as it is."
  warn "Setting it to production now would stop the container booting at all."
fi
set_env DJANGO_ALLOWED_HOSTS "$APP_DOMAIN,$API_DOMAIN,127.0.0.1,localhost"
set_env DJANGO_CSRF_TRUSTED_ORIGINS "https://$APP_DOMAIN,https://$API_DOMAIN"
set_env DJANGO_CORS_ALLOWED_ORIGINS "https://$APP_DOMAIN"

if ! grep -q "^BLIND_INDEX_PEPPER=" "$ENV_FILE"; then
  # Generated once, here, and never again. Rotating it makes every encrypted
  # customer phone permanently unsearchable, so the only safe moment to set it
  # is before a shop has entered any customers.
  pepper="$(openssl rand -hex 32)"
  printf 'BLIND_INDEX_PEPPER=%s\n' "$pepper" >> "$ENV_FILE"
  warn "Generated BLIND_INDEX_PEPPER. Back it up now - it can never be changed."
fi

# ---------------------------------------------------------------------------
say "4/6  Restarting and running preflight"
# ---------------------------------------------------------------------------
"${COMPOSE[@]}" up -d
# A moment for gunicorn to bind before the check tries to reach it.
sleep 8
if ! "${COMPOSE[@]}" exec -T api python manage.py preflight; then
  die "preflight found blocking problems. Fix them and re-run this script."
fi

# ---------------------------------------------------------------------------
say "5/6  Scheduling the daily alerts"
# ---------------------------------------------------------------------------
# Hourly, not twice daily: shops sit in different timezones, the container
# clock is UTC, and the command works out from each shop's local time whether
# it is due. Running it more often than necessary sends nothing twice.
CRON_LINE="0 * * * * cd $PROJECT_DIR && docker compose -f $COMPOSE_FILE --env-file $ENV_FILE exec -T api python manage.py send_scheduled_alerts >> /var/log/bhub-alerts.log 2>&1"
if crontab -l 2>/dev/null | grep -qF "send_scheduled_alerts"; then
  echo "    Already scheduled."
else
  (crontab -l 2>/dev/null || true; echo "$CRON_LINE") | crontab -
  echo "    Hourly alert run installed."
fi

# ---------------------------------------------------------------------------
# Daily, at 02:10 local. This is the ONLY thing that moves a lapsed
# subscription to past_due/expired and mirrors the tier back onto the shop —
# every feature gate reads Shop.settings_json["plan_tier"], and nothing else
# writes it on a schedule. Without this line a shop whose trial ended months
# ago keeps full Pro access forever, silently, and the product is free.
#
# It was documented as "run daily (cron / Celery beat)" and was in neither:
# no crontab entry, no beat_schedule, and the deployed compose runs no beat
# process at all (USE_INMEMORY_CHANNELS=1). So it had never once run.
EXPIRY_CRON_LINE="10 2 * * * cd $PROJECT_DIR && docker compose -f $COMPOSE_FILE --env-file $ENV_FILE exec -T api python manage.py expire_subscriptions >> /var/log/bhub-billing.log 2>&1"
if crontab -l 2>/dev/null | grep -qF "expire_subscriptions"; then
  echo "    Subscription expiry already scheduled."
else
  (crontab -l 2>/dev/null || true; echo "$EXPIRY_CRON_LINE") | crontab -
  echo "    Daily subscription expiry installed."
fi

# ---------------------------------------------------------------------------
# Hourly, same slot as the stock alerts. Until this existed nothing told a
# shopkeeper their trial was ending: days_remaining lived only inside the
# billing page, the 16th of 17 sidebar items. The command dedupes per
# milestone, so running it hourly does not mean hourly email.
REMINDER_CRON_LINE="30 * * * * cd $PROJECT_DIR && docker compose -f $COMPOSE_FILE --env-file $ENV_FILE exec -T api python manage.py send_billing_reminders >> /var/log/bhub-billing.log 2>&1"
if crontab -l 2>/dev/null | grep -qF "send_billing_reminders"; then
  echo "    Billing reminders already scheduled."
else
  (crontab -l 2>/dev/null || true; echo "$REMINDER_CRON_LINE") | crontab -
  echo "    Hourly billing reminders installed."
fi

# ---------------------------------------------------------------------------
# Hourly. Catches what degrades while the box is still up: a database that
# stopped answering, backups that silently stopped running, a disk filling
# toward the write-stop, billing drifting out of step. It CANNOT detect the
# droplet being down — if the box dies so does cron. For that, point an
# external monitor (UptimeRobot's free tier is enough) at /api/v1/health/.
# Alerts dedupe to once a day per problem, so hourly is not hourly email.
OPS_CRON_LINE="45 * * * * cd $PROJECT_DIR && docker compose -f $COMPOSE_FILE --env-file $ENV_FILE exec -T api python manage.py send_ops_alerts >> /var/log/bhub-ops.log 2>&1"
if crontab -l 2>/dev/null | grep -qF "send_ops_alerts"; then
  echo "    Ops alerts already scheduled."
else
  (crontab -l 2>/dev/null || true; echo "$OPS_CRON_LINE") | crontab -
  echo "    Hourly ops alerts installed."
fi

# Monthly, at 03:20 on the 1st - after the nightly backup at 02:00, so the
# drill exercises a fresh dump rather than yesterday's.
#
# Scheduled rather than written down as a monthly habit, because a manual
# monthly task is a task that happens once. Without this, the honest
# description of the restore drill would be "we ran it in August 2026", and
# nobody would know that was the description until they needed a restore.
#
# The drill restores into a throwaway database and drops it. Production is
# never touched, which is what makes it safe to run unattended.
DRILL_CRON_LINE="20 3 1 * * cd $PROJECT_DIR && bash scripts/go-live/restore-drill.sh >> /var/log/bhub-drill.log 2>&1"
if crontab -l 2>/dev/null | grep -qF "restore-drill.sh"; then
  echo "    Restore drill already scheduled."
else
  (crontab -l 2>/dev/null || true; echo "$DRILL_CRON_LINE") | crontab -
  echo "    Monthly restore drill installed."
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
  3. Back up $ENV_FILE somewhere off this droplet. SECRET_KEY and
     BLIND_INDEX_PEPPER cannot be regenerated - losing them makes every
     encrypted customer record permanently unreadable.
  4. Confirm the alerts really fire, rather than assuming:
       docker compose -f $COMPOSE_FILE exec -T api \\
         python manage.py send_scheduled_alerts --slot=morning

Then: https://$APP_DOMAIN
EOF
