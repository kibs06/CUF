-- SoleVision Admin Portal — Supabase RLS policies
-- Run in Supabase SQL Editor after creating an admin user in profiles.
--
-- ⚠️ 2026-08-09: these policies previously inlined
--   EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin')
-- into policies ON public.profiles — that self-referential subquery
-- caused RLS infinite recursion (Postgres error 42P17) and broke EVERY
-- query touching profiles. They now call public.is_admin() (a SECURITY
-- DEFINER function that bypasses RLS), defined in migration
-- 20260809120000_fix_profiles_rls_recursion.sql. Apply that migration
-- (or the CREATE FUNCTION below) BEFORE these policies.

-- Ensure the recursion-free helper exists even if this file is applied
-- on a DB without the migration (idempotent).
--
-- ⚠️ 2026-08-13: kept in sync with migration
-- 20260813000000_admin_suspension_enforcement.sql — is_admin() now also
-- excludes suspended accounts so a banned admin loses console access
-- instantly. If you re-run THIS file after that migration, do not use an
-- older is_admin() body here or you will silently downgrade enforcement.
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid()
      AND role = 'admin'
      AND NOT COALESCE(suspended, false)
  );
$$;

-- Policies that call is_admin() are evaluated for BOTH roles (e.g. the
-- public product-browsing policies run as anon). A SECURITY DEFINER
-- function still needs EXECUTE from the CALLING role, so grant both.
-- (CREATE OR REPLACE preserves prior ACLs, so this is needed even if the
-- migration already ran and revoked PUBLIC.)
REVOKE EXECUTE ON FUNCTION public.is_admin() FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.is_admin() TO anon, authenticated;

-- Optional columns for admin portal features
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS suspended boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS rejection_reason text;

-- Admins can read all profiles
DROP POLICY IF EXISTS "Admins can read all profiles" ON public.profiles;
CREATE POLICY "Admins can read all profiles"
ON public.profiles FOR SELECT
USING (public.is_admin());

-- Admins can update all profiles
DROP POLICY IF EXISTS "Admins can update all profiles" ON public.profiles;
CREATE POLICY "Admins can update all profiles"
ON public.profiles FOR UPDATE
USING (public.is_admin());

-- Admins can read all orders
DROP POLICY IF EXISTS "Admins can read all orders" ON public.orders;
CREATE POLICY "Admins can read all orders"
ON public.orders FOR SELECT
USING (public.is_admin());

-- Admins can update orders (status changes)
DROP POLICY IF EXISTS "Admins can update all orders" ON public.orders;
CREATE POLICY "Admins can update all orders"
ON public.orders FOR UPDATE
USING (public.is_admin());

-- Admins can read all products
DROP POLICY IF EXISTS "Admins can read all products" ON public.products;
CREATE POLICY "Admins can read all products"
ON public.products FOR SELECT
USING (public.is_admin());

-- Admins can update products
DROP POLICY IF EXISTS "Admins can update all products" ON public.products;
CREATE POLICY "Admins can update all products"
ON public.products FOR UPDATE
USING (public.is_admin());

-- Admins can read all payment intents (read-only Transactions view)
DROP POLICY IF EXISTS "Admins can read all payment intents" ON public.payment_intents;
CREATE POLICY "Admins can read all payment intents"
ON public.payment_intents FOR SELECT
USING (public.is_admin());

-- Admins can read all payment webhook events (read-only audit trail)
DROP POLICY IF EXISTS "Admins can read all payment webhook events" ON public.payment_webhook_events;
CREATE POLICY "Admins can read all payment webhook events"
ON public.payment_webhook_events FOR SELECT
USING (public.is_admin());

-- NOTE: These two tables must NEVER get admin INSERT/UPDATE/DELETE
-- policies — the admin app is read-only over payment state. The
-- authority to mark an order paid lives only in the signature-verified
-- gcash-webhook edge function (service role). The admin-only SELECT
-- policies above are also applied by
-- app/supabase/migrations/20260810000000_admin_transactions_view.sql
-- (prefer applying them there via `supabase db push`).

-- Enable Realtime for seller applications (Dashboard > Database > Replication)
-- ALTER PUBLICATION supabase_realtime ADD TABLE public.profiles;
