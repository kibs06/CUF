# Feature File Lookup Guide — SoleVision

This document maps 8 product improvements to their relevant file paths, existing logic, and what's missing. Designed to be given to an AI assistant (e.g. Claude Code, Cursor, GitHub Copilot Chat) with read/write access to the project.

---

## Project Architecture

- **State management:** Provider (all providers extend `ChangeNotifier`, use `context.watch<T>()` / `context.read<T>()`)
- **Local storage:** `SharedPreferences` (used for cart cache, onboarding flag, floating button position, last visited store, notification filter)
- **Data source:** Supabase (PostgreSQL) via `supabase_flutter` SDK — everything is a REST query, no local product list
- **Widget library:** Custom components in `lib/widgets/` — `SoleCard`, `SolePrimaryButton`, `SoleBadge`, `SoleStatusChip`, `SoleTimeline`, `SoleStarRating`, `SoleMetricCard`, `SoleProductCard`. **Use these**, don't introduce raw Material widgets where a `Sole*` equivalent exists.
- **Constants:** All colors, typography, roles, API keys in `lib/constants/app_constants.dart` — reuse existing style getters (e.g. `AppConstants.bodyStyle()`) rather than hardcoding `TextStyle`s
- **Product data:** Currently `Map<String, dynamic>` throughout — no full typed Product model. **Don't refactor this** unless a task explicitly requires it; work with the existing map-based pattern for consistency.

---

## Features

### 1. Secure Checkout Indicators

| Aspect | Detail |
|--------|--------|
| **File** | `lib/screens/customer/checkout_screen.dart` |
| **Location in file** | Payment method section — near the `RadioListTile` group built by `_buildPaymentRadio()` |
| **Existing logic** | The payment method section uses `SoleCard` with radio tiles for GCash QR and Pay on Delivery. The `SoleCard` styling, `AppConstants` colors and typography are already used here. |
| **What to add** | A security badge row: `Icons.lock_outline` + "Your payment information is encrypted and secure" text. Use a `SoleCard` or a simple `Row` with the lock icon and body-style text. Keep visual weight subtle — don't make it loud. |
| **Design guidance** | Purposeful minimalism, trust and clarity signals, dark mode compatible (check `AppConstants` for dark theme colors). |

### 2. Quantity Limit Display

| Aspect | Detail |
|--------|--------|
| **Primary file** | `lib/screens/customer/cart_screen.dart` |
| **Secondary file** | `lib/services/cart_service.dart` |
| **Existing logic** | `CartService.validateCartForCheckout()` (line ~248 in `cart_service.dart`) already returns `CartValidationResult` objects with `currentStock`, `cartQuantity`, and `itemKey` fields. `CartProvider.validateForCheckout()` (line ~517 in `cart_provider.dart`) calls this and stores results. |
| **What to add** | In the `_CartItemRow` or equivalent cart item widget: show a "Max: X" label near the quantity stepper. Disable the `+` stepper button when quantity reaches `currentStock`. If `validateForCheckout()` hasn't run recently for this item, fall back to not showing a limit rather than making a new network call. |
| **Extra (design request)** | When stock is low (e.g. ≤ 3), render a "Only X left" `SoleBadge` in an attention color alongside the quantity limit. |
| **CartValidationResult model** | Defined in `lib/models/cart_item_with_details.dart` (line ~92) — has `currentStock`, `cartQuantity`, `itemKey`, `available`. |

### 3. Size Guide Modal

| Aspect | Detail |
|--------|--------|
| **Trigger file** | `lib/screens/customer/product_detail_screen.dart` |
| **New widget file** | Create `lib/widgets/size_guide_modal.dart` |
| **Existing logic** | Size selection is built by `_buildSizesMap()` which renders `ChoiceChip`s for available sizes and a disabled chip with a cross for unavailable ones. The file uses `showModalBottomSheet` elsewhere (e.g. for color selection), so match that pattern. |
| **What to add** | A small "Size guide" `TextButton` or `InkWell` next to the size selector label. Opens a bottom sheet showing a static conversion table: EU sizes 36–46, US Men's equivalents, CM foot length. Content is static (no API call needed). Reuse `SoleCard` for the table rows. |
| **Design guidance** | Bottom sheets over full dialogs for secondary content. Keep context visible underneath. Thumb-friendly touch targets. |

### 4. Return / Refund Policy Screen

| Aspect | Detail |
|--------|--------|
| **Navigation file** | `lib/screens/shared/profile_screen.dart` |
| **New screen file** | Create `lib/screens/shared/terms_privacy_screen.dart` |
| **Existing logic** | `profile_screen.dart` line ~688 calls `_openPlaceholder('Terms & Privacy')` which shows a "Coming soon" snackbar. Replace this with a navigation to the new screen. |
| **What to add** | A full-screen widget showing: "Terms & Privacy" as the title. Draft policy copy covering: 7-day return window from delivery, items must be unworn/unused with original packaging, refund to original payment method within 5–7 business days, buyer covers return shipping unless item is defective/incorrect. Add a clear note at the top: text saying "Draft policy — pending legal review" so it's obvious this isn't final. |
| **Design guidance** | Plain, confident language. Clear visual hierarchy. Trust is a UX feature here. |

### 5. Social Sharing

