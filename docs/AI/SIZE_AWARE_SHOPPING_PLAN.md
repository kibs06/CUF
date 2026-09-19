# Size-Aware Shopping Plan — Make the Foot Profile Drive Browse, Detail, Cart & Checkout

**Date:** September 17, 2026
**Status:** **Partly shipped** — see §0. Every code shape below that is not listed there is still a proposal.
**Scope:** Customer-side only. Use the customer's saved foot size to (a) badge products that stock it, (b) offer a one-tap filter, (c) pre-select it on the product page, (d) flag a mismatch in cart and checkout.
**No schema change, no migration, no server work.** Everything is computed client-side from data the app already fetches (§4.2).
**Related:** `docs/AI/SIZE_VARIANT_FLOW.md` (**the size-format contract this must not break** — §3.3 and §12.3) · `docs/AI/FOOT_SIZING_ARCHITECTURE.md` (where the size comes from) · `docs/AI/CUSTOMER_HOME_ARCHITECTURE.md` · `docs/AI/PRODUCT_ARCHITECTURE.md` · `docs/AI/DARK_MODE_PLAN.md` (house style + the dual-brightness golden guard)

---

## How to work this doc

Six phases. **Each one is independently shippable and independently revertable**, and each is smaller than the one before it is risky. Order matters: P0 makes sizes *mean* something, P1 computes the match invisibly, and only then does anything become visible to a customer.

```bash
# After EVERY phase — the gate before moving on:
flutter analyze lib test && flutter test
```

Every phase except P0 ships **behind `kSizeAwareShoppingEnabled`** (P1 step 4), so shipping a phase is not the same as showing it. Turn the switch on at the end of P5, or per-surface as P2/P3/P4 land if you'd rather stage it that way.

---

## 0. What has shipped since this plan was written

| Phase | State |
|---|---|
| **P0** — one size key | ✅ **Shipped.** `lib/utils/size_key.dart` exists as designed (§5.1): `sizeSystem`, `sizeNumber`, `sizeKey`, `sizeKeyForEu`, `sizeNumberInEu`, `formatSize`, `compareSizes`. The unit switcher takes the saved scale (`savedFootSizeCategory`), so EU 42 reads `US 10.5` for a woman; half sizes sort numerically; the duplicate `euToUs` bodies delegate here. **(Superseded in part:** the switcher now resolves its scale through `productSizeChart` — the product's own audience first, then the saved scale — see `PRODUCT_AUDIENCE_PLAN.md` P3; with `productAudienceEnabled` now `true` it passes the product's own chart when one is set, and exactly `savedFootSizeCategory(profile)` for an unset product — every product, until the catalog is tagged.**)** |
| **P1** — the match | ⚠️ **Shipped in a different shape.** The match rule lives in **`lib/utils/size_match.dart`** (pure) rather than as provider stamps: `stockByEuSize`, `matchStockedSize`, `stocksMySize`, plus `shoppingEuSizeFrom` (resolving “my size”). `ProductProvider.productsInSize(euSize)` applies it. **No `my_size` stamps on product maps, no `kMySizeCategory`, no `shoppingEuSize` on `FootMeasurementProvider`, no `refreshForShopping()`** — those existed to serve the chip and the badge, which are not built. |
| **P2** — discovery | ⚠️ **The section only, where the plan proposed a chip + badge.** `lib/widgets/in_your_size_section.dart` — “In your size”, products that stock the customer's size right now, behind the one-const switch `AppConstants.sizeAwareShoppingEnabled` (the `kBestSellersRailEnabled` shape). No card badge, no filter chip, no `kSizeAwareShoppingEnabled` under that name. **Shape amended (Sep 19, 2026):** it shipped as a horizontal rail, and is now the Artisan Catalog's own 2-column masonry grid (`lib/widgets/product_grid_section.dart`) — same data, same absence rules, laid out as a shelf of the feed rather than a strip to swipe. **Renamed (Sep 19, 2026):** the heading is now “Based on your size”; the widget, its file and `productsInSize` keep their names. **Capped at the section, Sep 19, 2026:** the feed previews `kHomePreviewCount` = 10 of the shelf and closes with a “See more” card (`lib/widgets/see_more_card.dart`) that pushes the uncapped shelf (`lib/screens/customer/size_listing_screen.dart`) — so the cap moved out of `productsInSize` (which now returns the whole shelf, `limit: 0`) into the section that knows how long a preview should be. The card renders **unconditionally** whenever the section does (amended the same day after checking the live catalog: the shelf held ≤10, and a card hidden exactly when the catalog is small would hide the only way into the shelf page). That page is the P3/P4 surface this plan did not have: a full size-filtered listing, reachable from the home feed. |
| **P3 / P4 / P5** | ❌ **Not started.** The product page still auto-selects the first size in stock; cart and checkout say nothing about the profile. |

