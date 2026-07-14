# SoleVision — Seller Module Guide

**Last Updated:** July 9, 2026  
**Purpose:** Comprehensive reference for AI agents working on the Seller (Artisan) side of the application.

---

## Quick Summary

The Seller module is the core revenue-generating side of SoleVision. It provides artisans with tools to manage their store, process sales (online + POS), manage inventory, and view analytics. The seller shell has 5 tabs: Dashboard, POS, Products, Orders, Profile.

---

## Seller Shell Architecture

### Navigation Structure
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

---

## Screen-by-Screen Reference

### 1. Seller Dashboard (`seller_dashboard_screen.dart`)

**Purpose:** "Morning Briefing" — answers 4 questions instantly: sales, attention, orders, stock.

**Data Model:**
```dart
class _DashboardData {
  final double todayRevenue;           // Online + POS combined
  final int pendingOrders;             // Orders needing action
  final List<double> weeklySalesChart; // 7-day revenue trend
  final List<double> monthlySalesChart; // 6-month trend
  final List<Map<String, dynamic>> recentOrders; // Last 5 orders
  final Map<String, int> ordersByStatus;         // Status breakdown
  final Map<String, dynamic>? store;             // Store details
  final int lowStockCount;             // Items needing restock
  final int pendingCustoms;            // Custom order requests
  final List<Map<String, dynamic>> lowStockItems; // Low stock details
  final List<Map<String, dynamic>> staleOrders;   // Orders stuck in 'placed'
}
```

**Dashboard Sections:**
1. **Metrics Grid** — Today's Sales (large), Pending Orders, Low Stock, Custom Orders
2. **Alert Strip** — Horizontal scrolling alerts for low stock, stale orders, pending customs
3. **Order Status Summary** — Visual breakdown: Placed → Preparing → Ready → Received
4. **Recent Orders** — Last 5 orders with quick status update
5. **Quick Actions** — POS, Inventory, Orders, Reports
6. **Weekly Sales Chart** — Bar chart showing daily revenue
7. **Monthly Trend** — 6-month revenue trend

**Key Behaviors:**
- Pull-to-refresh reloads all data
- Metric cards are tappable (navigates to relevant screen)
- Order status updates trigger product active status sync
- Uses `SellerMetricCard`, `SellerSparkline`, `SellerWeeklyBar`, `SellerAlertChip` widgets

**Revenue Calculation (CRITICAL):**
```dart
// Revenue ALWAYS combines both sources
final results = await Future.wait([
  salesService.getTodayRevenue(storeId),  // Online orders + POS
  salesService.getWeeklyRevenue(storeId),
  salesService.getPendingOrderCount(storeId),
  orderService.getRecentOrders(storeId, limit: 5),
  // ...
]);
```

**Order Status Update Flow:**
```
placed → preparing → ready → received
         (cancelled → placed)
```

---

### 2. POS Screen (`pos_screen.dart`)

**Purpose:** In-person point-of-sale for walk-in customers. Supports cash and GCash payments.

**State Management:**
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

**Two-Panel Layout:**
- **Products Panel** — Searchable, filterable product grid
- **Order Panel** — Line items with quantity controls, order summary

**POS Flow:**
```
1. Seller selects product from grid
2. Product sheet opens (size selector, quantity)
3. Item added to _orderItems map
4. Panel switches to Order view
5. Seller reviews items, adjusts quantities
6. Checkout button opens payment sheet
7. Payment confirmed → creates order + sales transaction
8. Success overlay shows (3 seconds)
```

**Payment Methods:**
- **Cash** — Shows tendered input, calculates change
- **GCash** — No tendered input needed
- **Card** — Disabled (coming soon)

**Transaction Creation:**
```dart
// Creates BOTH order record AND POS transaction
await orderProvider.placeOrder(
  customerId: auth.profile?['id'] ?? 'seller-pos',
  items: orderItems,
  totalAmount: _subtotal,
  deliveryAddress: 'In-store POS',
  paymentMethod: paymentMethod,
);

// Auto-sync active status for each product after sale
for (final item in items) {
  await ProductService.instance.syncProductActiveStatus(item.product['id']);
}
```

**Key Behaviors:**
- Products with 0 stock are dimmed (opacity 0.48)
- Products with ≤5 stock show "Low (X)" badge
- Success overlay shows change amount for cash transactions
- Clear order requires confirmation dialog

