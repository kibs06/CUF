# SoleVision — Customer Module AI Context

> Condensed reference for AI agents working on the customer side.
> Derived from CUSTOMER_MODULE_DOCUMENTATION.md v1.0.0 (July 16, 2026).
>
> **Where do I start?** Read `lib/screens/customer/customer_shell.dart` for navigation,
> `lib/screens/customer/customer_home_screen.dart` for the main UI,
> and `lib/providers/cart_provider.dart` for the core business logic pattern.

---

## Quick Facts

- **Stack:** Flutter + Supabase (Postgres, Auth, Storage, Realtime)
- **State management:** ChangeNotifier + Provider
- **12 screens** in `lib/screens/customer/`
- **4-tab bottom nav:** Home, Store, Notifications, Profile
- **Cart is NOT a tab** — pushed via AppBar icon
- **Inbox is NOT a tab** — accessed via floating button or notifications
- **Design system:** Custom `Sole*` widgets (SoleCard, SolePrimaryButton, SoleTextField, etc.)

---

## Architecture (4 Layers)

```
PRESENTATION (Screens + Widgets)
        │
STATE    (Providers — ChangeNotifier + Provider)
        │
SERVICE  (Singletons — API calls, data transform)
        │
BACKEND  (Supabase — Postgres, Auth, Storage, Realtime)
```

**Data flow pattern:** Screen → Provider → Service → Supabase → Provider notifies → Screen rebuilds.
Optimistic updates are used for cart operations (local state first, background sync, rollback on failure).

---

## Screen Map

| # | Screen | File | Purpose |
|---|--------|------|---------|
| 1 | CustomerShell | `customer_shell.dart` | Root container, 4-tab IndexedStack |
| 2 | CustomerHomeScreen | `customer_home_screen.dart` | Product grid, search, categories, banner |
| 3 | ProductDetailScreen | `product_detail_screen.dart` | Image carousel, size/color selectors, add-to-cart |
| 4 | CartScreen | `cart_screen.dart` | Store-grouped cart, quantity stepper, checkout bar |
| 5 | CheckoutScreen | `checkout_screen.dart` | Address, payment, stock validation, order placement |
| 6 | MyOrdersScreen | `my_orders_screen.dart` | Order history with tab filtering |
| 7 | OrderTrackingScreen | `tracking_screen.dart` | Order status timeline |
| 8 | AddressBookScreen | `address_book_screen.dart` | Address CRUD, selection mode |
| 9 | AddEditAddressScreen | `add_edit_address_screen.dart` | Map pin-drop, GPS, geocoding, address form |
| 10 | ARVirtualFitScreen | `ar_fitting_screen.dart` | AR placeholder (not real AR) |
| 11 | CustomizationScreen | `customization_screen.dart` | 5-step custom shoe order |
| 12 | CustomerInboxScreen | `customer_inbox_screen.dart` | Conversation list |

---

## Navigation Tree

```
CustomerShell
├── Tab 0: Home → ProductDetailScreen → [Buy Now / Add to Cart / AR Fitting]
├── Tab 1: Store → StoreProfileScreen → [Follow / Message / Products]
├── Tab 2: Notifications → [OrderTrackingScreen / ChatView]
├── Tab 3: Profile → [MyOrders / AddressBook / Customization / EditProfile / Logout]
└── AppBar Cart → CartScreen → CheckoutScreen → Confirmation
```

**Entry points to messaging:**
- FloatingMessageButton (FAB on home screen) → CustomerInboxScreen → ChatView
- StoreProfileScreen "Message Store" → ChatView
- Notification tap (message type) → ChatView

---

## Provider Reference

