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

- **Image overlay (top-left):** red pill badge `SALE -30%` (or just `SALE` if percent is null), with `local_offer` icon. It is a `Positioned` overlay, so it never affects masonry sizing.
- **Price block:** when on sale → two stacked lines: sale price (`₱{displayPrice}` in primary, bold) + original price with `TextDecoration.lineThrough` (muted). Otherwise → single price.
- Top-right "Try On" AR badge is unrelated to sales (accent color).

The same pattern (strikethrough original + effective price) is used in the **Recently Viewed strip** (`isOnSale(fullProduct)` on the resolved live product) and on `product_detail_screen.dart`.

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
| `lib/widgets/sole_product_card.dart` | Sale badge + strikethrough/effective price display |
| `lib/screens/customer/product_detail_screen.dart` | Detail-page sale pricing (same helpers) |
| `lib/services/product_service.dart` / `supabase_service.dart` | Read/write of `sale_price`, `sale_starts_at`, `sale_ends_at` |
| `lib/screens/seller/add_edit_product_screen.dart`, `manage_products_screen.dart` | Seller sets/ends sales (validates `0 < salePrice < price`) |
| `supabase/migrations/20260804000000_add_product_sale_fields.sql` | Schema (nullable sale columns + index) |
| `test/utils/sale_price_test.dart` | Unit tests for the rule (time-window + price-edge cases) |

---

## 7. Modification checklist (so the next AI doesn't break it)

1. **Never duplicate the sale rule** — any new price display must call `isOnSale`/`effectivePrice`/`salePercent` from `sale_price.dart`.
2. **Don't switch the HOT DEALS section to masonry** and don't give those cards `imageAspectRatio` (see §4.2 gotcha).
3. Keep the section's visibility guard tied to `_searchKeyword.isEmpty` + `selectedCategory` — search/category states must not double-render sale items.
4. The `'On Sale'` chip is computed from `_products.any(isOnSale)` — if you add new sale criteria, update `sale_price.dart` only.
5. Sorting by price must use `effectivePrice`, or discounted items will sort by their inflated original price.
