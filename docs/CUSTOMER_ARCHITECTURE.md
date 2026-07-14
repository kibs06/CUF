# SoleVision — Customer Module Architecture

**Last Updated:** July 14, 2026  
**Purpose:** Comprehensive reference for AI agents working on the Customer side of SoleVision.

---

## Quick Summary

The Customer module is the consumer-facing side of SoleVision — an artisan leather footwear e-commerce app built with Flutter + Supabase. Customers browse products, try them on in AR, customize shoes, manage a cart with store-grouped items, checkout with address selection, track orders, message sellers, and receive notifications. The shell has 4 tabs: Home, Store, Notifications, Profile.

---

## Customer Shell Architecture

### Navigation Structure

```
CustomerShell (4-tab bottom navigation via SoleBottomNav)
├── Tab 0: CustomerHomeScreen    → Product catalog, search, categories, banners
├── Tab 1: StoreScreen           → Store listings / store profiles
├── Tab 2: NotificationsScreen   → Order update notifications with tabs (All/Catalog/Custom)
└── Tab 3: ProfileScreen         → Account settings, order history, addresses, messaging
```

### Sub-Screens (accessible from shell screens)

| Screen | Access From | Purpose |
|--------|-------------|---------|
| `ProductDetailScreen` | Home → product card tap | Product detail with image carousel, size/color selector, Add to Cart / Buy Now |
| `ARVirtualFitScreen` | Home → "Try On" badge, ProductDetail → AR pill | Simulated AR virtual fitting with shoe overlay, size picker, add to cart |
| `CustomizationScreen` | Profile or Store | 5-step Stepper wizard for custom shoe orders (base design → color → material → engraving → review) |
| `CartScreen` | AppBar cart icon, ProductDetail → Buy Now | Cart with store-grouped items, selection checkboxes, quantity steppers |
| `CheckoutScreen` | Cart → Check Out | Order summary, delivery address, payment method, price breakdown, stock validation |
| `AddressBookScreen` | Profile → My Addresses, Checkout → Deliver To | CRUD for delivery addresses with map pin-drop, selection mode for checkout |
| `AddEditAddressScreen` | AddressBook → Add/Edit | MapTiler-powered map for pin-drop address entry with GPS reverse geocoding |
| `MyOrdersScreen` | Profile → My Orders | Tab-filtered order list (All/Unpaid/Processing/Shipped/Review/Returns) |
| `OrderTrackingScreen` | MyOrders → order card tap, Notifications → tap | Vertical timeline showing order progress |
| `CustomerInboxScreen` | Profile → Messages | Conversation list with stores, unread badges |
| `ChatView` | Inbox → conversation tap | Real-time chat with messages, attachments, typing indicators, read receipts |

---

## Data Flow Diagrams

### Browse → Add to Cart → Checkout Flow

```
CustomerHomeScreen
  │
  ├─→ ProductProvider.loadProducts()
  │    └─→ SupabaseService.fetchProducts()
  │         └─→ SELECT products + stores + product_images + inventory + product_variants
  │
  ├─→ Product card tap → ProductDetailScreen(product)
  │    ├─→ _buildSizesMap() merges inventory + product_variants stock
  │    ├─→ Size selector (EU sizing, low stock badges, strikethrough for out-of-stock)
  │    ├─→ Color swatch selector (4 leather options)
  │    │
  │    ├─→ "Add to Cart" → CartProvider.addToCart()
  │    │    ├─→ Optimistic local update (Map + SharedPreferences cache)
  │    │    ├─→ FlyToCartAnimation overlay
  │    │    └─→ Background: CartService.addOrUpdateItem() → Supabase cart_items
  │    │
  │    └─→ "Try On" → ARVirtualFitScreen
  │         ├─→ ARViewPlaceholder (camera feed simulation)
  │         ├─→ Shoe overlay with size/color selection
  │         └─→ Add to Cart from AR screen
  │
  ├─→ CartIconButton (AppBar) → CartScreen
  │    ├─→ Cart items grouped by store
  │    ├─→ Selection checkboxes (per-item, per-store, select all)
  │    ├─→ Quantity steppers (+/-)
  │    └─→ Sticky checkout bar with total
  │
  └─→ Checkout → CheckoutScreen
       ├─→ _validateCart() → CartService.validateCartForCheckout()
       │    └─→ Re-fetches live price + stock per item
       │         └─→ Shows banners: out-of-stock, insufficient stock, price changed
       ├─→ AddressBookScreen → pick delivery address (required)
       ├─→ Payment method selection (GCash, Cash on Pickup, Card)
       ├─→ "Complete Order" → OrderProvider.placeOrder()
       │    ├─→ SupabaseService.createOrder()
       │    │    ├─→ INSERT INTO orders
       │    │    ├─→ INSERT INTO order_items (triggers inventory decrement)
       │    │    └─→ Stock check → StockUnavailableException on failure
       │    ├─→ CartProvider.removeServerItems() (ordered items only)
       │    └─→ SellerNotificationService.createNewOrder() (fire-and-forget)
       └─→ Confirmation screen with order ID + "Track My Order" button
```