| Provider | Key State | Key Methods |
|----------|-----------|-------------|
| `AuthProvider` | `_profile`, `_isLoading` | `login()`, `logout()`, `signUp()` |
| `ProductProvider` | `_products[]`, `_selectedCategory` | `loadProducts()`, `selectCategory()`, `getFilteredProducts()` |
| `CartProvider` | `_items{}`, `_selectedKeys`, `subtotal` | `addToCart()`, `removeFromCart()`, `incrementQuantity()`, `validateForCheckout()` |
| `OrderProvider` | `_orders[]`, `_myOrders[]` | `placeOrder()`, `loadMyOrders()`, `setMyOrdersFilter()` |
| `AddressProvider` | `_addresses[]`, `_selectedAddress` | `loadAddresses()`, `addAddress()`, `updateAddress()`, `deleteAddress()` |
| `MessageProvider` | `_conversations[]`, `_unreadCounts{}` | `loadConversationsForCustomer()`, `subscribeToInbox()` |
| `NotificationProvider` | `_notifications[]`, `_unreadCount` | `loadNotifications()`, `markAsRead()`, `markAllAsRead()` |
| `ChatAttachmentProvider` | `_failedMessages{}` | `addFailedMessage()`, `mergeWithFailed()` |

---

## Service Reference

| Service | Singleton | Dependencies |
|---------|-----------|-------------|
| `ProductService` | `ProductService.instance` | Supabase (products, inventory, product_variants, product_images) |
| `CartService` | `CartService.instance` | Supabase (cart_items, products, inventory, product_variants) |
| `OrderService` | `OrderService.instance` | SupabaseService.createOrder() |
| `AddressService` | `AddressService.instance` | Supabase (customer_addresses) |
| `MessageService` | `MessageService.instance` | Supabase (conversations, messages, profiles, stores) + Edge Functions |
| `ConnectivityService` | `ConnectivityService.instance` | connectivity_plus package |
| `StoreService` | `StoreService.instance` | Supabase (stores, store_follows, story_entries) |
| `PushNotificationService` | `PushNotificationService.instance` | Firebase Messaging + flutter_local_notifications |

---

## Key Data Models

### Address (`lib/models/address_model.dart`)
```dart
class Address {
  String? id; String userId; String label; // 'Home'|'Work'|'Other'
  String recipientName; String recipientPhone;
  String region; String province; String cityMunicipality; String barangay;
  String streetAddress; String? landmark;
  double latitude; double longitude; bool isDefault;
  String get formattedAddress; // computed
}
```

### CartItem (composite key: `productId-size-color`)
```dart
{
  'id': 'productId-size-color',
  'productId': String, 'productName': String, 'imageUrl': String,
  'price': double, 'size': String, 'color': String, 'quantity': int,
  'storeId': String?, 'storeName': String?,
  'variantId': String?, 'additionalPrice': double,
}
```

### Message (`lib/services/message_service.dart`)
```dart
class Message {
  String id; String conversationId; String senderId;
  String senderType; // 'customer' | 'seller'
  String? body; bool isRead; DateTime createdAt;
  String? attachmentUrl; String? attachmentType; // 'image' | 'video'
  // Local-only: isSending, sendFailed, localFile, progress
}
```

### Conversation (`lib/services/message_service.dart`)
```dart
class Conversation {
  String id; String storeId; String customerId;
  DateTime? lastMessageAt; String? lastMessagePreview;
  String? customerName; // Denormalized via DB trigger
  String? storeName; // Joined from stores table
  int unreadCount;
}
```

---

## Database Tables Used by Customer

| Table | Purpose | RLS |
|-------|---------|-----|
| `products` | Product catalog | Anyone can read active products |
| `product_images` | Product images | Joined from products |
| `product_variants` | Size+color variants with price | Joined from products |
| `inventory` | Size stock levels | Joined from products |
| `stores` | Store profiles | Anyone can read active stores |
| `cart_items` | User's cart | Users read/write own cart |
| `orders` | Order records | Customers read own, sellers read store's |
| `order_items` | Line items per order | Joined from orders |
| `customer_addresses` | Saved addresses | Users read/write own |
| `conversations` | Chat threads | Participants read own |
| `messages` | Chat messages | Participants read own conversation |
| `store_follows` | Follow relationships | Users manage own follows |
| `notifications` | Customer notifications | Users read/update own |
| `device_tokens` | FCM tokens | Users manage own |

---

## Key Queries

