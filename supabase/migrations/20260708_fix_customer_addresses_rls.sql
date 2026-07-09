-- ══════════════════════════════════════════════════════════════════
-- Migration: Fix customer_addresses RLS policies (never applied)
-- Date: July 8, 2026
-- Context: The original migration (20260705) created the table + RLS
--   policies, but the policies were never applied to the live database.
--   Customers get PostgrestException 42501 (insufficient_privilege)
--   when trying to INSERT into customer_addresses.
--   Owner column is user_id (NOT customer_id — that column doesn't exist).
-- ══════════════════════════════════════════════════════════════════

-- 1. Check what policies already exist (informational)
-- SELECT * FROM pg_policies WHERE tablename = 'customer_addresses';

-- 2. Drop any existing policies (idempotent — safe to re-run)
DROP POLICY IF EXISTS "Users can view their own addresses" ON public.customer_addresses;
DROP POLICY IF EXISTS "Users can insert their own addresses" ON public.customer_addresses;
DROP POLICY IF EXISTS "Users can update their own addresses" ON public.customer_addresses;
DROP POLICY IF EXISTS "Users can delete their own addresses" ON public.customer_addresses;

-- 3. Create all four CRUD policies
-- SELECT (read)
CREATE POLICY "Users can view their own addresses"
    ON public.customer_addresses FOR SELECT USING (
        auth.uid() = user_id
    );

-- INSERT (create)
CREATE POLICY "Users can insert their own addresses"
    ON public.customer_addresses FOR INSERT WITH CHECK (
        auth.uid() = user_id
    );

-- UPDATE (edit)
CREATE POLICY "Users can update their own addresses"
    ON public.customer_addresses FOR UPDATE USING (
        auth.uid() = user_id
    );

-- DELETE (remove)
CREATE POLICY "Users can delete their own addresses"
    ON public.customer_addresses FOR DELETE USING (
        auth.uid() = user_id
    );

-- 4. Verify — run this after applying the above:
-- SELECT policyname, cmd, qual, with_check
-- FROM pg_policies
-- WHERE tablename = 'customer_addresses'
-- ORDER BY cmd;
