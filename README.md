# CUFMAI

**The official app of the Carcar United Footwear Manufacturers Association, Inc. — a marketplace for handcrafted footwear from Carcar City, Cebu.**

Carcar City is long known as the "Footwear Capital of the South", and shoemaking is a generations-old heritage craft there, centred on the barangays of Poblacion 3, Liburon and Valladolid. In 2004 the town's independent shoemakers organised as **CUFMAI** — the Carcar United Footwear Manufacturers Association, Inc. — to turn a scattered craft tradition into one recognised local industry.

This app is that association's marketplace. It gives CUFMAI's member artisans the tools big brands have — a storefront, an order pipeline, and a point of sale — while keeping the craft the point: buyers outside Carcar can discover and order handcrafted leather shoes and sandals directly from the makers.

One Flutter app serves all three roles. Two React apps run alongside it against the same Supabase project: the admin portal (`admin-portal/`) and the customer-facing storefront (`customer-portal/`).

---

## The three roles

| Role | Who | What they get |
|------|-----|---------------|
| **Customer** | Shoe buyers | Browse stores and products, cart, checkout (cash / GCash / card), order tracking, customized orders, foot sizing, messaging, reviews |
| **Seller** | CUFMAI artisan members | Storefront, product & inventory management, online order flow, in-person POS, revenue reports, customer chat |
| **Admin** | Marketplace operator | Seller application review, user & product management, revenue and order analytics |

Access is decided by `profiles.role` (`customer` / `seller` / `admin`) plus `seller_status` (`none` / `pending` / `approved` / `rejected`) — a seller who applies during sign-up lands on a pending screen until an admin approves them.

---

## What's in the app

