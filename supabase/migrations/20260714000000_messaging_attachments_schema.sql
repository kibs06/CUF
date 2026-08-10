-- ============================================================
-- Messaging Attachments (images & videos)
-- Run AFTER messaging_schema.sql
-- ============================================================

-- ------------------------------------------------------------
-- 1. Extend messages table
-- ------------------------------------------------------------

-- body becomes optional: a message can now be attachment-only
-- (e.g. sending a photo with no caption), text-only (as before),
-- or both (attachment + caption).
ALTER TABLE messages ALTER COLUMN body DROP NOT NULL;

ALTER TABLE messages
  ADD COLUMN IF NOT EXISTS attachment_url text,
  ADD COLUMN IF NOT EXISTS attachment_type text CHECK (attachment_type IN ('image', 'video')),
  ADD COLUMN IF NOT EXISTS attachment_thumbnail_url text,
  ADD COLUMN IF NOT EXISTS attachment_duration_seconds integer,
  ADD COLUMN IF NOT EXISTS attachment_size_bytes bigint;

-- A message must have SOMETHING — either text, an attachment, or both.
-- Prevents fully empty rows.
ALTER TABLE messages
  ADD CONSTRAINT messages_body_or_attachment_check
  CHECK (
    (body IS NOT NULL AND btrim(body) <> '')
    OR attachment_url IS NOT NULL
  );

-- attachment_type must be set whenever attachment_url is set, and vice versa
ALTER TABLE messages
  ADD CONSTRAINT messages_attachment_pair_check
  CHECK (
    (attachment_url IS NULL AND attachment_type IS NULL)
    OR (attachment_url IS NOT NULL AND attachment_type IS NOT NULL)
  );

-- ------------------------------------------------------------
-- 2. Update the last-message-preview trigger to handle attachments
--    (body can now be null, so the old `left(NEW.body, 140)` would break)
-- ------------------------------------------------------------

CREATE OR REPLACE FUNCTION update_conversation_on_message()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE conversations
  SET last_message_at = NEW.created_at,
      last_message_preview = CASE
        WHEN NEW.body IS NOT NULL AND btrim(NEW.body) <> '' THEN left(NEW.body, 140)
        WHEN NEW.attachment_type = 'image' THEN '📷 Photo'
        WHEN NEW.attachment_type = 'video' THEN '🎥 Video'
        ELSE 'Attachment'
      END
  WHERE id = NEW.conversation_id;
  RETURN NEW;
END;
$$;
-- (trigger itself doesn't need re-creating — it already points at this function)

-- ------------------------------------------------------------
-- 3. Storage bucket for attachments
-- ------------------------------------------------------------

-- Private bucket — NOT public. Access is controlled entirely by the
-- RLS policies below, scoped to conversation participants only.
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'message-attachments',
  'message-attachments',
  false,
  26214400, -- 25 MB per file; adjust if you want a different cap
  ARRAY[
    'image/jpeg', 'image/png', 'image/webp', 'image/gif',
    'video/mp4', 'video/quicktime'
  ]
)
ON CONFLICT (id) DO UPDATE
  SET file_size_limit = EXCLUDED.file_size_limit,
      allowed_mime_types = EXCLUDED.allowed_mime_types;

-- Expected upload path convention (enforce this in the app's upload code):
--   message-attachments/{conversation_id}/{message_id}/{filename}
-- The RLS policies below rely on {conversation_id} being the first
-- path segment, so the upload path MUST follow this convention.

CREATE POLICY "conversation_participants_view_attachments"
  ON storage.objects FOR SELECT
  USING (
    bucket_id = 'message-attachments'
    AND (
      (storage.foldername(name))[1]::uuid IN (
        SELECT id FROM conversations WHERE customer_id = auth.uid()
        UNION
        SELECT c.id FROM conversations c
        JOIN stores s ON c.store_id = s.id
        WHERE s.owner_id = auth.uid()
      )
    )
  );

CREATE POLICY "conversation_participants_upload_attachments"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'message-attachments'
    AND (
      (storage.foldername(name))[1]::uuid IN (
        SELECT id FROM conversations WHERE customer_id = auth.uid()
        UNION
        SELECT c.id FROM conversations c
        JOIN stores s ON c.store_id = s.id
        WHERE s.owner_id = auth.uid()
      )
    )
  );

-- No UPDATE/DELETE policy on purpose — attachments, like messages,
-- shouldn't be editable after being sent. If you want to allow a
-- sender to delete their own upload before it's read, add a scoped
-- DELETE policy later rather than opening it broadly now.