**Two deviations worth knowing before building on this:**

1. **Resolution order is snapshot-first**, not scan-first (§5.2 proposed `latestMeasurement` → snapshot). `saveFootProfile` is written by BOTH the scan screens and the manual picker, so the snapshot is the most recent size the customer actually gave; a measurement left in memory can be older than a manual entry typed after it. The scan is the fallback for the cases the snapshot cannot cover (a best-effort write that failed, a size stored before the column existed).
2. **Nothing is stamped onto product maps.** The rail reads a derived list from the provider instead, so there is no stale-stamp class of bug to clear — `productsInSize(null)` is simply empty. A future badge phase that needs `product['my_size']` on a card should stamp it then, following `_stampUnitsSold()`.

### §1 is superseded

The gap table in §1 (“`profiles.foot_size_ph` is read by **one banner**”, “discovery never reads a size profile”) described the state **before** P0 and the rail. `foot_size_ph` now drives `InYourSizeSection` on the home feed as well, and `size_match.dart` owns the comparison every later surface must share.

## Phase overview

| Phase | Deliverable | Visible to customers? | Est. | Depends on |
|---|---|---|---|---|
| **P0** | One size key: shared helpers + three defect fixes | No (labels/sort only) | 0.5 day | — |
| **P1** | The match, computed and stamped onto product maps | No (invisible) | 0.5 day | P0 |
| **P2** | Card badge + "My size" filter chip | Yes | 0.5–1 day | P1 |
| **P3** | Product page: pre-select + availability line | Yes | 0.5 day | P1 |
| **P4** | Cart marker + one checkout notice | Yes | 0.5 day | P3 |
| **P5** | QA, docs, cleanup, switch-on | — | 0.5 day | P2–P4 |

**Total ≈ 3–4 days.**

Rollback is per phase because the switch gates the visible ones: flip `kSizeAwareShoppingEnabled` to `false` and P2/P3/P4 vanish; P0/P1 are inert without the switch.

---

## 1. The gap this closes

The app measures feet with an AR scanner, stores the result, and then **never uses it while shopping.**

| Fact | Evidence |
|---|---|
| `FootMeasurementProvider` is read by **exactly two widgets** — the v1 and v2 scan *results* screens. | `grep FootMeasurementProvider lib/` → `main.dart` (registration), the provider, `foot_results_screen.dart:122`, `foot_size_v2/foot_scan_results_screen_v2.dart:132` |
| `profiles.foot_size_ph` is written once and read by **one banner**. | written in `supabase_service.dart:145` (`updateProfileFootSnapshot`), read in `app_constants.dart:435` (`hasFootSize`) via `widgets/customer_foot_profile_banner.dart:16` |
| Product detail, cart, checkout and discovery **never read a size profile at all.** | `grep -i "recommendedEuSize\|foot_size_ph" lib/screens/customer/` → hits are scan screens only |
| `AppConstants.footProfileArScan`'s doc comment claims *"the rest of the app (checkout, size recommendations, the reminder banner) uses these to grade confidence."* | `app_constants.dart:404-406` — **checkout does not.** P5 corrects this comment. |

So the customer takes a 30-second scan, saves "EU 42", and every product page still opens on *"US 7"*, picked from whichever size happens to be first in stock (`product_detail_screen.dart:706-716`).

**Done looks like:** the customer who saved EU 42 sees which of the 40 cards on the home feed actually have their size, can filter to just those, lands on a product page already showing EU 42 selected, and is told once — at checkout only — if they've picked something else.

---

## 2. Decisions to lock before P0

P0 codes decision #1 into a constant, so lock that one first. The rest can be answered as their phase arrives.

| # | Question | Recommendation | Gates |
|---|---|---|---|
| **1** | Bare size default: US or EU? | **EU** — matches all five shipped labels and the 35–48 band | **P0** |
| 2 | Filter shape: chip, or a toggle beside the sort button? | **Chip** (`kMySizeCategory`) — reuses the pseudo-category machinery, one tap, hides itself when useless | P2 |
| 3 | Out-of-my-size products: hidden by the filter, or shown *unbadged*? | **Hidden when the filter is on; shown unbadged otherwise.** A filter that only dims is not a filter, but the default feed must not shrink silently | P2 |
| 4 | Checkout notice frequency | **Once per cart revision, dismissible** — anything more trains the customer to ignore it | P4 |
| 5 | Pre-select when the product sells a *different* system? | **Yes, when the EU value is a confident match** — otherwise this only works on EU-sized products, not the whole catalog | P3 |

---

