# SoleVision — Customer Order Process Architecture

> **Audience:** AI agents and developers working on the order pipeline.
> **Last updated:** July 18, 2026

---

## 1. Overview — The Order Lifecycle

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        CUSTOMER ORDER LIFECYCLE                             │
│                                                                             │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌────────┐│
│  │  Browse   │───▶│   Cart   │───▶│ Checkout │───▶│  Order   │───▶│ Track  ││
│  │  & Select │    │  Review  │    │  Confirm │    │ Placed!  │    │ Status ││
│  └──────────┘    └──────────┘    └──────────┘    └──────────┘    └────────┘│
│       │               │               │               │              │      │
│  ProductDetail    CartScreen     CheckoutScreen   Supabase     MyOrders +   │
│  screen           (validation)   (address, pay)   createOrder   Tracking     │
│                                                                             │
│  ──────────────────────── SELLER SIDE ────────────────────────────────────  │
│                                                                             │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐             │
│  │  Pending  │───▶│Confirmed │───▶│  Ready   │───▶│ Delivered │             │
│  │  (new)    │    │(prepare) │    │(pickup/  │    │(received) │             │
│  │           │    │          │    │ delivery)│    │           │             │
│  └──────────┘    └──────────┘    └──────────┘    └──────────┘             │
│                                                                             │
│  Status transitions are driven by the SELLER via manage_orders_screen.     │
│  The customer sees read-only status on tracking_screen.                     │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Status State Machine

### Order Status Values (from `orders.status`)

| Status | Meaning | Who sets it | Customer sees |
|--------|---------|-------------|---------------|
| `pending` | Order just placed, awaiting seller action | `createOrder()` auto-sets | "Processing" tab |
| `placed` | Legacy initial status (older orders) | Legacy code | "Processing" tab |
| `preparing` | Seller has confirmed, making the shoe | Seller taps "Confirm" | Timeline step 2 |
| `ready` | Shoe is done, ready for pickup/delivery | Seller taps "Ready" | Timeline step 3 |
| `received` | Customer has received the order | Seller taps "Delivered" | Timeline step 4 (final) |
| `cancelled` | Order was cancelled | Seller/Admin | "Returns" tab |

### Payment Status Values (from `orders.payment_status`)

| Status | Meaning |
|--------|---------|
| `paid` | GCash or Card (auto-set at creation) |
| `unpaid` | Cash on Pickup (default for cash) |

### Status Flow Diagram

```
                    ┌─────────────────┐
                    │   createOrder() │
                    │ status=pending  │
                    │ payment=        │
                    │  gcash/card→paid│
                    │  cash→unpaid    │
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
                    │     PENDING     │◄──────────── Seller can cancel
                    │  (new order)    │             from here to "cancelled"
                    └────────┬────────┘
                             │
                    Seller taps "Confirm"
                    ┌────────▼────────┐
                    │   PREPARING     │
                    │  (confirmed)    │
                    └────────┬────────┘
                             │
                    Seller taps "Ready"
                    ┌────────▼────────┐
                    │     READY       │
                    │ (ready for      │
                    │  pickup/delivery)│
                    └────────┬────────┘
                             │
                    Seller taps "Delivered"
                    ┌────────▼────────┐
                    │    RECEIVED     │
                    │  (completed)    │
                    └─────────────────┘
```

---

## 3. File Map — All Order-Related Files

### Customer Side

| File | Purpose |
|------|---------|
| `lib/screens/customer/cart_screen.dart` | Cart UI — store grouping, selection, quantity stepper |
| `lib/screens/customer/checkout_screen.dart` | Checkout form — address, payment, validation, submit |
| `lib/screens/customer/my_orders_screen.dart` | Order list with tab-based filtering |
| `lib/screens/customer/tracking_screen.dart` | Single order timeline view |
| `lib/screens/customer/product_detail_screen.dart` | Product detail — "Add to Cart" and "Buy Now" |
| `lib/screens/customer/address_book_screen.dart` | Address CRUD + selection mode for checkout |
| `lib/screens/customer/add_edit_address_screen.dart` | Address creation with MapTiler geocoding |

