# Seller Products Architecture

> **Purpose:** Quick onboarding doc for AI agents working on the seller-facing product management module (create, edit, list, inventory, POS product grid, barcode scanning).

---

## 1. Database Schema (products side)

### Core Tables

```
products                  product_images             product_variants
┌─────────────────────┐   ┌────────────────────┐    ┌────────────────────────┐
│ id (TEXT, PK)       │──→│ product_id (FK)     │   │ product_id (FK)        │
│ store_id (UUID, FK) │   │ image_url (TEXT)    │   │ size (TEXT)            │
│ seller_id (UUID,FK) │   │ display_order (INT) │    │ color (TEXT, nullable)  │
│ name (TEXT)         │   │ is_primary (BOOL)   │    │ stock (INT ≥ 0)         │
│ description (TEXT)  │   └────────────────────┘    │ additional_price (DEC)  │
│ price (DEC ≥ 0)     │                             │ sku (TEXT, nullable)    │
│ category (TEXT)     │   inventory                  └────────────────────────┘
│ tags (TEXT[])       │   ┌────────────────────┐
│ barcode (TEXT)      │   │ product_id (FK)    │    product_customizations
│ is_active (BOOL)    │   │ size (TEXT)        │    ┌────────────────────────┐
│ is_featured (BOOL)  │   │ stock (INT)        │    │ product_id (FK)        │
│ is_published (BOOL) │   │ PK: (product_id,   │    │ option_name (TEXT)      │
│ avg_rating (DEC)    │   │     size)          │    │ option_type (TEXT)      │
│ review_count (INT)  │   └────────────────────┘    │ options (TEXT[])        │
└─────────────────────┘                             │ is_required (BOOL)      │
                                                    │ additional_price (DEC)  │
   stores                                            └────────────────────────┘
   ┌─────────────────┐
   │ id (UUID, PK)   │←── products.store_id
   │ owner_id (UUID) │←── products.seller_id → profiles(id)
   │ name (TEXT)     │
   │ is_active (BOOL)│
   └─────────────────┘
```

**Key relationships:**
- `stores.owner_id` → `profiles(id)` — one store per seller
- `products.seller_id` → `profiles(id)` — defense-in-depth scoping (redundant with store_id)
- `inventory` is **synced from `product_variants`** (groups variants by size, sums stock across colors). See `_syncInventoryFromVariants()` in `ProductService`.

---

## 2. Service Layer

### `ProductService` (`lib/services/product_service.dart`)
Singleton (`.instance`). All seller product CRUD goes through this service — never call Supabase directly.

| Method | Purpose |
|--------|---------|
| `createProduct(storeId, name, price, description, category, tags, images, variants, customizations, {barcode})` | Full product creation: 1) Insert products row, 2) Upload images to Storage, 3) Insert product_images rows, 4) Insert variants, 5) Sync inventory, 6) Insert customizations. Returns new product ID. |
| `updateProduct(productId, name, price, description, category, tags, newImages, existingImageUrls, variants, customizations, isActive, isFeatured, {barcode})` | Full update: 1) Update products row, 2) Upload new images, 3) Delete + re-insert variants, 4) Sync inventory, 5) Delete + re-insert customizations. |
| `deleteProduct(productId)` | Cascade-aware delete: 1) Nullify FKs in order_items/sales_transaction_items/customization_requests, 2) Delete inventory/variants/images (from Storage too)/customizations, 3) Delete product row. |
| `getSellerProducts()` | Get ALL products for current seller's store, with `product_images`, `product_variants`, `product_customizations`, `inventory` joined. Scoped by both `seller_id` and `store_id`. |
| `getProduct(productId)` | Single product with all relations. |
| `getSellerStoreId()` | Fetches `stores.id` where `owner_id = currentUser.id AND is_active = true`. Returns `null` if no store exists. Used by ALL seller product operations. |
| `toggleActive(productId, isActive)` | Quick active/inactive toggle. |
| `toggleFeatured(productId, isFeatured)` | Quick featured toggle. |
| `syncProductActiveStatus(productId)` | Auto-deactivates product when ALL stock = 0 (checks both inventory and variant stock). |
| `removeImage(imageId, imageUrl)` | Delete a single image from DB + Storage. |

### `SupabaseService` (`lib/services/supabase_service.dart`)
Contains legacy product methods used by `ProductProvider`:

