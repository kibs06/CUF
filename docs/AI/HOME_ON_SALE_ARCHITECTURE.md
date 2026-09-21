# Home Screen "On Sale" — Architecture Reference

**Date:** August 7, 2026
**Scope:** How the customer home screen (`lib/screens/customer/customer_home_screen.dart`) decides what is "on sale" and surfaces it. Enough context for another AI to understand and safely modify the sale feature without re-reading every file.
**Related:** `docs/AI/CUSTOMER_HOME_ARCHITECTURE.md` (the full home screen walkthrough — this doc only covers the sale parts in depth).

---

## 1. The rule — one source of truth: `lib/utils/sale_price.dart`

**A product is on sale ONLY when all of these are true:**

1. `sale_price` is set, `> 0`, and **strictly less than** `price`, AND
2. `sale_starts_at` (if set) is in the past, AND
3. `sale_ends_at` (if set) is in the future.

This single rule lives in **one place** — `lib/utils/sale_price.dart` — and is imported by every screen, provider, service, and widget that deals with prices. **Never reimplement the comparison inline.** The three helpers:

| Function | Returns |
|----------|---------|
| `isOnSale(product, {now})` | `bool` — true only while the sale is active (rule above). `now` is injectable for tests. |
| `effectivePrice(product, {now})` | `double` — `sale_price` while active, else `price`. This is what the customer actually pays. |
| `salePercent(product, {now})` | `int?` — whole-number discount for badges (e.g. `-30`), `null` when not on sale. |

The helpers coerce values defensively (`_asDouble` handles int/double/string from Supabase; `_asDate` handles `DateTime`/ISO strings).

> ⚠️ The active-sale rule is **app-layer only** — deliberately **no DB CHECK constraint** requiring `sale_price < price`. Sellers can freely set/clear a sale; "equal or higher" simply evaluates to "not on sale".

---

## 2. Data model (Supabase)

Migration: `supabase/migrations/20260804000000_add_product_sale_fields.sql`

`public.products` gained three nullable columns:

| Column | Meaning |
|--------|---------|
| `sale_price` | `NUMERIC`, NULL = not on sale. **`price` is ALWAYS the original price — never overwritten by a sale.** |
| `sale_starts_at` | `TIMESTAMPTZ`, NULL = active immediately |
| `sale_ends_at` | `TIMESTAMPTZ`, NULL = never expires |

Plus `idx_products_active_sale` on `sale_price WHERE sale_price IS NOT NULL`.

Sellers write these fields via `lib/screens/seller/add_edit_product_screen.dart` and `manage_products_screen.dart` (which validate `salePrice > 0` and `salePrice < price` in the UI); `lib/services/product_service.dart` maps them to DB inserts/updates.

---

## 3. Data flow

```
Supabase (products table — customer fetch hides out-of-stock)
        │
        ▼
SupabaseService.fetchProducts(hideOutOfStock: true)   (lib/services/supabase_service.dart)
        │
        ▼
ProductProvider.loadProducts(hideOutOfStock: true)    (lib/providers/product_provider.dart)
        │   stores raw rows in `_products`, shuffles once for the "featured" feed
        │   exposes: products, categories, selectedCategory, getFilteredProducts()
        ▼
CustomerHomeScreen  (context.watch<ProductProvider>)
        │
        ├─ "On Sale" chip (pseudo-category) → provider-side filtering
        ├─ "On Sale" section sliver → ON SALE poster + saleProducts list
        └─ every SoleProductCard → sale-aware prices via sale_price.dart
```

**Fetch details that matter for sales:**
- The home screen calls `loadProducts(hideOutOfStock: true)` — out-of-stock items vanish from the catalog (and therefore from all sale listings) and reappear automatically once restocked.
- The catalog is shuffled once per load (`reshuffle: true`) for the `featured` default sort — filtering/sorting operate on this base list, so sale behavior is unaffected.

---

