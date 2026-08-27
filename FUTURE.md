# Future work

Bigger things, none of them urgent, roughly in the order I would do them.
For what is outstanding *now*, see `REMAINING.md`.

> Supersedes `docs/03_IMPROVEMENTS_AND_NEW_FEATURES.md`, last updated
> 2026-07-19.

---

## Sales history with line items

The history importer records flat bills — date, total, payment mode,
customer. That is correct and deliberately safe, but it means an imported
year of trading carries **no product detail**: best-sellers, dead stock and
category reports all ignore it. The shop sees its takings history and none of
what it actually sold.

Adding line items is a bigger job than it looks, because the safety rule has
to hold: an imported line must **not** move stock. Today's shelf already
reflects last year's sales, so replaying them would drive every product
negative. Lines would be recorded for attribution only.

It also needs product matching per line, which is where a bad import does the
most damage — a mis-matched line credits the wrong product's sales history,
and there is no obvious symptom.

**Do this only once the import screen has been used enough to trust.**

---

## Object storage for product photos

`BLOB_STORE=s3` already works — DigitalOcean Spaces, Cloudflare R2 and AWS
all speak the same protocol and differ only by endpoint. The code is written
and tested; nothing is wired to a vendor.

Filesystem storage is fine on one droplet. It stops being fine when:

- there is more than one API container — each would hold different photos
- the droplet is rebuilt and the volume was not in the backups
- photos should come from a CDN rather than through Django

Switching is one environment variable, but **existing objects do not move
themselves**. Copy them across with `rclone` or `aws s3 sync` first.

---

## Citus, or plain Postgres

Decide, then act on the decision. Distributing the big tables by shop id
while they are small is straightforward; doing it at a hundred times the
volume is a project. Dropping Citus and running plain Postgres is also a
perfectly good answer.

The one option with no upside is carrying it unused, which is today's state.

---

## Stock as a stored figure, refreshed from the ledger

Stock on hand is summed from the movement ledger on every read. That is the
right design — any figure traces back to the sale or delivery that caused it
— and it runs as one indexed query, not one per product.

The concern is only growth. Every sale, delivery, transfer and correction
adds ledger rows forever, and that sum re-reads all of them. At a hundred
times the current volume this is the query that slows first.

The fix, when it is needed: periodic snapshot rows. Sum everything up to a
date, store it, add only the movements since. The audit trail is untouched.
Worth building *before* the hundred-times case rather than after.

---

## Mobile: follow the cursors

The Flutter client calls the inventory endpoint with no limit and takes what
it is given. The default is 200 — deliberately left there so nothing changed
the day paging shipped — so a shop with more than 200 products sees only the
first 200 on a phone.

The server already returns an `X-Next-Cursor` header; the client needs to
follow it. Once it does, the default page size can drop and every list gets
faster for everyone.

---

## Worker capacity

Two Gunicorn processes with four threads each: eight requests in flight. Fine
for a handful of shops, and threaded rather than process-only, so a slow
query blocks a thread instead of the whole server.

Raise it to match the machine's cores — but **after** the image migration,
not before. Raising it first only means more large responses at once.

---

## Business types beyond retail

Pharmacy and restaurant were deferred, not cancelled. The feature flags exist
and resolve correctly; what is missing is screens that read them. Worth
revisiting once the retail path has real users and their feedback has been
absorbed.

---

## Things I would not build yet

- **Multi-currency.** A region layer already exists, but a second currency
  touches every money field and every report. Not until a shop asks.
- **Offline web.** The mobile app is already offline-first. The web app
  assumes a connection, which is right for a back-office tool.
- **Deeper analytics.** The reports that exist are barely used yet. More of
  them is not obviously the next most valuable thing.
