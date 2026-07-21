-- ============================================================
-- Fix: Store customer_name directly in conversations table
-- ============================================================
-- The profiles table RLS blocks sellers from reading customer
-- profiles, so any query that joins or batch-fetches profiles
-- returns 0 rows. Fix: denormalize the customer name into the
-- conversations table and auto-populate it via a trigger.
--
-- This eliminates ALL profiles queries from the seller inbox
-- and chat header code paths, bypassing RLS entirely.
-- ============================================================

-- Step 1: Add the column
ALTER TABLE public.conversations
  ADD COLUMN IF NOT EXISTS customer_name text;

-- Step 2: Backfill existing conversations from profiles
UPDATE public.conversations c
SET customer_name = p.full_name
FROM public.profiles p
WHERE c.customer_id = p.id
  AND c.customer_name IS NULL;

-- Step 3: Trigger function — auto-set customer_name on INSERT
CREATE OR REPLACE FUNCTION set_conversation_customer_name()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.customer_name IS NULL THEN
    SELECT full_name INTO NEW.customer_name
    FROM profiles
    WHERE id = NEW.customer_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_set_customer_name ON conversations;
CREATE TRIGGER trg_set_customer_name
  BEFORE INSERT ON conversations
  FOR EACH ROW
  EXECUTE FUNCTION set_conversation_customer_name();

-- Step 4: Also update on profile name change (keeps it in sync)
CREATE OR REPLACE FUNCTION sync_conversation_customer_name()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE conversations
  SET customer_name = NEW.full_name
  WHERE customer_id = NEW.id
    AND customer_name IS DISTINCT FROM NEW.full_name;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_customer_name ON profiles;
CREATE TRIGGER trg_sync_customer_name
  AFTER UPDATE OF full_name ON profiles
  FOR EACH ROW
  EXECUTE FUNCTION sync_conversation_customer_name();