### Provider Layer

| File | Purpose |
|------|---------|
| `lib/providers/order_provider.dart` | Order state — `placeOrder()`, `loadMyOrders()`, `setMyOrdersFilter()` |
| `lib/providers/cart_provider.dart` | Cart state — `addToCart()`, `removeFromCart()`, `validateForCheckout()` |

### Service Layer

| File | Purpose |
|------|---------|
| `lib/services/order_service.dart` | Order queries — `placeOrder()`, `fetchMyOrders()`, `fetchStoreOrders()` |
| `lib/services/cart_service.dart` | Cart DB ops — `fetchCart()`, `addOrUpdateItem()`, `validateCartForCheckout()` |
| `lib/services/supabase_service.dart` | Core DB — `createOrder()`, `updateOrderStatus()`, `_mapOrder()` |
| `lib/services/seller_notification_service.dart` | Creates seller notifications on order events |

### Shared / Widgets

| File | Purpose |
|------|---------|
| `lib/widgets/sole_timeline.dart` | Vertical timeline component for tracking |
| `lib/widgets/sole_card.dart` | Reusable card container |
| `lib/widgets/sole_status_chip.dart` | Status badge (color-coded) |
| `lib/widgets/sole_primary_button.dart` | Primary CTA button |
| `lib/utils/cart_helpers.dart` | `resolveVariant()`, `normalizeSize()`, `resolveInventoryStock()` |
| `lib/exceptions/stock_unavailable_exception.dart` | Custom exception for stock validation failures |

### Seller Side (Order Management)

| File | Purpose |
|------|---------|
| `lib/screens/seller/manage_orders_screen.dart` | Seller order list with status update actions |
| `lib/screens/seller/order_detail_screen.dart` | Seller view of a single order |

---

## 4. Data Models

### Database Tables

```sql
-- orders (one row per order)
CREATE TABLE public.orders (
    id              BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    customer_id     UUID REFERENCES profiles(id),
    store_id        UUID REFERENCES stores(id),
    status          TEXT DEFAULT 'pending',     -- pending|placed|preparing|ready|received|cancelled
    total_amount    NUMERIC,
    payment_method  TEXT DEFAULT 'cash',         -- cash|gcash|card
    payment_status  TEXT DEFAULT 'unpaid',       -- paid|unpaid
    fulfillment     TEXT DEFAULT 'pickup',       -- pickup|delivery
    notes           TEXT,                        -- stores delivery address text
    shipping_address JSONB,                      -- full address snapshot
    size            TEXT,                        -- LEGACY, do not use for new orders
    color           TEXT,                        -- LEGACY
    quantity        INTEGER,                     -- LEGACY
    created_at      TIMESTAMPTZ
);

-- order_items (line items within an order)
CREATE TABLE public.order_items (
    id              BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    order_id        BIGINT REFERENCES orders(id) ON DELETE CASCADE,
    product_id      TEXT REFERENCES products(id),
    size            TEXT,
    quantity        INTEGER DEFAULT 1,
    unit_price      NUMERIC DEFAULT 0
);

-- cart_items (persistent server-side cart)
CREATE TABLE public.cart_items (
    id              TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    user_id         UUID REFERENCES profiles(id),
    product_id      TEXT REFERENCES products(id),
    variant_id      BIGINT REFERENCES product_variants(id),
    quantity        INTEGER DEFAULT 1,
    customizations  JSONB,
    size            TEXT,
    created_at      TIMESTAMPTZ,
    updated_at      TIMESTAMPTZ
);

-- inventory (aggregated stock by size per product)
CREATE TABLE public.inventory (
    product_id      TEXT REFERENCES products(id),
    size            TEXT,
    stock           INTEGER DEFAULT 0,
    updated_at      TIMESTAMPTZ,
    PRIMARY KEY (product_id, size)
);
```

### In-Memory Order Map Structure (as returned by `_mapOrder()`)

