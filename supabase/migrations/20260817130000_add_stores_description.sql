-- Add the optional "about the store" description column to stores.
--
-- The app has referenced stores.description since the seller-application
-- rework (StoreService.createStore / updateStoreSeller write it, the
-- customer store profile renders it), but no migration ever added the
-- column to the database — so store creation/editing failed with PGRST204
-- ("Could not find the 'description' column of 'stores' in the schema
-- cache"). Idempotent so it's safe to re-run.
ALTER TABLE public.stores
    ADD COLUMN IF NOT EXISTS description TEXT;

COMMENT ON COLUMN public.stores.description IS
    'Optional longer "about the store" text — added post-approval via Create/Edit Store.';
