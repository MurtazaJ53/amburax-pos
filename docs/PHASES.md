# Business Hub — phased plan

Written 9 August 2026.

Each phase has an **exit criterion**: the thing that must be true before the
next one starts. A phase is not finished when its tasks are done, it is
finished when its criterion holds. That distinction is the point of planning it
this way — otherwise work continues because it is enjoyable rather than because
it is next.

---

## The position, stated plainly

| | |
|---|---|
| Backend tests | 679 |
| Counter app tests | 327 |
| Admin web tests | 105 |
| Features complete for a first shop | Yes |
| **Real users** | **Zero** |

The product is finished enough to be used and has never been used. Everything
built since the first deployment has been built on assumptions no shopkeeper
has tested. That is the single most important fact on this page, and it
determines the order of everything below.

---

## Phase 1 · Go live — one real shop

**Exit criterion: a shopkeeper who is not the developer bills a real customer
through the product, on their own device, without help.**

Nothing in this phase is engineering. That is deliberate. It is also the reason
it keeps being deferred — the tasks are small, unglamorous, and each one is
somebody else's blocker.

| Task | Owner | Effort |
|---|---|---|
| Point `app.amburax.com` at the droplet, certbot, nginx | Owner | 20 min |
| Tighten `DJANGO_ALLOWED_HOSTS` off `*`, add CSRF origins | Owner | 5 min |
| Move the backend to `api.amburax.com` | Owner | 15 min |
| Add the hourly cron entry for alerts | Owner | 1 min |
| Rotate the two exposed passwords, clear bash history | Owner | 5 min |
| Hindi/Gujarati review of the counter app | Owner | 1–2 hrs |
| Install the current build on the shopkeeper's phone | Owner | 30 min |

`amburax.com` already exists on Cloudflare, so the domain that blocked this for
weeks is no longer a blocker.

**Roughly half a day of work, and it is worth more than everything in Phase 2.**
Until a real shop uses this, every priority below is a guess.

---

## Phase 2 · Close the daily loop

**Exit criterion: the shop goes a full week without reaching for paper or a
calculator.**

Phase 1 will produce a list of what actually breaks. This is what I expect that
list to contain, and it should be re-ordered once real usage contradicts it.

### Returns and exchanges — 3–5 days

The ledger already has a `return` event type and there is no flow that uses it.
A customer bringing a shirt back for a different size is routine in garment
retail, and today the shopkeeper has to fake it with an adjustment and a fresh
bill, which breaks the audit trail the whole design rests on.

**This is the largest hole in daily operation and should be built first.**

### Stocktake mode — 3–5 days

A guided physical count: scan the shelves, see counted against expected, post
one reconciled set of adjustments with a variance report. Today a stocktake
means correcting items one at a time, which nobody will do for a whole shop —
so nobody does it, and the stock figures drift until they are not trusted.

### Whatever Phase 1 exposes — unknown

Reserve time for this. Something will be wrong that nobody predicted, and it
will matter more than either item above.

---

## Phase 3 · Prove it beyond one shop

**Exit criterion: three shops in different trades are using it, and the
reporting is trusted enough to act on.**

One garment shop is enough to show the system works somewhere real. It is not
enough to claim it generalises — a kirana selling by weight and a pharmacy with
batch and expiry rules would exercise the design very differently.

### Supplier price history — 2–3 days

Purchase orders already capture quoted versus billed rates. Tracking that over
time shows which supplier is quietly raising prices, which is information a
shop currently has no way to see at all.

### UPI payment reconciliation — 4–6 days

A UPI payment is recorded today because the cashier says it happened. Matching
against a gateway settlement feed would confirm the money arrived and flag the
ones that did not. Worth doing once there is enough volume for a discrepancy to
be plausible, and not before.

### Data quality work — ongoing

Cost prices are optional, and several reports withhold a figure when they are
missing. That is correct behaviour, but a shop that never records cost sees a
product full of blanks. Phase 3 is when it becomes clear whether the answer is
better prompting, an import path, or accepting it.

---

## Phase 4 · Reach

**Exit criterion: a shop can find, install and pay for the product without
being introduced to it.**

Deliberately after Phase 3. Distribution before the product is proven means
acquiring users who churn, and churned users do not come back.

| | Effort | Prerequisite |
|---|---|---|
| Play Store release | 2–3 days plus review | A new keystore, backed up off-machine |
| WhatsApp Business API | 3–5 days | Meta business account, template approval, per-message cost |
| Billing live on Razorpay | 1–2 days | Already built; needs live keys and a tested checkout |
| iOS on a device | ~1 week | Apple Developer account, a Mac. Builds in CI today, has never run on a phone |

---

## Phase 5 · Intelligence

**Exit criterion: none set. Nothing here should start until a shop asks for it
by name.**

- **Demand forecasting.** Needs a year of clean trading history to be anything
  other than guesswork, and must show its reasoning — no shopkeeper will spend
  money on a number they cannot interrogate.
- **Customer order-ahead.** The khata statement page proves customers will open
  a link from their shop; the same pattern could carry a monthly kirana list.
- **Offline-capable web app.** Only worth it if shops actually run the web POS
  during trading, which no evidence currently suggests.

---

## Not planned

Recorded so they stop being re-proposed.

| | Why |
|---|---|
| GST e-invoicing (IRN) | Mandatory only above ₹5 crore turnover, far above the target shop, and needs a paid GSP account |
| Windows desktop client | Measured at 1–2 weeks and genuinely feasible; the gap it fills is already covered by the Android app on hardware shops already own |
| macOS / Linux clients | No demand |

---

## The one thing to take from this

Phases 2 to 5 describe about four months of work, and every priority in them is
a guess made by the person who wrote the software. **Phase 1 is half a day and
replaces those guesses with evidence.**

It should start today, and nothing in Phase 2 should begin until it is done.