```dart
{
  'id': '123',                    // String (BIGINT cast to string)
  'customer_id': 'uuid',
  'store_id': 'uuid',
  'status': 'pending',
  'total_amount': 1500.0,         // double
  'payment_method': 'gcash',
  'payment_status': 'paid',
  'fulfillment': 'pickup',
  'notes': 'delivery address text',
  'shipping_address': {...},      // JSONB snapshot
  'created_at': '2026-07-18T...',
  'product_id': 'first_item_product_id',  // from _mapOrder()
  'size': 'EU42',                          // from first order_item
  'quantity': 1,                           // from first order_item
  'profiles': {'full_name': '...', 'email': '...'},
  'order_items': [...],            // raw order_items list
  'items_count': 2,               // total qty across all items
}
```

### In-Memory Cart Item Map Structure (from `CartItemWithDetails.toCartItemMap()`)

```dart
{
  'id': 'productId-EU42-brown',   // composite key
  'server_id': 'supabase_row_id',  // cart_items.id
  'product_id': 'uuid',
  'product_name': 'Classic Derby',
  'imageUrl': 'https://...',
  'price': 1500.0,                 // unitPrice (base + additional)
  'additional_price': 100.0,
  'size': 'EU42',
  'color': 'brown',
  'quantity': 2,
  'store_id': 'store-uuid',
  'store_name': 'Valladolid Leather Co.',
  'variant_id': '123',
  'customizations': null,
  'cart_size': 'EU42',             // raw size from cart_items.size column
}
```

---

## 5. Data Flow Diagrams

### Flow 1: Add to Cart → Checkout → Place Order

```
┌─────────────────────────────────────────────────────────────────────┐
│  1. PRODUCT DETAIL SCREEN                                           │
│  ─────────────────────────                                          │
│  User selects size + color → resolveVariant() → get variantId       │
│  User taps "Add to Cart"                                            │
│       │                                                             │
│       ▼                                                             │
│  CartProvider.addToCart()                                            │
│    ├─ Optimistic: adds to _items map + _selectedKeys                │
│    ├─ Writes to SharedPreferences cache                             │
│    └─ Background: CartService.addOrUpdateItem() → cart_items table  │
│       (returns server_id, stored as 'server_id' in cart item)       │
│                                                                     │
│  2. CART SCREEN                                                     │
│  ────────────                                                       │
│  User reviews items, selects which to checkout                      │
│  User taps "Checkout"                                               │
│       │                                                             │
│       ▼                                                             │
│  Navigator → CheckoutScreen                                         │
│                                                                     │
│  3. CHECKOUT SCREEN                                                 │
│  ───────────────────                                                │
│  On init:                                                           │
│    ├─ _loadAddress() → AddressProvider.loadAddresses()              │
│    │   → auto-selects default address                               │
│    └─ _validateCart() → CartService.validateCartForCheckout()       │
│        → re-fetches live prices + stock from Supabase               │
│        → shows banners: out-of-stock, price-changed, low-stock      │
│                                                                     │
│  User selects:                                                      │
│    ├─ Delivery address (AddressBookScreen in selection mode)         │
│    └─ Payment method (GCash / Cash on Pickup / Card)                │
│                                                                     │
│  User taps "Complete Order"                                         │
│    ├─ _validateCart() again (double-check)                           │
│    ├─ _canSubmitOrder() gate:                                       │
│    │   - selectedItems not empty                                    │
│    │   - not currently validating                                   │
│    │   - address selected                                           │
│    │   - all items available + sufficient stock                     │
│    └─ _submitCheckout()                                             │
│                                                                     │
│  4. ORDER CREATION                                                  │
│  ──────────────────                                                 │
│  OrderProvider.placeOrder()                                         │
│    └─ SupabaseService.createOrder()                                 │
│        ├─ Looks up store_id from first product                      │
│        ├─ STEP 1: INSERT into orders table                          │
│        │   - customer_id, store_id, status='pending'                │
│        │   - total_amount, payment_method, payment_status           │
│        │   - shipping_address (JSONB snapshot)                      │
│        ├─ Batch-fetch inventory for all products in order           │
│        ├─ STEP 2: INSERT each order_item row                        │
│        │   - Resolves size via resolveInventoryStock()              │
│        │   - If ANY insert fails → ROLLBACK:                        │
│        │     delete orphaned orders row + any inserted items        │
│        │     throw StockUnavailableException                        │
│        └─ Fire-and-forget: SellerNotificationService.createNewOrder │
│                                                                     │
│  5. POST-ORDER CLEANUP (back in CheckoutScreen)                     │
│    ├─ CartService.removeItems(serverIds) — delete ordered items     │
│    ├─ CartProvider.removeFromCart() for each local item             │
│    └─ Show confirmation screen with "Track My Order" button         │
│        → navigates to OrderTrackingScreen                           │
└─────────────────────────────────────────────────────────────────────┘
```

