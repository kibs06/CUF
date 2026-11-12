-- ══════════════════════════════════════════════════════════════════
-- Inventory reconciliation for approved return replacements
-- Date: 2026-11-12
--
-- Approving a return used to move no stock at all: the customer hands a
-- pair back and the store hands a replacement out, and `inventory` kept
-- the number it had after the original sale. This adds the missing half
-- as one SECURITY DEFINER RPC, for the same reason the rest of the stock
-- truth lives in functions (see 20260711_fix_trigger_security_definer):
-- arithmetic on `stock` read-modify-written from the seller's client
-- races with the sale and purchase triggers, and swallows the
-- `CHECK (stock >= 0)` rule.
--
-- What it does, per `order_items` line of the order:
--   1. the returned pair goes back on the shelf  (stock + quantity)
--   2. the replacement unit comes off it         (stock - quantity)
--
-- For a like-for-like swap (same product and size, which is all the
-- order rows can express) the two cancel to zero, and that is correct:
-- the sale already took the pair out of stock, the customer brings one
-- back and takes one away. The reconciliation matters when the pair is
-- worn enough that the store does not put it back — see the open item
-- at the foot of this file.
--
-- Ported from the exact matching rules the sale trigger uses: sizes are
-- compared on their digits only ('Size 9' and '9' are the same row), and
-- the decrement is guarded by `stock >= quantity` so it can never push
-- stock negative.
--
-- Idempotent by construction: `orders.replacement_inventory_at` stamps
-- the one time the reconciliation ran, so a retried approval cannot move
-- stock twice.
-- ══════════════════════════════════════════════════════════════════

-- ── 1. One-shot marker ─────────────────────────────────────────────
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS replacement_inventory_at TIMESTAMPTZ;

COMMENT ON COLUMN public.orders.replacement_inventory_at IS
  'When stock was reconciled for an approved replacement (returned pair back in, replacement unit out). NULL = not applied yet; also the idempotency guard for apply_return_replacement_inventory().';

