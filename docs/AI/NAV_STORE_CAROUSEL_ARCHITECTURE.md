# Store Tab — Carousel & Focused Info Architecture

> **Scope:** The customer-side **Store** tab (bottom nav index 1) — the "walking through a market" experience. Covers the hero store carousel, focused store info strip, and "Top Picks" product row below it.

---

## Screen Structure

The Store tab lives inside `CustomerShell` (`lib/screens/customer/customer_shell.dart`) as the second tab of four, hosted in a `PageView` where each page is wrapped in `KeepAlivePage` (lazy build on first visit, then kept mounted):

| Index | Tab       | Screen               |
|-------|-----------|----------------------|
| 0     | Home      | `CustomerHomeScreen` |
| 1     | **Store** | `StoreScreen`        |
| 2     | Notifications | `NotificationsScreen` |
| 3     | Profile   | `ProfileScreen`      |

The bottom nav is rendered by `SoleBottomNav` (`lib/widgets/sole_bottom_nav.dart`), and is wrapped together with the tab host in `HideOnScrollBottomBar` (`lib/widgets/hide_on_scroll_bottom_bar.dart`): scrolling a tab downwards collapses the bar out of the layout for a full screen, and the first drag back up returns it. Both the customer and the seller shell use this wrapper; the admin shell still hands its bar to the Scaffold directly. Scrolling the **Store** tab therefore moves the bar like any other.

---

## `StoreScreen`

**File:** `lib/screens/store/store_screen.dart`

Top-level `StatefulWidget`. Loads all stores from `StoreService.instance.fetchAllStores()` on init.

### State
- `_stores: List<Store>` — all active stores fetched from Supabase.
- `_focusedIndex: int` — which carousel page is currently centered.
- `_pageController: PageController` — configured with `viewportFraction: 0.85` so neighboring cards peek at the edges.
- `_isLoading: bool` — shimmer skeleton while stores load.

### Layout (top → bottom)

```
AppBar  "Stores"          + CartIconButton (right)
─────────────────────────────
StoreHeroCarousel          ← Section 1: full-width peek carousel
StoreFocusedInfo           ← Section 2: animated info strip for focused store
CrossStoreProductRow       ← Section 3: "Top Picks from {store}" 2-col grid
─────────────────────────────
Bottom Nav (SoleBottomNav)
```

All wrapped in a `SingleChildScrollView` with a noise texture overlay (`AppConstants.noiseOverlay`).

### Product Counts & Top Picks
A cached per-store index (`_reindexIfNeeded()`) tallies products per `store_id` and sorts top-picks by ID descending. The index is only rebuilt when the `products` list reference changes (checked via `identical()`), avoiding O(n) scans on every store swipe. The "Top Picks" section shows the newest products from the **focused** store only, capped at 12.

The same `storeId → products` map is handed to `StoreHeroCarousel` (`productsByStore`), and each card derives its **sale tag** from it — see §1c. Deriving from that one list is deliberate: the tag and the `👟` count beside it can never describe different shelves.

---

## Section 1 — `StoreHeroCarousel`

**File:** `lib/screens/store/widgets/store_hero_carousel.dart`

A `PageView.builder` with a `viewportFraction`-based peek effect and page indicator dots.

