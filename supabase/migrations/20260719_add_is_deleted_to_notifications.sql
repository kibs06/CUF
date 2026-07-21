-- ══════════════════════════════════════════════════════════════════
-- Soft-delete support for notification swipe-to-delete
-- Date: 2026-07-19
-- Adds is_deleted column to both notification tables so deleted
-- items disappear from feeds but can be restored via Undo.
-- ══════════════════════════════════════════════════════════════════

-- 1. Add is_deleted to customer notifications
ALTER TABLE public.notifications
  ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS idx_notifications_not_deleted
  ON public.notifications(user_id, is_deleted)
  WHERE is_deleted = false;

-- 2. Add is_deleted to seller notifications
ALTER TABLE public.seller_notifications
  ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS idx_seller_notifications_not_deleted
  ON public.seller_notifications(store_id, is_deleted)
  WHERE is_deleted = false;
