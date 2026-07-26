# SoleVision — Seller & POS Architecture

> **Purpose:** Comprehensive reference for AI agents working on the seller side of the app.
> **Last updated:** July 25, 2026
> **Audience:** AI agents implementing features, fixing bugs, or modifying seller-side logic.

---

## Table of Contents

1. [Quick Facts](#1-quick-facts)
2. [Architecture Overview](#2-architecture-overview)
3. [Seller Shell & Navigation](#3-seller-shell--navigation)
4. [Database Schema (Seller-Related Tables)](#4-database-schema-seller-related-tables)
5. [POS (Point of Sale) System](#5-pos-point-of-sale-system)
6. [Order Lifecycle & Status Machine](#6-order-lifecycle--status-machine)
7. [Product Management](#7-product-management)
8. [Inventory System](#8-inventory-system)
9. [Revenue & Reporting](#9-revenue--reporting)
10. [Seller Notifications](#10-seller-notifications)
11. [Messaging (Seller ↔ Customer)](#11-messaging-seller--customer)
12. [Custom Orders](#12-custom-orders)
13. [Service Layer Reference](#13-service-layer-reference)
14. [Provider Layer Reference](#14-provider-layer-reference)
15. [Widget Reference](#15-widget-reference)
16. [RLS Policies (Seller Scope)](#16-rls-policies-seller-scope)
17. [Known Bugs & Gotchas](#17-known-bugs--gotchas)
18. [Common Tasks](#18-common-tasks)

---

## 1. Quick Facts

| Item | Value |
|------|-------|
| **Stack** | Flutter (Dart) + Supabase (PostgreSQL, Storage, Realtime) |
| **State management** | ChangeNotifier + Provider |
| **Architecture pattern** | MVVM (Screens → Providers → Services → Supabase) |
| **Product ID type** | `TEXT` (UUID stored as text, not native UUID) |
| **Order ID type** | `BIGINT` (auto-increment) |
| **Store ID type** | `UUID` |
| **Currency** | Philippine Peso (₱) |
| **Storage buckets** | `product-images` (public), `store-assets` (public), `avatars` (public) |
| **Roles** | `customer`, `seller`, `admin` |
| **Seller statuses** | `none`, `pending`, `approved`, `rejected` |

---

## 2. Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                        SELLER ARCHITECTURE                           │
│                                                                     │
│  ┌──────────────┐                                                   │
│  │  Auth Gate    │  Routes to SellerShell if role=seller &&         │
│  │  (auth_gate)  │  seller_status=approved                          │
│  └──────┬───────┘                                                   │
│         │                                                           │
│  ┌──────▼───────────────────────────────────────────────────────┐   │
│  │                  SELLER SHELL (5 tabs)                        │   │
│  │  ┌─────────┐ ┌─────┐ ┌──────────┐ ┌──────┐ ┌─────────┐    │   │
│  │  │Dashboard│ │ POS │ │ Products │ │Orders│ │ Profile │    │   │
│  │  └────┬────┘ └──┬──┘ └────┬─────┘ └──┬───┘ └─────────┘    │   │
│  │       │         │         │           │                      │   │
│  └───────┼─────────┼─────────┼───────────┼──────────────────────┘   │
│          │         │         │           │                          │
│  ┌───────▼─────────▼─────────▼───────────▼──────────────────────┐   │
│  │                    PROVIDER LAYER                              │   │
│  │  OrderProvider  ProductProvider  SellerNotificationProvider   │   │
│  │  MessageProvider  ReviewProvider  AuthProvider                │   │
│  └───────────────────────┬───────────────────────────────────────┘   │
│                          │                                           │
│  ┌───────────────────────▼───────────────────────────────────────┐   │
│  │                    SERVICE LAYER                               │   │
│  │  SupabaseService  OrderService  ProductService  StoreService  │   │
│  │  SalesService  SellerNotificationService  MessageService      │   │
│  │  ReportService  ReviewService                                 │   │
│  └───────────────────────┬───────────────────────────────────────┘   │
│                          │                                           │
│  ┌───────────────────────▼───────────────────────────────────────┐   │
│  │                    SUPABASE (PostgreSQL)                       │   │
│  │  profiles  stores  products  orders  order_items              │   │
│  │  inventory  product_variants  product_images                  │   │
│  │  sales_transactions  sales_transaction_items                  │   │
│  │  seller_notifications  customization_requests                 │   │
│  │  reviews  messages  conversations                             │   │
│  └───────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 3. Seller Shell & Navigation

**File:** `lib/screens/seller/seller_shell.dart`

The seller shell is a `StatefulWidget` with an `IndexedStack` of 5 screens and a `NavigationBar` bottom nav.

```
SellerShell (5-tab bottom navigation)
├── Tab 0: SellerDashboardScreen  → Real-time metrics & alerts
├── Tab 1: POSScreen              → In-person transaction processing
├── Tab 2: ManageProductsScreen   → Product CRUD with grid view
├── Tab 3: ManageOrdersScreen     → Order management with status filters
└── Tab 4: ProfileScreen          → Account settings (shared with customer)
```

### Sub-Screens (accessible from shell screens)

| Screen | Access From | Purpose |
|--------|-------------|---------|
| `AddEditProductScreen` | ManageProductsScreen | Create/edit product with variants |
| `CreateStoreScreen` | Profile, ManageProducts | First-time store setup |
| `EditStoreScreen` | Store Profile | Edit store details |
| `StoreProfileScreen` | Profile | View/edit store branding |
| `ManageInventoryScreen` | Dashboard, More | Stock level management |
| `ManageOrdersScreen` | Dashboard, More | Order filtering by status |
| `OrderDetailScreen` | ManageOrdersScreen | Individual order details |
| `CustomOrdersScreen` | Dashboard, More | Customization request management |
| `ReportsScreen` | Dashboard, More | Sales reports & analytics |
| `SellerNotificationCenterScreen` | Dashboard bell icon | Notification feed |
| `SellerInboxScreen` | Dashboard message icon | Message inbox |

### Push Notification Deep-Links

The shell wires up `PushNotificationService.instance.onNavigateToScreen` to handle:
- `seller_order_detail` → Fetches order by `referenceId`, pushes `OrderDetailScreen`
- `seller_product_detail` → Switches to Products tab (index 2)
- `seller_custom_order` → Pushes `CustomOrdersScreen`

---

## 4. Database Schema (Seller-Related Tables)

### profiles
```sql
CREATE TABLE public.profiles (
    id              UUID REFERENCES auth.users ON DELETE CASCADE PRIMARY KEY,
    full_name       TEXT NOT NULL,
    email           TEXT NOT NULL UNIQUE,
    phone           TEXT,
    role            TEXT NOT NULL DEFAULT 'customer'
                        CHECK (role IN ('customer', 'seller', 'admin')),
    seller_status   TEXT NOT NULL DEFAULT 'pending'
                        CHECK (seller_status IN ('none', 'pending', 'approved', 'rejected')),
    avatar_url      TEXT,
    suspended       BOOLEAN DEFAULT false,
    rejection_reason TEXT,
    created_at      TIMESTAMPTZ DEFAULT now() NOT NULL
);
```

### stores (1 store per seller)
```sql
CREATE TABLE public.stores (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name            TEXT NOT NULL,
    tagline         TEXT,
    location        TEXT NOT NULL,
    brand_color     TEXT DEFAULT '#8B5A2B',
    banner_url      TEXT,
    logo_url        TEXT,
    rating          NUMERIC(2,1) DEFAULT 5.0,
    is_open         BOOLEAN DEFAULT true,
    is_active       BOOLEAN DEFAULT true,
    owner_id        UUID REFERENCES public.profiles(id),
    created_at      TIMESTAMPTZ DEFAULT now() NOT NULL
);
```
**Constraint:** One store per seller (enforced in `StoreService.createStoreSeller()`).

### products
```sql
CREATE TABLE public.products (
    id              TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    store_id        UUID REFERENCES public.stores(id),
    seller_id       UUID REFERENCES public.profiles(id),
    name            TEXT NOT NULL,
    description     TEXT,
    price           NUMERIC NOT NULL CHECK (price >= 0),
    category        TEXT NOT NULL DEFAULT 'General',
    tags            TEXT[] DEFAULT '{}',
    collection      TEXT,
    sku             TEXT,
    is_active       BOOLEAN NOT NULL DEFAULT true,
    is_featured     BOOLEAN NOT NULL DEFAULT false,
    is_published    BOOLEAN NOT NULL DEFAULT true,
    avg_rating      NUMERIC(2,1) NOT NULL DEFAULT 0,
    review_count    INTEGER NOT NULL DEFAULT 0,
    created_at      TIMESTAMPTZ DEFAULT now() NOT NULL,
    updated_at      TIMESTAMPTZ DEFAULT now() NOT NULL
);
```
**Categories:** `Casual`, `Formal`, `Sports`, `Sandals`, `Custom`, `Other`

### product_variants (size × color combinations)
```sql
CREATE TABLE public.product_variants (
    id              BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    product_id      TEXT REFERENCES public.products(id) ON DELETE CASCADE,
    size            TEXT NOT NULL,
    color           TEXT,
    stock           INTEGER NOT NULL DEFAULT 0 CHECK (stock >= 0),
    additional_price NUMERIC NOT NULL DEFAULT 0 CHECK (additional_price >= 0),
    sku             TEXT
);
```

### inventory (aggregated stock by size)
```sql
CREATE TABLE public.inventory (
    product_id      TEXT REFERENCES public.products(id) ON DELETE CASCADE,
    size            TEXT NOT NULL,
    stock           INTEGER NOT NULL DEFAULT 0 CHECK (stock >= 0),
    updated_at      TIMESTAMPTZ DEFAULT now() NOT NULL,
    PRIMARY KEY (product_id, size)
);
```
**Note:** Inventory is **derived** from `product_variants`. One row per unique size, stock summed across all colors. Synced via `_syncInventoryFromVariants()`.

### orders
```sql
CREATE TABLE public.orders (
    id              BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    customer_id     UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    store_id        UUID REFERENCES public.stores(id),
    status          TEXT NOT NULL DEFAULT 'placed'
                        CHECK (status IN ('placed', 'preparing', 'ready', 'received', 'cancelled', 'pending')),
    total_amount    NUMERIC NOT NULL CHECK (total_amount >= 0),
    payment_method  TEXT NOT NULL DEFAULT 'cash',
    payment_status  TEXT NOT NULL DEFAULT 'unpaid'
                        CHECK (payment_status IN ('paid', 'unpaid')),
    fulfillment     TEXT NOT NULL DEFAULT 'pickup'
                        CHECK (fulfillment IN ('pickup', 'delivery')),
    notes           TEXT,
    shipping_address JSONB,
    -- Legacy columns (do not use for new orders):
    size            TEXT,
    color           TEXT,
    quantity        INTEGER,
    created_at      TIMESTAMPTZ DEFAULT now() NOT NULL
);
```

### order_items
```sql
CREATE TABLE public.order_items (
    id          BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    order_id    BIGINT REFERENCES public.orders(id) ON DELETE CASCADE,
    product_id  TEXT REFERENCES public.products(id) ON DELETE SET NULL,
    size        TEXT,
    quantity    INTEGER NOT NULL DEFAULT 1 CHECK (quantity > 0),
    unit_price  NUMERIC NOT NULL DEFAULT 0 CHECK (unit_price >= 0)
);
```

### order_status_history
```sql
CREATE TABLE public.order_status_history (
    id          BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    order_id    BIGINT NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    status      TEXT NOT NULL,
    changed_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

### sales_transactions (POS in-person sales)
```sql
CREATE TABLE public.sales_transactions (
    id              BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    store_id        UUID REFERENCES public.stores(id) ON DELETE CASCADE,
    seller_id       UUID REFERENCES public.profiles(id),
    total_amount    NUMERIC NOT NULL CHECK (total_amount >= 0),
    payment_method  TEXT NOT NULL DEFAULT 'cash',
    amount_tendered NUMERIC DEFAULT 0,
    change_amount   NUMERIC DEFAULT 0,
    created_at      TIMESTAMPTZ DEFAULT now() NOT NULL
);
```

### sales_transaction_items (POS line items)
```sql
CREATE TABLE public.sales_transaction_items (
    id              BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    transaction_id  BIGINT REFERENCES public.sales_transactions(id) ON DELETE CASCADE,
    product_id      TEXT REFERENCES public.products(id) ON DELETE SET NULL,
    size            TEXT,
    quantity        INTEGER NOT NULL DEFAULT 1 CHECK (quantity > 0),
    unit_price      NUMERIC NOT NULL DEFAULT 0 CHECK (unit_price >= 0)
);
```

### customization_requests
```sql
CREATE TABLE public.customization_requests (
    id              BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    customer_id     UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    store_id        UUID REFERENCES public.stores(id),
    base_product_id TEXT REFERENCES public.products(id) ON DELETE SET NULL,
    color_choice    TEXT,
    material_choice TEXT,
    special_request TEXT,
    status          TEXT NOT NULL DEFAULT 'pending'
                        CHECK (status IN ('pending', 'approved', 'in_progress', 'completed', 'rejected')),
    created_at      TIMESTAMPTZ DEFAULT now() NOT NULL
);
```

### Key Relationships
```
profiles (1) ──→ (1) stores          (owner_id)
stores (1) ──→ (N) products          (store_id)
products (1) ──→ (N) product_variants (product_id)
products (1) ──→ (N) inventory        (product_id, derived)
products (1) ──→ (N) product_images   (product_id)
products (1) ──→ (N) order_items      (product_id)
products (1) ──→ (N) sales_transaction_items (product_id)
orders (1) ──→ (N) order_items       (order_id)
orders (1) ──→ (N) order_status_history (order_id)
sales_transactions (1) ──→ (N) sales_transaction_items (transaction_id)
customization_requests (N) ←── (1) stores (store_id)
customization_requests (N) ←── (1) profiles (customer_id)
```

---

## 5. POS (Point of Sale) System

**File:** `lib/screens/seller/pos_screen.dart`

### Purpose
In-person point-of-sale for walk-in customers. Supports **Cash** and **GCash** payments (Card disabled/coming soon).

### State Management
```dart
class _POSScreenState {
  final Map<String, _POSLineItem> _orderItems = {}; // Keyed by 'productId_size'
  String _searchKeyword = '';
  String _selectedCategory = 'All';
  int _panelIndex = 0;  // 0 = Products, 1 = Order
  bool _showSuccessOverlay = false;
  double _lastChange = 0;
}
```

### Two-Panel Layout
- **Panel 0 (Products):** Searchable, filterable product grid (3-column `GridView`)
- **Panel 1 (Order):** Line items with quantity controls, order summary

### POS Transaction Flow
```
1. Seller browses products (searchable grid with category filters)
2. Taps product → Bottom sheet opens (size selector + quantity)
3. "Add to Order" → _orderItems map updated, panel switches to Order view
4. Seller reviews items, adjusts quantities
5. "Checkout" → Payment sheet opens
6. Payment confirmed:
   a. OrderProvider.placeOrder(customerId: auth.profile['id'], ...)
      └─ SupabaseService.createOrder()
         ├─ INSERT INTO orders (status='pending', payment_method, total_amount)
         ├─ INSERT INTO order_items (triggers decrement_inventory_on_order)
         └─ Fire-and-forget: SellerNotificationService.createNewOrder()
   b. ProductService.syncProductActiveStatus() for each product
   c. Clear _orderItems, show success overlay (3 seconds)
```

### Payment Methods
| Method | Behavior |
|--------|----------|
| **Cash** | Shows tendered input field, calculates change |
| **GCash** | No tendered input needed |
| **Card** | Disabled (coming soon) |

### Product Display in POS
- Products with 0 stock → dimmed (opacity 0.48), not tappable
- Products with ≤5 stock → "Low (X)" badge
- Products with >5 stock → "In Stock" badge
- Category filter chips (horizontal scroll)
- Search by name or SKU

### Key Data Model
```dart
class _POSLineItem {
  final Map<String, dynamic> product;  // Full product map
  final String size;
  int quantity;
}
```

### Important: POS Creates BOTH Order + Sales Transaction
The POS flow calls `OrderProvider.placeOrder()` which creates an `orders` row AND `order_items` rows (triggering inventory decrement). This means POS sales appear in both the `orders` table and can be tracked via the order status flow.

**Revenue calculation always combines online orders + POS transactions.**

---

## 6. Order Lifecycle & Status Machine

### The Dual Status Problem (CRITICAL)

There are **two sets of status values** — this is the root cause of most order-related bugs:

| DB Value (`orders.status`) | Seller UI Label | Customer UI Label |
|---------------------------|-----------------|-------------------|
| `pending` | "Pending" | "Processing" tab |
| `placed` | (legacy) | "Processing" tab |
| `preparing` | "Confirmed" | Timeline step 2 |
| `ready` | "Ready" | Timeline step 3 |
| `received` | "Delivered" | Timeline step 4 |
| `cancelled` | "Cancelled" | "Returns" tab |

### The Mapping Layer

`SupabaseService.updateOrderStatus()` translates UI labels → DB values:

```dart
final statusMap = <String, String>{
  'confirmed': 'preparing',   // UI → DB
  'delivered': 'received',    // UI → DB
};
final dbStatus = statusMap[newStatus.toLowerCase()] ?? newStatus.toLowerCase();
```

### Status Flow
```
                    ┌─────────────────┐
                    │   createOrder() │
                    │ status=pending  │
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
                    │     PENDING     │◄── Seller can cancel
                    │  (new order)    │
                    └────────┬────────┘
                             │
                    Seller taps "Confirm"
                    UI sends: 'confirmed'
                    DB stores: 'preparing'
                    ┌────────▼────────┐
                    │   PREPARING     │
                    │  (confirmed)    │
                    └────────┬────────┘
                             │
                    Seller taps "Ready"
                    UI sends: 'ready'
                    DB stores: 'ready'
                    ┌────────▼────────┐
                    │     READY       │
                    │ (ready for      │
                    │  pickup/delivery)│
                    └────────┬────────┘
                             │
                    Seller taps "Delivered"
                    UI sends: 'delivered'
                    DB stores: 'received'
                    ┌────────▼────────┐
                    │    RECEIVED     │
                    │  (completed)    │
                    └─────────────────┘
```

### Customer-Facing Filter Mapping

| Customer Tab | Matches Status(es) |
|--------------|-------------------|
| `unpaid` | payment_status == 'unpaid' && status != 'cancelled' |
| `processing` | `pending`, `placed`, `preparing` |
| `shipped` | `ready` |
| `review` | `received` |
| `returns` | `cancelled` |

### DB Triggers on Status Change

| Trigger | Event | Purpose |
|---------|-------|---------|
| `trg_record_order_status_change` | AFTER UPDATE OF status | Inserts row into `order_status_history` |
| `trg_notify_on_order_status_change` | AFTER UPDATE OF status | Creates customer notification |
| `trg_notify_on_order_insert` | AFTER INSERT | Creates "payment pending" notification |
| `decrement_inventory_on_order` | INSERT on order_items | Decrements `inventory.stock` |

### Notification Trigger Mapping

| New Status | Notification Category | Title |
|------------|----------------------|-------|
| `pending` | `unpaid` | "Payment pending" |
| `placed` | `unpaid` | "Order placed" |
| `preparing` | `processing` | "Order confirmed" |
| `ready` | `shipped` | "Order ready" |
| `received` | `review` | "Order delivered" |
| `cancelled` | (no notification) | — |

---

## 7. Product Management

**File:** `lib/screens/seller/manage_products_screen.dart`
**Service:** `lib/services/product_service.dart`

### Product CRUD Flow

#### Create Product
```
1. Seller fills form (name, price, category, description, tags, images)
2. Adds variants (size × color combinations with stock + additional_price)
3. Adds customizations (optional: text, select, color options)
4. ProductService.createProduct():
   a. INSERT INTO products (name, price, category, ...)
   b. Upload images to Supabase Storage → product-images bucket
   c. INSERT INTO product_images (image_url, display_order, is_primary)
   d. INSERT INTO product_variants (size, color, stock, additional_price)
   e. INSERT INTO product_customizations (option_name, options, ...)
   f. _syncInventoryFromVariants() → aggregate stock by size
```

#### Update Product
```
1. ProductService.updateProduct():
   a. UPDATE products SET ...
   b. Delete old images from Storage + DB
   c. Upload new images → product_images
   d. Delete old variants + insert new ones
   e. Delete old customizations + insert new ones
   f. _syncInventoryFromVariants() → re-aggregate
```

#### Delete Product
```
ProductService.deleteProduct():
  1. Nullify FK refs:
     - order_items.product_id = null
     - sales_transaction_items.product_id = null
     - customization_requests.base_product_id = null
  2. Delete cascade tables:
     - inventory, product_variants, product_images, product_customizations
  3. Delete from products table
  4. Delete from Supabase Storage (product-images bucket)
```

### Product Grid (ManageProductsScreen)
- Uses `MasonryGridView.count` with 2 columns
- Image aspect ratios vary per product (deterministic based on product ID)
- Filter options: All, Low Stock, Out of Stock, Featured, Inactive
- Product card shows: image, Active/Inactive badge, Featured badge, Stock badge, Price, Category

### Product Card Actions (bottom sheet)
- Edit → Navigate to AddEditProductScreen
- Hide/Make Active → Toggle `is_active`
- Feature/Unfeature → Toggle `is_featured`
- Delete → Confirmation dialog, then permanent delete

---

## 8. Inventory System

**File:** `lib/screens/seller/manage_inventory_screen.dart`

### Two-Tier Inventory Model
```
product_variants (source of truth per size+color)
    │
    ▼  _syncInventoryFromVariants()
inventory (derived — one row per size, stock summed across colors)
```

### Inventory Sync Pattern
```dart
ProductService._syncInventoryFromVariants(productId, variants) {
  // 1. Group stock by size (sum across all colors)
  final stockBySize = <String, int>{};
  for (final v in variants) {
    stockBySize[v.size] = (stockBySize[v.size] ?? 0) + v.stock;
  }
  
  // 2. Delete existing inventory rows
  await _client.from('inventory').delete().eq('product_id', productId);
  
  // 3. Insert one row per unique size
  await _client.from('inventory').insert(stockBySize.entries.map((e) => {
    'product_id': productId,
    'size': e.key,
    'stock': e.value,
  }).toList());
  
  // 4. Fire low_stock notification if any size ≤ 5
}
```

### Stock Update Flow (Inventory Screen)
```
onStockChanged(newStock) {
  // 1. Update sizes map
  final sizesCopy = Map<String, int>.from(prod['sizes']);
  sizesCopy[item['size']] = newStock;
  
  // 2. Update product via provider
  await ProductProvider.updateProduct(prod['id'], {'sizes': sizesCopy});
  
  // 3. Auto-sync active status
  await ProductService.syncProductActiveStatus(prod['id']);
}
```

### Auto-Active Status
`syncProductActiveStatus(productId)` automatically sets `is_active` based on whether any variant has stock > 0.

### Size Resolution (Cart & POS)
```dart
// cart_helpers.dart — returns a record type
({String? variantId, double additionalPrice}) resolveVariant({
  required List variants,
  required String size,
  required String color,
}) {
  // Find variant matching size + color
  // Returns: variantId (nullable) + additionalPrice (0.0 if no match)
}
```

---

## 9. Revenue & Reporting

**Service:** `lib/services/sales_service.dart`
**Screen:** `lib/screens/seller/reports_screen.dart`

### Revenue is ALWAYS Combined
```dart
// Both sources are always combined for dashboard + reports
Future<double> getTodayRevenue(String storeId) async {
  final results = await Future.wait([
    getOnlineTodayRevenue(storeId),  // From orders table
    fetchTodaySales(storeId),         // From sales_transactions table
  ]);
  return results[0] + results[1];
}
```

### Revenue Sources
| Source | Table | Description |
|--------|-------|-------------|
| Online orders | `orders` + `order_items` | Customer checkout orders |
| POS sales | `sales_transactions` + `sales_transaction_items` | In-person register sales |

### 3-Step Store Order Chain
Orders don't have a direct `store_id` → `seller` link for querying. Instead:
```sql
-- Step 1: Get product IDs for store
SELECT id FROM products WHERE store_id = 'STORE_ID';

-- Step 2: Get order IDs from order_items
SELECT DISTINCT order_id FROM order_items WHERE product_id IN (product_ids);

-- Step 3: Fetch orders
SELECT * FROM orders WHERE id IN (order_ids) ORDER BY created_at DESC;
```

### Charts
- **Weekly:** 7-day bar/line chart (Mon=0, Sun=6)
- **Monthly:** 6-month trend (index 0 = 5 months ago)
- **Filter toggle:** All / Online / In-Store (POS)

### Reports Screen Sections
1. **Sales Overview** — Period selector (This Week / This Month), total revenue, comparison with previous period, bar chart
2. **Top Products** — Rank 1-5 by units sold
3. **Export** — CSV download (stub — shows SnackBar only)

---

## 10. Seller Notifications

**Service:** `lib/services/seller_notification_service.dart`
**Provider:** `lib/providers/seller_notification_provider.dart`
**Screen:** `lib/screens/seller/seller_notification_center_screen.dart`

### Notification Types
| Type | Trigger | Deduplication |
|------|---------|---------------|
| `new_order` | Customer places order | None (one per order) |
| `stale_order` | Order pending > threshold hours | Per order (unread only) |
| `low_stock` | Stock ≤ 5 after sale/update | Per product+size (unread only) |
| `custom_order_request` | Customer submits customization | None (one per request) |
| `new_message` | Customer sends message | Upsert with batching (cap 3 previews) |

### Message Notification Batching
```dart
// When a new message arrives for an existing unread notification:
// 1. Prepend new preview to metadata.previews (cap at 3)
// 2. Increment metadata.message_count
// 3. Refresh title, body, created_at
// 4. Do NOT create a new row
```

### Push Notifications
All notification types fire a push via `send-notification-push` Supabase Edge Function:
```dart
_triggerPush({
  required String storeId,
  required String type,
  required String title,
  required String body,
  String? referenceId,
  String? screen,  // Deep-link target
}) {
  // 1. Look up store owner_id from stores table
  // 2. Invoke send-notification-push function
}
```

### Bulk Operations (Selection Mode)
- Soft delete / restore
- Mark read / unread
- All operations support single and bulk modes

---

## 11. Messaging (Seller ↔ Customer)

**Provider:** `lib/providers/message_provider.dart`
**Service:** `lib/services/message_service.dart`
**Screen:** `lib/screens/seller/seller_inbox_screen.dart` (inbox), `lib/widgets/chat/chat_view.dart` (conversation)

### Architecture
- **Shared chat widget:** `ChatView` is parameterized by `viewerRole` ('seller' | 'customer')
- **Realtime:** Uses Supabase Realtime for live message updates
- **Conversations table:** Links `customer_id` + `store_id` with `last_message_at` for sorting
- **Messages table:** Stores individual messages with `conversation_id`, `sender_id`, `content`

### Seller Inbox
- Lists all conversations for the seller's store
- Shows last message preview, unread badge
- Tap to open `ChatView` with `viewerRole: 'seller'`

---

## 12. Custom Orders

**File:** `lib/screens/seller/custom_orders_screen.dart`

### Request Fields
- Base product name
- Color choice
- Material choice
- Special request
- Status (`pending` → `approved`/`rejected`)

### Actions
- Approve → Sets status to 'confirmed'
- Reject → Shows confirmation dialog

### ⚠️ Known Bug
The approve button has a documented TODO — it incorrectly calls `updateOrderStatus` on a customization request ID instead of a dedicated customization status update method.

---

## 13. Service Layer Reference

### SupabaseService (`lib/services/supabase_service.dart`)
| Method | Purpose |
|--------|---------|
| `login(email, password)` | Authenticate + fetch profile |
| `signUp(name, email, password, applyAsSeller)` | Register + create profile |
| `createOrder(...)` | Create order + items (with stock validation) |
| `updateOrderStatus(orderId, newStatus)` | Update status with UI→DB mapping |
| `fetchProducts()` | Customer product list with joins |
| `updateProduct(...)` | Update product + relations |
| `deleteProduct(id)` | Hard delete with cascade |
| `approveSellerApplication(userId)` | Set role=seller, seller_status=approved |
| `rejectSellerApplication(userId)` | Set seller_status=rejected |
| `_storeIdForSeller(sellerId)` | Look up store_id from owner_id |
| `_mapOrder(row)` | Transform raw order + joins into UI format |
| `_mapProduct(row)` | Transform raw product + joins into UI format |

### OrderService (`lib/services/order_service.dart`)
| Method | Purpose |
|--------|---------|
| `placeOrder(dto)` | Delegate to SupabaseService.createOrder() |
| `fetchStoreOrders(storeId)` | All orders for store (3-step chain) |
| `getRecentOrders(storeId, limit)` | Last N orders with profile/product joins |
| `getOrderCountByStatus(storeId)` | Status breakdown map |
| `updateOrderStatus(orderId, status)` | Delegate to SupabaseService |

### ProductService (`lib/services/product_service.dart`)
| Method | Purpose |
|--------|---------|
| `createProduct(...)` | Full product creation with images, variants, customizations |
| `updateProduct(...)` | Update with re-sync |
| `deleteProduct(productId)` | Hard delete with history preservation |
| `getSellerProducts()` | Current seller's products (with all relations) |
| `getProduct(productId)` | Single product with relations |
| `getSellerStoreId()` | Get store ID |
| `toggleActive(productId, isActive)` | Toggle visibility |
| `toggleFeatured(productId, isFeatured)` | Toggle featured |
| `syncProductActiveStatus(productId)` | Auto-manage is_active based on stock |
| `removeImage()` | Delete single image from DB + storage |
| `_syncInventoryFromVariants()` | Aggregate variant stock into inventory |

### StoreService (`lib/services/store_service.dart`)
| Method | Purpose |
|--------|---------|
| `getMyStore()` | Get current seller's store (null if not created) |
| `createStoreSeller(...)` | Create store (enforces one per seller) |
| `updateStoreSeller(...)` | Update store details + images |

### SalesService (`lib/services/sales_service.dart`)
| Method | Purpose |
|--------|---------|
| `recordSale(dto)` | Create POS transaction + items |
| `fetchTodaySales(storeId)` | Today's POS revenue |
| `fetchWeeklySales(storeId)` | Last 7 days POS transactions |
| `getTodayRevenue(storeId)` | Online + POS combined today |
| `getWeeklyRevenue(storeId)` | 7-day combined revenue chart |
| `getMonthlyRevenue(storeId)` | Current month combined |
| `getMonthlyRevenueTrend(storeId)` | 6-month trend |
| `getWeeklyReport(storeId)` | Full report data (SellerReportData) |
| `getPendingOrderCount(storeId)` | Orders needing action |

### SellerNotificationService (`lib/services/seller_notification_service.dart`)
| Method | Purpose |
|--------|---------|
| `getNotifications(storeId)` | Fetch recent notifications |
| `getUnreadCount(storeId)` | Count for badge display |
| `markAsRead(id)` / `markAllAsRead(storeId)` | Read state |
| `deleteNotification(id)` / `restoreNotification(id)` | Soft delete/restore |
| `createNewOrder(...)` | New order notification |
| `createStaleOrder(...)` | Stale order alert (deduplicated) |
| `createLowStock(...)` | Low stock alert (deduplicated) |
| `createNewMessage(...)` | Message notification (batched) |
| `createCustomOrderRequest(...)` | Custom order notification |

---

## 14. Provider Layer Reference

### OrderProvider (`lib/providers/order_provider.dart`)
**State:** `orders` (List<Map>), `customizations` (List<Map>), `isLoading`

| Method | Purpose |
|--------|---------|
| `loadOrders()` | Fetch store's orders + customizations |
| `placeOrder(...)` | Create order (delegate to service) |
| `updateOrderStatus(orderId, status)` | Update + reload |

### ProductProvider (`lib/providers/product_provider.dart`)
**State:** `products` (List<Map>), `_selectedCategory`, `categories`

| Method | Purpose |
|--------|---------|
| `loadProducts()` | Fetch all products |
| `getFilteredProducts(keyword)` | Filter by category + search |
| `selectCategory(category)` | Set active filter |
| `addProduct(data)` | Create + reload |
| `updateProduct(id, data)` | Update + reload |
| `deleteProduct(id)` | Delete + reload |

### SellerNotificationProvider (`lib/providers/seller_notification_provider.dart`)
**State:** `notifications` (List<SellerNotification>), `unreadBadge` (String)

| Method | Purpose |
|--------|---------|
| `init(storeId)` | Initialize with Realtime subscription |
| `refreshNotifications()` | Reload + count unread |
| `markAsRead(id)` | Mark single read |
| `markAllAsRead()` | Mark all read |
| `deleteNotification(id)` | Soft delete |

### MessageProvider (`lib/providers/message_provider.dart`)
**State:** `conversations`, `unreadBadge`

| Method | Purpose |
|--------|---------|
| `subscribeToInbox(storeId)` | Realtime subscription |
| `loadConversationsForStore(storeId)` | Fetch conversations |
| `refreshInbox()` | Force reload |

---

## 15. Widget Reference

### Seller-Specific Widgets (`lib/widgets/seller/`)

| Widget | File | Purpose |
|--------|------|---------|
| `SellerMetricCard` | `seller_metric_card.dart` | Dashboard metrics (large/small variants) |
| `SellerOrderCard` | `seller_order_card.dart` | Order card with status action button |
| `SellerStatusChip` | `seller_status_chip.dart` | Colored status badge (UI labels) |
| `SellerAlertChip` | `seller_alert_chip.dart` | Horizontal scrolling alert chips |
| `SellerInventoryRow` | `seller_inventory_row.dart` | Product + size + stock slider |
| `SellerProductRow` | `seller_product_row.dart` | Product row for list views |
| `PaymentMethodPill` | `payment_method_pill.dart` | Payment method selector (Cash/GCash/Card) |
| `SellerSparkline` | `seller_sparkline.dart` | Mini sparkline chart |
| `SellerRevenueLineChart` | `seller_revenue_line_chart.dart` | Revenue line chart |
| `SellerWeeklyBar` | `seller_weekly_bar.dart` | Bar chart for weekly/monthly |

### Shared Widgets

| Widget | File | Purpose |
|--------|------|---------|
| `SoleStatusChip` | `sole_status_chip.dart` | Customer-facing status chip (DB labels) |
| `SoleTimeline` | `sole_timeline.dart` | Vertical timeline component |
| `SoleProductCard` | `sole_product_card.dart` | Product card for masonry grid |
| `ChatView` | `chat/chat_view.dart` | Shared chat (parameterized by viewerRole) |

---

## 16. RLS Policies (Seller Scope)

### orders
| Operation | Policy |
|-----------|--------|
| SELECT (seller) | `EXISTS (SELECT 1 FROM stores WHERE id = store_id AND owner_id = auth.uid())` |
| UPDATE | `EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND (role = 'seller' OR role = 'admin'))` |

### products
| Operation | Policy |
|-----------|--------|
| SELECT | Anyone can read |
| INSERT/UPDATE/DELETE | Seller or Admin role |

### product_variants, product_images, inventory, product_customizations
| Operation | Policy |
|-----------|--------|
| SELECT | Anyone can read |
| ALL | Product owner (seller_id = auth.uid()) or Admin |

### sales_transactions, sales_transaction_items
| Operation | Policy |
|-----------|--------|
| SELECT (seller) | `EXISTS (SELECT 1 FROM stores WHERE id = store_id AND owner_id = auth.uid())` |
| INSERT (seller) | Same as SELECT |

### stores
| Operation | Policy |
|-----------|--------|
| SELECT | Anyone can read |
| INSERT | `auth.uid() = owner_id` |
| UPDATE | `auth.uid() = owner_id` |

---

## 17. Known Bugs & Gotchas

### ⚠️ CRITICAL: Dual Status Vocabulary
The seller UI uses labels (`confirmed`, `delivered`) that differ from DB values (`preparing`, `received`). This mapping is ONLY in `SupabaseService.updateOrderStatus()`. Some screens bypass this, causing inconsistencies.

### ⚠️ DO NOT
- **Don't use `product_variants.stock` for validation** — use `inventory.stock` as authoritative
- **Don't forget to sync active status after stock changes** — call `syncProductActiveStatus()`
- **Don't create orders without store_id lookup** — products → store_id chain is required
- **Don't assume POS creates only a sales transaction** — it creates an order + order_items (triggering inventory decrement)
- **Don't use raw DB status values in UI labels** — always map through the UI→DB layer

### ⚠️ ALWAYS
- **Always combine online + POS for revenue** — never use just one source
- **Always use the 3-step chain for store orders** — products → order_items → orders
- **Always call `_syncInventoryFromVariants()` after variant changes** — inventory is derived
- **Always handle null store_id** — new sellers may not have a store yet

### Known Issues
| # | Issue | Impact |
|---|-------|--------|
| 1 | `ManageOrdersScreen` tab filtering now fixed (uses `uiToDbFilter` map) | Was: Confirmed/Delivered tabs empty |
| 2 | `OrderDetailScreen` may show stale status after update | Seller sees old status briefly |
| 3 | `SellerOrdersScreen` sends raw DB values (bypasses mapping) | Inconsistent with ManageOrdersScreen |
| 4 | `custom_orders_screen.dart` approve button calls wrong function | Custom order approval broken |
| 5 | CSV export is a stub | Shows SnackBar only |
| 6 | POS History button is a stub | No implementation |
| 7 | Card payment is disabled | Coming soon |
| 8 | `isFollowing()` always returns false synchronously | Use `isFollowingAsync()` instead |

---

## 18. Common Tasks

### Adding a New Seller Screen
1. Create screen in `lib/screens/seller/`
2. Add navigation from appropriate parent screen
3. Use `AppConstants.sellerSurface` as background
4. Use `AppConstants.sellerCardBg` for cards
5. Use `AppConstants.sellerShadow` for card shadows
6. Follow existing pattern for AppBar (secondary color, white text)

### Modifying Dashboard Metrics
1. Edit `_DashboardData` class in `seller_dashboard_screen.dart`
2. Add data fetching in `_fetchDashboardData()`
3. Update `_buildMetricsGrid()` or add new section
4. Use existing widgets (`SellerMetricCard`, `SellerSparkline`, etc.)

### Adding a New Report Section
1. Add data model in `SellerReportData` if needed
2. Add fetching logic in `SalesService`
3. Update `_buildReportBody()` in `reports_screen.dart`
4. Use `SellerRevenueLineChart` for charts

### Fixing Order Status Issues
1. Check `OrderService.fetchStoreOrders()` — 3-step chain
2. Verify RLS policies on `orders` table
3. Check `OrderProvider.updateOrderStatus()` for error handling
4. Check `SupabaseService.updateOrderStatus()` status mapping

### Color Constants for Seller UI
```dart
// Seller-specific colors
static const Color sellerSurface = Color(0xFFF8F9FA);    // Background
static const Color sellerCardBg = Color(0xFFFFFFFF);       // Cards

// Status colors
static const Color statusPendingColor = Color(0xFFF59E0B);  // Amber
static const Color statusConfirmedColor = Color(0xFF3B82F6); // Blue
static const Color statusReadyColor = Color(0xFF8B5A2B);     // Primary brand
static const Color statusDeliveredColor = Color(0xFF6B8F47);  // Success green
static const Color statusCancelledColor = Color(0xFFD64545);  // Error red

// Stock colors
static const Color lowStockColor = Color(0xFFEF4444);   // Urgent red
static const Color okStockColor = Color(0xFF6B8F47);     // Safe green
```

### Database Query Patterns

#### Get Store's Orders (3-step chain)
```sql
-- Step 1: Get product IDs for store
SELECT id FROM products WHERE store_id = 'STORE_ID';

-- Step 2: Get order IDs from order_items
SELECT DISTINCT order_id FROM order_items WHERE product_id IN (product_ids);

-- Step 3: Fetch orders
SELECT * FROM orders WHERE id IN (order_ids) ORDER BY created_at DESC;
```

#### Get Today's Revenue (Online + POS)
```sql
-- Online orders (paid, non-cancelled)
SELECT SUM(total_amount) FROM orders
WHERE id IN (order_ids)
AND payment_status = 'paid'
AND status != 'cancelled'
AND created_at >= 'START_OF_DAY';

-- POS transactions
SELECT SUM(total_amount) FROM sales_transactions
WHERE store_id = 'STORE_ID'
AND created_at >= 'START_OF_DAY';
```

#### Get Top Products (by units sold)
```sql
-- Combine online order_items + sales_transaction_items
SELECT product_id, SUM(quantity) as units, SUM(quantity * unit_price) as revenue
FROM (
  SELECT product_id, quantity, unit_price FROM order_items WHERE order_id IN (order_ids)
  UNION ALL
  SELECT product_id, quantity, unit_price FROM sales_transaction_items WHERE transaction_id IN (tx_ids)
) combined
GROUP BY product_id
ORDER BY units DESC
LIMIT 5;
```