-- ── 2. RPC ─────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.apply_return_replacement_inventory(
  p_order_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order     public.orders%ROWTYPE;
  v_item      RECORD;
  v_restocked integer := 0;
  v_issued    integer := 0;
  v_skipped   integer := 0;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated'
      USING ERRCODE = '42501';
  END IF;

  -- Row lock: serializes this against a double-tapped approval and
  -- against any concurrent stock change on the same order.
  SELECT * INTO v_order
    FROM public.orders
   WHERE id = p_order_id
     FOR UPDATE;

  -- One message for "no such order" and "not your store", so the
  -- function cannot be used to probe order ids.
  IF v_order.id IS NULL
     OR NOT (public.is_admin() OR EXISTS (
               SELECT 1 FROM public.stores s
                WHERE s.id = v_order.store_id
                  AND s.owner_id = auth.uid()
             ))
  THEN
    RAISE EXCEPTION 'Order not found'
      USING ERRCODE = '42501';
  END IF;

  IF v_order.status <> 'replaced' THEN
    RAISE EXCEPTION
      'Stock is only reconciled once the replacement is approved.'
      USING ERRCODE = 'P0001';
  END IF;

  -- Retried approval (network blip, double tap): nothing left to move.
  IF v_order.replacement_inventory_at IS NOT NULL THEN
    RETURN jsonb_build_object(
      'applied', false,
      'reason',  'already_applied',
      'restocked', 0,
      'issued',    0,
      'skipped',   0
    );
  END IF;

  FOR v_item IN
    SELECT product_id, size, quantity
      FROM public.order_items
     WHERE order_id = p_order_id
  LOOP
    -- Product deleted since the sale: `inventory` rows cascade away with
    -- it, so recreating one would violate the FK. Nothing to hold stock
    -- for — count the units and move on.
    PERFORM 1 FROM public.products WHERE id = v_item.product_id;
    IF NOT FOUND THEN
      v_skipped := v_skipped + v_item.quantity;
      CONTINUE;
    END IF;

    -- (1) Returned pair back on the shelf.
    UPDATE public.inventory
       SET stock = stock + v_item.quantity,
           updated_at = now()
     WHERE product_id = v_item.product_id
       AND regexp_replace(size, '\D', '', 'g')
         = regexp_replace(v_item.size, '\D', '', 'g');

    -- Row deleted while the order was in flight: recreate it so the
    -- returned units are never lost (same guard the reservation release
    -- uses), at the size the customer actually bought.
    IF NOT FOUND THEN
      INSERT INTO public.inventory (product_id, size, stock)
      VALUES (v_item.product_id, v_item.size, v_item.quantity)
      ON CONFLICT (product_id, size) DO UPDATE
        SET stock = public.inventory.stock + EXCLUDED.stock,
            updated_at = now();
    END IF;
    v_restocked := v_restocked + v_item.quantity;

    -- (2) Replacement unit off the shelf. After (1) the row holds at
    -- least `quantity`, so this is expected to succeed; the guard is the
    -- same one the sale trigger uses, and a miss is counted rather than
    -- raised — the replacement is already promised to the customer and
    -- an exception here would roll the whole decision back.
    UPDATE public.inventory
       SET stock = stock - v_item.quantity,
           updated_at = now()
     WHERE product_id = v_item.product_id
       AND regexp_replace(size, '\D', '', 'g')
         = regexp_replace(v_item.size, '\D', '', 'g')
       AND stock >= v_item.quantity;

    IF FOUND THEN
      v_issued := v_issued + v_item.quantity;
    ELSE
      v_skipped := v_skipped + v_item.quantity;
    END IF;
  END LOOP;

  UPDATE public.orders
     SET replacement_inventory_at = now()
   WHERE id = p_order_id;

  RETURN jsonb_build_object(
    'applied',   true,
    'restocked', v_restocked,
    'issued',    v_issued,
    'skipped',   v_skipped
  );
END;
$$;

-- `REVOKE ... FROM PUBLIC` alone is not enough in this project: Supabase's
-- ALTER DEFAULT PRIVILEGES grants EXECUTE to `anon` by name.
REVOKE EXECUTE ON FUNCTION public.apply_return_replacement_inventory(uuid)
  FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.apply_return_replacement_inventory(uuid)
  TO authenticated;

COMMENT ON FUNCTION public.apply_return_replacement_inventory(uuid) IS
  'Reconciles inventory for an approved replacement: returned pair back in (+qty), replacement unit out (-qty) per order line. Own-store seller or admin only, order must be `replaced`, runs at most once (orders.replacement_inventory_at).';

-- ══════════════════════════════════════════════════════════════════
-- VERIFICATION (run after applying)
-- ══════════════════════════════════════════════════════════════════
-- 1. Grants — anon must be false, authenticated true:
--
--    SELECT has_function_privilege('anon',
--             'public.apply_return_replacement_inventory(uuid)', 'EXECUTE') AS anon_may,
--           has_function_privilege('authenticated',
--             'public.apply_return_replacement_inventory(uuid)', 'EXECUTE') AS auth_may;
--
-- 2. Happy path — on a 'replaced' order of your own store, in a
--    transaction you can throw away. Stock must be UNCHANGED before and
--    after for a like-for-like line, and the second call must report
--    applied=false:
--
--    BEGIN;
--      SELECT stock FROM public.inventory
--       WHERE product_id = (SELECT product_id FROM public.order_items
--                            WHERE order_id = '<order id>' LIMIT 1);
--      SELECT public.apply_return_replacement_inventory('<order id>');
--      SELECT public.apply_return_replacement_inventory('<order id>');
--      SELECT stock FROM public.inventory
--       WHERE product_id = (SELECT product_id FROM public.order_items
--                            WHERE order_id = '<order id>' LIMIT 1);
--      ROLLBACK;
--
-- 3. A non-'replaced' order must be rejected (expect P0001):
--
--    SELECT public.apply_return_replacement_inventory('<received order id>');
--
-- ══════════════════════════════════════════════════════════════════
-- OPEN ITEM — worn returns still count as sellable
-- ══════════════════════════════════════════════════════════════════
-- The in-store path inspects the pair before the swap, and a pair that
-- is worn or missing its tags is not sellable — but nothing on the order
-- records that verdict, so this function always puts it back. For a
-- like-for-like line the restock and the replacement cancel out, so the
-- number is right today; the moment the app records a per-item
-- "resellable" verdict at approval, step (1) should be skipped when the
-- verdict is false, and the pair should come off stock instead of on.
-- ══════════════════════════════════════════════════════════════════