```sql
-- Products (with all relations)
SELECT *, stores(name), product_images(image_url, display_order),
       inventory(size, stock), product_variants(*)
FROM products WHERE is_active = true ORDER BY created_at DESC;

-- Cart items
SELECT *, products(name, price, store_id, stores(name))
FROM cart_items WHERE user_id = auth.uid() ORDER BY created_at DESC;

-- Customer orders
SELECT *, order_items(*, products(name, product_images(image_url, display_order)))
FROM orders WHERE customer_id = auth.uid() ORDER BY created_at DESC;

-- Conversations (customer)
SELECT *, stores(name) FROM conversations
WHERE customer_id = auth.uid() ORDER BY last_message_at DESC NULLS FIRST;

-- Messages
SELECT * FROM messages WHERE conversation_id = ? ORDER BY created_at ASC;

-- Addresses
SELECT * FROM customer_addresses WHERE user_id = auth.uid()
ORDER BY is_default DESC, created_at DESC;
```

---

## Critical Bugs to Know

| # | Issue | File | Impact |
|---|-------|------|--------|
| 1 | `_buyNow()` doesn't navigate to checkout | `product_detail_screen.dart` | "Buy Now" is non-functional |
| 2 | `tracking_screen.dart` reads `order['size']` | `tracking_screen.dart` | Crashes — orders don't have `size` (order_items do) |
| 3 | `tracking_screen.dart` casts `total_amount as double` | `tracking_screen.dart` | Crashes — Supabase returns `int` for whole numbers |
| 4 | `ar_fitting_screen.dart` reads `product['sizes']` | `ar_fitting_screen.dart` | Field doesn't exist — size selector broken |

---

## Missing Features (High Priority)

| Feature | Notes |
|---------|-------|
| Cart tab in bottom nav | Only accessible via AppBar icon — poor discoverability |
| Inbox tab in bottom nav | Only via floating button |
| Order cancellation | RLS policy exists but no UI |
| Product reviews/ratings | No reviews section |
| Wishlist/favorites | No save-for-later |

---

## Key Widgets (Customer-Specific)

| Widget | File | Purpose |
|--------|------|---------|
| `SoleProductCard` | `lib/widgets/sole_product_card.dart` | Product card for masonry grid |
| `CartIconButton` | `lib/widgets/cart_icon_button.dart` | AppBar cart icon with badge |
| `FloatingMessageButton` | `lib/widgets/floating_message_button.dart` | FAB with unread badge |
| `FlyToCartAnimation` | `lib/widgets/fly_to_cart_animation.dart` | Overlay animation from product to cart |
| `SoleARPill` | `lib/widgets/sole_ar_pill.dart` | "Virtual Try-On" pill |
| `ChatView` | `lib/widgets/chat/chat_view.dart` | Shared chat UI (both roles) |

## Shared Widgets (Sole Design System)

| Widget | Purpose |
|--------|---------|
| `SoleCard` | Branded card with shadow |
| `SolePrimaryButton` | Primary action button |
| `SoleTextField` | Styled text input |
| `SoleBottomNav` | Bottom navigation bar |
| `SoleStatusChip` | Order status chip |
| `SoleTimeline` | Vertical timeline for order tracking |
| `ShimmerBox` | Loading skeleton |
| `EmptyStateWidget` | Empty state with icon + text |
| `ErrorRetryWidget` | Error state with retry button |
| `NoInternetView` | Offline state with retry |

---

## Patterns to Follow

1. **Optimistic updates** — Update local state immediately, sync in background, rollback on failure
2. **Singleton services** — `static final XyzService instance = XyzService._()`
3. **IndexedStack** — CustomerShell uses IndexedStack to preserve tab state
4. **Composite cart keys** — `productId-size-color` for cart item identification
5. **Variant resolution** — `resolveVariant()` returns variantId + additionalPrice
6. **Stock validation** — Double-check live inventory before order placement (race condition protection)
7. **Realtime subscriptions** — `.stream(primaryKey: ['id'])` on Supabase tables for live updates
8. **Auth lifecycle** — Providers listen to `onAuthStateChange` for load/clear
9. **Connectivity** — Auto-refresh on connection restore via `ConnectivityService`
10. **RLS everywhere** — All tables have Row Level Security; never bypass from client code
