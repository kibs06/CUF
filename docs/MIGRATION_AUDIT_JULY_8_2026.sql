-- ══════════════════════════════════════════════════════════════════
-- MIGRATION AUDIT — July 8, 2026
-- Purpose: Verify which migrations from supabase/migrations/ have
--   been applied to the live Supabase database.
-- Run this in Supabase SQL Editor and review each section.
-- ══════════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════════
-- MIGRATION 1: 20260702_notifications.sql
-- Creates: notifications table, RLS, indexes, trigger functions, triggers
-- ═══════════════════════════════════════════════════════════════════

-- 1a. Does notifications table exist?
SELECT '1a: notifications table' AS check,
  EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name = 'notifications') AS applied;

-- 1b. Does notification_category enum exist?
SELECT '1b: notification_category enum' AS check,
  EXISTS(SELECT 1 FROM pg_type WHERE typname = 'notification_category') AS applied;

-- 1c. How many indexes on notifications?
SELECT '1c: notifications indexes' AS check,
  COUNT(*) AS count,
  COUNT(*) >= 3 AS applied
FROM pg_indexes
WHERE tablename = 'notifications';

-- 1d. RLS policies on notifications
SELECT '1d: notifications RLS policies' AS check,
  policyname, cmd
FROM pg_policies
WHERE tablename = 'notifications'
ORDER BY cmd;

-- 1e. Trigger functions exist?
SELECT '1e: notify trigger functions' AS check,
  proname,
  proconfig
FROM pg_proc
WHERE proname IN ('notify_on_order_status_change', 'notify_on_order_insert')
ORDER BY proname;

-- 1f. Triggers attached to orders table?
SELECT '1f: notify triggers on orders' AS check,
  tgname,
  tgenabled
FROM pg_trigger
WHERE tgname IN ('trg_notify_on_order_status_change', 'trg_notify_on_insert')
   OR (tgname LIKE 'trg_notify%' AND NOT tgisinternal)
ORDER BY tgname;


-- ═══════════════════════════════════════════════════════════════════
-- MIGRATION 2: 20260703_add_cart_items_size.sql
-- Creates: size column on cart_items
-- ═══════════════════════════════════════════════════════════════════

-- 2a. Does cart_items have a size column?
SELECT '2a: cart_items.size column' AS check,
  EXISTS(
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'cart_items' AND column_name = 'size'
  ) AS applied;

-- 2b. How many cart_items have size populated?
SELECT '2b: cart_items size backfill' AS check,
  COUNT(*) AS total_rows,
  COUNT(size) AS rows_with_size,
  COUNT(*) - COUNT(size) AS rows_without_size
FROM cart_items;


-- ═══════════════════════════════════════════════════════════════════
-- MIGRATION 3: 20260704_add_orders_delete_policy.sql
-- Creates: DELETE policy on orders (pending only)
-- ═══════════════════════════════════════════════════════════════════

-- 3a. DELETE policy on orders?
SELECT '3a: orders DELETE policy' AS check,
  policyname,
  cmd,
  qual
FROM pg_policies
WHERE tablename = 'orders' AND cmd = 'DELETE';


-- ═══════════════════════════════════════════════════════════════════
-- MIGRATION 4: 20260704_fix_trigger_security_definer.sql
-- Creates/Replaces: decrement_inventory_on_order() and
--   decrement_inventory_on_sale() with SECURITY DEFINER
-- ═══════════════════════════════════════════════════════════════════

-- 4a. Functions exist and have SECURITY DEFINER?
SELECT '4a: inventory trigger SECURITY DEFINER' AS check,
  proname,
  proconfig
FROM pg_proc
WHERE proname IN ('decrement_inventory_on_order', 'decrement_inventory_on_sale')
ORDER BY proname;

-- 4b. If proconfig is NULL or doesn't contain 'security_definer', the fix is NOT applied


-- ═══════════════════════════════════════════════════════════════════
-- MIGRATION 5: 20260705_add_customer_addresses.sql
-- Creates: customer_addresses table, shipping_address column on orders,
--   RLS policies, trigger function, trigger
-- ═══════════════════════════════════════════════════════════════════

-- 5a. Does customer_addresses table exist?
SELECT '5a: customer_addresses table' AS check,
  EXISTS(
    SELECT 1 FROM information_schema.tables
    WHERE table_name = 'customer_addresses'
  ) AS applied;

-- 5b. Does orders have shipping_address column?
SELECT '5b: orders.shipping_address column' AS check,
  EXISTS(
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'orders' AND column_name = 'shipping_address'
  ) AS applied;

-- 5c. RLS policies on customer_addresses
SELECT '5c: customer_addresses RLS policies' AS check,
  policyname,
  cmd,
  qual,
  with_check
FROM pg_policies
WHERE tablename = 'customer_addresses'
ORDER BY cmd;

-- 5d. enforce_single_default_address trigger function?
SELECT '5d: enforce_single_default_address function' AS check,
  proname,
  proconfig
FROM pg_proc
WHERE proname = 'enforce_single_default_address';

-- 5e. Trigger attached to customer_addresses?
SELECT '5e: trg_enforce_single_default trigger' AS check,
  tgname,
  tgenabled
FROM pg_trigger
WHERE tgname = 'trg_enforce_single_default';


-- ═══════════════════════════════════════════════════════════════════
-- MIGRATION 6: 20260708_fix_customer_addresses_rls.sql
-- Creates/Replaces: 4 RLS policies on customer_addresses (idempotent)
-- NOTE: Same as Migration 5's policies. If 5c shows all 4 policies,
--   this migration is also effectively applied.
-- ═══════════════════════════════════════════════════════════════════

-- 6a. All 4 CRUD policies exist on customer_addresses?
SELECT '6a: customer_addresses all 4 CRUD policies' AS check,
  cmd,
  COUNT(*) AS policy_count
FROM pg_policies
WHERE tablename = 'customer_addresses'
GROUP BY cmd
ORDER BY cmd;

-- Expected: 4 rows (DELETE=1, INSERT=1, SELECT=1, UPDATE=1)


-- ═══════════════════════════════════════════════════════════════════
-- SUMMARY: All policies across all tables
-- ═══════════════════════════════════════════════════════════════════

SELECT
  tablename,
  policyname,
  cmd,
  CASE WHEN qual IS NOT NULL THEN 'USING' ELSE '-' END AS using_clause,
  CASE WHEN with_check IS NOT NULL THEN 'WITH CHECK' ELSE '-' END AS with_check_clause
FROM pg_policies
WHERE schemaname = 'public'
ORDER BY tablename, cmd, policyname;


-- ═══════════════════════════════════════════════════════════════════
-- SUMMARY: All tables in public schema
-- ═══════════════════════════════════════════════════════════════════

SELECT
  table_name,
  (SELECT COUNT(*) FROM information_schema.columns c WHERE c.table_name = t.table_name) AS column_count,
  EXISTS(SELECT 1 FROM pg_tables pt WHERE pt.tablename = t.table_name AND pt.rowsecurity) AS rls_enabled
FROM information_schema.tables t
WHERE table_schema = 'public'
  AND table_type = 'BASE TABLE'
ORDER BY table_name;