### Messaging Flow

```
CustomerInboxScreen
  │
  ├─→ MessageProvider.loadConversationsForCustomer(userId)
  │    └─→ MessageService.getConversationsForCustomer()
  │         └─→ SELECT conversations + stores(name)
  │
  ├─→ MessageProvider.subscribeToInbox(customerId: userId)
  │    └─→ MessageService.subscribeToInbox()
  │         └─→ _client.from('conversations').stream(primaryKey: ['id'])
  │              .eq('customer_id', userId)
  │              .listen → reload conversations
  │
  └─→ Conversation tap → ChatView(conversationId, viewerRole: 'customer')
       ├─→ _loadMessages() → MessageService.getMessages()
       │    └─→ SELECT messages WHERE conversation_id = ? ORDER BY created_at ASC
       │
       ├─→ _subscribeToMessages() → MessageService.subscribeToConversation()
       │    └─→ _client.from('messages').stream(primaryKey: ['id'])
       │         .eq('conversation_id', id)
       │         .order('created_at', ascending: true)
       │         .listen → replace _messages list (with merge logic for optimistic fields)
       │
       ├─→ _subscribeToTyping() → MessageService.subscribeToTyping()
       │    └─→ Broadcast channel: typing:$conversationId
       │         .onBroadcast('typing') → show/hide typing indicator
       │
       ├─→ _sendMessage() — Optimistic text send
       │    ├─→ Generate client-side UUID
       │    ├─→ Insert placeholder (isSending: true, isRead: false)
       │    ├─→ Background: MessageService.sendMessage()
       │    ├─→ On success: replace placeholder with server message
       │    └─→ On failure: mark as sendFailed with retry
       │
       ├─→ _sendAttachmentMessage() — Optimistic attachment send
       │    ├─→ Generate UUID, insert placeholder with localFile
       │    ├─→ MessageService.uploadAttachment() — chunked reads (1MB) with real progress
       │    │    ├─→ 0.0→0.85: File read phase (real byte-level progress)
       │    │    └─→ 0.85→1.0: uploadBinary() network phase
       │    ├─→ LinearProgressIndicator + percentage text on bubble
       │    ├─→ Generate video thumbnail if video
       │    ├─→ MessageService.sendMessage() with attachment URLs
       │    └─→ On failure: sendFailed state with retry overlay
       │
       ├─→ Read receipts: ✓ (sent) → ✓✓ (read) via realtime is_read updates
       │
       └─→ "New message ↓" pill when user scrolled up
```

### Notifications Flow

```
NotificationsScreen
  │
  ├─→ NotificationProvider (listens to auth state changes)
  │    └─→ On login: loadUnreadCounts() → NotificationService.fetchUnreadCounts()
  │
  ├─→ Tab: All / Catalog / Custom
  │    └─→ NotificationProvider.loadNotifications(categoryFilter, orderTypeFilter)
  │         └─→ NotificationService.fetchNotifications()
  │              └─→ SELECT notifications WHERE user_id = ? ORDER BY created_at DESC
  │
  ├─→ "Mark all read" → NotificationProvider.markAllAsRead()
  │    └─→ Optimistic: flip all locally, then background server write
  │
  └─→ Tap notification → markAsRead + fetch full order → OrderTrackingScreen
```

### Address Management Flow

```
AddressBookScreen
  │
  ├─→ AddressProvider.loadAddresses(userId)
  │    └─→ AddressService.getAddresses()
  │         └─→ SELECT customer_addresses WHERE user_id = ?
  │
  ├─→ Add/Edit → AddEditAddressScreen
  │    ├─→ MapTiler map with pin-drop
  │    ├─→ GPS reverse geocoding for address auto-fill
  │    ├─→ Address search via MapTiler Geocoding API
  │    └─→ AddressProvider.addAddress() / updateAddress()
  │
  └─→ Checkout integration:
       ├─→ CheckoutScreen auto-selects default address
       ├─→ "Change" → AddressBookScreen(selectionMode: true)
       └─→ Selected address snaps back to CheckoutScreen
```

