# CUFMAI / SoleVision — Gap Analysis (2026-11-07)

Source: full-repo search of Flutter `lib/`, `admin-portal/`, `customer-portal/`, `supabase/migrations + functions + tests`, `docs/` (roadmaps, handoff, AI notes), plus code search for `TODO / coming soon / placeholder / stub`.

> Note: `docs/RoadMap/SOLEVISION_ROADMAP.md` still says "38 tests, ~5% coverage" — `test/` now holds **228 Dart test files** plus 14 pgTAP suites. Treat coverage numbers in older docs as stale.

## 1. Mobile app (Flutter) — unfinished surfaces

All of these are live `TODO` / "coming soon" strings today, not roadmap wishes:

- ~~`lib/widgets/order_change_request_sheet.dart:175,185` — "Order details coming soon" / "Support chat coming soon"~~ **FIXED 2026-11-08:** overflow menu now navigates — View Order Details fetches the full order (`SupabaseService.fetchOrderWithItems` for customers → `OrderTrackingScreen`, `fetchSellerOrderById` for sellers → `OrderDetailScreen`) and Contact Support pushes `SupportChatScreen`. `ChatView._navigateToOrder` (order chips in messages) fixed the same way with role branching. `flutter analyze` clean on all three touched files; no pre-existing tests cover these paths.
- `lib/screens/account/account_security_screen.dart:348` — "Passkeys coming soon".
- `lib/screens/customer/my_orders_screen.dart:346` — SMS opt-in TODO, "SMS order updates — coming soon!". - ~~`lib/screens/customer/buy_again_screen.dart:110` — "Add search within orders" TODO.~~ **FIXED 2026-11-08:** search icon now toggles an autofocused AppBar search field; the query filters every tab live against order ID, store name, and product names, with a clear button, back-arrow to exit search mode, and a "No matching orders" empty state quoting the query. `flutter analyze` clean; debug build pushed to the connected phone (VOG L29). - ~~`lib/screens/seller/reports_screen.dart:97,452` — CSV export is still a SnackBar stub ("CSV export coming soon!").~~ **FIXED 2026-11-08:** both the AppBar download icon and the Export-section button now build a real CSV (BOM-prefixed for Excel, same pattern as the admin transactions export: report header + period, summary with totals and % change, daily-revenue rows, ranked top-products rows) and open the platform share sheet via `share_plus`/`Directory.systemTemp` — no new dependencies. Buttons disable with a "Preparing CSV…" state while exporting; AppBar tap before load shows "still loading". `flutter analyze` clean. PDF export remains open (was bundled with this item in Roadmap Phase 6).
- `lib/screens/messages/chat_view.dart:1265,1336` — store-ID navigation TODO, `targetSellerId: null // wire seller ID`.
- `lib/services/push_notification_service.dart:49` — seller-shell navigation TODO.
- Foot sizing pipeline is half-simulated: `foot_capture_screen.dart`, `foot_instructions_screen.dart`, `foot_processing_screen.dart` all carry `TODO(paper-scan)` — measurements are simulated, no real CV pipeline.
- AR try-on: `ar_fitting_screen.dart` is still the simulated feed. Real V3/V4 renderer exists behind `TRY_ON_V3=false`, `TRY_ON_FOOT_TRACK=false`, QA seams (`TRY_ON_PLACEHOLDER_MODEL`, `SHOE_PREVIEW_ALLOW_LEVEL1`, etc.). `product_models` table is **0 rows** — the whole model pipeline is reachable but unpopulated. 13+ bundled `.deepar` effects + `foot-v1.onnx` (~11 MB) + placeholder GLBs ship in `pubspec.yaml` assets — APK bloat (+27.7 MB renderer vs ≤8 MB target per roadmap).
- Customizations can be *written* from both app and portal, but no customer surface lets anyone *choose* an option — app passes `customizations: null` into cart. Dead-end feature.
- `products.is_published` gap was fixed in portal's `catalog.js`; verify the same filter exists in every Flutter read — historically the phone's checkbox hid from seller list but left the product on sale.

## 2. Customer portal (`customer-portal/`)

Detailed in its own README — deliberately absent, not forgotten:

