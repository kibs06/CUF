-- ══════════════════════════════════════════════════════════════════
-- Migration: Admin — permanently delete a user account
-- Date: 2026-08-17
--
-- WHY THIS CHANGE:
--   The admin Users Directory can reset roles or mark accounts
--   suspended, but there is no way to remove an account permanently
--   (e.g. spam / abusive accounts). Deleting a profile row directly
--   fails because several tables reference profiles/stores/products
--   WITHOUT ON DELETE CASCADE, and the auth.users row must be removed
--   too so the account can never sign in again.
--
--   This adds a single SECURITY DEFINER RPC, admin_delete_user(user_id),
--   callable only by an admin (is_admin() check inside the function —
--   RLS cannot be relied on because the function writes across schemas
--   incl. auth.users). It deletes in FK-safe order:
--
--     1. rows that block the profile delete (sales_transactions,
--        gcash_payment_proofs.submitted_by RESTRICT, order_payment_events,
--        payment_fee_config singleton)
--     2. the user's stores' products (store_id refs block store delete)
--     3. the user's stores (owner_id refs block profile delete)
--     4. orders whose store vanished (store_id has no cascade) → NULL out
--     5. the profile row itself (cascades to notifications, reviews,
--        messages, follows, addresses, etc. that DO cascade)
--     6. the auth.users row (cascades the profile via profiles.id FK)
--
--   Deliberately does NOT cascade-delete customers' orders placed at the
--   deleted seller's store: order rows are preserved with store_id set to
--   NULL so order history stays intact. Only the seller's own rows are
--   removed.
-- ══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.admin_delete_user(target_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_store_ids uuid[];
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

  -- payment_fee_config is a singleton row (id = 1) — just detach it.
  UPDATE public.payment_fee_config
    SET updated_by = NULL
    WHERE updated_by = target_user_id;

  -- 2. Stores owned by this user.
  SELECT array_agg(id) INTO v_store_ids
    FROM public.stores
    WHERE owner_id = target_user_id;

  IF v_store_ids IS NOT NULL THEN
    -- Products block the store delete (products.store_id has no cascade).
    -- order_items.product_id is ON DELETE SET NULL so order history
    -- survives product removal.
    DELETE FROM public.products
      WHERE store_id = ANY (v_store_ids)
         OR seller_id = target_user_id;

    -- Orders reference stores WITHOUT cascade; keep the customer's order
    -- history and just detach the deleted store.
    UPDATE public.orders
      SET store_id = NULL
      WHERE store_id = ANY (v_store_ids);

    -- Customization requests reference the store without cascade — detach.
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

  -- 5. The auth account — the profile id FK cascades from auth.users, but
  --    we delete explicitly anyway (idempotent) so the account can never
  --    sign in again.
  DELETE FROM auth.users
    WHERE id = target_user_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_delete_user(uuid) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.admin_delete_user(uuid) TO authenticated;

COMMENT ON FUNCTION public.admin_delete_user(uuid) IS
  'Admin-only: permanently deletes a user (profile + auth account) and their
   owned stores/products in FK-safe order. Customer orders placed at a deleted
   store are preserved with store_id = NULL. SECURITY DEFINER — the is_admin()
   check runs inside the function since it writes across schemas.';

-- ══════════════════════════════════════════════════════════════════
-- VERIFICATION QUERIES (run after applying)
-- ══════════════════════════════════════════════════════════════════
-- -- Function exists + owner:
-- SELECT proname, prosecdef FROM pg_proc
--   WHERE proname = 'admin_delete_user';
--
-- -- Executable by authenticated (the admin client role):
-- SELECT has_function_privilege('authenticated', 'public.admin_delete_user(uuid)', 'EXECUTE');
