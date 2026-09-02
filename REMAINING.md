# Remaining work

What is outstanding right now, most important first. Everything here was
checked against the code on 1 September 2026, not written from memory.

Current state: **all commits pushed** to `pos`
(`github.com/MurtazaJ53/amburax-pos`). Backend 1,474 tests green, web 713
green, types clean, production build clean.

> Supersedes `docs/02_ROADMAP_AND_REMAINING.md`, which was last updated on
> 2026-07-19 and predates roughly forty commits of work.

---

## 1. ~~None of it has been used in a browser~~ — mostly closed

Three rounds of browser testing on 27 Aug – 1 Sep drove the live deployment
with real data: three shops, 285 products, 200 customers, 500 sales, 100
expenses. That covered registration, the import screen, POS (cash, khata,
barcode, wholesale units), returns of both refund kinds, expenses, the day
book, P&L, GSTR-1, the Load more buttons on Stock and Customers, the SKU
generator, data-health tiles, staff invite and join, and a staff sale.

It found what tests do not: a till that could not sell a third of the
catalogue, inventory tiles disagreeing with the dashboard by ₹13 lakh, a
credit sale that left no debt, receipts printing an invented address, and
five separate cases of correct code that nothing called.

**Still not clicked by anyone:**

- the transfers redesign
- the import screen's wrong-kind warning and undo
- the receipt branding settings (logo, brand colour)

Every bug found in this session came from **reading** code, not from tests: a
compose file that would have discarded product photos, a `@staticmethod`
returning 500 on every product save, a migration command that looped forever,
a paging default that would have cut the mobile app from 200 products to 50.

Tests do not catch that class of problem, and they catch none of the next
class at all — "this is confusing", "the button is in the wrong place",
"this number looks wrong".

**Half an hour of real use will produce a better list than anything more I
can find by reading.**

---

## 1a. The weekly half hour

**Put it in the calendar. It is the highest-yield thing on this page.**

Every money bug in this project was found by a person using the app. None came
from the 1,382 tests, and one test asserted a bug was correct for months.

Once a week, spend thirty minutes as a shopkeeper rather than as the person
who wrote it: ring up a sale, put one on khata, take a payment, return an
item, close the till, read the day book. Do the boring path, not the clever
one.

Two rules, both of which are why it works:

- **Use the deployed site, not a dev server.** Three separate times a green
  test run and a server running last week's code were indistinguishable from
  outside.
- **Write down anything that felt wrong**, including "this number looks odd"
  and "I could not find the button". Those are the findings tests cannot
  produce, and half of them turn out to be real.

Thirty minutes of this out-finds any sprint that can be planned in advance. It
has done so every time so far.

---

## 2. Only you can do these

### Run the product image migration

One photo, 0.2 MB. It failed the first time with `Permission denied:
/var/lib/bhub/media/products` — the container runs as `appuser` and the named
volume was created owned by root.

The Dockerfile now creates and owns that directory, which fixes any **new**
deployment: Docker copies an image directory's ownership into an empty named
volume on first use. The volume on this droplet already exists and is already
root-owned, so it needs correcting once by hand:

```bash
cd /opt/bhub
docker compose -f docker-compose.demo.yml exec -u root api   chown -R appuser:appgroup /var/lib/bhub/media

docker compose -f docker-compose.demo.yml exec api   python manage.py migrate_product_images
```

Nothing was lost by the failure: the command moves a row only after reading
the bytes back out of the store, so a failed write leaves the photo in the
database exactly as it was.

**Then audit it**, because the products table cannot tell you on its own
whether a photo moved or vanished — both leave the column empty:

```bash
docker compose -f docker-compose.demo.yml exec api   python manage.py migrate_product_images --check
```

It resolves every stored key against the store rather than trusting that a
key exists, and names any product pointing at a photo the store does not
have. `Nothing outstanding` is the answer you want.

**Confirm `bhub_media` is in your backups** — unlike the database it has no
dump.

> **Correction to the scale review.** It ranked photos-in-the-database as the
> dominant cause of slow page loads, reasoning from the 60 KB client cap times
> a 200-row page: roughly 12 MB per load. This shop has one photo. The
> mechanism was real — the column shipped with every list and could not be
> cached — but the magnitude was hypothetical, and the measured cause of the
> slow loads was something else entirely: Turbopack compiling each route on
> first visit in `next dev`, which a production build removes. The image work
> still stands on its own (a photo does not belong in the row the till reads),
> it was simply not the thing making the app feel slow.

### Rebuild and ship the mobile app

Commit `61d8451` fixes product photos on mobile. Until the app is rebuilt and
released, a **fresh install or a data clear shows no product photos**. Phones
that already hold them are unaffected.

---

## 3. Small, and mine to do