---

## Provider Reference

### AuthProvider (`lib/providers/auth_provider.dart`)

| Property/Method | Purpose |
|----------------|---------|
| `currentUser` | Current Supabase User |
| `profile` | Profile row from `profiles` table |
| `userRole` | `'customer'` / `'seller'` / `'admin'` |
| `displayName` | User's full name |
| `login(email, password)` | Sign in via AuthService |
| `signUp(fullName, email, password, applyAsSeller)` | Register new account |
| `updateProfile(fullName, phone, avatarUrl)` | Edit profile |
| `resetPassword(email)` | Send reset email |
| `logout()` | Sign out + clear biometric credentials |

### CartProvider (`lib/providers/cart_provider.dart`)

**Three-layer persistence:** In-memory Map → SharedPreferences cache → Supabase `cart_items` table.

| Property/Method | Purpose |
|----------------|---------|
| `items` | Map of cart items keyed by `productId-size-color` |
| `selectedKeys` | Set of selected item keys for checkout |
| `groupedByStore` | Items grouped by `store_id` for store-section headers |
| `addToCart(...)` | Optimistic add + background Supabase sync |
| `incrementQuantity(key)` / `decrementQuantity(key)` | Quantity stepper |
| `removeFromCart(key)` | Remove item |
| `clearCart()` | Clear all (after order) |
| `removeServerItems(serverIds)` | Remove specific ordered items after checkout |
| `validateForCheckout()` | Re-fetch live price + stock for validation |
| `toggleItem(key)` / `toggleStore(storeId)` / `toggleAll()` | Selection checkboxes |
| `selectedItems` / `selectedTotal` | Computed from selection |
| `refreshFromServer()` | Pull-to-refresh sync |

### ProductProvider (`lib/providers/product_provider.dart`)

| Property/Method | Purpose |
|----------------|---------|
| `products` | All products from Supabase |
| `categories` | Derived category list |
| `selectedCategory` | Active category filter |
| `getFilteredProducts(keyword)` | Search + category filter |
| `loadProducts()` | Fetch from Supabase |

### OrderProvider (`lib/providers/order_provider.dart`)

| Property/Method | Purpose |
|----------------|---------|
| `placeOrder(customerId, items, totalAmount, ...)` | Create order via SupabaseService |
| `loadMyOrders()` | Fetch customer's orders |
| `setMyOrdersFilter(filter)` | Filter by status tab |
| `submitCustomization(...)` | Submit custom shoe request |

### AddressProvider (`lib/providers/address_provider.dart`)

| Property/Method | Purpose |
|----------------|---------|
| `addresses` | List of Address objects |
| `defaultAddress` | First address marked default |
| `selectedAddress` | Address selected for checkout |
| `loadAddresses(userId)` | Fetch from Supabase |
| `addAddress(address)` | Insert new address |
| `updateAddress(address)` | Update existing |
| `deleteAddress(id)` | Remove address |
| `setDefaultAddress(id, userId)` | Set as default |

### MessageProvider (`lib/providers/message_provider.dart`)

| Property/Method | Purpose |
|----------------|---------|
| `conversations` | List of Conversation objects |
| `unreadCount` / `unreadBadge` | Total unread conversations |
| `loadConversationsForCustomer(customerId)` | Fetch inbox |
| `subscribeToInbox(customerId:)` | Realtime inbox updates |
| `subscribeToConversation(conversationId)` | Realtime message updates |
| `sendMessage(...)` | Send text message |

### NotificationProvider (`lib/providers/notification_provider.dart`)

| Property/Method | Purpose |
|----------------|---------|
| `notifications` | List of AppNotification objects |
| `totalUnread` | Sum of unread across all categories |
| `unreadCounts` | Per-category unread map |
| `loadNotifications(categoryFilter, orderTypeFilter)` | Fetch notifications |
| `markAsRead(id)` | Optimistic mark single read |
| `markAllAsRead()` | Optimistic mark all read |

### ChatAttachmentProvider (`lib/providers/chat_attachment_provider.dart`)

