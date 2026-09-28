# SoleVision — Project Roadmap

**Version:** 2.1.3  
**Created:** July 16, 2026  
**Last Updated:** September 28, 2026  
**Current Status:** Phase 2 In Progress — Testing infrastructure established, CI/CD pipeline running. **🚩 iOS availability flagged** — the app ships Android-only today; the work to make it downloadable on iOS is inventoried in `docs/RoadMap/IOS_APP_STORE_READINESS.md`  
**Target Market:** Carcar City, Cebu, Philippines  

---

## Vision Statement

SoleVision aims to be the **go-to digital marketplace for artisan footwear** in the Philippines, connecting skilled craftspeople with customers who value handcrafted quality. The platform bridges the gap between traditional shoemaking heritage and modern e-commerce.

---

## Current State (July 2026)

### ✅ Completed

| Category | Features |
|----------|----------|
| **Customer** | Registration, biometric login, product browsing, store discovery, shopping cart, checkout, order tracking, custom orders, address management, messaging, push notifications, reviews & ratings |
| **Seller** | Store management, product CRUD, inventory management, POS, order management, sales reports, dashboard analytics (line charts, revenue breakdown, monthly income tracking), messaging, push notifications, notification swipe gestures |
| **Admin** | User management, seller approval, product monitoring, analytics dashboard (React web portal) |
| **Infrastructure** | Supabase backend, RLS security, Firebase FCM, real-time messaging, Edge Functions (send-message-push, send-notification-push), fl_chart for revenue visualization |
| **Production Hardening** | Environment variables for credentials, debug prints removed, deprecation warnings fixed, admin portal error boundary, Sentry error monitoring, Edge Function security hardened, fail-fast startup checks |
| **Testing & Quality** | Unit testing framework (mocktail), 38 passing tests (services, providers, utils), GitHub Actions CI/CD pipeline, coverage baseline established |

### 🟡 In Progress / Partially Complete

| Item | Status |
|------|--------|
| AR shoe fitting | Placeholder only — no real AR |
| CSV export for reports | Stub — shows SnackBar |
| Card payment in POS | Disabled — shows "coming soon" |
| Unit tests | 38 tests passing — services, providers, utils tested; widget tests need Supabase test instance |
| Notification preferences | No opt-out per category yet |
| Hard-delete soft-deleted notifications | Soft-delete works, no cron for permanent cleanup |
| Security audit (RLS, Edge Functions) | Queries documented, manual verification pending |
| Database backup verification | Requires Supabase Dashboard confirmation |
| Supabase anon key rotation | Key exposed in git history, rotation recommended |

---

## Roadmap Phases

### Phase 1: Production Hardening (Weeks 1-3) ✅ COMPLETE

**Goal:** Make the existing MVP production-ready and secure.

| Priority | Task | Effort | Impact | Status |
|----------|------|--------|--------|--------|
| 🔴 P0 | Move Supabase credentials to environment variables | Small | Security | ✅ Done — `String.fromEnvironment` in `app_constants.dart` |
| 🔴 P0 | Run all pending SQL migrations against live DB | Small | Stability | ⏳ Queries documented in `docs/HARDENING_SQL_QUERIES.md` — manual run required |
| 🔴 P0 | Run verification SQL queries for non-numeric sizes | Small | Stability | ⏳ Queries documented — manual run required |
| 🔴 P0 | Fix duplicate `product_variants` rows | Small | Data integrity | ⏳ Queries documented — manual run required |
| 🔴 P0 | Fix orphaned inventory rows | Small | Data integrity | ⏳ Queries documented — manual run required |
| 🟡 P1 | Update `supabase/schema.sql` to match live DB | Small | Developer experience | ✅ Done |
| 🟡 P1 | Remove debug prints from production code | Small | Code quality | ✅ Done — ~168 `debugPrint` calls removed |
| 🟡 P1 | Fix `isFollowing()` stub | Small | Functionality | ✅ Already implemented via `FollowProvider` |
| 🟡 P1 | Add `.env.example` for admin portal | Small | Onboarding | ✅ Done |
| 🟡 P1 | Add error boundary for admin portal | Medium | Stability | ✅ Done — `ErrorBoundary.jsx` wrapping app |
| 🟢 P2 | Fix `RadioListTile` deprecation warnings | Small | Code quality | ✅ Done — migrated to `ListTile` + `Radio` pattern |
| 🟢 P2 | Replace `.withOpacity()` with `.withValues()` | Small | Code quality | ✅ Done — ~165 instances replaced |

