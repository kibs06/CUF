# Customer Home — Architecture Overview

## Routing flow

```
main.dart
  → AuthGate (StreamBuilder<AuthState> on Supabase auth)
    → fetches profile from Supabase (with 12s timeout)
    → _routeByRole(profile):
        role == 'admin'        → AdminShell
        role == 'seller'       → SellerShell (+ one-time celebration screen)
        seller_status == 'pending' → PendingApprovalScreen
        default                → CustomerShell  ←── this doc
```

AuthGate also handles suspended accounts, onboarding vs. login routing, and profile error/retry screens.

## CustomerShell — tab host

**File:** `lib/screens/customer/customer_shell.dart`

Hosts its 4 tabs in a `PageView` where **every page is wrapped in `KeepAlivePage`** (`lib/widgets/keep_alive_page.dart`) with a `SoleBottomNav` bottom bar:

- Pages are built **lazily** on first visit, then kept mounted — so state survives tab switches and `initState` runs once per session.
- A `PageView` alone would **dispose** a page the moment it scrolls out of view (its viewport uses `cacheExtent: 0`), which made every tab tap rebuild the screen *and* re-fire its data fetches. `KeepAlivePage` is what prevents that; do not remove it.
- It is deliberately **not** an `IndexedStack`, which would build all four pages — and run all four screens' fetches — on the first frame.
- Because a kept-alive page is not rebuilt on a switch, the shell publishes the visible tab through **`ActiveTab`** (`lib/widgets/active_tab.dart`); a screen that must refresh on re-entry listens there (e.g. `ProfileScreen`, which takes a `tabIndex`).

| Index | Label | Screen | Notes |
|-------|-------|--------|-------|
| 0 | Home | `CustomerHomeScreen` | Browse + search + sale items |
| 1 | Store | `StoreScreen` | Multi-store carousel discovery |
| 2 | Notifications | `NotificationsScreen` | Push + in-app notifications |
| 3 | Profile | `ProfileScreen` | Shared across customer/seller roles |

The bottom nav reads `NotificationProvider.totalUnread` via `Consumer` for the bell badge.

## CustomerHomeScreen — the main browse tab

**File:** `lib/screens/customer/customer_home_screen.dart`

A `CustomScrollView` with slivers, wrapped in `RefreshIndicator`. No AppBar — the hero bleeds behind the status bar for a full-bleed effect.

### Layout (top to bottom)