| Property/Method | Purpose |
|----------------|---------|
| `addFailedMessage(message)` | Persist failed attachment for retry |
| `removeFailedMessage(conversationId, messageId)` | Remove after successful retry |
| `mergeWithFailed(dbMessages, conversationId)` | Merge failed into DB message list |

---

## Service Reference

### SupabaseService (`lib/services/supabase_service.dart`)

The core data access layer. All Supabase operations go through here (or through specialized services that wrap it).

| Method | Purpose |
|--------|---------|
| `login(email, password)` | Sign in + fetch profile |
| `signUp(fullName, email, password, applyAsSeller)` | Register + create profile |
| `getProfile(userId)` | Fetch profile with retry (up to 5 attempts) |
| `fetchProducts()` | All products with images, inventory, variants, store names |
| `createOrder(orderData)` | Create order + order_items with stock validation + rollback |
| `fetchOrders()` | All orders with customer/product joins |
| `createCustomization(data)` | Submit custom shoe request |

### CartService (`lib/services/cart_service.dart`)

| Method | Purpose |
|--------|---------|
| `fetchCart(userId)` | Full cart with joined product/variant data → `CartItemWithDetails` list |
| `addOrUpdateItem(userId, productId, variantId, quantity, ...)` | Upsert cart item |
| `updateQuantity(cartItemId, newQuantity)` | Set absolute quantity |
| `removeItem(cartItemId)` | Delete single item |
| `removeItems(userId, cartItemIds)` | Delete specific items (post-checkout) |
| `clearCart(userId)` | Delete all items |
| `validateCartForCheckout(userId, currentCartItems)` | Re-fetch live price + stock for validation |

### OrderService (`lib/services/order_service.dart`)

| Method | Purpose |
|--------|---------|
| `placeOrder(dto)` | Delegate to SupabaseService.createOrder() |
| `fetchStoreOrders(storeId, {status})` | Seller-side: 3-step chain (products → order_items → orders) |
| `fetchMyOrders()` | Customer-side: all orders with items joined |
| `getRecentOrders(storeId, limit)` | Last N orders for dashboard |
| `getOrderCountByStatus(storeId)` | Status breakdown for badges |
| `updateOrderStatus(orderId, newStatus)` | Status transition |

### MessageService (`lib/services/message_service.dart`)

| Method | Purpose |
|--------|---------|
| `getOrCreateConversation(storeId, customerId)` | Find or create conversation |
| `getConversationsForStore(storeId)` | Seller inbox |
| `getConversationsForCustomer(customerId)` | Customer inbox |
| `getMessages(conversationId, {limit})` | Fetch messages, oldest first |
| `sendMessage(id, conversationId, senderId, senderType, body, ...)` | Insert + update conversation + notify |
| `uploadAttachment(conversationId, messageId, filePath, mimeType, onProgress)` | Chunked read + uploadBinary with real progress |
| `generateVideoThumbnail(conversationId, messageId, videoPath)` | Generate + upload JPEG thumbnail |
| `markConversationRead(conversationId, readerType)` | Mark other party's messages as read |
| `subscribeToConversation(conversationId, onMessagesChanged)` | Realtime messages stream |
| `subscribeToInbox({storeId, customerId}, onUpdate)` | Realtime conversations stream |
| `sendTypingStart/Stop(...)` / `subscribeToTyping(...)` | Typing indicators via broadcast channels |

### AddressService (`lib/services/address_service.dart`)

| Method | Purpose |
|--------|---------|
| `getAddresses(userId)` | Fetch all addresses |
| `addAddress(address)` | Insert new address |
| `updateAddress(address)` | Update existing |
| `deleteAddress(id)` | Remove address |
| `setDefaultAddress(id, userId)` | Set default (unsets others) |

### NotificationService (`lib/services/notification_service.dart`)

| Method | Purpose |
|--------|---------|
| `fetchNotifications(userId, {categoryFilter, orderTypeFilter})` | Fetch notifications |
| `fetchUnreadCounts(userId)` | Per-category unread counts |
| `markAsRead(id)` | Mark single notification read |
| `markAllAsRead(userId)` | Mark all as read |

### ConnectivityService (`lib/services/connectivity_service.dart`)

| Property/Method | Purpose |
|----------------|---------|
| `isOnline` | Current connectivity state |
| `isOnlineStream` | Stream of connectivity changes |

