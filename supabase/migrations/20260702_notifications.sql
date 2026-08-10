-- ══════════════════════════════════════════════════════════════════
-- Notifications Feature — SQL Migration
-- Generated: July 2, 2026
-- Creates the notifications table, RLS policies, and triggers
-- that auto-generate notifications on order status changes.
-- ══════════════════════════════════════════════════════════════════

-- 1. ENUM TYPE
-- ══════════════════════════════════════════════════════════════════
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'notification_category') THEN
    CREATE TYPE notification_category AS ENUM (
      'unpaid', 'processing', 'shipped', 'review', 'returns'
    );
  END IF;
END
$$;

-- 2. NOTIFICATIONS TABLE
-- ══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.notifications (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  order_id    UUID REFERENCES public.orders(id) ON DELETE CASCADE,
  category    notification_category NOT NULL,
  title       TEXT NOT NULL,
  message     TEXT NOT NULL,
  order_type  TEXT NOT NULL DEFAULT 'catalog',  -- 'catalog' or 'custom'
  is_read     BOOLEAN NOT NULL DEFAULT false,
  created_at  TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Indexes for fast lookups
CREATE INDEX IF NOT EXISTS idx_notifications_user
  ON public.notifications(user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_notifications_user_unread
  ON public.notifications(user_id, category)
  WHERE is_read = false;

-- Add order_type column if it doesn't exist (some live DBs may be missing it)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'notifications' AND column_name = 'order_type'
  ) THEN
    ALTER TABLE public.notifications ADD COLUMN order_type TEXT NOT NULL DEFAULT 'catalog';
  END IF;
END
$$;

CREATE INDEX IF NOT EXISTS idx_notifications_user_order_type
  ON public.notifications(user_id, order_type, created_at DESC);

-- 3. ROW LEVEL SECURITY
-- ══════════════════════════════════════════════════════════════════
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

-- Users can view their own notifications
DROP POLICY IF EXISTS "Users can view own notifications" ON public.notifications;
CREATE POLICY "Users can view own notifications"
  ON public.notifications FOR SELECT
  USING (auth.uid() = user_id);

-- Users can mark their own notifications as read
DROP POLICY IF EXISTS "Users can update own notifications" ON public.notifications;
CREATE POLICY "Users can update own notifications"
  ON public.notifications FOR UPDATE
  USING (auth.uid() = user_id);

-- 4. TRIGGER FUNCTION: Generate notification on order status change
-- ══════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.notify_on_order_status_change()
RETURNS trigger AS $$
DECLARE
  v_category notification_category;
  v_title text;
  v_message text;
  v_order_short text;
BEGIN
  -- Short ID for display (last 8 chars)
  v_order_short := '#' || substring(new.id::text, length(new.id::text) - 7);

  -- Map order status → notification category
  -- Actual statuses: pending, placed, preparing, ready, received, cancelled
  CASE new.status
    WHEN 'pending' THEN
      v_category := 'unpaid';
      v_title := 'Payment pending';
      v_message := 'Order ' || v_order_short || ' is awaiting payment.';
    WHEN 'placed' THEN
      v_category := 'unpaid';
      v_title := 'Order placed';
      v_message := 'Order ' || v_order_short || ' has been placed successfully.';
    WHEN 'preparing' THEN
      v_category := 'processing';
      v_title := 'Order is processing';
      v_message := 'Order ' || v_order_short || ' is being prepared by the artisan.';
    WHEN 'ready' THEN
      v_category := 'shipped';
      v_title := 'Order ready';
      v_message := 'Order ' || v_order_short || ' is ready for pickup.';
    WHEN 'received' THEN
      v_category := 'review';
      v_title := 'Leave a review';
      v_message := 'How was order ' || v_order_short || '? Share your feedback.';
    ELSE
      -- cancelled or unmapped statuses → no notification
      RETURN new;
  END CASE;

  INSERT INTO public.notifications (user_id, order_id, category, title, message)
  VALUES (new.customer_id, new.id, v_category, v_title, v_message);

  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger: fire on order status change
DROP TRIGGER IF EXISTS trg_notify_on_order_status_change ON public.orders;
CREATE TRIGGER trg_notify_on_order_status_change
  AFTER UPDATE OF status ON public.orders
  FOR EACH ROW
  WHEN (old.status IS DISTINCT FROM new.status)
  EXECUTE FUNCTION public.notify_on_order_status_change();

-- 5. TRIGGER FUNCTION: Generate notification on new order creation
-- ══════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.notify_on_order_insert()
RETURNS trigger AS $$
DECLARE
  v_order_short text;
BEGIN
  v_order_short := '#' || substring(new.id::text, length(new.id::text) - 7);

  -- Only notify for pending/new orders
  IF new.status = 'pending' THEN
    INSERT INTO public.notifications (user_id, order_id, category, title, message)
    VALUES (
      new.customer_id,
      new.id,
      'unpaid',
      'Payment pending',
      'Order ' || v_order_short || ' is awaiting payment.'
    );
  END IF;

  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger: fire on order insert
DROP TRIGGER IF EXISTS trg_notify_on_order_insert ON public.orders;
CREATE TRIGGER trg_notify_on_order_insert
  AFTER INSERT ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_on_order_insert();

-- 6. SEED: Update schema.sql reference
-- ══════════════════════════════════════════════════════════════════
-- Run this migration in Supabase SQL Editor to activate notifications.
