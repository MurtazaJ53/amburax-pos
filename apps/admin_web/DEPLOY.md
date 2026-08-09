# Deploying the admin website

The backend already runs on the DigitalOcean droplet under Docker Compose. This
is about the Next.js admin site, which so far has only ever run on a laptop.

## Read this first: the droplet is small

`docker-compose.demo.yml` was written for a **2 GB droplet that already runs
another site alongside it**. The current allocation is:

| Container | Limit |
|---|---|
| `db` (Postgres) | 512 MB |
| `api` (Django) | 900 MB |
| **`web` (Next.js)** | **400 MB** |
| | **1.8 GB of 2 GB** |

That leaves under 200 MB for the OS, Nginx and the other site on the box.
**Check before you start it:**

```bash
free -m
```

If available memory is under ~600 MB, adding the web container will make both
sites unstable. Two honest options in that case:

- **Resize the droplet to 4 GB.** Simplest, and the box is doing real work now.
- **Host the website on a Next.js host instead**, leaving the droplet's memory
  to the backend. Nothing in the repo is configured for one; `vercel.json` was
  removed along with `render.yaml`, because carrying config for platforms this
  project has never deployed to invites someone to trust it. The Dockerfile is
  the supported path.

In practice the measured web container idles around 40 MB, so the 300 MB limit
is headroom rather than a target and resizing is rarely needed.

## Configuration

One environment variable:

| Variable | Value |
|---|---|
| `BUSINESS_HUB_API_BASE_URL` | `http://api:8000/api/v1` (same compose network) |

That is the whole configuration. Every API call is made **server-side** by the
proxy routes in `src/app/api`, which attach the session token from an HTTP-only
cookie. Browser code never holds a credential.

**Never rename this to `NEXT_PUBLIC_…`.** A `NEXT_PUBLIC_` variable is inlined
into the JavaScript bundle and served to every visitor.

> The deleted `render.yaml` declared `NEXT_PUBLIC_API_URL`, which nothing in the
> codebase reads. A deployment using it would have started, passed its health
> check, and silently fallen back to `http://127.0.0.1:8000/api/v1` — failing
> every request. Render was never used for this project; the file is gone.

## Deploying on the droplet

```bash
cd /opt/bhub
git pull
free -m                       # confirm headroom first

docker compose -f docker-compose.demo.yml build web
docker compose -f docker-compose.demo.yml up -d web
docker compose -f docker-compose.demo.yml logs -f --tail=50 web
```

The site binds to `127.0.0.1:3001`, not the public internet — same as the API.

### Nginx

Add a server block alongside the existing API one:

```nginx
server {
    listen 443 ssl http2;
    server_name shop.example.com;          # your domain

    ssl_certificate     /etc/letsencrypt/live/shop.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/shop.example.com/privkey.pem;

    location / {
        proxy_pass         http://127.0.0.1:3001;
        proxy_http_version 1.1;
        proxy_set_header   Host              $host;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
        proxy_set_header   Upgrade           $http_upgrade;
        proxy_set_header   Connection        "upgrade";
    }
}
```

Then `nginx -t && systemctl reload nginx`.

### Backend settings to update

Once the web hostname exists, on the droplet's `.env`:

- **`DJANGO_ALLOWED_HOSTS`** is currently `*`. Replace it with the real
  hostnames.
- **`DJANGO_CSRF_TRUSTED_ORIGINS`** lists only localhost. Add the deployed
  origin.

Restart the API afterwards.

## After deploying

```bash
pnpm smoke https://shop.example.com
```

Requests every page and API route and fails on any 5xx. It exists because a
build that compiles is not a page that works: the Hindi/Gujarati change
compiled cleanly and then returned 500 on every page, because `"use client"`
marks every export of a module client-only and the server layout was calling
one of them. Only a real request caught it.

Signed out, expect `307` (redirect to `/login`) for pages and `401` for API
routes. Anything `5xx` is a genuine failure.

## Known limitation

The backend is served from `api.indianwasteportal.com`, a domain belonging to
an unrelated project. It works, but it is visible in the address bar during
payment flows and should be replaced with a Business Hub domain before
customers use it.

## Scheduled alerts

Two alerts a day, per shop, in the shop's own timezone:

| Time | Alert | To |
|---|---|---|
| 09:00 | What is out of stock or running low | Owners and admins |
| 21:00 | The day's takings | Owners and admins |

They are sent by a management command, driven by cron. Add this on the droplet
with `crontab -e`:

```cron
0 * * * * cd /opt/bhub && docker compose -f docker-compose.demo.yml exec -T api python manage.py send_scheduled_alerts >> /var/log/bhub-alerts.log 2>&1
```

**Hourly, not twice daily.** Shops can sit in different timezones, the
container clock is UTC, and a missed run should not silently skip a day. The
command works out which shops are due from each shop's local time and records
what it sent, so running it more often than necessary costs nothing and running
it twice sends nothing twice.

A Celery beat schedule would be the tidier home for this, but the deployment
runs Celery in-process (`USE_INMEMORY_CHANNELS=1`) with no beat process, so
cron is the mechanism that actually exists.

To test without waiting for the hour:

```bash
docker compose -f docker-compose.demo.yml exec -T api \
  python manage.py send_scheduled_alerts --slot=morning
```

The once-a-day guard still applies, so a second run that day sends nothing.

### Email delivery

Alerts always create an in-app notification, and additionally email each
recipient **if `RESEND_API_KEY` is set**. It is not set on the droplet today,
so alerts currently appear in the app only. The same key enables khata
reminders and purchase-order emails.
