# SoleVision — Product Delete & Auto-Deactivation Changelog

**Date:** June 28, 2026  
**Status:** Complete (pending RLS migration)

---

## Overview

This session implemented two major features for the seller's product management flow:

1. **Hard Delete** — sellers can permanently delete products with a confirmation dialog
2. **Auto-Deactivation/Activation** — products automatically toggle `is_active` based on stock levels

We also debugged and fixed a critical silent-delete bug caused by missing RLS policies.

---

## Features Implemented

### Feature 1: Hard Delete a Product

Sellers can permanently delete a product via the long-press action menu on the products screen.

**Flow:**
1. Seller long-presses a product card → action sheet appears
2. Taps "Delete" → confirmation dialog with warning about order history
3. Confirms → product is deleted from DB, removed from local list immediately
4. Success/error SnackBar is shown

**Files Modified:**
- `lib/services/product_service.dart` — `deleteProduct()` method
- `lib/screens/seller/manage_products_screen.dart` — delete dialog, loading overlay, local list removal

### Feature 2: Auto-Deactivation & Auto-Activation

A product's `is_active` flag is automatically managed based on stock levels:

| Condition | Action |
|-----------|--------|
| ALL stock across `inventory` AND `product_variants` = 0 | Set `is_active = false` |
| ANY stock row > 0 | Set `is_active = true` |
| No inventory or variant rows at all | Set `is_active = false` |

**Call Sites:**
- `ManageInventoryScreen` — after inventory stock changes
- `POSScreen` — after each POS transaction item
- `SellerOrdersScreen` — when order status changes to "received"
- `SellerDashboardScreen` — when order status changes to "received"
- `AddEditProductScreen` — after saving a product (create or update)

**Files Modified:**
- `lib/services/product_service.dart` — new `syncProductActiveStatus()` method
- `lib/screens/seller/manage_inventory_screen.dart` — added sync call
- `lib/screens/seller/pos_screen.dart` — added sync call
- `lib/screens/seller/seller_orders_screen.dart` — added sync call
- `lib/screens/seller/seller_dashboard_screen.dart` — added sync call
- `lib/screens/seller/add_edit_product_screen.dart` — added sync call

### UI Changes: Active/Inactive Badge

Product cards now show an active status badge:
- **Active** → teal badge labeled "Active" (`Color(0xFF4ECDC4)`)
- **Inactive** → red badge labeled "Out of Stock"
- Inactive product cards are visually dimmed (50% opacity on image and title)

---

## Bug Fix: Silent Delete Failure

### Problem

Product deletion appeared to succeed (no error shown, product removed from local list) but the product was never actually deleted from the database. It reappeared on refresh.

### Root Causes (Two Layered Issues)

#### 1. Missing RLS DELETE Policy (Primary Cause)

The `products` table had RLS enabled but **no DELETE policy**. In Supabase, when RLS is enabled and no policy exists for an operation, that operation is silently blocked — no error is thrown.

**Fix:** Run these SQL statements in Supabase SQL Editor:

```sql
-- Allow sellers to delete their own products
CREATE POLICY "Seller deletes own products"
ON products
FOR DELETE
TO public
USING (auth.uid() = seller_id);

-- Allow admins to delete any product
CREATE POLICY "Admin deletes any product"
ON products
FOR DELETE
TO public
USING (current_user_role() = 'admin'::text);
```

#### 2. Missing FK Nullification (Secondary Cause)

Three tables had `NO ACTION` FK constraints on `products.id`, which would block the delete even with proper RLS:

| Table | Column | Fix |
|-------|--------|-----|
| `order_items` | `product_id` | Nullify before delete |
| `sales_transaction_items` | `product_id` | Nullify before delete |
| `customization_requests` | `base_product_id` | Nullify before delete |

**Fix:** Added explicit nullification of these references in `deleteProduct()` before the product row is deleted.

#### 3. Missing `await` on Storage Cleanup

`_removeStorageFile(url)` was called without `await`, making storage cleanup fire-and-forget.

**Fix:** Added `await` to each storage deletion call.

---

## Files Changed Summary

| File | Changes |
|------|---------|
| `lib/services/product_service.dart` | Rewrote `deleteProduct()` with FK-safe deletion order + try/catch; added `syncProductActiveStatus()` method; added `await` to storage cleanup |
| `lib/screens/seller/manage_products_screen.dart` | Updated delete dialog with order history warning; added Active/Inactive badge; added opacity dimming; added loading overlay during delete; removed full-reload after delete |
| `lib/screens/seller/manage_inventory_screen.dart` | Added `syncProductActiveStatus` call after stock changes |
| `lib/screens/seller/pos_screen.dart` | Added `syncProductActiveStatus` call after POS transactions |
| `lib/screens/seller/seller_orders_screen.dart` | Added `syncProductActiveStatus` call on order fulfillment |
| `lib/screens/seller/seller_dashboard_screen.dart` | Added `syncProductActiveStatus` call on order fulfillment |
| `lib/screens/seller/add_edit_product_screen.dart` | Added `syncProductActiveStatus` call after product save |

---

## Database Schema Reference

### `deleteProduct()` Deletion Order

1. **Nullify** references in tables with `NO ACTION` FK constraints:
   - `order_items.product_id → null`
   - `sales_transaction_items.product_id → null`
   - `customization_requests.base_product_id → null`
2. **Delete** from CASCADE tables:
   - `inventory`
   - `product_variants`
   - `product_images` (+ storage file cleanup)
   - `product_customizations`
3. **Delete** the product row from `products`

### `syncProductActiveStatus()` Logic

```
hasInventoryStock = ANY(inventory.stock > 0)
hasVariantStock = ANY(product_variants.stock > 0)
shouldBeActive = hasInventoryStock OR hasVariantStock

UPDATE products SET is_active = shouldBeActive WHERE id = productId
```

---

## Pending Actions

- [ ] Run the RLS migration SQL in Supabase SQL Editor
- [ ] Test seller can delete their own product
- [ ] Test product does not reappear after refresh
- [ ] (Optional) Apply FK constraint migration to `ON DELETE SET NULL`

### Optional FK Migration SQL

```sql
ALTER TABLE order_items
  DROP CONSTRAINT IF EXISTS order_items_product_id_fkey,
  ADD CONSTRAINT order_items_product_id_fkey
    FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE SET NULL;

ALTER TABLE sales_transaction_items
  DROP CONSTRAINT IF EXISTS sales_transaction_items_product_id_fkey,
  ADD CONSTRAINT sales_transaction_items_product_id_fkey
    FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE SET NULL;

ALTER TABLE customization_requests
  DROP CONSTRAINT IF EXISTS customization_requests_base_product_id_fkey,
  ADD CONSTRAINT customization_requests_base_product_id_fkey
    FOREIGN KEY (base_product_id) REFERENCES products(id) ON DELETE SET NULL;
```

If applied, the manual nullification in Flutter code becomes redundant but harmless.
