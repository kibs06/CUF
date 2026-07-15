-- ══════════════════════════════════════════════════════════════════
-- Migration: Push Notifications for Messages
-- Date: July 14, 2026
-- Purpose: Add device_tokens table, 'message' notification type,
--          metadata column, and DB trigger for new message notifications
-- ══════════════════════════════════════════════════════════════════

-- 1. Add 'message' to the notification_category enum
--    (PostgreSQL doesn't support ADD VALUE IF NOT EXISTS, so we check first)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_enum e
        JOIN pg_type t ON e.enumtypid = t.oid
        WHERE t.typname = 'notification_category' AND e.enumlabel = 'message'
    ) THEN
        ALTER TYPE public.notification_category ADD VALUE 'message';
    END IF;
END $$;

-- 2. Add metadata JSONB column to notifications table
--    (for conversationId, storeName, senderId, etc.)
ALTER TABLE public.notifications
ADD COLUMN IF NOT EXISTS metadata jsonb DEFAULT NULL;

-- 3. Create device_tokens table for FCM token storage
CREATE TABLE IF NOT EXISTS public.device_tokens (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    fcm_token text NOT NULL,
    platform text NOT NULL CHECK (platform IN ('ios', 'android')),
    updated_at timestamptz DEFAULT now(),
    UNIQUE(customer_id, fcm_token)
);

-- 4. RLS policies for device_tokens
ALTER TABLE public.device_tokens ENABLE ROW LEVEL SECURITY;

-- Customers can read their own tokens
DROP POLICY IF EXISTS "Customers can read own device tokens" ON public.device_tokens;
CREATE POLICY "Customers can read own device tokens"
    ON public.device_tokens FOR SELECT
    USING (auth.uid() = customer_id);

-- Customers can insert their own tokens
DROP POLICY IF EXISTS "Customers can insert own device tokens" ON public.device_tokens;
CREATE POLICY "Customers can insert own device tokens"
    ON public.device_tokens FOR INSERT
    WITH CHECK (auth.uid() = customer_id);

-- Customers can update their own tokens
DROP POLICY IF EXISTS "Customers can update own device tokens" ON public.device_tokens;
CREATE POLICY "Customers can update own device tokens"
    ON public.device_tokens FOR UPDATE
    USING (auth.uid() = customer_id);

-- Customers can delete their own tokens
DROP POLICY IF EXISTS "Customers can delete own device tokens" ON public.device_tokens;
CREATE POLICY "Customers can delete own device tokens"
    ON public.device_tokens FOR DELETE
    USING (auth.uid() = customer_id);

-- 5. Add INSERT policy for notifications table
--    (allows authenticated users to create notifications)
DROP POLICY IF EXISTS "Authenticated users can insert notifications" ON public.notifications;
CREATE POLICY "Authenticated users can insert notifications"
    ON public.notifications FOR INSERT
    TO authenticated
    WITH CHECK (true);

-- 6. Create function to notify on new message (seller → customer)
CREATE OR REPLACE FUNCTION public.notify_on_new_message()
RETURNS TRIGGER AS $$
DECLARE
    store_name TEXT;
    conv RECORD;
    preview_text TEXT;
BEGIN
    -- Only fire for seller → customer messages
    IF NEW.sender_type != 'seller' THEN
        RETURN NEW;
    END IF;

    -- Get conversation details
    SELECT customer_id, store_id INTO conv
    FROM public.conversations
    WHERE id = NEW.conversation_id;

    IF conv IS NULL THEN
        RETURN NEW;
    END IF;

    -- Get store name
    SELECT name INTO store_name
    FROM public.stores
    WHERE id = conv.store_id;

    -- Build preview text (truncate to 100 chars)
    preview_text := LEFT(COALESCE(NEW.body, 'Sent an attachment'), 100);

    -- Insert notification for the customer
    INSERT INTO public.notifications (
        user_id,
        category,
        title,
        message,
        is_read,
        metadata
    ) VALUES (
        conv.customer_id,
        'message',
        COALESCE(store_name, 'Store'),
        preview_text,
        false,
        jsonb_build_object(
            'conversation_id', NEW.conversation_id,
            'store_name', COALESCE(store_name, 'Store'),
            'sender_id', NEW.sender_id
        )
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 7. Create trigger on messages INSERT
DROP TRIGGER IF EXISTS on_new_message_notify ON public.messages;
CREATE TRIGGER on_new_message_notify
    AFTER INSERT ON public.messages
    FOR EACH ROW
    EXECUTE FUNCTION public.notify_on_new_message();

-- 8. Done — trigger runs as SECURITY DEFINER, no additional GRANT needed