---

### 3. Manage Products (`manage_products_screen.dart`)

**Purpose:** Product CRUD with masonry grid view, search, and filter.

**Filter Options:**
- All (default)
- Low Stock (stock > 0 and ≤ 5)
- Out of Stock (stock = 0)
- Featured
- Inactive

**Grid Layout:**
- Uses `MasonryGridView.count` with 2 columns
- Image aspect ratios vary per product for visual rhythm
- Deterministic ratios based on product ID (not list index)

**Product Card Features:**
- Primary image with aspect ratio variation
- Active/Inactive badge
- Featured badge (★ FEATURED)
- Stock badge (OUT / Low (X) / In stock)
- Price in monospace font
- Category label

**Actions (via bottom sheet):**
- Edit — Navigate to AddEditProductScreen
- Hide/Make Active — Toggle visibility
- Feature/Unfeature — Toggle featured status
- Delete — Confirmation dialog, then permanent delete

**Delete Product Flow:**
```dart
// 1. Nullify references in history tables
await _client.from('order_items').update({'product_id': null}).eq('product_id', productId);
await _client.from('sales_transaction_items').update({'product_id': null}).eq('product_id', productId);
await _client.from('customization_requests').update({'base_product_id': null}).eq('base_product_id', productId);

// 2. Delete cascade tables
await _client.from('inventory').delete().eq('product_id', productId);
await _client.from('product_variants').delete().eq('product_id', productId);
await _client.from('product_images').delete().eq('product_id', productId);
await _client.from('product_customizations').delete().eq('product_id', productId);

// 3. Delete the product itself
await _client.from('products').delete().eq('id', productId);
```

---

### 4. Manage Orders (`manage_orders_screen.dart`)

**Purpose:** Order management with status-based filtering.

**Tab Filters:**
| Tab | Status Filter | Count Badge |
|-----|---------------|-------------|
| All | None | Total count |
| Pending | status = 'pending' | Pending count |
| Confirmed | status = 'confirmed' | Confirmed count |
| Ready | status = 'ready' | Ready count |
| Delivered | status = 'delivered' | Delivered count |
| Cancelled | status = 'cancelled' | Cancelled count |

**Order Status Flow:**
```
pending → confirmed → ready → delivered
(cancelled → pending)
```

**Order Card (`SellerOrderCard`):**
- Customer name
- Product name
- Quantity
- Total amount
- Time ago
- Status chip (color-coded)
- Primary action button (status update)
- View details button

**Status Update:**
```dart
void _updateStatus(int orderId, String currentStatus) async {
  String nextStatus;
  switch (currentStatus.toLowerCase()) {
    case 'pending': nextStatus = 'confirmed'; break;
    case 'confirmed': nextStatus = 'ready'; break;
    case 'ready': nextStatus = 'delivered'; break;
    case 'cancelled': nextStatus = 'pending'; break;
    default: return;
  }
  final success = await Provider.of<OrderProvider>(context, listen: false)
      .updateOrderStatus(orderId, nextStatus);
}
```

---

### 5. Manage Inventory (`manage_inventory_screen.dart`)

**Purpose:** Stock level management with real-time updates.

**Summary Strip:**
- In Stock count (green)
- Low Stock count (amber)
- Out of Stock count (red)
- Tappable to filter

**Inventory Row (`SellerInventoryRow`):**
- Product name
- Size
- Current stock value
- Slider for stock adjustment
- Auto-sync active status after change

**Stock Update Flow:**
```dart
onStockChanged: (newStock) async {
  // 1. Update sizes map
  final sizesCopy = Map<String, int>.from(prod['sizes']);
  sizesCopy[item['size']] = newStock;
  
  // 2. Update product via provider
  await Provider.of<ProductProvider>(context, listen: false)
      .updateProduct(prod['id'], {'sizes': sizesCopy});
  
  // 3. Auto-sync active status
  await ProductService.instance.syncProductActiveStatus(prod['id']);
}
```

---

### 6. Reports (`reports_screen.dart`)

**Purpose:** Sales reports with weekly/monthly toggle.

**Report Sections:**
1. **Sales Overview**
   - Period selector (This Week / This Month)
   - Date range label
   - Total revenue
   - Week-over-week / month-over-month comparison
   - Bar chart (SellerWeeklyBar)

