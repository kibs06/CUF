-- ══════════════════════════════════════════════════════════════════
-- Migration: Seller approval notification
-- Date: 2026-08-16
--
-- WHY THIS CHANGE:
--   Admin approval (seller_approval_screen → approveSellerApplication)
--   only flipped profiles.seller_status/role — the seller was never told.
--   This adds a Postgres trigger that writes a `notifications` row the
--   moment an application is approved, following the exact pattern the
--   order triggers already use (20260702_notifications.sql). The app's
--   NotificationProvider realtime subscription picks the row up live
--   (badge + notifications feed), so no client code is needed to receive
--   it. (A true FCM push while the app is closed is a separate edge
--   function — not included here.)
--
--   Note: this intentionally uses the user-scoped `notifications` table,
--   NOT `seller_notifications` — that table is keyed by store_id, and a
--   newly approved seller has no store yet (it's created post-approval).
-- ══════════════════════════════════════════════════════════════════

-- 1. Add the 'approval' category to the existing enum
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_enum
    WHERE enumlabel = 'approval'
      AND enumtypid = 'public.notification_category'::regtype
  ) THEN
    ALTER TYPE public.notification_category ADD VALUE 'approval';
  END IF;
END
$$;

-- 2. Trigger function: notify the seller on approval
CREATE OR REPLACE FUNCTION public.notify_on_seller_approved()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.notifications (user_id, category, title, message)
  VALUES (
    new.id,
    'approval',
    'You''re approved!',
    'Your CUFMAI seller application was approved — your seller dashboard is ready.'
  );
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. Trigger: fire when seller_status transitions to 'approved'
DROP TRIGGER IF EXISTS trg_notify_on_seller_approved ON public.profiles;
CREATE TRIGGER trg_notify_on_seller_approved
  AFTER UPDATE OF seller_status ON public.profiles
  FOR EACH ROW
  WHEN (
    old.seller_status IS DISTINCT FROM new.seller_status
    AND new.seller_status = 'approved'
  )
  EXECUTE FUNCTION public.notify_on_seller_approved();

-- ══════════════════════════════════════════════════════════════════
-- VERIFICATION QUERIES (run after applying)
-- ══════════════════════════════════════════════════════════════════
-- -- Category added:
-- SELECT enumlabel FROM pg_enum
--   WHERE enumtypid = 'public.notification_category'::regtype;
--
-- -- Trigger exists:
-- SELECT tgname FROM pg_trigger WHERE tgname = 'trg_notify_on_seller_approved';