**Customer**
- Home feed with a masonry catalog, category rows, audience shelves (Men's / Women's / Kids' / Unisex), an On Sale poster, and a "Based on your size" shelf drawn from a saved foot measurement
- Search with suggestions, history, and a results page; shelves that search, filter and sort in place
- Store discovery, store pages, follow/unfollow and store messaging
- Store-grouped cart, stock validation at checkout, delivery fee, and an address book with map pin-drop
- Payments via PayMongo (GCash) with a webhook-backed status flow, plus cash on delivery/pickup
- Order timeline (Placed → Preparing → Ready → Received), vouchers, pickup reservations, and a 5-step custom shoe wizard
- Foot sizing: AR-assisted scanning and manual entry, with US/UK labels
- Dark mode, biometric sign-in, MFA, and new-device verification

**Seller**
- Dashboard with today's sales and order metrics
- Product and variant management (size / color / stock), with image uploads
- Online order flow with status management and delivery or pickup handling
- **POS** for walk-in sales — cash, GCash or card, including custom orders and vouchers
- Revenue reporting that combines online orders with POS transactions, plus store reviews

**Admin**
- Seller application approval, user suspension, product management
- Analytics: revenue, orders, top products and trends
- Available both in the Flutter app and the React web portal

---

## Tech stack

| Layer | Technology |
|-------|------------|
| Mobile app | Flutter 3.44 (Dart), `provider` for state management |
| Backend | Supabase — PostgreSQL with Row-Level Security, Auth, Storage, Realtime, Edge Functions |
| Admin portal | React + Vite + Tailwind CSS, TanStack React Query (`admin-portal/`) |
| Customer storefront | React + Vite + Tailwind CSS, TanStack React Query, `motion` for animation (`customer-portal/`) |
| Payments | PayMongo (GCash) with Edge Function webhooks (`create-gcash-payment`, `gcash-webhook`); manual GCash QR fallback |
| Push | Firebase Cloud Messaging + `flutter_local_notifications` |
| On-device ML | Google ML Kit — pose detection and selfie segmentation (foot sizing, try-on), text recognition |
| Maps | `flutter_map` + MapTiler geocoding (proxied through an Edge Function) |
| Currency | Philippine Peso (₱) |

---

## Repository layout

```
lib/
  main.dart              App entry, provider wiring, Supabase + Firebase init
  constants/             Theme, brightness, app-wide constants (incl. update URLs)
  models/                Data models
  providers/             State management (one per feature area)
  screens/
    auth/  customer/  seller/  admin/  store/  shared/
  services/              Data access and platform integrations
    supabase_service.dart, auth_service.dart, order_service.dart, ...
  utils/                 Pure helpers (pricing, sale rules, formatting)
  widgets/               Reusable UI
admin-portal/            React admin web portal
customer-portal/         React customer storefront (web)
supabase/
  migrations/            Ordered SQL migrations (schema, RLS, triggers)
  functions/             Edge Functions (payments, push, geocoding, uploads)
releases/                Release tooling + the in-app update manifest
test/                    Unit + widget tests (mirrors lib/)
docs/                    Architecture references and session logs
```

The layering is `screen → provider → service → Supabase`. Business rules live in one place and are inherited — for example, "is this on sale?" is `isOnSale` in `lib/utils/sale_price.dart`, used by the product cards, the home On Sale poster, and the store sale tags alike, so the three can never disagree.

---

## Getting started

### Prerequisites

- Flutter 3.44+ (`flutter --version`)
- A Supabase project (URL + anon key)
- Optional, for the pieces that need them: a MapTiler key, Firebase project files, Play/other ML Kit setup

### Configuration

Supabase and MapTiler values live in **`lib/constants/app_constants.dart`**, not in dart-defines. For local builds that also need the release-update check, copy `dart_defines.json.example` → `dart_defines.json` (git-ignored).

### Run

```bash
flutter pub get
flutter run
```

### Test

`flutter test` covers the app without a network or a Supabase instance; tests that would need them use fakes from `mocktail`.

```bash
flutter analyze lib test     # must stay clean
flutter test                 # full suite
flutter test test/utils/sale_price_test.dart   # a single file
```

CI (`.github/workflows/ci.yml`) runs `flutter analyze --no-pub` and `flutter test --no-pub --coverage` on every push and pull request to `main`.

### Android install notes

Sideloading an APK requires the downloading app (browser, file manager) to have **Install unknown apps** enabled: Android Settings → Apps → Special app access → Install unknown apps. It's a per-app user setting the app cannot request itself.

---

## Documentation

| Document | What it covers |
|----------|----------------|
| `docs/ABOUT_SOLEVISION.md` | What the app is, the problem it solves, who it's for |
| `docs/SoleVision_Complete_Documentation.md` | Master reference — schema, RLS, services, history |
| `docs/AI_PROJECT_SUMMARY.md` | Quick reference for the whole project |
| `docs/PROJECT_HANDOFF.md` | Decisions, known issues, what's next |
| `docs/RELEASE_SIGNING.md` | The Android release key, why in-app updates require it, the one-time reinstall |
| `docs/AI/` | Per-feature architecture notes (checkout, POS, foot sizing, notifications, …) |

---

## In-app update checker

During development/testing the app checks a **self-hosted** JSON file for a
newer build and lets testers download the new APK without plugging the phone
into a laptop. This is **not** Play Store's in-app update API (that comes
later once published).

### Where the files live

The URLs are configured in **one place**: `lib/constants/app_constants.dart`
(`updateManifestUrl` and `updateChangelogUrl`). They currently point at the
public GitHub repo `kibs06/CUF` via raw.githubusercontent:

- `https://raw.githubusercontent.com/kibs06/CUF/main/releases/version.json`
- `https://raw.githubusercontent.com/kibs06/CUF/main/releases/changelog.json`

So publishing a build is simply: **commit the updated files to the `releases/`
folder in that repo's `main` branch.** (Any static HTTPS host — Supabase
Storage, GitHub Pages, Netlify — works too; just update the two constants.)

### Expected JSON shape

**`version.json`** (the current release manifest):