2. **Top Products**
   - Rank 1-5
   - Product name
   - Units sold
   - Revenue

3. **Export**
   - Download CSV button (stub — shows SnackBar)

**Data Source:**
```dart
// Combines online orders + POS transactions
Future<SellerReportData> getWeeklyReport(
  String storeId, {
  DateTime? weekStart,
  DateTime? weekEnd,
  bool monthly = false,
}) async {
  // Fetches from both 'orders' and 'sales_transactions'
  // Aggregates daily revenue
  // Fetches top 5 products from order_items + sales_transaction_items
}
```

---

### 7. Custom Orders (`custom_orders_screen.dart`)

**Purpose:** Manage customer customization requests.

**Request Fields:**
- Base product name
- Color choice
- Material choice
- Special request
- Status (pending/confirmed/rejected)

**Actions:**
- Approve → Sets status to 'confirmed'
- Reject → Shows confirmation dialog

---

## Key Services Reference

### SalesService (`lib/services/sales_service.dart`)

| Method | Purpose | Returns |
|--------|---------|---------|
| `recordSale(dto)` | Create POS transaction + items | transaction ID |
| `fetchTodaySales(storeId)` | Today's POS revenue | double |
| `fetchWeeklySales(storeId)` | Last 7 days POS transactions | List<Map> |
| `getTodayRevenue(storeId)` | Online + POS combined today | double |
| `getWeeklyRevenue(storeId)` | 7-day combined revenue chart | List<double> |
| `getMonthlyRevenue(storeId)` | Current month combined | double |
| `getMonthlyRevenueTrend(storeId)` | 6-month trend | List<double> |
| `getWeeklyReport(storeId)` | Full report data | SellerReportData |
| `getPendingOrderCount(storeId)` | Orders needing action | int |

**Size Resolution in recordSale:**
```dart
// Same logic as createOrder
// 1. Exact match
// 2. Numeric match (strip prefix)
// 3. Fallback: first available
```

### OrderService (`lib/services/order_service.dart`)

| Method | Purpose | Returns |
|--------|---------|---------|
| `placeOrder(dto)` | Create order (delegates to SupabaseService) | order ID |
| `fetchStoreOrders(storeId)` | All orders for store | List<Map> |
| `getRecentOrders(storeId, limit)` | Last N orders with details | List<Map> |
| `getOrderCountByStatus(storeId)` | Status breakdown | Map<String, int> |
| `updateOrderStatus(orderId, status)` | Update order status | void |

**Store Order Filtering (3-step chain):**
```dart
// 1. Get product IDs for store
final productRows = await _client.from('products').select('id').eq('store_id', storeId);

// 2. Get order IDs from order_items
final itemRows = await _client.from('order_items').select('order_id').inFilter('product_id', productIds);

// 3. Fetch orders
final data = await _client.from('orders').select(...).inFilter('id', orderIds);
```

### ProductService (`lib/services/product_service.dart`)

| Method | Purpose | Returns |
|--------|---------|---------|
| `createProduct(...)` | Full product creation | product ID |
| `updateProduct(...)` | Update with variants | void |
| `deleteProduct(productId)` | Hard delete with history preservation | void |
| `getSellerProducts()` | Current seller's products | List<Map> |
| `getProduct(productId)` | Single product with relations | Map |
| `getSellerStoreId()` | Get store ID | String? |
| `toggleActive(productId, isActive)` | Toggle visibility | void |
| `toggleFeatured(productId, isFeatured)` | Toggle featured | void |
| `syncProductActiveStatus(productId)` | Auto-manage is_active based on stock | void |

**Inventory Sync Pattern:**
```dart
// product_variants = source of truth (per size+color)
// inventory = derived table (aggregated per size)
// Always call _syncInventoryFromVariants() after variant changes

Future<void> _syncInventoryFromVariants(String productId, List<ProductVariant> variants) async {
  // 1. Group stock by size (sum across colors)
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
}
```

---

## Seller Widgets Reference

### `SellerMetricCard` (`lib/widgets/seller/seller_metric_card.dart`)
- Used in dashboard metrics grid
- Supports large/small variants
- Optional trailing widget (e.g., sparkline)
- Tappable with onTap callback

### `SellerOrderCard` (`lib/widgets/seller/seller_order_card.dart`)
- Displays order info with customer/product details
- Primary action button (status update)
- View details button
- Status chip with color coding