## 3. Measured state: what already exists

### 3.1 The size, and where it comes from

Two sources, both already app-root providers (`main.dart:227-232`), both already populated for a signed-in customer:

| Source | Field | Fidelity | Today's readers |
|---|---|---|---|
| `FootMeasurement` (newest row, `foot_measurements`) | `effectiveEuSize` = `userAdjustedEuSize ?? recommendedEuSize` (`foot_measurement.dart:171`) | Full scan; carries width category, confidence, shoe category | scan result screens only |
| `profiles` snapshot | `foot_size_ph` (`auth_provider.dart:941-968` → `saveFootProfile`) | Cheap mirror written post-scan | the home reminder banner only |

`AuthProvider.saveFootProfile`'s doc comment states the intended split: *"full scan fidelity stays in foot_measurements — this is just the cheap snapshot other screens read."* **Nothing reads the snapshot.** This feature is the reader that comment assumes.

Also available and unused: `recommendedWidthCategory` (`'narrow' | 'standard' | 'wide'`) and `AppConstants.hasFootSize(profile)` / `needsFootProfile(source)`.

### 3.2 What product payloads already carry (why there's no new query)

`SupabaseService.fetchProducts()` (`supabase_service.dart:190-218`) — the query behind the home catalog — already selects:

```
'*, stores(name), product_images(image_url, display_order),
 inventory(size, stock), product_variants(size, stock, color),
 product_color_images(url, color_name, display_order)'
```

`fetchProductById()` (line 221) selects the same. **Size + stock per product is already on the client** before this feature starts. `ProductProvider.loadProducts()` even runs a second aggregation in parallel (`fetchUnitsSold()`) and stamps it onto each map — the exact pattern to copy.

### 3.3 The two precedents to copy rather than invent

| Precedent | Where | Why it's the template |
|---|---|---|
| `_stampUnitsSold()` — derived data written onto each product map so cards render it without reaching back into the provider | `product_provider.dart:122-131` | The badge must be renderable by `SoleProductCard` from `product['…']` alone. Same trick. |
| The `'On Sale'` / `'Best Sellers'` **pseudo-category** — a *derived* filter chip that hides itself when it would be a dead end | `categories` getter `product_provider.dart:140-160`; branch `:298-330` | "Only my size" is exactly this shape. No new filter machinery. |
| `kBestSellersRailEnabled` — one `const bool` switching a whole surface off | `customer_home_screen.dart` | The kill switch (P1 step 4). |

---

## 4. The three size defects (P0's reason to exist)

Not a UI problem. Make any badge before fixing these and every match is a coin flip.

### 4.1 A stored size's unit lives in a prefix — except when it doesn't

`SIZE_VARIANT_FLOW.md` §3.3 makes the format load-bearing:

```
product_variants.size   =  "{SYSTEM} {VALUE}"   →  "EU 40", "US 8", "UK 3.5", "JP 25" (custom)
inventory.size          =  synced from the variants; its exact key string is NOT settled by the docs
                           (SIZE_VARIANT_FLOW.md §7 shows "EU 40"; migration 20260703 says
                            cart_items.size is backfilled "to match inventory.size format" by
                            stripping LEADING LETTERS, which yields " 40")
cart_items.size         =  regexp_replace(pv.size, '^([A-Za-z]+)', '')   (migration 20260703)
```

The database resolves sizes **digits-only, everywhere** — `regexp_replace(size, '\D', '', 'g')` appears in the trigger, the voucher RPCs, the GCash RPCs, the pickup-reservation RPCs and the bulk-deposit RPC (`20260711_fix_trigger_security_definer.sql:33`, `20260808210000:140`, `20260915120000:418`, …). So `'EU 42'` matches `'42'` **because both reduce to `'42'`**.

**Consequence:** `"42"` and `"EU 42"` are the same size to the server but two different strings to Dart. `_buildSizesMap()` (`product_detail_screen.dart:648-688`) keys its map on the raw strings, so a product populating both tables can produce two entries for one physical size.

**P0 step 0 verifies the live key** (`select distinct size from inventory limit 20`). The plan doesn't depend on the answer — `sizeKey()` normalizes either form — but the leading-space wrinkle should be understood, not normalized away blindly.

### 4.2 The client has two contradictory conventions for a bare size

| Place | Bare `"40"` is treated as | Evidence |
|---|---|---|
| `unitOf()` — the product page's unit switcher | **US** | `cart_helpers.dart:66-71` — *"Bare numbers (no prefix) default to US — the app's canonical scale."* |
| Cart, checkout, seller orders, AR fitting, pending-GCash sheet | **EU** (hardcoded literal) | `cart_screen.dart:331` · `checkout_screen.dart:1477` · `seller_orders_screen.dart:138` · `ar_fitting_screen.dart:145,475` · `pending_gcash_checkout_sheet.dart:447` |

