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
        ├─ "On Sale / HOT DEALS" section sliver → saleProducts list
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
- **Graceful fallback:** if the sale expires mid-session while `'On Sale'` is selected, `saleFilterActive` flips false and the grid falls back to the full list — never a confusing empty state. (Note: the chip itself stays in the row until the next reload, since `categories` is recomputed from `_products`.)

### 4.2 Dedicated "On Sale / HOT DEALS" section (home screen sliver)

`customer_home_screen.dart` computes `saleProducts = productProvider.products.where(isOnSale).toList()` in `build()` and renders a **section** with a `_PriceTagBadge(label: 'HOT DEALS')` header and its own grid — but **only in the default browse state**:

```dart
if (_searchKeyword.isEmpty &&
    saleProducts.isNotEmpty &&
    (productProvider.selectedCategory == null ||
        productProvider.selectedCategory == 'All')) ...
```

When the user is searching or has a category chip (incl. `'On Sale'`) active, the section is hidden — the main grid below already shows the relevant items, so it would duplicate.

**⚠️ Important gotcha — this section is a plain `SliverGrid`, NOT masonry.** Two `SliverMasonryGrid`s in one `CustomScrollView` trigger a scroll-offset-correction loop in `flutter_staggered_grid_view` 0.7.0 that yanks the viewport back and makes the bottom of the catalog unreachable. So:
- The section uses `SliverGridDelegateWithFixedCrossAxisCount` (2 columns, `childAspectRatio: 0.58` ≈ the masonry cards' average height).
- Cards here are rendered **without `imageAspectRatio`** → `SoleProductCard` uses `Expanded` image fill and adapts to any cell height without overflow.
- The main catalog below keeps `SliverMasonryGrid.count` + deterministic `imageAspectRatio` per product id.

**If you change this section: do not switch it to masonry, and do not add `imageAspectRatio` to these cards.**

### 4.3 Per-card sale rendering — `lib/widgets/sole_product_card.dart`

Each card calls the shared helpers once:

```dart
final bool onSale = isOnSale(product);
final double displayPrice = effectivePrice(product);
final int? salePct = salePercent(product);
```

- **Hanging sale tag (top-right corner):** instead of a flat red pill, a physical-looking **hang tag** (`lib/widgets/hanging_sale_tag.dart`) is clipped to the card's top-right corner as a pure `Positioned` overlay — it never affects masonry sizing or the HOT DEALS grid contract. The tag shows a "?" until the user taps it, then flips to the live discount (`-23%`), with a pendulum idle swing, flip+bounce+sparkle reveal, haptic, and reduced-motion support.
- **Price block:** when on sale → two stacked lines: **sale price** (`₱{displayPrice}` in primary, bold) + **original price** with `TextDecoration.lineThrough` (muted). Otherwise → single price. The original/strikethrough line is **always visible**; the *sale-price* line is hidden behind a peel-away strip of tape (`lib/widgets/sale_price_tape.dart`) until the user taps it. The sale-price `Text` sits inside a box padded by `hitPadding` (default `fromLTRB(10, 18, 10, 8)`) — that padding is the **≥40px tap target** (dead air above the price; per-site `hitPadding` tunes where the slack goes). The SAME padded box is returned in the revealed state, so the footprint is pixel-identical and nothing reflows. The tape **visual** is a separate `IgnorePointer` overlay that hugs the text (~8px overhang above, ~4px below) and never reaches the strikethrough line.
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
| `lib/screens/customer/customer_home_screen.dart` | "On Sale" section sliver + chip wiring + recently-viewed sale prices |
| `lib/providers/product_provider.dart` | `categories` (`'On Sale'` pseudo-category), `getFilteredProducts` (sale filter + effective-price sort) |
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
2. **Don't switch the HOT DEALS section to masonry** and don't give those cards `imageAspectRatio` (see §4.2 gotcha). The hanging tag is an overlay (`clipBehavior: Clip.none` outer `Stack` in `SoleProductCard`) and must never change that.
3. Keep the section's visibility guard tied to `_searchKeyword.isEmpty` + `selectedCategory` — search/category states must not double-render sale items.
4. The `'On Sale'` chip is computed from `_products.any(isOnSale)` — if you add new sale criteria, update `sale_price.dart` only.
5. Sorting by price must use `effectivePrice`, or discounted items will sort by their inflated original price.
6. **Reveal state is per user+product, not per widget, and is SPLIT in two (Option B).** Always read it through `SaleTagProvider` — the tag uses `isTagRevealed`/`revealTag`, the tape uses `isTapeRevealed`/`revealTape`. Never merge the sets and never make one interaction reveal the other (that was the old shared Option A — it has been deliberately reverted). Each product shows the same face on every screen. To make reveals sync across devices later, swap `SaleTagService` for a Supabase table with a `reveal_type` discriminator (`'tag'` vs `'price'`, PK `(user_id, product_id, reveal_type)`) — the provider API stays the same.
7. **Never change the price block's footprint between states.** The sale-price `Text` sits in a padded box (`hitPadding` — the ≥40px tap target) and the SAME box is returned in the covered and revealed states; the tape visual is a `Positioned`/`IgnorePointer` overlay (`clipBehavior: Clip.none`) hugging the text. Covered and revealed must be pixel-identical in size, and the original/strikethrough line is never covered. Don't shrink `hitPadding` below ~40px total height — the detail screen puts the slack above (`fromLTRB(10, 22, 10, 0)`) to preserve its bottom-aligned price row; the strip uses `fromLTRB(10, 20, 10, 9)` for its 11px price.
8. **Animate only user-triggered reveals.** Reveals that arrive from the async provider load must jump straight to revealed (`provider.isLoading` is true during the load) — otherwise the catalog would replay a wall of flips/peels on every app start.
9. **Grid builders recycle element States across products.** `SliverChildBuilderDelegate`/`itemBuilder` re-use the same `State` for a different `productId` after scrolling. Both `HangingSaleTag` and `SalePriceTape` reset every per-product flag (`_localRevealed`, `_prevRevealed`, `_peelRequested`, …) in `didUpdateWidget` when `productId` changes — if you add new per-product state to either widget, reset it there too, or a guest's reveal will leak onto a different product.
10. **Never build a second "is this sale active" check.** The countdown only renders where `isOnSale(product)` is true; the timer's target is `sale_ends_at` (NULL → no timer). All sale logic still lives in `sale_price.dart`.
11. **Expiry fallback is centralized in `SaleEndWatcher`.** When the countdown hits zero it rebuilds with `now = sale_ends_at + 1s` so the whole card/screen falls back together. Any new surface showing a countdown (or sale prices) must be wrapped in `SaleEndWatcher` with the `now` it provides threaded into `isOnSale`/`effectivePrice`/`salePercent`.
12. **One shared ticker, no per-card timers.** Countdown displays subscribe to `SaleCountdownTicker.instance` (remove in `dispose`) — never spin up their own `Timer.periodic` per card. `SaleEndWatcher`'s one-shot expiry timer is fine (idle between schedule and fire).
