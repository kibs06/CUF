-- ============================================================
-- Seller ⇄ Customer Messaging
-- One thread per (store_id, customer_id) pair.
-- ============================================================

-- Conversations table
CREATE TABLE IF NOT EXISTS conversations (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  store_id        uuid NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  customer_id     uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  last_message_at timestamptz,
  last_message_preview text,
  created_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE(store_id, customer_id)
);

CREATE INDEX IF NOT EXISTS idx_conversations_store_id ON conversations(store_id);
CREATE INDEX IF NOT EXISTS idx_conversations_customer_id ON conversations(customer_id);
CREATE INDEX IF NOT EXISTS idx_conversations_last_message_at ON conversations(last_message_at DESC);

-- Messages table
-- Note: sender_id is nullable + ON DELETE SET NULL so message history
-- survives if a user account is later deleted, consistent with the
-- "nullify references, don't cascade" pattern used elsewhere in the app
-- (e.g. order_items.product_id on product delete).
CREATE TABLE IF NOT EXISTS messages (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id   uuid NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  sender_id         uuid REFERENCES profiles(id) ON DELETE SET NULL,
  sender_type       text NOT NULL CHECK (sender_type IN ('customer', 'seller')),
  body              text NOT NULL,
  order_reference_id uuid REFERENCES orders(id) ON DELETE SET NULL,
  is_read           boolean NOT NULL DEFAULT false,
  created_at        timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_messages_conversation_id ON messages(conversation_id);
CREATE INDEX IF NOT EXISTS idx_messages_created_at ON messages(created_at DESC);

-- ============================================================
-- RLS Policies
-- ============================================================

ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;

-- Conversations: customer can read their own conversations
DROP POLICY IF EXISTS "customer_read_own_conversations" ON conversations;
CREATE POLICY "customer_read_own_conversations"
  ON conversations FOR SELECT
  USING (customer_id = auth.uid());

-- Conversations: seller can read conversations for their stores
DROP POLICY IF EXISTS "seller_read_store_conversations" ON conversations;
CREATE POLICY "seller_read_store_conversations"
  ON conversations FOR SELECT
  USING (
    store_id IN (
      SELECT id FROM stores WHERE owner_id = auth.uid()
    )
  );

-- Conversations: only customers can create new conversations
DROP POLICY IF EXISTS "customer_insert_conversations" ON conversations;
CREATE POLICY "customer_insert_conversations"
  ON conversations FOR INSERT
  WITH CHECK (customer_id = auth.uid());

-- NOTE: No client-side UPDATE policy on conversations.
-- last_message_at / last_message_preview are maintained automatically
-- by the trigger below (SECURITY DEFINER), so neither party needs
-- direct UPDATE access to this table. This also avoids race conditions
-- if messages from both sides land close together.

-- Messages: customer can read messages in their own conversations
DROP POLICY IF EXISTS "customer_read_own_messages" ON messages;
CREATE POLICY "customer_read_own_messages"
  ON messages FOR SELECT
  USING (
    conversation_id IN (
      SELECT id FROM conversations WHERE customer_id = auth.uid()
    )
  );

-- Messages: seller can read messages in their store's conversations
DROP POLICY IF EXISTS "seller_read_store_messages" ON messages;
CREATE POLICY "seller_read_store_messages"
  ON messages FOR SELECT
  USING (
    conversation_id IN (
      SELECT c.id FROM conversations c
      JOIN stores s ON c.store_id = s.id
      WHERE s.owner_id = auth.uid()
    )
  );

-- Messages: customer can send messages in their own conversations
DROP POLICY IF EXISTS "customer_insert_messages" ON messages;
CREATE POLICY "customer_insert_messages"
  ON messages FOR INSERT
  WITH CHECK (
    sender_id = auth.uid()
    AND sender_type = 'customer'
    AND conversation_id IN (
      SELECT id FROM conversations WHERE customer_id = auth.uid()
    )
  );

-- Messages: seller can send messages in their store's conversations
DROP POLICY IF EXISTS "seller_insert_messages" ON messages;
CREATE POLICY "seller_insert_messages"
  ON messages FOR INSERT
  WITH CHECK (
    sender_id = auth.uid()
    AND sender_type = 'seller'
    AND conversation_id IN (
      SELECT c.id FROM conversations c
      JOIN stores s ON c.store_id = s.id
      WHERE s.owner_id = auth.uid()
    )
  );

-- NOTE: No general client-side UPDATE policy on messages.
-- Marking a message read is done via the mark_message_read() RPC
-- below (SECURITY DEFINER), not via direct table UPDATE. This
-- prevents either party from being able to rewrite message body,
-- sender_type, or sender_id after the fact — RLS alone can't
-- restrict UPDATEs to a single column, only to rows.

-- ============================================================
-- Functions & Triggers
-- ============================================================

-- Automatically keep conversations.last_message_at / last_message_preview
-- in sync whenever a new message is inserted, regardless of which
-- party sent it. Runs as SECURITY DEFINER so it can update the
-- conversations row without needing a client-facing UPDATE policy.
CREATE OR REPLACE FUNCTION update_conversation_on_message()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE conversations
  SET last_message_at = NEW.created_at,
      last_message_preview = left(NEW.body, 140)
  WHERE id = NEW.conversation_id;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_update_conversation_on_message ON messages;
CREATE TRIGGER trg_update_conversation_on_message
  AFTER INSERT ON messages
  FOR EACH ROW
  EXECUTE FUNCTION update_conversation_on_message();

-- Mark a single message as read. Call via RPC from the app instead
-- of a direct table UPDATE. Only flips is_read — no other column
-- can be touched through this path.
CREATE OR REPLACE FUNCTION mark_message_read(message_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE messages
  SET is_read = true
  WHERE id = message_id
    AND conversation_id IN (
      -- caller must be a participant in the conversation
      SELECT id FROM conversations WHERE customer_id = auth.uid()
      UNION
      SELECT c.id FROM conversations c
      JOIN stores s ON c.store_id = s.id
      WHERE s.owner_id = auth.uid()
    );
END;
$$;

-- Mark all unread messages from the other party as read in one call.
-- reader_role should be 'customer' or 'seller' — the role of the
-- caller, used to only flip messages sent by the *other* party.
CREATE OR REPLACE FUNCTION mark_conversation_read(convo_id uuid, reader_role text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF reader_role NOT IN ('customer', 'seller') THEN
    RAISE EXCEPTION 'reader_role must be customer or seller';
  END IF;

  UPDATE messages
  SET is_read = true
  WHERE conversation_id = convo_id
    AND is_read = false
    AND sender_type <> reader_role
    AND conversation_id IN (
      SELECT id FROM conversations WHERE customer_id = auth.uid()
      UNION
      SELECT c.id FROM conversations c
      JOIN stores s ON c.store_id = s.id
      WHERE s.owner_id = auth.uid()
    );
END;
$$;

-- ============================================================
-- Realtime publication
-- ============================================================

-- Add to realtime publication (idempotent: check first)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'conversations'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE conversations;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'messages'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE messages;
  END IF;
END $$;