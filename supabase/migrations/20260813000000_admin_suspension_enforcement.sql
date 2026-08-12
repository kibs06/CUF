-- ══════════════════════════════════════════════════════════════════
-- Admin suspension enforcement — hard ban for suspended accounts
-- ══════════════════════════════════════════════════════════════════
-- WHAT THIS ADDS
--   1. profiles.suspended_reason / suspended_at  (audit trail for bans)
--   2. public.is_suspended()  — SECURITY DEFINER helper, same pattern as
--      is_admin(): policies call it without re-entering profiles RLS
--      (avoids the 42P17 infinite-recursion trap).
--   3. is_admin() / is_seller_or_admin() now ALSO exclude suspended
--      accounts. Because nearly every admin/seller policy routes through
--      these two helpers, a suspended admin or seller loses ALL elevated
--      access the moment the flag flips — no per-table policy edits
--      needed for those roles.
--   4. Customer-write policies that DON'T use those helpers (orders,
--      cart, reviews, customization requests, messages, follows, POS
--      sales) get an explicit `AND NOT public.is_suspended()` so a
--      banned customer can't place orders / message sellers etc.
--   5. Guard triggers: an admin cannot demote or suspend themselves,
--      and the last active admin cannot be demoted or suspended.
--
-- NOTE: banning cannot be enforced at the login layer by RLS (auth
-- happens before any policy runs), so the Flutter app's AuthGate and
-- the admin portal's useAuth check `suspended` on the profile and block
-- sign-in there. RLS here is the second, server-side layer that keeps
-- an already-logged-in suspended user out of the data plane.
-- ══════════════════════════════════════════════════════════════════

-- ─── 1. Audit columns ─────────────────────────────────────────────
-- DEPLOY ORDER: apply this migration BEFORE deploying the admin portal
-- changes — useUsers.js selects suspended_reason / suspended_at, and
-- PostgREST 400s on missing columns until this has run.
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS suspended_reason TEXT,
  ADD COLUMN IF NOT EXISTS suspended_at    TIMESTAMPTZ;

COMMENT ON COLUMN public.profiles.suspended_reason IS
  'Why the account was suspended (set by the admin portal).';
COMMENT ON COLUMN public.profiles.suspended_at IS
  'When the account was suspended (set by the admin portal).';

-- ─── 2. is_suspended() helper ─────────────────────────────────────
-- SECURITY DEFINER so policies can call it without re-entering
-- profiles RLS (same rationale as is_admin()). anon + authenticated
-- both need EXECUTE because policies are evaluated for both roles.
CREATE OR REPLACE FUNCTION public.is_suspended()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    (SELECT suspended FROM public.profiles WHERE id = auth.uid()),
    false
  );
$$;

REVOKE EXECUTE ON FUNCTION public.is_suspended() FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.is_suspended() TO anon, authenticated;

COMMENT ON FUNCTION public.is_suspended() IS
  'True when the current user profile has suspended = true. SECURITY DEFINER (bypasses RLS) so write policies can block suspended users without re-entering profiles RLS (fixes 42P17 infinite recursion).';

-- ─── 3. Redefine role helpers to exclude suspended accounts ───────
-- CREATE OR REPLACE preserves existing ACLs. Any policy that calls
-- is_admin() / is_seller_or_admin() (products, orders, stores, reviews,
-- seller_business_docs, admin reads...) now returns false for a
-- suspended account — instant, DB-wide loss of elevated access.
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid()
      AND role = 'admin'
      AND NOT COALESCE(suspended, false)
  );
$$;

REVOKE EXECUTE ON FUNCTION public.is_admin() FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.is_admin() TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.is_seller_or_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid()
      AND role IN ('seller', 'admin')
      AND NOT COALESCE(suspended, false)
  );
$$;

REVOKE EXECUTE ON FUNCTION public.is_seller_or_admin() FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.is_seller_or_admin() TO anon, authenticated;

-- ─── 4. Block suspended users in customer/seller write policies ───
-- (Policies already routing through is_admin/is_seller_or_admin are
--  covered by the redefinitions above and are NOT touched here.)

-- Orders — a banned customer can no longer place orders
DROP POLICY IF EXISTS "Users can place their own orders" ON public.orders;
CREATE POLICY "Users can place their own orders"
    ON public.orders FOR INSERT
    WITH CHECK (auth.uid() = customer_id AND NOT public.is_suspended());

-- Cart — banned customer can't add to cart
DROP POLICY IF EXISTS "Users can insert items into their cart" ON public.cart_items;
CREATE POLICY "Users can insert items into their cart"
    ON public.cart_items FOR INSERT
    WITH CHECK (auth.uid() = user_id AND NOT public.is_suspended());

