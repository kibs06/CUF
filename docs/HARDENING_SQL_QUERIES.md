# Phase 1: Production Hardening — SQL Verification Queries

Run these queries against your **live Supabase database** via the SQL Editor in the Supabase Dashboard.

---

## 1. Migration Verification

Check which migration files have been applied by looking for the tables/triggers they create:

```sql
-- Check for all expected tables
SELECT table_name 
FROM information_schema.tables 
WHERE table_schema = 'public' 
ORDER BY table_name;

-- Expected tables: cart_items, conversations, customer_addresses, 
-- device_tokens, inventory, messages, notifications, order_items, 
-- order_status_history, orders, product_customizations, product_images, 
-- product_reviews, product_variants, products, profiles, reviews, 
-- review_images, sales_transaction_items, sales_transactions, 
-- seller_notifications, stores, story_entries, store_follows

-- Check for messaging tables (migration 20260713)
SELECT EXISTS (
  SELECT 1 FROM information_schema.tables 
  WHERE table_name = 'conversations'
) AS has_conversations,
EXISTS (
  SELECT 1 FROM information_schema.tables 
  WHERE table_name = 'messages'
) AS has_messages;

-- Check for device_tokens (migration 20260714)
SELECT EXISTS (
  SELECT 1 FROM information_schema.tables 
  WHERE table_name = 'device_tokens'
) AS has_device_tokens;

-- Check for order_status_history (migration 20260720)
SELECT EXISTS (
  SELECT 1 FROM information_schema.tables 
  WHERE table_name = 'order_status_history'
) AS has_order_status_history;

-- Check for customer_addresses (migration 20260705)
SELECT EXISTS (
  SELECT 1 FROM information_schema.tables 
  WHERE table_name = 'customer_addresses'
) AS has_customer_addresses;

-- Check for reviews table (migration 20260718)
SELECT EXISTS (
  SELECT 1 FROM information_schema.tables 
  WHERE table_name = 'reviews'
) AS has_reviews;

-- Check for seller_notifications (migration 20260715)
SELECT EXISTS (
  SELECT 1 FROM information_schema.tables 
  WHERE table_name = 'seller_notifications'
) AS has_seller_notifications;

-- Check inventory trigger functions have SECURITY DEFINER (migration 20260711)
SELECT proname, proconfig
FROM pg_proc
WHERE proname IN ('decrement_inventory_on_order', 'decrement_inventory_on_sale');

-- Check orders status check constraint (migration 20260722)
SELECT conname, pg_get_constraintdef(oid)
FROM pg_constraint
WHERE conrelid = 'orders'::regclass AND conname = 'orders_status_check';
```

---

## 2. Non-Numeric Size Verification

Check the `product_variants` table for size values that aren't valid numeric shoe sizes:

```sql
-- Find all product_variants with non-numeric sizes
SELECT pv.id, pv.product_id, p.name AS product_name, pv.size, pv.color, pv.stock
FROM product_variants pv
JOIN products p ON p.id = pv.product_id
WHERE pv.size !~ '^[0-9]+(\.[0-9]+)?$'
ORDER BY pv.product_id, pv.size;

-- Find sizes that are empty or null
SELECT pv.id, pv.product_id, p.name AS product_name, pv.size, pv.stock
FROM product_variants pv
JOIN products p ON p.id = pv.product_id
WHERE pv.size IS NULL OR trim(pv.size) = ''
ORDER BY pv.product_id;

-- Find sizes with text prefix (e.g. "EU42", "US10")
SELECT pv.id, pv.product_id, p.name AS product_name, pv.size, pv.stock
FROM product_variants pv
JOIN products p ON p.id = pv.product_id
WHERE pv.size ~ '^[A-Za-z]'
ORDER BY pv.product_id, pv.size;

-- Summary: Count of valid vs invalid sizes
SELECT 
  COUNT(*) AS total_variants,
  COUNT(*) FILTER (WHERE size ~ '^[0-9]+(\.[0-9]+)?$') AS numeric_sizes,
  COUNT(*) FILTER (WHERE size !~ '^[0-9]+(\.[0-9]+)?$') AS non_numeric_sizes
FROM product_variants;
```

---

## 3. Duplicate product_variants Detection

```sql
-- Find duplicate product_variants (same product_id + size + color)
SELECT 
  product_id, 
  size, 
  color,
  COUNT(*) AS duplicate_count,
  ARRAY_AGG(id ORDER BY id) AS variant_ids,
  SUM(stock) AS total_stock
FROM product_variants
GROUP BY product_id, size, color
HAVING COUNT(*) > 1
ORDER BY duplicate_count DESC;

-- Detailed view of duplicates (showing all columns for inspection)
SELECT pv1.*
FROM product_variants pv1
INNER JOIN (
  SELECT product_id, size, color
  FROM product_variants
  GROUP BY product_id, size, color
  HAVING COUNT(*) > 1
) dup ON pv1.product_id = dup.product_id 
     AND pv1.size = dup.size 
     AND pv1.color = dup.color
ORDER BY pv1.product_id, pv1.size, pv1.color, pv1.id;
```

