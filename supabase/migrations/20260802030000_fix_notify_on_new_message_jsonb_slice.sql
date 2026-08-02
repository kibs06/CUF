-- ══════════════════════════════════════════════════════════════════
-- Fix: notify_on_new_message jsonb slice crash (seller sends fail)
-- Date: Aug 2, 2026
-- ══════════════════════════════════════════════════════════════════
-- Bug: The batch-message-notifications rewrite (20260725000000)
--   trimmed metadata.previews with `updated_previews[0:2]`.
--   JSONB subscripting does NOT support slices — only native arrays
--   do. Once a customer has 3+ unread message notifications for a
--   conversation, the NEXT seller→customer message INSERT throws:
--       PostgrestException(code: 42804, message: jsonb subscript
--       does not support slices)
--   The trigger error rolls back the whole message insert, so the
--   seller sees "Failed • Tap to retry" and no row is created.
--   (Verified live: 4 sequential seller inserts → 4th fails with
--   the exact error above.)
--
-- Fix: Replace the invalid slice with jsonb-safe trimming that keeps
--   the newest 3 previews (jsonb_agg + WITH ORDINALITY — no slice
--   operator). Everything else in the function is unchanged.
-- ══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.notify_on_new_message()
RETURNS TRIGGER AS $$
DECLARE
    store_name TEXT;
    conv RECORD;
    preview_text TEXT;
    sender_name TEXT;
    existing_notif RECORD;
    new_preview JSONB;
    updated_previews JSONB;
    new_count INTEGER;
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

    -- Get store name (used as both title and sender label)
    SELECT name INTO store_name
    FROM public.stores
    WHERE id = conv.store_id;

    sender_name := COALESCE(store_name, 'Store');

    -- Build preview text (truncate to 100 chars)
    preview_text := LEFT(COALESCE(NEW.body, 'Sent an attachment'), 100);

    -- Build the new preview entry (newest first in the array)
    new_preview := jsonb_build_object(
        'sender', sender_name,
        'text', preview_text,
        'timestamp', NEW.created_at::text
    );

    -- ── Upsert: look for existing unread message notification for this conversation ──
    SELECT id, metadata INTO existing_notif
    FROM public.notifications
    WHERE user_id = conv.customer_id
      AND category = 'message'
      AND is_read = false
      AND is_deleted = false
      AND metadata->>'conversation_id' = NEW.conversation_id::text
    LIMIT 1;

    IF existing_notif IS NOT NULL THEN
        -- ── UPDATE existing row ────────────────────────────────
        -- Append new preview to front, cap at 3 (drop oldest)
        updated_previews := existing_notif.metadata->'previews';

        IF updated_previews IS NULL THEN
            -- Legacy row without previews — initialize with just the new one
            updated_previews := jsonb_build_array(new_preview);
        ELSE
            -- Prepend new preview
            updated_previews := jsonb_build_array(new_preview) || updated_previews;
            -- Trim to max 3 (jsonb-safe: no slice operator; keep newest 3)
            IF jsonb_array_length(updated_previews) > 3 THEN
                updated_previews := (
                    SELECT jsonb_agg(elem ORDER BY ord)
                    FROM jsonb_array_elements(updated_previews) WITH ORDINALITY AS t(elem, ord)
                    WHERE ord <= 3
                );
            END IF;
        END IF;

        -- Increment message_count (or initialise to 2 if legacy row)
        new_count := COALESCE((existing_notif.metadata->>'message_count')::int, 1) + 1;

        UPDATE public.notifications
        SET
            title = sender_name,
            message = preview_text,
            created_at = NEW.created_at,
            is_deleted = false,
            metadata = jsonb_build_object(
                'conversation_id', NEW.conversation_id,
                'store_name', sender_name,
                'sender_id', NEW.sender_id,
                'previews', updated_previews,
                'message_count', new_count
            )
        WHERE id = existing_notif.id;
    ELSE
        -- ── INSERT new row ─────────────────────────────────────
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
            sender_name,
            preview_text,
            false,
            jsonb_build_object(
                'conversation_id', NEW.conversation_id,
                'store_name', sender_name,
                'sender_id', NEW.sender_id,
                'previews', jsonb_build_array(new_preview),
                'message_count', 1
            )
        );
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- The trigger on messages (on_new_message_notify) already exists and
-- references this function by name — CREATE OR REPLACE re-points it.
-- No DROP TRIGGER needed.
