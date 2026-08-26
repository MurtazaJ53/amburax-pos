# Business Hub Operations Runbook

## Purpose

This document is for day-to-day operational response when something goes wrong in Business Hub.

## Common issue categories

### 1. Login or workspace recovery problems

Symptoms:
- user signs in but no shop loads
- user lands in recovery state
- staff account looks unassigned

Likely causes:
- claims are stale
- `users/{uid}` is missing `shopId`
- staff membership exists but local recovery has not run yet

First checks:
1. verify the user exists in Firebase Auth
2. verify `users/{uid}` exists
3. verify `shops/{shopId}/staff/{uid}` exists if they are staff/admin
4. verify Firestore rules allow the needed reads

### 2. Web shows data but Flutter does not

Likely causes:
- old web local SQLite contains data not yet synced to Firestore
- Flutter does not yet sync that data domain locally
- the Flutter account recovered the wrong or no shop context

First checks:
1. verify Firestore actually contains the missing data
2. verify the affected entity type is supported in Flutter sync
3. verify the user belongs to the correct shop

### 3. Flutter app looks polished but incomplete

Likely cause:
- UI has moved ahead of full feature parity

Action:
- compare requested flow against Sync Parity Matrix
- confirm whether the missing behavior is:
  - absent by design
  - partial
  - broken

### 4. Sales sync issues

Symptoms:
- sale saved locally but not visible elsewhere
- stock mismatch after sale

First checks:
1. verify sale exists in local client state
2. verify sale exists in Firestore `shops/{shopId}/sales`
3. verify stock updates also reached Firestore inventory docs
4. verify permissions on sale creation were valid

### 5. Performance issues

Symptoms:
- slow startup
- laggy scrolling
- delayed inventory/POS screen readiness

Likely causes:
- too much local data shaping on first paint
- missing Flutter parity leading to repeated retries or empty-state work
- old mobile path / WebView overhead if testing wrong app

First checks:
1. verify which app path is under test
2. verify local schema size and sync scope
3. verify target phone class

## Operational dashboards to trust

Right now, the most trustworthy operational truth sources are:
- Firestore data itself
- web/admin app for broader domain coverage
- Flutter mobile only for domains already implemented there

## Incident severity suggestion

### Severity 1

- sales cannot be recorded
- login broken for all users
- cloud data corruption risk

### Severity 2

- a major role cannot access its primary workflow
- sync broken for an important domain

### Severity 3

- UI mismatch
- partial parity gap
- non-critical mobile polish issue

## Recommended operational discipline

1. Always confirm whether issue is:
   - local-only
   - cloud truth
   - parity gap
   - rules problem

2. Never assume web and Flutter are identical yet.

3. Keep old app path available until Flutter cutover is fully signed off.

## Setting up a counter to print receipts

### What the browser will and will not do

`window.print()` always opens the print dialogue. There is no JavaScript, CSS
or browser setting that makes a normal web page print silently — it is a
deliberate security rule, because a page that could print without asking
could empty a paper tray. Anyone who tells you otherwise is describing kiosk
mode, which is below.

So a counter has two possible setups, and they are mutually exclusive:

| Setup | Tap to paper | Can also save a PDF |
| --- | --- | --- |
| Normal browser | dialogue, then Print | yes, "Save as PDF" in the dialogue |
| Chrome kiosk printing | prints immediately | no — it always goes to the default printer |

Pick per machine. A till that only ever prints receipts wants kiosk. A back
office that emails invoices wants the normal browser.

### Kiosk printing on a till

1. Set the thermal printer as the **Windows default printer**. Kiosk mode
   sends to the default and offers no choice, so this is the whole
   configuration.
2. Create a desktop shortcut with the flag:

   ```
   "C:\Program Files\Google\Chrome\Application\chrome.exe" --kiosk-printing --app=https://YOUR-HOST
   ```

   `--app=` opens it without tabs or an address bar, which is what you want on
   a counter. Use the shop's real host, not localhost, unless the till is the
   machine running the app.
3. Open the shortcut, complete a sale, press **Print or save PDF**. It should
   print with no dialogue at all.

If a dialogue still appears, the flag did not apply — check the shortcut is
being used rather than a pinned taskbar Chrome, and that no other Chrome
window was already open when it launched (Chrome reuses a running process and
ignores the flag).

### Paper

The receipt sets its own page size at print time: **76mm** for an Indian shop
and **80mm** for a UK one, taken from the shop's region, with automatic
height so a long bill runs down the roll instead of being cut into pages.

Nothing needs configuring for this. If a receipt prints on A4 with a strip of
content at the top, the page rule did not apply — that is a bug in the app,
not a printer setting, and it is worth reporting rather than working around
by changing the driver's paper size.

### Colour or plain

The receipt has a **Plain / Colour** switch beside the print button.

- **Plain** forces one ink. A thermal roll has one, and a grey heading on
  76mm paper is a heading nobody can read. This is the default and the right
  choice for a counter.
- **Colour** uses the shop's logo and brand colour. It is for the A4 or PDF
  copy a customer is emailed, and it is wasted on a thermal printer.

A shop's logo and brand colour are set in shop settings. A shop that has set
neither prints exactly what it printed before.

### What appears on the receipt

Only what a customer or a tax officer would want: the shop, the bill, the tax
breakdown, and — where the law requires it — the composition-dealer wording.

The closing line comes from the shop's own footer note. If a shop wants
"Exchange within 7 days with the bill", they set it; nothing is printed on a
shop's paper that the shop did not agree to.

## Moving product photos out of the database

Photos used to be base64 text in a column on the product, so they travelled
with every backup and every replica of the table the till reads. New photos go
to object storage automatically. This moves the ones written before that.

### Choose where they live

`BLOB_STORE=filesystem` (the default) keeps them in the `media_data` Docker
volume at `/var/lib/bhub/media`. No vendor, no cost, no extra dependency —
but **that volume must be in your backups.** Unlike the database it has no
dump, and losing it loses every picture. It also dies with the droplet.

`BLOB_STORE=s3` puts them in DigitalOcean Spaces, Cloudflare R2 or AWS S3 —
all three speak the same protocol and differ only by endpoint. Set:

```
BLOB_STORE=s3
BLOB_S3_BUCKET=business-hub-media
BLOB_S3_ENDPOINT=https://blr1.digitaloceanspaces.com
BLOB_S3_REGION=blr1
BLOB_S3_ACCESS_KEY=...
BLOB_S3_SECRET_KEY=...
```

This needs `boto3` installed. It is imported only when the S3 backend is
built, so a filesystem deployment never needs it.

### Run the move

Always dry-run first. It writes nothing and tells you how much would move:

```
docker compose -f docker-compose.prod.yml exec api \
  python manage.py migrate_product_images --dry-run
```

Then for real:

```
docker compose -f docker-compose.prod.yml exec api \
  python manage.py migrate_product_images
```

Safe to interrupt and safe to re-run. A product is only cleared from the
column once its bytes are confirmed readable back out of the store, and the
image endpoint reads the store first and falls back to the column — so while
it runs, moved and unmoved products both show their pictures.

Rows whose text will not decode are skipped and left untouched, and named on
stderr. They were already broken; the command moves pictures, it does not
decide something is rubbish and delete it.

### If you switch stores later

Set the new `BLOB_*` values and run the command again. It only picks up rows
still holding a photo in the column, so **it will not copy objects from one
store to another** — move those with the vendor's own tooling (`rclone`, `aws
s3 sync`) before switching.