- No POS, no custom-orders page (`custom_order_request` notification is inert), no "message this customer" on orders, no store creation (needs app map picker), no 3D-model request form (points to app), no per-colour gallery read (`product_color_images` written but never read — shop falls back to product gallery).
- Seller is force-redirected out of the shop (`AppLayout` → `/seller`); `/settings` closed to sellers with a separate `/seller/account`. Easy to break on each new customer route.
- Deploy footgun: host must rewrite all paths to `/index.html` (documented for Netlify/Vercel/Firebase) or shared `/product/:id` links 404 on refresh.
- Business rules are hand-ported (`pricing.js`, `stock.js`, `searchRules.js`, `sellerRules.js`, swatches). Any Dart change must be mirrored in JS — drift risk. Tests exist (`npm test`) but only cover pure rules.

## 3. Admin portal (`admin-portal/`)

- Ships its own GLB pipeline: file-picker + link publish, in-browser decimate+normalize via checked-in `glb_normalizer.gen.js` (512 KB). Rebuild contract tested, but Dart→JS drift breaks `npm test` until `tool/build_shoe_model_normalizer_web.mjs` is re-run.
- Model publish gated by `VITE_ADMIN_MODEL_UPLOAD=true`; queue empty-state must check `device_gate_open()` or a gated session looks like "nothing waiting" — subtle, documented in README.
- README's "Supabase requirements" section is stale (says suspension columns "optional" — they shipped in `20260813000000`).

## 4. Backend / Supabase — the riskiest gaps

From `supabase/MIGRATIONS_LIVE_STATUS.md` (source of truth, not `migration list`):

- **Not applied:** `20260917120000_add_pickup_reservation_color.sql` (needs drop+recreate of RPC, 42725 ambiguity), `20261012120000_add_location_to_failed_logins.sql` (lockout city-level geo; app has fallback retry but live has no columns), `20260915150000` device-gate edit (product_models exemption — live function returns 22 names, repo 23).
- **Blocked:** `pg_cron` not installed → `20260817150000` auto-schedule + `expire-online-gcash-payments` sweep never run. Stale pending GCash intents previously bricked checkout for a real customer.
- **Fragile process:** `db push` is broken (prefix collisions `20260714*`, etc.) — do not follow its "revert" advice. All applies are manual SQL Editor runs tracked by hand in the status file.
- `notifications` was never added to `supabase_realtime` publication — customer feed refetches on focus; only `seller_notifications` is truly realtime. Silent-subscription trap.
- Schema inconsistencies: `products` PK is TEXT, `product_variants.id` UUID, `product_models.variant_id` TEXT with no FK; `inventory` derived from `product_variants` by app code (`_syncInventoryFromVariants`), no DB trigger — dual source of truth.
- 14 pgTAP files pass locally (`supabase db reset` green) but live ≠ local; `admin_account_security` sweep, voucher, pickup, device-gate suites only prove the clean DB.

## 5. Cross-cutting: iOS, security, DevOps, docs

- **iOS = zero.** `docs/RoadMap/IOS_APP_STORE_READINESS.md` B1–B8 all open: no App Store record, no `DEVELOPMENT_TEAM`, no `Podfile`/`Podfile.lock`, no `GoogleService-Info.plist`, bundle-id split (`com.solevision.app` vs `com.cufmai.solvision.checkout` vs `CUFMAI` display name), no `ITSAppUsesNonExemptEncryption`, no privacy labels, no macOS CI / IPA job. Update overlay on iOS is a static stub.
- **Security debt:** anon key confirmed exposed in git history — rotation still pending; no staging env (second Supabase project); backup/restore never confirmed in Dashboard; RLS audit is a doc of queries, not CI; Edge Functions hardened but no rate limiting; device gate `enforcement_enabled=false`; trusted-devices needs two dashboard toggles (Confirm-email + `{{ .Token }}` templates).
- **Quality/docs stale:** roadmap coverage numbers stale (see note); `docs/PROJECT_HANDOFF.md` is v1.1.0 / July 2, 2026; `supabase/schema.sql` still outdated; `SupabaseService` legacy catch-all still in use alongside focused services; `url_launcher` / deep-link `applinks:YOUR-DOMAIN.com` placeholder not wired; in-app update checker is Android-APK-only (`version.json` has no iOS field).

## Suggested priority

- **P0:** apply the 2 pending migrations in order, decide pg_cron (install or formally defer expiry sweeps), rotate anon key, confirm backup, add `notifications` to realtime publication or document focus-refetch as permanent.
- **P1:** populate `product_models` (1 real shoe end-to-end) or hide all 3D entry points; finish CSV export or remove the button; wire customizations into cart or hide the section; stand up staging; add iOS CI compile check (cheapest B-blocker).
- **P2:** kill `SupabaseService` duplication, add pagination + N+1 audit, image cache policy, unify bundle id + app name, refresh roadmap/handoff numbers so the next audit doesn't re-discover fixed work.
