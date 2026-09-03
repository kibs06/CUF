-- ══════════════════════════════════════════════════════════════════
-- Migration: Tighten profiles RBAC — guard sensitive columns,
--             restrict cross-user reads, add lookup RPC
-- Date: 2026-09-01
--
-- FINDINGS FROM AUDIT:
--   1. profiles SELECT is world-readable (any authenticated user sees
--      all PII: name, email, phone, birthday, gender, ID type, store
--      lat/lng, document URLs).
--   2. Owner UPDATE has no column guard — a row owner can SET
--      role = 'admin' or seller_status = 'approved' on their own row.
--   3. Admin approve/reject done via raw table UPDATE (not SECURITY
--      DEFINER RPC) — works via RLS but inconsistent with the project
--      pattern (set_business_verification_status, admin_delete_user).
--
-- FIXES APPLIED:
--   A. Column-level guard trigger: prevents row owners from modifying
--      role, seller_status, suspended, suspended_reason, suspended_at.
--      Only SECURITY DEFINER functions (admin RPCs) can change these.
--   B. SECURITY DEFINER get_user_name_email(ids[]): returns {id,
--      full_name, email} for cross-user lookups (order service needs
--      customer names on the seller's order list). No PII beyond name
--      and email. Caller must be authenticated; the function itself
--      does not enforce role — it exposes only the minimal fields
--      needed for order display.
--   C. Tighten profiles SELECT: only own row + admin. All cross-user
--      reads must go through get_user_name_email() or SECURITY
--      DEFINER functions.
--
-- NOTE: This migration is intentionally conservative. It does NOT:
--   - Remove the existing "Users can update their own profile" policy
--     (that's still needed for profile editing)
--   - Change the approve/reject path to RPCs (that's a separate
--     refactoring step — the current path works via RLS and the
--     column guard trigger below prevents self-elevation)
--   - Touch seller_business_docs or storage (already well-protected)
-- ══════════════════════════════════════════════════════════════════

-- ────────────────────────────────────────────────────────────────
-- A. Column-level guard trigger — prevent self-role-elevation
-- ────────────────────────────────────────────────────────────────
-- Without this trigger, a malicious client could do:
--   UPDATE profiles SET role = 'admin' WHERE id = auth.uid();
-- The "Users can update their own profile" RLS policy allows this
-- because auth.uid() = id. The CHECK constraint only validates
-- allowed VALUES (role IN ('customer','seller','admin')), not safe
-- ASSIGNMENTS. This trigger catches the dangerous columns.
--
-- SECURITY DEFINER: runs as owner (postgres), bypasses RLS, so it
-- always sees the real OLD/NEW values regardless of what RLS allows.
-- ────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.guard_profiles_sensitive_columns()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Only guard against non-admin callers. Admins bypass this via
    -- SECURITY DEFINER functions (approve/reject RPCs) that run as
    -- the function owner, not as auth.uid(). Direct admin UPDATEs
    -- through RLS are also fine — the admin UPDATE policy calls
    -- is_admin() which already excludes suspended accounts.
    IF NOT public.is_admin() THEN
        -- Block row owners from modifying sensitive columns via the
        -- "Users can update their own profile" policy.
        IF auth.uid() = NEW.id THEN
            IF NEW.role IS DISTINCT FROM OLD.role THEN
                RAISE EXCEPTION 'Cannot change your own role.';
            END IF;
            IF NEW.seller_status IS DISTINCT FROM OLD.seller_status THEN
                RAISE EXCEPTION 'Cannot change your own seller_status.';
            END IF;
            IF NEW.suspended IS DISTINCT FROM OLD.suspended THEN
                RAISE EXCEPTION 'Cannot change your own suspended status.';
            END IF;
            IF NEW.suspended_reason IS DISTINCT FROM OLD.suspended_reason THEN
                RAISE EXCEPTION 'Cannot change your own suspended_reason.';
            END IF;
            IF NEW.suspended_at IS DISTINCT FROM OLD.suspended_at THEN
                RAISE EXCEPTION 'Cannot change your own suspended_at.';
            END IF;
        END IF;

        -- Also block non-admin sellers from modifying OTHER users'
        -- sensitive columns (the "Admins can update all profiles" policy
        -- gates admin UPDATEs, but belt-and-suspenders).
        IF public.is_seller_or_admin() AND auth.uid() != NEW.id THEN
            IF NEW.role IS DISTINCT FROM OLD.role THEN
                RAISE EXCEPTION 'Only admins can change roles.';
            END IF;
            IF NEW.seller_status IS DISTINCT FROM OLD.seller_status THEN
                RAISE EXCEPTION 'Only admins can change seller_status.';
            END IF;
            IF NEW.suspended IS DISTINCT FROM OLD.suspended THEN
                RAISE EXCEPTION 'Only admins can change suspended status.';
            END IF;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_profiles_sensitive_columns ON public.profiles;
CREATE TRIGGER trg_guard_profiles_sensitive_columns
    BEFORE UPDATE ON public.profiles
    FOR EACH ROW EXECUTE FUNCTION public.guard_profiles_sensitive_columns();

-- ────────────────────────────────────────────────────────────────
-- B. SECURITY DEFINER cross-user lookup RPC
-- ────────────────────────────────────────────────────────────────
-- Returns {id, full_name, email} for a list of user IDs. Used by:
--   - order_service.dart: seller's order list needs customer names
--   - notification title builders: look up sender/full_name
--
-- Exposes ONLY full_name and email — no phone, birthday, gender,
-- ID type, document URLs, or any other PII. The function does NOT
-- enforce a role check — it's SECURITY DEFINER for RLS bypass (so
-- it can read profiles that the caller can't SELECT directly), and
-- the narrow field set limits the information exposure.
--
-- REVOKE from PUBLIC, GRANT to authenticated only.
-- ────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.get_user_name_email(user_ids uuid[])
RETURNS TABLE(id uuid, full_name text, email text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT p.id, p.full_name, p.email
    FROM public.profiles p
    WHERE p.id = ANY(user_ids);
$$;

REVOKE EXECUTE ON FUNCTION public.get_user_name_email(uuid[]) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.get_user_name_email(uuid[]) TO authenticated;

COMMENT ON FUNCTION public.get_user_name_email(uuid[]) IS
    'SECURITY DEFINER: returns {id, full_name, email} for cross-user lookups. Exposes only name + email — no PII. Used by order_service (seller sees customer names) and notification builders.';

-- ────────────────────────────────────────────────────────────────
-- C. Tighten profiles SELECT — own row + admin only
-- ────────────────────────────────────────────────────────────────
-- Remove the world-readable "Public profiles are viewable by
-- everyone" policy and replace with two targeted policies:
--   1. Users can read their own profile (auth.uid() = id)
--   2. Admins can read all profiles (public.is_admin())
--
-- This means:
--   ✅ Users still see their own full profile
--   ✅ Admins still see all profiles for review/management
--   ✅ Cross-user lookups go through get_user_name_email()
--   ❌ Seller A cannot SELECT * FROM profiles WHERE id = seller_B
--   ❌ Customer A cannot see customer B's phone/birthday/ID type
-- ────────────────────────────────────────────────────────────────

-- Drop the permissive base policy
DROP POLICY IF EXISTS "Public profiles are viewable by everyone" ON public.profiles;

-- Owner can read their own row
DROP POLICY IF EXISTS "Users can read their own profile" ON public.profiles;
CREATE POLICY "Users can read their own profile"
    ON public.profiles FOR SELECT
    USING (auth.uid() = id);

-- Admins can read all profiles (already exists from 20260809120000)
-- No change needed — it's already: USING (public.is_admin())

-- ══════════════════════════════════════════════════════════════════
-- VERIFICATION QUERIES (run after applying)
-- ══════════════════════════════════════════════════════════════════

-- 1. Confirm trigger exists:
-- SELECT trigger_name, event_manipulation, action_timing
--   FROM information_schema.triggers
--   WHERE event_object_table = 'profiles'
--     AND trigger_name = 'trg_guard_profiles_sensitive_columns';

-- 2. Confirm world-readable policy is gone:
-- SELECT policyname, cmd, qual FROM pg_policies
--   WHERE tablename = 'profiles' AND schemaname = 'public';

-- 3. Confirm get_user_name_email exists and is SECURITY DEFINER:
-- SELECT proconfig, proacl FROM pg_proc
--   WHERE proname = 'get_user_name_email';

-- 4. Self-role-elevation test (should fail):
--   SET ROLE authenticated;
--   UPDATE public.profiles SET role = 'admin' WHERE id = auth.uid();
--   → expect exception 'Cannot change your own role.'
--   RESET ROLE;

-- 5. Cross-user SELECT test (should return zero rows for non-admin):
--   SET ROLE authenticated;
--   SELECT * FROM public.profiles WHERE id != auth.uid() LIMIT 1;
--   → expect 0 rows (policy blocks it)
--   RESET ROLE;

-- 6. get_user_name_email test (should work for any authenticated user):
--   SELECT * FROM public.get_user_name_email(ARRAY['some-uuid-here']::uuid[]);
--   → expect {id, full_name, email} for that user
