-- Migration: fix admin_delete_user for live NO ACTION orders_customer_id_fkey
-- Date: 2026-10-24
--
-- WHY: deleting a user who placed orders as a customer failed with
--   'update or delete on table "profiles" violates foreign key constraint
--   "orders_customer_id_fkey" on table "orders"'. The function assumed
--   orders.customer_id is ON DELETE CASCADE (base schema), but the live
--   database uses NO ACTION, so the profile delete aborts.
--
-- FIX: explicitly delete the target user's own orders (customer_id = target)
-- BEFORE deleting the profile. Their line items go with them via the
-- order_items -> orders CASCADE. Orders placed by OTHER customers at the
-- deleted seller's store are still preserved with store_id = NULL -- only
-- the deleted user's own orders are removed.

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

  -- Orders the target user placed as a customer. The live
  -- orders_customer_id_fkey is NO ACTION (not CASCADE as the base schema
  -- assumes), so these must go explicitly before the profile delete.
  -- Their order_items go with them via ON DELETE CASCADE on order_id.
  DELETE FROM public.orders
    WHERE customer_id = target_user_id;

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
   owned stores/products in FK-safe order. The user''s own customer orders
   are removed first (live orders_customer_id_fkey is NO ACTION); line items
   for the deleted products are removed next (live order_items.product_id is
   NOT NULL, so SET NULL cannot preserve them). Other customers'' order
   headers are kept with store_id = NULL. SECURITY DEFINER -- the is_admin()
   check runs inside the function since it writes across schemas.';