## 4. Where "on sale" shows up on the home screen

### 4.1 "On Sale" category chip (pseudo-category, provider-side)

`ProductProvider.categories` derives `{'All', ...real categories...}` and **appends `'On Sale'` only if `_products.any(isOnSale)`**. It is a *filter chip*, not a real `category` value.

In `ProductProvider.getFilteredProducts(keyword)`:

```dart
final bool saleFilterActive =
    _selectedCategory == 'On Sale' && _products.any(isOnSale);
if (saleFilterActive) {
  filtered = filtered.where((p) => isOnSale(p)).toList();
}
```

- Selecting the chip filters the **main catalog grid** to active-sale items only.
- **Degradation when the data empties:** if the sale expires mid-session while `'On Sale'` is selected, `saleFilterActive` flips false and the `'On Sale'` branch stops applying — the selection then falls through to the generic category branch below it, matches no product's `category` (nothing has `category == 'On Sale'`), and the grid shows its empty state with its "browse all" action. It does **not** fall back to the full list. The chip itself also disappears on the next rebuild, since `categories` is recomputed from `_products`.
  - *(Corrected Sep 15, 2026 — this previously read "falls back to the full list — never a confusing empty state", which the branch structure does not do; verified while building the `'Best Sellers'` pseudo-category below, which is tested against exactly this case.)*
- **`'Best Sellers'` is the second pseudo-category** and behaves identically — see §4.4.

### 4.2 Dedicated "On Sale" section (home screen sliver) — headed by the ON SALE poster

`customer_home_screen.dart` computes `saleProducts = productProvider.products.where(isOnSale).toList()` in `build()` and renders a **section** whose **first grid cell is the ON SALE poster** (`lib/widgets/on_sale_card.dart`) — but **only in the default browse state**:

```dart
if (_searchKeyword.isEmpty &&
    saleProducts.isNotEmpty &&
    (productProvider.selectedCategory == null ||
        productProvider.selectedCategory == 'All')) ...
```

When the user is searching or has a category chip (incl. `'On Sale'`) active, the section is hidden — the main grid below already shows the relevant items, so it would duplicate.

**The heading row is gone (Sep 20, 2026).** The section used to open with an `On Sale` title and a yellow `HOT DEALS` price-tag badge (`_PriceTagBadge` + `_PriceTagPainter`, both deleted from `customer_home_screen.dart`). Both are replaced by the poster, which says the section's name at poster scale and carries the live figure the badge could only decorate — the same move "Based on your size" made when its text header became a `FitCard`.

**The poster's number is derived, never stored.** `maxDiscountPercent(saleProducts)` in `lib/utils/sale_price.dart` is the best discount among the products that are on sale *right now* — the shared `isOnSale` rule decides who counts, a product with no original price is skipped rather than divided by, and the result is **floored** (unlike `salePercent`'s badge, which rounds) because the card claims "up to" across the whole shelf and must never overstate a deal. It is computed in `build()`, and it is `null` while the catalog is loading or when nothing valid is on sale — which is what hides the poster, with no second condition. The poster is the grid's **first cell** (`itemCount: saleProducts.length + (maxDiscount == null ? 0 : 1)`, `if (maxDiscount != null && index == 0)`), so the +1 cell is *dropped* rather than left blank while the number is unknown.