-- Reviews — banned customer can't post reviews
DROP POLICY IF EXISTS "Customers can insert their own reviews" ON public.reviews;
CREATE POLICY "Customers can insert their own reviews"
    ON public.reviews FOR INSERT
    WITH CHECK (auth.uid() = customer_id AND NOT public.is_suspended());

-- Legacy product_reviews table — only exists on DBs where migration
-- 20260717_product_reviews.sql was applied (the current app uses the
-- `reviews` table instead). Guard so this migration never fails with
-- 42P01 on databases where that legacy table was never created.
DO $$
BEGIN
  IF to_regclass('public.product_reviews') IS NOT NULL THEN
    DROP POLICY IF EXISTS "Customers can insert reviews for purchased products" ON public.product_reviews;
    CREATE POLICY "Customers can insert reviews for purchased products" ON public.product_reviews
      FOR INSERT WITH CHECK (
        auth.uid() = customer_id
        AND NOT public.is_suspended()
        AND EXISTS (
          SELECT 1 FROM public.order_items oi
          JOIN public.orders o ON o.id = oi.order_id
          WHERE o.customer_id = auth.uid() AND oi.product_id = product_reviews.product_id
        )
      );
  END IF;
END
$$;

-- Customization requests — banned customer can't submit new requests
DROP POLICY IF EXISTS "Users can create customization requests" ON public.customization_requests;
CREATE POLICY "Users can create customization requests"
    ON public.customization_requests FOR INSERT
    WITH CHECK (auth.uid() = customer_id AND NOT public.is_suspended());

-- Conversations & messages — banned customer can't start threads / message
DROP POLICY IF EXISTS "customer_insert_conversations" ON public.conversations;
CREATE POLICY "customer_insert_conversations"
  ON conversations FOR INSERT
  WITH CHECK (customer_id = auth.uid() AND NOT public.is_suspended());

DROP POLICY IF EXISTS "customer_insert_messages" ON public.messages;
CREATE POLICY "customer_insert_messages"
  ON messages FOR INSERT
  WITH CHECK (
    sender_id = auth.uid()
    AND sender_type = 'customer'
    AND NOT public.is_suspended()
    AND conversation_id IN (
      SELECT id FROM conversations WHERE customer_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "seller_insert_messages" ON public.messages;
CREATE POLICY "seller_insert_messages"
  ON messages FOR INSERT
  WITH CHECK (
    sender_id = auth.uid()
    AND sender_type = 'seller'
    AND NOT public.is_suspended()
    AND conversation_id IN (
      SELECT c.id FROM conversations c
      JOIN stores s ON c.store_id = s.id
      WHERE s.owner_id = auth.uid()
    )
  );

-- Store follows — banned customer can't follow stores
DROP POLICY IF EXISTS "Users can follow stores" ON public.store_follows;
CREATE POLICY "Users can follow stores"
    ON public.store_follows FOR INSERT
    WITH CHECK (auth.uid() = user_id AND NOT public.is_suspended());

-- POS sales — suspended seller can't ring up register sales
DROP POLICY IF EXISTS "Sellers can create transactions for their store" ON public.sales_transactions;
CREATE POLICY "Sellers can create transactions for their store"
    ON public.sales_transactions FOR INSERT
    WITH CHECK (
      NOT public.is_suspended()
      AND EXISTS (
        SELECT 1 FROM public.stores
        WHERE id = store_id AND owner_id = auth.uid()
      )
    );

-- ─── 5. Guard triggers ────────────────────────────────────────────
-- An admin cannot demote or suspend their own account (would lock the
-- only admin out of the console), and the LAST active admin can never
-- be demoted/suspended by anyone.

CREATE OR REPLACE FUNCTION public.prevent_admin_self_lockout()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF OLD.role = 'admin'
     AND auth.uid() = OLD.id
     AND (NEW.role IS DISTINCT FROM 'admin' OR NEW.suspended IS DISTINCT FROM false)
  THEN
    RAISE EXCEPTION 'You cannot demote or suspend your own admin account.';
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.protect_last_admin()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF OLD.role = 'admin'
     AND (NEW.role IS DISTINCT FROM 'admin' OR NEW.suspended IS DISTINCT FROM false)
     AND (SELECT count(*) FROM public.profiles
          WHERE role = 'admin' AND NOT COALESCE(suspended, false)) <= 1
  THEN
    RAISE EXCEPTION 'Cannot demote or suspend the last active admin.';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_admin_self_lockout ON public.profiles;
CREATE TRIGGER trg_prevent_admin_self_lockout
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.prevent_admin_self_lockout();

DROP TRIGGER IF EXISTS trg_protect_last_admin ON public.profiles;
CREATE TRIGGER trg_protect_last_admin
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.protect_last_admin();