```json
{
  "latest_version": "1.4.0",
  "apk_url": "https://example.com/releases/app-release-1.4.0.apk",
  "released_at": "2026-08-01",
  "notes": ["Fixed login crash on Android 14", "Improved startup time"]
}
```

**`changelog.json`** (historical patch notes, newest first — same shape per
entry, an array of release objects):

```json
[
  { "latest_version": "1.4.0", "apk_url": "...", "released_at": "2026-08-01", "notes": [...] },
  { "latest_version": "1.3.2", "apk_url": "...", "released_at": "2026-07-20", "notes": [...] }
]
```

Versions are compared semantically, so `1.10.0` is correctly detected as newer
than `1.9.0`. If the fetch fails (no internet, host down, malformed JSON) the
app stays silent — no crash, no blocking, no popup.

The changelog is cached locally (SharedPreferences, 24h TTL) so the What's New
screen loads instantly and still shows the last known release notes offline. A
pull-to-refresh on that screen forces a fresh fetch.

### Auto-release via GitHub Actions (recommended)

The repo ships `.github/workflows/release.yml`, which does the whole release
whenever you push a `vX.Y.Z` tag:

1. Builds the release APK, signed with the project's release key — supplied to
   CI through repository secrets, and **the job fails without them** (a
   debug-signed release cannot be installed over any previous release; see
   `docs/RELEASE_SIGNING.md`).
2. Rewrites `releases/version.json` + prepends `releases/changelog.json` on
   `main` (version taken from the tag, notes read from the annotated tag
   message — one bullet per line).
3. Creates a GitHub Release `vX.Y.Z` with the APK attached as
   `app-release-<version>.apk`, and commits the JSON updates to `main` so the
   in-app update checker resolves immediately.

```bash
# 1. Bump version: in pubspec.yaml, commit, push to main
# 2. Create an annotated tag with the release notes (one bullet per line)
git tag -a v1.0.1 -m "Fixed login crash
Improved startup time"
# 3. Push it — the workflow takes it from here
git push origin v1.0.1
```

Release builds are signed with `android/app/cufmai-release.jks`, created once
by `tool/setup_release_signing.sh`, which also prints the four repository
secrets CI needs (`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`,
`ANDROID_KEY_ALIAS`, optional `ANDROID_KEY_PASSWORD`). **Every release must be
signed with that one key** — Android refuses to replace an installed app whose
signing certificate differs, which is what "App not installed." means when the
in-app updater hands over a new APK. Read `docs/RELEASE_SIGNING.md` before
touching any of it. (Supabase/MapTiler values come from `app_constants.dart`,
not dart-defines, so these are the only secrets involved.)

### Feature switches in a release

New visible surfaces ship **dark**: each one reads a compile-time switch from
`AppConstants` (`bool.fromEnvironment(...)`), so a build that never passes the
define behaves exactly like the release before the feature existed. The app's
switches, and their shipped defaults:

| Switch | Default | What it gates |
|--------|---------|---------------|
| `SHOE_MODEL_UPLOAD` | **on** | the seller's 3D-model upload section in the product form |
| `SHOE_MODEL_REQUEST` | **on** | the **3D fitting request** row in the seller's product action sheet (ask the CUFMAI team to model the pair) and the admin queue that answers it. Its “3D fitting ready” state opens the model itself — the seller’s viewer resolves the product’s model on their own device and draws it, or says plainly that there is nothing to draw |
| `ADMIN_MODEL_UPLOAD` | **on** | the admin's “Upload a 3D model” action in that queue |
| `SHOE_PREVIEW` | **off** | the **3D icon in the lower-right corner of the product photograph**, which opens the full-screen 3D viewer (`ShoePreviewScreen`); “Try On in AR” is the escalation inside that viewer. Off means no 3D entry on the page at all — the pinned AR pill it used to fall back to came off on 2026-10-01. A product whose model is verified on disk shows the icon *and*, inside the viewer, the AR button; a product with no model shows **neither**. Needs no ARCore and no camera permission (no session is created), but it does need the model verified on disk, so it rides on `TRY_ON_PREFETCH`. ⚠️ It ships off because nobody has seen a render on hardware yet |
| `SHOE_PREVIEW_DIAGNOSTICS` | **off** | a QA second line under the box's refusal sentence, carrying the **measured renderer facts** — the native reason, the backend, Filament's supported/active feature level and the device's advertised GLES version. It exists because the phone this was written for (a P30 Pro with locked developer options) has no reachable logcat, so the diagnosis has to be on the page. The line deliberately does **not** claim cube-map-array support: that extension string is on `ActivityManager.DeviceConfigurationInfo.glExtensions`, which is not in the public SDK, so `supported=` is the proxy for it. Never customer copy |
| `SHOE_PREVIEW_ALLOW_LEVEL1` | **off** | ⚠️ **QA only, and the one switch here that can kill the app.** It asks the renderer to attempt a glTF load below Filament's `FEATURE_LEVEL_2`, where it has always refused, because that load was a `SIGSEGV` on an emulator (F22) and level 1 has never been tried on real hardware (F14, D10). It is a measurement, not a surface. Two locks: this define, and the native side, which honours a `true` only in a **debuggable** build (a shipped release APK is not) and announces the build on the product page |
| `SHOE_PREVIEW_LOWER_ENGINE_TO_LEVEL1` | **off** | ⚠️ **QA only: builds (or lowers) the Filament engine at `FEATURE_LEVEL_1`** — `Engine.Builder.featureLevel` when the engine does not exist yet, `Engine.setActiveFeatureLevel` when it does. It is the *other half* of the switch above: on a level-2 phone the refusal never fires, so the override alone proves nothing, and a level-1 engine cannot be obtained from the owner's phone on demand. Used **alone** it reproduces the P30 Pro's condition (the box shows the refusal line with `supported=FEATURE_LEVEL_2 active=FEATURE_LEVEL_1`); used **with** `SHOE_PREVIEW_ALLOW_LEVEL1` it is the experiment — whether a level-1 renderer can draw a shoe at all. It only ever *lowers* (the ceiling is what the driver resolved), so a level-1 or level-0 device is unaffected. Two locks, the same two: this define, and a **debuggable** build |

A switch that is never passed is **not** the same as a switch passed as `false`
— both mean "off", but only the first is invisible in a release log. That is
how a flag-gated surface ends up reported as "missing" from a build whose
release notes announce it.

- **In CI (tagged releases):** set the repository variable
  `RELEASE_DART_DEFINES` (Settings → Secrets and variables → Actions →
  Variables) to a space-separated list, e.g.
  `SHOE_MODEL_REQUEST=true ADMIN_MODEL_UPLOAD=true`. The build step passes each
  one as `--dart-define=` and **echoes the full command** it ran, so the release
  log answers "does this APK have the request flow?" without rebuilding it.
  Unset means every switch keeps its shipped default.
- **Locally:** `dart_defines.json` (git-ignored) — `releases/publish.sh` passes
  it with `--dart-define-from-file` when it exists.
  `dart_defines.json.example` lists every switch at its shipped default, so
  copying it changes nothing.

Both 3D-model switches are **on** by default since 2026-09-29, which is the end
of a two-step job that took longer than the code did:

1. `supabase/manual/20260928140000_add_shoe_model_requests.apply.sql` was applied
   in the SQL Editor and confirmed with the bundle's own PART 2 query — **twelve
   true, `ALL CHECKS: true`** (`supabase/MIGRATIONS_LIVE_STATUS.md`).
2. `RELEASE_DART_DEFINES=SHOE_MODEL_REQUEST=true ADMIN_MODEL_UPLOAD=true` was
   set, and v1.0.33 shipped carrying both.