**The poster is full bleed and its sign is a mark, not a character (Sep 21, 2026).** The grid runs at `childAspectRatio: 0.58`, a taller cell than `ON / SALE / UP TO 61%` has copy to fill, and `FitCard` spends the leftover as one band between the words and the closer (the number stays on the card's bottom edge). Two changes close almost all of it, both of them about *size*, never about the copy:

- **`padding: 0`** — the same full-bleed treatment the size poster (`in_your_size_section.dart`) and the Workshop poster already use. With the default 16px frame the poster's type was measured against a cell 32px narrower than the one the size poster gets at the same grid width (~21% smaller type), and the block visibly did not fill the cell next to it.
- **`%` travels as `FitCard.heroValueSuffix`, not inside the value.** `OnSaleCard.value` is the digits alone (`61`), so the number is scaled to the whole line and the sign is drawn small (`heroSuffixSizeOfWidth`, 0.2 of the inner width) and top-aligned on the digits. `61%` as one string shares the line three ways; `61` + a mark gives the digits the width, and a taller number is a taller hero block, which is what the band is waiting for.

The caption is back to the card's ordinary small one — the big thing on this poster is the number, and `UP TO` only says how to read it. What is *not* done: spreading `ON` and `SALE` apart to soak up the height (it costs the poster the tight two-word lockup that names the section), and the copy cannot be made taller than the cell's width allows. So a few px of band remain on a 183px cell — the poster fills its cell the way the size poster fills its own, not perfectly edge to edge.

**Tapping it opens the full sale list.** `lib/screens/customer/on_sale_listing_screen.dart` — the `SizeListingScreen` pattern: back button, the section's name, its count and its best discount, then the same `SoleProductCard` at the same `productGridRatio`, uncapped, and an empty state ("Nothing on sale right now") for a sale that ends while the page is open. It reads the catalog already in memory. **Since Sep 21, 2026 it carries the shared search + filter + sort toolbar** (§4.5) — the size shelf's band, unchanged — so a shelf a customer has already left the feed for can still be narrowed and re-ordered in place. (It used to say "no sort control", on the reasoning that the section that opens it has none; the section names the shelf, it does not have to be the only place the shelf is ordered.) This is deliberately *not* the `'On Sale'` chip: the chip narrows the Home feed in place, which is right for "only these, here"; the poster's tap asks to leave the feed for the sale, with the feed — and the section — waiting behind it.

**This section is a plain `GridView`, NOT masonry.**
- The section uses `SliverGridDelegateWithFixedCrossAxisCount` (2 columns, `childAspectRatio: 0.58` ≈ the masonry cards' average height).
- Cards here are rendered **without `imageAspectRatio`** → `SoleProductCard` uses `Expanded` image fill and adapts to any cell height without overflow. They are uniform by design, which is exactly what a fixed `childAspectRatio` is for.
- The main catalog below keeps `MasonryGridView.count` + deterministic `imageAspectRatio` per product id.

**Corrected Sep 19, 2026 — the older warning here overstated the risk.** It said two masonry grids in one `CustomScrollView` trigger a scroll-offset-correction loop in `flutter_staggered_grid_view` 0.7.0 that makes the bottom of the catalog unreachable. That loop was never reproduced with the box-level `MasonryGridView.count` grids this feed actually uses: "Based on your size" is now a second one (`lib/widgets/product_grid_section.dart`) directly above the catalog, and the feed still scrolls to its last card — pinned by `test/widgets/nested_masonry_scroll_test.dart`. What survives, and is the real reason to leave this section alone: its cards are **uniform**, so a deterministic grid is both exact and the honest shape here, and adding `imageAspectRatio` to them would make each card self-sizing inside a fixed cell (the empty-gaps/overflow defect this note was originally guarding against).

### 4.3 Per-card sale rendering — `lib/widgets/sole_product_card.dart`

Each card calls the shared helpers once:

```dart
final bool onSale = isOnSale(product);
final double displayPrice = effectivePrice(product);
final int? salePct = salePercent(product);
```

- **Hanging sale tag (top-right corner):** instead of a flat red pill, a physical-looking **hang tag** (`lib/widgets/hanging_sale_tag.dart`) is clipped to the card's top-right corner as a pure `Positioned` overlay — it never affects masonry sizing or the HOT DEALS grid contract. The tag shows a "?" until the user taps it, then flips to the live discount (`-23%`), with a pendulum idle swing, flip+bounce+sparkle reveal, haptic, and reduced-motion support.
- **Price block:** when on sale → two stacked lines: **sale price** (`₱{displayPrice}` in primary, bold) + **original price** with `TextDecoration.lineThrough` (muted). Otherwise → single price. The original/strikethrough line is **always visible**; the *sale-price* line is hidden behind a peel-away strip of tape (`lib/widgets/sale_price_tape.dart`) until the user taps it. The sale-price `Text` sits inside a box padded by `hitPadding` — that padding is the **≥40px tap target**, and per-site `hitPadding` tunes where the slack goes. The SAME padded box is returned in the revealed state, so the footprint is pixel-identical and nothing reflows. The tape **visual** is a separate `IgnorePointer` overlay that hugs the text and never reaches the strikethrough line.

**The target no longer has to be dead air (Sep 21, 2026).** The ≥40px has to come from *inside* the tape's own box: Flutter delivers a tap only within every ancestor's bounds, so slack cannot be borrowed from a parent and no overlay can reach outside its box. On a product card the padding-only version therefore opened ~18px between the rating row and the price and another ~8px between the two prices — invisible in the hit area, plainly visible on the card. `SalePriceTape.targetBelow` is the fix: a line that *belongs* with the price shares the target without the tape covering it, so `SoleProductCard` passes the strikethrough original price as `targetBelow` with `hitPadding: fromLTRB(10, 4, 10, 4)` and the ≥40px is the two price lines together (~44px). The visual's insets are measured against the price's own box (not the target's), so the tape still hugs the number alone. The other call sites are unchanged and still use padding: the detail screen `fromLTRB(10, 22, 10, 0)` and the Recently Viewed strip `fromLTRB(10, 20, 10, 9)`.
- **Option B — independent reveal states (confirmed decision):** the tape and the hanging tag each read their **own** per-user+per-product flag from `SaleTagProvider` (`isTagRevealed`/`revealTag` vs `isTapeRevealed`/`revealTape`) and each persist to their own key. Tapping the tag only flips the tag; tapping the tape only peels the tape — **no choreography, no stagger, no cross-triggering**. All four combinations (neither/either/both revealed) are valid and render correctly. On catalog load, reveals from the async provider load **jump** straight to revealed (never a wall of flips/peels) — only user-triggered reveals animate (`provider.isLoading` distinguishes the two).
- The "Try On" AR badge was **removed from cards** (redundant — the product detail page has its own Try-On entry). `onTryOnTap` no longer exists on `SoleProductCard`.
- The tape applies wherever the sale-price block renders: catalog grid, "On Sale" grid, HOT DEALS, the **Recently Viewed strip** (scaled down), and the **product detail** price row. Reduced motion → instant swap (no peel). Covered state exposes `Semantics` "Sale price hidden, tap to reveal".

#### 4.3.1 Reveal-state persistence — `SaleTagProvider`

The revealed/unrevealed state is **per user + per product**, and is the *same everywhere a product is shown* (cards, HOT DEALS, store screens, product detail hero). It is owned by `lib/providers/sale_tag_provider.dart`, which keeps **two independent sets** — never merged:

- **Hanging tag set** — key `sale_tag_reveals_<userId>` (JSON list of product ids).
- **Price tape set** — key `sale_price_reveals_<userId>` (separate list). Revealing one never affects the other.
- Backed by **local SharedPreferences** (`lib/services/sale_tag_service.dart`). ⚠️ Known limitation: local-only — reveals don't sync across devices.
- Both sets are loaded **once per signed-in user** (lazily, on first render — never per card per render) as two separate lookups; `revealTag()` / `revealTape()` flip the UI **optimistically** then persist in the background.
- Signed-out/guest: tags/tape render unrevealed; a tap flips/peels for the session only (nothing persisted).
- A revealed face always shows the **current live** `salePercent(product)` / `effectivePrice(product)` — the reveal only gates *whether* the number shows, not *which* number.

The same pattern (strikethrough original + effective price) is used in the **Recently Viewed strip** (`isOnSale(fullProduct)` on the resolved live product — no hanging tag at that tiny 130px scale, but the sale price does get the peel-away tape) and `product_detail_screen.dart` (tag hangs off the hero image's left edge; the sale price in the block below gets the tape; the full "You save ₱X · Ends …" note stays visible).

#### 4.3.2 Sale countdown overlay — `lib/widgets/sale_countdown_overlay.dart`

A countdown readout overlaid on the **bottom edge of the product image** telling the customer how long the sale lasts. It renders **only** where `isOnSale(product)` is true AND `sale_ends_at` is non-NULL — an open-ended sale (NULL end date) shows **no timer at all** (don't invent urgency).

- **Formats** (re-evaluated live on every tick, never cached):
  - **`> 24h` remaining** → `"2 days left"` / `"1 day left"` — whole days, **floored** (47h shows "1 day left"). Days-mode cards effectively never re-render (the display string only changes once a day).
  - **`≤ 24h` remaining** → a live ticking `HH:MM:SS` (real seconds move; Sora tabular figures via `AppConstants.monoStyle` so digits never jitter). The `remaining > 24h ? days : clock` choice is recomputed on every tick, so a countdown left open across the boundary flips over on its own.
  - **`< 1h` remaining** → the band deepens to a richer golden yellow + a slow gentle pulse (static urgent color under reduced-motion settings).
- **Performance:** ONE app-wide `Timer.periodic(1s)` (`SaleCountdownTicker`, ref-counted — starts on first subscriber, stops when the last visible countdown scrolls away) drives every visible countdown; **never one timer per card**. Countdowns count *ticks* (deterministic in tests) with a wall-clock clamp so they stay honest after backgrounding. Cards subscribe while visible and unsubscribe in `dispose`.
- **Expiry / fallback:** when the countdown reaches zero the overlay hides itself, and `SaleEndWatcher` (same file) fires a **one-shot** timer at the exact `sale_ends_at` moment that rebuilds its subtree with `now` = end + 1s — so `isOnSale(product, now: now)` flips false and the **hanging tag, price tape, sale-price line and countdown all fall back to non-sale together** (no stale/frozen sale UI on an idle screen). `SoleProductCard`, `ProductDetailScreen` and each Recently Viewed strip item are wrapped in a `SaleEndWatcher`; thread the `now` it provides into every sale helper.
- **Placement & look:** cards, the product detail hero and the Recently Viewed strip all get the **same full-width yellow (amber) band** across the image's bottom — pinned `left: 0, right: 0` so it always reaches both edges (no side gaps). Dark brown text (`AppConstants.secondary`) on amber (`0xFFFFC107` — the HOT DEALS accent) keeps contrast; under 1h the band deepens to golden yellow (`0xFFF0A500`) and pulses. On the detail hero the dot indicators sit raised above the band. Pure `Positioned` overlay everywhere — no layout/masonry impact, same contract as the tag/tape.
- `Semantics` is human-readable ("Sale ends in 2 days", "Sale ends in 1 hour and 30 minutes") at minute resolution — no per-second screen-reader spam.

### 4.4 `'Best Sellers'` — the second pseudo-category (added Sep 15, 2026)

> **⚠ Currently gated OFF (Sep 17, 2026).** The rail is hidden on the home screen by
> `kBestSellersRailEnabled = false` in `lib/screens/customer/customer_home_screen.dart`.
> Nothing was removed: the widget, the provider rule, the chip and every test of them
> are intact, and flipping that const back to `true` restores the rail with no other
> change. The `'Best Sellers'` **chip** is deliberately unaffected — it is a catalog
> filter (like `'On Sale'`), not this rail, and still works when selected.

The home screen carries a **Best Sellers** rail beside the On Sale section, fed by the `units_sold` aggregation (§4.1's pattern reused, not a parallel mechanism):

- **One rule, one place:** `bestSellerProducts(products, unitsSold)` in `lib/providers/product_provider.dart` returns the top `kBestSellerLimit` (= 20) products by `units_sold`, **excluding anything that has never sold**, most-sold first, ties broken on rating then name. Both the chip and the rail call it, so they cannot disagree. `hasBestSellers` gates whether either is offered at all.
- **Chip:** `categories` appends `kBestSellersCategory` (`'Best Sellers'`) when `hasBestSellers`, and `getFilteredProducts()` applies it through a sibling branch to the `'On Sale'` one (`bestSellerFilterActive`), with the same degradation described in §4.1.
- **Rail:** `lib/widgets/best_sellers_section.dart` renders a header (`Best Sellers` + a `SoleBadge('MOST SOLD')` + "See all") over a horizontal `ListView` of the shared `HorizontalProductCard` — the same 130×180 strip card as the profile's "Buy Again"/"Recently Viewed" rails. It reads `ProductProvider.bestSellers` (live), so **no extra query**. The home screen renders it only in the default browse state (`_searchKeyword.isEmpty` + no category filter), exactly like the On Sale section in §4.2 — **and only while `kBestSellersRailEnabled` is true (it is currently `false`, see the note above).**
- **No masonry concern:** it is a horizontal list inside a fixed-height `SizedBox`, not a second grid — §4.2's `flutter_staggered_grid_view` gotcha does not apply.

### 4.5 Searching and filtering a shelf in place — `ProductShelfToolbar` (added Sep 21, 2026)

Both shelf pages ("Based on your size", "On Sale") put one band under their heading: `lib/widgets/product_shelf_toolbar.dart` — a 44px field shaped exactly like the search page's (hairline, `radius: 6`, leading magnifier, trailing clear), the `All` + category chips, and `ProductSortChip` at the right edge.

- **One band, not one per page.** The chips and the sort control are the *same widgets* the search results page uses (`UnderlineCategoryChip`, `ProductSortChip`), so a customer who learns the controls on one page cannot meet a differently-shaped version on the next.
- **The field filters; it does not navigate.** Typing narrows the grid under it live — nothing to submit, no page left — which is what a shelf of ten or fifty products wants. The app's search *page* is the other kind of thing (whole catalog, suggestions, history, its own back stack) and keeps its own bar.
- **The count follows.** `shelfCountLabel(shown:, total:, qualifier:)` renders `10 pairs · EU 39`, or `3 of 10 pairs · EU 39` while a query or a chip is narrowing the shelf, so the heading can never count products the grid is not showing.
- **Rules live in the provider, not the pages.** `ProductProvider.shelfProducts(shelf, query:, category:, sort:)` filters on the same `matchesSearchQuery` the home search uses and sorts through the same `_applySort` as the catalog (so §5's sale-aware price sort holds here too). `shelfCategories(shelf)` derives the chips **from the shelf itself** — never from `categories`, which is the whole catalog's vocabulary and appends the pseudo-categories — so a chip can never lead to an empty grid, and the chip row is hidden entirely when the shelf holds none.
- **The pages own the state.** Each keeps `_query` / `_category` / `_sort` and its empty state clears them (plus the controller), so a customer is never left staring at a narrowed shelfwondering what narrowed it.

---

## 5. Sorting under active sales

Price sorts are **sale-aware** — `ProductProvider.getFilteredProducts` sorts by `effectivePrice(product)` (via `_extractPrice`), not the raw `price`:

```dart
case SortMode.priceLowToHigh:
  sorted.sort((a, b) => _extractPrice(a).compareTo(_extractPrice(b)));
```

So "Price: Low to High" lists discounted items at their *actual* price. `SortMode.featured` (default) is a no-op that preserves the session's shuffle.

---

## 6. Key files

| File | Role in the sale feature |
|------|--------------------------|
| `lib/utils/sale_price.dart` | **Single source of truth** — `isOnSale`, `effectivePrice`, `salePercent` |
| `lib/screens/customer/customer_home_screen.dart` | "On Sale" section sliver + Best Sellers rail + chip wiring + recently-viewed sale prices |
| `lib/providers/product_provider.dart` | `categories` (the `'On Sale'` and `'Best Sellers'` pseudo-categories), `getFilteredProducts` (sale filter, best-seller filter, effective-price sort), `bestSellerProducts()` / `bestSellers` / `hasBestSellers` |
| `lib/widgets/best_sellers_section.dart` | The Best Sellers home rail (live `units_sold` ranking, shared `HorizontalProductCard`) |
| `lib/widgets/on_sale_card.dart` | The ON SALE poster — a `FitCard` handed `ON` / `SALE`, `UP TO` and the live max discount; the section's heading and its first grid cell |
| `lib/screens/customer/on_sale_listing_screen.dart` | The full sale list the poster opens (reuses `SoleProductCard` + `productGridRatio` and the shared shelf toolbar) |
| `lib/widgets/product_shelf_toolbar.dart` | The search + filter + sort band a shelf page puts under its heading, plus `shelfCountLabel` |
| `lib/widgets/product_sort_chip.dart` / `lib/widgets/underline_category_chip.dart` | The sort control and the underline chips, shared by the shelf pages and the search page |
| `lib/widgets/sole_product_card.dart` | Hanging tag + price-tape overlays, strikethrough/effective price display |
| `lib/widgets/hanging_sale_tag.dart` | The interactive hang tag (swing, flip reveal, semantics, reduced motion) |
| `lib/widgets/sale_price_tape.dart` | Peel-away tape over the sale price (corner-lift peel, blur, shimmer, shared reveal state) |
| `lib/providers/sale_tag_provider.dart` | Per-user/per-product reveal state (optimistic flips, lazy load, `isLoading`) |
| `lib/services/sale_tag_service.dart` | SharedPreferences persistence (local-only, per-user key) |
| `lib/widgets/sale_countdown_overlay.dart` | Shared 1s ticker + `SaleEndWatcher` expiry fallback + the countdown overlay |
| `lib/screens/customer/product_detail_screen.dart` | Detail-page sale pricing (same helpers) |
| `lib/services/product_service.dart` / `supabase_service.dart` | Read/write of `sale_price`, `sale_starts_at`, `sale_ends_at` |
| `lib/screens/seller/add_edit_product_screen.dart`, `manage_products_screen.dart` | Seller sets/ends sales (validates `0 < salePrice < price`) |
| `supabase/migrations/20260804000000_add_product_sale_fields.sql` | Schema (nullable sale columns + index) |
| `test/utils/sale_price_test.dart` | Unit tests for the rule (time-window + price-edge cases) |

---

## 7. Modification checklist (so the next AI doesn't break it)

1. **Never duplicate the sale rule** — any new price display must call `isOnSale`/`effectivePrice`/`salePercent` from `sale_price.dart`.
2. **Don't switch the On Sale section to masonry** and don't give those cards `imageAspectRatio` (see §4.2 gotcha) — the poster is a cell in that same fixed grid, not an overlay on it. The hanging tag is an overlay (`clipBehavior: Clip.none` outer `Stack` in `SoleProductCard`) and must never change that.
3. Keep the section's visibility guard tied to `_searchKeyword.isEmpty` + `selectedCategory` — search/category states must not double-render sale items.
4. The `'On Sale'` chip is computed from `_products.any(isOnSale)` — if you add new sale criteria, update `sale_price.dart` only. The same applies to `'Best Sellers'` (§4.4): its rule lives in `bestSellerProducts()` and the chip/rail both read it — never re-derive "is this a best seller" in a widget.
5. Sorting by price must use `effectivePrice`, or discounted items will sort by their inflated original price. A shelf listing page must **not** grow its own sort: it calls `ProductProvider.shelfProducts(...)`, which routes through the same `_applySort` as the catalog, and it takes its chips from `shelfCategories(shelf)` (the shelf's own vocabulary) rather than from `categories`.
6. **Reveal state is per user+product, not per widget, and is SPLIT in two (Option B).** Always read it through `SaleTagProvider` — the tag uses `isTagRevealed`/`revealTag`, the tape uses `isTapeRevealed`/`revealTape`. Never merge the sets and never make one interaction reveal the other (that was the old shared Option A — it has been deliberately reverted). Each product shows the same face on every screen. To make reveals sync across devices later, swap `SaleTagService` for a Supabase table with a `reveal_type` discriminator (`'tag'` vs `'price'`, PK `(user_id, product_id, reveal_type)`) — the provider API stays the same.
7. **Never change the price block's footprint between states.** The sale-price `Text` sits in a padded box (`hitPadding`) and the SAME box is returned in the covered and revealed states; the tape visual is a `Positioned`/`IgnorePointer` overlay (`clipBehavior: Clip.none`) hugging the text alone — its insets are measured against the price's box, never the target's, so a `targetBelow` line is never covered. Covered and revealed must be pixel-identical in size, and the original/strikethrough line is never covered. The **≥40px tall tap area is the rule** (not the padding that used to provide it): reach it with padding where the slack will not show, or with `targetBelow` where it would — that is what `SoleProductCard` does (`hitPadding: fromLTRB(10, 4, 10, 4)` plus the original price as the second line of the target), because the padding-only version put ~18px of dead air between the rating row and the price. The detail screen still puts its slack above (`fromLTRB(10, 22, 10, 0)`) to preserve its bottom-aligned price row; the strip uses `fromLTRB(10, 20, 10, 9)` for its 11px price. A `targetBelow` also means the target's semantics: the reveal label is its own node (`container: true`, `explicitChildNodes` when there is a line below) so the original price keeps its own announcement while the covered number stays hidden.
8. **Animate only user-triggered reveals.** Reveals that arrive from the async provider load must jump straight to revealed (`provider.isLoading` is true during the load) — otherwise the catalog would replay a wall of flips/peels on every app start.
9. **Grid builders recycle element States across products.** `SliverChildBuilderDelegate`/`itemBuilder` re-use the same `State` for a different `productId` after scrolling. Both `HangingSaleTag` and `SalePriceTape` reset every per-product flag (`_localRevealed`, `_prevRevealed`, `_peelRequested`, …) in `didUpdateWidget` when `productId` changes — if you add new per-product state to either widget, reset it there too, or a guest's reveal will leak onto a different product.
10. **Never build a second "is this sale active" check.** The countdown only renders where `isOnSale(product)` is true; the timer's target is `sale_ends_at` (NULL → no timer). All sale logic still lives in `sale_price.dart`.
11. **Expiry fallback is centralized in `SaleEndWatcher`.** When the countdown hits zero it rebuilds with `now = sale_ends_at + 1s` so the whole card/screen falls back together. Any new surface showing a countdown (or sale prices) must be wrapped in `SaleEndWatcher` with the `now` it provides threaded into `isOnSale`/`effectivePrice`/`salePercent`.
12. **One shared ticker, no per-card timers.** Countdown displays subscribe to `SaleCountdownTicker.instance` (remove in `dispose`) — never spin up their own `Timer.periodic` per card. `SaleEndWatcher`'s one-shot expiry timer is fine (idle between schedule and fire).
13. **Pseudo-categories are a pattern — follow it, don't fork it.** `'On Sale'` and `'Best Sellers'` are derived rules dressed as chips: appended in `categories` only while they can yield something, branched in `getFilteredProducts()`, never a real `category` value in the DB, and backed by exactly one rule function. A future "filter the catalog by rule X" belongs in the same two places (plus a rail if it deserves one), not in a new filtering mechanism.
