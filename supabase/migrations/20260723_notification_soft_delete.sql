-- ══════════════════════════════════════════════════════════════════
-- Notification Soft-Delete Support
-- Date: 2026-07-23
-- Adds is_deleted column to both notification tables for swipe-to-delete
-- with undo support (soft-delete pattern).
-- ══════════════════════════════════════════════════════════════════

-- ─── 1. Add is_deleted to customer notifications ───────────────
ALTER TABLE public.notifications
  ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN NOT NULL DEFAULT false;

-- ─── 2. Add is_deleted to seller notifications ─────────────────
ALTER TABLE public.seller_notifications
  ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN NOT NULL DEFAULT false;

-- ─── 3. Update RLS policies to exclude soft-deleted rows ───────
-- Drop existing policies and recreate with is_deleted filter

-- Customer notifications: SELECT policy
DROP POLICY IF EXISTS "Users can view their own notifications" ON public.notifications;
CREATE POLICY "Users can view their own notifications"
  ON public.notifications FOR SELECT
  USING (auth.uid() = user_id AND is_deleted = false);

-- Customer notifications: UPDATE policy (for mark-as-read/unread)
DROP POLICY IF EXISTS "Users can update their own notifications" ON public.notifications;
CREATE POLICY "Users can update their own notifications"
  ON public.notifications FOR UPDATE
  USING (auth.uid() = user_id);

-- Seller notifications: SELECT policy
DROP POLICY IF EXISTS "Sellers can view their store notifications" ON public.seller_notifications;
CREATE POLICY "Sellers can view their store notifications"
  ON public.seller_notifications FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.stores
      WHERE stores.id = seller_notifications.store_id
        AND stores.owner_id = auth.uid()
    )
    AND is_deleted = false
  );

-- Seller notifications: UPDATE policy (for mark-as-read/unread)
DROP POLICY IF EXISTS "Sellers can update their store notifications" ON public.seller_notifications;
CREATE POLICY "Sellers can update their store notifications"
  ON public.seller_notifications FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.stores
      WHERE stores.id = seller_notifications.store_id
        AND stores.owner_id = auth.uid()
    )
  );