### `SellerWeeklyBar` (`lib/widgets/seller/seller_weekly_bar.dart`)
- Bar chart for weekly/monthly revenue
- Configurable day labels
- Today index highlighting

### `SellerSparkline` (`lib/widgets/seller/seller_sparkline.dart`)
- Mini sparkline chart for quick trends
- Used in dashboard metric card

### `SellerAlertChip` (`lib/widgets/seller/seller_alert_chip.dart`)
- Horizontal scrolling alert chips
- Icon + text + onTap

### `SellerStatusChip` (`lib/widgets/seller/seller_status_chip.dart`)
- Color-coded status badge
- Used in order cards and custom orders

### `SellerInventoryRow` (`lib/widgets/seller/seller_inventory_row.dart`)
- Product name, size, stock slider
- Real-time stock adjustment
- Auto-sync on change

### `SellerProductRow` (`lib/widgets/seller/seller_product_row.dart`)
- Product row for list views
- Image, name, price, stock

### `PaymentMethodPill` (`lib/widgets/seller/payment_method_pill.dart`)
- Payment method selector (Cash, GCash, Card)
- Selected state styling
- Disabled state for unavailable methods

---

## Color Constants for Seller UI

```dart
// Seller-specific colors
static const Color sellerSurface = Color(0xFFF8F9FA);    // Slightly cooler than customer
static const Color sellerCardBg = Color(0xFFFFFFFF);       // Pure white cards

// Status colors
static const Color statusPendingColor = Color(0xFFF59E0B);  // Amber
static const Color statusConfirmedColor = Color(0xFF3B82F6); // Blue
static const Color statusReadyColor = Color(0xFF8B5A2B);     // Primary (brand)
static const Color statusDeliveredColor = Color(0xFF6B8F47);  // Success green
static const Color statusCancelledColor = Color(0xFFD64545);  // Error red

// Stock colors
static const Color lowStockColor = Color(0xFFEF4444);   // Urgent red
static const Color okStockColor = Color(0xFF6B8F47);     // Safe green

// Shadow
static final List<BoxShadow> sellerShadow = [
  BoxShadow(
    color: Colors.black.withAlpha(15),
    blurRadius: 10,
    offset: const Offset(0, 2),
  ),
];
```

---

## Common Tasks

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
4. Use existing widgets (`SellerMetricCard`, etc.)

### Adding a New Report Section
1. Add data model in `SellerReportData` if needed
2. Add fetching logic in `SalesService`
3. Update `_buildReportBody()` in `reports_screen.dart`
4. Use `SellerWeeklyBar` for charts

### Fixing Order Status Issues
1. Check `OrderService.fetchStoreOrders()` — 3-step chain
2. Verify RLS policies on `orders` table
3. Check `OrderProvider.updateOrderStatus()` for error handling

---

## Database Queries Reference

### Get Store's Orders (3-step chain)
```sql
-- Step 1: Get product IDs for store
SELECT id FROM products WHERE store_id = 'STORE_ID';

-- Step 2: Get order IDs from order_items
SELECT DISTINCT order_id FROM order_items WHERE product_id IN (product_ids);

-- Step 3: Fetch orders
SELECT * FROM orders WHERE id IN (order_ids) ORDER BY created_at DESC;
```

### Get Today's Revenue (Online + POS)
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

### Get Weekly Revenue Chart
```sql
-- Aggregate by weekday (Mon=0, Sun=6)
SELECT 
  EXTRACT(DOW FROM created_at) as day_index,
  SUM(total_amount) as daily_total
FROM (
  SELECT total_amount, created_at FROM orders WHERE id IN (order_ids) AND status != 'cancelled'
  UNION ALL
  SELECT total_amount, created_at FROM sales_transactions WHERE store_id = 'STORE_ID'
) combined
WHERE created_at >= '7_DAYS_AGO'
GROUP BY day_index;
```

### Get Top Products (by units sold)
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

---

## Gotchas & Known Issues

### ⚠️ DO NOT
- **Don't use `product_variants.stock` for validation** — use `inventory.stock` as authoritative
- **Don't forget to sync active status after stock changes** — call `syncProductActiveStatus()`
- **Don't create orders without store_id lookup** — products → store_id chain is required
- **Don't assume POS creates only a sales transaction** — it creates BOTH order + sales transaction

