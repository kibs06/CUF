-- ============================================================
-- Allow each party to permanently delete their OWN sent messages
-- (long-press a message → Delete in the chat UI).
--
-- A DELETE removes the row for BOTH parties — the other party's
-- chat updates automatically via the realtime subscription.
-- Sender-only scoping prevents either party from deleting the
-- other's messages, mirroring the INSERT policies' ownership checks.
-- ============================================================

-- Messages: customer can delete their own sent messages
DROP POLICY IF EXISTS "customer_delete_own_messages" ON messages;
CREATE POLICY "customer_delete_own_messages"
  ON messages FOR DELETE
  USING (
    sender_id = auth.uid()
    AND sender_type = 'customer'
    AND conversation_id IN (
      SELECT id FROM conversations WHERE customer_id = auth.uid()
    )
  );

-- Messages: seller (store owner) can delete their own sent messages
DROP POLICY IF EXISTS "seller_delete_own_messages" ON messages;
CREATE POLICY "seller_delete_own_messages"
  ON messages FOR DELETE
  USING (
    sender_id = auth.uid()
    AND sender_type = 'seller'
    AND conversation_id IN (
      SELECT c.id FROM conversations c
      JOIN stores s ON c.store_id = s.id
      WHERE s.owner_id = auth.uid()
    )
  );

-- ============================================================
-- Keep the inbox preview in sync after a message is deleted.
-- The INSERT trigger only runs on new messages, so deleting the
-- latest message would otherwise leave last_message_at /
-- last_message_preview pointing at a row that no longer exists.
-- This rolls the metadata back to the newest remaining message
-- (or clears it if the thread is empty).
-- ============================================================

CREATE OR REPLACE FUNCTION update_conversation_on_message_delete()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE conversations
  SET last_message_at = (
        SELECT m.created_at FROM messages m
        WHERE m.conversation_id = OLD.conversation_id
        ORDER BY m.created_at DESC, m.id DESC
        LIMIT 1
      ),
      last_message_preview = (
        SELECT left(m.body, 140) FROM messages m
        WHERE m.conversation_id = OLD.conversation_id
        ORDER BY m.created_at DESC, m.id DESC
        LIMIT 1
      )
  WHERE id = OLD.conversation_id;
  RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS trg_update_conversation_on_message_delete ON messages;
CREATE TRIGGER trg_update_conversation_on_message_delete
  AFTER DELETE ON messages
  FOR EACH ROW
  EXECUTE FUNCTION update_conversation_on_message_delete();

-- ============================================================
-- Storage cleanup for deleted attachment messages
--
-- Files live under message-attachments/{conversation_id}/{message_id}/.
-- The app deletes them when the sender deletes their own attachment
-- message (after the row delete succeeds). This policy lets a sender
-- remove ONLY files whose owning message they sent — folder segment 2
-- is the message id, segment 1 is the conversation id. Mirrors the
-- sender-only scope of the messages DELETE policies above.
-- ============================================================

DROP POLICY IF EXISTS "sender_delete_own_attachment_files" ON storage.objects;
CREATE POLICY "sender_delete_own_attachment_files"
  ON storage.objects FOR DELETE
  USING (
    bucket_id = 'message-attachments'
    AND (storage.foldername(name))[1]::uuid IN (
      SELECT id FROM conversations WHERE customer_id = auth.uid()
      UNION
      SELECT c.id FROM conversations c
      JOIN stores s ON c.store_id = s.id
      WHERE s.owner_id = auth.uid()
    )
    -- Guard segment 2 with a UUID pattern BEFORE casting so a junk path
    -- (e.g. {convo}/{junk}/x.jpg uploaded by a participant) is denied
    -- instead of throwing 'invalid input syntax for type uuid'.
    AND (storage.foldername(name))[2] ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    AND (storage.foldername(name))[2]::uuid IN (
      SELECT id FROM messages
      WHERE sender_id = auth.uid()
        AND conversation_id = (storage.foldername(name))[1]::uuid
    )
  );