### Props
| Prop              | Type                | Description                              |
|-------------------|---------------------|------------------------------------------|
| `stores`          | `List<Store>`       | All stores to show in the carousel       |
| `pageController`  | `PageController`    | Shared with parent (viewportFraction 0.85)|
| `onStoreChanged`  | `ValueChanged<int>` | Callback when the centered page changes  |
| `currentIndex`    | `int`               | Index of the focused store               |
| `productCounts`   | `Map<String, int>`  | Product count per store ID               |
| `productsByStore` | `Map<String, List<Map<String,dynamic>>>` | Per-store products — feeds each card's sale tag (and its expiry) |
| `onEnterStoreSale`| `ValueChanged<Store>` | Opens a store pre-filtered to its on-sale products (the tag's tap) |

### Behavior
- Fixed height: `SizedBox(height: 280)` containing a `PageView.builder`.
- On page scroll, each card is scaled: `scale = (1 - (distance * 0.05)).clamp(0.95, 1.0)` — so the centered card is 1.0 and neighbors are 0.95.
- `pageSnapping: true` so pages snap to center.
- Below the `PageView`, a `Row` of animated dots — active dot is wider (20px) in `AppConstants.accent`, inactive dots are 6px in semi-transparent gray.

---

## Section 1b — `StoreHeroCard`

**File:** `lib/screens/store/widgets/store_hero_card.dart`

A single carousel card. Each card is a 260px-tall rounded container (`borderRadius: 24`) with a box shadow tinted by the store's brand color.

### Visual Layers (back → front)

1. **Background:** If `store.bannerUrl` exists → `CachedNetworkImage(fit: BoxFit.cover)`. Otherwise → `store.cardGradient` (a `LinearGradient` from the brand color to a darker blend).

2. **Dark overlay:** `LinearGradient` from top (30% black) to bottom (160% black alpha) for text readability.

3. **Stitch texture:** `CustomPaint(painter: const StitchPainter())` — diagonal dashed white lines at ~5% opacity evoking leather stitching. Defined in `lib/screens/store/widgets/stitch_painter.dart`.

4. **Card content** (padded 20px, `Column` with `Spacer`):

   ```
   ┌─────────────────────────────────────┐
   │  [CircleAvatar]        [OPEN chip] │  ← Top row
   │                                     │
   │                                     │
   │  Store Name (26px bold white)       │  ← Bottom-aligned via Spacer
   │  Tagline (14px white 80% opacity)  │
   │  🕘 8:00 AM – 5:00 PM             │
   │                                     │
   │  [⭐ 4.5] [👟 1] [📍 Carcar]     │  ← Stat pills
   └─────────────────────────────────────┘
   ```

### Elements

| Element | Details |
|---------|---------|
| **CircleAvatar** | Radius 28, white background. Shows `store.logoUrl` as image or `store.initials` (first 2 words' first letters). |
| **Open/Closed chip** | Rounded pill (borderRadius 12). Green (`AppConstants.success`) when `store.isOpenNow`, gray otherwise. Text: "OPEN" / "CLOSED" in 9px mono bold white. |
| **Store name** | `headlineStyle(26)`, white, max 2 lines with ellipsis. |
| **Tagline** | `bodyStyle(14)`, white at 80% alpha. Shown only if non-empty. |
| **Hours label** | `bodyStyle(12)`, white at 82% alpha. Prefixed with 🕘. Shown only if `store.hoursLabel != null`. |
| **Stat pills** | Row of rounded-border containers (borderRadius 20, white border at 30% alpha). Each contains an emoji + text in 11px white. Shows: rating (if store has reviews), product count, location (first segment). |
| **Sale tag** | Right of the pills, and only when the store is on sale — see §1c. |

### Scale Animation
Wrapped in `AnimatedScale(scale: scale, duration: 200ms, curve: Curves.easeOut)`.

---

## Section 1c — The sale tag

**Files:** `lib/widgets/store_sale_tag.dart` (the pill), `lib/utils/store_sale.dart` (the rule), `lib/widgets/sale_countdown_overlay.dart` (`StoreSaleEndWatcher`).

A store that has at least one product on sale right now carries a **hang-tag pill** in the stat row. It borrows the product card's `HangingSaleTag` **motif** — cream paper, a cut top-right corner, a punched amber grommet — but not that widget: the product tag is 72×100 and its tap *reveals* a discount, while this is a 68×28 pill whose whole body opens the store's sale items. It is fixed-size (the row is laid out against that box) and its copy scales **down** inside it at large text scales rather than growing out of it.

**The rule is inherited, never re-decided.** "A store is on sale" = `storeSaleFrom(products)` in `lib/utils/store_sale.dart`, which composes the shared `isOnSale` / `maxDiscountPercent` / `earliestSaleEnd` from `sale_price.dart`. No `stores` column, no second query — the catalog is already in memory.

**Two faces.** `UP TO` / `-30%` (the best live discount, floored, the same qualifier and rule the ON SALE home poster uses). A sale too small to floor (`maxDiscountPercent` returns null) falls back to a bare `ON` / `SALE` rather than printing `-0%` or hiding — a store that IS on sale must not look like one that is not.

**Motion.** Only the focused card runs the idle dangle: a `Timer`-scheduled, `TickerMode`-gated, reduced-motion-aware lean that **ends at zero** every beat — the same shape as `SeeMoreCard`'s glide and the Workshop poster's tease, deliberately not the product tag's continuous pendulum.

**Expiry.** Nothing rebuilds the Stores tab when a sale ends, so the card wraps the tag in `StoreSaleEndWatcher`, the store-level sibling of `SaleEndWatcher`: it re-derives `StoreSale` at each end and schedules the **next** one, so a store with several sales at different ends stays on sale when the first expires and falls back on its own when the last one does. An all-open-ended sale schedules nothing (no invented urgency).

**Absent-safe.** No sale → the tag renders nothing *and* contributes no space: the 6px leading gap belongs to the tag, so an absent sale leaves no hole in the row.

**Tap.** The tag is its own target (nested inside the card's own tap, which opens the store): it opens `StoreProfileScreen(storeId, saleOnly: true)`, whose grid is filtered by the same `isOnSale` rule and keeps a visible, clearable **On Sale** chip — a customer is never stuck inside a filtered view.

---

## Section 2 — `StoreFocusedInfo`

**File:** `lib/screens/store/widgets/store_focused_info.dart`

An info strip below the carousel that updates with a fade+slide animation when the focused store changes.

### Layout
```
Store Name          (18px bold, secondary color)
Location  ·  🟢 Open Now   (13px, secondary muted)
Hours: 8:00 AM – 5:00 PM   (12px, secondary muted)
⭐ 4.5  ·  1 products      (13px, primary, semibold)
[  Enter Store →  ]         (full-width button)
```

### Animation
Uses `AnimatedSwitcher` (250ms) with a combined `FadeTransition` + `SlideTransition` (subtle 8% vertical slide). The `child` key is `ValueKey(store.id)` so content swaps smoothly on store change.

### "Enter Store" Button
- Full-width, 48px height, `AppConstants.primary` background with matching box shadow.
- Text: "Enter Store" in 15px bold white.
- Arrow icon (`Icons.arrow_forward_rounded`) with a micro-interaction: shifts 2px right on tap-down, snaps back on tap-up.
- Navigates to `StoreProfileScreen(storeId: store.id)`.

---

## Section 3 — `CrossStoreProductRow`

**File:** `lib/screens/store/widgets/cross_store_product_row.dart`

"Top Picks from {storeName}" — a 2-column product grid.

### Layout
```
│ Top Picks  from Janella     ← Label with primary-colored left bar
┌──────────┐ ┌──────────┐
│ Product  │ │ Product  │     ← 2-col Wrap (not GridView)
│  Card    │ │  Card    │        No shrinkWrap — laid out naturally
└──────────┘ └──────────┘
```

### Behavior
- Uses `LayoutBuilder` to compute `cardWidth = (maxWidth - spacing) / 2` with 14px spacing.
- Renders a `Wrap` widget (not `GridView` or `ListView`) — avoids shrinkWrap overhead.
- Each card is a `SoleProductCard` with an aspect ratio from `productGridRatio(product)`.
- Tapping a card navigates to `ProductDetailScreen`.
- Returns `SizedBox.shrink()` if no products.

---

## `StitchPainter`

**File:** `lib/screens/store/widgets/stitch_painter.dart`

A `CustomPainter` that draws 45° diagonal dashed lines across the canvas. Used as a subtle leather-stitching texture overlay on hero cards.

- Default color: white at 5% opacity (`0x0DFFFFFF`)
- Dash length: 8px, gap: 6px, line spacing: 24px, stroke width: 1px
- `shouldRepaint` always returns `false` (static texture)

---

## `Store` Model

**File:** `lib/models/store.dart`

Maps to the `stores` table in Supabase. Key fields used by the carousel:

| Field          | Type       | Carousel Usage                                      |
|----------------|------------|-----------------------------------------------------|
| `id`           | `String`   | Page keys, product count lookups                    |
| `name`         | `String`   | Card title, focused info title, Top Picks label     |
| `tagline`      | `String?`  | Card subtitle                                       |
| `location`     | `String`   | Card pill (first segment), focused info text        |
| `brandColor`   | `String`   | Card shadow tint, gradient background               |
| `bannerUrl`    | `String?`  | Card background image (fallback: gradient)          |
| `logoUrl`      | `String?`  | CircleAvatar image (fallback: initials)             |
| `rating`       | `double?`  | Card pill, focused info (hidden until first review) |
| `isOpen`       | `bool`     | Open/Closed chip, focused info status               |
| `openTime`     | `String?`  | Hours label on card and focused info                |
| `closeTime`    | `String?`  | Hours label on card and focused info                |
| `manualOverride`| `bool`    | Affects `isOpenNow` computation                     |

### Derived Properties
- `initials` — first letter of first two words, uppercased.
- `cardGradient` — `LinearGradient` from brand color → darker blend (55% toward dark brown).
- `isOpenNow` — computed from manual override, schedule times, or raw `isOpen` flag.
- `hoursLabel` — formatted "9:00 AM – 5:00 PM" string, or null.

---

## Data Flow

```
StoreService.fetchAllStores()
    ↓
StoreScreen._stores
    ↓
┌──────────────────────────────────────────┐
│  StoreHeroCarousel(stores, currentIndex) │
│       ↓                                  │
│  StoreHeroCard(store, scale)             │  ← per page
│       ↓                                  │
│  [dots indicator]                        │
├──────────────────────────────────────────┤
│  StoreFocusedInfo(store, productCount)   │  ← updates on page change
├──────────────────────────────────────────┤
│  CrossStoreProductRow(topPicks)          │  ← filtered by focused store
└──────────────────────────────────────────┘
```

When the user swipes the carousel, `_onStoreChanged(index)` updates `_focusedIndex`, which triggers a rebuild. `StoreFocusedInfo` uses `AnimatedSwitcher` with `ValueKey(store.id)` to animate the content swap. `CrossStoreProductRow` re-filters products for the newly focused store.

---

## Skeleton Loading

`_StoreScreenSkeleton` mirrors the final layout with `ShimmerGroup`:
- 260px skeleton box for the carousel card (borderRadius 24)
- Two skeleton text lines for the focused info
- A section header skeleton
- A horizontal `ListView` of 3 `_CrossStoreCardSkeleton` widgets (150×110 image + text skeletons)
