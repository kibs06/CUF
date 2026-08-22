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

Uses `IndexedStack` (all 4 tabs stay alive in memory) with a `SoleBottomNav` bottom bar:

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
   - Category text tabs with underline indicator
   - "NEW ARRIVALS / CRAFTED FOR FALL" headline + floating product cards + "SHOP NOW" CTA + page dots
2. **Sheet** — `SliverToBoxAdapter` with rounded top corners (`ClipRRect` `borderRadius: 22`), containing:
   - Foot profile banner (conditional — only for incomplete profiles)
   - On Sale section (conditional — only when no search + no category filter + sale items exist)
   - Catalog header + sort button
   - Product grid (`MasonryGridView.count`, 2-col)
   - Bottom spacing for nav bar

### Data flow

- On `initState` (post-frame): calls `ProductProvider.loadProducts(hideOutOfStock: true)` to fetch the full catalog from Supabase, then shuffles it.
- On pull-to-refresh: re-calls `loadProducts(hideOutOfStock: true)`.
- On connectivity restore (was offline → now online): auto-refreshes products.
- On `_loadConversations()`: loads chat conversations for the floating message badge + subscribes to realtime inbox.
- Push notification deep-link handlers: navigates to `ChatView`, `OrderTrackingScreen`, or `MyReportsScreen`.
- Search: hero search bar drives inline filtering via `ProductProvider.getFilteredProducts(_searchKeyword)`.

### Key providers consumed

- `ProductProvider` — `context.watch` for: `products`, `categories`, `selectedCategory`, `sortMode`, `isLoading`, `getFilteredProducts()`, `selectCategory()`, `setSortMode()`.
- `CartProvider` — `context.select` for `itemCount` (cart badge on hero icon).
- `MessageProvider` — `context.read` for conversation loading (no watch).

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
| `onSearchChanged` | Type in search bar | `setState(_searchKeyword)` → inline grid filter |

### State passed from parent

- `searchController` / `searchFocusNode` — owned by `CustomerHomeScreen`, passed down for the real search TextField
- `cartCount` — from `CartProvider.itemCount`

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

## Key widgets (shared)

| Widget | File | Used by |
|--------|------|---------|
| `SoleProductCard` | `widgets/sole_product_card.dart` | Home grid, sale section, cross-store row |
| `SoleBottomNav` | `widgets/sole_bottom_nav.dart` | All shells (customer, seller, admin) |
| `CartIconButton` | `widgets/cart_icon_button.dart` | Home, Store app bars |
| `FloatingMessageButton` | `widgets/floating_message_button.dart` | Home tab overlay |
| `ShimmerGroup` / `SkeletonBox` | `widgets/shimmer_group.dart` | Loading skeletons |
| `NoInternetView` | `widgets/no_internet_view.dart` | Offline state |
| `CustomerFootProfileBanner` | `widgets/customer_foot_profile_banner.dart` | Home — foot sizing reminder |

## File tree summary

```
lib/
├── main.dart                          # App entry, providers, Supabase init
├── screens/
│   ├── auth_gate.dart                 # Auth state → role routing
│   ├── customer/
│   │   ├── customer_shell.dart        # IndexedStack + bottom nav (4 tabs)
│   │   ├── customer_home_screen.dart  # Main browse tab (this doc's focus)
│   │   ├── product_detail_screen.dart
│   │   ├── cart_screen.dart
│   │   ├── checkout_screen.dart
│   │   ├── my_orders_screen.dart
│   │   ├── buy_again_screen.dart
│   │   ├── recently_viewed_screen.dart
│   │   ├── tag_products_screen.dart
│   │   ├── tracking_screen.dart
│   │   ├── write_review_screen.dart
│   │   ├── customization_screen.dart
│   │   └── ar_fitting / foot_*        # AR foot scanning flow
│   │   └── widgets/
│   │       └── home_hero.dart         # Full-bleed hero (search, chips, cards, CTA)
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
