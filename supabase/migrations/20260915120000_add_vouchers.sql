-- ══════════════════════════════════════════════════════════════════
-- Migration: Vouchers / coupon codes — schema (ANQUI checklist item #5)
-- Date: 2026-09-15
-- Depends on: 20260804000000 (products.sale_price window),
--             20260808120000 (orders.items_snapshot),
--             20260809120000 (public.is_admin / is_seller_or_admin),
--             20260717_product_reviews.sql (public.set_updated_at)
--
-- Purpose: the client confirmed per-product sale pricing is NOT enough —
--          store owners want real discount CODES ("ANQUI10") entered at
--          checkout. This migration adds the tables; the enforcement
--          (validation + atomic redemption) lives in
--              20260915130000_add_voucher_enforcement.sql
--
-- Security posture (read before changing anything here):
--   • The client NEVER sends a discount amount. It sends a CODE on the
--     order insert; the server looks the code up, validates it and
--     recomputes the payable total inside the SAME transaction as the
--     order insert (see the orders triggers in the enforcement
--     migration). A modified client therefore cannot forge a total.
--   • Customers have NO select policy on `vouchers` at all — the only
--     way to read a voucher is through the SECURITY DEFINER preview RPC
--     (`validate_voucher`), which takes a code. Codes cannot be listed
--     or enumerated from the app.
--   • Redemptions are written ONLY by the orders trigger (SECURITY
--     DEFINER). There is deliberately no INSERT/UPDATE/DELETE policy.
--
-- Client-visible decisions made here (flagged for review):
--   • Platform-wide vouchers (store_id IS NULL) can only be created by
--     an admin; sellers can read them but never write them.
--   • DEACTIVATE, never DELETE: there is no DELETE policy on vouchers,
--     because redemptions reference them for reconciliation.
--   • A voucher's money terms (code / type / value / store scope) are
--     frozen once it has been redeemed at least once, so historical
--     orders stay explainable. Everything else (window, caps, active
--     flag, minimum) stays editable so a seller can extend or stop a
--     live promo.
-- ══════════════════════════════════════════════════════════════════

-- ────────────────────────────────────────────────────────────────
-- 0. orders — the money breakdown a voucher needs to be auditable
--    subtotal_amount / discount_amount are written by the server (the
--    trigger), not by callers; voucher_code + voucher_id are snapshotted
--    onto the order so history survives an edited or deleted voucher.
-- ────────────────────────────────────────────────────────────────
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS subtotal_amount NUMERIC,
  ADD COLUMN IF NOT EXISTS discount_amount NUMERIC NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS voucher_code    TEXT,
  ADD COLUMN IF NOT EXISTS voucher_id      UUID;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'orders_discount_amount_non_negative'
  ) THEN
    ALTER TABLE public.orders
      ADD CONSTRAINT orders_discount_amount_non_negative CHECK (discount_amount >= 0);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'orders_subtotal_amount_non_negative'
  ) THEN
    ALTER TABLE public.orders
      ADD CONSTRAINT orders_subtotal_amount_non_negative
      CHECK (subtotal_amount IS NULL OR subtotal_amount >= 0);
  END IF;
END $$;

COMMENT ON COLUMN public.orders.subtotal_amount IS
  'Server-computed goods subtotal (excludes the fixed ₱100 delivery fee). Written by orders_apply_voucher() when a voucher is used; NULL on orders placed without one.';
COMMENT ON COLUMN public.orders.discount_amount IS
  'Voucher discount actually granted on this order, in pesos. Server-computed — never accepted from a client.';
COMMENT ON COLUMN public.orders.voucher_code IS
  'Normalized (upper-case) voucher code snapshot. Kept on the order so history stays correct after the voucher is edited or deactivated.';
COMMENT ON COLUMN public.orders.voucher_id IS
  'Voucher row that was redeemed. ON DELETE SET NULL — the code snapshot above is what history reads.';

