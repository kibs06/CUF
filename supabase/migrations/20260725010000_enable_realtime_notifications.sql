-- ══════════════════════════════════════════════════════════════════
-- Enable Realtime for notification tables
-- Date: July 25, 2026
-- Purpose:
--   The Flutter app uses .stream() (Supabase Realtime) on both the
--   notifications and seller_notifications tables. Without adding
--   these tables to the supabase_realtime publication, the client
--   receives: "Unable to subscribe to changes with given parameters"
-- ══════════════════════════════════════════════════════════════════

-- 1. Customer notifications — add to Realtime publication (if not already)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'notifications'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications;
  END IF;
END
$$;

-- 2. Seller notifications — add to Realtime publication (if not already)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'seller_notifications'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.seller_notifications;
  END IF;
END
$$;