### Phase 1.5: Security & Safety Audit (Week 4) 🟡 IN PROGRESS

**Goal:** Address security gaps identified during Phase 1 review.

| Priority | Task | Effort | Impact | Status |
|----------|------|--------|--------|--------|
| 🔴 P0 | Verify database backup/restore point exists | Small | Safety | ⏳ Requires Supabase Dashboard confirmation |
| 🔴 P0 | Audit RLS policies end-to-end | Medium | Security | ✅ Queries documented in `docs/PHASE1_5_SECURITY_AUDIT.md` |
| 🔴 P0 | Review Edge Function security | Medium | Security | ✅ JWT auth validation, payload limits, UUID validation added |
| 🟡 P1 | Set up error/crash monitoring (Sentry) | Medium | Observability | ✅ Done — `sentry_flutter` integrated in Flutter app |
| 🟡 P1 | Stand up minimal staging environment | Medium | DevOps | ⏳ Requires second Supabase project |
| 🟢 P2 | Confirm git history doesn't contain leaked credentials | Small | Security | 🔴 Credentials confirmed exposed — key rotation recommended |
| 🟢 P2 | Spot-check Phase 1 fixes re-verified | Small | Stability | ⏳ Requires running SQL verification queries |

**Fix applied:** Added fail-fast startup check in `lib/main.dart` that throws immediately if `SUPABASE_URL` or `SUPABASE_ANON_KEY` are empty, preventing the cryptic "No host specified in URI" auth crash.

### Phase 2: Testing & Quality (Weeks 3-6) 🟡 IN PROGRESS
**Goal:** Establish testing infrastructure and improve code quality.

| Priority | Task | Effort | Impact | Status |
|----------|------|--------|--------|--------|
| 🔴 P0 | Set up unit testing framework | Medium | Quality | ✅ Done — mocktail added, test structure created |
| 🔴 P0 | Write unit tests for critical services (CartService, OrderService) | Large | Reliability | ✅ Done — 8 tests for CartService + OrderService |
| 🟡 P1 | Write unit tests for providers (CartProvider) | Large | Reliability | ✅ Done — 14 pure logic tests |
| 🟡 P1 | Write unit tests for cart_helpers (resolveVariant, normalizeSize, etc.) | Medium | Reliability | ✅ Done — 16 tests for pure functions |
| 🟡 P1 | Write widget tests for key screens (CheckoutScreen, ProductDetailScreen) | Large | Reliability | ⏳ Pending — requires Supabase test instance |
| 🟡 P1 | Add integration tests for checkout flow | Large | Reliability | ⏳ Pending — requires staging environment |
| 🟡 P1 | Set up CI/CD pipeline (GitHub Actions) | Medium | DevOps | ✅ Done — analyze + test + coverage on every PR |
| 🟢 P2 | Add linting rules and enforce code style | Small | Code quality | ⏳ Pending |
| 🟢 P2 | Add code coverage reporting | Small | Visibility | ✅ Done — coverage baseline ~5% (focused files: cart_item_with_details 95%, cart_helpers 80%) |

### Phase 3: Payment Integration (Weeks 6-10)
**Goal:** Enable real payment processing for the Philippine market.

| Priority | Task | Effort | Impact |
|----------|------|--------|--------|
| 🔴 P0 | Integrate GCash API for online payments | Large | Revenue |
| 🟡 P1 | Integrate PayMongo for card payments | Large | Revenue |
| 🟡 P1 | Implement payment confirmation webhooks | Medium | Reliability |
| 🟡 P1 | Add payment failure handling and retry logic | Medium | UX |
| 🟡 P1 | Implement refund flow | Medium | Business |
| 🟢 P2 | Add payment receipts (PDF generation) | Medium | Business |
| 🟢 P2 | Implement installment payment options | Large | Business |

### Phase 4: Enhanced Messaging & Notifications (Weeks 8-12)
**Goal:** Improve communication features and notification reach.

