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

Photos are still in the database. New ones go to storage; the existing ones
have not moved. Nothing is broken — the image endpoint falls back to the
column — but the payload saving is not realised until this runs.

```bash
docker compose -f docker-compose.demo.yml exec api \
  python manage.py migrate_product_images --dry-run   # writes nothing

docker compose -f docker-compose.demo.yml exec api \
  python manage.py migrate_product_images
```

**Before running it**, confirm the droplet has been redeployed since commit
`804964a`. That commit added the `bhub_media` volume to
`docker-compose.demo.yml` — the file `deploy.sh` actually uses. Without it,
`BLOB_ROOT` falls back inside the container and the migration would move
every photo somewhere the next deploy throws away.

**Also confirm `bhub_media` is in your backups.** Unlike the database it has
no dump, and losing it loses every product photo.

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
