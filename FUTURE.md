# Future work

Bigger things, none of them urgent, roughly in the order I would do them.
For what is outstanding *now*, see `REMAINING.md`.

> Supersedes `docs/03_IMPROVEMENTS_AND_NEW_FEATURES.md`, last updated
> 2026-07-19.

---

## Password reset

There is no password reset. No "forgot password" link, no reset endpoint, no
token — and nothing to send one with, because no mail server is configured on
the deployment. An owner who forgets their password on a Tuesday morning
cannot open their own till.

The only way back is an operator with a shell:

```bash
docker compose exec api python manage.py changepassword owner@example.com
```

That path is now covered by `platform_apps/users/tests_password_recovery.py`,
which pins the two things that had never been checked: the command finds the
account by **email** (this project has no usernames, and Django resolves by
`USERNAME_FIELD`), and the password it sets is one the real sign-in endpoint
accepts. Before those tests it was an assumption.

Doing this properly needs SMTP first. A reset flow that emails a link, on a
deployment where mail silently goes nowhere, would be one more control that
looks like it works — which is the failure this whole codebase has been
spending its time removing. So: mail server, then reset, in that order.

**Before the pilot**, tell the client plainly that password recovery goes
through the operator, and make sure somebody other than them has the shop's
details written down.

---

## The counter PIN, and the locked till it needs

The server half of the counter PIN is built, reviewed and tested: a hashed
`pos_pin_hash` on the membership, a verify endpoint that fails **closed** when
its throttle cache is unreachable, an audit event on every failed attempt, and
the role read back from the membership rather than assumed.

The browser half was a PIN pad behind a panel mode nothing ever selected. A
"Staff Login" no member of staff could reach, and a Team page counting PINs
that no screen could set — both permanently zero. Both have been removed:
shipping a control that can only ever read zero is worse than shipping
nothing, because it makes a promise about a shift change that the till cannot
keep.

What it is actually waiting for is a **locked till screen**, and the reason
that is not a small job is enforcement. A lock drawn over the page is defeated
by a reload, so the gate has to live in `middleware.ts` alongside token
renewal, covering every POS route. That is a new check in the request path for
every page load, which is not a thing to add days before a pilot to solve a
problem no shop has reported yet.

When it is built: `/api/auth/pin` already does the round trip correctly and
passes the server's three distinct answers through (wrong PIN, PIN never set,
too many attempts), and the membership serialiser already reports
`has_pos_pin`. What is missing is the lock control, the middleware gate, and a
set-PIN control on the Team page.

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

## Credit notes for returns

The highest-value item on this list, because it is the only one a real client
hits on their own without being told.

Returns are now handled correctly everywhere money is counted - the day book,
the P&L, the GST summary and its rate and HSN tables, the drawer, takings and
best sellers. Two exports are still not: the Tally voucher XML and the GSTR-1
CSV both describe invoices as they were issued, so a bill with goods returned
against it appears at its original value.

That is deliberate rather than unfinished. Quietly shrinking an invoice the
customer holds a copy of would be a worse error than the one it fixes; under
GST a return is a credit note, a separate document with its own number. So
the work is to emit those documents - a CDNR section for GSTR-1, a credit
note voucher for Tally - not to change the invoice rows.

Both screens now say plainly that the gap exists and that the accountant must
enter them. That holds for one shop with a few returns a month. It stops
holding as soon as returns are routine or there is more than one shop.

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
