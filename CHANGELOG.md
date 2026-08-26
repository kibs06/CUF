# SoleVision — Changelog

## Session: Get Your Foot Size 2.0 — Clean-Rewrite AR Auto Scan (Beta)

### New v2 feature (coexists with v1; Settings → "Get Your Foot Size 2.0")
- **`lib/screens/customer/foot_size_v2/foot_scan_setup_screen_v2.dart`** (new) — Modern setup screen: hero header with time estimate, staggered "what to expect" rows, chip groups for shoe category / foot condition, CTA doubles as camera-permission pre-flight (opens app settings when permanently denied).
- **`lib/screens/customer/foot_size_v2/foot_scan_session_screen_v2.dart`** (new) — Full-bleed native AR view (`PlatformViewLink`, same wiring as v1), animated 4-segment stepper (L·T → L·S → R·T → R·S), breathing corner-bracket guide frame, glass-card coach hints via `AnimatedSwitcher`, live cm readout, sweep-ring capture button, haptics on step/foot completion, start-failure states as first-class glass sheets. One continuous AR session across all four captures.
- **`lib/screens/customer/foot_size_v2/foot_scan_results_screen_v2.dart`** (new) — Premium results: staggered section entrances over one entrance controller, count-up cm/mm values, hero EU size with US/UK pills, L/R foot cards with SIZING badge, width-fit gauge, animated confidence ring gauge (percentage sweeps to `confidenceScore`, colored by level) with a per-factor **"Why this score"** breakdown (sample volume, reading consistency, measured-vs-estimated width, both feet, sock compensation), **half-size adjustment stepper** ("Does this size feel right?" — ±0.5 EU clamped to ±2 sizes of the recommendation, live US/UK re-derivation via `euToUs`/`euToUk`, haptics, Reset chip, "Adjusted by you" badge; adjustment recorded in the saved reason), sticky save bar → `foot_measurements` (`algorithmVersion: 'v2.0'`, `measurementSource: 'ar_auto_scan'`) + profile snapshot using the adjusted sizes.
- **Confidence breakdown (`ScanResultsPayloadV2.confidenceFactors`)** — Controller builds typed `ConfidenceFactorV2` rows (positive/negative + title + detail) from real pipeline signals: final sample count vs ideal/min thresholds, IQR consistency of the sizing foot, widthMeasured fraction, both-feet coverage, sock compensation. Rendered under the ring so low scores always come with reasons.
- **`lib/providers/v2/scan_session_controller.dart`** (new) — Typed rewrite of the auto-scan sampling loop (`ScanPhase`/`CoachHint` instead of stringly guidance). Ports v1's skeleton (overlap guard, stall coaching, temporal gate, area-tracking poll) with the documented bug fixes below. **Precision gates (v2-only):** 5 s capture window (vs 4 s v1), `kV2MinSampleConfidence = 0.50` floor on recorded samples, anatomically implausible measured widths (ratio outside 0.20–0.60 of length) rejected as bad hitTest pairs. Exposed `passSampleCount` for live scan animation.
- **`lib/providers/v2/scan_phase.dart`**, **`lib/widgets/foot_size_v2/glass_card.dart`**, **`scan_stepper.dart`** (new) — Shared types + floating-glass UI kit.
- **`lib/widgets/foot_size_v2/scan_instruction_overlay.dart`** (new) — Looping "how to scan" GIF-style demo per capture step: pure CustomPaint animation (phone glyph descends/orbits, footprint pulses, guide box dashed). Auto-plays once per step, dismissible, replayable via "How to scan" chip.
- **`lib/widgets/foot_size_v2/foot_trace_overlay.dart`** (new) — Live scanning animation: stylized foot outline draws itself progressively as clean samples accumulate, sweeping scan-line with intersection sparkles, soft accent fill deepening with progress. Driven by `passSampleCount / idealSampleCount` during capture.

