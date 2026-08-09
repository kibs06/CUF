-- ══════════════════════════════════════════════════════════════════
-- Migration: Fix 42P17 — infinite recursion in RLS policy for "profiles"
-- Date: 2026-08-09
--
-- SYMPTOM: every authenticated query that touches public.profiles fails
-- with  {"code":"42P17","message":"infinite recursion detected in policy
--          for relation \"profiles\""}
-- (seen in the app as a raw PostgrestException on the auth-gate /
-- profile-load screen).
--
-- ROOT CAUSE: policies defined ON public.profiles whose USING clause
-- contains a subquery against public.profiles itself, e.g.
--
--     CREATE POLICY "Admins can read all profiles"
--       ON public.profiles FOR SELECT
--       USING (EXISTS (SELECT 1 FROM public.profiles
--                       WHERE id = auth.uid() AND role = 'admin'));
--
-- When RLS evaluates such a policy for a row, the inner SELECT re-enters
-- RLS on the same table → the policy is evaluated again → infinite
-- recursion → 42P17. Any query that reads profiles (directly OR as a
-- subquery from another table's policy) triggers it, because Postgres
-- applies RLS recursively to every table reference in a policy.
--
-- FIX: move the "am I an admin?" check into a SECURITY DEFINER function.
-- SECURITY DEFINER functions run as their owner (postgres, the migration
-- owner), which BYPASSES RLS — so the function can query profiles without
-- re-entering the policy machinery. Policies then call public.is_admin()
-- instead of inlining a self-referential profiles subquery.
--
-- ══════════════════════════════════════════════════════════════════

-- ────────────────────────────────────────────────────────────────
-- 1. Recursion-free role helpers (SECURITY DEFINER)
--    SECURITY DEFINER functions run as their owner (postgres — the
--    migration role), which bypasses RLS → querying profiles inside
--    them never re-enters the policy machinery → no recursion.
--    STABLE: result is constant within a statement, so Postgres can
--    evaluate each once per query.
-- ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND role = 'admin'
  );
$$;

REVOKE EXECUTE ON FUNCTION public.is_admin() FROM PUBLIC;
-- Policies calling these helpers are evaluated for BOTH roles (e.g. the
-- public product-browsing policies run as anon). A SECURITY DEFINER
-- function still needs EXECUTE from the CALLING role, so anon must be
-- granted too — otherwise every anon query on a table with an admin
-- policy fails with "permission denied for function".
GRANT  EXECUTE ON FUNCTION public.is_admin() TO anon, authenticated;

COMMENT ON FUNCTION public.is_admin() IS
  'True when the current user has role=admin. SECURITY DEFINER (runs as owner, bypasses RLS) so policies can call it without re-entering profiles RLS (fixes 42P17 infinite recursion).';

CREATE OR REPLACE FUNCTION public.is_seller_or_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND role IN ('seller', 'admin')
  );
$$;

REVOKE EXECUTE ON FUNCTION public.is_seller_or_admin() FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.is_seller_or_admin() TO anon, authenticated;

COMMENT ON FUNCTION public.is_seller_or_admin() IS
  'True when the current user has role seller or admin. SECURITY DEFINER so policies can call it without re-entering profiles RLS (fixes 42P17 infinite recursion).';

