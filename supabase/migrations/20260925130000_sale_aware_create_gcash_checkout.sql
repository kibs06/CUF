-- ══════════════════════════════════════════════════════════════════
-- Migration: create_gcash_checkout prices from the LIST price
-- Date: 2026-09-25
--
-- ⚠️ READ FIRST — this migration does NOT re-open the direct-GCash
-- route. `create_gcash_checkout` was deliberately closed on 2026-09-05
-- (`20260905000000_fix_t5_manual_gcash_dedupe_audit.sql` §5, "CLOSE THE
-- REMOTE ROUTE") because the attempt-#5 flow was deprecated in favour of
-- PayMongo Checkout Sessions, and the open creation entry point let any
-- authenticated user feed the seller's confirmation queue from
-- anywhere. It is expected to stay DENIED for `authenticated`, and this
-- file contains no GRANT — it only makes the function correct for the
-- day someone decides to revive it.
--
-- ── The bug ────────────────────────────────────────────────────────
-- The function reads `SELECT price ... FROM products` and used that
-- number for the line, the subtotal and the total. Since
-- `products.sale_price` shipped (`20260804000000`), that ignores an
-- active sale — while every surface a customer actually looks at prices
-- with the effective price:
--
--   • the Flutter app's cart  → lib/utils/sale_price.dart `effectivePrice`
--   • the customer portal     → customer-portal/src/lib/pricing.js, a port
--                               of the same file
--
-- So a pair advertised at ₱150 against a ₱390 list price would be
-- invoiced at ₱390 + ₱100 delivery, and `order_items.unit_price` would
-- record ₱390 as well — the record of what the customer agreed to pay
-- would be wrong too.
--
-- This is latent, not live: the route has been closed since
-- 2026-09-05, and no wired UI ever called it (the app's checkout uses
-- PayMongo). It is fixed here anyway because the function is left in the
-- database on purpose so legacy orders resolve, and a bug that only
-- appears when a route is revived is the worst kind to inherit.
--
-- ── The fix ────────────────────────────────────────────────────────
-- The app's own rule, transcribed — INCLUDING its boundaries, which
-- `sale_price.dart` `isOnSale` defines and `pricing.test.js` pins:
--   • the sale price must be non-null, positive and STRICTLY below the
--     list price;
--   • `sale_starts_at`, when set, is inclusive (`now.isBefore(start)` in
--     Dart means "at exactly start it IS on sale" → `start <= now()`);
--   • `sale_ends_at`, when set, is inclusive (`now.isAfter(end)` means
--     "at exactly end it is STILL on sale" → `end >= now()`).
-- Nothing else changes: item validation, size resolution, stock
-- reservation, the ₱100 fee and the 'pickup' fulfilment are untouched.
--
-- ── Still divergent, deliberately ──────────────────────────────────
-- `product_variants.additional_price` is added by both clients' carts
-- (`unitPrice = price + additionalPrice`) and not here, because
-- `p_items` carries no colour and two colours of one size can carry
-- different surcharges — there is no honest way to pick one. No variant
-- currently has `additional_price > 0` (checked against the deployed
-- database on 2026-09-25). Fixing it properly means adding a colour to
-- the checkout payload; the portal's reconciliation guard stops before
-- payment rather than overcharge in the meantime.
-- ══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.create_gcash_checkout(
  p_items            jsonb,   -- [{product_id, size, quantity}]
  p_delivery_address text,
  p_shipping_address jsonb
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_item            jsonb;
  v_product_uuid    uuid;
  v_cart_size       text;
  v_qty             int;
  v_price           numeric;
  v_list_price      numeric;
  v_sale_price      numeric;
  v_sale_start      timestamptz;
  v_sale_end        timestamptz;
  v_name            text;
  v_store_id        uuid;
  v_first_store     uuid := NULL;
  v_resolved_size   text;
  v_subtotal        numeric := 0;
  v_total           numeric;
  v_order_id        uuid;
  v_deadline        timestamptz;
  v_store_name      text;
  v_qr              text;
  v_number          text;
  v_account         text;
BEGIN
  IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'No items to order';
  END IF;

  -- Pass 1: validate items, pin prices (server-side, never client-trusted),
  -- resolve the exact inventory size for each line.
  CREATE TEMP TABLE _checkout_items (
    product_id uuid NOT NULL,
    size       text NOT NULL,
    quantity   int NOT NULL,
    unit_price numeric NOT NULL
  ) ON COMMIT DROP;

  FOR v_item IN SELECT value FROM jsonb_array_elements(p_items) LOOP
    v_qty := COALESCE((v_item->>'quantity')::int, 0);
    IF v_item->>'product_id' IS NULL OR v_qty <= 0 THEN
      RAISE EXCEPTION 'Each item needs a product_id and a quantity greater than zero';
    END IF;
    BEGIN
      v_product_uuid := (v_item->>'product_id')::uuid;
    EXCEPTION WHEN others THEN
      RAISE EXCEPTION 'Invalid product reference in cart';
    END;

    v_cart_size := COALESCE(v_item->>'size', '');

    SELECT price, sale_price, sale_starts_at, sale_ends_at, name, store_id
      INTO v_list_price, v_sale_price, v_sale_start, v_sale_end,
           v_name, v_store_id
      FROM public.products
     WHERE id = v_product_uuid;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'One of your items is no longer available. Please refresh your cart.';
    END IF;

    -- ── Effective price: `isOnSale` from lib/utils/sale_price.dart, in SQL.
    IF v_sale_price IS NOT NULL
       AND v_sale_price > 0
       AND v_sale_price < v_list_price
       AND (v_sale_start IS NULL OR v_sale_start <= now())
       AND (v_sale_end   IS NULL OR v_sale_end   >= now())
    THEN
      v_price := v_sale_price;
    ELSE
      v_price := v_list_price;
    END IF;

    IF v_first_store IS NULL THEN v_first_store := v_store_id; END IF;
    v_subtotal := v_subtotal + (v_price * v_qty);

    -- Resolve size exactly like the app (normalized match first; a
    -- sizeless item falls back to any in-stock row).
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

    INSERT INTO _checkout_items (product_id, size, quantity, unit_price)
    VALUES (v_product_uuid, v_resolved_size, v_qty, v_price);
  END LOOP;

  IF v_subtotal <= 0 THEN
    RAISE EXCEPTION 'Order total must be greater than zero';
  END IF;
  v_total := v_subtotal + 100;   -- fixed ₱100 delivery fee, matches the app

  -- Pass 2: create the order (the one-open-order partial unique index
  -- rejects a second concurrent checkout → friendly error).
  BEGIN
    INSERT INTO public.orders (
      customer_id, store_id, status, fulfillment, total_amount,
      payment_method, payment_status, notes, shipping_address, source,
      payment_confirmation_deadline
    ) VALUES (
      auth.uid(), v_first_store, 'awaiting_payment_confirmation', 'pickup',
      v_total, 'gcash', 'pending', p_delivery_address, p_shipping_address,
      'online', now() + interval '30 minutes'
    )
    RETURNING id, payment_confirmation_deadline INTO v_order_id, v_deadline;
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'You already have a GCash checkout awaiting confirmation. Complete or cancel it first.';
  END;

  -- Insert line items → decrement_inventory_on_order fires per row.
  -- Insufficient stock raises P0001 → the WHOLE transaction (order + all
  -- items) rolls back, so no orphaned order and no partial reservation.
  INSERT INTO public.order_items (order_id, product_id, size, quantity, unit_price)
  SELECT v_order_id, product_id, size, quantity, unit_price
    FROM _checkout_items;

  INSERT INTO public.order_payment_events (order_id, event_type, actor_id, notes)
  VALUES (v_order_id, 'created', auth.uid(),
          'Order created, stock reserved, awaiting seller confirmation');

  SELECT name, gcash_qr_url, gcash_number, gcash_account_name
    INTO v_store_name, v_qr, v_number, v_account
    FROM public.stores
   WHERE id = v_first_store;

  RETURN jsonb_build_object(
    'order_id', v_order_id,
    'store_id', v_first_store,
    'total_amount', v_total,
    'payment_confirmation_deadline', v_deadline,
    'store_name', v_store_name,
    'gcash_qr_url', v_qr,
    'gcash_number', v_number,
    'gcash_account_name', v_account
  );
END;
$$;

-- Note: NO GRANT and NO REVOKE here. The ACLs are whatever
-- `20260905000000` (revoked from `authenticated`) and
-- `20260925120000_revoke_anon_on_deprecated_gcash_rpcs.sql` (revoked from
-- `anon`) left in place — i.e. this statement changes the function's
-- BODY only, and the route stays closed.

-- ══════════════════════════════════════════════════════════════════
-- VERIFICATION (run after applying — as an owner/service role, since
-- the function is not reachable by any client role)
-- ══════════════════════════════════════════════════════════════════
-- 1. Grants are unchanged (expect anon_may = false, auth_may = false):
--
--    SELECT has_function_privilege('anon',
--             'public.create_gcash_checkout(jsonb, text, jsonb)', 'EXECUTE') AS anon_may,
--           has_function_privilege('authenticated',
--             'public.create_gcash_checkout(jsonb, text, jsonb)', 'EXECUTE') AS auth_may;
--
-- 2. A sale item is invoiced at its sale price. Roll the order back —
--    the function reserves stock, so this MUST NOT be committed:
--
--    BEGIN;
--      -- pick a product with a live sale, e.g.
--      --   SELECT id, price, sale_price FROM products
--      --    WHERE sale_price IS NOT NULL AND sale_price < price LIMIT 1;
--      SELECT public.create_gcash_checkout(
--               '[{"product_id": "5d2dadf8-680d-4d6a-b16e-153eeaf622d4",
--                  "size": "EU 39", "quantity": 1}]'::jsonb,
--               'verification only', '{}'::jsonb) ->> 'total_amount';
--      -- expect sale_price + 100 (100 + 100 = 200), not price + 100 (250)
--    ROLLBACK;
--
-- 3. The boundary rule, in SQL, against the same product row:
--
--    SELECT id, price, sale_price,
--           CASE WHEN sale_price IS NOT NULL AND sale_price > 0
--                 AND sale_price < price
--                 AND (sale_starts_at IS NULL OR sale_starts_at <= now())
--                 AND (sale_ends_at   IS NULL OR sale_ends_at   >= now())
--                THEN sale_price ELSE price END AS effective
--      FROM products WHERE sale_price IS NOT NULL;
-- ══════════════════════════════════════════════════════════════════