| Method | Purpose |
|--------|---------|
| `fetchProducts({storeId})` | Fetch products optionally scoped to a store. Used by `ProductProvider.loadProducts()` (no storeId = all products, customer view) and `loadSellerProducts()` (storeId = seller's store). Returns mapped products with `images`, `sizes`, `store_name`. |
| `addProduct(productData)` | Legacy — inserts product + inventory + images. |
| `updateProduct(id, productData)` | Legacy — updates product fields + inventory + images. |
| `deleteProduct(id)` | Legacy — soft-deletes by setting `is_published = false`. |

---

## 3. Provider Layer

### `ProductProvider` (`lib/providers/product_provider.dart`)
State management for the cached product list. Used by screens that need reactive product data.

| Property/Method | Purpose |
|-----------------|---------|
| `products` | List of all loaded products. |
| `isLoading` | Loading state flag. |
| `selectedCategory` | Current category filter. |
| `categories` | Derived list of unique categories across products. |
| `loadProducts()` | Load ALL products (customer/admin). No store scoping. |
| `loadSellerProducts()` | Load only current seller's products. Uses `getSellerStoreId()` + `fetchProducts(storeId:)`. Returns empty list if seller has no store (scoping safety). |
| `getFilteredProducts(keyword)` | Filter by selectedCategory + search keyword. |
| `selectCategory(category)` | Update category filter and notify. |
| `addProduct(data)` | Legacy wrapper — calls `SupabaseService.addProduct()`. |
| `updateProduct(id, data)` | Legacy wrapper — calls `SupabaseService.updateProduct()`. |
| `deleteProduct(id)` | Legacy wrapper — calls `SupabaseService.deleteProduct()`. |

---

## 4. Model Layer

### `ProductVariant` (`lib/models/product_models.dart`)
```dart
class ProductVariant {
  final String? id;
  final String size;
  final String? color;
  final int stock;
  final double additionalPrice;
  final String? sku;
  // Factory: fromMap()  |  Method: toInsertMap(productId)
}
```

### `ProductCustomization` (`lib/models/product_models.dart`)
```dart
class ProductCustomization {
  final String? id;
  final String optionName;
  final String optionType;  // 'text' | 'select' | 'color'
  final List<String> options;
  final bool isRequired;
  final double additionalPrice;
  // Factory: fromMap()  |  Method: toInsertMap(productId)
}
```

---

## 5. Screen Layer

### Screen Overview

| Screen | Purpose | Data Source |
|--------|---------|-------------|
| `ManageProductsScreen` | Grid of seller's products with filter/search. Tap to edit, long-press for actions. FAB to add. | `ProductService.getSellerProducts()` |
| `AddEditProductScreen` | Full product form: images, basic info, barcode, tags, variants, customizations, visibility toggles. | `ProductService.createProduct()` / `updateProduct()` |
| `ManageInventoryScreen` | Stock management list. Filter by in-stock/low/out. Per-size stock editing with slider. | `ProductProvider.products` (via `loadSellerProducts()`) |
| `POSScreen` | Point-of-sale product grid with masonry layout. Search, barcode scanning, size/qty sheet, cart. | `ProductProvider.loadSellerProducts()` |
| `StoreProfileScreen` | Public store view with product listing. | `ProductService.getSellerProducts()` |

### POS Product Screen (key details)

The POS screen (`lib/screens/seller/pos_screen.dart`) has its own specialized flow:

```
┌─────────────────────────────────────┐
│  Header: "POS" + history icon       │
├─────────────────────────────────────┤
│  Search bar [Search...] [QR icon]   │  ← QR icon opens barcode scanner
│  Recent scans: [Product] [Product]  │  ← scan history chips (max 10)
├─────────────────────────────────────┤
│  Category chips: All / Sandals / …  │
├─────────────────────────────────────┤
│  ┌────────┐  ┌────────┐            │
│  │ Image  │  │ Image  │            │  2-column masonry grid
│  │ Name   │  │ Name   │           │  (content-sized heights)
│  │ Price  │  │ Price  │            │
│  │ Stock  │  │ Stock  │            │
│  └────────┘  └────────┘            │
│  ┌────────┐  ┌────────┐            │
│  │ Image  │  │ Image  │            │
│  │ Name   │  │ Name   │            │
│  └────────┘  └────────┘            │
├─────────────────────────────────────┤
│  3 items · ₱2,400     [Checkout]   │  ← sticky cart bar
└─────────────────────────────────────┘
│ Home │ POS │ Products │ Orders │ Profile │
└──────────────────────────────────────────┘
```

**Product flow in POS:**
1. Tap product card → Size/Qty bottom sheet opens
2. Select size, adjust quantity → "Add to Order ₱XXX"
3. Product added to in-memory order items
4. Cart bar updates with count + total
5. Tap Checkout → Payment screen → Order created

**Barcode scanning flow:** (see `lib/screens/seller/pos_barcode_scanner.dart`)
1. Tap QR icon → full-screen camera scanner
2. Scanner detects barcode → match against in-memory `_products` list
   - Search priority: product-level `barcode` → product-level `sku` → variant-level `sku`
3. On match: `HapticFeedback.lightImpact()` + `SystemSound.play(click)` → open Size/Qty sheet
4. On no match: SnackBar "No product found for barcode: {code}"
5. On out-of-stock match: SnackBar "{name} is out of stock"
6. Camera permission denied: dedicated error view with settings link
7. Successful scans recorded in `_scanHistory` (max 10, deduped by barcode)

---

## 6. Key Data Flows

### Create Product
```
AddEditProductScreen
  → ProductService.createProduct()
    → Insert products row
    → Upload images to Storage (bucket: 'product-images')
    → Insert product_images rows
    → Insert product_variants rows
    → _syncInventoryFromVariants()  ← groups by size, sums stock
        → Delete old inventory rows
        → Insert aggregated inventory rows
        → Fire low_stock notifications if stock ≤ 5
    → Insert product_customizations rows
  → Pop with result=true → ManageProductsScreen reloads
```

### Edit Product
```
AddEditProductScreen (pre-filled from product map)
  → ProductService.updateProduct()
    → Update products row
    → Upload new images + insert product_images
    → Delete + re-insert product_variants
    → _syncInventoryFromVariants() (same as create)
    → Delete + re-insert product_customizations
  → syncProductActiveStatus() as fire-and-forget
  → Pop with result=true
```

### Delete Product (cascade-safe)
```
ManageProductsScreen (long-press → confirm dialog)
  → ProductService.deleteProduct(productId)
    → UPDATE order_items SET product_id = null WHERE product_id = ?
    → UPDATE sales_transaction_items SET product_id = null ...
    → UPDATE customization_requests SET base_product_id = null ...
    → DELETE FROM inventory WHERE product_id = ?
    → DELETE FROM product_variants WHERE product_id = ?
    → DELETE FROM product_images WHERE product_id = ?
      → Also remove from Storage
    → DELETE FROM product_customizations WHERE product_id = ?
    → DELETE FROM products WHERE id = ?
  → Remove from local list, show success SnackBar
```

### List Products (seller-scoped)
```
ManageProductsScreen.initState()
  → ProductService.getSellerProducts()
    → getSellerStoreId()  ← stores WHERE owner_id = currentUser.id
    → supabase.from('products').select('*, product_images(*), ...')
        .eq('seller_id', ...)
        .eq('store_id', ...)
        .order('created_at', descending)
  → Render in MasonryGridView (2 columns, content-sized cards)
```

### POS Product Grid (provider-cached)
```
POSScreen.initState()
  → ProductProvider.loadSellerProducts()
    → ProductService.instance.getSellerStoreId()
    → SupabaseService.fetchProducts(storeId: ...)
      → supabase.from('products').select('*, stores(name), product_images(...), inventory(...), product_variants(...)')
          .eq('store_id', ...)
    → Store in _products (in-memory list)
  → Filter/search/barcode scan against in-memory list
  → Category filter → getFilteredProducts(category, keyword)
```

---

## 7. Image Storage

- **Bucket:** `product-images` (public read)
- **Path pattern:** `{sellerId}/{productId}/{timestamp}_{index}.{ext}`
- **Images table:** `product_images` links to products, has `display_order` and `is_primary`
- **Upload flow:** `XFile` picked via `image_picker` → read bytes → `uploadBinary()` to Storage → `getPublicUrl()` → insert URL into `product_images` table

---

## 8. Seller Scoping (Security)

All seller-side product operations enforce scoping in two layers:

1. **Application layer:** Every query uses `getSellerStoreId()` to find the seller's store, then scopes by `store_id`. `ProductProvider.loadSellerProducts()` returns empty list if no store exists — preventing data leaks for sellers without a store.

2. **Database RLS:** Row-Level Security policies on all product-related tables verify `seller_id = auth.uid()` or admin role. The `products` table checks seller role for insert/update/delete.

---

## 9. File Map

| File | Role |
|------|------|
| `lib/services/product_service.dart` | Primary product CRUD service (singleton) |
| `lib/services/supabase_service.dart` | Legacy product methods + fetchProducts with store scoping |
| `lib/providers/product_provider.dart` | State management for cached product list |
| `lib/models/product_models.dart` | ProductVariant + ProductCustomization models |
| `lib/screens/seller/add_edit_product_screen.dart` | Full product create/edit form |
| `lib/screens/seller/manage_products_screen.dart` | Product list grid with filters + actions |
| `lib/screens/seller/manage_inventory_screen.dart` | Stock management by size |
| `lib/screens/seller/pos_screen.dart` | POS product grid + search + cart |
| `lib/screens/seller/pos_barcode_scanner.dart` | Barcode/QR scanner widget |
| `supabase/schema.sql` | Full database schema documentation |
| `supabase/migrations/20260727000000_add_barcode_to_products.sql` | Migration adding `barcode` column |
