# SoleVision — Customer Module Documentation

**Version:** 1.0.0  
**Last Updated:** July 16, 2026  
**Purpose:** Complete reference for the Customer-facing side of the SoleVision app.

---

## Table of Contents

1. [Overview](#1-overview)
2. [Architecture](#2-architecture)
3. [Navigation Structure](#3-navigation-structure)
4. [Screen Reference](#4-screen-reference)
5. [Data Flow Diagrams](#5-data-flow-diagrams)
6. [State Management](#6-state-management)
7. [Services Layer](#7-services-layer)
8. [Widgets Reference](#8-widgets-reference)
9. [Data Models](#9-data-models)
10. [Database Queries](#10-database-queries)
11. [Feature Status & Audit](#11-feature-status--audit)
12. [Known Issues & Bugs](#12-known-issues--bugs)
13. [Critical Issues to Fix](#13-critical-issues-to-fix)
14. [Testing Checklist](#14-testing-checklist)

---

## 1. Overview

The Customer module is the primary buyer-facing side of SoleVision. It allows customers to:

- Browse artisan footwear from multiple stores
- Search and filter products by category
- View product details with image galleries and size selectors
- Add products to a persistent cart
- Checkout with delivery address and payment method selection
- Track order status in real-time
- Request custom shoe designs
- Manage saved delivery addresses
- Chat with stores in real-time (text, images, video)
- Receive push notifications for new messages

### Key Files

| Category | Files |
|----------|-------|
| **Screens** | `lib/screens/customer/*.dart` (12 screens) |
| **Shell** | `lib/screens/customer/customer_shell.dart` |
| **Widgets** | `lib/widgets/sole_product_card.dart`, `lib/widgets/cart_icon_button.dart`, `lib/widgets/floating_message_button.dart`, `lib/widgets/fly_to_cart_animation.dart`, `lib/widgets/sole_ar_pill.dart`, `lib/widgets/messages_quick_preview_sheet.dart` |
| **Providers** | `lib/providers/cart_provider.dart`, `lib/providers/product_provider.dart`, `lib/providers/order_provider.dart`, `lib/providers/address_provider.dart`, `lib/providers/message_provider.dart`, `lib/providers/notification_provider.dart` |
| **Services** | `lib/services/cart_service.dart`, `lib/services/product_service.dart`, `lib/services/order_service.dart`, `lib/services/address_service.dart`, `lib/services/message_service.dart`, `lib/services/connectivity_service.dart` |
| **Utilities** | `lib/utils/cart_helpers.dart` |

---

## 2. Architecture

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    PRESENTATION LAYER                            │
│                                                                 │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐  │
│  │ CustomerShell │  │   Screens    │  │     Widgets          │  │
│  │ (Bottom Nav)  │──│  (12 total)  │──│  (SoleProductCard,   │  │
│  │              │  │              │  │   CartIconButton,     │  │
│  │  Home        │  │  Home        │  │   FloatingMessageBtn, │  │
│  │  Store       │  │  ProductDetail│  │   FlyToCartAnimation) │  │
│  │  Notifs      │  │  Cart        │  │                      │  │
│  │  Profile     │  │  Checkout    │  └──────────────────────┘  │
│  └──────────────┘  │  MyOrders    │                            │
│                    │  Tracking    │                            │
│                    │  AddressBook │                            │
│                    │  AddAddress  │                            │
│                    │  AR Fitting  │                            │
│                    │  Customization│                           │
│                    │  CustomerInbox│                           │
│                    └──────┬───────┘                            │
│                           │                                     │
├───────────────────────────┼─────────────────────────────────────┤
│                    STATE LAYER                                   │
│                           │                                     │
│  ┌────────────────────────┼──────────────────────────────────┐  │
│  │                   Providers                                │  │
│  │                                                            │  │
│  │  ┌─────────────┐ ┌─────────────┐ ┌──────────────────┐    │  │
│  │  │ ProductProvider│ │ CartProvider │ │ OrderProvider    │    │  │
│  │  │ - products[] │ │ - items{}    │ │ - orders[]       │    │  │
│  │  │ - categories │ │ - selectedKeys│ │ - myOrders[]     │    │  │
│  │  │ - category   │ │ - subtotal   │ │ - stockError     │    │  │
│  │  └─────────────┘ └─────────────┘ └──────────────────┘    │  │
│  │                                                            │  │
│  │  ┌─────────────┐ ┌─────────────┐ ┌──────────────────┐    │  │
│  │  │AddressProvider│ │Auth Provider│ │ MessageProvider   │    │  │
│  │  │ - addresses[]│ │ - profile   │ │ - conversations[] │    │  │
│  │  │ - selected   │ │ - isLoading │ │ - unreadCounts{}  │    │  │
│  │  └─────────────┘ └─────────────┘ └──────────────────┘    │  │
│  │                                                            │  │
│  │  ┌─────────────┐ ┌─────────────────────────────────────┐  │  │
│  │  │NotificationProvider│ │ ChatAttachmentProvider         │  │  │
│  │  │ - notifications[]  │ │ - failedMessages{}             │  │  │
│  │  └─────────────┘ └─────────────────────────────────────┘  │  │
│  └────────────────────────────────────────────────────────────┘  │
│                           │                                     │
├───────────────────────────┼─────────────────────────────────────┤
│                    SERVICE LAYER                                 │
│                           │                                     │
│  ┌────────────────────────┼──────────────────────────────────┐  │
│  │                   Services (Singletons)                    │  │
│  │                                                            │  │
│  │  ┌──────────────┐ ┌──────────────┐ ┌──────────────────┐  │  │
│  │  │ ProductService│ │ CartService   │ │ OrderService     │  │  │
│  │  │              │ │              │ │                  │  │  │
│  │  │ fetchProducts│ │ fetchCart()  │ │ placeOrder()     │  │  │
│  │  │ createProduct│ │ addToCart()  │ │ fetchStoreOrders │  │  │
│  │  │ updateProduct│ │ removeFromCart│ │ updateOrderStatus│  │  │
│  │  │ deleteProduct│ │ validateFor  │ │ getRecentOrders  │  │  │
│  │  │              │ │   Checkout() │ │                  │  │  │
│  │  └──────────────┘ └──────────────┘ └──────────────────┘  │  │
│  │                                                            │  │
│  │  ┌──────────────┐ ┌──────────────┐ ┌──────────────────┐  │  │
│  │  │AddressService │ │ MessageService│ │ ConnectivitySvc  │  │  │
│  │  │              │ │              │ │                  │  │  │
│  │  │ addAddress() │ │ sendMessage()│ │ isOnline         │  │  │
│  │  │ updateAddress│ │ getMessages()│ │ isOnlineStream   │  │  │
│  │  │ deleteAddress│ │ subscribeTo  │ │                  │  │  │
│  │  │ setDefault() │ │   Conversation│ │                  │  │  │
│  │  └──────────────┘ └──────────────┘ └──────────────────┘  │  │
│  │                                                            │  │
│  │  ┌──────────────┐ ┌──────────────┐                        │  │
│  │  │ StoreService  │ │ PushNotifSvc │                        │  │
│  │  │              │ │              │                        │  │
│  │  │ getMyStore() │ │ init()       │                        │  │
│  │  │ followStore()│ │ onNavigateTo │                        │  │
│  │  │ unfollowStore│ │   Chat       │                        │  │
│  │  └──────────────┘ └──────────────┘                        │  │
│  └────────────────────────────────────────────────────────────┘  │
│                           │                                     │
├───────────────────────────┼─────────────────────────────────────┤
│                    BACKEND (Supabase)                            │
│                           │                                     │
│  ┌────────────────────────┼──────────────────────────────────┐  │
│  │  ┌──────────┐ ┌──────────┐ ┌────────────┐ ┌──────────┐  │  │
│  │  │   Auth   │ │ Postgres │ │  Storage   │ │ Realtime │  │  │
│  │  │ (JWT)   │ │   (RLS)  │ │ (images)   │ │(messages)│  │  │
│  │  └──────────┘ └──────────┘ └────────────┘ └──────────┘  │  │
│  └────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### Layer Responsibilities

| Layer | Responsibility | Pattern |
|-------|---------------|---------|
| **Presentation** | UI rendering, user input handling, navigation | StatefulWidget + Consumer/Provider.watch |
| **State** | Business logic, state mutation, error handling | ChangeNotifier + Provider |
| **Service** | API calls, data transformation, side effects | Singleton classes, throw exceptions |
| **Backend** | Data persistence, auth, realtime, storage | Supabase SDK |

### Data Flow Pattern

```
User taps "Add to Cart"
  │
  ▼
ProductDetailScreen._addToCart()
  │  1. Resolve variant via resolveVariant()
  │  2. Call cart.addToCart()
  │
  ▼
CartProvider.addToCart()
  │  1. Add to local _items{} map (optimistic)
  │  2. Notify listeners (UI updates instantly)
  │  3. Background: CartService.syncToServer()
  │
  ▼
CartService.syncToServer()
  │  1. Supabase INSERT/UPDATE cart_items
  │  2. On failure: rollback local state
  │
  ▼
Supabase PostgreSQL
  │  cart_items table updated
  │  RLS ensures user can only modify own cart
  │
  ▼
UI reflects new cart count (CartIconButton badge)
```

---

## 3. Navigation Structure

### Customer Shell (Bottom Navigation)

```
CustomerShell
├── Tab 0: CustomerHomeScreen     (Home icon)
├── Tab 1: StoreScreen            (Storefront icon)
├── Tab 2: NotificationsScreen    (Notifications icon)
└── Tab 3: ProfileScreen          (Person icon)

AppBar actions:
└── CartIconButton (badge shows item count)
    └── onTap → CartScreen (pushed, not a tab)
```

### Navigation Map

```
CustomerShell
│
├── Home Tab
│   ├── Search → filters product grid
│   ├── Category chips → filter by category
│   ├── Product card tap → ProductDetailScreen
│   │   ├── Image tap → Full-screen image viewer
│   │   ├── "Add to Cart" → adds to cart + fly animation
│   │   ├── "Buy Now" → adds to cart (should navigate to checkout)
│   │   ├── "Try On" pill → ARVirtualFitScreen
│   │   └── Back → returns to home
│   ├── "Continue Browsing" chip → StoreProfileScreen
│   └── FloatingMessageButton → CustomerInboxScreen
│
├── Store Tab
│   ├── Store card tap → StoreProfileScreen
│   │   ├── Follow/Unfollow toggle
│   │   ├── Product list → ProductDetailScreen
│   │   └── "Message Store" → ChatView
│   └── Collection cards → StoreScreen filtered
│
├── Notifications Tab
│   ├── Order notification → OrderTrackingScreen
│   ├── Message notification → ChatView
│   └── Customization notification → MyOrdersScreen
│
├── Profile Tab
│   ├── "My Orders" → MyOrdersScreen
│   │   ├── Tab: All / Unpaid / Processing / Shipped / Review / Returns
│   │   ├── Order card tap → OrderTrackingScreen
│   │   └── "Enable SMS" → stub (coming soon)
│   ├── "My Addresses" → AddressBookScreen
│   │   ├── "Add New Address" → AddEditAddressScreen (map pin-drop)
│   │   ├── "Edit" → AddEditAddressScreen (edit mode)
│   │   ├── "Set as Default" → updates default
│   │   └── "Delete" → removes address
│   ├── "Custom Craft" → CustomizationScreen (5-step stepper)
│   ├── "Edit Profile" → EditProfileScreen
│   └── "Logout" → signs out
│
└── Cart (via AppBar icon)
    └── CartScreen
        ├── Store group cards
        │   ├── Store header → StoreProfileScreen
        │   ├── Item checkbox → toggle selection
        │   ├── Quantity stepper → increment/decrement
        │   └── Delete → remove from cart
        └── Checkout bar → CheckoutScreen
            ├── Address selection → AddressBookScreen (selection mode)
            ├── Payment method (GCash / Cash / Card)
            ├── Stock validation warnings
            └── "Place Order" → OrderConfirmationScreen
                ├── "Track My Order" → OrderTrackingScreen
                └── "Back to Home" → pop to root
```

---

## 4. Screen Reference

### 4.1 CustomerShell (`customer_shell.dart`)

**Purpose:** Root container with bottom navigation. Uses `IndexedStack` to preserve screen state across tab switches.

| Property | Value |
|----------|-------|
| Tabs | 4 (Home, Store, Notifications, Profile) |
| State preservation | `IndexedStack` |
| Cart access | `CartIconButton` in AppBar actions |

**Note:** Cart and Inbox are NOT tabs — they are pushed via navigation.

### 4.2 CustomerHomeScreen (`customer_home_screen.dart`)

**Purpose:** Main landing screen. Shows featured products, categories, search, and a promotional banner.

| Feature | Implementation |
|---------|---------------|
| Search | `TextField` with debounced filtering via `ProductProvider.getFilteredProducts()` |
| Categories | Horizontal `ChoiceChip` row from `ProductProvider.categories` |
| Banner | Auto-scrolling `PageView` with 3 hardcoded Unsplash images (4s interval) |
| Product grid | `SliverMasonryGrid.count` with 2 columns, deterministic aspect ratios |
| Continue browsing | `SharedPreferences` remembers last visited store |
| Connectivity | Auto-refreshes products when connection restored |
| Push notifications | Wires up `onNavigateToChat` and `onWrongAccount` callbacks |
| Floating button | `FloatingMessageButton` with unread badge |

**Data source:** `ProductProvider.loadProducts()` → `ProductService.fetchProducts()`

### 4.3 ProductDetailScreen (`product_detail_screen.dart`)

**Purpose:** Full product detail with image carousel, size/color selectors, and add-to-cart.

| Feature | Implementation |
|---------|---------------|
| Image carousel | `PageView.builder` with dot indicators + counter badge |
| Full-screen viewer | `InteractiveViewer` with pinch-to-zoom |
| Size selector | `_buildSizesMap()` merges `inventory` + `product_variants` |
| Color selector | 4 hardcoded color swatches (Burnished Clay, Carob Dark, Off-White Suede, Saddle Brown) |
| Low stock label | Shows "Only X left" when stock ≤ 5 |
| Add to cart | `CartProvider.addToCart()` + `FlyToCartAnimation` |
| Buy Now | Calls `_addToCart()` (⚠️ BUG: doesn't navigate to checkout) |
| AR Try On | `SoleARPill` → `ARVirtualFitScreen` |
| Button animation | Scale-down/up on press via `AnimationController` |

**Size resolution (`_buildSizesMap()`):**
```
1. Read from inventory table (aggregated per size)
2. Read from product_variants table (per size+color)
3. Merge: take higher stock value if size exists in both
4. Sort numerically by EU size
```

### 4.4 CartScreen (`cart_screen.dart`)

**Purpose:** Shopping cart with per-store grouping, quantity controls, and checkout bar.

| Feature | Implementation |
|---------|---------------|
| Store grouping | `CartProvider.groupedByStore` — groups items by `store_id` |
| Select/deselect | Per-item, per-store, and "Select All" checkboxes |
| Indeterminate state | Store checkbox shows indeterminate when partially selected |
| Quantity stepper | +/- buttons with `incrementQuantity`/`decrementQuantity` |
| Delete | Bottom sheet confirmation dialog |
| Checkout bar | Sticky bottom bar with total, delivery fee, and checkout button |
| Refresh | Pull-to-refresh syncs from Supabase |

**Cart item structure:**
```dart
{
  'id': 'productId-size-color',  // Composite key
  'productId': String,
  'productName': String,
  'imageUrl': String,
  'price': double,         // base price + additionalPrice
  'size': String,
  'color': String,
  'quantity': int,
  'storeId': String?,
  'storeName': String?,
  'variantId': String?,
  'additionalPrice': double,
}
```

### 4.5 CheckoutScreen (`checkout_screen.dart`)

**Purpose:** Order placement with address selection, payment method, and stock validation.

| Feature | Implementation |
|---------|---------------|
| Address selection | Auto-selects default address; tap to change via `AddressBookScreen` |
| Payment methods | GCash (default), Cash, Card (disabled) |
| Stock validation | `_validateCart()` checks live inventory on load and before submission |
| Out-of-stock warnings | Shows banners for unavailable items; blocks checkout |
| Insufficient stock | Shows warning; blocks checkout |
| Order submission | `OrderProvider.placeOrder()` → `SupabaseService.createOrder()` |
| Confirmation | Shows order ID, total, with "Track My Order" and "Back to Home" buttons |

**Validation flow:**
```
1. _validateCart() called on screen load
   → CartService.validateForCheckout()
   → Fetches live inventory for each cart item
   → Returns availability + stock info per item

2. _canSubmitOrder() checks:
   → selectedItems is not empty
   → Not currently validating
   → Address is selected
   → All items are available with sufficient stock

3. _submitCheckout() called on button tap
   → Re-validates stock (race condition protection)
   → Validates form
   → Calls OrderProvider.placeOrder()
   → On success: clears cart, shows confirmation
   → On failure: shows StockUnavailableException message
```

### 4.6 MyOrdersScreen (`my_orders_screen.dart`)

**Purpose:** Order history with tab-based status filtering.

| Tab | Filter |
|-----|--------|
| All orders | No filter |
| Unpaid | `payment_status != 'paid'` |
| Processing | `status IN ('pending', 'placed', 'preparing')` |
| Shipped | `status = 'ready'` |
| Review | `status = 'received'` |
| Returns | (Not implemented — empty) |

**Features:**
- Tab bar with scrollable tabs
- Pull-to-refresh
- Connectivity-aware (shows retry on offline)
- Shimmer loading skeletons
- Order card shows: order ID, status chip, product thumbnail, name, size, quantity, date, total
- Promo banner for SMS opt-in (stub)
- Deep-linking via `initialFilter` parameter

### 4.7 OrderTrackingScreen (`tracking_screen.dart`)

**Purpose:** Order status timeline visualization.

| Feature | Status |
|---------|--------|
| Timeline | Uses `SoleTimeline` widget with 4 steps |
| Status mapping | Maps status string to active index |
| Order details | Shows size and total |

⚠️ **BUGS:**
- Hardcoded dummy data (dates, store name)
- Reads `order['size']` which doesn't exist on order objects
- Casts `total_amount` as `double` without null safety

### 4.8 AddressBookScreen (`address_book_screen.dart`)

**Purpose:** Manage saved delivery addresses.

| Feature | Implementation |
|---------|---------------|
| List addresses | `AddressProvider.loadAddresses()` |
| Add address | Navigate to `AddEditAddressScreen` |
| Edit address | Navigate to `AddEditAddressScreen(existingAddress:)` |
| Delete address | Confirmation dialog → `AddressProvider.deleteAddress()` |
| Set default | `AddressProvider.setDefaultAddress()` |
| Selection mode | `selectionMode: true` — tap to select and pop with result |

### 4.9 AddEditAddressScreen (`add_edit_address_screen.dart`)

**Purpose:** Add or edit a delivery address with map pin-drop.

| Step | Description |
|------|-------------|
| Step A: Map | Full-screen map with center pin, GPS auto-locate, search bar |
| Step B: Form | Address details form (recipient, phone, region, province, city, barangay, street, landmark) |

**Map features:**
- MapTiler tiles via `flutter_map`
- GPS auto-locate on open (with permission handling)
- "My Location" button for manual recenter
- Search bar with MapTiler geocoding API (debounced, 350ms)
- Prediction dropdown with place selection
- Reverse geocoding to pre-fill form fields
- Friendly error messages for permission denied / location off

**Form fields:**
- Label (Home/Work/Other)
- Recipient name
- Phone number
- Region, Province, City/Municipality, Barangay
- Street address
- Landmark (optional)
- Set as default toggle

### 4.10 ARVirtualFitScreen (`ar_fitting_screen.dart`)

**Purpose:** AR virtual shoe fitting (PLACEHOLDER — no real AR).

| Feature | Implementation |
|---------|---------------|
| Camera feed | `ARViewPlaceholder` widget (static background) |
| Product switcher | Horizontal list of product thumbnails |
| Size selector | Compact chip row |
| Stock checker | Bottom sheet showing size availability |
| Add to cart | `CartProvider.addToCart()` with variant lookup |
| Tutorial | First-time overlay with 3-step guide |
| Animations | Pulse tracking dot, particle scatter effect |

⚠️ **BUG:** Reads `product['sizes']` which doesn't exist. Falls back to hardcoded product data.

### 4.11 CustomizationScreen (`customization_screen.dart`)

**Purpose:** 5-step stepper for custom shoe orders.

| Step | Content |
|------|---------|
| 1. Base Design | Choose from 3 hardcoded shoe models (Oxford, Loafer, Boot) |
| 2. Color & Dye | 6 color options in a grid |
| 3. Material | 3 material options (Calfskin, Suede, Canvas) |
| 4. Special Request | Free-text input for personalization notes |
| 5. Review | Summary card with selections |

**Submission:** `OrderProvider.submitCustomization()` → inserts into `customization_requests` table.

⚠️ **Issue:** No store selector — doesn't know which store to send the request to.

### 4.12 CustomerInboxScreen (`customer_inbox_screen.dart`)

**Purpose:** List of conversations with stores.

| Feature | Implementation |
|---------|---------------|
| Conversation list | `MessageProvider.loadConversationsForCustomer()` |
| Realtime updates | `MessageProvider.subscribeToInbox()` |
| Unread indicator | Blue dot + bold text for unread conversations |
| Tap to chat | Navigate to `ChatView` with `viewerRole: 'customer'` |
| Empty state | "No messages yet" with guidance text |
| Connectivity | Auto-refresh on connection restore |

---

## 5. Data Flow Diagrams

### 5.1 Browse Products → Add to Cart → Checkout → Order

```
┌─────────────────────────────────────────────────────────────┐
│                    BROWSE PRODUCTS                           │
│                                                             │
│  CustomerHomeScreen                                         │
│       │                                                     │
│       ├── Search: TextField → ProductProvider.getFilteredProducts()
│       ├── Categories: ChoiceChip → ProductProvider.selectCategory()
│       └── Product card tap → ProductDetailScreen             │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│                    PRODUCT DETAIL                            │
│                                                             │
│  ProductDetailScreen                                        │
│       │                                                     │
│       ├── _buildSizesMap()                                  │
│       │    ├── Read inventory table (aggregated per size)   │
│       │    ├── Read product_variants (per size+color)       │
│       │    └── Merge: take higher stock, sort numerically   │
│       │                                                     │
│       ├── _addToCart()                                      │
│       │    ├── resolveVariant() → variantId + additionalPrice│
│       │    ├── CartProvider.addToCart()                      │
│       │    │    ├── Local: add to _items{} map              │
│       │    │    └── Background: CartService.syncToServer()  │
│       │    └── FlyToCartAnimation.show()                    │
│       │                                                     │
│       └── "Buy Now" → _addToCart()                          │
│            └── ⚠️ Should navigate to CheckoutScreen         │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│                    CART                                      │
│                                                             │
│  CartScreen                                                 │
│       │                                                     │
│       ├── Display: grouped by store                         │
│       ├── Quantity: increment/decrement                     │
│       ├── Selection: per-item, per-store, all               │
│       └── Checkout bar → CheckoutScreen                     │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│                    CHECKOUT                                  │
│                                                             │
│  CheckoutScreen                                             │
│       │                                                     │
│       ├── _loadAddress() → AddressProvider.loadAddresses()  │
│       ├── _validateCart() → CartService.validateForCheckout()│
│       │    └── Checks live inventory for each cart item     │
│       │                                                     │
│       ├── _submitCheckout()                                 │
│       │    ├── Re-validate stock                            │
│       │    ├── Validate form                                │
│       │    ├── OrderProvider.placeOrder()                    │
│       │    │    └── SupabaseService.createOrder()            │
│       │    │         ├── INSERT INTO orders                  │
│       │    │         ├── INSERT INTO order_items (per item)  │
│       │    │         ├── DB trigger → decrement inventory    │
│       │    │         └── On failure → StockUnavailableExcept.│
│       │    │                                                 │
│       │    └── On success: clear cart, show confirmation     │
│       │                                                     │
│       └── Confirmation screen                               │
│            ├── "Track My Order" → OrderTrackingScreen        │
│            └── "Back to Home" → pop to root                  │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 5.2 Messaging Flow

```
┌─────────────────────────────────────────────────────────────┐
│                    CUSTOMER MESSAGING                        │
│                                                             │
│  CustomerInboxScreen                                        │
│       │                                                     │
│       ├── Load: MessageProvider.loadConversationsForCustomer()│
│       ├── Subscribe: MessageProvider.subscribeToInbox()      │
│       │    └── Supabase Realtime on conversations table     │
│       └── Tap conversation → ChatView                       │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│                    CHAT VIEW                                 │
│                                                             │
│  ChatView(conversationId, viewerRole: 'customer')           │
│       │                                                     │
│       ├── _loadMessages()                                   │
│       │    └── MessageService.getMessages()                  │
│       │                                                     │
│       ├── _subscribeToMessages()                            │
│       │    └── MessageService.subscribeToConversation()      │
│       │         └── Supabase Realtime .stream() on messages │
│       │                                                     │
│       ├── _sendMessage()                                    │
│       │    ├── Generate client-side UUID                     │
│       │    ├── Insert optimistic placeholder (isSending=true)│
│       │    ├── MessageService.sendMessage()                  │
│       │    │    ├── INSERT INTO messages                     │
│       │    │    ├── UPDATE conversations (last_message_at)   │
│       │    │    └── _createMessageNotification()             │
│       │    │         ├── SellerNotificationService (in-app) │
│       │    │         └── _triggerPushNotification()          │
│       │    │              └── Edge Function → FCM            │
│       │    └── On success: replace placeholder               │
│       │         On failure: mark as sendFailed               │
│       │                                                     │
│       ├── _subscribeToTyping()                              │
│       │    └── Supabase Broadcast Channel                    │
│       │                                                     │
│       └── Read receipts                                     │
│            └── markConversationRead() → is_read = true       │
│                 └── Realtime UPDATE → ✓✓ appears             │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 5.3 Address Management Flow

```
┌─────────────────────────────────────────────────────────────┐
│                    ADDRESS FLOW                              │
│                                                             │
│  AddressBookScreen                                          │
│       │                                                     │
│       ├── Load: AddressProvider.loadAddresses()              │
│       ├── Add → AddEditAddressScreen                        │
│       │    │                                                 │
│       │    ├── Step A: Map Pin-Drop                         │
│       │    │    ├── GPS auto-locate on open                  │
│       │    │    ├── Search bar (MapTiler geocoding)          │
│       │    │    ├── Prediction dropdown                      │
│       │    │    ├── Reverse geocoding → pre-fill form        │
│       │    │    └── "Confirm Location" → Step B              │
│       │    │                                                 │
│       │    └── Step B: Address Form                         │
│       │         ├── Recipient name + phone                   │
│       │         ├── Region, Province, City, Barangay         │
│       │         ├── Street + Landmark                        │
│       │         ├── Label (Home/Work/Other)                  │
│       │         ├── Set as default toggle                    │
│       │         └── "Save" → AddressProvider.addAddress()    │
│       │                                                     │
│       ├── Edit → AddEditAddressScreen(existingAddress)       │
│       ├── Delete → confirmation → AddressProvider.delete()   │
│       └── Set Default → AddressProvider.setDefault()         │
│                                                             │
│  Checkout Screen (selection mode)                           │
│       └── AddressBookScreen(selectionMode: true)            │
│            └── Tap address → pops with Address result       │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## 6. State Management

### Provider Architecture

| Provider | Scope | Key State | Key Methods |
|----------|-------|-----------|-------------|
| `AuthProvider` | App-wide | `_currentUser`, `_profile`, `_isLoading`, `_errorMessage` | `login()`, `logout()`, `signUp()` |
| `ProductProvider` | Product browsing | `_products[]`, `_selectedCategory`, `categories` | `loadProducts()`, `selectCategory()`, `getFilteredProducts()` |
| `CartProvider` | Shopping cart | `_items{}`, `_selectedKeys`, `subtotal`, `deliveryFee` | `addToCart()`, `removeFromCart()`, `incrementQuantity()`, `validateForCheckout()` |
| `OrderProvider` | Orders | `_orders[]`, `_myOrders[]`, `_stockError` | `placeOrder()`, `loadMyOrders()`, `setMyOrdersFilter()` |
| `AddressProvider` | Addresses | `_addresses[]`, `_selectedAddress` | `loadAddresses()`, `addAddress()`, `updateAddress()`, `deleteAddress()` |
| `MessageProvider` | Messaging | `_conversations[]`, `_unreadCounts{}` | `loadConversationsForCustomer()`, `subscribeToInbox()` |
| `NotificationProvider` | Notifications | `_notifications[]`, `_unreadCount` | `loadNotifications()` |
| `ChatAttachmentProvider` | Failed messages | `_failedMessages{}` | `addFailedMessage()`, `mergeWithFailed()` |

### Cart State Details

```dart
class CartProvider {
  // Items keyed by "productId-size-color"
  Map<String, CartItem> _items = {};
  
  // Selection state
  Set<String> _selectedKeys = {};
  
  // Computed properties
  double get subtotal;          // Sum of selected item prices × quantities
  double get selectedTotal;     // subtotal + deliveryFee
  double get selectedDeliveryFee; // ₱100 flat if items selected
  int get selectedCount;        // Number of selected items
  bool get allSelected;         // Are all items selected?
  List<Map<String, dynamic>> get groupedByStore; // Items grouped by store_id
  
  // Methods
  void addToCart({...});        // Add item + background sync
  void removeFromCart(key);     // Remove item + background sync
  void incrementQuantity(key);  // +1 quantity + background sync
  void decrementQuantity(key);  // -1 quantity (removes if 0)
  void toggleItem(key);         // Toggle single item selection
  void toggleStore(storeId);    // Toggle all items in a store
  void toggleAll();             // Toggle all items
  void selectAll();             // Select all items
  Future refreshFromServer();   // Re-fetch cart from Supabase
  Future validateForCheckout(); // Check live inventory for all items
}
```

---

## 7. Services Layer

### Service Dependency Graph

```
ProductService ──→ Supabase (products, inventory, product_variants, product_images)
CartService ────→ Supabase (cart_items, products, inventory, product_variants)
OrderService ───→ SupabaseService.createOrder()
AddressService ─→ Supabase (customer_addresses)
MessageService ─→ Supabase (conversations, messages, profiles, stores)
                  + Edge Functions (send-message-push)
ConnectivityService → connectivity_plus package
StoreService ───→ Supabase (stores, store_follows, story_entries)
PushNotificationService → Firebase Messaging + flutter_local_notifications
```

### Key Service Methods (Customer-Relevant)

#### ProductService

| Method | Purpose | Returns |
|--------|---------|---------|
| `fetchProducts()` | Fetch all active products with relations | `List<Map>` |
| `getProduct(id)` | Single product with inventory + variants | `Map` |

#### CartService

| Method | Purpose | Returns |
|--------|---------|---------|
| `fetchCart()` | Fetch user's cart with product details | `List<CartItem>` |
| `addToCart()` | Insert cart item to Supabase | `void` |
| `removeFromCart()` | Delete cart item from Supabase | `void` |
| `updateQuantity()` | Update quantity in Supabase | `void` |
| `validateForCheckout()` | Check live inventory for all cart items | `List<ValidationResult>` |

#### OrderService

| Method | Purpose | Returns |
|--------|---------|---------|
| `placeOrder()` | Delegate to SupabaseService.createOrder() | `Map` (order) |
| `loadMyOrders()` | Fetch customer's orders with items | `List<Map>` |

#### AddressService

| Method | Purpose | Returns |
|--------|---------|---------|
| `fetchAddresses()` | Get all addresses for user | `List<Address>` |
| `addAddress()` | Insert new address | `Address` |
| `updateAddress()` | Update existing address | `Address` |
| `deleteAddress()` | Remove address | `void` |
| `setDefaultAddress()` | Set default address | `void` |

#### MessageService

| Method | Purpose | Returns |
|--------|---------|---------|
| `getOrCreateConversation()` | Find or create conversation | `Conversation` |
| `getMessages()` | Fetch messages (oldest first) | `List<Message>` |
| `sendMessage()` | Insert message + update conversation + trigger push | `Message` |
| `uploadAttachment()` | Chunked file upload with progress | `String` (URL) |
| `subscribeToConversation()` | Realtime subscription for messages | `StreamSubscription` |
| `subscribeToInbox()` | Realtime subscription for conversations | `StreamSubscription` |
| `markConversationRead()` | Mark other party's messages as read | `void` |

---

## 8. Widgets Reference

### Customer-Specific Widgets

| Widget | File | Purpose |
|--------|------|---------|
| `SoleProductCard` | `lib/widgets/sole_product_card.dart` | Product card for masonry grid with image, price, badges |
| `CartIconButton` | `lib/widgets/cart_icon_button.dart` | AppBar cart icon with badge count |
| `FloatingMessageButton` | `lib/widgets/floating_message_button.dart` | FAB with unread message badge |
| `FlyToCartAnimation` | `lib/widgets/fly_to_cart_animation.dart` | Overlay animation from product image to cart icon |
| `SoleARPill` | `lib/widgets/sole_ar_pill.dart` | "Virtual Try-On" floating pill |
| `MessagesQuickPreviewSheet` | `lib/widgets/messages_quick_preview_sheet.dart` | Quick preview of recent messages |
| `ArViewPlaceholder` | `lib/widgets/ar_view_placeholder.dart` | Static AR camera placeholder |

### Shared Widgets (Used by Customer)

| Widget | File | Purpose |
|--------|------|---------|
| `SoleCard` | `lib/widgets/sole_card.dart` | Branded card with shadow |
| `SolePrimaryButton` | `lib/widgets/sole_primary_button.dart` | Primary action button |
| `SoleTextField` | `lib/widgets/sole_text_field.dart` | Styled text input |
| `SoleBottomNav` | `lib/widgets/sole_bottom_nav.dart` | Bottom navigation bar |
| `SoleBadge` | `lib/widgets/sole_badge.dart` | Small label badge |
| `SoleStatusChip` | `lib/widgets/sole_status_chip.dart` | Order status chip |
| `SoleTimeline` | `lib/widgets/sole_timeline.dart` | Vertical timeline for order tracking |
| `ShimmerBox` | `lib/widgets/shimmer_box.dart` | Loading skeleton placeholder |
| `EmptyStateWidget` | `lib/widgets/empty_state_widget.dart` | Empty state with icon + text |
| `ErrorRetryWidget` | `lib/widgets/error_retry_widget.dart` | Error state with retry button |
| `NoInternetView` | `lib/widgets/no_internet_view.dart` | Offline state with retry |
| `ConnectivityBanner` | `lib/widgets/connectivity_banner.dart` | Top banner for connectivity status |
| `ChatView` | `lib/widgets/chat/chat_view.dart` | Shared chat UI (both roles) |

---

## 9. Data Models

### Address Model (`lib/models/address_model.dart`)

```dart
class Address {
  final String? id;
  final String userId;
  final String label;          // 'Home', 'Work', 'Other'
  final String recipientName;
  final String recipientPhone;
  final String region;
  final String province;
  final String cityMunicipality;
  final String barangay;
  final String streetAddress;
  final String? landmark;
  final double latitude;
  final double longitude;
  final bool isDefault;

  String get formattedAddress;  // Computed: full address string
}
```

### CartItem (from `lib/models/cart_item_with_details.dart`)

```dart
class CartItemWithDetails {
  final String cartItemId;
  final String productId;
  final String productName;
  final String? imageUrl;
  final double price;
  final String size;
  final String color;
  final int quantity;
  final String? storeId;
  final String? storeName;
  final String? variantId;
  final double additionalPrice;
  final int currentStock;      // From inventory (authoritative)
  final bool isActive;
}
```

### Message (from `lib/services/message_service.dart`)

```dart
class Message {
  // DB-persisted
  final String id;              // Client-generated UUID
  final String conversationId;
  final String senderId;
  final String senderType;      // 'customer' | 'seller'
  final String? body;
  final bool isRead;
  final DateTime createdAt;
  final String? attachmentUrl;
  final String? attachmentType; // 'image' | 'video'

  // Local-only (not persisted)
  final bool isSending;
  final bool sendFailed;
  final File? localFile;
  final double progress;        // 0.0–1.0
}
```

### Conversation (from `lib/services/message_service.dart`)

```dart
class Conversation {
  final String id;
  final String storeId;
  final String customerId;
  final DateTime? lastMessageAt;
  final String? lastMessagePreview;
  final String? customerName;   // Denormalized via DB trigger
  final String? storeName;      // Joined from stores table
  final int unreadCount;
}
```

---

## 10. Database Queries

### Fetch Products (with all relations)
```sql
SELECT *, 
  stores(name),
  product_images(image_url, display_order),
  inventory(size, stock),
  product_variants(*)
FROM products
WHERE is_active = true
ORDER BY created_at DESC;
```

### Fetch Cart Items
```sql
SELECT *,
  products(name, price, store_id, stores(name))
FROM cart_items
WHERE user_id = auth.uid()
ORDER BY created_at DESC;
```

### Place Order
```sql
-- 1. Insert order
INSERT INTO orders (customer_id, store_id, status, total_amount, payment_method, payment_status)
VALUES (?, ?, 'pending', ?, ?, 'paid')
RETURNING *;

-- 2. Insert order items (triggers handle inventory)
INSERT INTO order_items (order_id, product_id, size, quantity, unit_price)
VALUES (?, ?, ?, ?, ?);

-- DB trigger: decrement_inventory_on_order() fires on INSERT
```

### Fetch Customer Orders
```sql
SELECT *, order_items(*, products(name, product_images(image_url, display_order)))
FROM orders
WHERE customer_id = auth.uid()
ORDER BY created_at DESC;
```

### Fetch Conversations (Customer)
```sql
SELECT *, stores(name)
FROM conversations
WHERE customer_id = auth.uid()
ORDER BY last_message_at DESC NULLS FIRST;
```

### Fetch Messages
```sql
SELECT *
FROM messages
WHERE conversation_id = ?
ORDER BY created_at ASC;
```

### Fetch Addresses
```sql
SELECT *
FROM customer_addresses
WHERE user_id = auth.uid()
ORDER BY is_default DESC, created_at DESC;
```

---

## 11. Feature Status & Audit

### ✅ Fully Working

| Feature | Screen | Quality |
|---------|--------|---------|
| Product browsing with search & categories | CustomerHomeScreen | ⭐⭐⭐⭐ |
| Product detail with image carousel | ProductDetailScreen | ⭐⭐⭐⭐ |
| Size selector with stock display | ProductDetailScreen | ⭐⭐⭐⭐ |
| Add to cart with animation | ProductDetailScreen | ⭐⭐⭐⭐ |
| Cart management with store grouping | CartScreen | ⭐⭐⭐⭐ |
| Checkout with address & payment | CheckoutScreen | ⭐⭐⭐⭐ |
| Address CRUD with map pin-drop | AddressBookScreen + AddEditAddressScreen | ⭐⭐⭐⭐⭐ |
| GPS auto-locate & search | AddEditAddressScreen | ⭐⭐⭐⭐ |
| Order history with tab filtering | MyOrdersScreen | ⭐⭐⭐⭐ |
| Real-time messaging | ChatView | ⭐⭐⭐⭐⭐ |
| Read receipts & typing indicators | ChatView | ⭐⭐⭐⭐⭐ |
| Push notifications (messages) | PushNotificationService | ⭐⭐⭐⭐ |
| Connectivity handling | ConnectivityService | ⭐⭐⭐⭐ |

### ⚠️ Partially Working / Has Bugs

| Feature | Screen | Issue |
|---------|--------|-------|
| Buy Now button | ProductDetailScreen | Doesn't navigate to checkout |
| Order tracking timeline | OrderTrackingScreen | Hardcoded dummy data, type cast bugs |
| AR fitting | ARVirtualFitScreen | Reads non-existent `product['sizes']` field |
| Custom shoe orders | CustomizationScreen | No store selector |
| SMS opt-in | MyOrdersScreen | Stub — shows "coming soon" |

### ❌ Missing Features

| Feature | Priority | Notes |
|---------|----------|-------|
| Cart tab in bottom nav | High | Cart only accessible via AppBar icon |
| Inbox tab in bottom nav | High | Messages only via floating button |
| Order cancellation | High | RLS policy exists but no UI |
| Product reviews/ratings | Medium | No reviews section |
| Wishlist/favorites | Medium | No save-for-later |
| Share product | Medium | No share button |
| Size guide | Low | No help for EU sizing |
| Recently viewed products | Low | No history tracking |

---

## 12. Known Issues & Bugs

### 🔴 Critical

| # | Issue | File | Line | Impact |
|---|-------|------|------|--------|
| 1 | `_buyNow()` doesn't navigate to checkout | `product_detail_screen.dart` | `_buyNow()` | "Buy Now" button is non-functional |
| 2 | `tracking_screen.dart` reads `order['size']` | `tracking_screen.dart` | Line ~30 | Order objects don't have `size` — crashes |
| 3 | `tracking_screen.dart` casts `total_amount as double` | `tracking_screen.dart` | Line ~40 | Supabase returns `int` for whole numbers — crashes |
| 4 | `ar_fitting_screen.dart` reads `product['sizes']` | `ar_fitting_screen.dart` | Multiple | Field doesn't exist — size selector broken |

### 🟡 Medium

| # | Issue | File | Impact |
|---|-------|------|--------|
| 5 | No Cart/Inbox tab in bottom nav | `customer_shell.dart` | Poor discoverability |
| 6 | SMS opt-in is a stub | `my_orders_screen.dart` | Confusing "coming soon" |
| 7 | Banner uses hardcoded Unsplash URLs | `customer_home_screen.dart` | Could break |
| 8 | Customization has no store selector | `customization_screen.dart` | Order goes nowhere |

### 🟢 Low

| # | Issue | File | Impact |
|---|-------|------|--------|
| 9 | `withOpacity()` deprecation warnings | Multiple | Code quality |
| 10 | No pull-to-refresh on product detail | `product_detail_screen.dart` | Minor UX |
| 11 | AR is fully placeholder | `ar_fitting_screen.dart` | Misleading "Try On" button |

---

## 13. Critical Issues to Fix

### Fix 1: `_buyNow()` Navigation

**Current code:**
```dart
void _buyNow() {
  _addToCart();
  Future.delayed(const Duration(milliseconds: 1200), () {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Processing checkout...')),
    );
  });
}
```

**Fix:**
```dart
void _buyNow() {
  _addToCart();
  Future.delayed(const Duration(milliseconds: 1200), () {
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CheckoutScreen()),
    );
  });
}
```

### Fix 2: Tracking Screen

**Issues:**
- Hardcoded timeline dates and store name
- `order['size']` doesn't exist (should read from `order_items`)
- `order['total_amount'] as double` unsafe cast

**Fix:** Read from `order_items` for size/product info, use `(order['total_amount'] as num?)?.toDouble()`, and compute timeline dates from `order['created_at']` + status.

### Fix 3: AR Fitting Sizes

**Current:** Reads `_activeProduct['sizes']` (doesn't exist)

**Fix:** Read from `inventory` and `product_variants` like `ProductDetailScreen._buildSizesMap()` does.

---

## 14. Testing Checklist

### Product Browsing
- [ ] Products load on home screen
- [ ] Search filters products by name
- [ ] Category chips filter correctly
- [ ] Banner auto-scrolls
- [ ] "Continue Browsing" chip navigates to last store
- [ ] Pull-to-refresh reloads products
- [ ] Offline state shows retry view

### Product Detail
- [ ] Image carousel swipes correctly
- [ ] Full-screen image viewer opens on tap
- [ ] Size selector shows available sizes
- [ ] Low stock label shows "Only X left"
- [ ] Color selector changes selection
- [ ] "Add to Cart" shows animation + success state
- [ ] "Buy Now" navigates to checkout ⚠️ CURRENTLY BROKEN

### Cart
- [ ] Items grouped by store
- [ ] Store header tap navigates to store
- [ ] Item checkbox toggles selection
- [ ] Store checkbox toggles all items in store
- [ ] "Select All" / "Deselect All" works
- [ ] Quantity +/- updates correctly
- [ ] Delete removes item with confirmation
- [ ] Checkout bar shows correct total
- [ ] Pull-to-refresh syncs from server

### Checkout
- [ ] Default address auto-selected
- [ ] "Change Address" opens address book
- [ ] Payment method selection works
- [ ] Stock validation shows warnings
- [ ] "Place Order" creates order
- [ ] Confirmation screen shows order ID
- [ ] "Track My Order" navigates to tracking

### Address Management
- [ ] GPS auto-locates on map open
- [ ] Search bar returns predictions
- [ ] Prediction selection moves map
- [ ] Reverse geocoding fills form
- [ ] Form validation works
- [ ] Save creates address
- [ ] Edit loads existing data
- [ ] Delete removes with confirmation
- [ ] Set default updates correctly

### Messaging
- [ ] Inbox loads conversations
- [ ] Unread indicator shows correctly
- [ ] Tap opens ChatView
- [ ] Messages appear in correct order
- [ ] Send message appears immediately (optimistic)
- [ ] Read receipts update live
- [ ] Typing indicator shows
- [ ] Image attachment uploads with progress
- [ ] Failed message shows retry option

### Order Tracking
- [ ] Timeline shows correct active step
- [ ] Order details display correctly ⚠️ CURRENTLY BROKEN
- [ ] Back navigation works

---

*SoleVision Customer Module Documentation v1.0.0 — July 16, 2026*