1. **HomeHero** — `SliverToBoxAdapter` (344px). Full-bleed hero with gradient background, containing:
   - Icon row: real search `TextField` + cart icon with badge
   - Category text tabs with underline indicator, **plus the audience chips** (Men's / Women's / Kids' / Unisex) — see `HomeCategoryRow` below. Order is `All` → audiences → categories → pseudo-categories
   - "NEW ARRIVALS / CRAFTED FOR FALL" headline + floating product cards + "SHOP NOW" CTA + page dots
2. **Sheet** — `SliverToBoxAdapter` with rounded top corners (`ClipRRect` `borderRadius: 22`), containing:
   - Foot profile banner (conditional — only for incomplete profiles)
   - Based on your size (conditional — see below — a `FitCard` size poster as the first cell of The Workshop Collection's 2-column masonry grid, not a rail)
   - Men's / Women's / Kids' rails (conditional — see below; gated by `AppConstants.productAudienceEnabled`, **now `true`**, and each hides itself when the catalog holds nothing for that audience — which is every audience today: P4 measured all 15 live products as unset, so the rails render nothing until a seller answers "Who is it for?" on a product)
   - On Sale section (conditional — only when no search + no category filter + sale items exist)
   - Best Sellers rail (**currently gated off** by `kBestSellersRailEnabled = false` in `customer_home_screen.dart`; the widget and its data are kept, so re-enabling is a one-const flip. Also conditional — same gate as On Sale; hidden when nothing has sold). See `docs/AI/HOME_ON_SALE_ARCHITECTURE.md` §4.4
   - The Workshop Collection card (the heading; tapping it flips it over onto the sort list)
   - Product grid (`MasonryGridView.count`, 2-col)
   - Catalog end-cap (`CatalogEndCap`, conditional — see below)
   - Bottom spacing for nav bar

### Data flow

- On `initState` (post-frame): calls `ProductProvider.loadProducts(hideOutOfStock: true)` to fetch the full catalog from Supabase, then shuffles it.
- On pull-to-refresh: re-calls `loadProducts(hideOutOfStock: true)`.
- On connectivity restore (was offline → now online): auto-refreshes products.
- On `_loadConversations()`: loads chat conversations for the floating message badge + subscribes to realtime inbox.
- Push notification deep-link handlers: navigates to `ChatView`, `OrderTrackingScreen`, or `MyReportsScreen`.
- `loadProducts()` also fetches the `units_sold` aggregation in parallel (`SupabaseService.fetchUnitsSold()`) and stamps `units_sold` onto each product — that single value powers the **Best Selling** sort, the **Best Sellers** filter chip and the Best Sellers rail. No second query exists for any of them.
- Search: **not on this screen.** The hero and pinned bars are read-only stand-ins that open `ProductSearchScreen` (suggestions, recent + trending terms), which pushes `SearchResultsScreen`. The feed is never narrowed by a query — see `docs/AI/SEARCH_ARCHITECTURE.md` for why, and for what it replaced.

### Key providers consumed

- `ProductProvider` — `context.watch` for: `products`, `categories`, `selectedCategory`, `sortMode`, `isLoading`, `bestSellers`, `getFilteredProducts()`, `selectCategory()`, `setSortMode()`.
- `CartProvider` — `context.select` for `itemCount` (cart badge on hero icon).
- `MessageProvider` — `context.read` for conversation loading (no watch).

### Based on your size grid

`lib/widgets/in_your_size_section.dart` — the first surface where the saved foot
profile changes what the customer is *shown while shopping*. Products that stock
their size right now, most-sold first, headed by the size the app believes —
rendered **in The Workshop Collection's own 2-column masonry grid**, not as a
horizontal strip. The section is a shelf of the feed the customer already reads,
instead of a carousel they have to swipe; the body is `ProductGridSection`
(`lib/widgets/product_grid_section.dart`), and it takes its card heights from the
catalog's `productGridRatio` rule so the same product is the same card height in
both grids.

**The heading is a poster tile, not a line of text.** A `FitCard`
(`lib/widgets/fit_card.dart` — the "Fit Card" pattern: the copy is the whole
design, every line scaled to the full inner width — the words **and** the size
value, stacked on one leading of `0.86em` — with the `EU` as a caption sized as
a fraction of the card, and the value pinned to the card's bottom edge)
takes the grid's **first cell**, top-left, at the reference
505×800 proportion — the same footprint as a product card. It reads "Based / on
your / size" over `EU` and the customer's own number, so the section's name is as
loud as the products it introduces and the size it was built on is the card's
hero value rather than 12px muted meta. The tile has no destination yet, so it
does not claim to be tappable (`onTap` null → no button semantics, no ripple).
Its colours are the app's roles, not the mockup's warm hexes: fill
`surfaceSubtle`, edge `hairline`, ink `secondary`, accent `AppPalette.primaryInk`,
radius `productCardRadius` (the product family's corner, so the poster and the
tiles beside it are one design) — all brightness-aware, which is what keeps it
correct on dark. `ProductGridSection` takes either a `title` or a `tile` (assertedmutually exclusive), so a later category tile has one place to plug into.

**The rule lives elsewhere, on purpose.** `lib/utils/size_match.dart` owns the
match (pure Dart, unit-tested without a widget harness): `stocksMySize()` = an
exact EU size with stock behind it, read from the authoritative `inventory`
relation — the same source as the buy button, so the rail can never list
something unpurchasable. Other systems are converted (US 9 → EU 42); a system
the app owns no chart for (`'JP 25'`) or a bare value outside the app's own
22–48 bands is **skipped, never guessed at**. A sold-out exact size is not
suggested; a ±½ *near* size is never offered as the customer's size.
`ProductProvider.productsInSize(euSize)` applies it and ranks the result
(units sold → rating → name, so the per-load shuffle cannot reorder it), and
returns the **whole** shelf — the preview length is the section's call, not the
provider's.

**Where the size comes from** — `shoppingEuSizeFrom(profile, measurement:)`: the
profile snapshot first (written by both the scan results screens and the manual
picker, so it holds the most recent size given), then a scan already in memory.
Deliberately **no fetch** — and the rail never triggers a measurement load, it
only reads one that is already there.

**Absent-safe**, the same rule the plan sets for every size surface: no size on
file → nothing; no product stocks it → nothing; a product with no size data →
not suggested; kill switch `AppConstants.sizeAwareShoppingEnabled` off →
nothing. The widget carries its own trailing spacing, so a hidden section leaves
no gap behind it.

**The feed previews ten of them, then hands over.** `kHomePreviewCount` = 10
(the tile is a cell too, so 1 + 10 + 1 = 12 cells, six clean rows), and when the
shelf holds more than that the preview is still what a customer reads, and a
`SeeMoreCard` — the same `FitCard` poster, saying `See` / `more` over a painted
arrow — always closes the grid in its bottom-RIGHT corner, whether anything was
cut or not: it is the shelf's door, not a "there is more" promise, and on a
short catalog it is the only way in. Neither it nor the product beside it is a
**masonry cell** — the flow packs cells into whichever column is shorter, which
left the closing row ragged no matter which side the card sat on — so the LAST
product comes out of the flow to join it and the section closes on one fixed
row: product left, card right, one cell wide each, one gutter under the packed
products (`ProductGridSection.trailing`). The flow above keeps the masonry
look; the ending is the one row this design wants deterministic. Tapping it pushes `SizeListingScreen`
(`lib/screens/customer/size_listing_screen.dart`), the same shelf uncapped in
the same order with the same `SoleProductCard`, headed by the size it was built
on. The card shares the section's absence rules and nothing else: empty catalog,
no size on file, kill switch off → no section, so no door either.

**Browse gate** (caller-side, like On Sale / Best Sellers): rendered only when
`_searchKeyword.isEmpty` and `selectedCategory` is `null`/`'All'` — a personal
shelf above a search result or a category filter would read as a second,
unrelated feed.

**Two grids, one scroll view.** The feed now holds this grid *and* the catalog's
`MasonryGridView.count`. A note in `customer_home_screen.dart` used to warn that
two masonry grids in one `CustomScrollView` trigger a scroll-offset-correction
loop; it was never reproduced with these box-level grids, and
`test/widgets/nested_masonry_scroll_test.dart` pins the behaviour that matters
(the feed still reaches its last card). The On Sale section stays a plain
`GridView` on its own merits — its cards are uniform by design, which is what
`childAspectRatio: 0.58` is tuned for.

### Audience rails — Men's / Women's / Kids'

`lib/widgets/audience_section.dart` — one rail per rail-eligible audience, in the
frame order fixed by `productRailAudiences` (`['men', 'women', 'kids']`), sitting
between the size rail and On Sale. The home screen **iterates that list** rather
than listing three widgets, so the order and the `unisex` exclusion are decided
by one constant instead of by call-site discipline.

**Gated — and the gate is now ON.** `AppConstants.productAudienceEnabled` is
`true` (flipped at P5 of `docs/AI/PRODUCT_AUDIENCE_PLAN.md`), and the widget
checks it *before* touching the provider — with the switch off it asks for no
list at all. Flipping it back to `false` is the whole rollback, so the flag and
its code paths must stay.

**Turning it on changed nothing on screen, and that is the point.** Every
surface here is data-derived: all 15 products in the live catalog still have
`audience = null` (measured at P4 of the plan), so each rail hides itself and
the audience chips render nothing. The rails stay empty until products are
tagged — the one honest source being a seller (or an admin), never a guess.

**Stated, never inferred.** `ProductProvider.productsForAudience(audience)` keeps
products whose `audience` equals the value exactly and ranks them with the same
`_compareSuggestions` the size rail uses (units sold → rating → name), capped at
`kAudienceRailLimit`. `null` and `'unisex'` are excluded **hard** — an unset
product stays in the catalog grid, search and every category and is only absent
from these three rails, while a `unisex` product in all three would put one card
three times down the feed. An unrecognised argument returns EMPTY rather than
defaulting to a rail.

**Header.** The title is `productAudienceLabel(audience)`, not a string passed by
this screen — `"Men's"` / `"Women's"` / `"Kids'"` are spelled in exactly one file
(`lib/utils/product_audience.dart`), and a rail can never be labelled with an
audience it does not query.

**Shared rail body.** The three audience rails render through
`lib/widgets/product_rail_section.dart` (header row + `HorizontalProductCard`
strip + trailing gap), and share `lib/widgets/product_section_header.dart` (title
+ optional muted `meta` line) with "Based on your size"'s grid. It does **not** hide
itself: hiding
belongs to the section widget, which is the only thing that knows whether
"nothing to show" means "not applicable" (no size on file, no matching audience)
or "empty catalog".

**Absent-safe, and self-spacing.** Same caller-side browse gate as every other
conditional rail. When a section renders nothing it renders *nothing* — no
header, no strip, no residual gap — which is the normal state until P4's
backfill, so "invisible" has to be the default rather than something this screen
arranges.

### Catalog end-cap (the feed's finish line)

`lib/widgets/catalog_end_cap.dart` — the closing sign-off: a short clay rule,
"That's the whole shelf", and the count line. Before it, the feed ended on the
same product card repeated to the last item followed by blank space, which read
as the grid breaking rather than the shelf ending.

**Deliberately a signpost only** — no CTA and no product rail. The feed has
already shown everything it has; the module marks the end and names how much the
customer just got through.

**Gate** (mirrors On Sale / Best Sellers): rendered only when
`_searchKeyword.isEmpty` **and** `selectedCategory` is `null`/`'All'` **and**
the catalog is not loading **and** `filteredProducts` is non-empty. Under a
search or a category the feed is a slice, so "that's the whole shelf" would be
false.

**Counts** — `productCount` is the loaded catalog size; `storeCount` is the
distinct `store_id`s in that same list (the key the Store tab indexes on), so
the module adds **no query**. `catalogSignpostLine` omits whichever half it
cannot prove: no shop count yields `'12 pairs'`, no pairs yields no line at all.

## HomeHero widget

**File:** `lib/screens/customer/widgets/home_hero.dart`

A self-contained `StatefulWidget` (344px) that renders the full-bleed hero section:

- **Background**: 3-stop gradient (warm sand → golden brown → deep chocolate) with radial glow and dark overlay for text readability
- **Icon row**: Real search `TextField` (frosted pill, focus state with primary border/shadow) + cart icon with item count badge
- **Category tabs**: Text tabs with animated underline indicator. Drives `ProductProvider.selectCategory()`
- **Featured banner carousel**: `PageView.builder` with 3 editorial items, auto-scrolls every 4s
- **Floating product cards**: Two overlapping, slightly rotated cards showing real products from `ProductProvider.products`
- **"Shop now" CTA**: "NEW ARRIVALS" eyebrow + "CRAFTED FOR FALL" serif headline + underlined CTA
- **Page indicator dots**: Animated dots reflecting `_bannerIndex`

### Callbacks

| Callback | Trigger | Action in CustomerHomeScreen |
|----------|---------|------------------------------|
| `onCartTap` | Tap cart icon | Push `CartScreen` |
| `onCtaTap` | Tap "SHOP NOW →" | `Scrollable.ensureVisible` to product grid |
| `onProductTap` | Tap floating card | Push `ProductDetailScreen` |
| (none — the bars are tap-only) | Tap a search bar | Push `ProductSearchScreen` via `_openSearchScreen()` |
| `onAudienceTap` | Tap an audience chip | Push `AudienceListingScreen(audience:)` |

### State passed from parent

- `onSearchTap` — the only prop either search bar takes; `CustomerHomeScreen` owns the navigation
- `cartCount` — from `CartProvider.itemCount`
- `onAudienceTap` — the shelf chips again hand navigation to the screen; the hero reads `ProductProvider.audiencesInCatalog` and passes the canonical catalogue value back

### HomeCategoryRow widget

**File:** `lib/screens/customer/widgets/home_category_row.dart`

The hero's chip strip, extracted so it reads no providers (the hero itself cannot be built in a widget test — `BannerProvider` constructs a live Supabase client).

- **Category chips** drive `ProductProvider.selectCategory()` and grow the animated underline while active — unchanged behaviour. The indicator is `AppConstants.inkInverse` (**pinned**), not a theme token: this row sits on the hero's photo band, which is dark in both brightnesses, so a brightness-aware colour would resolve to the near-black page on dark and vanish into the image.
- **Audience chips** (`HomeCategoryRow.audiences`, in practice `ProductProvider.audiencesInCatalog`) each open `AudienceListingScreen` for that audience. They are **never underlined**: tapping one leaves this feed instead of narrowing it. Two chips, one look — a row of two visually distinct control types reads as a toolbar.
- A chip only exists for an audience the catalog **actually holds** (`audiencesInCatalog`), the same rule the `On Sale` / `Best Sellers` chips follow — with today's `audience = null` catalog this is an empty list, so the row is exactly what it was before the feature was switched on.
- The whole strip is gated by `AppConstants.productAudienceEnabled` (now `true`).
- The strip is a horizontally scrolling `Row` sized to its content, **not** a fixed-height `ListView` — the fixed 44px clipped the label by 4px at a 1.3× text scale.

### AudienceListingScreen

**File:** `lib/screens/customer/audience_listing_screen.dart`

One audience's entire shelf: header (label + count) with a Back button, its own sort chip (local `SortMode`, default Featured — passing it never re-sorts Home), the `MasonryGridView` of that audience's products, and an empty state when the shelf is bare. Its source is `ProductProvider.productsInAudience()` — uncapped, and the one audience surface that **includes** `unisex` (the rails must skip it, or a house slipper appears in three rails at once). Untagged products appear on no shelf, here or in the rails.

Two constraints a later edit must keep:

- **The header stacks when the text scale is large.** Above a threshold tied to the scaled sort label, the sort chip moves to its own line instead of sharing one with the back button and the title. A sort label is a *word* — squeezing it means ellipsising it, which is a control the customer cannot read. The chip's label is `Flexible` as well, so no font/scale combination can overflow it; it wraps before it would clip.
- **Accent ink is `AppPalette.primaryInk`, not `AppConstants.primary`.** The brand clay is pinned at `#8B5A2B`, which is only ~3.3:1 on the dark page — under AA for the 11–13px labels on this page (the sort chip, the empty-state pill). The pinned clay stays for fills and hairline tints, where it is decoration rather than something to read.

## StoreScreen — multi-store discovery tab

**File:** `lib/screens/store/store_screen.dart`

A vertical `SingleChildScrollView` with three sections:

1. **StoreHeroCarousel** — `PageView.builder` with peek viewport (0.85). Shows store cards with scale animation driven by a `PageController` listener. `onStoreChanged` fires on page settle.
2. **StoreFocusedInfo** — store name, tagline, product count for the currently focused store.
3. **CrossStoreProductRow** — horizontal scroll of top-picks (newest 12 products) from the focused store.

### Performance notes

- Uses `context.select<ProductProvider>` (not `context.watch`) to only rebuild when the `products` list reference changes.
- Per-store product counts and top-picks are cached via `_reindexIfNeeded()` — only recomputed when the product list reference changes (checked via `identical()`), not on every swipe.

### Store sub-widgets

| Widget | File | Purpose |
|--------|------|---------|
| `StoreHeroCarousel` | `widgets/store_hero_carousel.dart` | PageView carousel + page dots. Scale animation via own `PageController` listener (does NOT trigger parent rebuilds). |
| `StoreHeroCard` | `widgets/store_hero_card.dart` | Single card: brand gradient/banner, logo, open/closed chip, stat pills. Uses `CachedNetworkImage`. |
| `StoreFocusedInfo` | `widgets/store_focused_info.dart` | Store name, tagline, product count strip. |
| `CrossStoreProductRow` | `widgets/cross_store_product_row.dart` | Horizontal scroll of product cards for focused store. |

## ProfileScreen — shared across roles

**File:** `lib/screens/shared/profile_screen.dart`

Not customer-specific — same screen renders for customers and sellers (role-conditional sections).

**Customer sections:**
- Avatar + name + email + role badge
- Edit panel (collapsible name/phone form)
- Following count + following list dialog
- My Orders panel (Unpaid / Processing / Shipped / Review / Returns with badge counts from `OrderProvider`)
- Buy Again section
- Recently Viewed section
- Settings card → `SettingsScreen`
- Help & Support → `HelpMenuScreen`
- What's New → `WhatsNewScreen`

**Seller-only sections:**
- Store info (open/closed toggle, status, link to `StoreProfileScreen`)
- Payment Methods → `GcashPaymentSettingsScreen`
- Business Verification → `SellerBusinessVerificationScreen`

Uses TTL-based refresh: re-fetches orders, recently-viewed, and business status on tab re-entry (via `DateTime` diff in `build()`).

## Key providers

| Provider | File | Scope | What it owns |
|----------|------|-------|-------------|
| `AuthProvider` | `providers/auth_provider.dart` | App-root | User session, profile, login/signup/logout, profile updates, email change |
| `ProductProvider` | `providers/product_provider.dart` | App-root | Product catalog (all/seller-scoped), categories, sort mode, filtered products |
| `OrderProvider` | `providers/order_provider.dart` | App-root | Customer orders, order counts by status |
| `CartProvider` | `providers/cart_provider.dart` | App-root | Cart items, totals |
| `FollowProvider` | `providers/follow_provider.dart` | App-root | Followed stores |
| `MessageProvider` | `providers/message_provider.dart` | App-root | Chat conversations, realtime subscription |
| `NotificationProvider` | `providers/notification_provider.dart` | App-root | Unread notification count |
| `UpdateProvider` | `providers/update_provider.dart` | App-root | App version info |

All providers are app-root singletons, created in `main.dart` and consumed via `Provider.of` / `context.watch` / `context.select` / `context.read`.

## Notable services

| Service | File | Purpose |
|---------|------|---------|
| `AuthService` | `services/auth_service.dart` | Supabase auth wrapper, profile CRUD |
| `SupabaseService` | `services/supabase_service.dart` | Raw Supabase queries (products, orders, etc.) |
| `StoreService` | `services/store_service.dart` | Store CRUD, fetch all stores |
| `ProfileService` | `services/profile_service.dart` | Avatar pick + upload |
| `ConnectivityService` | `services/connectivity_service.dart` | Online/offline stream |
| `PushNotificationService` | `services/push_notification_service.dart` | FCM setup, deep-link callbacks |
| `RecentlyViewedService` | `utils/recently_viewed.dart` | Local recently-viewed product history |
| `productImageUrls` | `utils/product_images.dart` | Every photo on a product map, in the seller's order — reads a raw row's `product_images` and the mapped model's flat `images` |

## Key widgets (shared)

| Widget | File | Used by |
|--------|------|---------|
| `SoleProductCard` | `widgets/sole_product_card.dart` | Home grid, sale section, cross-store row. Text-scale safe: its price/category row and rating/sold row wrap rather than overflow on a narrow phone at a large scale (they overflowed at 2.0× until P2's chip-row work surfaced it). Its photo area is a `ProductImagePager` |
| `ProductImagePager` | `widgets/product_image_pager.dart` | The card's swiped photo: one page per image, dots for the current one, and the sale countdown stacked under them |
| `BestSellersSection` | `widgets/best_sellers_section.dart` | Home — horizontally-scrolling Best Sellers rail (live `units_sold` order) |
| `HorizontalProductCard` | `widgets/horizontal_product_card.dart` | Home Best Sellers rail, profile Buy Again / Recently Viewed rails |
| `SoleBottomNav` | `widgets/sole_bottom_nav.dart` | All shells (customer, seller, admin) |
| `CartIconButton` | `widgets/cart_icon_button.dart` | Home, Store app bars |
| `FloatingMessageButton` | `widgets/floating_message_button.dart` | Home tab overlay |
| `ShimmerGroup` / `SkeletonBox` | `widgets/shimmer_group.dart` | Loading skeletons |
| `NoInternetView` | `widgets/no_internet_view.dart` | Offline state |
| `CustomerFootProfileBanner` | `widgets/customer_foot_profile_banner.dart` | Home — foot sizing reminder |
| `InYourSizeSection` | `widgets/in_your_size_section.dart` | Home — The Workshop Collection's grid of products that stock the customer's saved size |
| `ProductGridSection` | `widgets/product_grid_section.dart` | Home — the shared grid body (text header *or* poster tile + 2-col catalog masonry + trailing gap) |
| `FitCard` | `widgets/fit_card.dart` | The "Fit Card" poster tile — copy scaled to fill the card, no icons; "Based on your size · EU 42" is the reference card. The hero is a value or a widget (`heroWidget`), which is how "See more" carries an arrow |
| `SeeMoreCard` | `widgets/see_more_card.dart` | Home — the capped grid's last cell: a `FitCard` saying `See` / `more` over a painted `ArrowGlyph`, nudging on press, opening `SizeListingScreen` |
| `ProductSectionHeader` | `widgets/product_section_header.dart` | Home — the shared section header (title + muted meta) rails and grid both use |
| `ProductRailSection` | `widgets/product_rail_section.dart` | Home — the shared rail body (header + 130×180 strip + trailing gap) the three audience rails render through |
| `AudienceSection` | `widgets/audience_section.dart` | Home — one Men's / Women's / Kids' rail (self-hiding, switch-gated) |
| `HomeCategoryRow` | `screens/customer/widgets/home_category_row.dart` | Home hero — category chips + the audience shelf chips |
| `CatalogEndCap` | `widgets/catalog_end_cap.dart` | Home — the "that's the whole shelf" sign-off at the end of the catalog |

## File tree summary

```
lib/
├── main.dart                          # App entry, providers, Supabase init
├── screens/
│   ├── auth_gate.dart                 # Auth state → role routing
│   ├── customer/
│   │   ├── customer_shell.dart        # PageView + KeepAlivePage + bottom nav (4 tabs)
│   │   ├── customer_home_screen.dart  # Main browse tab (this doc's focus)
│   │   ├── product_detail_screen.dart
│   │   ├── cart_screen.dart
│   │   ├── checkout_screen.dart
│   │   ├── my_orders_screen.dart
│   │   ├── buy_again_screen.dart
│   │   ├── recently_viewed_screen.dart
│   │   ├── audience_listing_screen.dart  # One audience's whole shelf
│   │   ├── size_listing_screen.dart   # The size shelf uncapped ("See more")
│   │   ├── search_results_screen.dart
│   │   ├── tag_products_screen.dart
│   │   ├── tracking_screen.dart
│   │   ├── write_review_screen.dart
│   │   ├── customization_screen.dart
│   │   └── ar_fitting / foot_*        # AR foot scanning flow
│   │   └── widgets/
│   │       ├── home_hero.dart         # Full-bleed hero (search, chips, cards, CTA)
│   │       └── home_category_row.dart # Category chips + audience shelf chips
│   ├── store/
│   │   ├── store_screen.dart          # Store discovery tab
│   │   └── widgets/                   # Carousel, card, info, product row
│   ├── shared/
│   │   ├── profile_screen.dart        # Cross-role profile
│   │   ├── settings_screen.dart
│   │   └── ...
│   ├── seller/                        # Seller shell + screens
│   └── admin/                         # Admin shell + screens
├── providers/                         # 15 ChangeNotifier providers
├── services/                          # Supabase, auth, stores, etc.
├── widgets/                           # Shared UI components
├── constants/
│   └── app_constants.dart             # Colors, styles, role strings, categories
└── utils/                             # Helpers (sale_price, recently_viewed, etc.)
```