### Bug fixes from docs/AI/AR_FOOT_SCAN_ERROR_ANALYSIS.md
- **E15 — side-step guide box off-screen (found on device)** — `kSideCaptureGuideRect` (x 0.15–0.85) is wider than the visible crop band on tall phones (~x 0.19–0.81 with a 4:3 sensor), so the side-step box drew off-screen (stray clipped "VIEW" label at the screen edge) and its corner area probes could never hit the plane. v2 now clamps the guide rect into the computed visible band (`effectiveGuideRect`) for probing and drawing; the test fake simulates crop geometry. v1 shares the constants and remains affected (frozen).
- **E5** (`ArFootSizingView.kt`) — ARCore availability retries now back off 500 ms on the session executor instead of re-dispatching immediately (shared by v1 + v2).
- **E10** (`ArFootSizingView.kt`) — Removed the fabricated 3×3 m fallback plane; plane-detection failures now log honestly and report `planeDetected = false`.
- **E7** (`ar_foot_measurement_pipeline.dart`) — `MeasurementSample.widthMeasured` flag; `combineGuidedSamples` computes the width median from measured-only samples (proportional estimates excluded, safe fallback when too few).
- **E8** (v2 controller/results) — Payload and results screen show compensated values only; sizing consumes exactly what's displayed. No fake `lightingQuality`/`paperConfidence`.
- **E13** (v2 controller) — Per-pass sample buffer merged into per-foot cumulative sets only after a pass succeeds; foot results frozen immediately upon combine. Failed/retried/cancelled passes contribute nothing.

### Tests & docs
- **`test/providers/v2/scan_session_controller_test.dart`** (new, 10 tests) — Happy path L·T→L·S→R·T→R·S, start-failure reasons as typed phases, stall coaching, E13 retry/cancel isolation, E7 width-exclusion, E8 sock-compensation identity, confidence-factors presence (all positive on an ideal both-feet scan).
- **`test/widgets/foot_size_v2/foot_scan_results_screen_v2_test.dart`** (new) — Results screen renders hero size + confidence % + factor rows; ± stepper re-derives US/UK live with reset and clamp behavior; no adjustment card when no EU recommendation exists. Plus GlassCard tone tests, ScanStepper segment tests. Pipeline E7 exclusion tests added to `test/utils/ar_foot_measurement_pipeline_test.dart`. Full suite: 523 passing, `flutter analyze` clean.
- **`docs/AI/AR_FOOT_SCAN_ERROR_ANALYSIS.md`** — Fix statuses updated (2026-08-25); open items: E6/E9/E11/E14 + on-device E1 re-verification.

## Session 3: Merged Auth Front Door + Seller Application Upgrades + Dev Mode

### Auth — Merged Front Door (AccountEntryScreen)
- **`lib/screens/auth/account_entry_screen.dart`** (new) — Replaced `LoginScreen` and `RoleChoiceScreen` with one full-bleed video hero front door that switches in place between **create** (customer / seller role picker) and **signin** (email/password login) modes via a shared `AnimationController`. Video never restarts on mode switch; reduced-motion honored.
- **`lib/screens/auth/login_screen.dart` / `role_choice_screen.dart`** — Deleted (merged into `account_entry_screen.dart`).
- **`lib/widgets/auth/full_bleed_video_background.dart`** — Renamed/upgraded to `VideoHeroBackground` with tuned global dim + overlapping top/bottom scrims so every chrome element clears 4.5:1 contrast on the brightest video frame.
- **`lib/widgets/auth/dark_auth_text_field.dart`** (new) — Cream-on-dark text field variant for the signin mode over video.
- **`lib/screens/auth_gate.dart`** — Routes to `AccountEntryScreen`; sign-in no longer self-navigates (AuthGate reacts to the auth stream).
- **`lib/screens/auth/onboarding_screen.dart`, `signup_scaffold.dart`, `step_progress_indicator.dart`** — Updated for the merged entry; step indicator simplified.

### Dev Mode (testing shortcut — REMOVE BEFORE RELEASE)
- **`lib/utils/dev_mode.dart`** (new) — `DevMode` singleton toggled by the swipe gesture **↑↑↓↓→→←←** on the account entry screen; swipe UI in `dev_mode_swipe_detector.dart`, badge in `dev_mode_badge.dart`.
- Dev mode lets you mash **Continue** through the whole seller flow (skips validation/terms/duplicate-email), then routes into a real `PendingApprovalScreen` preview with a `DEV PREVIEW` banner.
- Full removal checklist tracked in `docs/AI/DEV_MODE_ARCHITECTURE.md`.