| Priority | Task | Effort | Impact |
|----------|------|--------|--------|
| ✅ Done | Order status push notifications (customer + seller) | Medium | Engagement |
| ✅ Done | Notification swipe gestures (delete, mark read/unread) | Medium | UX |
| ✅ Done | Push notifications for all notification types (orders, stock, custom requests) | Medium | Engagement |
| 🟡 P1 | Email notifications for order updates | Medium | Engagement |
| 🟡 P1 | Notification preferences (opt-in/out per category) | Medium | UX |
| 🟢 P2 | Group messaging (multiple sellers per conversation) | Large | Feature |
| 🟢 P2 | Message search functionality | Medium | UX |
| 🟢 P2 | Voice messages | Large | Feature |
| 🟢 P2 | Message reactions/emoji | Medium | Feature |

### Phase 5: Search & Discovery (Weeks 10-14)
**Goal:** Help customers find products faster and discover new stores.

| Priority | Task | Effort | Impact |
|----------|------|--------|--------|
| 🔴 P0 | Implement full-text search with fuzzy matching | Large | Discovery |
| 🟡 P1 | Advanced filters (category, price range, store, size, color) | Medium | UX |
| 🟡 P1 | Search history and recent searches | Small | UX |
| 🟡 P1 | "Similar products" recommendations | Medium | Engagement |
| 🟡 P1 | Store discovery page with categories | Medium | Discovery |
| 🟢 P2 | Trending products section | Medium | Engagement |
| 🟢 P2 | Personalized product recommendations | Large | Engagement |
| 🟢 P2 | Saved searches with alerts | Medium | UX |

### Phase 6: Seller Analytics & Tools (Weeks 12-16)
**Goal:** Give sellers better insights and tools to grow their business.

| Priority | Task | Effort | Impact |
|----------|------|--------|--------|
| ✅ Done | Dashboard: Today's Sales with order count, top product, revenue breakdown | Medium | Analytics |
| ✅ Done | Dashboard: Monthly Income card with month-over-month comparison | Medium | Analytics |
| ✅ Done | Dashboard: Revenue line charts (weekly + monthly) with fl_chart | Medium | Analytics |
| ✅ Done | Dashboard: Online vs POS revenue breakdown bottom sheet | Small | Analytics |
| 🟡 P1 | Implement CSV/PDF export for reports | Medium | Business |
| 🟡 P1 | Customer insights (repeat buyers, demographics) | Medium | Analytics |
| 🟡 P1 | Product performance analytics (views, conversion) | Medium | Analytics |
| 🟡 P1 | Inventory forecasting based on sales trends | Large | Business |
| 🟢 P2 | Competitor price comparison | Large | Analytics |
| 🟢 P2 | Automated restock alerts | Medium | Business |
| 🟢 P2 | Bulk product import/export | Large | Efficiency |

### Phase 7: Customer Experience (Weeks 14-18)
**Goal:** Improve the overall shopping experience.

| Priority | Task | Effort | Impact |
|----------|------|--------|--------|
| ✅ Done | Customer reviews and ratings | Large | Trust |
| 🟡 P1 | Wishlist / favorites feature | Medium | Engagement |
| 🟡 P1 | Product Q&A (customers ask questions on product pages) | Medium | Engagement |
| 🟡 P1 | Size guide with measurements | Medium | UX |
| 🟢 P2 | Store following feed with product updates | Medium | Engagement |
| 🟢 P2 | Social sharing (share products to social media) | Medium | Growth |
| 🟢 P2 | Referral program | Large | Growth |

### Phase 8: AR & Innovation (Weeks 18-24)
**Goal:** Differentiate with augmented reality and innovative features.

