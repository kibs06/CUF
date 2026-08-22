# Search Architecture — Customer Home Tab

## Overview

Search is **inline** on the home screen — the hero search bar is a real, functional `TextField` that filters the product grid in real time as the user types. There is no separate search screen or overlay. Clearing the text field restores the full catalog.

## Components

```
CustomerHomeScreen
  └─ HomeHero (hero section)
       └─ Icon row → real TextField (searchController + searchFocusNode from parent)
            └─ onChanged → setState(_searchKeyword)
                 └─ triggers getFilteredProducts(_searchKeyword) in build()
                      └─ MasonryGridView in the sheet rebuilds with filtered results
```

## Data flow

```
User taps hero search bar → FocusNode focuses (keyboard opens, bar visually changes)
  → User types → onChanged fires → setState(_searchKeyword)
  → build() calls ProductProvider.getFilteredProducts(_searchKeyword)
    → 1. Category filter (from _selectedCategory)
    → 2. Keyword filter (name substring + tag per-word match)
    → 3. Sort (from _sortMode)
  → MasonryGridView rebuilds with filtered results
  → User clears text → _searchKeyword = '' → full catalog restored
```

## Key behaviors

### Keyword filtering (ProductProvider.getFilteredProducts)

The search is **real-time** — no debounce. Every keystroke triggers a rebuild with filtered results.

Matching rules:
- **Product name**: exact substring match (case-insensitive). Query `"leather"` matches `"Classic Leather Derby"`.
- **Product tags**: per-word match. Query `"handmade leather"` matches any product tagged with `"handmade"` OR `"leather"` (OR logic across words, not AND).
- **Combined**: name match is checked first; if it hits, tags are skipped (short-circuit).

### Category filtering

Category tabs in the hero call `ProductProvider.selectCategory()`, which is an **app-root singleton** — the same `selectedCategory` state shared with the On Sale section conditional.

Filtering logic in `getFilteredProducts`:
1. `'On Sale'` pseudo-category → filters by `isOnSale()` rule (sale price active + not expired)
2. `'All'` or `null` → no category filter
3. Any other value → exact match on `product['category']`

**Cross-section state sharing**: Changing category in the hero tabs also affects the On Sale section visibility and the filtered grid, because all read/write the same `ProductProvider._selectedCategory`.

### Sort

`ProductProvider._sortMode` is shared across the home screen's sort button. The search has no separate sort control — it inherits whatever sort mode is active.

Available modes: `featured` (shuffled), `priceLowToHigh`, `priceHighToLow`, `nameAZ`, `nameZA`.

### Clearing search

When the user backspaces the text field to empty:
- `_searchKeyword` becomes `''`
- `getFilteredProducts('')` returns the full category-filtered (or unfiltered) catalog
- On Sale section reappears (if no category filter is active and sale items exist)
- Featured banner reappears (if no category filter is active)

## State ownership

| State | Owner | Shared? | Persists when search cleared? |
|-------|-------|---------|-------------------------------|
| `_keyword` (search text) | CustomerHomeScreen (local) | No | No (local state) |
| `searchController` / `searchFocusNode` | CustomerHomeScreen (local) | No | Yes (text field stays focused) |
| `_selectedCategory` | ProductProvider (global) | Yes — hero tabs, On Sale conditional | Yes |
| `_sortMode` | ProductProvider (global) | Yes — sort button | Yes |
| `_products` (catalog) | ProductProvider (global) | Yes — all screens | Yes |

## File map

| File | Role |
|------|------|
| `lib/screens/customer/widgets/home_hero.dart` | Hero section with real search TextField (controller + focusNode from parent) |
| `lib/screens/customer/customer_home_screen.dart` | Parent screen — owns search state, passes controller/focusNode/onChanged to HomeHero, filters grid |
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
- **No results**: Shows `search_off` icon + "No shoes match your criteria."
- **Search bar focused**: Visual state changes (solid white background, primary border, shadow). Unfocused returns to frosted pill.
- **Category changed while searching**: Grid immediately re-filters with the new category + existing keyword.