-- ────────────────────────────────────────────────────────────────
-- 1. vouchers
--    One row per code. store_id NULL = platform-wide (admin-created).
--    funded_by records WHO absorbs the discount, which is the field
--    sellers need for reconciliation (a platform promo must not be
--    read as the seller's own giveaway).
-- ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.vouchers (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code                TEXT NOT NULL,
  store_id            UUID REFERENCES public.stores(id) ON DELETE CASCADE,
  discount_type       TEXT NOT NULL CHECK (discount_type IN ('fixed', 'percent')),
  discount_value      NUMERIC NOT NULL CHECK (discount_value > 0),
  -- Percent vouchers are stored 0 < value <= 100 and may be capped in
  -- pesos (e.g. 20% up to ₱150). Fixed vouchers ignore the cap.
  max_discount_amount NUMERIC CHECK (max_discount_amount IS NULL OR max_discount_amount > 0),
  min_order_amount    NUMERIC NOT NULL DEFAULT 0 CHECK (min_order_amount >= 0),
  max_uses            INTEGER CHECK (max_uses IS NULL OR max_uses > 0),
  uses_count          INTEGER NOT NULL DEFAULT 0 CHECK (uses_count >= 0),
  per_user_limit      INTEGER NOT NULL DEFAULT 1 CHECK (per_user_limit > 0),
  starts_at           TIMESTAMPTZ,
  ends_at             TIMESTAMPTZ,
  funded_by           TEXT NOT NULL DEFAULT 'store' CHECK (funded_by IN ('store', 'platform')),
  is_active           BOOLEAN NOT NULL DEFAULT TRUE,
  created_by          UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (starts_at IS NULL OR ends_at IS NULL OR ends_at > starts_at),
  CHECK (discount_type <> 'percent' OR discount_value <= 100)
);

COMMENT ON TABLE public.vouchers IS
  'Discount codes. store_id NULL = platform-wide (admin-only). The discount is applied server-side at order creation — see 20260915130000.';
COMMENT ON COLUMN public.vouchers.funded_by IS
  'Who absorbs the discount: ''store'' (the seller) or ''platform''. Sellers can only ever create store-funded vouchers (enforced by the INSERT/UPDATE policies); platform funding is an admin-only field.';
COMMENT ON COLUMN public.vouchers.per_user_limit IS
  'Max redemptions per customer. Enforced under a FOR UPDATE lock on this row, so concurrent checkouts cannot both pass.';
COMMENT ON COLUMN public.vouchers.uses_count IS
  'Redemptions so far. Only ever incremented by the orders redemption trigger (same transaction as the order).';

-- Case-insensitive uniqueness + lookup. Codes are normalized to
-- upper/trim by the trigger below, so this index is the enforced truth.
CREATE UNIQUE INDEX IF NOT EXISTS uq_vouchers_code ON public.vouchers (code);
CREATE INDEX IF NOT EXISTS idx_vouchers_store ON public.vouchers (store_id);
CREATE INDEX IF NOT EXISTS idx_vouchers_active_window
  ON public.vouchers (code) WHERE is_active;

-- FK added after the table it points at, in its own guarded block so a
-- re-run (or a partial earlier run) is harmless.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'orders_voucher_id_fkey'
  ) THEN
    ALTER TABLE public.orders
      ADD CONSTRAINT orders_voucher_id_fkey
      FOREIGN KEY (voucher_id) REFERENCES public.vouchers(id) ON DELETE SET NULL;
  END IF;
END $$;

-- Normalize the code on the way in (defensive: the RPCs upper-case too,
-- so a hand-written SQL insert can never create a code the app cannot
-- look up).
CREATE OR REPLACE FUNCTION public.normalize_voucher_fields()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  NEW.code := upper(btrim(NEW.code));
  IF NEW.code = '' THEN
    RAISE EXCEPTION 'A voucher needs a code' USING ERRCODE = 'P0001';
  END IF;
  IF NEW.discount_type = 'percent' THEN
    NEW.discount_value := round(NEW.discount_value, 2);
  ELSE
    NEW.discount_value := round(NEW.discount_value, 2);
  END IF;
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_normalize_voucher_fields ON public.vouchers;
CREATE TRIGGER trg_normalize_voucher_fields
  BEFORE INSERT OR UPDATE ON public.vouchers
  FOR EACH ROW EXECUTE FUNCTION public.normalize_voucher_fields();

