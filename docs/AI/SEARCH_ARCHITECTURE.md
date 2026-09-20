# Search Architecture — Customer Home Tab

> **Rewritten 2026-09-18.** This doc used to describe search as an *inline* filter
> of the Home feed. That design had a hole: nothing on Home could clear a query.
> Neither search bar had a clear button, the hero field was read-only, and backing
> out of the search screen silently kept the last term — so a query that matched
> nothing (a real example: **"Formal Shoes"**, which matched no product *name* or
> *tag*) left the customer inside a search they could not leave. Search is now a
> **destination**: it owns its query, and Back always returns to a full feed.

## Overview

Three surfaces, one direction of travel:

```
Home feed (bars are tap-only stand-ins — the feed is NEVER filtered by a query)
  └─ tap search ─▶ Search page (the field you type in + suggestions)
        └─ commit ─▶ Search results page (own field, filters, sort, grid)
              └─ tap a card ─▶ Product detail
```

- **Home bars** (`home_hero.dart`, `home_sticky_search_bar.dart`) are read-only
  `TextField`s that only open the search page. Typing on Home is deliberately
  impossible: nothing typed there would have anywhere to go, and leaving it
  editable is what created the trap.
- **Search page** (`product_search_screen.dart`) — the only place a customer
  types. Empty field shows "Recently Searched" + "Search Discovery"; while
  typing it swaps to a live **suggestion panel**.
- **Results page** (`search_results_screen.dart`) — the query, a category tab
  row (underlined when one is active), a sort chip, the result grid, and a
  **no-match panel** that always carries products.

## Data flow

```
Home bar tapped → ProductSearchScreen
  → user types → onChanged → build reads ProductProvider.suggestionsFor(query)
      → suggestions are derived from the ALREADY-LOADED catalog (no query, no network)
  → commit (submit, search button, or a suggestion row)
      → SearchHistoryService.record(term)
      → push SearchResultsScreen(initialQuery: term)      ← note: PUSH, not pop
          → build reads ProductProvider.searchResults(query, category, sort)
          → empty? → ProductProvider.relatedProducts() → "Popular right now" rail
  → Back → the search page, field still holding the term (refine it)
  → Back → Home, showing the whole catalog
```

## The matching rule (`lib/utils/product_search.dart`)

Pure Dart, no Flutter, unit-tested without a widget harness. A product matches a
query when **any** of these holds:

| Signal | Rule | Why |
|---|---|---|
| Name | contains the whole query | `"formal derby"` → "Formal Derby" |
| Name | contains **any** query word | `"leather derby"` still finds "Formal Leather Derby" |
| **Category** | contains any query word | **`"Formal Shoes"` → the Formal shelf.** A category is the catalog's own word for those products; a search that cannot use it tells the customer their own catalog does not exist |
| Tags | contains any query word | the previous rule, unchanged |

Any single word matching is enough — an **OR**, not an AND. A customer typing
more words is narrowing in their head, not asking for a conjunction, and an
empty page is the worse failure.

**A blank query matches nothing** (not everything): "no query" is not a search.
The results page handles that case with an invitation, not a failure message.

`ProductProvider.getFilteredProducts()` keeps its own keyword path (name +
tags) — it is the *catalog filter*, exercised by the provider tests. The
customer-facing search path is `searchResults()`, so a future edit to one cannot
silently redefine the other. Both share the same sort (`_applySort`).

## Suggestions (`searchSuggestionsFor`)

Candidates are the categories, tags and product names whose text contains any
typed word. Ranking, in order: **word-prefix before mid-word**, then **how many
products the term would return**, then kind (category → tag → product), then
alphabetically. The typed query itself is never a suggestion row — the page
renders "search for what I typed" as its own first row.

## The results page's category chips (`searchCategories`)

The chips are the categories **this query's matches actually fall into** — not
`ProductProvider.categories`. That getter is the whole catalog's vocabulary: it
starts with `'All'` (the page renders its own `All` chip, so reusing the list
printed two of them), it always contains `AppConstants.productCategories`
whether or not anything is in them, and it appends the 'On Sale' / 'Best
Sellers' pseudo-categories. A chip that can only ever lead to "0 results" is
worse than no chip.

Consequently a chip can vanish when a new query no longer matches it, so the
page computes its effective filter each build (`selectedCategory` is the stored
filter *only while it is still one of the chips*) instead of mutating state
during a build.