### ⚠️ ALWAYS
- **Always combine online + POS for revenue** — never use just one source
- **Always use the 3-step chain for store orders** — products → order_items → orders
- **Always call `_syncInventoryFromVariants()` after variant changes** — inventory is derived
- **Always handle null store_id** — new sellers may not have a store yet

### Known Issues
- `isFollowing()` always returns false synchronously (use `isFollowingAsync()`)
- CSV export is a stub (shows SnackBar only)
- Settings screen is a stub (shows SnackBar only)
- POS History button is a stub (no implementation)
- Card payment is disabled (coming soon)

---

## Data Flow Diagrams

### POS Sale Flow
```
POSScreen
  │
  ├─→ Product selected → Size/Qty sheet
  │
  ├─→ Add to order → _orderItems map
  │
  ├─→ Checkout → Payment sheet
  │
  └─→ Confirm payment
       │
       ├─→ OrderProvider.placeOrder()
       │    └─→ SupabaseService.createOrder()
       │         ├─→ INSERT INTO orders
       │         ├─→ INSERT INTO order_items (triggers inventory decrement)
       │         └─→ Returns order data
       │
       ├─→ ProductService.syncProductActiveStatus()
       │    └─→ Checks inventory + variants → updates products.is_active
       │
       └─→ Success overlay (3 seconds)
```

### Dashboard Load Flow
```
SellerDashboardScreen
  │
  ├─→ StoreService.getMyStore() → get storeId
  │
  └─→ _fetchDashboardData()
       │
       ├─→ SalesService.getTodayRevenue(storeId)
       │    └─→ Online orders + POS transactions
       │
       ├─→ SalesService.getWeeklyRevenue(storeId)
       │    └─→ 7-day combined chart
       │
       ├─→ SalesService.getMonthlyRevenueTrend(storeId)
       │    └─→ 6-month trend
       │
       ├─→ OrderService.getRecentOrders(storeId, limit: 5)
       │    └─→ 3-step chain + profile/product joins
       │
       ├─→ OrderService.getOrderCountByStatus(storeId)
       │    └─→ Status breakdown
       │
       ├─→ ProductProvider.loadProducts()
       │    └─→ For low stock detection
       │
       └─→ OrderProvider.loadOrders()
            └─→ For stale orders, pending customs
```

---

## Testing Checklist

### Dashboard
- [ ] Today's sales shows combined online + POS
- [ ] Pending orders count is accurate
- [ ] Low stock items display correctly
- [ ] Weekly chart shows correct daily values
- [ ] Pull-to-refresh works
- [ ] Metric card taps navigate correctly
- [ ] Order status updates refresh dashboard

### POS
- [ ] Product grid loads with images
- [ ] Search filters products by name/SKU
- [ ] Category filter works
- [ ] Product sheet shows available sizes only
- [ ] Add to order works
- [ ] Quantity controls work
- [ ] Clear order requires confirmation
- [ ] Cash payment calculates change correctly
- [ ] GCash payment completes without tendered input
- [ ] Success overlay shows and auto-dismisses
- [ ] Order + sales transaction both created
- [ ] Product active status syncs after sale

### Products
- [ ] Grid loads with masonry layout
- [ ] Filter chips work (All, Low Stock, Out, Featured, Inactive)
- [ ] Search filters products
- [ ] Product card shows correct badges
- [ ] Add product navigates to form
- [ ] Edit product loads full data
- [ ] Delete requires confirmation
- [ ] Toggle active/featured works
- [ ] Loading shimmer shows masonry preview

### Orders
- [ ] Tab filters work correctly
- [ ] Order count badges show correct numbers
- [ ] Status update button works
- [ ] Order detail screen loads correctly
- [ ] Empty state shows for no orders

### Inventory
- [ ] Summary strip shows correct counts
- [ ] Filter pills work
- [ ] Stock slider updates in real-time
- [ ] Auto-sync updates product active status
- [ ] Grouping by product name works

### Reports
- [ ] Weekly/monthly toggle works
- [ ] Revenue chart shows correct values
- [ ] Week-over-week comparison displays
- [ ] Top products list shows correct data
- [ ] Export button shows coming soon SnackBar

---

*SoleVision Seller Module Guide — July 9, 2026*