-- Freeze money terms once money has actually been discounted.
CREATE OR REPLACE FUNCTION public.guard_voucher_money_terms()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF OLD.uses_count > 0 OR EXISTS (
    SELECT 1 FROM public.voucher_redemptions r WHERE r.voucher_id = OLD.id
  ) THEN
    IF NEW.code <> OLD.code
       OR NEW.discount_type <> OLD.discount_type
       OR NEW.discount_value <> OLD.discount_value
       OR NEW.store_id IS DISTINCT FROM OLD.store_id
       OR NEW.funded_by <> OLD.funded_by THEN
      RAISE EXCEPTION
        'This voucher has already been redeemed, so its code and discount can no longer be changed. Deactivate it and create a new one instead.'
        USING ERRCODE = 'P0001';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_voucher_money_terms ON public.vouchers;
CREATE TRIGGER trg_guard_voucher_money_terms
  BEFORE UPDATE ON public.vouchers
  FOR EACH ROW EXECUTE FUNCTION public.guard_voucher_money_terms();

-- ────────────────────────────────────────────────────────────────
-- 2. voucher_redemptions
--    One row per (voucher, order). This is what per-user limits and the
--    seller's redemption history read — counting orders afterwards
--    would drift as soon as an order is cancelled or deleted.
-- ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.voucher_redemptions (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  voucher_id      UUID NOT NULL REFERENCES public.vouchers(id) ON DELETE RESTRICT,
  code            TEXT NOT NULL,
  customer_id     UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  order_id        UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  store_id        UUID REFERENCES public.stores(id) ON DELETE SET NULL,
  discount_amount NUMERIC NOT NULL CHECK (discount_amount > 0),
  funded_by       TEXT NOT NULL CHECK (funded_by IN ('store', 'platform')),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (voucher_id, order_id)
);

COMMENT ON TABLE public.voucher_redemptions IS
  'Append-only record of which customer redeemed which voucher on which order. Written only by the orders AFTER INSERT trigger.';
COMMENT ON COLUMN public.voucher_redemptions.order_id IS
  'UNIQUE per voucher: a single order can never redeem the same voucher twice.';

CREATE INDEX IF NOT EXISTS idx_voucher_redemptions_voucher
  ON public.voucher_redemptions (voucher_id);
CREATE INDEX IF NOT EXISTS idx_voucher_redemptions_customer
  ON public.voucher_redemptions (voucher_id, customer_id);
CREATE INDEX IF NOT EXISTS idx_voucher_redemptions_store
  ON public.voucher_redemptions (store_id, created_at DESC);

-- ────────────────────────────────────────────────────────────────
-- 3. RLS
-- ────────────────────────────────────────────────────────────────
ALTER TABLE public.vouchers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.voucher_redemptions ENABLE ROW LEVEL SECURITY;

-- ── vouchers ────────────────────────────────────────────────────
-- CUSTOMERS have no read access at all: they can only learn about a code
-- by presenting it to validate_voucher() (SECURITY DEFINER), so codes
-- cannot be listed or enumerated from the app. Sellers see their own
-- store's codes plus platform-wide ones; admins see everything.
DROP POLICY IF EXISTS "Sellers read their own vouchers" ON public.vouchers;
CREATE POLICY "Sellers read their own vouchers"
  ON public.vouchers FOR SELECT
  TO authenticated
  USING (
    public.is_admin()
    OR EXISTS (
      SELECT 1 FROM public.stores s
      WHERE s.id = vouchers.store_id AND s.owner_id = auth.uid()
    )
    OR (store_id IS NULL AND public.is_seller_or_admin())
  );

-- Sellers may create store-scoped vouchers only; platform-wide ones are
-- admin-only (the CHECK on the table also forces funded_by='platform').
DROP POLICY IF EXISTS "Sellers create store vouchers" ON public.vouchers;
CREATE POLICY "Sellers create store vouchers"
  ON public.vouchers FOR INSERT
  TO authenticated
  WITH CHECK (
    public.is_admin()
    OR (
      store_id IS NOT NULL
      AND funded_by = 'store'
      AND created_by = auth.uid()
      AND EXISTS (
        SELECT 1 FROM public.stores s
        WHERE s.id = vouchers.store_id AND s.owner_id = auth.uid()
      )
    )
  );

