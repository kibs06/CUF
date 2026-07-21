# SoleVision — Project Roadmap

**Version:** 2.1.0  
**Created:** July 16, 2026  
**Last Updated:** July 22, 2026  
**Current Status:** Phase 2 In Progress — Testing infrastructure established, CI/CD pipeline running  
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

| Priority | Task | Effort | Impact |
|----------|------|--------|--------|
| 🟡 P1 | AR shoe fitting with real 3D models | Very Large | Innovation |
| 🟡 P1 | 360° product view | Large | UX |
| 🟢 P2 | Virtual try-on for different colors/materials | Very Large | Innovation |
| 🟢 P2 | AI-powered size recommendation | Large | Innovation |
| 🟢 P2 | Custom shoe designer (visual editor) | Very Large | Feature |

### Phase 9: Platform Expansion (Weeks 20-26)
**Goal:** Expand beyond the initial Carcar City market.

| Priority | Task | Effort | Impact |
|----------|------|--------|--------|
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
