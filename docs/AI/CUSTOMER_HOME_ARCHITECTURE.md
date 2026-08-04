# Customer Home Screen — Architecture Reference

**Date:** August 4, 2026
**File:** `lib/screens/customer/customer_home_screen.dart`
**Purpose:** Enough context for another AI (or developer) to understand and safely modify the customer home screen without re-reading the whole file.

---

## 1. What this screen is

`CustomerHomeScreen` is the **customer's landing tab** in the app shell. It is a scrollable catalog page that:

1. Greets the logged-in customer by first name.
2. Provides a **search bar** that filters the product grid live.
3. Shows **category filter chips** (All / Casual / Sandals / …).
4. Shows a horizontal **Recently Viewed** strip (from `SharedPreferences`).
5. Shows an auto-rotating **featured banner** (`PageView`, 4s interval, mock data).
6. Shows a **masonry product grid** ("Artisan Catalog" / "Search Results") with a **sort** control.
7. Hosts a floating **message button** with an unread badge, and wires **push-notification deep links**.

---

## 2. Data flow — who feeds the screen

```
Supabase (products table)
        │  RLS-scoped to active products
        ▼
SupabaseService.instance  (lib/services/supabase_service.dart)
        │
        ▼
ProductProvider  (ChangeNotifier, lib/providers/product_provider.dart)
        │  exposes: products, isLoading, categories, selectedCategory,
        │           sortMode, getFilteredProducts(keyword), selectCategory(),
        │           setSortMode(), loadProducts()
        │
        ▼
CustomerHomeScreen  (context.watch<ProductProvider> / context.read<...>)
```

- **Reads state** via `context.watch<ProductProvider>()` in `build()` — the grid re-renders whenever the provider notifies.
- **Mutates state** via `context.read<ProductProvider>(...)` in event handlers (`onSelected`, `onTap`).
- **Other providers touched:** `AuthProvider` (greeting name), `MessageProvider` (inbox badge + realtime subscription).

---

## 3. Provider API used (from `lib/providers/product_provider.dart`)

| Member | Type | Purpose |
|--------|------|---------|
| `products` | `List<Map<String, dynamic>>` | Raw product rows from Supabase |
| `isLoading` | `bool` | True while fetching |
| `categories` | `List<String>` | `{'All', ...}` derived from product rows |
| `selectedCategory` | `String?` | Current category filter (`'All'` default) |
| `sortMode` | `SortMode` | Current sort (default `newest`) |
| `getFilteredProducts(keyword)` | `List<...>` | Applies category filter → search keyword → sort |
| `selectCategory(cat)` | void | Sets filter + notifies |
| `setSortMode(mode)` | void | Sets sort + notifies |
| `loadProducts()` | `Future<void>` | Refetches from Supabase |

`SortMode` enum: `newest`, `priceLowToHigh`, `priceHighToLow`, `nameAZ`, `nameZA`. Label helper: `sortModeLabel(mode)`.

**Important:** `getFilteredProducts` does the filtering/sorting in memory — the screen does **not** re-query Supabase per keystroke or per chip tap.

---

## 4. Build structure (top → bottom)

```
Scaffold
├─ AppBar — title "CUFMAI", actions: [CartIconButton]
└─ body: Stack
   ├─ noiseOverlay (decorative texture, IgnorePointer)
   ├─ SafeArea → RefreshIndicator (pull-to-refresh → loadProducts())
   │   └─ CustomScrollView (AlwaysScrollableScrollPhysics)
   │       ├─ [0] Greeting + Search bar            (SliverToBoxAdapter)
   │       ├─ [1] Category chips                   (SliverToBoxAdapter, horizontal ChoiceChips)
   │       ├─ [2] Recently Viewed strip            (if no search + items exist)
   │       │      — "Products you view will show up here" empty hint otherwise
   │       ├─ [3] Featured banner PageView + dots  (if search empty)
   │       ├─ [4] "Artisan Catalog" header + Sort button
   │       ├─ [5] Catalog grid                     (3 states — see below)
   │       └─ [6] bottom spacing (SizedBox 80)
   └─ FloatingMessageButton (unread badge, home tab only)
```

### Catalog grid states (`[5]`)
- `productProvider.isLoading` → spinner, **or** `NoInternetView` with retry when offline (`ConnectivityService`).
- `filteredProducts.isEmpty` → "No shoes match your criteria."
- else → `SliverPadding(horizontal: 20)` wrapping **`SliverMasonryGrid.count`**:
  - `crossAxisCount: 2`, `crossAxisSpacing: 16`, `mainAxisSpacing: 16`
  - each item = `SoleProductCard(product, imageAspectRatio: _imageAspectRatioFor(prod), onTap → ProductDetailScreen, onTryOnTap → ARVirtualFitScreen)`

---

## 5. Masonry grid — the two-piece contract

The staggered layout works because **both** halves agree:

1. **Grid = `SliverMasonryGrid.count`** (from `flutter_staggered_grid_view`) — packs columns by natural item height.
2. **Card = `SoleProductCard` with `imageAspectRatio` non-null** (`lib/widgets/sole_product_card.dart`) — becomes **self-sizing**:
   - `imageAspectRatio != null` → `AspectRatio` image + `MainAxisSize.min` column.
   - `imageAspectRatio == null` → `Expanded` image (fills parent height; for uniform grids).

`_imageAspectRatioFor(product)` picks a deterministic ratio from `[1.0, 0.78, 1.22, 0.95]` **keyed off the product id hash**, so card heights are stable across filtering/re-sorting (index-based assignment would shift heights).

> ⚠️ **Gotcha:** never put these self-sizing cards into a fixed `SliverGrid`/`GridView` (`childAspectRatio`) — short images leave gaps, tall ones overflow. This bug was fixed in the store screens by converting them to `SliverMasonryGrid`/`MasonryGridView` too.

See `docs/AI/HOME_MASONRY_GRID_WIDGETS.md` for the exact widget code.

---

## 6. Local state in the State class

| Field | Purpose |
|-------|---------|
| `_searchController` | Search `TextField` controller |
| `_bannerController` / `_bannerIndex` / `_bannerTimer` | Featured banner auto-rotate (4s) |
| `_searchKeyword` | Live search query (triggers `setState`) |
| `_connectivitySub` / `_wasOffline` | Auto-refresh products when connectivity returns |
| `_recentlyViewed` | Items from `RecentlyViewedService` (SharedPreferences, capped) |
| `_featuredArrivals` | **Mock** banner data (3 hardcoded Unsplash items) |

---

## 7. Lifecycle & side effects

`initState()`:
- Loads recently viewed (async).
- Post-frame: `ProductProvider.loadProducts()`, `_loadConversations()`, `_initPushNotifications()`.
- Subscribes to `ConnectivityService.isOnlineStream`; on restore-from-offline, reloads products.
- Starts the 4s banner timer.

`dispose()`: cancels the connectivity sub, disposes controllers, cancels the timer.

**Side-effect services used:**
- `ConnectivityService.instance.isOnline / isOnlineStream`
- `MessageProvider.subscribeToInbox(customerId)` + `loadConversationsForCustomer(customerId)`
- `PushNotificationService.instance.onNavigateToChat / onNavigateToScreen` — set here so taps on push notifications navigate to `ChatView`, `OrderTrackingScreen`, or `MyReportsScreen`.

---

## 8. Navigation targets

| Action | Route |
|--------|-------|
| Tap product card | `ProductDetailScreen(product)` |
| Tap "Try On" badge | `ARVirtualFitScreen(preselectedProduct)` |
| Tap recently-viewed item | `ProductDetailScreen(fullProduct)` (resolved from provider list) |
| Push → chat | `ChatView(conversationId, viewerRole: 'customer', otherPartyName)` |
| Push → order tracking | `OrderTrackingScreen(order)` (fetches order by id first) |
| Push → reports | `MyReportsScreen()` |

---

## 9. Styling conventions

- Colors/typography from `AppConstants` (`primary`, `secondary`, `accent`, `surfaceLight`, `borderGray`, `headlineStyle`, `bodyStyle`, `monoStyle`).
- Cards: `SoleProductCard`; containers use `AppConstants.cardRadius` + `warmShadow`.
- `noiseOverlay(opacity: 0.03)` is the standard background texture.
- Category chips: `ChoiceChip` with `showCheckmark: false` (highlight-only selection), selected = primary fill + white text.
- Search bar: white pill (`radius 30`), primary focus border.

---

## 10. Common modification checklist

When changing this screen, keep in mind:
1. **Search + category filtering happens in the provider** (`getFilteredProducts`) — if you add a new filter, extend the provider, not the widget.
2. **Don't mix masonry cards with fixed grids** — keep `SliverMasonryGrid.count` + `imageAspectRatio` (or remove the ratio and use a uniform grid).
3. **`_featuredArrivals` is mock data** — the banner is decorative; wire it to a real endpoint if it needs to become dynamic.
4. **The greeting uses `auth.displayName`** — guard against empty/null if you touch it.
5. Chips/banners conditionally render on `_searchKeyword.isEmpty` — keep that coupling consistent.

---

## Key files

| File | Role |
|------|------|
| `lib/screens/customer/customer_home_screen.dart` | This screen |
| `lib/providers/product_provider.dart` | Products, categories, sort, filtered list |
| `lib/widgets/sole_product_card.dart` | Masonry-capable product card |
| `lib/utils/recently_viewed.dart` | SharedPreferences-backed recently viewed |
| `lib/widgets/floating_message_button.dart` | Floating chat button + badge |
| `lib/widgets/cart_icon_button.dart` | Cart shortcut in AppBar |
| `lib/services/connectivity_service.dart` | Offline detection |
| `lib/services/push_notification_service.dart` | Deep-link handlers |
| `lib/widgets/chat/chat_view.dart` | Chat destination |
