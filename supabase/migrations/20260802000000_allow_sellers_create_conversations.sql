-- ============================================================
-- Fix: Allow store owners (sellers) to create conversations
-- ============================================================
-- Bug: The seller's "Message Customer" flow (order detail) calls
-- getOrCreateConversation(), which INSERTs into `conversations`
-- when no thread exists yet. RLS only had customer_insert_conversations
-- (WITH CHECK customer_id = auth.uid()), so a seller's INSERT was
-- rejected with a permission-denied error and the chat never opened.
--
-- Fix: Add a permissive seller INSERT policy keyed on store ownership.
-- Policies are OR'd together, so customers keep their existing path.
-- The existing BEFORE INSERT trigger (set_conversation_customer_name,
-- SECURITY DEFINER) still auto-populates customer_name for seller-created
-- threads, and seller_insert_messages already allows the seller to then
-- post messages in their own store's conversations.
-- ============================================================

DROP POLICY IF EXISTS "seller_insert_conversations" ON public.conversations;
CREATE POLICY "seller_insert_conversations"
    ON public.conversations FOR INSERT
    WITH CHECK (
        store_id IN (
            SELECT id FROM public.stores WHERE owner_id = auth.uid()
        )
    );