-- ────────────────────────────────────────────────────────────────
-- 2. Rebuild the recursive policies on public.profiles
--    The three historical names that caused the recursion (from
--    schema.sql era and admin-portal/supabase/admin_policies.sql).
--    Each is only rebuilt IF it already exists in the live DB — the
--    same never-adds-privileges principle as §3. This also makes the
--    migration safe to re-run (each CREATE is preceded by its DROP).
--    Existing non-recursive profiles policies (own-row insert/update,
--    "conversation partners" SELECT) are untouched.
-- ────────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_policy p JOIN pg_class c ON c.oid = p.polrelid
             WHERE c.relname = 'profiles' AND p.polname = 'Admins can read all profiles') THEN
    DROP POLICY "Admins can read all profiles" ON public.profiles;
    CREATE POLICY "Admins can read all profiles" ON public.profiles FOR SELECT USING (public.is_admin());
  END IF;
  IF EXISTS (SELECT 1 FROM pg_policy p JOIN pg_class c ON c.oid = p.polrelid
             WHERE c.relname = 'profiles' AND p.polname = 'Admins can update all profiles') THEN
    DROP POLICY "Admins can update all profiles" ON public.profiles;
    CREATE POLICY "Admins can update all profiles" ON public.profiles FOR UPDATE USING (public.is_admin());
  END IF;
  IF EXISTS (SELECT 1 FROM pg_policy p JOIN pg_class c ON c.oid = p.polrelid
             WHERE c.relname = 'profiles' AND p.polname = 'Admins can update any profile') THEN
    DROP POLICY "Admins can update any profile" ON public.profiles;
    CREATE POLICY "Admins can update any profile" ON public.profiles FOR UPDATE USING (public.is_admin());
  END IF;
END
$$;

-- ────────────────────────────────────────────────────────────────
-- 3. Also fix policies on OTHER tables that inline the same
--    self-referential profiles subquery. These are NOT recursive on
--    their own table, but they still evaluate RLS on profiles as part
--    of their USING clause — so they were equally broken by the
--    recursive profiles policies, and they'd be re-broken the moment
--    profiles RLS is ever restricted again. Switching them all to
--    public.is_admin() / public.is_seller_or_admin() is the durable
--    fix.
--    IMPORTANT: each rebuild is guarded on the policy ALREADY EXISTING
--    in the live DB (pg_policy check). A DB that never had a given
--    policy keeps exactly that state — this migration never ADDS a
--    privilege that wasn't there. The same guard applies to the
--    profiles policies in §2 (they are rebuilt because they are the
--    recursion source, but only if they already exist).
--
--    COVERAGE NOTE: tables not listed here (e.g. notifications,
--    conversations, addresses) still inline the old profiles subquery
--    in some policies. Post-fix these are HARMLESS — profiles SELECT
--    is world-readable ("conversation partners" USING(true)) and the
--    helper functions don't recurse — so they are not blockers. They
--    would only matter if profiles RLS is ever tightened again; at
--    that point they can be converted the same way as below.
-- ────────────────────────────────────────────────────────────────

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_policy p JOIN pg_class c ON c.oid = p.polrelid
             WHERE c.relname = 'orders' AND p.polname = 'Admins can read all orders') THEN
    DROP POLICY "Admins can read all orders" ON public.orders;
    CREATE POLICY "Admins can read all orders" ON public.orders FOR SELECT USING (public.is_admin());
  END IF;
  IF EXISTS (SELECT 1 FROM pg_policy p JOIN pg_class c ON c.oid = p.polrelid
             WHERE c.relname = 'orders' AND p.polname = 'Admins can update all orders') THEN
    DROP POLICY "Admins can update all orders" ON public.orders;
    CREATE POLICY "Admins can update all orders" ON public.orders FOR UPDATE USING (public.is_admin());
  END IF;
  IF EXISTS (SELECT 1 FROM pg_policy p JOIN pg_class c ON c.oid = p.polrelid
             WHERE c.relname = 'orders' AND p.polname = 'Sellers and Admins can update order status') THEN
    DROP POLICY "Sellers and Admins can update order status" ON public.orders;
    CREATE POLICY "Sellers and Admins can update order status" ON public.orders FOR UPDATE USING (public.is_seller_or_admin());
  END IF;
