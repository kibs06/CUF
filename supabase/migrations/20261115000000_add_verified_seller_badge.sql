-- ══════════════════════════════════════════════════════════════════
-- Migration: Verified Seller badge
-- Date: 2026-11-15
--
-- WHY THIS CHANGE:
--   The seller application collects the business requirements (DTI cert,
--   BIR COR, mayor's/barangay permit) in `seller_business_docs`, and an
--   admin reviews them in the same queue as the Tier 1 identity docs. But
--   approving the application only flipped `profiles.role`/`seller_status`
--   — the docs row stayed `pending` for ever, so an approved seller kept
--   seeing "Business Verification · Optional" on their profile, nothing
--   anywhere in the app said "verified seller", and the seller was never
--   told their requirements had been accepted.
--
--   Three things now happen, all server-side so both admin consoles (the
--   Flutter console and the admin-portal React app) behave identically:
--     1. Approving a seller verifies their pending business documents in
--        the SAME transaction as the approval.
--     2. `profiles.seller_verified_at` mirrors the verdict — a public,
--        non-sensitive trust flag. The badge cannot be read from
--        `seller_business_docs`, which holds private document paths and is
--        owner/admin only, and `profiles` is already world-readable.
--     3. Verifying the documents writes a `notifications` row, so the
--        seller hears about it in-app (the feed's realtime subscription
--        picks it up, same as the approval notification).
--
--   Additive and idempotent: one nullable column, then a backfill of the
--   sellers already verified before this file existed.
-- ══════════════════════════════════════════════════════════════════

-- ────────────────────────────────────────────────────────────────
-- 1. PROFILES — public verified-seller stamp
-- ────────────────────────────────────────────────────────────────
ALTER TABLE public.profiles
    ADD COLUMN IF NOT EXISTS seller_verified_at TIMESTAMP WITH TIME ZONE;

COMMENT ON COLUMN public.profiles.seller_verified_at IS
    'When an admin verified this seller''s business requirements (seller_business_docs). Non-null = the seller carries the Verified Seller badge on their profile and store page. Mirrors seller_business_docs.verification_status = ''verified''; cleared when the docs are rejected. Publicly readable on purpose — the badge is a buyer-facing trust signal.';

-- Backfill: sellers whose documents were already verified.
UPDATE public.profiles p
   SET seller_verified_at = COALESCE(d.verified_at, timezone('utc'::text, now()))
  FROM public.seller_business_docs d
 WHERE d.profile_id = p.id
   AND d.verification_status = 'verified'
   AND p.seller_verified_at IS NULL;

-- ────────────────────────────────────────────────────────────────
-- 2. SYNC — keep the profiles stamp equal to the docs verdict
--    'verified'  → stamp (verified_at, else now)
--    'rejected' / 'none' → clear (the badge is withdrawn)
--    'pending'   → leave as-is: a seller verified before keeps the badge
--                  while a re-review is open.
-- ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.sync_seller_verified_at()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NEW.verification_status = 'verified' THEN
        UPDATE public.profiles
           SET seller_verified_at =
               COALESCE(NEW.verified_at, timezone('utc'::text, now()))
         WHERE id = NEW.profile_id;
    ELSIF NEW.verification_status IN ('rejected', 'none') THEN
        UPDATE public.profiles
           SET seller_verified_at = NULL
         WHERE id = NEW.profile_id;
    END IF;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.sync_seller_verified_at() IS
    'Mirrors seller_business_docs.verification_status onto profiles.seller_verified_at so the buyer-facing Verified Seller badge has a public source.';

DROP TRIGGER IF EXISTS trg_sync_seller_verified_at
    ON public.seller_business_docs;
CREATE TRIGGER trg_sync_seller_verified_at
    AFTER INSERT OR UPDATE OF verification_status ON public.seller_business_docs
    FOR EACH ROW EXECUTE FUNCTION public.sync_seller_verified_at();

-- ────────────────────────────────────────────────────────────────
-- 3. NOTIFY — tell the seller the moment they become verified
--    Fires on the transition INTO 'verified' only, so an admin pressing
--    Verify twice cannot spam the feed. Category 'approval' is reused
--    deliberately: it is already in the `notification_category` enum and
--    mirrored by the Dart enum, the customer portal and the contract test,
--    so no client has to learn a new label for one message.
-- ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.notify_on_seller_verified()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Guarded in stages on purpose: `OLD` is unassigned on INSERT, so it is
    -- only ever touched inside an UPDATE branch rather than as one arm of an
    -- OR that happens to short-circuit.
    IF NEW.verification_status IS DISTINCT FROM 'verified' THEN
        RETURN NEW;
    END IF;
    IF TG_OP = 'UPDATE' AND OLD.verification_status = 'verified' THEN
        RETURN NEW;
    END IF;

    BEGIN
        INSERT INTO public.notifications (user_id, category, title, message)
        VALUES (
            NEW.profile_id,
            'approval',
            'You''re a verified seller ✅',
            'Your business documents (DTI, BIR COR, permit) were reviewed and approved. Your Verified Seller badge is now showing on your profile and on your public store page.'
        );
    END;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.notify_on_seller_verified() IS
    'Writes the in-app "verified seller" notification when a business-docs verdict lands on verified. Reuses the existing approval notification category.';

DROP TRIGGER IF EXISTS trg_notify_on_seller_verified
    ON public.seller_business_docs;
CREATE TRIGGER trg_notify_on_seller_verified
    AFTER INSERT OR UPDATE OF verification_status ON public.seller_business_docs
    FOR EACH ROW EXECUTE FUNCTION public.notify_on_seller_verified();

-- ────────────────────────────────────────────────────────────────
-- 4. APPROVAL = BUSINESS-REQUIREMENTS VERDICT
--    The docs the admin reviewed in the application queue are verified in
--    the same transaction as `seller_status = 'approved'`.
--
--    Only 'none'/'pending' rows are promoted, and only when at least one
--    document is actually on file:
--      • a docs row an admin explicitly REJECTED stays rejected (the
--        rejection is a deliberate verdict, not something an approval of
--        the application should silently overturn);
--      • a legacy seller with no documents is not claimed as verified.
--    No recursion: the docs triggers above only touch
--    profiles.seller_verified_at, and this trigger only fires OF
--    seller_status (which no docs trigger writes).
-- ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.verify_seller_docs_on_approval()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    UPDATE public.seller_business_docs
       SET verification_status = 'verified',
           verified_at = timezone('utc'::text, now())
     WHERE profile_id = NEW.id
       AND verification_status IN ('none', 'pending')
       AND (
           (dti_cert_url    IS NOT NULL AND dti_cert_url    <> '')
        OR (bir_cor_url    IS NOT NULL AND bir_cor_url    <> '')
        OR (permit_url     IS NOT NULL AND permit_url     <> '')
       );
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.verify_seller_docs_on_approval() IS
    'Approving a seller application verifies the business documents the admin reviewed in the same queue, so "approved seller" and "verified seller" cannot disagree.';

DROP TRIGGER IF EXISTS trg_verify_seller_docs_on_approval
    ON public.profiles;
CREATE TRIGGER trg_verify_seller_docs_on_approval
    AFTER UPDATE OF seller_status ON public.profiles
    FOR EACH ROW
    WHEN (
        NEW.seller_status = 'approved'
        AND OLD.seller_status IS DISTINCT FROM NEW.seller_status
    )
    EXECUTE FUNCTION public.verify_seller_docs_on_approval();

-- Trigger functions are never called through PostgREST; keep them out of
-- the RPC surface (mirrors the grant hygiene in 20260812000000).
REVOKE EXECUTE ON FUNCTION public.sync_seller_verified_at()          FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.notify_on_seller_verified()        FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.verify_seller_docs_on_approval()   FROM PUBLIC;

-- ══════════════════════════════════════════════════════════════════
-- VERIFICATION QUERIES (run after applying)
-- ══════════════════════════════════════════════════════════════════
-- -- Column exists:
-- SELECT column_name, data_type FROM information_schema.columns
--   WHERE table_schema = 'public' AND table_name = 'profiles'
--     AND column_name = 'seller_verified_at';
--
-- -- The three triggers exist:
-- SELECT tgname, tgrelid::regclass AS tbl FROM pg_trigger
--   WHERE tgname IN ('trg_sync_seller_verified_at',
--                    'trg_notify_on_seller_verified',
--                    'trg_verify_seller_docs_on_approval');
--
-- -- Backfill count (sellers already verified before this migration):
-- SELECT count(*) FROM public.profiles WHERE seller_verified_at IS NOT NULL;
--
-- -- End-to-end dry run on a real pending application (rollback-safe):
-- -- BEGIN;
-- --   UPDATE public.profiles SET seller_status = 'approved',
-- --          role = 'seller' WHERE id = '<applicant uuid>';
-- --   SELECT verification_status, verified_at
-- --     FROM public.seller_business_docs WHERE profile_id = '<applicant uuid>';
-- --   -- expect 'verified' + a timestamp
-- --   SELECT seller_verified_at FROM public.profiles
-- --     WHERE id = '<applicant uuid>';           -- expect non-null
-- --   SELECT title FROM public.notifications
-- --     WHERE user_id = '<applicant uuid>' ORDER BY created_at DESC LIMIT 2;
-- --   -- expect 'You're approved!' and 'You're a verified seller ✅'
-- -- ROLLBACK;
--
-- -- A REJECTED docs row is NOT overturned by an approval:
-- -- BEGIN;
-- --   UPDATE public.seller_business_docs SET verification_status = 'rejected'
-- --     WHERE profile_id = '<applicant uuid>';
-- --   UPDATE public.profiles SET seller_status = 'approved'
-- --     WHERE id = '<applicant uuid>';
-- --   SELECT verification_status FROM public.seller_business_docs
-- --     WHERE profile_id = '<applicant uuid>';   -- expect 'rejected'
-- -- ROLLBACK;
