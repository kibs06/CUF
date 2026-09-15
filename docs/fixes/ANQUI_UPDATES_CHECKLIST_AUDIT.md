# AUDIT — "UPDATES (anqui)" Checklist

**Date:** September 15, 2026
**Status:** 12 of the 17 rows shipped, 3 partial, 0 missing, 2 need client clarification. **Items 1, 5, 7, 14 and 16 closed Sep 15, 2026.** Item 3 counts as shipped *with an open gap* — the iOS panel is still not tappable. Item 16 is code-complete and verified end-to-end against a real stack (including the server-side gate and the admin support view, both verified over real HTTP), but needs two dashboard toggles plus one deliberate `set_device_enforcement(true)` before it is live — until that switch is thrown the gate is installed but not enforcing. The support view that makes a lockout ticket investigable (Manage Users → ⋮ → Account Security) ships with it.
**Source:** `updates-checklist (1).md` (store-owner update request, 17 items)
**Scope:** SoleVision / CUFMAI Flutter app + Supabase backend (the customer + seller app)

---

## TL;DR

| # | Checklist item | Verdict | Notes |
|---|----------------|---------|-------|
| 1 | Border for the color white | ✅ **Done** (Sep 15) | Always-on hairline ring added to the customer swatch (extracted to `lib/widgets/color_thumbnail_swatch.dart`); every other swatch renderer audited — none affected. |
| 2 | Should not add to cart when clicking "Buy Now" | ✅ **Shipped** | `_buyNow()` builds a direct item list and never touches the cart. |
| 3 | For iOS (since it's the iOS panel) | ✅ **Shipped** | Update overlay / What's-New screen already branch on iOS. App Store listing is the real gap. |
| 4 | "Buy Now" is direct, cannot be added to cart | ✅ **Shipped** | Same code path as #2; `CheckoutScreen(directItems:)` is a separate mode. |
| 5 | Discount/voucher (store owner, scoped) | ✅ **Done** (Sep 15) | Per-product **sale price** was already shipped; now a full **voucher/coupon code** system too — codes entered at checkout, validated + applied **server-side** (forged totals impossible), seller management + redemption history. Built + verified locally; **not live until the two migrations and the edge function are deployed** (§5). |
| 6 | Categorize products (filter) | ✅ **Shipped** | Category chips + `AppConstants.productCategories` + `selectCategory()`. |
| 7 | Filter best seller products | ✅ **Done** (Sep 15) | **Filter** added, not just a sort: a `Best Sellers` pseudo-category chip (mirrors `'On Sale'`) plus a horizontally-scrolling Best Sellers rail on the home screen. One shared rule — top 20 by `units_sold`, never-sold excluded — so chip and rail can never disagree (§7). |
| 8 | Most-sold products at the top | ✅ **Shipped** | `SortMode.bestSelling` using the `units_sold` aggregation (not the default order); the new rail also ranks most-sold first. |
| 9 | Search for products like "sandals" | ⚠️ **Partial** | Search exists, but matches **name + tags only** — not category, not fuzzy. |
| 10 | Count how many times sold | ✅ **Shipped** | `fetchUnitsSold()` → "X sold" on cards + detail. Excludes bulk reservations. |
| 11 | Shorten / minimize the process (easier to find) | ❓ **Clarify** | Ambiguous — discovery friction vs checkout friction. Proposals below. |
| 12 | Slide to view more items | ⚠️ **Partial** | Hero + image carousels + horizontal rails exist; main catalog is a static grid. |
| 13 | Store rating | ✅ **Shipped** | `stores.rating` trigger + store profile stars + rate/reviews screens. |
| 14 | Reserve for pick up (expires in 24 h) | ✅ **Done** (Sep 15) | New lightweight **free pickup hold** — 1–2 units of one size, 24 h, no deposit, no approval — as a **separate sibling** to the deposit-gated bulk flow (they share only `inventory.stock` and the `reservations` notification category). Cancel/expire release stock exactly once (shared release core + `FOR UPDATE SKIP LOCKED` sweep); a collected hold becomes a real POS order and **counts toward `units_sold`** (§14). Built + verified locally; **not live until the migration is deployed**. |
| 15 | Ask clients about their policy | ❓ **Clarify** | Only platform-wide Terms & Privacy exists; no per-store policy. |
| 16 | Send OTP (prefer email) | ✅ **Shipped** | Signup verification + new-device step-up OTP; `trusted_devices` RLS + 30 pgTAP assertions. Enforced **server-side** by a device secret + RESTRICTIVE RLS on the 27 private tables (+44 pgTAP assertions) — a hand-crafted client with a stolen password cannot skip the code on direct table access. (`pickup_reservations`, item 14, joined the gate: 26 → 27.) **Support tooling included:** Manage Users → Account Security shows each account's devices, credential state, code timeline and lockouts (+31 pgTAP assertions). ⏳ Needs "Confirm email" ON + `{{ .Token }}` in two dashboard templates; the gate itself ships **switched off** until the updating build is out. |
| 17 | Require complete info at registration | ⚠️ **Partial** | Name/email/birthday/terms required; phone, gender, address are optional. |

**Bottom line:** most of the list is done. Items **1, 2, 4, 5, 7, 14 and 16** were closed on Sep 15 (item 5 = real voucher codes, after the client confirmed per-product sale was not enough; item 7 = a real best-seller *filter* + home rail, not just the sort; item 14 = a *separate*, no-deposit pickup hold rather than a small version of the deposit-gated bulk flow; item 16 = the scope the client chose — signup verification plus a step-up challenge on an unseen device, **not** passwordless login — now enforced by the database rather than only by the app). The remaining new work is the store-policy work (15) and small UX polish (9/12). Items 11 and 15 need the client to confirm intent before building.

**Two deployment steps are outstanding.** The voucher feature is finished in code and green in the local database suite, but its two migrations are still listed "Not yet applied" in `supabase/MIGRATIONS_LIVE_STATUS.md`, so **codes do not work in the live app yet**. Applying them, plus the matching `create-gcash-payment-intent` edge function, is the last action for item 5. Likewise `20260915170000_add_pickup_reservations.sql` (item 14) is code-complete and green locally but **not applied**, so the *Reserve for Pickup* action is not live either — and, unlike the vouchers, it has a hard prerequisite: the customer sees it only once the same build is out that teaches the app to hold a device secret, because the gate that will cover `pickup_reservations` ships switched off for exactly that reason.

---

## 1. Border for the color white — ✅ Done (Sep 15, 2026)

**Ask:** a light/white color swatch needs a visible outline so it doesn't disappear on a white card.

**What we had.** The customer product-detail color selector rendered `_ColorThumbnailSwatch` (a private class in `lib/screens/customer/product_detail_screen.dart`) whose ring was `Colors.transparent` when unselected. The swatch color for white/cream/beige/off-white/suede is `Color(0xFFF1E8DC)` (`_swatchColorFor`), so an unselected light swatch with no image was invisible on a white card. The seller side already had the correct pattern (`_SmallColorDot` / `_ColorSwatchChip` in `lib/screens/seller/add_edit_product_screen.dart`).

**Fix (shipped).**
1. **New public widget** `lib/widgets/color_thumbnail_swatch.dart` (`ColorThumbnailSwatch`), extracted from the private class so it can be unit-tested. It draws an **always-on hairline ring** (`AppConstants.borderGray` @ 0.5 alpha, 1 px) in a `Container` that **wraps** the `ClipOval` — outside the clip, so it is never clipped — while the existing primary selection ring is preserved and still shows when selected. The outer padding went 2 px → 1 px so the visible thumbnail stays exactly 40×40 (no layout reflow).
2. `lib/screens/customer/product_detail_screen.dart` imports and now uses `ColorThumbnailSwatch`.
3. **Audit of the other swatch renderers — none had the bug:**
   - `lib/screens/customer/customization_screen.dart` — the swatch chips already sit in a bordered card (`borderGray` 0.4 → `primary` when selected) and all six presets are dark/saturated, so no swatch can disappear. (The inner dot has no ring; harmless today, worth adding only if a light palette is ever introduced.)
   - `lib/screens/customer/ar_fitting_screen.dart` — **no color swatch UI exists**; `_activeColor` is hardcoded to `'Burnished Clay'` and shown only as text. Out of scope for a border fix (a missing-feature gap, tracked separately).
   - Store brand colour — the seller swatch (`lib/screens/seller/store_profile_screen.dart` ~463) and the create/edit-store pickers already draw a `borderGray` ring; customer store screens use the brand colour only as an accent (Follow button), not as a swatch.
4. **Regression tests** — `test/widgets/color_thumbnail_swatch_test.dart` asserts the hairline ring exists, is solid/1 px/non-transparent and equals `AppConstants.borderGray.withValues(alpha: 0.5)`; that the ring **wraps** the `ClipOval` (and is never inside it); that the thumbnail stays 40×40; and that a **selected** swatch still shows the primary ring.

**Verification:** `flutter analyze` clean on the touched files; full test suite **568/568 pass** (4 new).

---

## 2 & 4. "Buy Now" must not add to cart — ✅ Shipped

**Ask:** Buy Now goes straight to checkout and must never add the item to the persistent cart.

**What we have.** `product_detail_screen.dart` `_buyNow()` (~line 845) builds a `directItems` list in memory and pushes `CheckoutScreen(directItems: directItems)`. The code comment is explicit: *"Buy Now NEVER touches the cart, so backing out of checkout leaves My Cart exactly as it was."* `CheckoutScreen` has a dedicated direct-items mode (`lib/screens/customer/checkout_screen.dart`, ~lines 21, 47, 162, 685) that ignores the cart's selection entirely.

**Residual risk.** Several older docs still claim this is broken (`docs/debug/CUSTOMER_ORDER_PROCESS.md` #1, `docs/CUSTOMER_MODULE_DOCUMENTATION.md` #1, `docs/AI/CUSTOMER_MODULE_CONTEXT.md` #1 — "Buy Now doesn't navigate to checkout"). Those are **stale** and should be corrected so nobody "re-fixes" it.

**Fix (Small).**
1. Add a regression test: tapping Buy Now only → assert `CartService.addToCart` / cart items are untouched and `CheckoutScreen` receives `directItems`.
2. Strike the stale bug entries in the three docs above (mark as fixed, link to this audit).

---

## 3. "For iOS (since it's the iOS panel)" — ✅ Shipped (with a real gap)

**Ask:** the update prompt / "what's new" panel should behave correctly on iOS (where you cannot sideload an APK).

**What we have.** Both update surfaces already branch on platform:
- `lib/widgets/update_overlay.dart` — `final isAndroid = !Platform.isIOS;` (~line 87); `_buildActions` shows **"Update Now"** (APK download) on Android, and a static **"Open the App Store to update"** panel on iOS.
- `lib/screens/shared/whats_new_screen.dart` (~line 376) — `if (Platform.isIOS)` shows *"Updates are installed from the App Store on iOS."*, and skips the APK downloader.

So the "iOS panel" itself is handled. Two things are still missing to make it *useful* on iOS:
1. The iOS panel is **not tappable** — it's just text. Add an `appStoreUrl` constant and make it a link (`launchUrl`), ideally driven by the release manifest like `apkUrl` is.
2. Publishing to the App Store is a separate workstream (bundle id, signing, App Store Connect listing, review). The in-app update check (`update_checker.dart` / `releases/version.json`) is Android-oriented; confirm the version manifest still produces the correct "new version available" signal for an iOS build.

**Fix (Small, in-app) / Medium (App Store).** Wire the iOS panel to open the App Store URL; track App Store submission separately.

---

## 5. Discount / voucher — ✅ Done in code (Sep 15, 2026) · ⏳ pending live apply

**Client decision:** per-product sale pricing was confirmed **not sufficient** —
real coupon codes were built. Status: **built, wired and verified locally**; the
two migrations and the matching edge function still have to be deployed to the
live project before a customer can type a code.

**What shipped.**

| Piece | Where |
|---|---|
| Schema + RLS + orders money columns + pricing helpers | `supabase/migrations/20260915120000_add_vouchers.sql` |
| Evaluation, preview RPC, atomic redemption triggers, deactivate RPC | `supabase/migrations/20260915130000_add_voucher_enforcement.sql` |
| DB tests (pgTAP) | `supabase/tests/vouchers.test.sql` — 37 assertions, **executed green** on a clean local stack (see *Verified* below) |
| Dart client + model tests | `lib/services/voucher_service.dart`, `test/services/voucher_service_test.dart` |
| Customer UI | Voucher section in `lib/screens/customer/checkout_screen.dart` (works for cart checkout **and** Buy Now direct checkout) |
| Seller UI | `lib/screens/seller/vouchers_screen.dart` — Profile → Vouchers: create/stop codes, redemption history split by who funded the discount |
| Architecture | `docs/AI/CHECKOUT_AND_GCASH_ARCHITECTURE.md` §12 |

**How it is made forge-proof.** The client sends only a **code**. A BEFORE
INSERT trigger on `orders` re-evaluates the code inside the order transaction
(holding `FOR UPDATE` on the voucher row), reprices the cart from
`products` — sale-aware — and overwrites `subtotal_amount`,
`discount_amount` and `total_amount`. The redemption row + `uses_count` are
written by an AFTER INSERT trigger in that same transaction, so a code cannot
be double-redeemed under concurrency and an invalid code fails the insert with
a readable reason instead of silently charging more.

**Decisions taken without explicit client sign-off** (see §12.3 of the
architecture doc): vouchers **stack on top of** an active product sale with the
₱100 delivery fee added after the discount; vouchers are **online-only** (POS
rejects a code); `funded_by` lets a platform-wide code be absorbed by CUFMAI
rather than the seller; codes are **deactivated, never deleted**, and their
money terms freeze after the first redemption.

**Verified — the suite was executed, not just written (Sep 15, 2026).** Docker
Desktop was reinstalled on this machine, the local Supabase stack was started
with the same service exclusions CI uses, `supabase db reset` applied **all 89
migrations from scratch**, and `supabase test db` finished with **`Result:
PASS`** (5 files, 155 tests — item 16's `trusted_devices` suite added 30 more). The voucher file's 37 assertions cover every
rejection reason, percent codes + peso caps, clamping to the goods subtotal,
the **forged-total overwrite**, `max_uses = 1` under a `FOR UPDATE` lock race,
per-user limits, POS refusal, refusal without `items_snapshot`, and RLS (a
customer listing vouchers sees none). `supabase db lint` reports only two
pre-existing findings, neither from the voucher work.

Getting that run green also required fixing five **pre-existing** test-file
bugs — these files had evidently never been executed: the RLS canary failed on
a table `anon` deliberately cannot read; two files had SQL that cannot parse
(`to_regindex`, a stray paren); `is(count(*), 1)` has no pgTAP overload;
five `throws_ok` calls passed the expected message in the *errcode* slot; and
the bulk-reservation file created its hold under the **seller's** JWT (so every
customer-side step got `FORBIDDEN`) and selected rows with an unscoped subquery.
All five were test-side defects, not product defects.

**Remaining work:** apply the two migrations to the **live** database (see
`supabase/MIGRATIONS_LIVE_STATUS.md`) and deploy the updated
`create-gcash-payment-intent` edge function alongside them — the DB trigger is
what enforces the discount, so the function change alone is not enough.

---

**Original audit (kept for context).**

**Ask:** *"Add discount/voucher feature (store owner can give discounts without affecting other products)."*

**What we have (the scoped part is done).** Product-level sales are fully built: `products.sale_price` (+ `sale_starts_at` / `sale_ends_at`), the shared active-sale rules in `lib/utils/sale_price.dart` (`isOnSale`, `effectivePrice`, `salePercent`), sale-aware sorting/price, the hanging sale tag (`lib/widgets/hanging_sale_tag.dart`), a peel-away tape (`lib/widgets/sale_price_tape.dart`), an **"On Sale" pseudo-category** filter, and a seller UI in `add_edit_product_screen.dart` (~line 1657, *"Original price is never changed — customers see the discounted price"*). Research doc: `docs/store/PRODUCT_SALE_FEATURE_RESEARCH.md`; architecture: `docs/AI/HOME_ON_SALE_ARCHITECTURE.md`.

This **already satisfies the literal ask**: a store owner can discount one product without touching others.

**What is missing.** There is **no voucher/coupon code system** — no `vouchers`/`coupons` table, no code entry at checkout, no order-level discount field. A grep for `voucher` across the app returns only a chat quick-reply string.

**Fix (decide first).**
- If per-product sale is what the client wants → nothing to build; just demonstrate it. (Recommended, cheapest.)
- If they want **codes** ("ANQUI10", ₱100 off ₱1000) → new feature. Suggested shape: `vouchers` table (`code`, `store_id NULL` = platform-wide, `discount_type` fixed/percent, `min_order`, `max_uses`, `per_user_limit`, `starts_at`, `ends_at`, `funded_by`), a `validate_voucher(code, cart)` RPC, apply the discount inside the existing `createOrder` / GCash intent so totals can't be forged client-side, and a seller redemption screen. Reuse the GCash/order audit patterns already in `docs/AI/CHECKOUT_AND_GCASH_ARCHITECTURE.md`.

---

## 6. Categorize products (filter) — ✅ Shipped

**What we have.** The canonical category list lives in `AppConstants.productCategories` (`lib/constants/app_constants.dart` ~line 232) and is shared by the seller product form and the customer filter so they can't drift. `ProductProvider.categories` unions presets with on-product values and appends the "On Sale" pseudo-category; `selectCategory()` + `getFilteredProducts()` filter the catalog; the home screen renders category chips; stores expose a collection drill-down (`lib/screens/store/collection_screen.dart`, `store_profile_screen.dart`).

**Fix (Small, optional).** If they want richer filtering, add multi-select categories + price/size/color filters — already scoped in the roadmap as Phase 5 ("Advanced filters").

---

## 7. Filter best seller products — ✅ Done (Sep 15, 2026)

**Ask:** a way to see only best-selling products.

**What we had.** A **sort**, not a **filter**: `SortMode.bestSelling` ("Best Selling") in `lib/providers/product_provider.dart` (enum ~line 22, sort ~line 280), fed by the `units_sold` aggregation. It reordered the full catalog but never restricted it, and there was no Best-Sellers section anywhere.

**What shipped (both halves of the gap).**
1. **`Best Sellers` pseudo-category chip** — appended to `ProductProvider.categories` (so it appears in the same hero chip row as every other category) exactly like the existing `'On Sale'` pseudo-category, and handled by a sibling branch in `getFilteredProducts()`. It restricts the visible list, combines with search/tags and with any sort mode, and — like `'On Sale'` — is only offered while it can actually yield something.
2. **Best Sellers rail on the home screen** (`lib/widgets/best_sellers_section.dart`) — a horizontally-scrolling strip above the Artisan Catalog using the shared `HorizontalProductCard` (the same card as the profile's "Buy Again" / "Recently Viewed" rails), with a "See all" action that applies the chip. It reads the **same** live `units_sold` aggregation `loadProducts()` already fetched — no second query, no cached snapshot — and ranks most-sold first.

**The inclusion rule (a product decision, made deliberately).** Top **20** products by `units_sold`, **excluding anything that has never sold**. "Has ever sold" alone was rejected: on an established catalog it returns most of the catalog and the chip stops being a filter. The rule lives in one place — `bestSellerProducts()` in `lib/providers/product_provider.dart` — so the chip and the rail can never disagree; ties break on rating then name, because the catalog list is reshuffled per load and an unstable sort would reshuffle the rail too.

**Empty state.** A brand-new store (nothing sold yet) does **not** get a dead chip or an empty rail — `hasBestSellers` gates both, so the home screen is exactly what it is today. The `Best Sellers` filter follows `'On Sale'`'s existing degradation if the data empties under a selected chip: the chip disappears and the grid shows its empty state with a "browse all" escape.

**Verified.** `test/providers/product_provider_test.dart` (24 tests: the rule, the cap, the tie-break, chipping, combining with search/tags/sort, the empty catalog, and that `'On Sale'` + `SortMode.bestSelling` still behave) and `test/widgets/best_sellers_section_test.dart` (6 tests: empty rail, header/badge/cards, most-sold order, horizontal scroll, "See all"). `flutter analyze` clean; full suite 611 green.

**Note.** The seller-side product list has its own filter bar (On Sale / Low Stock / Featured / Inactive) — a stock-health axis with no `units_sold` aggregation loaded for the seller scope, so `Best Sellers` was deliberately **not** added there. The seller's Reports screen already has "top 5 by units sold".

---

## 8. Most-sold products at the top — ✅ Shipped

**What we have.** `SupabaseService.fetchUnitsSold()` (`lib/services/supabase_service.dart` ~line 231) sums `order_items.quantity` for orders that are `status != 'cancelled' AND payment_status = 'paid'`, and `ProductProvider.loadProducts()` fetches it in parallel with the catalog and stamps `units_sold` onto each product. `SortMode.bestSelling` sorts descending by that value.

**Caveats worth stating to the client.**
- The **default** order is `SortMode.featured` (a per-session shuffle), not best-selling. If "appear at the top" means *by default*, change the default sort. As of Sep 15 the Best-Sellers rail (item 7) does put the most-sold products at the top of the home screen — but only in a rail, not by reordering the whole catalog.
- POS sales are included (they're paid, non-cancelled orders), and so are **fulfilled pickup reservations** — fulfilment writes a paid POS order, so it is counted by construction (§14). **Fulfilled bulk reservations are not counted** (documented in `docs/AI/BULK_RESERVATION_ARCHITECTURE.md` §219), because they record no sale at all.

---

## 9. Search for products like "sandals" — ⚠️ Partial

**What we have.** A full search funnel: `lib/screens/customer/product_search_screen.dart`, the home hero + sticky search bars (`widgets/home_hero.dart`, `widgets/home_sticky_search_bar.dart`), persisted history (`lib/services/search_history_service.dart`), and the filter in `ProductProvider.getFilteredProducts()`.

**The gap.** Search matches the **product name (substring)** and **tags (per-word)** only — it does **not** match the `category` field, and there is no fuzzy/stemming match. So a product named *"Lola's Woven Flat"* with category `Sandals` will **not** be found by the query "sandals". A grep confirms category is never consulted in the search predicate.

**Fix (Small → Large).**
- **Small:** add `category` (and ideally `collection`) to the search predicate. One-line-ish change in `getFilteredProducts()`.
- **Medium:** normalize plural/singular + common misspellings (a small synonym map: sandals/sandal/slip-on/flip-flop).
- **Large (roadmap Phase 5 P0):** Postgres full-text search (`tsvector` column + GIN index + `websearch_to_tsquery`) with fuzzy `pg_trgm` fallback, so search scales past the client-side filter.

---

## 10. Count how many times sold — ✅ Shipped

**What we have.** `units_sold` (see item 8) is displayed as social proof: `"$sold sold"` on product cards (`lib/widgets/sole_product_card.dart` ~line 145, with compact formatting via `lib/utils/compact_number.dart`), on the product detail social-proof row (`product_detail_screen.dart` ~line 1445), and in seller Reports ("top 5 by units sold", `lib/services/sales_service.dart` ~line 562, `reports_screen.dart`).

**Fix (Small, optional).** ~~Decide whether fulfilled reservations should count.~~ **Decided (Sep 15, 2026, §14):** a **fulfilled pickup reservation counts** — collecting a hold writes a real paid POS order, which is exactly what `fetchUnitsSold()` already sums, so it needs no special case; **fulfilled bulk reservations still do not**, because they record no sale at all. Still open: whether the store profile should show an aggregate "X sold" badge.

---

## 11. Shorten / minimize the process (easier to find) — ❓ Needs clarification

**Ambiguous.** Two plausible readings:

**(a) Discovery friction — "easier to find products/stores".**
Already partly addressed: category chips (including the new Best Sellers chip), search, recently viewed, "More from Store", following feed. Cheap wins: promote search to the home top bar (exists), add a **New Arrivals** rail to sit beside the Best Sellers one (item 7 shipped the Best Sellers rail Sep 15), and surface the search entry earlier on scroll.

**(b) Checkout / re-order friction — "fewer steps to buy".**
- The **Buy Again** screen already exists (`lib/screens/customer/buy_again_screen.dart`) for one-tap reordering — surface it more prominently.
- Consider: quick-add from the grid (size-less add is risky), a persisted cart across sessions, and collapsing checkout's two steps into one for one-item orders.

**Recommended action:** ask the client *which* process feels long (browsing vs checkout vs registration) before building. Note item 17 may be the same complaint (registration).

---

## 12. Slide to view more items — ⚠️ Partial

**What we have (carousels already slide):**
- Home hero banner `PageView` (`lib/widgets/home_hero.dart`, real banners from Supabase).
- Product image carousel `PageView.builder` (`product_detail_screen.dart` ~line 1030).
- "More from Store" horizontal product scroll (`_MoreFromStoreSection`).
- Recently-viewed horizontal section.
- A nav store carousel (`docs/AI/NAV_STORE_CAROUSEL_ARCHITECTURE.md`).

**The gap.** The **main catalog is a static 2-column grid** (and the home uses a masonry/grid), so "slide to see more" only applies to rails/carousels, not the primary browse surface.

**Fix (Small → Medium).** The Best Sellers rail shipped Sep 15 (item 7); a **New Arrivals** rail would complete the pair, and consider swipe-parity between a product image carousel and its siblings. If the client means "swipe through the whole feed like a deck", that's a bigger interaction redesign and needs confirmation.

---

## 13. Store rating — ✅ Shipped

**What we have.** `stores.rating` (+ `review_count`) maintained by the `refresh_store_rating()` DB trigger (referenced in `lib/models/store.dart` and `lib/screens/seller/store_profile_screen.dart`). Displayed on the store hero/info cards (`store_hero_card.dart`, `store_focused_info.dart`), the store profile stats (`store_profile_screen.dart` ~line 738), and the seller dashboard (~line 668). Rating + review flows: `lib/screens/store/rate_store_screen.dart`, `lib/screens/store/store_reviews_screen.dart`, `lib/services/review_service.dart`, shared star widget `lib/widgets/sole_star_rating.dart`. Architecture: `docs/AI/STORE_ARCHITECTURE_AND_RATINGS.md`.

**Fix (none).** Optionally surface the store rating on product cards / search results for trust.

---

## 14. Reserve for pick up (expires after 24 hours) — ✅ Done (Sep 15, 2026) · ⏳ pending live apply

**Ask:** a customer should be able to reserve a pair for pickup, with the reservation expiring after 24 hours. **Client decision:** the small (1–2 pair) hold is **FREE** — no deposit, stock simply released if unclaimed.

**What already existed.** A **bulk reservation** system (reseller holds): a customer asks a seller to hold a large quantity; the seller approves, which opens a **24-hour GCash deposit window**; stock is drawn only when the store owner confirms the deposit; the hold auto-expires (sweep). Tables/RPCs: `bulk_reservations`, `bulk_reservation_deposits`, `request/decide/cancel/fulfill/expire_bulk_reservation`, statuses `pending → awaiting_deposit → approved → fulfilled` (plus cancelled/rejected/expired). See `docs/AI/BULK_RESERVATION_ARCHITECTURE.md`, `lib/services/reservation_service.dart`, migrations `20260913110000`–`20260913140000`.

**The gap.** That is a **bulk, deposit-gated, approval-gated reseller** feature — it is not the "reserve 1–2 pairs for pickup at the store, hold for 24 h, then release" the checklist describes, and it was deliberately **not** repurposed.

**What was built.** A separate, simpler sibling system — `pickup_reservations`:

- **Schema.** `pickup_reservations` (`customer_id`, `store_id`, `product_id`, `size`, `quantity`, `reserved_stock`, `status`, `pickup_deadline`, exactly-once audit stamps, `fulfilled_order_id`, `reminder_sent_at`). Statuses: `active` → `fulfilled` / `cancelled` / `expired`. **No deposit column and no approval state exists.**
- **The cap is 2**, from the checklist's own "1–2 pairs". Above it the RPC raises `ABOVE_PICKUP_CAP` and the sheet points the customer at the bulk flow. The number lives in **one** SQL function, pinned to the Dart constant by a contract test.
- **RPCs:** `request_pickup_reservation` / `cancel_pickup_reservation` (customer **or** seller) / `fulfill_pickup_reservation` (seller, "customer arrived") / `expire_pickup_reservations` / `send_pickup_reservation_reminders`.
- **Stock** is held by the **same mechanism the bulk flow uses** — a `stock >= quantity` compare-and-set decrement of `inventory.stock` (the only availability number the app reads, so a held size is genuinely unbuyable by everyone else). It is **not** a second parallel concept, and the hold is size-specific (`inventory`/`order_items` are keyed `(product_id, size)`).
- **Exactly-once release.** Cancel and the sweep share one core that re-reads the row `FOR UPDATE` and **no-ops if the status already moved on**, so expiring and cancelling the same hold can never double-return stock. The sweep also uses `FOR UPDATE SKIP LOCKED`.
- **Fulfilment** converts the hold into a real POS order (`source='pos'`, `status='received'`, `payment_status='paid'`, seller-chosen method, cash by default) — paid **at the counter**, not through online checkout, and inventory is **not drawn a second time** (the hold already moved the units). A hold is fulfilable for a short grace period past its deadline, but not one the sweep already released.
- **Notifications** all reuse the existing `reservations` category: request → customer + store owner, **T-2 h reminder** (the customer gets *one per hold* — they have one pair to collect; the **store gets one aggregated summary per batch** — "2 pickup holds expire in the next 2 hours — 2 pairs return to stock unless collected", because twenty holds must not mean twenty notifications), expiry → customer + store owner, cancel → counterparty.
- **The store's early warning.** The seller screen opens with a summary band — `2 holds · 3 pairs held` / `2 pairs back within 2h` — plus a `Lapsing soon (N)` filter chip that appears only when there is something in it, and the dashboard chip carries the same signal in one line from a single query. "Returning" counts both holds inside the 2-hour window (the same window the server reminder uses) **and** any already past their deadline but not yet swept, since those are the first units to come back — a lapsed hold is counted as still held, because it is.
- **The hold can be extended once, and only while it is still live.** "I am on my way but I will not make 6pm" is exactly what a free hold should survive, so the customer can ask for one more window (`extend_pickup_reservation`, +24 h) — but a store must not end up parking stock indefinitely. Three rules, each enforced in the RPC: only the **customer** may extend (a store extending its own hold is a bulk reservation), only **before the deadline passes** (once it has, the sweep may release the stock at any moment, so more time is not ours to promise), and only **once**. The total is therefore capped at **48 h from reservation**, and that ceiling is a **table CHECK** (`pickup_reservations_within_max_window`, plus `…_within_extension_cap`), so no code path — including a future RPC that forgets to check — can exceed it. Stock is untouched (the units left the shelf at creation), nothing is charged, and the extension **re-arms the T-2h reminder** because the new deadline is owed its own warning. Both sides are notified: the customer gets the new deadline (and "that was your last extension"), the store is told its commitment grew.
- **Duplicate holds are impossible, not just unlikely.** The RPC's own "you already hold this size" check is **serial** — two simultaneous submits both pass it — so a partial unique index on `(customer_id, product_id, size) WHERE status = 'active'` backs it up. The loser gets `23505` and the whole call rolls back (stock included); the app shows the same copy as the serial path, from one shared constant. Worth noting the failure mode: the stock compare-and-set already prevented overselling, so the only symptom was one customer holding the same pair twice — the kind of thing that never surfaces as a bug report.
- **UI:** a *Reserve for Pickup* action on product detail (quantity capped at 2 **and** at the size's live stock), *Profile → My Pickup Reservations* with a countdown + cancel, and a seller screen with *customer arrived — fulfill* + manual release, surfaced on the seller dashboard.
- **`units_sold` decision (the audit's open question, now closed): YES.** A fulfilled pickup counts, and not by a new exception — `fulfill` writes exactly the kind of order `fetchUnitsSold()` already sums (`order_items.quantity` over paid, non-cancelled orders), so it feeds Best Sellers (item #7 / item #8) with no new aggregation anywhere. Bulk reservations still do not count, because they record no sale at all.

**Separate, on purpose.** The two systems share only `inventory.stock` and the `reservations` notification category. A deposit or an approval step appearing in the pickup flow is a bug, and the contract test asserts the pickup service never references the bulk tables or RPCs.

**Verified:** **128** pgTAP assertions (cap, insufficient stock, the compare-and-set, the partial unique index on an *active* hold, held/released stock, the **sweep-vs-manual-cancel race with no double-release**, sweep idempotency, an expired-vs-live pair, fulfil's order shape + single stock draw + `units_sold`, the T-2 h reminder firing exactly once, the store summary's counts and per-store isolation, the ownerless-store guard, and the **extension rules** — the constants, both CHECK constraints, no stock movement, the cap, a direct 72-hour UPDATE refused by the constraint itself, only-the-customer, a lapsed hold refused, and the reminder re-armed), **94** Dart tests (14 contract + 57 service + 10 sheet widget + 6 seller widget + 7 customer widget), **844** Flutter tests total, `flutter analyze` clean, and **358** DB assertions from a clean `supabase db reset`. Full detail: `docs/AI/PICKUP_RESERVATION_ARCHITECTURE.md`.

**⏳ Not live.** `20260915170000_add_pickup_reservations.sql` is **not yet applied** (`supabase/MIGRATIONS_LIVE_STATUS.md`). It also folds the new table into the trusted-device gate — `pickup_reservations` is customer-private, so it is gated like `orders`/`cart_items` (26 → 27 gated tables), which the pgTAP invariant "every RLS table is either device-gated or explicitly exempt" forces any future migration to remember.

---

## 15. Ask clients about their policy — ❓ Needs clarification

**Ambiguous.** Likely one of:

**(a) Collect + display each store's own policy** (returns, warranty, pickup hours). Today only **platform-wide** copy exists — `lib/screens/shared/terms_privacy_screen.dart` with `CUFMAITermsPolicy.customer|seller|all`, plus the `TermsPolicyTile` used at signup. There is **no per-store policy** field.
- Fix (Medium): add `stores.policy_returns`, `stores.policy_pickup`, `stores.policy_warranty` (or a single rich-text `policy` jsonb), a seller editor in store settings, and display on the store profile + at checkout.

**(b) Ask the customer to acknowledge a store's policy at purchase** (a per-order policy-acceptance step).
- Fix (Small): surface the store's policy in `CheckoutScreen` with an acknowledgement checkbox, recorded on the order.

**(c) Ask customers for feedback about the platform's policies** (a survey).
- Fix (Small): reuse the existing report/support flow (`lib/services/report_service.dart`, `support_chat_screen.dart`).

**Recommended action:** confirm which before building. (a) is the most likely and most valuable.

---

## 16. Send OTP (prefer email) — ✅ Done in code (Sep 15, 2026) · ⏳ pending dashboard config + enforcement switch

**Ask:** send a one-time code by email (during registration / verification).

**What we had.** Supabase supported it (`otp_length = 6` / `otp_expiry = 3600` documented in `config.toml`, TOTP MFA already shipped), but the app **never called** `signInWithOtp` / `verifyOtp` (zero grep hits) and `SIGNUP_ARCHITECTURE.md` documented **auto-login after sign up** — email confirmation was not enforced, so accounts could exist with unverified addresses.

**Client decision confirmed:** scope is (1) **signup verification** and (2) a **step-up OTP challenge on a device the account has never been seen on**. Explicitly **not** passwordless login, and additive to the existing TOTP MFA.

**What was built.**
1. **Confirm email is ON** in `supabase/config.toml` (local), and the app handles both configurations. This is not only a screen: there is no `on auth.users` trigger and `profiles`' INSERT policy is `auth.uid() = id`, so with confirmation ON the **profile write moves to verify time** (`writeProfileFromMetadata`, row-safe for legacy accounts).
2. **One shared verify screen** (`lib/screens/shared/email_otp_screen.dart`) for both purposes, with resend + a visible cooldown + an expiry countdown matching the configured `otp_expiry`.
3. **Signup path:** customer signup and the seller flow both route through the code gate; the seller flow verifies **before** uploading documents (the private bucket's RLS needs a session), and verification never grants seller access — the application still lands as `seller_status='pending'`.
4. **New-device path:** a per-install device id in secure storage, a new `trusted_devices` table keyed by `(user_id, device_id)` with RLS (reads/revokes only; writes only via the `SECURITY DEFINER` `trust_device()` RPC that takes the user from `auth.uid()`), and a password login from an unknown device withdraws the AAL1 session and requires a code. Reviewable/revocable in Account & Security → **Manage Login Device**.
5. **Decisions made and documented** (see `docs/AI/EMAIL_OTP_AND_DEVICE_TRUST_ARCHITECTURE.md` §3.4, §3.5, §6): TOTP MFA **satisfies** the step-up so MFA users skip the email code; every existing user's device looks new on first login post-rollout → **one code each, no grandfathering**; legacy never-confirmed accounts are **not** dead-ended (a fresh code is mailed and the verify screen is shown).
6. **The step-up is now enforced by the SERVER, not by the screen** (`20260915150000_enforce_trusted_devices.sql`, §Part C of the same doc). Point 4's challenge was a *client-side* gate: a hand-crafted client holding a stolen password could simply not ask for the code and still read every private table. The gate now requires a **device secret** — 32 random bytes minted by `trust_device()`, kept only as a SHA-256 in a `device_secrets` table with **no policies and no grants**, sent as `x-cufmai-device: <device_id>:<secret>` and checked by `public.device_is_trusted()` in a **RESTRICTIVE** RLS policy on the 26 private tables (`orders`, `cart_items`, `messages`, `customer_addresses`, `payment_intents`, `vouchers`, `sales_transactions`…). The device *id* is deliberately not the credential — it is a UUID the client invents.
   - **A stolen password cannot mint a secret:** `trust_device()` requires a session that already proved possession (`amr` otp/magiclink, or `aal2`), so the secret can only come from an emailed code or an MFA factor.
   - **Bootstrap tables are exempt on purpose** (each for a concrete lockout): `profiles` (role routing), `trusted_devices` (the challenge reads it), `failed_logins` (the lockout counter runs *before* any step-up). Public catalogue tables are exempt too — a gate there is friction without protection.
7. **Rollout is staged and reversible.** Enforcement ships **OFF** (`device_enforcement_policy.enforcement_enabled = false`), so applying the migration cannot break the installed client, which sends no header. Flip it with `select public.set_device_enforcement(true);` (admin-only RPC) once the updating build is out. The client also *repairs itself*: on session restore it asks `device_gate_open()`, so while enforcement is off no code is ever mailed for this reason, and the moment it is switched on, an already-signed-in install fixes itself instead of showing empty screens.

**Verified end-to-end on a real local stack**, not just unit-tested: `signUp` with confirmation ON really returns no session; the delivered email really contains a 6-digit code; `verifyOtp(type: signup)` really returns a session and sets `email_confirmed_at`; a wrong code really returns `otp_expired`; `signInWithOtp(shouldCreateUser: false)` really does **not** create an account for an unknown address.

**The gate itself was then verified over real HTTP** (Kong → PostgREST → RLS, with a genuine password-grant session rather than a simulated one): `orders` with no header → `200 []`; with a wrong secret → `200 []`; with the correct secret → the row; another account's device id with a valid secret → `[]`; `profiles` and `trusted_devices` still readable with no header (so the app can render *and* the challenge can run); `trust_device` on the password session → **403 / 42501 "A verified email code or a second factor is required…"**; a cart INSERT → **403 by the `Require a trusted device` policy**; and with enforcement switched back off, the same header-less read returns the row again.

`supabase test db` → 7 files / **229 tests PASS** (30 for `trusted_devices` + 43 for the gate + 31 for the support view below); `flutter test` → **750 PASS**; `flutter analyze` clean.

**The secure-storage seam is now tested too.** The claim "logging out and back in on this phone does not re-trigger the OTP" used to rest on structure rather than execution, because nothing in the suite could drive `FlutterSecureStorage`. It is now driven by the plugin's own `setMockInitialValues`, so the real `DeviceTrustService` is exercised across simulated relaunches and through the actual logout cleanup (`BiometricService.clearCredentials` + `AccountManager.removeAccount`), with the keychain-unavailable path in an un-mocked companion file. Writing those tests found and fixed two defects: `BiometricService.clearAll()` used a blanket `deleteAll()` on the *shared* secure store (unreachable, but it would have wiped the device identity and its step-up credential), and the secret-retirement loop deleted while iterating `readAll().keys`, which skips entries and left stale secrets behind on some platforms.

> ⏳ **Three items are outstanding before this works on the live project** (a `config.toml` default does not change the hosted project):
> 1. Authentication → Sign In / Providers → Email → **"Confirm email": ON**.
> 2. Authentication → Email Templates → **add `{{ .Token }}`** to **Confirm signup** and **Magic Link**.
> 3. Apply `20260915150000_enforce_trusted_devices.sql`, then — **only once the build carrying the device header is in users' hands** — run `select public.set_device_enforcement(true);`. Until that switch is thrown the server gate is wired up but not enforcing; the migration alone deliberately changes nothing.
>
> The stock Supabase templates render only a confirmation **link** — verified against a real stack — so without those edits the code-entry screen has nothing to accept. Templates to mirror live in `supabase/templates/`.

**Support tooling — the ticket this feature creates, answered.** A step-up gate generates exactly one new support request: *"I got a new phone and I can't get in."* Before this, nothing in the admin portal could investigate it — an admin could not see whether the account had a device on record, whether that device still held the credential the gate checks, whether a lockout was in force, or whether enforcement was even switched on. **Manage Users → ⋮ → Account Security** now opens a per-account view (`20260915160000_add_admin_account_security.sql` + `lib/screens/admin/admin_account_security_screen.dart`):
- **What it shows:** every trusted device with **`has_secret`** — a device the app lists as trusted while the server refuses it is the headline state — plus the account's confirmation/lockout/role facts, GoTrue's own code-and-sign-in timeline, the password lockout rows, and the enforcement switch.
- **It states what it cannot know, in the payload:** a wrong code leaves **no trace** server-side (GoTrue rejects it without writing anything), and a refused device is **never recorded** (a phone that never finished the step-up has no row at all). So an empty timeline cannot be misread as "nobody tried" — the exact wrong conclusion in a lockout ticket.
- **The timeline had to match three shapes,** measured against a real GoTrue: `user_recovery_requested` carries the user in `actor_id`, but `user_signedup` puts the **service role** there and the user only in `traits.user_id`. An `actor_id`-only filter silently drops every signup event, so both a pgTAP assertion and the HTTP run include a service-role-shaped row.
- **Locked down:** `SECURITY DEFINER` + `is_admin()` (42501 for anyone else), granted to `authenticated` only (`anon` → **401**, so accounts cannot be enumerated without a session), subject taken as an **argument** because investigating someone else's account is the point, and `device_secrets` — which has no grants at all — is read only for the **mint time**, never the hash (verified: `secret_hash` does not appear in the response text).
- **Verified over real HTTP** with an admin JWT, using the client's exact call: admin → **200** with both devices' credential state and exactly the 7 documented device keys; non-admin, own account → **403/42501**; anonymous → **401**; unknown id → **P0002** naming the id.
- **A design decision worth knowing:** while enforcement ships **OFF**, the screen leads with "the device gate is switched off" and *suppresses* the device findings, because blaming a credential-less device when the gate is off sends support down the wrong path. The device evidence is still on screen — only the interpretation changes.

---

## 17. Require complete information at registration — ⚠️ Partial

**What we have today** (`lib/screens/auth/customer_register_screen.dart`, see `docs/AI/SIGNUP_ARCHITECTURE.md`):

| Field | Customer signup | Seller application |
|-------|-----------------|--------------------|
| Full name | **Required** | **Required** |
| Email | **Required** (+ duplicate check) | **Required** |
| Birthday (13+) | **Required** | **Required** |
| Password (+ confirm) | **Required** | **Required** |
| Terms acceptance | **Required** | **Required** |
| Phone | Optional | **Required** (Step 1) |
| Gender | Optional (self-describe) | Optional |
| Address | Not collected at signup (collected at checkout) | Store location + 3 business docs + 5 product photos **Required** to apply |

So "complete information" is largely enforced for sellers but **loose for customers** — phone is optional, gender is optional, and no address is captured up front.

**Fix (Small → Medium).**
1. Decide the **customer** mandate: make phone required (it's needed for delivery/pickup contact), and optionally require a delivery address before the first checkout.
2. Prefer a **"Complete your profile" gate at first checkout** over hard-blocking signup — it protects conversion and matches the existing skippable-onboarding pattern (`FootProfileOnboardingScreen`).
3. If phone becomes required, add a PH format validator + (optionally) verify it — which ties into item 16.

---

## Cross-cutting observations

- **Docs have drifted.** At least three docs still call Buy Now "broken" (#2/4) while the code is correct, and the roadmap/`PROJECT_IMPROVEMENT_PLAN` predate the sale, reservation, and rating features. Fixing the references prevents wasted "re-fixes".
- **Two checklists now overlap.** `docs/fixes/GO_LIVE_PRELAUNCH_CHECKLIST.md` covers payment/webhook/security launch blockers; this audit covers product/UX requests. Keep them separate but cross-link.
- **Migrations not applied.** The bulk-reservation migrations (items 8/10/14 touch their behavior) and the two **voucher** migrations (item 5) are still listed **"Not yet applied"** in `supabase/MIGRATIONS_LIVE_STATUS.md`. Voucher codes therefore do not work in the live app until they are applied and the updated edge function is deployed. Any reservation work (item 14) must land after its migrations are applied.
- **The DB suite is executed, not just written.** Docker Desktop was reinstalled locally and `supabase db reset` + `supabase test db` now pass end to end — 4 files, 125 assertions (vouchers 37 of them). Getting there required fixing five pre-existing test-file bugs; see §5. CI (`supabase-migrations.yml`) runs the same suite on any PR touching `supabase/`.
- **Fulfillment is pickup-only in practice.** `fulfillment` is hardcoded `'pickup'`. If the client is leaning into pickup reservations (item 14), that's aligned — but it also means the delivery UI is currently decorative.
- **`units_sold` definition.** "Paid, non-cancelled orders" — POS included, bulk reservations excluded. State this definition to the client so "best seller" and "sold count" match their mental model. The new Best Sellers chip/rail inherit it verbatim.
- **Pseudo-categories are a pattern now, not a one-off.** `'On Sale'` (active-sale rule) and `'Best Sellers'` (live top-20 by `units_sold`) are both derived rules dressed as chips: appended to `ProductProvider.categories`, branched in `getFilteredProducts()`, hidden when they can't yield anything. Any future "filter the catalog by a rule" ask should follow the same shape rather than adding a second filtering mechanism.

---

## Suggested build order

**Sprint 1 — cheap wins / verify (Small)**
1. ✅ **Done** — white-swatch border fix + audit of all swatch renderers (item 1). Test: `test/widgets/color_thumbnail_swatch_test.dart`.
2. Buy-Now regression test + fix stale docs (items 2/4).
3. Category matching in search (item 9, small part).
4. ✅ **Done** — Best Sellers filter chip + home rail (item 7; item 8's sort kept intact and used by the rail's order). Tests: `test/providers/product_provider_test.dart`, `test/widgets/best_sellers_section_test.dart`.
5. Make the iOS update panel tappable (item 3).

**Sprint 2 — registration & trust (Medium)**
6. ✅ **Done (Sep 15)** — email OTP: signup verification + new-device step-up challenge, shared code screen, `trusted_devices` (+ RLS, + 30 pgTAP assertions), the **server-side gate** that makes it unskippable (`device_secrets` + RESTRICTIVE policies, +43 pgTAP assertions, ship-off switch), and the **admin support view** for the ticket it creates (Manage Users → Account Security, +31 pgTAP assertions). Needs the two dashboard toggles above, then `set_device_enforcement(true)`.
7. Decide + enforce required customer fields (item 17).
8. Per-store policy fields + display (item 15a).

**Sprint 3 — pickup reservations (Medium)**
9. ✅ **Done (Sep 15)** — a lightweight 24 h **free** pickup hold, built as a **separate** system rather than by reusing the deposit-gated bulk machinery, with expiry sweep + notifications + seller fulfil (item 14; §14). Tests: `supabase/tests/pickup_reservations.test.sql` (128), `test/services/pickup_reservation_contract_test.dart` (14), `test/services/pickup_reservation_service_test.dart` (57), `test/widgets/pickup_reservation_sheet_test.dart` (10), `test/widgets/seller_pickup_reservations_test.dart` (6), `test/widgets/my_pickup_reservations_test.dart` (7). Needs `20260915170000` applied — and the same build that teaches the app to hold a device secret, since the table is gated.

**Sprint 4 — deeper search (Large, if wanted)**
10. Postgres full-text + fuzzy search (item 9 roadmap).
11. ✅ **Done (Sep 15)** — voucher codes (item 5). The client confirmed per-product sale was not enough, so the code system was built, wired into checkout on both paths, tested (pgTAP + Dart) and verified locally. Only the live deployment remains (§5).

**Open questions to send the client**
- Item 11: which process feels long — browsing, checkout, or registration?
- Item 15: store policy to *show*, to *accept at checkout*, or a *feedback survey*?
- Item 12: slide through rails only, or swipe through the entire product feed?


**Answered**
- Item 5: ~~is a per-product sale enough, or do you want discount codes?~~ → **codes** (client confirmed); built and verified Sep 15, 2026 (§5).
- Item 16: ~~is email OTP for signup verification, login, or both?~~ → **signup verification + a step-up challenge on an unseen device** (client confirmed); built and verified Sep 15, 2026 (§16).
- Item 14: ~~is a small pickup hold deposit-gated like the bulk flow, or free?~~ → **free** (client confirmed); the stock is simply released after 24 h. Built and verified Sep 15, 2026 (§14).

---

## Appendix — key evidence map

| Concern | File(s) |
|---------|---------|
| Color swatch (white border) ✅ fixed | `lib/widgets/color_thumbnail_swatch.dart` (`ColorThumbnailSwatch`), used by `lib/screens/customer/product_detail_screen.dart` (`_swatchColorFor` ~580); test `test/widgets/color_thumbnail_swatch_test.dart`; seller pattern in `lib/screens/seller/add_edit_product_screen.dart` (`_SmallColorDot` / `_ColorSwatchChip`) |
| Buy Now direct checkout | `lib/screens/customer/product_detail_screen.dart` `_buyNow()` ~845; `lib/screens/customer/checkout_screen.dart` (direct mode) |
| iOS update panel | `lib/widgets/update_overlay.dart` ~87; `lib/screens/shared/whats_new_screen.dart` ~376; `lib/services/update_checker.dart` |
| Per-product sale | `lib/utils/sale_price.dart`; `lib/widgets/hanging_sale_tag.dart`; `lib/widgets/sale_price_tape.dart`; `docs/AI/HOME_ON_SALE_ARCHITECTURE.md`; `docs/store/PRODUCT_SALE_FEATURE_RESEARCH.md` |
| Voucher / coupon codes ✅ shipped (pending live apply) | `supabase/migrations/20260915120000_add_vouchers.sql` (tables, RLS, orders money columns, pricing helpers) and `20260915130000_add_voucher_enforcement.sql` (`voucher_evaluate`, `validate_voucher`, the `orders` BEFORE/AFTER INSERT triggers, `deactivate_voucher`); `supabase/tests/vouchers.test.sql` (37 pgTAP assertions); `lib/services/voucher_service.dart`; voucher section in `lib/screens/customer/checkout_screen.dart`; `lib/screens/seller/vouchers_screen.dart`; `supabase/functions/create-gcash-payment-intent/index.ts`; `docs/AI/CHECKOUT_AND_GCASH_ARCHITECTURE.md` §12 |
| Category filter | `lib/constants/app_constants.dart` ~232; `lib/providers/product_provider.dart` (`categories`, `selectCategory`, `getFilteredProducts`) |
| Best-selling / sold count | `lib/providers/product_provider.dart` (`SortMode.bestSelling` sort, `bestSellers` / `hasBestSellers` / `bestSellerProducts()` rule); `lib/services/supabase_service.dart` `fetchUnitsSold()` ~238; `lib/widgets/sole_product_card.dart` ~145; tests `test/providers/product_provider_test.dart`, `test/widgets/best_sellers_section_test.dart` |
| Best Sellers filter + rail ✅ shipped | `lib/providers/product_provider.dart` (`kBestSellersCategory`, `kBestSellerLimit`, `bestSellerProducts()`, `categories`, `getFilteredProducts`); `lib/widgets/best_sellers_section.dart`; `lib/widgets/horizontal_product_card.dart`; `lib/screens/customer/customer_home_screen.dart` (rail + empty-state handling) |
| Search | `lib/screens/customer/product_search_screen.dart`; `lib/services/search_history_service.dart`; `lib/providers/product_provider.dart` (name+tags predicate) |
| Store rating | `lib/models/store.dart`; `lib/screens/store/store_profile_screen.dart`; `lib/screens/store/rate_store_screen.dart`; `lib/services/review_service.dart`; `docs/AI/STORE_ARCHITECTURE_AND_RATINGS.md` |
| Bulk (reseller) reservations | `lib/services/reservation_service.dart`; `lib/screens/customer/my_reservations_screen.dart`; `lib/screens/seller/reservation_requests_screen.dart`; `supabase/migrations/2026091311-140000_*`; `docs/AI/BULK_RESERVATION_ARCHITECTURE.md` |
| Pickup reservations ✅ shipped (pending live apply) | `supabase/migrations/20260915170000_add_pickup_reservations.sql` (table, RLS, the cap/hold/extension constants, the `(customer_id, product_id, size) WHERE active` unique index, the `…_within_max_window` and `…_within_extension_cap` CHECKs, `request`/`extend`/`cancel`/`fulfill`/`expire`/`send_*_reminders` RPCs, the shared release core); `supabase/tests/pickup_reservations.test.sql` (128 pgTAP assertions); `lib/services/pickup_reservation_service.dart`; `lib/screens/customer/widgets/pickup_reservation_sheet.dart`; `lib/screens/customer/my_pickup_reservations_screen.dart`; `lib/screens/seller/pickup_reservations_screen.dart`; entries in `lib/screens/customer/product_detail_screen.dart`, `lib/screens/shared/profile_screen.dart`, `lib/screens/seller/seller_dashboard_screen.dart`; tests `test/services/pickup_reservation_contract_test.dart`, `test/services/pickup_reservation_service_test.dart`, `test/widgets/pickup_reservation_sheet_test.dart`, `test/widgets/seller_pickup_reservations_test.dart`, `test/widgets/my_pickup_reservations_test.dart`; `docs/AI/PICKUP_RESERVATION_ARCHITECTURE.md` |
| Policies (platform only) | `lib/screens/shared/terms_privacy_screen.dart`; `lib/widgets/auth/terms_policy_tile.dart` |
| Auth / OTP / signup | `lib/screens/auth/customer_register_screen.dart`; `lib/providers/auth_provider.dart` `signUpCustomer` ~321; `lib/services/auth_service.dart`; `lib/services/mfa_service.dart`; `supabase/config.toml` (~212–314); `docs/AI/SIGNUP_ARCHITECTURE.md` |
| Email OTP (signup + new device) ✅ shipped (pending dashboard config; server gate shipped **off**) | `supabase/migrations/20260915140000_add_trusted_devices.sql` (table + `trust_device()` RPC + RLS); `supabase/migrations/20260915150000_enforce_trusted_devices.sql` (`device_secrets` + `device_enforcement_policy` + `device_is_trusted()`/`session_proves_possession()`/`device_gate_open()`/`set_device_enforcement()` + the RESTRICTIVE `Require a trusted device` policies on 26 private tables + `device_gate_exempt_tables()`/`install_device_gate_policies()`); `supabase/migrations/20260915160000_add_admin_account_security.sql` (`admin_account_security_overview()`); `lib/screens/admin/admin_account_security_screen.dart`; `lib/services/account_security_service.dart`; `lib/models/account_security_overview.dart`; `supabase/tests/trusted_devices.test.sql` (30 pgTAP assertions); `supabase/tests/trusted_device_enforcement.test.sql` (43); `supabase/tests/admin_account_security.test.sql` (31); `test/models/account_security_overview_test.dart`, `test/services/account_security_service_test.dart`, `test/widgets/admin_account_security_screen_test.dart`; `test/services/device_gate_contract_test.dart`, `supabase/templates/confirmation.html`, `supabase/templates/magic_link.html` (`[auth.email.template.*]` in `supabase/config.toml` — the key **must** be `confirmation`); `lib/screens/shared/email_otp_screen.dart`; `lib/services/email_otp_service.dart`; `lib/services/device_trust_service.dart`; `lib/services/login_challenge_service.dart`; `lib/screens/auth_gate.dart` (`_signupVerificationGate`, `_deviceChallengeGate`); `lib/providers/auth_provider.dart` (`verifySignupEmail`, `verifyDeviceChallenge`, `resend*`, `cancel*`); `lib/providers/seller_application_controller.dart` (`requestEmailVerification`); `lib/screens/shared/manage_login_device_screen.dart`; tests `test/services/email_otp_service_test.dart`, `test/services/device_trust_service_test.dart`, `test/services/login_challenge_service_test.dart`, `test/widgets/email_otp_screen_test.dart`; `test/services/device_trust_persistence_test.dart`, `test/services/device_trust_storage_failure_test.dart`, `test/services/device_gate_contract_test.dart`; `docs/AI/EMAIL_OTP_AND_DEVICE_TRUST_ARCHITECTURE.md` |

---

*Audit generated September 15, 2026 — evidence read directly from the working tree; line numbers approximate and may drift.*