END
$$;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_policy p JOIN pg_class c ON c.oid = p.polrelid
             WHERE c.relname = 'products' AND p.polname = 'Admins can read all products') THEN
    DROP POLICY "Admins can read all products" ON public.products;
    CREATE POLICY "Admins can read all products" ON public.products FOR SELECT USING (public.is_admin());
  END IF;
  IF EXISTS (SELECT 1 FROM pg_policy p JOIN pg_class c ON c.oid = p.polrelid
             WHERE c.relname = 'products' AND p.polname = 'Admins can update all products') THEN
    DROP POLICY "Admins can update all products" ON public.products;
    CREATE POLICY "Admins can update all products" ON public.products FOR UPDATE USING (public.is_admin());
  END IF;
  IF EXISTS (SELECT 1 FROM pg_policy p JOIN pg_class c ON c.oid = p.polrelid
             WHERE c.relname = 'products' AND p.polname = 'Sellers and Admins can insert products') THEN
    DROP POLICY "Sellers and Admins can insert products" ON public.products;
    CREATE POLICY "Sellers and Admins can insert products" ON public.products FOR INSERT WITH CHECK (public.is_seller_or_admin());
  END IF;
  IF EXISTS (SELECT 1 FROM pg_policy p JOIN pg_class c ON c.oid = p.polrelid
             WHERE c.relname = 'products' AND p.polname = 'Sellers and Admins can update products') THEN
    DROP POLICY "Sellers and Admins can update products" ON public.products;
    CREATE POLICY "Sellers and Admins can update products" ON public.products FOR UPDATE USING (public.is_seller_or_admin());
  END IF;
  IF EXISTS (SELECT 1 FROM pg_policy p JOIN pg_class c ON c.oid = p.polrelid
             WHERE c.relname = 'products' AND p.polname = 'Sellers and Admins can delete products') THEN
    DROP POLICY "Sellers and Admins can delete products" ON public.products;
    CREATE POLICY "Sellers and Admins can delete products" ON public.products FOR DELETE USING (public.is_seller_or_admin());
  END IF;
END
$$;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_policy p JOIN pg_class c ON c.oid = p.polrelid
             WHERE c.relname = 'stores' AND p.polname = 'Admins can manage all stores') THEN
    DROP POLICY "Admins can manage all stores" ON public.stores;
    CREATE POLICY "Admins can manage all stores" ON public.stores FOR ALL USING (public.is_admin());
  END IF;
END
$$;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_policy p JOIN pg_class c ON c.oid = p.polrelid
             WHERE c.relname = 'story_entries' AND p.polname = 'Admins can manage story entries') THEN
    DROP POLICY "Admins can manage story entries" ON public.story_entries;
    CREATE POLICY "Admins can manage story entries" ON public.story_entries FOR ALL USING (public.is_admin());
  END IF;
END
$$;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_policy p JOIN pg_class c ON c.oid = p.polrelid
             WHERE c.relname = 'product_images' AND p.polname = 'Admins can manage all product images') THEN
    DROP POLICY "Admins can manage all product images" ON public.product_images;
    CREATE POLICY "Admins can manage all product images" ON public.product_images FOR ALL USING (public.is_admin());
  END IF;
END
$$;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_policy p JOIN pg_class c ON c.oid = p.polrelid
             WHERE c.relname = 'product_variants' AND p.polname = 'Admins can manage all product variants') THEN
    DROP POLICY "Admins can manage all product variants" ON public.product_variants;
    CREATE POLICY "Admins can manage all product variants" ON public.product_variants FOR ALL USING (public.is_admin());
  END IF;
END
$$;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_policy p JOIN pg_class c ON c.oid = p.polrelid
             WHERE c.relname = 'product_customizations' AND p.polname = 'Admins can manage all product customizations') THEN
    DROP POLICY "Admins can manage all product customizations" ON public.product_customizations;
    CREATE POLICY "Admins can manage all product customizations" ON public.product_customizations FOR ALL USING (public.is_admin());
  END IF;
END
$$;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_policy p JOIN pg_class c ON c.oid = p.polrelid
             WHERE c.relname = 'inventory' AND p.polname = 'Admins can manage all inventory') THEN
    DROP POLICY "Admins can manage all inventory" ON public.inventory;
    CREATE POLICY "Admins can manage all inventory" ON public.inventory FOR ALL USING (public.is_admin());
  END IF;
