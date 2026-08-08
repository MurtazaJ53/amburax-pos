# Which platforms Business Hub ships on

Two surfaces, deliberately.

| Surface | Status | Who uses it |
|---|---|---|
| **Flutter Android app** (phone + tablet) | Shipping | The counter — billing, stock, khata. Works with no signal |
| **Next.js admin web** (any browser) | Shipping | The owner — reports, purchasing, team, GST export |
| **Flutter iOS app** | Builds in CI, never run on a device | Added on request; unproven and unsigned. See "iOS" below |
| Windows desktop | Not shipped — see below | — |
| macOS / Linux | Not planned | No demand |

## Why not a desktop app

A Tauri project lived at `apps/desktop` until 8 Aug 2026. It was removed. It
was never an application: `index.html` still read "Welcome to Tauri" with the
Vite and TypeScript logos, `src/main.ts` was the template's `greet()` demo, and
`README.md` was the stock "Tauri + Vanilla TS" text. Only `tauri.conf.json` had
been edited — product name, identifier, window title.

Worse, its `frontendDist` pointed at `../../../dist`, the build output of the
**retired** React app. It was a shell aimed at a dead folder, and it made the
repository look as though a desktop client existed. Two CI jobs built and
published bundles of it for Windows, Linux and macOS; those were removed too.

The gap a desktop app would fill is already covered. A shop with a counter PC
can open the admin web in a browser today. The only thing a native desktop
client adds over that is **offline** billing on a PC — and offline is precisely
what the Android app already does, on hardware every shopkeeper already owns.
An Android tablet is also cheaper than the PC it would replace.

## If Windows is ever wanted, it is about a week

Flutter targets Windows, and this was verified rather than assumed. On
8 Aug 2026, `flutter create --platforms=windows .` followed by
`flutter build windows` produced a running `business_hub_mobile.exe` in about
twenty minutes, first attempt, no code changes. The scaffold was then reverted,
because carrying a platform folder implies support that is not being
maintained.

The build succeeding is misleading on its own: Flutter omits plugins that have
no Windows implementation, so the Dart code compiles and then throws
`MissingPluginException` when those features are used. The real work is:

| Plugin | Breaks | Approach |
|---|---|---|
| `blue_thermal_printer` | Bluetooth receipt printing | Use `printing` (already a dependency) → system/USB printer |
| `mobile_scanner` | Camera barcode scan | Guard it out; counter PCs use USB scanners, which behave as keyboards |
| `flutter_contacts` | Contact import | Guard it out; desktop has no contact book |
| `local_auth` | Biometric app lock | `local_auth_windows` (Windows Hello), or PIN only |

Beyond the plugins, the v3 screens were designed for phone and tablet, so they
run on a monitor but do not feel native — small touch targets, narrow layouts,
and the window title defaults to `business_hub_mobile`.

Estimate from that verified starting point: **1–2 days** to stop it crashing
and print through the system printer, **3–5 days** to be usable on a counter
PC, **1–2 weeks** to feel designed for a wide screen.

Regenerating the scaffold is one command, so nothing is lost by not carrying it.

## iOS

Added 8 August 2026 at the owner's request, after the reasoning above was put
to them. The table at the top still reflects where effort goes; iOS is built
but unproven.

**Nobody on this project can verify it locally.** Development happens on
Windows and Xcode is macOS-only, so the iOS target cannot be compiled, run or
tested here. `.github/workflows/flutter_ios_build.yml` runs on a GitHub-hosted
macOS runner and is the only check that the build is not broken — treat a red
run there as a failing test, because it is the sole signal.

It builds `--no-codesign`. Signing needs an Apple Developer account
(99 USD/year), a certificate and a provisioning profile, none of which exist.
An unsigned build proves the code compiles, the pods resolve and no plugin has
broken the target. It produces nothing installable on a phone.

### Plugin position is much better than Windows

Only one dependency is genuinely Android-only:

| Plugin | iOS |
|---|---|
| `mobile_scanner` | supported |
| `local_auth` (Face ID / Touch ID) | supported |
| `flutter_contacts` | supported |
| `blue_thermal_printer` | **not supported** |

iOS does not expose Bluetooth Classic SPP to apps — Apple permits BLE, or
accessories enrolled in the MFi programme — so a Classic-SPP thermal printer
cannot work there at all. `ReceiptPrinterService.supportsBluetoothPrinting`
now gates every entry point, throwing a `PrinterUnsupportedError` that names
the alternative rather than a bare `MissingPluginException` at the till.
`openCashDrawer` no-ops instead of throwing, because it is fired unawaited
after a sale and an exception would surface long after the bill printed.

Real iOS receipt printing would mean a BLE printer and a different package:
**2–3 days**, not started.

### Still required before anything ships to a phone

- Apple Developer Program membership, 99 USD/year
- A signing certificate and provisioning profile, added as repository secrets
- A Mac or a paid cloud-Mac service for on-device testing; the CI job cannot
  run the app, only build it
- App Store review

### Info.plist

Five usage descriptions were added for camera, Face ID, contacts and photo
library. Without them iOS terminates the app the first time a restricted API
is touched, and review rejects the build. The wording is specific on purpose —
reviewers reject vague strings such as "needed for the app to work".