**The chips carry their state as an underline, not as a box.** The active
category is a 2px rule under the label (the label itself goes to
`AppConstants.primary` at weight 700); the inactive ones are plain muted text —
no fill, no border. This is the hero tabs' convention, and it is deliberate: a
row of bordered chips sitting next to a bordered sort button reads as a toolbar
of six buttons when only one of them is a *state*, and the underline does not
compete with the grid below it. The rule animates from width 0 on select (so it
is unmistakably the indicator moving rather than a second box appearing), and
its width is **measured from the label**, not fixed — which is why `_chip` reads
its style from a `Builder` *inside* the Scaffold: `Text` merges the ambient
`DefaultTextStyle` (Material's `bodyMedium`, `letterSpacing: 0.25`) and a
measurement taken from the body style alone comes out ~2px narrow on a
7-character label. `test/widgets/search_results_screen_test.dart` asserts the
underline's rendered width matches the label's to within 0.5px, so a future
style change cannot silently desync the two.

## The no-match panel (`ProductProvider.relatedProducts`)

`relatedProducts()` **takes no query, on purpose.** A query that matched nothing
is a query whose words appear nowhere in the catalog (name, tag *or* category),
so there is nothing similar to compute from. Rather than invent a similarity, the
panel shows the shop's own picks (units sold → rating → name) — honest, and
incapable of contradicting the "no matches" it sits under. It renders through
`ProductRailSection`, so it is tappable straight through to the product page.

## State ownership

| State | Owner | Shared? | Notes |
|---|---|---|---|
| Query | `SearchResultsScreen` (local) / the search page's field | No | Home has **no** query state at all |
| Category filter on results | `SearchResultsScreen` (local) | No | Deliberately not `ProductProvider.selectedCategory`, or a search would re-filter Home underneath |
| Sort on results | `SearchResultsScreen` (local, default `featured`) | No | Passed into `searchResults()`; `ProductProvider.sortMode` is left alone |
| `selectedCategory` | `ProductProvider` (global) | Yes — hero tabs, On Sale/Best Sellers gating | Home's catalog filter only |
| `sortMode` | `ProductProvider` (global) | Yes — Home's collection card (its back is the sort list) | Unchanged by search |
| `_products` (catalog) | `ProductProvider` (global) | Yes | Both search surfaces read it; neither fetches |

## File map

| File | Role |
|------|------|
| `lib/utils/product_search.dart` | The rule: `searchWords`, `matchesSearchQuery`, `searchSuggestionsFor` (pure) |
| `lib/providers/product_provider.dart` | `searchResults()`, `suggestionsFor()`, `relatedProducts()`, shared `_applySort` |
| `lib/screens/customer/product_search_screen.dart` | The field you type in + the suggestion panel |
| `lib/screens/customer/search_results_screen.dart` | Results, filters, sort, no-match panel |
| `lib/screens/customer/widgets/home_hero.dart` | Hero bar — read-only stand-in that opens search |
| `lib/screens/customer/widgets/home_sticky_search_bar.dart` | Pinned bar — same |
| `lib/widgets/product_sort_sheet.dart` | The one "Sort by" sheet Home and the results page share |
| `lib/services/search_history_service.dart` | On-device recent searches (per user, capped at 8) |

**Deleted:** `lib/screens/customer/widgets/search_history_overlay.dart` — a
floating history dropdown under the Home bars. It could only appear while a
read-only field held focus, so it became unreachable once typing moved into the
search page; its content is the search page's "Recently Searched" section.

## Edge cases

- **Nothing matched** → the no-match panel: title, "Browse All Styles" (pops to
  the feed), and the "Popular right now" rail.
- **Cleared field on results** → the page invites a search and still shows the
  rail; it never says `No matches for ""`.
- **Empty catalog** → `relatedProducts()` is empty, so the panel renders without
  the rail; the page is short but never blank.
- **Back from results** → the search page with the term intact, then Home with
  the full catalog. There is no state to get stuck behind.
- **Long result lists** → the grid is not capped; `searchResults(limit:)` exists
  for callers that need a cap.

## Traps for the next edit

1. **Do not filter the Home feed by a query again.** The feed's narrowings are
   the category chips and its sort. Anything else reintroduces the trap.
2. **Do not give `relatedProducts()` a query parameter** to "improve" it — see
   the section above; there is nothing to be similar to.
3. **Do not make the results page sort through the provider.** It passes `sort:`
   into `searchResults()` so the Home feed's order is untouched.
4. **Do not add a second matching rule.** `matchesSearchQuery` is the rule for
   results; the suggestion panel uses the same function's vocabulary via
   `searchSuggestionsFor`.
5. **Do not build the chip row from `ProductProvider.categories`** — it contains
   `'All'` plus categories with nothing in them. Use `searchCategories(query)`.