### Flow 2: View Orders & Track Status

```
┌─────────────────────────────────────────────────────────────────────┐
│  MY ORDERS SCREEN                                                   │
│  ─────────────────                                                  │
│  Entry points:                                                      │
│    ├─ Profile screen → "My Orders"                                  │
│    ├─ Profile screen → specific tab (e.g. "Shipped")                │
│    └─ Direct navigation                                             │
│                                                                     │
│  Tab filters:                                                       │
│    ├─ "All orders"     → all orders                                 │
│    ├─ "Unpaid"         → payment_status='unpaid' && not cancelled   │
│    ├─ "Processing"     → status in (pending, placed, preparing)     │
│    ├─ "Shipped"        → status='ready'                             │
│    ├─ "Review"         → status='received'                          │
│    └─ "Returns"        → status='cancelled'                         │
│                                                                     │
│  Data: OrderProvider.loadMyOrders()                                 │
│    └─ OrderService.fetchMyOrders()                                  │
│        └─ Supabase query: orders → order_items → products           │
│           (includes product_images for thumbnails)                   │
│                                                                     │
│  Pull-to-refresh supported                                          │
│  Auto-refresh when connection restored after offline                 │
│                                                                     │
│  TRACKING SCREEN                                                    │
│  ────────────────                                                   │
│  Receives order map as constructor param                             │
│  Maps status to timeline index:                                     │
│    pending/placed → index 0 (Order Placed)                          │
│    preparing      → index 1 (Being Prepared)                        │
│    ready          → index 2 (Ready for Pickup/Delivery)             │
│    received       → index 3 (Received)                              │
│                                                                     │
│  Uses SoleTimeline widget (vertical timeline with dots/connectors)  │
│                                                                     │
│  ⚠️ KNOWN BUGS in tracking_screen.dart:                             │
│    - Hardcoded store name "Carcar Craft Collection"                 │
│    - Hardcoded timeline dates ("June 15, 10:30 AM")                 │
│    - Reads order['size'] — doesn't exist on order object            │
│    - Casts total_amount as double (crashes on int)                  │
└─────────────────────────────────────────────────────────────────────┘
```

### Flow 3: Cart Validation (Checkout Pre-flight)

```
┌─────────────────────────────────────────────────────────────────────┐
│  CartService.validateCartForCheckout()                              │
│  ──────────────────────────────────────                             │
│                                                                     │
│  1. fetchCart(userId) — re-fetches from Supabase                    │
│     → returns CartItemWithDetails list with live prices/stock       │
│                                                                     │
│  2. Batch-fetch ALL inventory rows for products in cart             │
│     → groups by product_id                                          │
│                                                                     │
│  3. For each server cart item:                                      │
│     a. Find matching local cart item (by composite key)             │
│     b. Call resolveInventoryStock():                                │
│        - Exact size match → use that stock                          │
│        - Normalized match (strip EU/US prefix) → use that stock     │
│        - No match → return -1 (treat as unavailable)                │
│     c. Determine:                                                   │
│        - isAvailable = product.isActive AND stock > 0               │
│        - priceChanged = |cartPrice - currentPrice| > 0.01           │
│        - insufficientStock = cartQuantity > stock                   │
│                                                                     │
│  4. Return CartValidationResult list                                │
│     → CheckoutScreen shows inline banners for each issue            │
│                                                                     │
│  Gate logic (_canSubmitOrder):                                      │
│    - No validation in progress                                      │
│    - Address selected                                               │
│    - All items available AND sufficient stock                       │
└─────────────────────────────────────────────────────────────────────┘
```