Used by Home, MyOrders, Inbox, and ChatView to auto-refresh on reconnect.

---

## Key Widgets Reference

### SoleProductCard (`lib/widgets/sole_product_card.dart`)

- Displays product image with "Try On" AR badge overlay
- Deterministic aspect ratio per card (keyed off product ID for stable masonry)
- CachedNetworkImage with shimmer placeholder
- Tappable → ProductDetailScreen

### CartIconButton (`lib/widgets/cart_icon_button.dart`)

- AppBar shopping bag icon with animated badge
- Bounce animation when cart count increases
- Navigates to CartScreen on tap
- `iconKey` param for fly-to-cart overlay positioning

### SoleBottomNav (`lib/widgets/sole_bottom_nav.dart`)

- Role-aware NavigationBar (4 tabs for customer)
- customer: Home, Store, Notifications, Profile
- seller: Dashboard, Products, POS, Orders, Profile
- admin: Dashboard, Users, Requests, Monitor, Profile

### SoleCard, SolePrimaryButton, SoleBadge, SoleStatusChip, SoleTimeline

- Shared UI components used across customer and seller screens
- Styled with AppConstants design tokens

---

## Data Models

### Address (`lib/models/address_model.dart`)

```dart
class Address {
  final String? id;
  final String userId;
  final String label;            // 'Home', 'Work', etc.
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

  String get formattedAddress;   // Full address line
  String get shortAddress;       // Compact display
  Map<String, dynamic> toSnapshot();  // JSONB for orders table
}
```

### CartItemWithDetails (`lib/models/cart_item_with_details.dart`)

Bundles raw `cart_items` row with joined product/variant data:

```dart
class CartItemWithDetails {
  final String id;              // Supabase row ID
  final String productId;
  final String? variantId;
  final int quantity;
  final String productName;
  final String? imageUrl;
  final bool isActive;
  final String? storeId;
  final String? storeName;
  final double price;           // Base product price
  final String size;
  final String? color;
  final int stock;
  final double additionalPrice; // Variant surcharge

  double get unitPrice;         // price + additionalPrice
  double get lineTotal;         // unitPrice × quantity
  Map<String, dynamic> toCartItemMap();  // Legacy format for CartProvider
}
```

### CartValidationResult

Used during checkout validation:

```dart
class CartValidationResult {
  final String cartItemId;
  final String productName;
  final bool isAvailable;
  final double currentPrice;
  final int currentStock;
  final bool priceChanged;
  final double cartPrice;
  final int cartQuantity;
  final bool insufficientStock;
}
```

### Store (`lib/models/store.dart`)

```dart
class Store {
  final String id;
  final String name;
  final String? tagline;
  final String location;
  final String brandColor;       // hex string
  final String? bannerUrl;
  final String? logoUrl;
  final double rating;
  final bool isOpen;
  final bool isActive;

  Color get color;               // Parsed brand color
  String get initials;           // First 2 letters of name
}
```

### ProductVariant / ProductCustomization (`lib/models/product_models.dart`)

```dart
class ProductVariant {
  final String? id;
  final String size;
  final String? color;
  final int stock;
  final double additionalPrice;
  final String? sku;
}

class ProductCustomization {
  final String? id;
  final String optionName;
  final String optionType;       // 'text', 'select', 'color'
  final List<String> options;
  final bool isRequired;
  final double additionalPrice;
}
```

---

## Design System

### Color Palette (AppConstants)

| Token | Hex | Usage |
|-------|-----|-------|
| `primary` | `#8B5A2B` | Burnished Clay — brand color, CTAs, active states |
| `secondary` | `#3B2314` | Carob Dark — text, icons |
| `accent` | `#4ECDC4` | Celadon Teal — AR mode, highlights, badges |
| `surfaceLight` | `#F5F0EB` | Off-White Suede — backgrounds |
| `surfaceDark` | `#1A1208` | Midnight Canvas — AR overlay, dark surfaces |
| `success` | `#6B8F47` | Olive Stitch — success states |
| `error` | `#D64545` | Crimson Welt — errors, delete actions |
| `borderGray` | `#D2C7BC` | Borders, dividers |

### Typography

| Style | Font | Usage |
|-------|------|-------|
| `headlineStyle` | Playfair Display | Section headers, product names |
| `bodyStyle` | DM Sans | Body text, labels, buttons |
| `monoStyle` | JetBrains Mono | Prices, order IDs, codes |

### Visual Language

