# Remaining work

What is outstanding right now, most important first. Everything here was
checked against the code on 27 August 2026, not written from memory.

Current state: **all commits pushed** to `pos`
(`github.com/MurtazaJ53/amburax-pos`). Backend 1,119 tests green, web 601
green, types clean, production build clean.

> Supersedes `docs/02_ROADMAP_AND_REMAINING.md`, which was last updated on
> 2026-07-19 and predates roughly forty commits of work.

---

## 1. None of it has been used in a browser

**The biggest gap, and the only one nobody but you can close.**

Everything in this repository is verified by tests, types and a production
build. No person has clicked:

- the import screen's wrong-kind warning, duplicate list, rehearsal or undo
- the data-health check tiles
- the receipt branding settings (logo, brand colour)
- the "Load more" buttons on Stock, Sales and Customers
- the transfers redesign
- the SKU generator on the label screen

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
| Delete `findExisting` in `lib/import-detect.ts` | Dead code I wrote. The rehearsal's `updated` count replaced it, produced by the real matching rules rather than a second guess at them. Only its own test references it. |
| Verify rehearsal counts across chunks | A file over 500 rows rehearses in chunks and the counts are summed client-side. I fixed exactly this class of bug for batches in `0336e74` and have not proven the same is right here. |
| One unexplained test failure | Seen once in a full backend run, not reproducible in five runs since. I removed the one nondeterminism I had introduced — a fixture deriving a phone number from `hash()`, which Python randomises per process. Likely that. **Not proven.** |

---

## 4. Decisions I need from you

### Citus: use it or drop it

Production runs Citus, a Postgres that can spread one table across machines
by a key. Shop id is exactly the shape this data has. **No table is
distributed**, so it behaves as ordinary Postgres.

Not a bug, and enabling it today buys nothing. It matters because it is the
real answer to "what happens at a hundred times the shops", and it is far
easier to switch on while the data is small. Carrying it unused is the one
option with no upside either way.

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
estimate in the scale review into an observation, and settles the Citus
question with evidence instead of reasoning.

Deliberately last: it would currently measure the un-migrated state, so its
numbers go stale the moment section 2 runs. **Never against production.**

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