### Seller Application Flow — Step Upgrades
- **Step 1** — Password strength meter; terms tile placement.
- **Step 2 (Identity)** — Seller now picks their **government ID type** first (valid PH IDs: passport, driver's license, UMID, SSS, PhilHealth, PRC, postal ID, voter's ID, TIN, NBI clearance) — the ID photo upload appears only after a type is chosen. Migration `20260816000000_add_seller_id_type.sql` adds `id_type` to `profiles`.
- **Step 4 (Storefront)** — Removed payout method/details (no longer collected at application). Added required **store front photo** (uploads to the public `store-assets` bucket, stored as `profiles.store_front_url`, becomes the store banner post-approval via `StoreService.createStore`) and **5 required product photos** (`product_photo_urls TEXT[]`, private verification bucket, compact horizontal carousel of square slots on the form, all shown in admin review). Migration `20260816120000_add_seller_store_photos.sql`.
- Draft autosave/resume (30 min) extended to cover the new ID type + store/product photos; in-memory storage for tests (`flutter_secure_storage_platform_interface` dev dep).

### Pending Approval Screen — Redesign
- **`lib/screens/auth/pending_approval_screen.dart`** — Rebuilt: dev banner (black + hazard stripes), header card (badge + UNDER ADMIN REVIEW + serif heading), intro paragraph, state-driven **What happens next** timeline (received ✓ green → verification in progress amber → certified member muted, driven by `profiles.seller_status`), divider-separated **What we received** rows, secondary Tier 2 card (dashed border), primary **Back to home** button (pushes customer home so a pending applicant can browse; pops in dev preview) and removed Log out.

### Seller Approval Notification
- **`supabase/migrations/20260816150000_add_seller_approval_notification.sql`** (new) — Adds `'approval'` to the `notification_category` enum + a `SECURITY DEFINER` trigger on `profiles` that inserts an in-app notification the moment `seller_status` → `approved`. Picked up live by the existing realtime subscription — zero client code needed.
- **`lib/models/notification_category.dart`, `app_notification.dart`, `notifications_screen.dart`** — Added the `approval` category (badge icon, brand-brown accent).

### Docs
- New: `docs/AI/SIGN_IN_ARCHITECTURE.md`, `docs/AI/DEV_MODE_ARCHITECTURE.md`; updated `SIGNUP_ARCHITECTURE.md`, `SELLER_APPLICATION_UI_ARCHITECTURE.md`, obsidian auth MOC, Code Map.

## Session 2: Seller Dashboard Real Data + Users Redesign + Login Freeze Fix

### Reports Screen — Replace Mock Data with Real Supabase Data
- **`lib/models/seller_report_data.dart`** — New data class: `SellerReportData` with `weeklyTotal`, `dailyRevenue` (7 doubles, Mon=0 Sun=6), `topProducts` list, `weekStart`/`weekEnd`.
- **`lib/services/sales_service.dart`** — Added `getWeeklyReport(storeId)` that fetches online orders (filtered by `status != 'cancelled'` AND `payment_status = 'paid'`) + POS transactions, aggregates daily revenue by weekday, aggregates top products from `order_items` + `sales_transaction_items`, fetches product names. All queries use the 3-step products→order_items→orders pattern.
- **`lib/screens/seller/reports_screen.dart`** — Full rewrite from `StatelessWidget` to `StatefulWidget` with `FutureBuilder`. Added shimmer loading skeleton, `ErrorRetryWidget` on failure, pull-to-refresh, real top products list with rank badges and revenue formatting, CSV export stub with snackbar, empty state for zero-sales weeks.
- **Period selector toggle** — Added `This Week` / `This Month` segmented chip toggle to the reports screen. `getWeeklyReport` accepts a `monthly` flag that aggregates revenue by day-of-month (28-31 bars) instead of weekday (7 bars). Bar labels dynamically switch to day numbers for monthly view. Date label shows full month name + year (e.g., "June 2026") for monthly. `SellerWeeklyBar` accepts an optional `todayIndex` parameter.
- **Revenue comparison card** — Added week-over-week / month-over-month percentage change indicator below the total revenue. `SellerReportData` now includes `previousPeriodTotal` and a `percentChange` getter. The service fetches the previous period's online + POS revenue in parallel with the current period. UI shows an up/down arrow with colored percentage (green for positive, red for negative) and context label ("vs last week" / "vs last month"). Hidden when previous period has no data.