The **same stored size renders as "US 7" on the product page and "EU 40" in the cart** — a 33-size discrepancy in what the customer is told, on the shop's most important screen. Resolution = decision #1 + P0 step 3.

### 4.3 Half sizes sort as zero

```dart
// product_detail_screen.dart:681-686, and again in _buildStockByColor()
sizes.entries.toList()
  ..sort((a, b) => (int.tryParse(a.key) ?? 0).compareTo(int.tryParse(b.key) ?? 0));
```

`int.tryParse` returns **null** for `"9.5"` *and* for `"EU 40"` — both collapse to `0` and sort to the front. Fixed in P0 step 4.

### 4.4 Three divergent EU↔US converters

| Helper | Rule | Category-aware? |
|---|---|---|
| `cart_helpers.convertSizeNumber` | `EU = US + 33` | No — men's scale only |
| `FootMeasurement.euToUs` (`foot_measurement.dart:315`) | men `−33`, women `−31.5`, kids `−33` | Yes |
| `foot_measurement_utils.euToUs` (`:278`) | same as the model's | Yes |

The product page's US/UK switcher therefore mislabelled women's sizes. **This plan sidesteps it entirely by never converting for the match** (§5.2 compares and displays in EU, so identity conversion is all that's ever needed).

**Done separately (not part of the phases below).** The switcher now takes the shopper's saved scale. `size_key.dart` owns the offsets (`kEuToUsChartOffset`), the two duplicate `euToUs`/`euToUk` bodies delegate to it, `formatSize`/`convertSizeNumber`/`displaySizeInUnit` take an optional `category`, and `ProductDetailScreen` passes `savedFootSizeCategory(profile)`.

> **Updated by `PRODUCT_AUDIENCE_PLAN.md` P3.** The single value that screen passes is now
> `productSizeChart(...)` — the **product's own** audience chart first (a men's-cut shoe reads the men's
> label for every shopper), then the shopper's saved scale, then men's — behind the same
> `AppConstants.productAudienceEnabled` switch — **now `true`**. A product with an audience set reads that
> chart; every product without one resolves to `savedFootSizeCategory(profile)` exactly, so the paragraphs
> above still describe what an **unset** product shows — which, per P4's measurement, is every product in
> the live catalog. The chart keys, the offsets, and `sizeUnitsForCategory`'s "kids gets EU only" rule are
> unchanged — this plan's decision #1 (bare sizes are EU) is untouched. No saved scale → men's (the app's existing default), never a guessed one. The UK label stays on the app's single `EU − 33.5` chart on purpose: the app owns a women's offset for the US chart only, so the scan screens and the product page keep agreeing.

---

## 5. What P0 and P1 build

### 5.1 P0 — `lib/utils/size_key.dart` (pure, no Flutter)

One place that owns what a size *means*, so no surface invents its own rule. Pure functions → unit-testable without a widget harness, following `customer_profile_fields.dart`'s precedent.

```dart
/// Which system a bare (prefix-less) size belongs to. See decision #1.
const String kDefaultSizeSystem = 'EU';

/// Plausible EU band — sizes outside it are treated as an unknown system
/// rather than silently reinterpreted (§5.2 step 1).
const double kEuMin = 35, kEuMax = 48;

/// Half a size. The "closest available" tolerance — never a silent substitution.
const double kNearSizeToleranceEu = 0.5;

/// The system ('EU' | 'US' | 'UK' | 'JP' | …) a stored size string is in.
/// Prefers an explicit prefix; a bare number falls back to [kDefaultSizeSystem].
String sizeSystem(String raw);

/// The numeric value ('EU 40' → 40.0, '9.5' → 9.5). null when unparseable.
double? sizeNumber(String raw);

/// The digits-only key the DATABASE matches on — mirrors
/// regexp_replace(size, '\D', '', 'g'). Two sizes sharing a key are the same
/// row to every RPC in supabase/migrations/.
String sizeKey(String raw);

/// The profile's EU size as a [sizeKey], for comparing against catalog sizes.
String sizeKeyForEu(double euSize);

/// Value of [raw] in EU (identity when already EU). No per-category offsets —
/// §4.4 explains why that's the point.
double? sizeNumberInEu(String raw);

/// 'EU 40' / 'US 8' — the one formatter every surface uses instead of a
/// hardcoded 'EU ' literal (§4.2).
String formatSize(String raw, {String? unit});
```

### 5.2 P1 — resolving "my size" and the match rule

```dart
// lib/providers/foot_measurement_provider.dart — add getters, no new provider.
/// The customer's effective EU size for SHOPPING: the newest scan's effective
/// size (user-adjusted wins), falling back to the profiles snapshot. null when
/// the customer has never given a size — every surface must then render
/// NOTHING rather than guess.
double? get shoppingEuSize;
```

Read order: `latestMeasurement?.effectiveEuSize` → `profiles.foot_size_ph` → `null`.

**No new provider.** `FootMeasurementProvider` is already app-root and already loads the measurement; the snapshot fallback comes from `AuthProvider.profile`. A third provider is a fourth place to keep in sync.

**The match rule** — given profile EU size `E` and a product's size strings:

1. Map each size string to `sizeNumberInEu(s)`. Sizes with no determinable system **and** a value outside `[kEuMin, kEuMax]` are *unknown*: never matched, never claimed.
2. **Exact** — a catalog size equal to `E`.
3. **Near** — within `kNearSizeToleranceEu`. Reported as *"closest is EU 41.5"*, never substituted.
4. A product **stocks my size** when an exact match exists with `stock > 0`, using the **same stock rule as purchasability** (`lib/utils/product_stock.dart`) so a badge can never contradict the buy button.

---

## 6. The phases

### P0 — One size key · *0.5 day · no behaviour change intended*

**Goal:** every layer agrees what a stored size is, the customer-facing label stops contradicting itself, and half sizes sort correctly. This phase is a refactor with three small bug fixes; the deliverable is a passing characterization suite.

- [ ] **0. Verify the live keys** (5 min). `select distinct size from inventory limit 20` beside `select distinct size from product_variants limit 20`. Record what you see in this doc's §4.1 — it settles whether `inventory.size` keeps the prefix and whether the leading space is real.
- [ ] **1. Write `test/utils/size_key_test.dart` FIRST**, before the implementation. Cover `'EU 40'`, `'40'`, `' 40'`, `'US 8'`, `'UK 3.5'`, `'JP 25'`, `'9.5'`, `''`, `'Other'`, garbage — and assert the DB-mirror invariant directly: `sizeKey('EU 40') == sizeKey('40')`.
- [ ] **2. Create `lib/utils/size_key.dart`** (§5.1).
- [ ] **3. Fix the bare-size convention.** `cart_helpers.unitOf()` default → `kDefaultSizeSystem`, with a comment naming decision #1 and pointing here. Then delete the five hardcoded `'EU '` literals and route them through `formatSize()`: `cart_screen.dart:331`, `checkout_screen.dart:1477`, `seller_orders_screen.dart:138`, `ar_fitting_screen.dart:145` and `:475`, `pending_gcash_checkout_sheet.dart:447`. **These are outside the customer surface too (seller orders) — that's correct, one formatter.**
- [ ] **4. Fix the sort** (§4.3): `_buildSizesMap()` and `_buildStockByColor()` sort by `sizeNumber()`, not `int.tryParse`.
- [ ] **5. Resolve the stock-source question** (§R2 in §8). `_buildSizesMap` currently **sums** variant stock and inventory stock under one key, while its doc comment says *"the higher stock value wins"* — and `inventory` is derived from `product_variants`, so summing inflates. Key the map by `sizeKey()`, make **inventory win when present** (`fetchProducts`'s contract names it "the authoritative stock source for checkout", `supabase_service.dart:180-189`), and fix the lying comment.
- [ ] **6. Run the gate.**

**Done when:** `flutter analyze lib test` clean, `flutter test` green, the new size-key suite passes, and `grep -rn "'EU \$" lib/` returns nothing.

**Rollback:** a plain revert — nothing here is gated by the switch, and nothing here is customer-new. The only visible change is that a product page and the cart finally agree on which unit a size is in, plus correct half-size ordering.

---

### P1 — Resolve & stamp · *0.5 day · invisible*

**Goal:** the app knows whether each product has my size, and puts it on the product map where a card can read it — with nothing rendered yet.

- [ ] **1. `shoppingEuSize` + `refreshForShopping()`** on `FootMeasurementProvider` (§5.2). The refresh must no-op when already loaded.
- [ ] **2. `ProductProvider`:** add `const String kMySizeCategory = 'My Size'`, `applySizeProfile(double? shoppingEuSize)`, and a `mySizeCount` getter. Stamping writes `my_size` (`'exact' | 'near' | 'none'`), `my_size_stock`, and `my_size_label` (the display string) onto each product map — mirroring `_stampUnitsSold()`.
- [ ] **3. `applySizeProfile(null)` CLEARS all stamps** (signed out / no size on file). No stale stamps, ever — this is the mistake that would show a size badge to a customer who never gave one.
- [ ] **4. Add the kill switch** `const bool kSizeAwareShoppingEnabled` beside `kBestSellersRailEnabled`, **default `false`** until P5.
- [ ] **5. Wire the four refresh hooks:** after login, after a scan saves, after the manual size picker saves, and at the end of `loadProducts()`. Cheapest correct home for the first three is wherever the reminder banner already reads the profile.
- [ ] **6. `categories` adds `kMySizeCategory` only when** `shoppingEuSize != null` **and** at least one product matches — the exact dead-end-chip rule `'On Sale'` and `'Best Sellers'` follow (`product_provider.dart:154-159`).
- [ ] **7. `getFilteredProducts()` gains the branch** beside the existing pseudo-categories (decision #3).
- [ ] **8. Provider tests:** null clears everything; a size change **replaces** stamps rather than merging (the re-scan regression, §8 R5); the chip appears only when a match exists; selecting it returns exactly the stamped set.
- [ ] **9. Run the gate.**

**Done when:** tests pass and **nothing in the running app looks different** with the switch on or off. That's the whole point of this phase.

**Rollback:** delete the stamps; no customer could tell.

---

### P2 — Discovery: badge + chip · *0.5–1 day · first visible phase*

**Goal:** the value proposition, visible.

- [ ] **1. Card badge** in `sole_product_card.dart` — three states, absent-safe:

  | State | Text | Placement |
  |---|---|---|
  | `exact` with stock | `EU 42 ✓` | bottom-left of the image, clear of the countdown band |
  | exact, zero stock | `EU 42 sold out` | same slot, muted |
  | anything else, or **no size data on the map** | *nothing* | — |

- [ ] **2. Audit the four narrower product queries** for whether they can cheaply select the same relation: `collection_screen.dart:91`, `store_profile_screen.dart:692`, `cross_store_product_row.dart:78`, `recently_viewed_section.dart:272,295`, `recently_viewed_screen.dart:91`. **Absent data → no badge**, never a guessed one. If a query can't be widened cheaply, leave it badge-less and note it.
- [ ] **3. The chip** renders automatically once `categories` includes it — verify the label and the dead-end behaviour in the hero (`home_hero.dart:268-269`). Per decision #2, label it **`My size · EU 42`** so the customer can see what the app believes, and let that label tap through to the size picker.
- [ ] **4. Empty state:** if the filter is on and yields nothing, reuse the existing "browse all" action that clears the selection (`customer_home_screen.dart:837` precedent).
- [ ] **5. Widget tests:** badge for exact-with-stock, the sold-out variant, and **nothing** when the map lacks size data. Chip hidden with no profile.
- [ ] **6. Dual-brightness golden** for the badge (dark-mode guard).
- [ ] **7. Manual QA checklist** (see §6 P5 for the shared one) — at minimum: customer with a size, customer without, and a product in a US system.
- [ ] **8. Run the gate.**

**Done when:** a signed-in customer with EU 42 sees badges only on products that genuinely stock EU 42, the chip appears only when it can yield something, and a customer with no size on file sees the feed exactly as it is today.

**Rollback:** `kSizeAwareShoppingEnabled = false`.

---

### P3 — Product page · *0.5 day*

**Goal:** landing on a product shows the right size already selected, and says honestly what's available.

- [ ] **1. Default the unit switcher to the product's actual system**, not hardcoded `'US'` (`product_detail_screen.dart:505`), so an EU-sized product opens as `EU 42` rather than `US 7`.
- [ ] **2. Replace the auto-select rule** (`initState`, lines 706-716 and 745-757) — today it picks "the first size with stock". New order: **my size in stock → nearest in stock → first in stock.** `_selectedSize` must keep holding the **canonical DB string** (the existing invariant at line 503; the unit switcher is display-only).
- [ ] **3. One context line** under the size grid:
  - in stock in my size → `In your size · EU 42 · 3 left`
  - not stocked, near exists → `EU 42 isn't available — closest is EU 41.5`
  - product system unknown → *nothing*
- [ ] **4. Optional width advisory** — only if it can be said honestly. Nothing in the catalog carries width, so the sole truthful output is a line when `recommendedWidthCategory` is set, e.g. *"You scanned as wide; this style is not width-rated."* If it can't be said honestly, **ship nothing here** and leave it to the fit-data work (§7.2).
- [ ] **5. Widget tests:** opens with the profile size selected when stocked; falls back to nearest with the "closest is" line; falls back to first-in-stock with no profile; **never claims a size the product doesn't sell**.
- [ ] **6. Run the gate.**

**Done when:** the product page is never wrong about availability, and a customer with no profile sees today's behaviour exactly.

**Rollback:** `kSizeAwareShoppingEnabled = false`.

---

### P4 — Cart & checkout · *0.5 day*

**Goal:** catch the mismatch before money moves — once, quietly, without ever fighting the customer.

- [ ] **1. Cart line marker.** Route `cart_screen.dart:331` through `formatSize()` (P0 already did the label; verify), then when `item['size']` ≠ my size append a quiet inline `· not your usual EU 42` in the muted ink role. No banner, no dialog, no colour alarm — someone buying a gift or a different style on purpose must not be fought. The rows already carry their sizes locally, so no network call.
- [ ] **2. The one checkout notice** in `checkout_screen.dart`, a single `SoleCard` above the order summary, shown **only when at least one line item's size differs**:

  > **Sizes don't match your foot profile**
  > You usually order **EU 42**. This order has **EU 43** (1 item).
  > `[ Change sizes ]` `[ Continue anyway ]`

- [ ] **3. Enforce the four rules** (each is the difference between help and harassment): **never blocking** (no dialog, no disabled submit, no re-ask — the customer's explicit choice always wins); **once per cart revision**, dismissal persisted keyed on a hash of the cart's product+size pairs via `SharedPreferences` (the cart-cache pattern already in use); **not repeated** on confirmation, the GCash sheet, or tracking; **absent profile → absent card**.
- [ ] **4. Widget tests:** appears once; dismissal sticks; **does not return on rebuild**; absent with no profile; submission is never blocked.
- [ ] **5. Manual QA on device** — including a GCash flow, since that path re-enters the checkout screen from the deep link.
- [ ] **6. Run the gate.**

**Done when:** the notice can only ever inform, and a customer who dismisses it is never shown it again for that cart.

**Rollback:** `kSizeAwareShoppingEnabled = false`.

---

### P5 — QA, docs, switch-on · *0.5 day*

- [ ] **1. Full manual QA pass** on device:

  | Scenario | Expected |
  |---|---|
  | Customer with AR-scanned EU 42 | Feed badged; chip present; detail pre-selects 42 |
  | Customer with a manually-picked size | Same, labelled per open question #4 |
  | Customer who skipped the profile | **Feed and pages identical to today** |
  | Customer signed out | Identical to today; no stamps |
  | Product sold in US sizes | Converts correctly or stays silent — never a wrong badge |
  | Product with an EU 42.5 and no 42 | Near-match line, no false badge |
  | EU 42 out of stock, 41/43 in stock | "sold out" badge, nearest pre-selected |
  | Re-scan to a different size | Badges and pre-select follow immediately |
  | Offline / slow network | No badge flash, no skeleton, no wrong claim |
  | Dark mode + largest text scale | Badge and notice legible, no overlap with sale tag or countdown |

- [ ] **2. Dark-mode pass** (`docs/AI/DARK_MODE_PLAN.md` Phase 5 conventions) — roles only, no literal hex.
- [ ] **3. Fix the stale comment** at `app_constants.dart:404-406` (it claims checkout uses the foot profile; after this it's true for cart/checkout, so word it accurately or delete it).
- [ ] **4. Docs:** record the "one size key" rule in `SIZE_VARIANT_FLOW.md` §12.3; update `CUSTOMER_HOME_ARCHITECTURE.md` for the chip; CHANGELOG entry in the house voice.
- [ ] **5. Flip `kSizeAwareShoppingEnabled = true`.**
- [ ] **6. Final gate, then delete any dead code** the phases left behind.

---

## 7. Out of scope (listed so it isn't smuggled in)

1. **Per-product fit feedback** ("runs half a size small, 7 of 9 buyers sized up"). The natural follow-on — it makes the recommendation *learn* — but it needs a new table, a post-delivery prompt and a seller-facing display. Separate plan.
2. **Seller-side width/fit data** — required before any honest width *filter* (P3 step 4 is advice only).
3. **Tuning the women's/kids offset** in the unit switcher (§4.4) — the wiring is done; the `−31.5` value itself still needs an authoritative chart. A women's UK chart is not modelled at all.
4. **Anything that changes price, stock or the order.** This feature only ever *informs*.

---

## 8. Risks

| # | Risk | Mitigation |
|---|---|---|
| R1 | **Wrong confident claim** — a bare `"42"` that is really a custom system (JP/CHN) gets badged as the customer's EU 42. | Only claim when the system is known from a prefix, or the value sits inside `[kEuMin, kEuMax]` **and** the product's other sizes are consistent with EU. Otherwise no badge. |
| R2 | Two keys for one size — or one key counted twice (§4.1, P0 step 5). | Key by `sizeKey()`; **inventory wins when present**; fix the lying comment. Assert the displayed number equals the DB's. |
| R3 | Half sizes: profile 42, catalog 42.5 only. | The near band is ±0.5 and is *labelled "closest"*. Never a silent substitution, never at checkout. |
| R4 | Badge contradicts the buy button (badge available, cart says out of stock). | Both read `lib/utils/product_stock.dart`. Test asserts the badge's idea of "available" equals `purchasableProducts`'s. |
| R5 | Wrong size shown as "your usual" after a re-scan. | `shoppingEuSize` reads `effectiveEuSize` (user-adjusted wins); a re-scan **invalidates the stamps**, not just the measurement. |
| R6 | Signed-out / offline / profile not yet loaded → a badge flashes, then vanishes. | Stamps are **cleared**, not stale, until a size resolves. Absent size = absent UI. No skeleton, no guess. |
| R7 | The stored profile size is itself wrong (bad scan). | The adjustment stepper already corrects it (`userAdjustedEuSize`); the badge pre-selects but never locks the choice. |

---

## 9. Test plan (consolidated)

**Pure unit — `test/utils/size_key_test.dart`** *(P0)*
- Parsing/formatting over `'EU 40'`, `'40'`, `' 40'`, `'US 8'`, `'UK 3.5'`, `'JP 25'`, `'9.5'`, `''`, `'Other'`, garbage.
- `sizeKey('EU 40') == sizeKey('40')` — **the DB-mirror invariant.**
- Half sizes sort numerically (the §4.3 regression).
- Match rule: exact / near / unknown-outside-band; `stock == 0` → not available.

**Provider — `test/providers/product_provider_test.dart`** *(P1)*
- `applySizeProfile(null)` leaves every map unstamped.
- `applySizeProfile(42)` stamps exactly the products with 42 **in stock**.
- `categories` contains `'My Size'` only when a match exists; `getFilteredProducts` returns exactly the stamped set when selected.
- Re-running with a different size **replaces** stamps (R5).

**Widget** *(P2–P4)*
- `SoleProductCard`: exact-with-stock badge, sold-out variant, **nothing** when the map has no size data (R4).
- `ProductDetailScreen`: pre-select, nearest fallback + line, no-profile fallback, never a size the product doesn't sell.
- `CartScreen`: marker only on the mismatching line.
- `CheckoutScreen`: once, dismisses, does not return on rebuild, absent with no profile, never blocks.
- Dual-brightness golden for the badge and the checkout card.

**Guard** *(P0/P5)*
- A test asserting no customer-facing file contains a hardcoded `'EU '` size label — the exact regression the P0 cleanup invites.

---

## 10. Open questions

1. **How common are US-sized products?** Rare → the "unknown system" path in §5.2 is an edge case. Common → it's a mainline path and deserves real copy.
2. **Should the chip's label carry the size?** (`My size · EU 42`) so the customer sees what the app believes and can correct it from there. *Recommendation: yes.* (P2 step 3)
3. **Should the badge require an AR scan**, or is the typed onboarding size enough? The snapshot can outlive a deleted scan. *Recommendation: use either, but label the manual-only state less assertively ("your saved size") rather than "your scan".*
4. **A "swap all lines to my size" action in the cart?** Out of scope here, but the obvious next step once the mismatch is visible.

---

## 11. Key files

| File | Phase | Change |
|---|---|---|
| `lib/utils/size_key.dart` | P0 | **new** — the one parser / formatter / `sizeKey` |
| `lib/utils/cart_helpers.dart` | P0 | `unitOf()` default; `displaySizeInUnit` delegates to `formatSize` |
| `lib/screens/customer/product_detail_screen.dart` | P0, P3 | sort fix; pre-select rule; unit-switcher default; availability line |
| `lib/screens/customer/cart_screen.dart` | P0, P4 | label via `formatSize`; mismatch marker |
| `lib/screens/customer/checkout_screen.dart` | P0, P4 | label; single dismissible notice |
| `lib/screens/seller/seller_orders_screen.dart`, `ar_fitting_screen.dart`, `widgets/pending_gcash_checkout_sheet.dart` | P0 | label via `formatSize` |
| `lib/providers/foot_measurement_provider.dart` | P1 | `shoppingEuSize`, `refreshForShopping()` |
| `lib/providers/product_provider.dart` | P1 | `kMySizeCategory`, `applySizeProfile()`, `categories`, `getFilteredProducts` branch, `mySizeCount` |
| `lib/widgets/sole_product_card.dart` | P2 | size badge (3 states, absent-safe) |
| `lib/screens/customer/widgets/home_hero.dart` | P2 | verify chip label + dead-end behaviour |
| `lib/constants/app_constants.dart` | P1, P5 | switch + constants; correct the stale claim at `:404-406` |
| `docs/AI/SIZE_VARIANT_FLOW.md` | P5 | record the one-key rule in §12.3 |
