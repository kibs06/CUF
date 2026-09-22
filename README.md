# SoleVision

**A multi-role marketplace for handcrafted footwear from Carcar City, Cebu.**

Carcar is the hometown of the Philippine shoe industry, but its artisans — mostly members of **CUFMAI** (Carcar United Footwear Manufacturers Association Inc.) — sell through traditional channels with no digital storefront, so buyers outside the city have no easy way to find them. SoleVision gives those makers the tools big brands have — a storefront, an order pipeline, and a point of sale — without replacing the craftsmanship.

One Flutter app serves all three roles, with a React portal for web administration.

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

1. Builds the release APK (debug-signed, same as local builds).
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

No secrets are needed: release builds use the debug signing config and the
app reads its Supabase/MapTiler values from `app_constants.dart`, not
dart-defines.

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

Requirements: Flutter on PATH and the GitHub CLI (`gh`) installed +
authenticated (`gh auth login`). Install gh with `winget install GitHub.cli`
(Windows) or `brew install gh` (macOS).

### Manual release checklist

If you'd rather publish by hand:

1. Bump `version:` in `pubspec.yaml` (e.g. `1.4.0+8`).
2. Build the release APK: `flutter build apk --release`.
3. Create a GitHub Release tagged `v1.4.0` and attach the APK **renamed** to
   `app-release-1.4.0.apk` (the in-app Download button uses that exact URL).
4. Update `releases/version.json` with the new version + APK URL + notes.
5. Prepend the same entry to `releases/changelog.json`.
6. Commit and push `pubspec.yaml` + both JSONs to `main`.
