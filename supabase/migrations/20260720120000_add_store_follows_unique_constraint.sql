-- Migration: add unique constraint on store_follows (user_id, store_id)
-- Safe to run even if some duplicate rows already exist — dedupes first.

-- Step 1: remove any duplicate (user_id, store_id) pairs, keeping the earliest follow
DELETE FROM store_follows a
USING store_follows b
WHERE a.user_id = b.user_id
  AND a.store_id = b.store_id
  AND a.created_at > b.created_at;

-- Step 2: add the unique constraint (matches the existing onConflict in upsert)
ALTER TABLE store_follows
  ADD CONSTRAINT store_follows_user_store_unique UNIQUE (user_id, store_id);
