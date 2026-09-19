-- ══════════════════════════════════════════════════════════════════
-- Migration: Hot-query indexes for the seller dashboard / POS / catalog
-- Date: 2026-09-18
-- Depends on: 20260601000000_base_schema.sql (orders, order_items, products,
--             product_images, product_variants, product_customizations),
--             20260709_one_store_per_seller.sql (stores UNIQUE(owner_id)),
--             20260726000000_add_order_source_column.sql (orders.source),
--             20260808200000_add_direct_gcash_online_checkout.sql
--             (status 'awaiting_payment_confirmation')
--
-- Purpose: the seller Dashboard, POS and Products tabs load slowly because
--          every query they make filters or joins on a column that has NO
--          index. In Postgres a FOREIGN KEY constraint does NOT create an
--          index, and none of these were ever added:
--
--            products.store_id            ← every product/catalog query
--            products.seller_id           ← getSellerProducts(), product RLS
--            orders.store_id              ← every POS/revenue query AND the
--                                           "Sellers can view orders for
--                                            their store" RLS policy
--            orders.customer_id           ← "My Orders" + the customer RLS
--                                           policy (auth.uid() = customer_id)
--            orders.created_at            ← every date-windowed revenue query
--            order_items.order_id         ← every line-item join + the
--                                           order_items RLS EXISTS probe
--            order_items.product_id       ← the products→order_items chain
--                                           SalesService/OrderService use to
--                                           resolve a store's order IDs
--            product_images.product_id    ← the fetchProducts() embed
--            product_variants.product_id  ← the fetchProducts() embed
--            product_customizations.product_id
--
--          Without them the planner sequential-scans `orders` (and then
--          probes `stores` per row for the RLS policy), and nested-loops
--          each child table per product. A seller opening Dashboard → POS →
--          Products issues ~40 such queries, so the cost is paid ~40×.
--
-- Indexes added (all `IF NOT EXISTS`, so a partial or repeated apply is
-- harmless):
--   orders
--     • (store_id, created_at DESC)          store dashboards / RLS join
--     • (customer_id, created_at DESC)       customer order history / RLS
--     • (store_id, source, created_at DESC)  POS-only revenue + POS history
--     • (store_id) WHERE status = 'awaiting_payment_confirmation'
--                                            the dashboard's 30s GCash poll
--   order_items
--     • (order_id)                           item joins + RLS probe
--     • (product_id) WHERE product_id IS NOT NULL
--                                            products→order_items chain
--   products
--     • (store_id, created_at DESC)          seller-scoped catalog
--     • (seller_id)                          getSellerProducts() + product RLS
--   product_images
--     • (product_id, display_order)          primary-image / gallery embed
--   product_variants
--     • (product_id)                         stock + size embed
--   product_customizations
--     • (product_id)                         the 4th join in fetchProducts()
--
-- NOT added on purpose:
--   • inventory(product_id) — already covered by the
--     PRIMARY KEY (product_id, size) prefix.
--   • product_color_images(product_id) — already covered by
--     idx_product_color_images_product_color from 20260818000000.
--   • stores(owner_id) — already UNIQUE via 20260709_one_store_per_seller.
--   • products(audience) — nothing filters on it yet; see
--     20260918193313_add_product_audience.sql.
--
-- Locking note: these are plain CREATE INDEX statements (the Supabase CLI
-- runs each migration inside a transaction, where CREATE INDEX
-- CONCURRENTLY is illegal). Each one blocks writes to its table for the
-- duration of the build. That is fine at the current table sizes; if this
-- ever has to be replayed against a large live orders table, run the
-- statements individually with CONCURRENTLY outside a transaction
-- instead.
-- ══════════════════════════════════════════════════════════════════

-- ────────────────────────────────────────────────────────────────
-- 1. orders
-- ────────────────────────────────────────────────────────────────

-- Seller-scoped reads ordered by time, and the shape the
-- "Sellers can view orders for their store" RLS policy lets the planner
-- turn into an index scan:
--   orders JOIN stores ON stores.id = orders.store_id
--   WHERE stores.owner_id = auth.uid()
-- Covered patterns: getOrderCountByStatus(), the dashboard's store loads,
-- fetchPosHistory() (store + source, ordered), getMonthlyRevenue()'s
-- store-scoped POS leg, and the 30-second GCash count.
CREATE INDEX IF NOT EXISTS idx_orders_store_created
  ON public.orders (store_id, created_at DESC);

-- The customer half of the same policy (auth.uid() = customer_id) plus the
-- customer's "My Orders" list, which is always newest-first.
CREATE INDEX IF NOT EXISTS idx_orders_customer_created
  ON public.orders (customer_id, created_at DESC);