While the defaults were `false` they did one useful thing and one harmful one.
Useful: the row writes through an RPC, so on a database without that migration a
tap answers "function does not exist", and shipping it hidden is the V2.2 lesson.
Harmful: with the migration live, `false` no longer protected anybody — it hid
the row from **every build that passes no dart-defines** (an IDE's Android App run
configuration, a bare `flutter run`) while the tagged release of the same commit
had it, which is how a shipped feature gets reported as missing. A deliberate
`--dart-define=SHOE_MODEL_REQUEST=false` still turns it off.

### One-command release script (local alternative)

The `releases/` folder ships a small local release toolchain you can run from
your machine instead of pushing a tag:

- **`releases/publish.sh`** (or **`releases/publish.bat`** on Windows) — one
  command that does everything below: bumps `pubspec.yaml`, builds the APK,
  rewrites `version.json`, prepends `changelog.json`, commits + pushes, then
  creates a GitHub Release with the APK attached.
- **`releases/update_release_files.dart`** — the file-surgery helper the script
  calls (pure Dart, no extra deps).

```bash
# Example: ship v1.0.29
./releases/publish.sh 1.0.29 "A store that's on sale now says so|Fixed: a rail card's name sits on its own edge"
# Windows:
releases\publish.bat 1.0.29 "A store that's on sale now says so|Fixed: a rail card's name sits on its own edge"
```

Requirements: Flutter on PATH, the GitHub CLI (`gh`) installed + authenticated
(`gh auth login`), and the release signing key in place
(`android/key.properties` + `android/app/cufmai-release.jks`). Install gh with
`winget install GitHub.cli` (Windows) or `brew install gh` (macOS). The script
stops rather than publish a debug-signed APK no device could install.

### Manual release checklist

If you'd rather publish by hand:

1. Bump `version:` in `pubspec.yaml` (e.g. `1.4.0+8`).
2. Build the release APK: `flutter build apk --release` (with
   `android/key.properties` present, so it is signed with the release key).
3. Create a GitHub Release tagged `v1.4.0` and attach the APK **renamed** to
   `app-release-1.4.0.apk` (the in-app Download button uses that exact URL).
4. Update `releases/version.json` with the new version + APK URL + notes.
5. Prepend the same entry to `releases/changelog.json`.
6. Commit and push `pubspec.yaml` + both JSONs to `main`.

## QA builds — a measurement, not a release

**Where to get one:** [**Actions → QA APK (not a release)**](https://github.com/kibs06/CUF/actions/workflows/qa-apk.yml)
→ *Run workflow* → open the finished run → the **Artifacts** box holds
`solevision-qa-instrumented-apk`. It is a `.zip`, so unzip it before installing,
and it expires after 30 days — dispatch a fresh one whenever it lapses, or from
a terminal:

```bash
gh workflow run qa-apk.yml -f diagnostics=true -f lower_engine=true -f allow_level1=true
```

**Why it is not a release.** The three `SHOE_PREVIEW_*` QA switches are honoured
only in a **debuggable** APK (a published release is not `FLAG_DEBUGGABLE`, so it
ignores them — see the switch table above), and they measure the renderer rather
than serve a customer. The APK is also ~244 MB, which GitHub refuses in an
ordinary push, so it cannot live in the tree either: a workflow artifact is the
one place it can exist without being a release. When the release signing secrets
are present the artifact is **re-signed with the project key**, so it installs as
an ordinary *update* over the shipped build — same package, same signer, login
kept — while staying debuggable.

**What it does that a release cannot.** It carries the renderer's own heartbeat
printed under the box (loop iterations, frames actually presented, refused
frames, swap-chain rebuilds, engines, touches) and parks the last line in a file,
so a crash still leaves the previous process's final words on the screen. That is
the only diagnostic channel for the phones this was written for: the test device
has developer options locked behind a password its previous owner set, so
`adb logcat` will never be read from it. Local builds of the same thing live in
`build/qa/` (git-ignored).