### Flow 4: Size Resolution Chain

```
┌─────────────────────────────────────────────────────────────────────┐
│  When resolving a size for stock lookup, the app uses a chain:      │
│                                                                     │
│  1. cart_items.size column (authoritative, stored on add-to-cart)   │
│  2. product_variants table (via LEFT JOIN in fetchCart)             │
│  3. inventory table (fallback via _buildSizesMap in UI)             │
│                                                                     │
│  resolveInventoryStock() normalizes both sides:                     │
│    "EU42" → "42"  (strip alpha prefix)                             │
│    "42" stays "42"                                                   │
│                                                                     │
│  Match order:                                                       │
│    1. Exact string match (cart_size == inventory.size)              │
│    2. Normalized numeric match (normalizeSize both)                 │
│    3. No match → return -1 (item treated as unavailable)            │
│                                                                     │
│  ⚠️ NO fallback to "first available size" — this prevents          │
│     false stock reads and the "no longer available" bug.            │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 6. Key Service Methods Reference

### OrderService

```dart
class OrderService {
  // Customer: place an order
  Future<String> placeOrder(Map<String, dynamic> dto);  // → order ID

  // Customer: fetch all orders for current user
  Future<List<Map<String, dynamic>>> fetchMyOrders();
  // Returns: [{id, status, total_amount, payment_method, payment_status,
  //            created_at, store_id, order_items: [{id, product_id, size,
  //            quantity, unit_price, products: {name, category,
  //            product_images: [{image_url, display_order}]}}]}]

  // Seller: fetch orders for a store
  Future<List<Map<String, dynamic>>> fetchStoreOrders(String storeId, {String? status});

  // Seller: recent N orders
  Future<List<Map<String, dynamic>>> getRecentOrders(String storeId, {int limit = 5});

  // Seller: count by status
  Future<Map<String, int>> getOrderCountByStatus(String storeId);

  // Seller/Admin: update status
  Future<void> updateOrderStatus(String orderId, String newStatus);
}
```

### CartService

```dart
class CartService {
  // Fetch full cart with joined product/variant/store data
  Future<List<CartItemWithDetails>> fetchCart(String userId);

  // Add or increment cart item
  Future<String> addOrUpdateItem({...});  // → cart item server ID

  // Update quantity
  Future<void> updateQuantity({required String cartItemId, required int newQuantity});

  // Remove single item
  Future<void> removeItem(String cartItemId);

  // Clear entire cart
  Future<void> clearCart(String userId);

  // Remove specific items (post-order cleanup)
  Future<void> removeItems(String userId, List<String> cartItemIds);

  // Validate cart for checkout (prices + stock)
  Future<List<CartValidationResult>> validateCartForCheckout(
    String userId,
    Map<String, Map<String, dynamic>> currentCartItems,
  );
}
```

### SupabaseService.createOrder()

```dart
Future<Map<String, dynamic>> createOrder(Map<String, dynamic> orderData) async {
  // Input: {
  //   customer_id, items: [{product_id, size, quantity, unit_price}],
  //   total_amount, delivery_address, payment_method, shipping_address
  // }

  // Steps:
  // 1. Lookup store_id from first product
  // 2. INSERT orders row (status='pending')
  // 3. Batch-fetch inventory for all products
  // 4. For each item: resolveInventoryStock(), INSERT order_item
  //    - If ANY insert fails → delete orphaned order + inserted items
  //    - If stock check fails (PostgrestException P0001) → StockUnavailableException
  // 5. Fire-and-forget: SellerNotificationService.createNewOrder()

  // Output: _mapOrder({...orderMap, 'order_items': [...]})
}
```

### CartProvider (State Management)

```dart
class CartProvider extends ChangeNotifier {
  // Cart state
  Map<String, Map<String, dynamic>> get items;
  Set<String> get selectedKeys;