-- POS revenue is a sub-slice of a store's orders that SalesService hits
-- repeatedly (fetchTodaySales, fetchWeeklySales, getPosMonthlyRevenueTrend,
-- _fetchTrend's in-store branch, fetchPosHistory). Leading with
-- (store_id, source) lets those queries skip every online order.
CREATE INDEX IF NOT EXISTS idx_orders_store_source_created
  ON public.orders (store_id, source, created_at DESC);

-- The dashboard's _PaymentsToConfirmCard polls this every 30 seconds for
-- the whole session. The rows awaiting confirmation are a handful out of
-- the store's entire order history, so a partial index keeps that poll
-- independent of how large the history grows.
CREATE INDEX IF NOT EXISTS idx_orders_awaiting_payment_confirmation
  ON public.orders (store_id)
  WHERE status = 'awaiting_payment_confirmation';

-- ────────────────────────────────────────────────────────────────
-- 2. order_items
-- ────────────────────────────────────────────────────────────────

-- Every line-item embed (fetchOrders, fetchStoreOrders, getRecentOrders,
-- fetchPosHistory, fetchMyOrders) joins on order_id, and the
-- "Order items follow order access rules" policy probes orders by it for
-- each candidate row.
CREATE INDEX IF NOT EXISTS idx_order_items_order_id
  ON public.order_items (order_id);

-- SalesService._getOrderIds() / OrderService._getOrderIdsForStore() resolve
-- a store's order IDs through `order_items.product_id IN (…store products…)`.
-- This is the single most-repeated query in the seller app — the dashboard
-- runs that chain 7 times per load (every revenue/trend metric recomputes
-- it). Partial, because ON DELETE SET NULL leaves tombstone rows with a
-- NULL product_id that can never match an IN list.
CREATE INDEX IF NOT EXISTS idx_order_items_product_id
  ON public.order_items (product_id)
  WHERE product_id IS NOT NULL;

-- ────────────────────────────────────────────────────────────────
-- 3. products
-- ────────────────────────────────────────────────────────────────

-- Seller-scoped catalog. Exactly the shape of
-- SupabaseService.fetchProducts(storeId:) → .eq('store_id').order('created_at'),
-- and of the products hop in the order-ID chain.
CREATE INDEX IF NOT EXISTS idx_products_store_created
  ON public.products (store_id, created_at DESC);

-- ProductService.getSellerProducts() filters seller_id AND store_id; the
-- product_images / product_variants / product_customizations policies also
-- resolve ownership with
--   EXISTS (SELECT 1 FROM products WHERE id = product_id AND seller_id = auth.uid())
CREATE INDEX IF NOT EXISTS idx_products_seller_id
  ON public.products (seller_id);

-- ────────────────────────────────────────────────────────────────
-- 4. product_images
-- ────────────────────────────────────────────────────────────────

-- fetchProducts / fetchProductById / getSellerProducts embed
-- product_images(image_url, display_order) and _mapProduct sorts by
-- display_order. Composite so the embed is served straight from the index.
CREATE INDEX IF NOT EXISTS idx_product_images_product_display
  ON public.product_images (product_id, display_order);

-- ────────────────────────────────────────────────────────────────
-- 5. product_variants
-- ────────────────────────────────────────────────────────────────

-- The 3rd join in fetchProducts()/getSellerProducts() (and the fallback
-- stock source in the seller's product grid).
CREATE INDEX IF NOT EXISTS idx_product_variants_product_id
  ON public.product_variants (product_id);

-- ────────────────────────────────────────────────────────────────
-- 6. product_customizations
-- ────────────────────────────────────────────────────────────────

-- The 4th join in fetchProducts()/getSellerProducts(). Listed here because
-- leaving one of that query's four joins unindexed would keep the whole
-- embed on a nested loop, undoing the three above.
CREATE INDEX IF NOT EXISTS idx_product_customizations_product_id
  ON public.product_customizations (product_id);

-- ────────────────────────────────────────────────────────────────
-- 7. Refresh planner statistics for the affected tables so the new indexes
--    are actually chosen without waiting for autovacuum.
-- ────────────────────────────────────────────────────────────────
ANALYZE public.orders;
ANALYZE public.order_items;
ANALYZE public.products;
ANALYZE public.product_images;
ANALYZE public.product_variants;
ANALYZE public.product_customizations;

-- ────────────────────────────────────────────────────────────────
-- VERIFICATION QUERIES (run after applying)
-- ────────────────────────────────────────────────────────────────
-- -- All expected indexes are present (expect 11 rows):
-- SELECT tablename, indexname FROM pg_indexes
--  WHERE schemaname = 'public'
--    AND indexname IN (
--      'idx_orders_store_created','idx_orders_customer_created',
--      'idx_orders_store_source_created',
--      'idx_orders_awaiting_payment_confirmation',
--      'idx_order_items_order_id','idx_order_items_product_id',
--      'idx_products_store_created','idx_products_seller_id',
--      'idx_product_images_product_display','idx_product_variants_product_id',
--      'idx_product_customizations_product_id')
--  ORDER BY tablename, indexname;
--
-- -- The orders RLS join now uses an index scan, not a seq scan
-- -- (look for "Index Scan using idx_orders_store_created"):
-- EXPLAIN (ANALYZE, BUFFERS)
-- SELECT * FROM public.orders
--  WHERE store_id = (SELECT id FROM public.stores LIMIT 1);
--
-- -- The order-ID chain is index-backed on both hops:
-- EXPLAIN (ANALYZE, BUFFERS)
-- SELECT order_id FROM public.order_items
--  WHERE product_id IN (SELECT id FROM public.products WHERE store_id IS NOT NULL);
