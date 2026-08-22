# Search Architecture — Customer Home Tab

## Overview

Search is split across two layers: a **hero entry point** (decorative tap target) and a **full-screen search overlay** (functional filtering). There is no inline search on the home screen — all filtering happens in the overlay.

## Components

```
CustomerHomeScreen
  └─ HomeHero (hero section)
       └─ Icon row → decorative search bar (GestureDetector)
            └─ onSearchTap → pushes HomeSearchScreen

HomeSearchScreen (full-screen overlay)
  ├─ AppBar with auto-focused TextField
  ├─ Category chips (horizontal scroll)
  ├─ Results count + "Clear all"
  └─ MasonryGridView of filtered products
```

## Data flow

```
User taps hero search bar
  → Navigator.push(HomeSearchScreen)
    → TextField auto-focuses (keyboard opens)
    → User types → setState(_keyword)
    → context.watch<ProductProvider>()
    → ProductProvider.getFilteredProducts(_keyword)
      → 1. Category filter (from _selectedCategory)
      → 2. Keyword filter (name substring + tag per-word match)
      → 3. Sort (from _sortMode)
    → MasonryGridView rebuilds with filtered results
    → User taps product → Navigator.push(ProductDetailScreen)
    → User taps back → Navigator.pop (returns to home)
```

## Key behaviors

### Keyword filtering (ProductProvider.getFilteredProducts)

The search is **real-time** — no debounce. Every keystroke triggers a rebuild with filtered results.

Matching rules:
- **Product name**: exact substring match (case-insensitive). Query `"leather"` matches `"Classic Leather Derby"`.
- **Product tags**: per-word match. Query `"handmade leather"` matches any product tagged with `"handmade"` OR `"leather"` (OR logic across words, not AND).
- **Combined**: name match is checked first; if it hits, tags are skipped (short-circuit).

### Category filtering

Category chips in the search overlay call `ProductProvider.selectCategory()`, which is an **app-root singleton** — the same `selectedCategory` state shared with the hero's frosted chips and the home screen's On Sale conditional.

Filtering logic in `getFilteredProducts`:
1. `'On Sale'` pseudo-category → filters by `isOnSale()` rule (sale price active + not expired)
2. `'All'` or `null` → no category filter
3. Any other value → exact match on `product['category']`

**Cross-screen state sharing**: Changing category in the search overlay also changes it on the home screen (and vice versa), because both read/write the same `ProductProvider._selectedCategory`.

### Sort

`ProductProvider._sortMode` is shared across the search overlay and the home screen's sort button. The search overlay does NOT have its own sort control — it inherits whatever sort mode is active on the home screen.

Available modes: `featured` (shuffled), `priceLowToHigh`, `priceHighToLow`, `nameAZ`, `nameZA`.

### Clear all

The "Clear all" button in the search overlay:
1. Clears the TextField (`_controller.clear()`)
2. Resets local keyword state (`_keyword = ''`)
3. Resets global category to `'All'` (`selectCategory('All')`)

This restores the full unfiltered catalog in the overlay. Returning to the home screen also shows the full catalog (since the overlay's keyword was local state, not shared).

## State ownership

| State | Owner | Shared? | Reset on overlay close? |
|-------|-------|---------|------------------------|
| `_keyword` (search text) | HomeSearchScreen (local) | No | Yes (destroyed with widget) |
| `_selectedCategory` | ProductProvider (global) | Yes — hero chips, home On Sale, overlay chips | No (persists) |
| `_sortMode` | ProductProvider (global) | Yes — home sort button | No (persists) |
| `_products` (catalog) | ProductProvider (global) | Yes — all screens | No (persists) |

## File map

| File | Role |
|------|------|
| `lib/screens/customer/widgets/home_hero.dart` | Hero section with decorative search bar (GestureDetector → `onSearchTap` callback) |
| `lib/screens/customer/home_search_screen.dart` | Full-screen search overlay with TextField, category chips, filtered masonry grid |
| `lib/screens/customer/customer_home_screen.dart` | Parent screen — passes `onSearchTap: () => Navigator.push(HomeSearchScreen())` to HomeHero |
| `lib/providers/product_provider.dart` | App-root singleton — owns `products`, `selectedCategory`, `sortMode`, `getFilteredProducts()` |

## Filtering pipeline (inside ProductProvider.getFilteredProducts)

```
输入: _products (全部产品列表), searchKeyword, _selectedCategory, _sortMode
  │
  ├─ 1. Category filter
  │     ├─ 'On Sale' → where(isOnSale)
  │     ├─ 'All' / null → no filter
  │     └─ other → where(category == selectedCategory)
  │
  ├─ 2. Keyword filter (if searchKeyword.isNotEmpty)
  │     ├─ query = keyword.trim().toLowerCase()
  │     ├─ words = query.split(whitespace)
  │     └─ for each product:
  │           ├─ name.contains(query) → include (short-circuit)
  │           └─ tags.any(tag => words.any(w => tag.contains(w))) → include
  │
  └─ 3. Sort
        ├─ featured → no-op (preserve shuffle order)
        ├─ priceLowToHigh → sort by effectivePrice asc
        ├─ priceHighToLow → sort by effectivePrice desc
        ├─ nameAZ → sort by name asc
        └─ nameZA → sort by name desc
```

## Edge cases

- **Empty keyword + no category filter**: Shows all products in shuffled order (featured mode).
- **Empty keyword + category selected**: Shows all products in that category.
- **Keyword + no category**: Searches across all categories.
- **Keyword + category**: Searches within the filtered category.
- **No results**: Shows `search_off` icon + "No shoes match your search."
- **Overlay dismissed without clearing**: Keyword is lost (local state), but category persists globally. Home screen shows the category-filtered catalog.