DROP POLICY IF EXISTS "Sellers update their own vouchers" ON public.vouchers;
CREATE POLICY "Sellers update their own vouchers"
  ON public.vouchers FOR UPDATE
  TO authenticated
  USING (
    public.is_admin()
    OR EXISTS (
      SELECT 1 FROM public.stores s
      WHERE s.id = vouchers.store_id AND s.owner_id = auth.uid()
    )
  )
  WITH CHECK (
    public.is_admin()
    OR (
      store_id IS NOT NULL
      AND funded_by = 'store'
      AND EXISTS (
        SELECT 1 FROM public.stores s
        WHERE s.id = vouchers.store_id AND s.owner_id = auth.uid()
      )
    )
  );

-- NOTE: deliberately no DELETE policy — vouchers are deactivated, never
-- deleted, so redemption history stays readable.

-- ── voucher_redemptions (read-only for everyone; writes via trigger) ──
DROP POLICY IF EXISTS "Customers read their own redemptions" ON public.voucher_redemptions;
CREATE POLICY "Customers read their own redemptions"
  ON public.voucher_redemptions FOR SELECT
  TO authenticated
  USING (auth.uid() = customer_id);

DROP POLICY IF EXISTS "Sellers read redemptions for their store" ON public.voucher_redemptions;
CREATE POLICY "Sellers read redemptions for their store"
  ON public.voucher_redemptions FOR SELECT
  TO authenticated
  USING (
    public.is_admin()
    OR (
      store_id IS NOT NULL
      AND EXISTS (
        SELECT 1 FROM public.stores s
        WHERE s.id = voucher_redemptions.store_id AND s.owner_id = auth.uid()
      )
    )
  );

-- ────────────────────────────────────────────────────────────────
-- 4. Server-side pricing helpers
--    Single source of truth for "what does this cart cost on the
--    server". Used by BOTH the checkout preview RPC and the order
--    trigger, so a preview can never disagree with what gets charged.
-- ────────────────────────────────────────────────────────────────

-- Mirrors lib/utils/sale_price.dart (isOnSale / effectivePrice) exactly:
-- a product counts as on sale only when sale_price is set, strictly
-- below price, and now() sits inside the optional window.
CREATE OR REPLACE FUNCTION public.product_effective_price(
  p_price         numeric,
  p_sale_price    numeric,
  p_sale_starts_at timestamptz,
  p_sale_ends_at  timestamptz,
  p_at            timestamptz
) RETURNS numeric
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN COALESCE(p_price, 0) <= 0 THEN 0
    WHEN p_sale_price IS NULL OR p_sale_price <= 0 THEN p_price
    WHEN p_sale_price >= p_price THEN p_price
    WHEN p_sale_starts_at IS NOT NULL AND p_at < p_sale_starts_at THEN p_price
    WHEN p_sale_ends_at IS NOT NULL AND p_at > p_sale_ends_at THEN p_price
    ELSE p_sale_price
  END;
$$;

COMMENT ON FUNCTION public.product_effective_price(numeric, numeric, timestamptz, timestamptz, timestamptz) IS
  'Sale-aware unit price. Mirrors lib/utils/sale_price.dart — keep both in sync.';

-- Reprice a cart from the database, resolving sizes against live stock.
-- Returns {store_id, subtotal, items:[{product_id,product_name,size,quantity,unit_price}]}.
-- Prices come from public.products, so a client-supplied unit price is
-- never trusted. Raises P0001 with a customer-readable message for every
-- rejection (same copy the checkout UI already shows).
CREATE OR REPLACE FUNCTION public.checkout_cart_summary(p_items jsonb)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_item          jsonb;
  v_product_uuid  uuid;
  v_cart_size     text;
  v_qty           int;
  v_price         numeric;
  v_name          text;
  v_store_id      uuid;
  v_first_store   uuid := NULL;
  v_resolved_size text;
  v_subtotal      numeric := 0;
  v_out           jsonb := '[]'::jsonb;
