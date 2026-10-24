-- Migration: fix admin_delete_user for live NOT NULL order_items.product_id
-- Date: 2026-10-24
--
-- WHY: deleting a seller with products that appear in order_items failed with
--   "null value in column product_id of relation order_items violates
--   not-null constraint". The function assumed order_items.product_id is
--   nullable ON DELETE SET NULL (base schema), but the live database enforces
--   product_id NOT NULL, so the FK's SET NULL action fires into the NOT NULL
--   wall and the whole delete aborts.
--
-- FIX: explicitly delete the line-item rows that reference the doomed
-- products BEFORE deleting the products (same for sales_transaction_items,
-- which shares the SET NULL assumption). Order headers are still preserved
-- with store_id = NULL; only the line items for the deleted seller's
-- products are removed (their product is gone, so the row cannot survive
-- with a NOT NULL product_id). CASCADE tables (reviews, cart, inventory,
-- variants, images, reservations) need no handling.
--
-- SAFE ON BOTH SCHEMAS: explicit child deletes work whether the live column
-- is nullable or not, and whether the FK is SET NULL or NO ACTION.

CREATE OR REPLACE FUNCTION public.admin_delete_user(target_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_store_ids uuid[];
  v_product_ids uuid[];
BEGIN
  -- Only admins may permanently delete accounts.
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Only admins can delete accounts';
  END IF;

  IF target_user_id IS NULL THEN
    RAISE EXCEPTION 'target_user_id is required';
  END IF;

  -- 1. Rows that block the profile delete (no cascade / RESTRICT).
  DELETE FROM public.sales_transactions
    WHERE seller_id = target_user_id;
  DELETE FROM public.gcash_payment_proofs
    WHERE submitted_by = target_user_id;
  DELETE FROM public.order_payment_events
    WHERE actor_id = target_user_id;

  -- payment_fee_config is a singleton row (id = 1) -- just detach it.
  UPDATE public.payment_fee_config
    SET updated_by = NULL
    WHERE updated_by = target_user_id;

  -- 2. Stores owned by this user.
  SELECT array_agg(id) INTO v_store_ids
    FROM public.stores
    WHERE owner_id = target_user_id;

  -- Collect every product row about to be deleted (store-owned + direct).
  SELECT array_agg(id) INTO v_product_ids
    FROM public.products
    WHERE seller_id = target_user_id
       OR (v_store_ids IS NOT NULL AND store_id = ANY (v_store_ids));

  IF v_product_ids IS NOT NULL THEN
    -- Line items reference products WITHOUT a survivable SET NULL on the
    -- live DB (product_id is NOT NULL): remove them first so the product
    -- delete below cannot fail. order_item_reviews cascade from both
    -- order_items and products, so they are cleaned up automatically.
    DELETE FROM public.order_items
      WHERE product_id = ANY (v_product_ids);
    DELETE FROM public.sales_transaction_items
      WHERE product_id = ANY (v_product_ids);

    -- Customization drafts point at a base product (nullable): detach so
    -- the request survives without its template.
    UPDATE public.customization_requests
      SET base_product_id = NULL
      WHERE base_product_id = ANY (v_product_ids);
  END IF;

  IF v_store_ids IS NOT NULL THEN
    -- Products block the store delete (products.store_id has no cascade).
    DELETE FROM public.products
      WHERE store_id = ANY (v_store_ids)
         OR seller_id = target_user_id;

    -- Orders reference stores WITHOUT cascade; keep the customer's order
    -- history and just detach the deleted store.
    UPDATE public.orders
      SET store_id = NULL
      WHERE store_id = ANY (v_store_ids);

    -- Customization requests reference the store without cascade -- detach.
    UPDATE public.customization_requests
      SET store_id = NULL
      WHERE store_id = ANY (v_store_ids);

    DELETE FROM public.stores
      WHERE id = ANY (v_store_ids);
  END IF;

  -- 3. Products owned directly (seller without a store row edge case).
  DELETE FROM public.products
    WHERE seller_id = target_user_id;

  -- 4. The profile row (cascades notifications/reviews/follows/messages/
  --    cart/foot measurements/customer addresses, etc.).
  DELETE FROM public.profiles
    WHERE id = target_user_id;

  -- 5. The auth account -- the profile id FK cascades from auth.users, but
  --    we delete explicitly anyway (idempotent) so the account can never
  --    sign in again.
  DELETE FROM auth.users
    WHERE id = target_user_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_delete_user(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_delete_user(uuid) TO authenticated;

COMMENT ON FUNCTION public.admin_delete_user(uuid) IS
  'Admin-only: permanently deletes a user (profile + auth account) and their
   owned stores/products in FK-safe order. Line items for the deleted
   products are removed first (live order_items.product_id is NOT NULL, so
   SET NULL cannot preserve them); order headers are kept with
   store_id = NULL. SECURITY DEFINER -- the is_admin() check runs inside
   the function since it writes across schemas.';