### Seller Dashboard — Monthly Revenue Trend Chart
- **`lib/services/sales_service.dart`** — Added `getMonthlyRevenueTrend(storeId)` that fetches online orders + POS transactions for the past 6 months, aggregates by month index. Added static `monthlyLabels()` that generates abbreviated month labels.
- **`lib/screens/seller/seller_dashboard_screen.dart`** — Added `monthlySalesChart` to `_DashboardData`, fetched via `Future.wait`, rendered as a `SellerWeeklyBar` chart below the weekly bar chart.

### Seller Dashboard — Optimize getRecentOrders Query
- **`lib/services/order_service.dart`** — Added `limit` parameter to `_getOrderIdsForStore` helper. The database now applies `.limit()` after `.order()` so only N order IDs are fetched instead of all IDs + Dart slicing. `getRecentOrders` passes `limit` through to the helper.

### Seller Dashboard — Pull-to-Refresh Fix
- **`lib/screens/seller/seller_dashboard_screen.dart`** — Added `_cachedData` field to preserve last-loaded data. FutureBuilder now only shows the shimmer skeleton on initial load; on pull-to-refresh, existing data stays visible while the spinner animates. Error during refresh silently falls back to cached data instead of replacing the UI.

### Seller Dashboard — Replace Mock Data with Real Supabase Data
- **`lib/services/sales_service.dart`** — Extended with: `getOnlineTodayRevenue`, `getTodayRevenue` (online + POS), `getOnlineWeeklySales`, `getWeeklyRevenue` (7-day weekday aggregation combining online + POS), `getMonthlyRevenue`, `getTotalOrderCount`, `getPendingOrderCount`. Product/order lookups use a products→order_items chain to avoid PostgREST join syntax issues.
- **`lib/services/order_service.dart`** — Extended with: `getRecentOrders` (customer name + product name via separate queries), `getOrderCountByStatus`, `fetchStoreOrders` rewritten to filter server-side instead of fetching all orders. Added `SupabaseClient` constructor parameter.
- **`lib/screens/seller/seller_dashboard_screen.dart`** — Full rewrite: `FutureBuilder` pattern with `_DashboardData` model, shimmer loading skeleton, `ErrorRetryWidget` on failure, pull-to-refresh, order status summary section (placed/preparing/ready/received), store rating in today's sales subtitle, real weekly bar chart data, correct status transitions (placed→preparing→ready→received), `_emptyDashboard()` fallback for unmounted widgets, `mounted` check after async operations, removed dead `weeklyRevenue`/`totalOrders` fields.

### Users Page Redesign
- **`lib/hooks/useUsers.js`** — Rewritten to remove `suspended` column, return `{ all, customers, sellers, admins }` grouped by role.
- **`lib/pages/Users.jsx`** — Full rewrite with role-separated tab layout (All/Customers/Sellers/Admins), stats chips, real-time search, side-by-side sections.
- **`lib/components/users/UserRow.jsx`** — Individual user row with deterministic avatar colors, hover actions.
- **`lib/components/users/UserSection.jsx`** — Role-colored section container with icon and count.
- **`lib/components/users/UserDetailModal.jsx`** — Role-colored header, info grid, role change buttons.

### Admin Products Page Cleanup
- **`admin-portal/src/pages/Products.jsx`** — Removed duplicate heading/subtitle/Add Product button, cleaned up dead code.
- **`admin-portal/src/components/products/StoreGroup.jsx`** — Enlarged banner from h-40 to h-64, added store rating chip, larger logo, improved gradient.
- **`admin-portal/src/hooks/useProducts.js`** — Added `rating` to store query, removed dead `allStores`.

### Login Freeze Fix
- **`lib/providers/auth_provider.dart`** — `logout()` clears all state + biometric credentials before signOut. `login()` clears stale `_currentUser`/`_profile` at start, uses try/catch/finally to guarantee `_isLoading` resets. `signUp()` also upgraded to finally pattern.
- **`lib/services/auth_service.dart`** — Removed pre-signOut in `signIn()` to avoid auth stream race condition.
- **`lib/screens/auth_gate.dart`** — Added `_resetProfileCache()` to clear stale profile when auth stream emits null user.
- **`lib/screens/auth/login_screen.dart`** — `_submit()` cleaned up with early returns, `mounted` guard, proper `Future<void>` return type.
