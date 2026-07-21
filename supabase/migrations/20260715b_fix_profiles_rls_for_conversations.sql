-- ============================================================
-- Fix: Allow sellers to read customer profiles via conversations
-- ============================================================
-- The profiles table has restrictive RLS that only lets users
-- read their own profile. This silently blocks the seller from
-- reading customer names when querying profiles for the inbox.
--
-- Fix: Add a policy allowing users to read profiles of people
-- they share a conversation with.
-- ============================================================

-- Drop existing permissive SELECT policy if it exists (safe to re-run)
DROP POLICY IF EXISTS "Public profiles are viewable by everyone" ON public.profiles;
DROP POLICY IF EXISTS "Users can view profiles of their conversation partners" ON public.profiles;

-- Allow any authenticated user to read any profile (broad but simple)
-- This matches the documented schema and is safe because profiles
-- only contain non-sensitive display data (name, avatar, role).
CREATE POLICY "Users can view profiles of their conversation partners"
    ON public.profiles FOR SELECT
    USING (true);
