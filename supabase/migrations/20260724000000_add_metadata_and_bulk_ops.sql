-- ══════════════════════════════════════════════════════════════════
-- Migration: Add metadata to seller_notifications + DELETE RLS policies
-- Date: July 24, 2026
-- Purpose:
--   1. Add metadata JSONB column to seller_notifications (for message
--      batching previews, matching the customer notifications schema).
--   2. Add DELETE RLS policies to both tables so authenticated users
--      can hard-delete rows when selection-mode bulk-delete is invoked
--      via the service layer (the app uses soft-delete via UPDATE
--      is_deleted, but DELETE policies are needed as a safety net and
--      for any future hard-delete cleanup jobs).
-- ══════════════════════════════════════════════════════════════════

-- ─── 1. Add metadata JSONB to seller_notifications ─────────────
ALTER TABLE public.seller_notifications
  ADD COLUMN IF NOT EXISTS metadata JSONB DEFAULT NULL;

-- ─── 2. DELETE RLS policies ────────────────────────────────────
-- Customer notifications: users can delete their own rows
DROP POLICY IF EXISTS "Users can delete own notifications" ON public.notifications;
CREATE POLICY "Users can delete own notifications"
  ON public.notifications FOR DELETE
  USING (auth.uid() = user_id);

-- Seller notifications: store owners can delete their store's rows
DROP POLICY IF EXISTS "Sellers can delete their store notifications" ON public.seller_notifications;
CREATE POLICY "Sellers can delete their store notifications"
  ON public.seller_notifications FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM public.stores
      WHERE stores.id = seller_notifications.store_id
        AND stores.owner_id = auth.uid()
    )
  );