> **Deep dive:** the real virtual fitting (fit verdict + 3D try-on on the shipped ARCore stack) is planned in detail in `docs/RoadMap/VIRTUAL_FITTING_ARCHITECTURE.md` (design) and `docs/RoadMap/VIRTUAL_FITTING_ROADMAP.md` (phases V0–V5, ~10–13 weeks, Android first). The rows below are the umbrella view only.
>
> **V0 state (2026-09-27):** the renderer spike is **code-complete** — it builds, boots on Android and renders a placeholder GLB behind a dev flag; three defects found before any device run are fixed (the screen deadlocked behind its own session timeout, the plugin dropped the model handed over before its view existed, the dev flag did not guard the camera prompt or the staged model), and it carries its own tests. V0's measurements are recorded in `docs/RoadMap/AR_TRY_ON_SPIKE_FINDINGS.md`. Two things gate the phase and neither is code — a **physical ARCore phone** (fps/load/memory; an emulator provably cannot load a model) and a **partner's sample shoe** (the content pipeline). One budget is already breached: the renderer costs **+27.7 MB** of APK against a ≤8 MB target, so the renderer route itself is an open decision.
>
> **V1 state (2026-09-27): the fit verdict is code-complete** — *the part a customer feels with no 3D at all*. The pure engine (`lib/utils/fit_engine.dart`, 45 tests), the migration that gives products last dimensions (**applied and verified live** — `products` at 26 columns with all five CHECKs; 1 of 15 products carries a spec, and that one is clearly-flagged **demo** data), the seller form that collects them (30 + 11 tests), the **product-detail card** that shows the verdict (21 + 15 tests), and **shadow mode** (13 tests), which records what the card *would* say to the diagnostic log without showing the customer anything. The visible card ships behind `AppConstants.virtualFitEnabled`, **off** on purpose: the bands are workshop defaults, the catalog carries one demo spec and no measured one, and nothing has been compared with an artisan's opinion. What is left is the sample and the people — fill specs into real products, run shadow mode over their pages, review the `[FIT]` lines at the V0.8 workshop, then flip the switch.
>
> **V2 state (2026-09-28): everything in the model pipeline that needs nobody is code — including the upload, which is the part that was missing.** The authoring validator (V2.7, 11 checks + CLI), the table/bucket migration (V2.1, **applied 2026-09-28 and verified by object**: `product_models` 17 columns / 4 indexes / 4 policies / **0 rows**, `shoe-models` public 8 MiB `model/gltf-binary`), the read service (V2.5, resolve → download → sha256 → cache → LRU evict) and now the **write path** (V2.2/V2.3): the seller form's "3D Model (Optional)" section takes the handover link and declared length, fetches the file, runs the contract, shows the failing rows as sentences, and publishes on Save. It ships behind `AppConstants.shoeModelUploadEnabled`, which now defaults **on** (2026-09-28): the apply it was waiting for had already happened, and only the docs were still saying otherwise. The read side then gained its **first consumer** the same day (V2.6): the product page warms the model cache on mount through `lib/services/try_on_prefetch.dart`, a class whose whole job is that no prefetch failure — a missing table, a dead network, a hash mismatch, an unwritable cache — can ever reach the page (11 service tests + 7 tests that mount the real product screen). It too now defaults on (`tryOnPrefetchEnabled`, 2026-09-28): with the table empty the live effect is one empty read per product page view, and the renderer that would use a warm cache is still V3, so the metered-connection guard is the next hardening step rather than a precondition. Three of the roadmap row's items are deferred with recorded reasons rather than skipped: the file picker (no dependency can select a `.glb`, so a link is the practical handover), the per-colour override (`variant_id` is colour *and* size, so one colour's model would render on one size only), and the material-part → colour map (the product's colours carry no paint value and the repo's only name→colour map is a UI swatch with a synthetic fallback). And **V2.4 arrived the same day (2026-09-28)**, which is the one part of V2 that is about security rather than plumbing: `supabase/functions/validate-shoe-model/` re-reads a model's row, checks ownership explicitly, downloads the object, hashes it against the row's own `sha256` and runs the authoring contract over the bytes — the rule set its TypeScript mirror carries, proven identical to the Dart reference over 22 fixtures by `node tool/check_glb_validator_parity.mjs`. Because a checker a client can skip is not a boundary, the transition into `status='active'` is gated by a trigger (`20260928120000_gate_product_model_active.sql`, **written and deliberately NOT applied** — publishing works in both states, since the app now inserts every model as a draft and lets the server publish it) that refuses every role but the service role. What V2 still needs is a real GLB and the partner capture sessions. **One real GLB has now been through it (2026-09-28)** — a marketplace/AI-generated shoe that failed 7 of the 11 checks for mechanical reasons rather than modelling ones (rotation left on the node, length on X, 4.30× life size, 4096² textures, one `Material.001`), which is what V2.7's new normaliser fixes: `tool/prepare_shoe_model.dart` took it from **31.48 MiB to 1.66 MiB and 7/11 to 11/11 PASS**, so the pipeline can ingest a bought asset as well as a captured one. It does not change what V2.8 is for: the normaliser makes a lookalike **load**, and only a captured pair makes it **the product**. `product_models` still holds 0 rows.
>
> **V3 state (2026-09-28): V3 has started with the half no device can invalidate.** `lib/providers/try_on/` now holds the phase machine (`try_on_phase.dart`), the pure capability gate (`try_on_mode.dart`) and the session controller (`try_on_session_controller.dart`), plus the Dart half of the platform channel (`lib/services/ar_try_on_channel.dart`), and the product page hands the gate its availability answer — **59 new tests** (11 gate, 23 channel contract, 19 controller, 6 wiring), analyzer clean, **1,979 pass / 6 skipped** in both switch configurations. It ships behind `AppConstants.tryOnV3Enabled`, **off**, and this is the one switch that waits on its own renderer rather than on a table or another team: V0.7 has not chosen between SceneView + Compose (+27.7 MB against a ≤8 MB budget) and driving Filament directly, V0.6's fps/load numbers need a physical ARCore phone (finding F14: at feature level 1 no model loads on an emulator at all), and `product_models` holds **0 rows**, so there is nothing to render. Flipping it today would show every customer the simulated screen — which is why V3's remaining tasks (V3.2–V3.5, V3.7) are sequenced behind that decision rather than beside it.
>
> **V3.2 and V3.5 then landed the same day, and the order matters.** V3.2 wrote the native renderer on the measured Filament-direct route (`com.solevision.app.tryon`, findings §5.6) — it compiles and has **never run**, and the camera feed and floor plane are unimplemented for a measured reason (finding F20: the Filament artifacts ship zero assets, so the two `.filamat` files those draws need are ours to supply). V3.5 then made the path *reachable*: the try-on screen swaps the real platform view into the camera-feed slot and falls back on every non-real state, and a default-off QA seam (`tryOnPlaceholderModelEnabled`) points the production read service at the repo's bundled block-out, so resolve → digest verify → cache → handover can be exercised as real code with no database row. **11 new tests; analyzer clean; 1,990 pass / 6 skipped.** What no amount of code removes: `product_models` is empty, no fps number exists, and the QA seam must never be on in a customer build.

| Priority | Task | Effort | Impact |
|----------|------|--------|--------|
| 🟡 P1 | AR shoe fitting with real 3D models → planned as `VIRTUAL_FITTING_ROADMAP.md` V0–V5; **V0 code-complete** (spike built + tested, size delta measured and failing; device run + partner sample outstanding) | Very Large | Innovation |
| 🟡 P1 | 360° product view | Large | UX |
| 🟢 P2 | Virtual try-on for different colors/materials | Very Large | Innovation |
| 🟢 P2 | AI-powered size recommendation → **built as the fit engine** (`VIRTUAL_FITTING_ROADMAP.md` V1: saved scan mm × the product's last spec → band + toe/width allowance + confidence; card on product detail behind a flag that ships off) | Large | Innovation |
| 🟢 P2 | Custom shoe designer (visual editor) | Very Large | Feature |

### Phase 9: Platform Expansion (Weeks 20-26)
**Goal:** Expand beyond the initial Carcar City market.

> **🚩 Flag (2026-09-28): iOS availability is committed but not started.** Every release so far is an Android APK; there is no TestFlight build, no App Store listing, and four build prerequisites are unfilled (no `DEVELOPMENT_TEAM`, no `ios/Podfile`, no `ios/Runner/GoogleService-Info.plist`, no macOS CI). The full blocker list with file evidence, the work packages (I1–I7) and the decisions still owed live in **`docs/RoadMap/IOS_APP_STORE_READINESS.md`**. Clearing it is the prerequisite for every "reach a new market" row below.

| Priority | Task | Effort | Impact |
|----------|------|--------|--------|
| 🟡 P1 | **iOS availability — make the app downloadable from the App Store** → flagged 2026-09-28, inventoried as I1–I7 in `docs/RoadMap/IOS_APP_STORE_READINESS.md` (signing, bundle id, CocoaPods, Firebase iOS plist, listing, TestFlight automation) | Large | Market |
| 🟡 P1 | Multi-language support (Filipino, Cebuano) | Medium | Market |
| 🟡 P1 | Delivery partner integration (Lalamove, Grab Express) | Large | Market |
| 🟡 P1 | Shipping calculator with real-time rates | Medium | UX |
| 🟢 P2 | Multi-city expansion (Cebu City, Manila) | Large | Growth |
| 🟢 P2 | Seller subscription tiers (free, pro, enterprise) | Large | Revenue |
| 🟢 P2 | Offline mode with local caching | Large | UX |

---

## Technical Roadmap

### Infrastructure Improvements

| Timeline | Task | Priority | Status |
|----------|------|----------|--------|
| Weeks 1-2 | Set up CI/CD with GitHub Actions | High | ✅ Done — `.github/workflows/ci.yml` created |
| Weeks 2-3 | Implement automated testing pipeline | High | ✅ Done — 38 tests, flutter test --coverage in CI |
| Weeks 3-4 | Set up monitoring & error tracking (Sentry) | High | ✅ Done — `sentry_flutter` integrated |
| Weeks 4-6 | Database performance optimization (indexes, query analysis) | Medium | ⏳ Pending |
| Weeks 6-8 | Implement caching strategy (Redis/Memorystore) | Medium | ⏳ Pending |
| Weeks 8-10 | Set up staging environment | Medium | ⏳ Pending |
| Weeks 10-12 | Implement database backups and disaster recovery | High | ⏳ Pending |

### Code Quality Improvements

| Timeline | Task | Priority | Status |
|----------|------|----------|--------|
| Weeks 1-2 | Refactor `SupabaseService` — extract domain-specific services | Medium | ⏳ Pending |
| Weeks 2-4 | Implement proper error handling throughout | High | ✅ Partial — error boundary added, Sentry integrated |
| Weeks 3-5 | Add comprehensive logging (structured, level-based) | Medium | ⏳ Pending |
| Weeks 4-6 | Refactor state management (consider Riverpod migration) | Medium | ⏳ Pending |
| Weeks 6-8 | Implement proper dependency injection | Medium | ⏳ Pending |
| Weeks 8-10 | Add API versioning and backward compatibility | Low | ⏳ Pending |

### Performance Optimization

| Timeline | Task | Priority | Status |
|----------|------|----------|--------|
| Weeks 1-2 | Optimize `_NoisePainter` (pre-rendered texture) | Medium | ⏳ Pending |
| Weeks 2-3 | Implement image caching and lazy loading | Medium | ⏳ Pending |
| Weeks 3-4 | Optimize database queries (N+1 problem prevention) | High | ⏳ Pending |
| Weeks 4-6 | Implement pagination for all list views | High | ⏳ Pending |
| Weeks 6-8 | Add skeleton loading screens | Medium | ⏳ Pending |
| Weeks 8-10 | Implement virtual scrolling for large lists | Low | ⏳ Pending |

---

## Milestones

### Milestone 1: Production Ready (Week 3) ✅ ACHIEVED

- [x] All P0 security items completed (credentials in env vars, fail-fast checks)
- [x] SQL migration queries documented (ready for manual run)
- [x] Debug prints removed (~168 instances)
- [x] Schema documentation updated
- [x] Environment variables configured
- [x] Error boundary added to admin portal
- [x] RadioListTile deprecation warnings fixed
- [x] `.withOpacity()` replaced with `.withValues()`

### Milestone 1.5: Security Hardened (Week 4) 🟡 IN PROGRESS

- [x] RLS policies audited (queries documented)
- [x] Edge Functions hardened (JWT auth, input validation)
- [x] Sentry error monitoring integrated
- [x] Fail-fast startup checks for missing credentials
- [x] Git history checked for leaked credentials
- [ ] Database backup verified
- [ ] SQL verification queries run against live DB
- [ ] Supabase anon key rotated
- [ ] Staging environment stood up

### Milestone 2: Quality Assured (Week 6) 🟡 IN PROGRESS

- [x] Unit test framework set up (mocktail, test structure)
- [ ] Critical service tests written (>80% coverage) — 38 tests now, ~5% overall coverage
- [x] CI/CD pipeline running (GitHub Actions: analyze + test + coverage)
- [x] Error tracking implemented (Sentry)

### Milestone 3: Payments Live (Week 10)

- [ ] GCash integration complete
- [ ] Card payments via PayMongo
- [ ] Payment confirmation webhooks
- [ ] Refund flow implemented

### Milestone 4: Full Featured (Week 16)

- [ ] Full-text search implemented
- [ ] Advanced filters working
- [ ] Seller analytics complete
- [ ] CSV/PDF export functional

### Milestone 5: Market Expansion (Week 24)

- [ ] Multi-language support
- [ ] Delivery partner integration
- [ ] AR shoe fitting functional
- [ ] Ready for multi-city launch

---

## Session Changelog

### July 22, 2026 — Phase 2: Testing & CI/CD

**Testing Infrastructure:**
- Added `mocktail: ^1.0.4` to dev_dependencies in `pubspec.yaml`
- Created `test/services/cart_service_test.dart` — 3 tests for CartItemWithDetails model (unitPrice, lineTotal, toCartItemMap) and CartService singleton
- Created `test/services/order_service_test.dart` — 5 tests for OrderService delegation methods (placeOrder, updateOrderStatus, exception propagation) with mocked dependencies
- Created `test/providers/cart_provider_test.dart` — 14 pure logic tests for CartProvider state calculations (subtotal, deliveryFee, allSelected, toggleItem, toggleAll, clearCart, selectedSubtotal, groupedByStore)
- Created `test/utils/cart_helpers_test.dart` — 16 tests for resolveVariant, normalizeSize, resolveInventoryStock pure functions
- Updated `test/widget_test.dart` to placeholder (requires Supabase initialization for real widget tests)
- Total: **38 tests passing**

**Coverage Baseline:**
- `cart_item_with_details.dart`: 95% line coverage (21/22 lines)
- `cart_helpers.dart`: 80% line coverage (24/30 lines)
- Overall: ~5% (focused on tested files only)

**CI/CD Pipeline:**
- Created `.github/workflows/ci.yml` — runs on every PR and push to main
- Steps: Checkout → Setup Flutter → Cache pub dependencies → Install → Analyze → Test with coverage → Upload coverage artifact
- Coverage threshold warning at <10% (soft gate)

**Key Findings:**
- `cart_helpers.dart` is the strongest test target — pure functions with zero dependencies
- `CartProvider` cannot be unit tested directly (constructor accesses `Supabase.instance`)
- `CartService`/`OrderService` use singleton patterns with `Supabase.instance.client` — hard to unit test without refactoring
- Widget tests require a test Supabase instance or mocked providers

### July 21, 2026 — Phase 1.5 + Sentry + Auth Fix

**Sentry Integration:**
- Added `sentry_flutter: ^8.14.1` to `pubspec.yaml`
- Added `SENTRY_DSN` to `dart_defines.json.example` and `app_constants.dart`
- Integrated `SentryFlutter.init()` in `lib/main.dart` with environment tagging and error capture
- Fixed missing closing brace in `_firebaseMessagingBackgroundHandler`

**Supabase Auth Crash Fix:**
- Diagnosed root cause: `String.fromEnvironment` returns empty strings when `--dart-define-from-file` isn't used at build time
- Added fail-fast startup check in `lib/main.dart` that throws immediately if `SUPABASE_URL` or `SUPABASE_ANON_KEY` are empty

**Edge Function Security Hardening:**
- Added JWT auth validation via `supabaseAdmin.auth.getUser(token)` to both Edge Functions
- Added payload size limits (10KB) to both Edge Functions
- Added UUID format validation for `conversation_id`, `sender_id`, and `recipientUserId`
- Added non-empty validation for `title` and `body` in `send-notification-push`

**Security Audit Document:**
- Created `docs/PHASE1_5_SECURITY_AUDIT.md` with complete RLS policy audit, Edge Function review, and test queries

### July 20, 2026 — Phase 1: Production Hardening

**Credentials Migration:**
- Moved Supabase URL, anon key, and MapTiler key from hardcoded values to `String.fromEnvironment` in `lib/constants/app_constants.dart`
- Created `dart_defines.json.example` template
- Created `admin-portal/.env.example` with placeholder values

**Debug Print Cleanup:**
- Removed ~168 unconditional `debugPrint()` calls from `lib/` Dart files
- Removed bare `print()` calls from `push_notification_service.dart`

**Deprecation Fixes:**
- Replaced ~165 `.withOpacity()` calls with `.withValues(alpha:)` across all `lib/` Dart files
- Fixed `RadioListTile` deprecation in `checkout_screen.dart` and `customization_screen.dart` (migrated to `ListTile` + `Radio` pattern)

**Admin Portal Improvements:**
- Added `ErrorBoundary.jsx` component wrapping the app in `main.jsx`
- Updated `.env.example` with proper placeholder template

**SQL Verification Queries:**
- Created `docs/HARDENING_SQL_QUERIES.md` with queries for migration verification, non-numeric sizes, duplicate variants, and orphaned inventory

---

## Success Metrics

### Technical Metrics

| Metric | Current | Target (6 months) |
|--------|---------|-------------------|
| Test coverage | ~5% (38 tests) | >60% |
| App crash rate | Unknown | <1% |
| Average load time | ~3s | <1.5s |
| API response time | Unknown | <200ms (p95) |
| Uptime | Unknown | >99.5% |
| Error monitoring | ✅ Sentry integrated | Full alerting configured |

### Business Metrics

| Metric | Current | Target (6 months) |
|--------|---------|-------------------|
| Active sellers | ~3 seed stores | 20+ |
| Active customers | Testing phase | 500+ |
| Monthly orders | 0 | 100+ |
| Customer satisfaction | Unknown | >4.5/5 |
| Seller retention | Unknown | >80% |

### User Experience Metrics

| Metric | Current | Target (6 months) |
|--------|---------|-------------------|
| Checkout completion rate | Unknown | >70% |
| Search usage | Unknown | >40% of sessions |
| Messaging usage | New feature | >30% of users |
| Push notification opt-in | Unknown | >60% |

---

## Risk Assessment

### High Risk

| Risk | Mitigation |
|------|------------|
| Payment integration complexity | Start with GCash (simpler API), phase card payments |
| AR feature technical challenges | Consider 3rd party SDK (e.g., DeepAR, 8th Wall) |
| Scalability under load | Implement caching early, optimize queries |
| Credentials leaked in git history | Rotate Supabase anon key immediately |

### Medium Risk

| Risk | Mitigation |
|------|------------|
| User adoption in Carcar City | Partner with local artisan associations |
| Seller onboarding friction | Create seller onboarding guide, video tutorials |
| Data privacy compliance | Implement privacy policy, data retention rules |
| Edge Functions lack rate limiting | Add Supabase Edge Function rate limiting |

### Low Risk

| Risk | Mitigation |
|------|------------|
| Technology obsolescence | Flutter and Supabase are actively maintained |
| Competitor entry | Focus on niche (artisan footwear) and local market |

---

## Dependencies

### External Services

| Service | Purpose | Status |
|---------|---------|--------|
| Supabase | Backend (DB, Auth, Storage, Realtime) | ✅ Integrated |
| Firebase | Push notifications (FCM) | ✅ Integrated |
| Sentry | Error monitoring | ✅ Integrated |
| MapTiler | Maps and geocoding | ✅ Integrated |
| GCash | Mobile payments | 🔜 Phase 3 |
| PayMongo | Card payments | 🔜 Phase 3 |
| Lalamove/Grab | Delivery partners | 🔜 Phase 9 |

### Internal Dependencies

| Dependency | Blocks |
|------------|--------|
| Payment integration | Order completion, seller payouts |
| Testing infrastructure | CI/CD, reliable deployments |
| Search implementation | Product discovery, filtering |
| AR framework selection | Virtual try-on features |

---

## Review Cadence

| Review | Frequency | Focus |
|--------|-----------|-------|
| Sprint planning | Bi-weekly | Task prioritization, blockers |
| Technical review | Weekly | Code quality, architecture decisions |
| Product review | Monthly | Feature progress, user feedback |
| Roadmap review | Quarterly | Phase completion, priority adjustment |

---

## How to Use This Roadmap

1. **Priorities:** P0 = Must have, P1 = Should have, P2 = Nice to have
2. **Effort estimates:** Small (<1 week), Medium (1-2 weeks), Large (2-4 weeks), Very Large (4+ weeks)
3. **Phases are approximate** — they can overlap and adjust based on user feedback
4. **Milestones are checkpoints** — not hard deadlines
5. **This is a living document** — update as priorities change

---

*SoleVision Roadmap v2.1.0 — Updated July 22, 2026*  
*Review and update quarterly or after major milestones.*
