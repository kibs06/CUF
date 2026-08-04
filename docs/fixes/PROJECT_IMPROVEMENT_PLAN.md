# SoleVision — Project Improvement Plan

**Date:** August 4, 2026  
**Status:** In progress — 8 product improvements complete ✅  
**Current version:** v1.0.5 (6 builds)

---

## Table of Contents

1. [Project Snapshot](#1-project-snapshot)
2. [Progress Log](#2-progress-log)
3. [🔴 Critical — Fix First](#3--critical--fix-first)
4. [🟠 High Value](#4--high-value)
5. [🟡 Product Improvements](#5--product-improvements)
6. [🟢 Hygiene](#6--hygiene)
7. [Recommended Execution Order](#7-recommended-execution-order)

---

## 1. Project Snapshot

**SoleVision** — Flutter marketplace (customer/seller/admin) + React admin portal + Supabase backend, with POS, chat, reviews, AR foot sizing (ML Kit), push notifications, and GCash/PayMongo QR payments.

| Layer | Technology |
|-------|-----------|
| Mobile App | Flutter 3.12+ with Provider state management |
| Admin Portal | React 18 + Vite, TanStack Query, Tailwind CSS |
| Backend | Supabase (PostgreSQL, Auth, Storage, RLS, Edge Functions) |
| Payments | PayMongo QR Ph / GCash via Edge Functions |
| AR | Google ML Kit pose detection + selfie segmentation |
| CI/CD | GitHub Actions (analyze + test + auto-release via tags) |

**What's working well:**
- CI pipeline with auto-release via GitHub Actions
- Reusable widget library (`SoleCard`, `SolePrimaryButton`, `SoleBadge`, etc.)
- RLS on all tables with well-structured policies
- Release pipeline (tag → build → version.json + changelog → GitHub Release)
- Consistent design system (Playfair Display / DM Sans / JetBrains Mono, warm palette)

---

## 2. Progress Log

> Updates made during the Aug 4, 2026 implementation session.

| # | Item | Status | Notes |
|---|------|--------|-------|
| 1 | **Search filters/sort** (product improvement) | ✅ Done | Sort bottom sheet (Newest, Price ↑/↓, Name A–Z/Z–A) + `SortMode` state in `ProductProvider` |
| 2 | **Estimated delivery dates** (product improvement) | ✅ Done | `deliveryEstimateText` constant shown in checkout price breakdown |
| 3 | **Return/refund policy** (product improvement) | ✅ Done | New `TermsPrivacyScreen` replacing the "Coming soon" placeholder; flagged as draft pending legal review |
| 4 | **Secure checkout indicators** (product improvement) | ✅ Done | Lock icon + "encrypted and secure" text in checkout payment section |
| 5 | **Recently viewed products** (product improvement) | ✅ Done | `RecentlyViewedService` (SharedPreferences, max 20, dedupe) + horizontal section + empty-state hint |
| 6 | **Quantity limit display** (product improvement) | ✅ Done | "Max: X" label, disabled `+` stepper at limit, "Only X left" `SoleBadge` for low stock |
| 7 | **Size guide modal** (product improvement) | ✅ Done | New `SizeGuideModal` bottom sheet (EU/US/CM table) with "Size guide" trigger on product detail |
| 8 | **Social sharing** (product improvement) | ✅ Done | `share_plus ^13.3.0` + share button in product detail AppBar |
| 9 | **Store masonry grid fix** (bug, not in original plan) | ✅ Done | Replaced buggy `SliverMasonryGrid`/`MasonryGridView` (flutter_staggered_grid_view 0.7.0) with standard `SliverGrid`/`GridView.builder` on `store_profile_screen.dart` + `collection_screen.dart` |
| 10 | **Seller chat crash fix** (critical item 2.3, partial) | ✅ Done | jsonb-slice trigger fix **committed** (`af6514a`); migration + chat UX improvements **committed** (`3353215`) |
| 11 | **Home screen item counter** (cleanup) | ✅ Done | Removed "X items" text from product grid header |

**Remaining (see sections below):** CI green (§3.1), webhook HMAC (§3.2), secrets (§3.4), real tests (§4.1), docs drift (§4.2), deprecation rot (§4.3), debugPrint noise (§4.4), dependency bumps (§6.1), catch-with-stacktraces (§6.2), schema.sql (§6.3).

---

## 3. 🔴 Critical — Fix First

### 3.1 CI is Red — Tests Fail to Compile

**What's happening:**
- `flutter analyze` reports **961 issues** on `main`
- `flutter test` has **4 failing tests**:
  - `cart_provider_test.dart`, `cart_service_test.dart`, `order_service_test.dart` **fail to load** — they `import 'package:mocktail/mocktail.dart'` but **mocktail is not in `pubspec.yaml` dev_dependencies**
  - `widget_test.dart` throws 3 exceptions — the smoke test calls `SoleVisionApp()` which initializes Supabase/Firebase in `main()`, crashing in a bare test environment

**Impact:** Every push to `main` fails the CI check. The test suite is non-functional.

**Fix:**
1. Add `mocktail: ^0.3.0` to `dev_dependencies` in `pubspec.yaml`
2. Rework `widget_test.dart` to either:
   - Use `createMockClient` pattern, or
   - Extract app initialization into a testable entry point that guards platform-specific calls
3. Run `flutter test` until green
4. Verify `flutter analyze` issues decrease significantly

**Files affected:** `pubspec.yaml`, `test/widget_test.dart`

> ⚠️ **Still open.** Note: the product-improvement pass added `share_plus` to `pubspec.yaml` but did not touch the test setup.

---

### 3.2 PayMongo Webhook Signature Verification is a Stub

**What's happening** (`supabase/functions/_shared/paymongo.ts`):
```ts
export function verifyWebhookSignature(
  payload: string,
  signature: string,
): boolean {
  // TODO: Implement proper HMAC verification with PAYMONGO_WEBHOOK_SECRET
  return true; // ← accepts ALL requests
}
```

The `gcash-webhook` edge function marks orders as **paid** when it receives a `payment.paid` event through this "verified" webhook.

**Impact:** Anyone who discovers the webhook URL can forge a `payment.paid` event and get orders flagged paid without actual payment. This is the highest-severity security issue in the codebase.

**Fix:**
1. Implement PayMongo HMAC SHA-256 verification using the `PAYMONGO_WEBHOOK_SECRET` env var
2. PayMongo signs payloads with: `sha256(secret + body)` or uses a header with timestamp+signature
3. Store the webhook secret in Supabase Edge Function secrets (not in code)
4. Return 401 (not 200) on verification failure — the current 200-on-error masks issues

**Reference:** [PayMongo Webhook Security Docs](https://developers.paymongo.com/reference/verify-a-webhook)

**Files affected:** `supabase/functions/_shared/paymongo.ts`, `supabase/functions/gcash-webhook/index.ts`

> ⚠️ **Still open.**

---

### 3.3 Uncommitted Work — Seller Chat Fix + Migration

**✅ FIXED — Committed (`3353215`).** 

Migration `20260802000000_allow_sellers_create_conversations.sql` + all 3 Dart files committed in one unit.

> **Note:** The migration still needs to be **applied** to the live Supabase database. If it hasn't been applied, seller-initiated chats will still be rejected by RLS.

---

### 3.4 Secrets Committed to Public Repo

**What's happening** (`lib/constants/app_constants.dart`):
```dart
static const String url = 'https://psczvbfoybqhjeqssimw.supabase.co';
static const String anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...';
static const String maptilerKey = 'ZsHghTkRWCoZDpjMxUir';
```

These are hardcoded and committed to the public GitHub repo `kibs06/CUF`.

**Impact:**
- Supabase anon key is semi-public by design (RLS protects data), but it still reveals the project structure
- MapTiler API key is **not** semi-public — anyone can abuse it
- Once committed to git, secrets remain in history even after removal

**Fix:**
1. **Rotate the MapTiler key** immediately (revoke and regenerate in MapTiler dashboard)
2. Move secrets to `--dart-define` for local builds:
   ```bash
   flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=... --dart-define=MAPTILER_KEY=...
   ```
3. Add `.env.example` documenting required variables
4. Update CI (`release.yml`) to read from GitHub Secrets
5. Consider using `flutter_dotenv` package for simpler env management

**Files affected:** `lib/constants/app_constants.dart`, `pubspec.yaml`, `.github/workflows/release.yml`

> ⚠️ **Still open.** Note: the delivery-estimate pass added `deliveryEstimateText` to this file — secrets untouched.

---

## 4. 🟠 High Value

### 4.1 Tests Don't Actually Test the Code

**What's happening:**
`cart_provider_test.dart` re-implements subtotal and selection logic *inline* and asserts against its own copy — it would pass even if `CartProvider` were deleted. Similarly, parts of `order_service_test.dart` mock a `SupabaseService.createOrder` that may not match the real signature.

**Example from `cart_provider_test.dart`:**
```dart
test('calculates subtotal from items', () {
  // This tests the TEST's own logic, not CartProvider
  final subtotal = items.values.fold<double>(0.0, (sum, item) =>
    sum + ((item['price'] as double) * (item['quantity'] as int)));
  expect(subtotal, 450.0); // Always passes
});
```

**What to actually test:**
- `validateCartForCheckout()` with real inventory data (mock Supabase client)
- `createOrder()` triggering the DB inventory decrement
- Size resolution paths (exact match, numeric fallback, edge cases)
- RLS policy enforcement (customer cannot see other customers' orders)

**Estimated effort:** Medium — requires proper mocking infrastructure

> ⚠️ **Still open.** The recent features (sort/filter, recently-viewed, quantity limits) would be good candidates for new tests.

---

### 4.2 Docs Have Drifted Badly

**What's happening:**

| Doc | Issue |
|-----|-------|
| `docs/project_doc.md` (v1.2.0, July 3) | Says "AR fitting is a placeholder" — it shipped. Says notifications "not yet wired" — fully wired now |
| `supabase/schema.sql` | Acknowledged-outdated everywhere — still referenced by new contributors |
| `docs/AI_DEVELOPMENT_GUIDE.md` | Says "this project has NO git repository" — has 60+ commits |
| `releases/changelog.json` | v1.0.4 entry says "rebranded to CUFMAI" but branding was reverted (commit `f39b34b`) — not corrected |
| `docs/project_doc.md` | Version header says "1.2.0" — actual release is v1.0.5+6 |

**Impact:** New contributors and AI agents receive wrong information. Schema references are misleading.

**Fix:**
1. Update `project_doc.md` to reflect current feature status and version
2. Regenerate `supabase/schema.sql` from the live database (or mark it clearly as "reference only — check migrations for actual state")
3. Fix branding inconsistencies in changelog
4. Update `AI_DEVELOPMENT_GUIDE.md` to reflect git-based workflow
5. Consider a "single source of truth" doc that's easier to keep current

> ⚠️ **Still open.** The implementation session added feature docs under `docs/AI/` + this plan, but did not update the stale core docs.

---

### 4.3 Deprecation Rot (961 Analyze Issues)

**What's happening:**

| Issue Type | Count | Files |
|-----------|-------|-------|
| `withOpacity()` deprecated → `withValues(alpha:)` | ~104 | Throughout `lib/` |
| `RadioListTile` deprecations | ~16 | `product_detail_screen.dart` |
| Missing `mocktail` in pubspec | 3 | Test files |
| `uri_does_not_exist` | 3 | Test imports |
| Unused local variables | Several | Various |

Most of the 961 issues are `withOpacity` deprecations. The noise makes it hard to spot real issues.

**Fix:** Systematic find-and-replace:
```bash
# Find all withOpacity calls
grep -rn 'withOpacity' lib --include='*.dart'

# Replace: .withOpacity(0.1) → .withValues(alpha: 0.1)
```

**Estimated effort:** Low — mechanical replacement, no logic change

> ⚠️ **Still open.** Feature files were checked with targeted `flutter analyze` (0 errors/warnings) but the repo-wide count is unchanged.

---

### 4.4 DebugPrint Noise in Production Code

**What's happening:**
Over 175 `debugPrint` calls scattered throughout production code, including:
- Full FCM token dumps: `debugPrint('[Push] Full FCM token: $token')`
- Detailed SQL payloads: `debugPrint('[ORDER-CREATE] Inserting order_item: $payload')`
- Emoji-laden logs: `debugPrint('[STOCK-RESOLVE] ❌ No inventory rows found')`

**Impact:** Log noise in production, potential information leakage, no structured logging.

**Fix:**
1. Guard all debug prints behind `kDebugMode` (some already are, most aren't)
2. Consider a lightweight logging wrapper that can be disabled in release builds
3. At minimum, remove token dumps and verbose payload logging

> ⚠️ **Still open.**

---

## 5. 🟡 Product Improvements

> These are from the existing `docs/UI_UX_AUDIT.md` (July 21, 2026).

### 5.1 Missing Features (High Priority)

| Feature | Impact | Effort | Status |
|---------|--------|--------|--------|
| **Wishlist / Favorites** | No way to save products for later — flagged as "major conversion blocker" | Medium | ❌ **Not started** |
| **Search filters/sort** | Search bar exists but no filter by size/price/category or sort by price/rating | Medium | ✅ **Done** — sort bottom sheet (Newest, Price ↑/↓, Name), wired into existing category chips in `ProductProvider` |
| **Estimated delivery dates** | Checkout shows ₱100 delivery fee but no estimated arrival date | Low | ✅ **Done** — "Estimated delivery: 3–5 business days" under the delivery fee row |
| **Return/refund policy** | Terms & Privacy shows "Coming soon" placeholder | Low | ✅ **Done** — `TermsPrivacyScreen` (7-day returns, refund 5–7 days, buyer pays return shipping unless defective), marked draft/pending legal review |
| **Secure checkout indicators** | No padlock icon or "Secure Payment" text in checkout | Low | ✅ **Done** — lock badge + "encrypted and secure" copy in payment section |

### 5.2 Missing Features (Medium Priority)

| Feature | Impact | Effort | Status |
|---------|--------|--------|--------|
| Recently viewed products | No history of browsed items | Low | ✅ **Done** — `RecentlyViewedService` (SharedPreferences, cap 20, dedupe), horizontal section on home + empty-state hint |
| Quantity limit display | Cart doesn't show max available stock | Low | ✅ **Done** — "Max: X" label + disabled `+` at limit, plus "Only X left" `SoleBadge` urgency (design extra) |
| Size guide modal | No EU/US size conversion chart | Low | ✅ **Done** — `SizeGuideModal` bottom sheet with EU/US/CM table, "Size guide" link on product detail |
| Social sharing | Cannot share products with friends | Low | ✅ **Done** — `share_plus ^13.3.0`, share button in product detail AppBar |

---

## 6. 🟢 Hygiene

### 6.1 Outdated Dependencies

Key packages with newer versions available:

| Package | Current | Latest | Change |
|---------|---------|--------|--------|
| `permission_handler` | 12.0.3 | 13.0.0 | Major |
| `fl_chart` | 0.70.2 | 1.2.0 | Major |
| `flutter_slidable` | 3.1.1 | 4.0.3 | Major |
| `connectivity_plus` | 6.1.3 | 7.3.1 | Major |
| `firebase_core` | 4.12.1 | 4.13.0 | Minor |
| `firebase_messaging` | 16.4.3 | 16.5.0 | Minor |
| `google_mlkit_commons` | 0.11.0 | 0.12.0 | Minor |

**Note on the Aug 4 session:**
- `share_plus ^13.3.0` was **added** (needed for social sharing) — no conflicts.
- `flutter_staggered_grid_view` stays at `0.7.0` (last published version; `0.8.0` was never released). The masonry-grid bug was worked around by switching to stock `SliverGrid`/`GridView` instead of upgrading.

**Recommendation:** Update minor versions first (safe). For major versions, read changelogs carefully — especially `fl_chart` (0.70 → 1.2 has breaking API changes).

### 6.2 Error Handling Without Stack Traces

**What's happening:**
Many `catch (e)` blocks don't capture the stack trace (`st`), making debugging difficult. The chat system already hit this — the original `sendMessage` catch block swallowed errors, making "Failed • Tap to retry" impossible to debug.

**Example (pre-fix):**
```dart
} catch (e) {
  // Mark the placeholder as failed with retry option
}
```

**Example (post-fix, now committed):**
```dart
} catch (e, st) {
  debugPrint('[ChatView] sendMessage failed: $e\n$st');
}
```

**Fix:** Apply the `(e, st)` pattern across all catch blocks in services and providers. This is already the project's best practice — just needs to be applied consistently.

> ✅ **Partially done** — `chat_view.dart` now uses `(e, st)` + shows the raw error in a snackbar (committed in `3353215`). The rest of the codebase still needs the treatment.

### 6.3 Schema.sql is Outdated

**What's happening:**
`supabase/schema.sql` is acknowledged as outdated everywhere, but it's still the first file new contributors look at. The live database has evolved with:
- UUID PKs instead of TEXT
- Additional tables (conversations, messages, seller_notifications, reports, etc.)
- Removed columns (`story_entries.title`)
- Added columns and RLS policies

**Fix:** Either:
1. Regenerate from the live database using `pg_dump --schema-only`, or
2. Delete it and replace with a pointer to the migrations folder + docs

> ⚠️ **Still open.**

---

## 7. Recommended Execution Order

Current status of the original list (Aug 4):

| Priority | Item | Effort | Impact | Status |
|----------|------|--------|--------|--------|
| **1** | Add mocktail to dev_dependencies + fix widget_test | 30 min | Unblocks CI | ❌ Open |
| **2** | Commit uncommitted seller chat fix + migration | 15 min | Fixes seller chat | ✅ **Done** (`3353215`) |
| **3** | Implement PayMongo webhook HMAC verification | 2-3 hours | Security critical | ❌ Open |
| **4** | Rotate MapTiler key + move to --dart-define | 1 hour | Security | ❌ Open |
| **5** | Replace `withOpacity` → `withValues` (104 calls) | 1-2 hours | Code quality | ❌ Open |
| **6** | Fix widget_test to work without real Supabase | 1-2 hours | CI green | ❌ Open |
| **7** | Update stale docs (project_doc, changelog) | 1-2 hours | Onboarding | ❌ Open |
| **8** | Add proper tests (checkout validation, size resolution) | 4-6 hours | Reliability | ❌ Open |
| **9** | Clean up debugPrint calls | 1-2 hours | Log hygiene | ❌ Open |
| **10** | Update outdated dependencies (minor first) | 2-3 hours | Maintenance | ❌ Open |
| — | **8 product improvements (§5)** | — | — | ✅ **All done** (except Wishlist) |
| — | **Store masonry grid fix** | — | — | ✅ **Done** |

**Updated recommendation for next session:** the highest-value remaining work, in order:

1. **Green CI** — add mocktail, fix `widget_test.dart` (unblocks all future pushes)
2. **PayMongo webhook HMAC** (the one real security hole)
3. **Wishlist / Favorites** (the last major product feature from the UI/UX audit)
4. **Secrets hygiene** — rotate MapTiler key + move to `--dart-define`

---

## Appendix: Key Files Reference

| File | Purpose |
|------|---------|
| `lib/constants/app_constants.dart` | Supabase creds, colors, typography (contains hardcoded secrets) |
| `supabase/functions/_shared/paymongo.ts` | PayMongo API helpers (HMAC verification stub) |
| `supabase/functions/gcash-webhook/index.ts` | Webhook handler (uses stub verification) |
| `test/widget_test.dart` | Failing smoke test (expects 'SoleVision', hits 3 exceptions) |
| `test/services/order_service_test.dart` | Fails to compile (missing mocktail) |
| `test/providers/cart_provider_test.dart` | Tests own logic, not CartProvider |
| `.github/workflows/ci.yml` | CI pipeline (analyze + test) — currently red |
| `docs/project_doc.md` | Main docs (stale, outdated feature status) |
| `docs/UI_UX_AUDIT.md` | UI/UX audit (feature gap recommendations) |
| `releases/version.json` | Current release manifest (v1.0.5) |
| `releases/changelog.json` | Release history (branding inconsistency) |
| `lib/screens/customer/customer_home_screen.dart` | Sort bottom sheet, recently-viewed section, product grid |
| `lib/providers/product_provider.dart` | `SortMode` state + filtered/sorted product accessor |
| `lib/screens/customer/checkout_screen.dart` | Secure-payment badge, delivery estimate row |
| `lib/screens/customer/cart_screen.dart` | Quantity limits + low-stock badge |
| `lib/screens/customer/product_detail_screen.dart` | Share button, size-guide trigger, recently-viewed capture |
| `lib/widgets/size_guide_modal.dart` | New — size conversion bottom sheet |
| `lib/screens/shared/terms_privacy_screen.dart` | New — return/refund + terms screen (draft copy) |
| `lib/utils/recently_viewed.dart` | New — SharedPreferences recently-viewed helper |
| `lib/screens/store/store_profile_screen.dart` | Masonry → standard grid (fixed) |
| `lib/screens/store/collection_screen.dart` | Masonry → standard grid (fixed) |

---

*Generated by Buffy (AI assistant) — August 4, 2026*