BEGIN
  IF p_items IS NULL
     OR jsonb_typeof(p_items) <> 'array'
     OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'No items to order' USING ERRCODE = 'P0001';
  END IF;

  FOR v_item IN SELECT value FROM jsonb_array_elements(p_items) LOOP
    v_qty := COALESCE((v_item->>'quantity')::int, 0);
    IF v_item->>'product_id' IS NULL OR v_qty <= 0 THEN
      RAISE EXCEPTION 'Each item needs a product_id and a quantity greater than zero'
        USING ERRCODE = 'P0001';
    END IF;
    BEGIN
      v_product_uuid := (v_item->>'product_id')::uuid;
    EXCEPTION WHEN others THEN
      RAISE EXCEPTION 'Invalid product reference in cart' USING ERRCODE = 'P0001';
    END;
    v_cart_size := COALESCE(v_item->>'size', '');

    SELECT public.product_effective_price(
             p.price, p.sale_price, p.sale_starts_at, p.sale_ends_at, now()),
           p.name,
           p.store_id
      INTO v_price, v_name, v_store_id
      FROM public.products p
     WHERE p.id = v_product_uuid;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'One of your items is no longer available. Please refresh your cart.'
        USING ERRCODE = 'P0001';
    END IF;

    IF v_first_store IS NULL THEN
      v_first_store := v_store_id;
    ELSIF v_store_id <> v_first_store THEN
      RAISE EXCEPTION 'Your cart contains items from different stores. Please check out each store separately.'
        USING ERRCODE = 'P0001';
    END IF;

    -- Size resolution mirrors create_gcash_checkout / resolveInventorySize.
    SELECT size INTO v_resolved_size
      FROM public.inventory
     WHERE product_id = v_product_uuid
       AND stock > 0
       AND regexp_replace(size, '\D', '', 'g')
         = regexp_replace(v_cart_size, '\D', '', 'g')
     LIMIT 1;
    IF v_resolved_size IS NULL AND v_cart_size = '' THEN
      SELECT size INTO v_resolved_size
        FROM public.inventory
       WHERE product_id = v_product_uuid AND stock > 0
       LIMIT 1;
    END IF;
    IF v_resolved_size IS NULL THEN
      RAISE EXCEPTION 'Size "%" is no longer available for %. Please update your cart.',
        v_cart_size, v_name
        USING ERRCODE = 'P0001';
    END IF;

    v_subtotal := v_subtotal + (v_price * v_qty);
    v_out := v_out || jsonb_build_object(
      'product_id', v_product_uuid,
      'product_name', v_name,
      'size', v_resolved_size,
      'quantity', v_qty,
      'unit_price', v_price
    );
  END LOOP;

  IF v_subtotal <= 0 THEN
    RAISE EXCEPTION 'Order total must be greater than zero' USING ERRCODE = 'P0001';
  END IF;

  RETURN jsonb_build_object(
    'store_id', v_first_store,
    'subtotal', v_subtotal,
    'items', v_out
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.checkout_cart_summary(jsonb) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.checkout_cart_summary(jsonb) TO authenticated;

COMMENT ON FUNCTION public.checkout_cart_summary(jsonb) IS
  'Server-side repricing of a cart (sale-aware, size-resolved). Shared by the voucher preview RPC and the orders voucher trigger so the quoted total can never drift from the charged one.';

-- ────────────────────────────────────────────────────────────────
-- VERIFICATION QUERIES (run after applying)
-- ────────────────────────────────────────────────────────────────
-- -- Tables + columns landed
-- SELECT column_name FROM information_schema.columns
--  WHERE table_name = 'orders'
--    AND column_name IN ('subtotal_amount','discount_amount','voucher_code','voucher_id');
-- -- RLS on
-- SELECT relname, relrowsecurity FROM pg_class
--  WHERE relname IN ('vouchers','voucher_redemptions');
-- -- No customer SELECT policy on vouchers (expect 0 customer rows):
-- SELECT policyname, roles FROM pg_policies WHERE tablename = 'vouchers';
