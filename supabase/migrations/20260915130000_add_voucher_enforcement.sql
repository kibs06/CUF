-- ══════════════════════════════════════════════════════════════════
-- Migration: Vouchers / coupon codes — validation + atomic redemption
--            (ANQUI checklist item #5)
-- Date: 2026-09-15
-- Depends on: 20260915120000_add_vouchers.sql (tables + pricing helpers)
--
-- Purpose: ONE place decides whether a code is valid and how big the
--          discount is (public.voucher_evaluate), and ONE place applies
--          it to a real order (the BEFORE INSERT trigger on public.orders
--          + the AFTER INSERT redemption trigger).
--
-- Why a trigger instead of "validate then create":
--   A separate validate call followed by an order insert is a TOCTOU
--   hole — the cart, the voucher's use count, or its window can change
--   in between, and a client could quote a discount it never gets. The
--   trigger runs INSIDE the order insert's transaction, holds
--   `SELECT ... FOR UPDATE` on the voucher row, and OVERWRITES
--   total_amount / discount_amount / subtotal_amount from server-side
--   values. There is no code path — client, POS, edge function or SQL —
--   that can create an online order with a voucher and a forged total.
--
-- Paths that reach it (all of them, deliberately):
--   • GCash  → supabase/functions/create-gcash-payment-intent (service
--     role insert; the service role bypasses RLS, so the trigger is what
--     protects the money).
--   • Cash   → SupabaseService.createOrder (client insert; RLS + trigger).
--   • POS    → rejected: a voucher is an ONLINE-order feature.
--
-- Stacking rule (decided here — flagged for client review):
--   A voucher STACKS on top of an active product sale. The discount base
--   is the sale-aware goods subtotal produced by
--   public.checkout_cart_summary (which applies sale_price exactly like
--   lib/utils/sale_price.dart), and the fixed ₱100 delivery fee is added
--   AFTER the discount, so a voucher never pays for delivery and the
--   payable total can never go negative.
--
-- Customer-visible failure reasons (the UI shows these verbatim):
--   invalid_code, inactive, not_started, expired, max_uses_reached,
--   per_user_limit_reached, below_minimum, wrong_store, empty_cart.
-- ══════════════════════════════════════════════════════════════════

-- ────────────────────────────────────────────────────────────────
-- 0. The fixed online delivery fee, in ONE place
--    (the app's CartProvider.deliveryFee and the PayMongo edge function
--    both use ₱100 — keep this in sync with them)
-- ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.online_delivery_fee()
RETURNS numeric
LANGUAGE sql
IMMUTABLE
AS $$ SELECT 100::numeric $$;

COMMENT ON FUNCTION public.online_delivery_fee() IS
  'Fixed ₱100 delivery fee for online orders. Mirrors CartProvider.deliveryFee and DELIVERY_FEE in create-gcash-payment-intent.';

-- ────────────────────────────────────────────────────────────────
-- 1. voucher_evaluate — THE decision function
--    Called by the customer-facing preview RPC AND by the orders
--    trigger, so what the customer is quoted is exactly what is
--    charged. Returns a verdict; never raises for a bad code (the
--    caller decides whether an invalid code is an error or a message).
--
--    p_lock = TRUE takes `SELECT ... FOR UPDATE` on the voucher row,
--    which is what makes max_uses / per_user_limit race-safe: a second
--    concurrent order blocks on the lock, then re-reads the row with
--    the winner's incremented uses_count.
-- ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.voucher_evaluate(
  p_code     text,
  p_subtotal numeric,
  p_store_id uuid,
  p_user_id  uuid,
  p_lock     boolean DEFAULT false
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_code       text := upper(btrim(COALESCE(p_code, '')));
  v_v          public.vouchers%ROWTYPE;
  v_user_used  integer := 0;
  v_discount   numeric := 0;
  v_store_name text;
  v_base       numeric := COALESCE(p_subtotal, 0);
BEGIN
  IF v_code = '' THEN
    RETURN jsonb_build_object(
      'ok', false, 'reason', 'invalid_code',
      'message', 'Enter a voucher code to apply a discount.'
    );
  END IF;

  IF v_base <= 0 THEN
    RETURN jsonb_build_object(
      'ok', false, 'reason', 'empty_cart',
      'message', 'Add items to your cart before applying a voucher.'
    );
  END IF;

  IF p_lock THEN
    SELECT * INTO v_v FROM public.vouchers WHERE code = v_code FOR UPDATE;
  ELSE
    SELECT * INTO v_v FROM public.vouchers WHERE code = v_code;
  END IF;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'ok', false, 'reason', 'invalid_code',
      'message', 'That code is not valid. Please check it and try again.'
    );
  END IF;

  -- Scoped to one store? Then the cart has to be that store's.
  IF v_v.store_id IS NOT NULL AND v_v.store_id IS DISTINCT FROM p_store_id THEN
    SELECT name INTO v_store_name FROM public.stores WHERE id = v_v.store_id;
    RETURN jsonb_build_object(
      'ok', false, 'reason', 'wrong_store',
      'message', format('That code only works on orders from %s.',
                        COALESCE(v_store_name, 'another store'))
    );
  END IF;

  IF NOT v_v.is_active THEN
    RETURN jsonb_build_object(
      'ok', false, 'reason', 'inactive',
      'message', 'That code is no longer active.'
    );
  END IF;

  IF v_v.starts_at IS NOT NULL AND now() < v_v.starts_at THEN
    RETURN jsonb_build_object(
      'ok', false, 'reason', 'not_started',
      'message', 'That code is not available yet.'
    );
  END IF;

  IF v_v.ends_at IS NOT NULL AND now() > v_v.ends_at THEN
    RETURN jsonb_build_object(
      'ok', false, 'reason', 'expired',
      'message', 'That code has expired.'
    );
  END IF;

  IF v_v.max_uses IS NOT NULL AND v_v.uses_count >= v_v.max_uses THEN
    RETURN jsonb_build_object(
      'ok', false, 'reason', 'max_uses_reached',
      'message', 'That code has already been fully claimed.'
    );
  END IF;

  IF p_user_id IS NOT NULL THEN
    SELECT count(*) INTO v_user_used
      FROM public.voucher_redemptions r
     WHERE r.voucher_id = v_v.id AND r.customer_id = p_user_id;
    IF v_user_used >= v_v.per_user_limit THEN
      RETURN jsonb_build_object(
        'ok', false, 'reason', 'per_user_limit_reached',
        'message', 'You have already used that code.'
      );
    END IF;
  END IF;

  IF v_base < v_v.min_order_amount THEN
    RETURN jsonb_build_object(
      'ok', false, 'reason', 'below_minimum',
      'message', format('Spend at least ₱%s to use that code.',
                        to_char(v_v.min_order_amount, 'FM999,999,990.00'))
    );
  END IF;

  -- Discount math. Never exceeds the goods subtotal (so the payable
  -- total never goes negative), and percent vouchers honour the cap.
  IF v_v.discount_type = 'percent' THEN
    v_discount := round(v_base * v_v.discount_value / 100, 2);
    IF v_v.max_discount_amount IS NOT NULL THEN
      v_discount := LEAST(v_discount, v_v.max_discount_amount);
    END IF;
  ELSE
    v_discount := round(v_v.discount_value, 2);
  END IF;

  IF v_discount > v_base THEN
    v_discount := v_base;
  END IF;
  IF v_discount <= 0 THEN
    RETURN jsonb_build_object(
      'ok', false, 'reason', 'invalid_code',
      'message', 'That code does not discount anything on this order.'
    );
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'reason', 'ok',
    'message', 'Voucher applied.',
    'voucher_id', v_v.id,
    'code', v_v.code,
    'discount_type', v_v.discount_type,
    'discount_value', v_v.discount_value,
    'discount_amount', round(v_discount, 2),
    'funded_by', v_v.funded_by,
    'min_order_amount', v_v.min_order_amount
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.voucher_evaluate(text, numeric, uuid, uuid, boolean) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.voucher_evaluate(text, numeric, uuid, uuid, boolean) TO authenticated;

COMMENT ON FUNCTION public.voucher_evaluate(text, numeric, uuid, uuid, boolean) IS
  'SINGLE source of truth for voucher validity + discount size. Used by validate_voucher (preview) and the orders trigger (enforcement). p_lock=true takes FOR UPDATE on the voucher row so max_uses/per_user_limit are race-safe.';

-- ────────────────────────────────────────────────────────────────
-- 2. validate_voucher — the checkout UI's live quote
--    Reprices the cart server-side (sale-aware), evaluates the code and
--    returns the exact totals the order will get. The client renders
--    this and sends back ONLY the code — never the numbers.
-- ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.validate_voucher(
  p_code  text,
  p_items jsonb
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_summary  jsonb;
  v_subtotal numeric;
  v_store_id uuid;
  v_verdict  jsonb;
  v_discount numeric := 0;
  v_fee      numeric := public.online_delivery_fee();
BEGIN
  v_summary  := public.checkout_cart_summary(p_items);
  v_subtotal := (v_summary->>'subtotal')::numeric;
  v_store_id := (v_summary->>'store_id')::uuid;

  v_verdict := public.voucher_evaluate(
    p_code, v_subtotal, v_store_id, auth.uid(), false
  );

  IF (v_verdict->>'ok')::boolean THEN
    v_discount := (v_verdict->>'discount_amount')::numeric;
  END IF;

  RETURN jsonb_build_object(
    'ok', (v_verdict->>'ok')::boolean,
    'reason', v_verdict->>'reason',
    'message', v_verdict->>'message',
    'code', CASE WHEN (v_verdict->>'ok')::boolean
                 THEN v_verdict->>'code' ELSE upper(btrim(COALESCE(p_code, ''))) END,
    'store_id', v_store_id,
    'subtotal', round(v_subtotal, 2),
    'delivery_fee', v_fee,
    'discount_amount', round(v_discount, 2),
    'total', round(v_subtotal + v_fee - v_discount, 2)
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.validate_voucher(text, jsonb) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.validate_voucher(text, jsonb) TO authenticated;

COMMENT ON FUNCTION public.validate_voucher(text, jsonb) IS
  'Customer-facing voucher preview: reprices the cart server-side and returns the verdict + final totals. Advisory only — the orders trigger re-evaluates and is the enforcement point.';

-- ────────────────────────────────────────────────────────────────
-- 3. Enforcement — apply the voucher inside the order transaction
-- ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.orders_apply_voucher()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_summary  jsonb;
  v_subtotal numeric;
  v_store_id uuid;
  v_verdict  jsonb;
  v_discount numeric;
BEGIN
  IF NEW.voucher_code IS NULL OR btrim(NEW.voucher_code) = '' THEN
    NEW.voucher_code := NULL;
    RETURN NEW;
  END IF;

  -- Vouchers are an online-order feature (POS checkout is in-person).
  -- Reject loudly rather than silently charging full price.
  IF COALESCE(NEW.source, '') <> 'online' THEN
    RAISE EXCEPTION 'Vouchers can only be redeemed on online orders.'
      USING ERRCODE = 'P0001';
  END IF;

  -- The discount base must come from the server, so the order has to
  -- carry the items it is priced from.
  IF NEW.items_snapshot IS NULL
     OR jsonb_typeof(NEW.items_snapshot) <> 'array'
     OR jsonb_array_length(NEW.items_snapshot) = 0 THEN
    RAISE EXCEPTION 'A voucher needs the order items so the discount can be verified.'
      USING ERRCODE = 'P0001';
  END IF;

  v_summary  := public.checkout_cart_summary(NEW.items_snapshot);
  v_subtotal := (v_summary->>'subtotal')::numeric;
  v_store_id := (v_summary->>'store_id')::uuid;

  IF v_store_id IS DISTINCT FROM NEW.store_id THEN
    RAISE EXCEPTION 'The order items do not match this order''s store.'
      USING ERRCODE = 'P0001';
  END IF;

  -- NEW.customer_id (not auth.uid()) is the redemption identity: the
  -- PayMongo edge function inserts with the service role, where auth.uid()
  -- is NULL but the order still belongs to a real customer.
  v_verdict := public.voucher_evaluate(
    NEW.voucher_code, v_subtotal, NEW.store_id, NEW.customer_id, true
  );

  IF NOT (v_verdict->>'ok')::boolean THEN
    RAISE EXCEPTION '%', v_verdict->>'message' USING ERRCODE = 'P0001';
  END IF;

  v_discount := (v_verdict->>'discount_amount')::numeric;

  -- Server-authoritative money. Everything the caller sent for these
  -- columns is overwritten — that is the whole point.
  NEW.subtotal_amount := round(v_subtotal, 2);
  NEW.discount_amount := v_discount;
  NEW.voucher_code    := v_verdict->>'code';
  NEW.voucher_id      := (v_verdict->>'voucher_id')::uuid;
  NEW.total_amount    := round(v_subtotal + public.online_delivery_fee() - v_discount, 2);

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_orders_apply_voucher ON public.orders;
CREATE TRIGGER trg_orders_apply_voucher
  BEFORE INSERT ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.orders_apply_voucher();

-- Consumption: only runs for a row the BEFORE trigger accepted, so it
-- cannot fire for a rejected order, and it shares the order's
-- transaction (a failed order insert rolls the redemption back with it).
CREATE OR REPLACE FUNCTION public.orders_record_voucher_redemption()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_funded_by text;
BEGIN
  IF NEW.voucher_id IS NULL OR COALESCE(NEW.discount_amount, 0) <= 0 THEN
    RETURN NEW;
  END IF;

  SELECT funded_by INTO v_funded_by FROM public.vouchers WHERE id = NEW.voucher_id;

  INSERT INTO public.voucher_redemptions (
    voucher_id, code, customer_id, order_id, store_id, discount_amount, funded_by
  ) VALUES (
    NEW.voucher_id, NEW.voucher_code, NEW.customer_id, NEW.id, NEW.store_id,
    NEW.discount_amount, COALESCE(v_funded_by, 'store')
  )
  ON CONFLICT (voucher_id, order_id) DO NOTHING;

  UPDATE public.vouchers
     SET uses_count = uses_count + 1
   WHERE id = NEW.voucher_id;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_orders_record_voucher_redemption ON public.orders;
CREATE TRIGGER trg_orders_record_voucher_redemption
  AFTER INSERT ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.orders_record_voucher_redemption();

-- ────────────────────────────────────────────────────────────────
-- 4. Housekeeping RPC — expire a code early (seller/admin) so a promo
--    can be stopped without waiting for ends_at. Deactivation is the
--    supported alternative to deleting a voucher.
-- ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.deactivate_voucher(p_voucher_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.vouchers%ROWTYPE;
BEGIN
  SELECT * INTO v_row FROM public.vouchers WHERE id = p_voucher_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Voucher not found' USING ERRCODE = 'P0001';
  END IF;
  IF NOT (public.is_admin() OR EXISTS (
    SELECT 1 FROM public.stores s
     WHERE s.id = v_row.store_id AND s.owner_id = auth.uid()
  )) THEN
    RAISE EXCEPTION 'You are not allowed to change that voucher.'
      USING ERRCODE = '42501';
  END IF;

  UPDATE public.vouchers
     SET is_active = false,
         ends_at = LEAST(COALESCE(ends_at, now()), now())
   WHERE id = p_voucher_id;

  RETURN jsonb_build_object('ok', true, 'id', p_voucher_id, 'is_active', false);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.deactivate_voucher(uuid) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.deactivate_voucher(uuid) TO authenticated;

COMMENT ON FUNCTION public.deactivate_voucher(uuid) IS
  'Retires a voucher immediately (is_active=false + ends_at<=now()). Sellers may only retire their own store''s vouchers; admins may retire any.';

-- ────────────────────────────────────────────────────────────────
-- VERIFICATION QUERIES (run after applying)
-- ────────────────────────────────────────────────────────────────
-- -- Triggers exist
-- SELECT tgname FROM pg_trigger WHERE tgrelid = 'public.orders'::regclass
--   AND tgname LIKE '%voucher%';
-- -- A forged total is overwritten by the trigger:
-- --   insert an online order with voucher_code set + a wrong total_amount
-- --   → total_amount comes back as subtotal + 100 - discount.
-- SELECT has_function_privilege('authenticated',
--   'public.validate_voucher(text, jsonb)', 'EXECUTE');  -- expect true