  // Computed
  int get itemCount;
  double get subtotal;
  double get selectedSubtotal;
  double get selectedTotal;
  List<Map<String, dynamic>> get selectedItems;
  List<Map<String, dynamic>> get groupedByStore;

  // Mutations (optimistic + background sync)
  void addToCart({...});
  void removeFromCart(String cartKey);
  void incrementQuantity(String cartKey);
  void decrementQuantity(String cartKey);
  void clearCart();

  // Selection
  void toggleItem(String cartKey);
  void toggleStore(String storeId);
  void toggleAll();

  // Checkout
  Future<List<CartValidationResult>> validateForCheckout();

  // Server sync
  Future<void> refreshFromServer();
  Future<void> removeServerItems(List<String> serverIds);
  Future<void> clearCartFromServer();
}
```

### OrderProvider (State Management)

```dart
class OrderProvider extends ChangeNotifier {
  // My Orders (customer-facing)
  List<Map<String, dynamic>> get myOrders;      // filtered list
  bool get isLoadingMyOrders;
  String? get myOrdersError;

  Future<void> loadMyOrders();
  void setMyOrdersFilter(String filter);        // 'all'|'unpaid'|'processing'|'shipped'|'review'|'returns'

  // Place order
  Future<Map<String, dynamic>?> placeOrder({...});
  StockUnavailableException? get stockError;

  // Admin/Seller
  List<Map<String, dynamic>> get orders;
  Future<void> loadOrders();
  Future<bool> updateOrderStatus(dynamic orderId, String newStatus);
}
```

---

## 7. RLS Policies — Order Access

| Table | Who can SELECT | Who can INSERT | Who can UPDATE |
|-------|---------------|----------------|----------------|
| `orders` | Customer (own), Seller (own store), Admin (all) | Customer (own) | Seller, Admin |
| `order_items` | Customer (own order), Seller/Admin (via order) | Customer (own order) | — |
| `cart_items` | Own cart | Own cart | Own cart |
| `inventory` | Everyone | Seller (own products), Admin | Seller (own products), Admin |

### Key RLS Details

- **orders**: `auth.uid() = customer_id` for customer SELECT/INSERT
- **orders**: Seller SELECT requires `EXISTS (SELECT 1 FROM stores WHERE id = store_id AND owner_id = auth.uid())`
- **order_items**: SELECT requires matching order ownership OR seller/admin role
- **order_items**: INSERT requires matching order ownership
- **cart_items**: All operations restricted to `auth.uid() = user_id`

---

## 8. Known Bugs & Issues

### 🔴 Critical

| # | Issue | File | Details |
|---|-------|------|---------|
| 1 | `_buyNow()` doesn't navigate to checkout | `product_detail_screen.dart` | Calls `_addToCart()` then shows snackbar "Processing checkout..." but **never navigates to CheckoutScreen**. User taps "Buy Now" and nothing visible happens. |
| 2 | `tracking_screen.dart` has hardcoded dummy data | `tracking_screen.dart` | Timeline items have hardcoded dates ("June 15, 10:30 AM"), hardcoded store name, and reads `order['size']` which doesn't exist on the order object (orders don't have a `size` field — `order_items` do). This will crash with null error. |
| 3 | `tracking_screen.dart` casts `total_amount as double` | `tracking_screen.dart` | Line `(order['total_amount'] as double)` will throw if value is `int` (Supabase returns `int` for whole numbers). Fix: `(order['total_amount'] as num?)?.toDouble()`. |
| 4 | `createOrder()` doesn't check stock before inserting order row | `supabase_service.dart` | Stock is only checked via the DB trigger on `order_items` insert. If the trigger isn't deployed, orders can be placed with zero stock. |
| 5 | **Seller status values don't match DB CHECK constraint** | `manage_orders_screen.dart` | Seller's `_updateStatus()` transitions `pending → confirmed → ready → delivered`, but the DB CHECK constraint only allows `placed|preparing|ready|received|cancelled|pending`. Values `confirmed` and `delivered` will cause PostgrestExceptions on update. |

### 🟡 Medium

| # | Issue | File | Details |
|---|-------|------|---------|
| 6 | `_mapOrder()` takes first item's size/quantity as order-level fields | `supabase_service.dart` | Multi-item orders lose individual item data in the top-level map. `tracking_screen.dart` reads `order['size']` which only reflects the first item. |
| 7 | Cart sync race condition on slow connections | `cart_provider.dart` | `_syncAddToServer()` runs in background. If user checks out before sync completes, `server_id` is null → falls back to `clearCartFromServer()` (clears ALL items, not just ordered ones). |
| 8 | `_validateCart()` fetches from server but compares against local cart | `checkout_screen.dart` | If user added items locally but server sync hasn't completed, validation may miss items or show stale data. |
| 9 | No retry mechanism for failed order placement | `checkout_screen.dart` | If `_submitCheckout()` fails, user sees a snackbar but must manually re-add items if the cart was partially cleared. |

### 🟢 Low

| # | Issue | File | Details |
|---|-------|------|---------|
| 10 | SMS banner shows "coming soon" to production users | `my_orders_screen.dart` | `_handleEnableSms()` just shows a snackbar. Should be hidden until feature is ready. |
| 11 | Legacy columns in orders table (`size`, `color`, `quantity`) | `schema.sql` | Not used by new order flow but still in the table. Can cause confusion. |
| 12 | `orders.status` CHECK includes both `placed` and `pending` | `schema.sql` | Two different initial statuses is confusing. New orders use `pending`, legacy used `placed`. |

---

## 9. Constants Reference

From `lib/constants/app_constants.dart`:

```dart
// Order statuses
static const String statusPlaced = 'placed';      // Legacy
static const String statusPreparing = 'preparing';
static const String statusReady = 'ready';
static const String statusReceived = 'received';