| Aspect | Detail |
|--------|--------|
| **File** | `lib/screens/customer/product_detail_screen.dart` |
| **Dependency** | `pubspec.yaml` — add `share_plus` (not currently a dependency) |
| **Existing logic** | The AppBar (`SliverAppBar`) currently has `actions: [CartIconButton]`. The product detail screen already loads product data as `Map<String, dynamic>`. |
| **What to add** | A share icon button (`Icons.share_outlined`) in the `SliverAppBar actions` before the cart icon. On tap, call `Share.share()` with a text string containing product name, price, and image URL. Use the same button styling as the existing back button (circular semi-transparent background). If the app already uses `url_launcher` with deep links, craft a deep link; otherwise just share text. |
| **Edge cases** | If the image URL is empty or broken, skip it rather than sharing a broken link. Handle the async call with try/catch. |

### 6. Recently Viewed Products

| Aspect | Detail |
|--------|--------|
| **Capture file** | `lib/screens/customer/product_detail_screen.dart` |
| **Display file** | `lib/screens/customer/customer_home_screen.dart` |
| **New helper file** | Create `lib/utils/recently_viewed.dart` |
| **Existing logic** | `customer_home_screen.dart` lines ~93–105 use `SharedPreferences` to store/store `last_visited_store_id` and `last_visited_store_name` in `initState()`. Follow this exact pattern. |
| **What to add** | **RecentlyViewedService** — a helper class that stores a JSON array of lightweight product summaries (`{id, name, price, imageUrl}`), capped at 20, most recent first. Uses `SharedPreferences`. **Capture** — in `product_detail_screen.dart` `initState()` (or `didChangeDependencies()`), call `RecentlyViewedService.add(product)`. **Display** — on `customer_home_screen.dart`, add a `SliverToBoxAdapter` (or section) above the product catalog with a horizontal scrolling list using `SoleProductCard`. Hide entirely if the list is empty. |
| **Extra (design request)** | When the recently viewed list is empty, show a subtle placeholder hint: "Products you view will show up here" to make the feature discoverable. |

### 7. Estimated Delivery Dates

| Aspect | Detail |
|--------|--------|
| **Display file** | `lib/screens/customer/checkout_screen.dart` |
| **Constants file** | `lib/constants/app_constants.dart` |
| **Existing logic** | The checkout screen has a `_priceRow` section showing subtotal, delivery fee (₱100), and total. The delivery fee is computed as `subtotal > 0 ? 100 : 0` in `CartProvider`. |
| **What to add** | Add a constant `deliveryEstimateText = "Estimated delivery: 3-5 business days after order confirmation"` to `AppConstants`. Display it as a line under or near the delivery fee row in `_priceRow`. Use a `Row` with a clock/truck icon and the text, in a subtle secondary color. |
| **Design guidance** | Trust signal — plain language, clear visual hierarchy. Hardcoded global estimate, no per-store processing days (no schema migration needed). |

### 8. Search Filters / Sort

| Aspect | Detail |
|--------|--------|
| **Primary files** | `lib/screens/customer/customer_home_screen.dart`, `lib/providers/product_provider.dart` |
| **Service file** | `lib/services/supabase_service.dart` (minor — or skip for client-side sorting) |
| **Existing logic** | `ProductProvider` has `products` list, `selectedCategory`, and `getFilteredProducts(searchKeyword)` which filters by search + category. Products are fetched by `SupabaseService.fetchProducts()` once. |
| **What to add** | **Sort state** — add a `SortMode` enum (`newest`, `priceAsc`, `priceDesc`, `rating`, `nameAZ`, `nameZA`) and `_sortMode` to `ProductProvider`, plus a `getSortedAndFilteredProducts()` accessor. **UI** — a sort bottom sheet or dropdown triggered from a button next to "Artisan Catalog" header. Options: Price: Low-High, Price: High-Low, Rating, Newest, Name (A-Z, Z-A). Wire into existing category chips — don't replace them. **Filter** — price range slider and size filter if the data supports it, but start with sort-only for a clean MVP. |
| **Scale decision** | Since `fetchProducts()` returns a reasonable-size list (seller-level, not marketplace-level), client-side sort is acceptable. No server-side changes needed. |

---

## Summary of New Files to Create

| Feature | New File |
|---------|----------|
| Size guide modal | `lib/widgets/size_guide_modal.dart` |
| Return/refund policy | `lib/screens/shared/terms_privacy_screen.dart` |
| Recently viewed | `lib/utils/recently_viewed.dart` |

## Summary of Existing Files to Modify

| File | Features |
|------|----------|
| `lib/screens/customer/checkout_screen.dart` | #1 (secure badge), #7 (delivery estimate) |
| `lib/screens/customer/cart_screen.dart` | #2 (quantity limit) |
| `lib/screens/customer/product_detail_screen.dart` | #3 (size guide trigger), #5 (share button), #6 (capture view) |
| `lib/screens/shared/profile_screen.dart` | #4 (route to new screen) |
| `lib/screens/customer/customer_home_screen.dart` | #6 (recently viewed section), #8 (sort/filter) |
| `lib/providers/product_provider.dart` | #8 (sort mode + filtered accessor) |
| `lib/constants/app_constants.dart` | #7 (delivery estimate constant) |
| `pubspec.yaml` | #5 (add share_plus dependency) |