END
$$;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_policy p JOIN pg_class c ON c.oid = p.polrelid
             WHERE c.relname = 'sales_transactions' AND p.polname = 'Admins can view all transactions') THEN
    DROP POLICY "Admins can view all transactions" ON public.sales_transactions;
    CREATE POLICY "Admins can view all transactions" ON public.sales_transactions FOR SELECT USING (public.is_admin());
  END IF;
  -- NOTE: "Sellers can view their store's transactions" is NOT touched —
  -- it checks store ownership via stores, not profiles, so it never
  -- triggered the recursion and rewriting it would be a semantic change.
END
$$;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_policy p JOIN pg_class c ON c.oid = p.polrelid
             WHERE c.relname = 'customization_requests' AND p.polname = 'Admins can view all customization requests') THEN
    DROP POLICY "Admins can view all customization requests" ON public.customization_requests;
    CREATE POLICY "Admins can view all customization requests" ON public.customization_requests FOR SELECT USING (public.is_admin());
  END IF;
  IF EXISTS (SELECT 1 FROM pg_policy p JOIN pg_class c ON c.oid = p.polrelid
             WHERE c.relname = 'customization_requests' AND p.polname = 'Sellers and Admins can update customization status') THEN
    DROP POLICY "Sellers and Admins can update customization status" ON public.customization_requests;
    CREATE POLICY "Sellers and Admins can update customization status" ON public.customization_requests FOR UPDATE USING (public.is_seller_or_admin());
  END IF;
END
$$;

DO $$
BEGIN
  -- order_items read path (schema.sql-era policy) — preserves the ORIGINAL
  -- semantics (order's customer OR any seller/admin) while removing the
  -- inline profiles subquery that triggered the recursion.
  IF EXISTS (SELECT 1 FROM pg_policy p JOIN pg_class c ON c.oid = p.polrelid
             WHERE c.relname = 'order_items' AND p.polname = 'Order items follow order access rules') THEN
    DROP POLICY "Order items follow order access rules" ON public.order_items;
    CREATE POLICY "Order items follow order access rules" ON public.order_items FOR SELECT
      USING (
        EXISTS (
          SELECT 1 FROM public.orders
          WHERE id = order_id AND (
            customer_id = auth.uid()
            OR public.is_seller_or_admin()
          )
        )
      );
  END IF;
END
$$;

DO $$
BEGIN
  -- sales_transaction_items read path (schema.sql-era policy) — preserves the
  -- ORIGINAL semantics (store owner OR admin) while replacing the inline
  -- profiles subquery with the recursion-free helper.
  IF EXISTS (SELECT 1 FROM pg_policy p JOIN pg_class c ON c.oid = p.polrelid
             WHERE c.relname = 'sales_transaction_items' AND p.polname = 'Transaction items follow transaction access rules') THEN
    DROP POLICY "Transaction items follow transaction access rules" ON public.sales_transaction_items;
    CREATE POLICY "Transaction items follow transaction access rules" ON public.sales_transaction_items FOR SELECT
      USING (
        EXISTS (
          SELECT 1 FROM public.sales_transactions st
          WHERE id = transaction_id AND (
            EXISTS (SELECT 1 FROM public.stores WHERE id = st.store_id AND owner_id = auth.uid())
            OR public.is_admin()
          )
        )
      );
  END IF;
END
$$;

-- ────────────────────────────────────────────────────────────────
-- VERIFICATION (run after applying)
-- ────────────────────────────────────────────────────────────────
-- SELECT public.is_admin();                                  -- false for a normal user
-- SELECT public.is_seller_or_admin();                        -- false for a normal user
-- SELECT * FROM pg_policies WHERE tablename = 'profiles';    -- no policy contains
--                                                              -- "FROM public.profiles"
-- SELECT policyname, cmd, qual FROM pg_policies
--   WHERE tablename IN ('profiles','orders','products','stores')
--   AND qual LIKE '%is_admin%';                               -- all admin checks via helper