// Cart
static const double deliveryFee = 100.0;  // ₱100 flat delivery fee
```

### Order Status → Tab Mapping (MyOrdersScreen)

| Tab | Filter Logic |
|-----|-------------|
| All orders | No filter |
| Unpaid | `payment_status == 'unpaid' && status != 'cancelled'` |
| Processing | `status in (pending, placed, preparing)` |
| Shipped | `status == 'ready'` |
| Review | `status == 'received'` |
| Returns | `status == 'cancelled'` |

### Order Status → Seller Tab Mapping (ManageOrdersScreen)

| Tab | Status |
|-----|--------|
| All | No filter |
| Pending | `status == 'pending'` |
| Confirmed | `status == 'confirmed'` |
| Ready | `status == 'ready'` |
| Delivered | `status == 'delivered'` |
| Cancelled | `status == 'cancelled'` |

⚠️ **Naming mismatch**: Customer side uses `preparing`, seller side uses `confirmed`. The DB stores `preparing` but the seller UI labels it "Confirmed". The seller's `_updateStatus()` transitions `pending → confirmed → ready → delivered`, but the DB CHECK constraint allows `placed|preparing|ready|received|cancelled|pending` — not `confirmed` or `delivered`. This is a potential crash if the DB constraint is enforced.

---

## 10. Database Queries Reference

### Create Order
```sql
-- Step 1: Insert order
INSERT INTO orders (customer_id, store_id, status, total_amount, payment_method, payment_status, shipping_address, notes)
VALUES ($userId, $storeId, 'pending', $total, $method, $paymentStatus, $shippingAddress, $deliveryAddress)
RETURNING *;

-- Step 2: Insert each order_item
INSERT INTO order_items (order_id, product_id, size, quantity, unit_price)
VALUES ($orderId, $productId, $size, $qty, $unitPrice);
```

### Fetch Customer Orders
```sql
SELECT id, customer_id, status, total_amount, payment_method, payment_status,
       created_at, store_id,
       order_items(id, product_id, size, quantity, unit_price,
         products(name, category,
           product_images(image_url, display_order)))