---

## 4. Orphaned Inventory Rows Detection

```sql
-- Find inventory rows that reference non-existent products
SELECT i.product_id, i.size, i.stock, i.updated_at
FROM inventory i
LEFT JOIN products p ON p.id = i.product_id
WHERE p.id IS NULL
ORDER BY i.product_id;

-- Find inventory rows where the product_id format doesn't match
-- (e.g. UUID stored differently)
SELECT i.product_id, i.size, i.stock
FROM inventory i
WHERE i.product_id NOT IN (SELECT id FROM products)
ORDER BY i.product_id;

-- Summary
SELECT 
  (SELECT COUNT(*) FROM inventory) AS total_inventory_rows,
  (SELECT COUNT(*) FROM inventory i LEFT JOIN products p ON p.id = i.product_id WHERE p.id IS NULL) AS orphaned_rows;
```

---

## 5. Orphaned Orders Detection (orders with 0 items)

```sql
-- Find orders with no order_items
SELECT o.id, o.status, o.total_amount, o.created_at, o.customer_id,
       (SELECT COUNT(*) FROM order_items oi WHERE oi.order_id = o.id) AS item_count
FROM orders o
WHERE NOT EXISTS (SELECT 1 FROM order_items oi WHERE oi.order_id = o.id)
ORDER BY o.created_at DESC;

-- Count of orphaned orders
SELECT COUNT(*) AS orphaned_order_count
FROM orders o
WHERE NOT EXISTS (SELECT 1 FROM order_items oi WHERE oi.order_id = o.id);
```

---

## ⚠️ Destructive Operations — DO NOT RUN WITHOUT REVIEW

After reviewing the results above, if you find duplicates or orphans that need cleanup, use these **safe** queries:

### De-duplicate product_variants (keep lowest ID, merge stock)

```sql
-- Step 1: Preview what will be affected
-- Run this first and verify the results!
WITH duplicates AS (
  SELECT product_id, size, color, 
         ARRAY_AGG(id ORDER BY id) AS ids,
         SUM(stock) AS total_stock
  FROM product_variants
  GROUP BY product_id, size, color
  HAVING COUNT(*) > 1
),
keeper AS (
  SELECT ids[1] AS keep_id, ids[2:] AS remove_ids, total_stock
  FROM duplicates
)
SELECT * FROM keeper;

-- Step 2: Merge stock into keeper and delete duplicates (UNCOMMENT TO RUN)
/*
UPDATE product_variants pv
SET stock = k.total_stock
FROM (
  SELECT ids[1] AS keep_id, SUM(stock) AS total_stock
  FROM (
    SELECT ARRAY_AGG(id ORDER BY id) AS ids, product_id, size, color
    FROM product_variants
    GROUP BY product_id, size, color
    HAVING COUNT(*) > 1
  ) dups
  GROUP BY ids[1]
) k
WHERE pv.id = k.keep_id;

DELETE FROM product_variants pv
WHERE pv.id IN (
  SELECT unnest(ids[2:])
  FROM (
    SELECT ARRAY_AGG(id ORDER BY id) AS ids
    FROM product_variants
    GROUP BY product_id, size, color
    HAVING COUNT(*) > 1
  ) dups
);
*/
```

### Delete orphaned inventory rows

```sql
-- Step 1: Preview
SELECT * FROM inventory i
LEFT JOIN products p ON p.id = i.product_id
WHERE p.id IS NULL;

-- Step 2: Delete (UNCOMMENT TO RUN)
/*
DELETE FROM inventory i
WHERE NOT EXISTS (SELECT 1 FROM products p WHERE p.id = i.product_id);
*/
```

### Delete orphaned orders (0 items)

```sql
-- Step 1: Preview
SELECT id, status, total_amount, created_at
FROM orders o
WHERE NOT EXISTS (SELECT 1 FROM order_items oi WHERE oi.order_id = o.id);

-- Step 2: Delete (UNCOMMENT TO RUN)
/*
DELETE FROM orders o
WHERE NOT EXISTS (SELECT 1 FROM order_items oi WHERE oi.order_id = o.id);
*/
```

---

**Remember:** Always backup your data before running destructive operations. Run the preview queries first and confirm the results look correct before uncommenting the DELETE statements.