- Card radius: `16px` (`AppConstants.cardRadius`)
- Button radius: `12px` (`AppConstants.buttonRadius`)
- Warm shadow: `primary` at 8% opacity, 12px blur
- Noise overlay: Organic speckle texture at 2-3% opacity on surfaces
- Animations: Fly-to-cart overlay, bounce on cart icon, elastic scale on confirmation checkmark

---

## Supabase Tables Used (Customer Side)

| Table | Purpose |
|-------|---------|
| `profiles` | User accounts (id, full_name, email, role, seller_status, avatar_url, phone) |
| `products` | Product catalog (name, price, category, description, store_id, is_active, is_featured) |
| `product_images` | Product photos (product_id, image_url, display_order) |
| `product_variants` | Size/color/stock per variant (product_id, size, color, stock, additional_price) |
| `product_customizations` | Customization options per product |
| `inventory` | Aggregated stock per size (product_id, size, stock) — derived from variants |
| `stores` | Artisan stores (name, tagline, location, brand_color, banner_url, logo_url, owner_id) |
| `cart_items` | Shopping cart (user_id, product_id, variant_id, quantity, size, customizations) |
| `orders` | Order records (customer_id, store_id, status, total_amount, payment_method, shipping_address) |
| `order_items` | Line items (order_id, product_id, size, quantity, unit_price) |
| `customer_addresses` | Delivery addresses (user_id, label, recipient_name, region, province, city, barangay, etc.) |
| `conversations` | Chat conversations (store_id, customer_id, last_message_at, last_message_preview) |
| `messages` | Chat messages (conversation_id, sender_id, sender_type, body, is_read, attachment_url, etc.) |
| `notifications` | Customer notifications (user_id, category, title, message, is_read) |
| `customization_requests` | Custom shoe orders (customer_id, store_id, color_choice, material_choice, special_request, status) |

---

## Authentication & Routing

### AuthGate (`lib/screens/auth_gate.dart`)

The app's root widget. A `StreamBuilder<AuthState>` that:

1. **No session + first time** → OnboardingScreen
2. **No session + returning** → LoginScreen
3. **Session + loading** → Loading spinner
4. **Session + profile error** → ErrorRetryWidget (checks connectivity first)
5. **Session + profile loaded** → Route by role:
   - `role == 'customer'` → CustomerShell
   - `role == 'seller' && seller_status == 'approved'` → SellerShell
   - `seller_status == 'pending'` → PendingApprovalScreen
   - `role == 'admin'` → AdminShell

Session expiry mid-use triggers a non-dismissible bottom sheet.

### AuthService (`lib/services/auth_service.dart`)

- `signIn()` — force sign-out existing session first, then `signInWithPassword()`
- `signUp()` — create auth user + upsert profile row
- `getProfile()` — retry up to 5 times (trigger may need time), then create manually if still null

---

## Gotchas & Known Issues

### ⚠️ DO NOT
- **Don't assume `cart_items` has a `size` column** — it was added in migration `20260703`. Old rows may have NULL size. Always fall back to variant or inventory data.
- **Don't use `product_variants.stock` for validation** — use `inventory.stock` as authoritative (inventory is derived from variants via `_syncInventoryFromVariants`).
- **Don't forget to sync active status after stock changes** — call `ProductService.syncProductActiveStatus()` after inventory modifications.
- **Don't create orders without store_id lookup** — the products → store_id chain is required for the orders table.
- **Don't block on notifications** — all notification creation is fire-and-forget (`.catchError` or not awaited).

### ⚠️ ALWAYS
- **Always combine online + POS for revenue** — never use just one source (seller side).
- **Always use the 3-step chain for store orders** — products → order_items → orders.
- **Always call `_syncInventoryFromVariants()` after variant changes** — inventory is derived.
- **Always check `mounted` before `setState`** — prevents "setState() called after dispose()" errors.
- **Always use `AppConstants.surfaceLight` as background** — not `Colors.white` or `Colors.grey`.

### Known Issues
- `isFollowing()` always returns false synchronously (use `isFollowingAsync()`)
- CSV export is a stub (shows SnackBar only)
- Settings screen is a stub (shows SnackBar only)
- Card payment is disabled (coming soon)
- SMS order updates banner is a stub
- AR fitting is simulated (camera placeholder, not real ARCore/ARKit)

---

*SoleVision Customer Module Architecture — July 14, 2026*