FROM orders
ORDER BY created_at DESC;
```

### Fetch Cart
```sql
SELECT *,
  products!inner(name, is_active, price, store_id,
    product_images(image_url, display_order)),
  product_variants(id, size, color, stock, additional_price)
FROM cart_items
WHERE user_id = $userId
ORDER BY created_at ASC;
```

### Validate Cart Stock
```sql
-- Batch fetch inventory for all products in cart
SELECT product_id, size, stock
FROM inventory
WHERE product_id IN ($productIds)
AND stock > 0;
```

### Update Order Status
```sql
UPDATE orders SET status = $newStatus WHERE id = $orderId RETURNING *;
```

---

## 11. Edge Cases & Gotchas

1. **Multi-store cart → single-store order (BUG)**: `CheckoutScreen` sends ALL selected items to `placeOrder()` in one call, but `createOrder()` only looks up `store_id` from the first product. All items get assigned to one store regardless of their actual store. Fix: group items by `store_id` and create separate orders per store.

2. **Cart composite key**: `$productId-$size-${color ?? 'none'}`. Two items with same product but different sizes are separate cart entries.

3. **Size normalization**: `normalizeSize("EU42")` → `"42"`. This is critical for inventory matching since cart may store "EU42" while inventory has "42".

4. **Optimistic cart updates**: Local state updates immediately, then syncs to server in background. If server fails, rollback happens.

5. **`server_id` is null until background sync completes**: Checkout must handle this case. Current code falls back to `clearCartFromServer()` which clears ALL items.

6. **Address snapshot**: `shipping_address` is stored as JSONB at order creation time. Changing the address later doesn't update existing orders.

7. **Order ID is BIGINT, not UUID**: Displayed as first 8 characters for brevity.

8. **`_mapOrder()` flattens first item**: Top-level `size`, `quantity`, `product_id` come from the first order_item only. Multi-item orders lose this data at the top level.

9. **Seller status mismatch (CRITICAL)**: The seller UI uses `confirmed` and `delivered` but the DB CHECK constraint doesn't allow these values. This will cause runtime errors on status updates. The DB needs `ALTER TABLE orders DROP CONSTRAINT orders_status_check; ALTER TABLE orders ADD CONSTRAINT orders_status_check CHECK (status IN ('placed','pending','preparing','confirmed','ready','delivered','received','cancelled'));` or the seller code must map to DB-allowed values (`confirmed` → `preparing`, `delivered` → `received`).

---

## 12. Testing Checklist

- [ ] Add item to cart → verify cart count updates
- [ ] Add same item with different size → verify separate cart entries
- [ ] Increment/decrement quantity → verify stock limits respected
- [ ] Checkout with valid address + items → verify order created
- [ ] Checkout with out-of-stock item → verify error banner shown
- [ ] Checkout with insufficient stock → verify "reduce quantity" banner
- [ ] Checkout with price change → verify "price updated" banner
- [ ] Place order → verify cart cleared, confirmation shown
- [ ] Place order → verify seller notification created
- [ ] View My Orders → verify orders appear with correct status
- [ ] Tap order → verify tracking screen loads
- [ ] Seller updates status → verify customer sees updated status
- [ ] Pull-to-refresh on My Orders → verify reload works
- [ ] Offline → place order → verify retry mechanism
- [ ] Multi-item order → verify all items in order_items table
- [ ] Payment method → verify payment_status mapping (gcash/card → paid, cash → unpaid)
- [ ] Multi-store cart → verify items are grouped correctly by store
- [ ] Cart sync failure → verify optimistic rollback restores cart
- [ ] Concurrent purchase of last-stock item → verify stock check prevents oversell
- [ ] Payment method → verify payment_status mapping (gcash/card → paid, cash → unpaid)
- [ ] Multi-store cart → verify items are grouped correctly
- [ ] Cart sync failure → verify optimistic rollback restores cart
- [ ] Concurrent purchase of last-stock item → verify stock check prevents oversell