| Item | Why |
|---|---|
| ~~Delete `findExisting` in `lib/import-detect.ts`~~ — **done** | Removed in `5b7c127`. The name still appears in the web app, but that is `findExistingCustomer` in `lib/customer-match.ts`, which is live and used by the POS checkout. This row was stale, not outstanding. |
| ~~Verify rehearsal counts across chunks~~ — **done, correct** | Proven on 1 Sep with a 600-row file: 550 unique SKUs plus 50 duplicates placed deliberately *after* the 500-row boundary, so they land in the second chunk. Two `/import` calls, and the result was `550 added · 50 updated · 0 skipped` — the duplicates counted as updates, not as a second creation. The rehearsal also listed all 50 with row numbers spanning the boundary (`ct-0000 (rows 1, 551)`), so duplicate detection runs over the whole file rather than per chunk. The feared divergence cannot happen: each chunk is written before the next is processed, so a later chunk sees what an earlier one created. |
| One unexplained test failure — **still not reproduced** | Seen once, long ago. Chased again on 2 September 2026: three more full runs (1540 passed each), plus five repeats of every suite that reads the current date — attendance, sales, projections, purchases, payments, notifications, inventory, reconcile. All green. The `hash()`-derived fixture that was the leading suspect is gone and no other per-process nondeterminism turned up. The remaining suspicion is a **day-boundary**: Django runs on `Asia/Kolkata` while timestamps are stored in UTC, so between 18:30 and midnight IST "today" differs depending on which clock a test asks. Those runs were inside that window and still passed, so it is a suspicion and nothing more. **Not proven, and not chased further until it is seen again** — there is no failure to debug, and inventing one costs more than it finds. |

---

## 4. Decisions I need from you

### ~~Citus: use it or drop it~~ — dropped, 2 September 2026

**The premise of this item was wrong, and that is the finding.** It said
"production runs Citus". Production does not. `scripts/go-live/deploy.sh`
picks the first compose file it finds, which is `docker-compose.demo.yml`,
and that has always been `postgres:16-alpine`. The only Citus in this repo
was an image pin in `docker-compose.prod.yml`, a file the droplet does not
use, and no table was ever distributed anywhere.

So there was never a running extension to switch on — only a belief that
sharding was half-solved, which is worse than not having it, because it is the
kind of thing somebody repeats to a customer. The pin is now
`postgres:16-alpine` in both files, with a comment saying what was there and
how to put it back. `docs/04` and `docs/05` said "Citus image in prod" and
"Citus is already the prod image"; both are corrected.

If one box turns out not to be enough, turning Citus on is a deliberate
migration made against numbers from the load test below — not a switch
somebody assumes is already flipped.

### ~~A `UNIQUE` constraint on `sku`~~ — done

Added on 27 August 2026 as `uniq_active_sku_per_shop`, on
`(shop, Lower(sku))` — case-folded, because a plain unique index in Postgres
is case sensitive while the till resolves a scan with `iexact`, and an index
that permits the collision it exists to prevent is worse than none.

Partial: blank codes are excluded (most shops leave most products without
one) and so are archived rows (they should not hold a code for ever).

Migration `0010` separates any duplicates already in the data before building
the index. The oldest row keeps its code — its labels are the ones already
printed — and the rest take a `-2`, `-3` suffix. **Watch the deploy output**:
it prints how many it had to separate, and those products now carry a
different code from the one on their shelf label.

---

## 5. Load test — Phase 4 of the scale plan

Seed a hundred times the data, drive real traffic, measure. Turns every
estimate in the scale review into an observation.

**Both halves now exist.** `seed_load` fills one shop; `scripts/load_test.py`
signs in and times the six reads a slow morning is actually felt through —
inventory list, stock on hand, sales history, dashboard, best sellers,
debtors — reporting p50/p95/max and the row count beside each, so a fast empty
answer is never mistaken for a fast one.

```bash
python manage.py seed_load <shop-id> --confirm      # on the staging box
python scripts/load_test.py --base-url http://127.0.0.1:8001/api/v1     --email owner@example.com --password ... --shop-id <shop-id> --rounds 30
```

The driver refuses hosts that look like the live shop. Overriding that needs
`--i-know-this-is-not-production`, and the reason is not politeness: a load
test against the box a shop is selling from is an outage you caused on
purpose, and the numbers are wrong anyway because a real till competes for the
same disk.

Exercised on 2 September 2026 against a local API with a small seeded shop
(300 products, 200 customers, 400 sales) purely to prove the tooling runs and
reports: worst p95 was 430 ms on the sales list. **Those numbers mean nothing
about scale** — SQLite, one machine, a fiftieth of the intended data. The real
run still needs a staging box with Postgres and the full seed.

Still deliberately after section 2: run before the media migration and the
numbers go stale the moment it happens. **Never against production.**

---

## Known, accepted, not worth fixing yet

- **Pre-existing lint warnings** — `setState` called synchronously inside an
  effect, in several components. Present before this session; each is a
  `void load()` on mount. Real, low value.
- **`nameKey` unused** in `lib/customer-match.test.ts`. Pre-existing, and the
  only lint error in the web app.
- **Sales history records no line items.** The importer stores flat bills,
  which is correct and safe. The consequence is that best-sellers cannot
  count imported sales — see `FUTURE.md`.
