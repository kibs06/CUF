-- ══════════════════════════════════════════════════════════════════
-- Migration: Seller tiered verification — Tier 1 (application docs)
--             + Tier 2 (optional business docs) + private storage
-- Date: 2026-08-12
--
-- WHY THIS CHANGE (restating the spec in the codebase's terms):
--   1. The legacy single-form signup (register_screen.dart) served both
--      roles with a toggle; seller applicants got no signal they were
--      entering a higher-stakes flow and nothing was collected to verify
--      they are a real person / a real Carcar artisan.
--   2. The new signup splits into a role-choice entry (customer vs.
--      seller) and a multi-step seller application flow that collects
--      Tier 1 identity + community + storefront data BEFORE an admin
--      reviews (the role still only flips customer → seller on approval).
--   3. Tier 2 (formal business docs: DTI, BIR COR, mayor's/barangay
--      permit) is OPTIONAL and decoupled from the approval gate — most
--      home-based CUFMAI artisans won't have DTI/BIR at signup time, so
--      Tier 1 is enough to start selling and Tier 2 merely upgrades trust.
--
-- All columns are additive / nullable so pre-migration users (approved
-- sellers and customers) are completely unaffected: AuthGate and the
-- seller shell treat missing Tier 1 fields on legacy accounts as
-- acceptable, never as an error state.
--
-- ══════════════════════════════════════════════════════════════════

-- ────────────────────────────────────────────────────────────────
-- 1. PROFILES — Tier 1 seller-application fields (all nullable)
-- ────────────────────────────────────────────────────────────────
ALTER TABLE public.profiles
    ADD COLUMN IF NOT EXISTS id_document_url     TEXT,
    ADD COLUMN IF NOT EXISTS selfie_url          TEXT,
    ADD COLUMN IF NOT EXISTS cufmai_member_id    TEXT,
    ADD COLUMN IF NOT EXISTS barangay_proof_url  TEXT,
    ADD COLUMN IF NOT EXISTS store_name          TEXT,
    ADD COLUMN IF NOT EXISTS store_description   TEXT,
    ADD COLUMN IF NOT EXISTS payout_method       TEXT
        CHECK (payout_method IN ('gcash', 'bank')),
    ADD COLUMN IF NOT EXISTS payout_details      TEXT;

COMMENT ON COLUMN public.profiles.id_document_url IS
    'Tier 1: storage path of the applicant''s government-issued ID photo (private bucket seller-verification-docs).';
COMMENT ON COLUMN public.profiles.selfie_url IS
    'Tier 1: storage path of the applicant''s liveness selfie (private bucket seller-verification-docs).';
COMMENT ON COLUMN public.profiles.cufmai_member_id IS
    'Tier 1: CUFMAI membership number, when the applicant is a member (mutually satisfiable with barangay_proof_url).';
COMMENT ON COLUMN public.profiles.barangay_proof_url IS
    'Tier 1: storage path of barangay proof of residency when the applicant is NOT a CUFMAI member (private bucket).';
COMMENT ON COLUMN public.profiles.store_name IS
    'Tier 1: proposed store name collected during the seller application. The live stores row is still created post-approval via CreateStoreScreen.';
COMMENT ON COLUMN public.profiles.store_description IS
    'Tier 1: one-paragraph store description collected during the seller application.';
COMMENT ON COLUMN public.profiles.payout_method IS
    'Tier 1: preferred payout rail for seller earnings: gcash or bank.';
COMMENT ON COLUMN public.profiles.payout_details IS
    'Tier 1: payout destination — GCash number, or bank name + account number.';

-- ────────────────────────────────────────────────────────────────
-- 2. SELLER_BUSINESS_DOCS — Tier 2 (optional, decoupled from the
--    approval gate). One row per profile (unique index enforces it).
--    verification_status is client-writable ONLY as 'none'/'pending'
--    (trigger guard below); 'verified'/'rejected' is admin-only.
-- ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.seller_business_docs (
    id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id           UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
    dti_cert_url         TEXT,
    bir_cor_url          TEXT,
    permit_url           TEXT,
    verification_status  TEXT NOT NULL DEFAULT 'none'
        CHECK (verification_status IN ('none', 'pending', 'verified', 'rejected')),
    submitted_at         TIMESTAMP WITH TIME ZONE,
    verified_at          TIMESTAMP WITH TIME ZONE,
    created_at           TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS seller_business_docs_profile_id_key
    ON public.seller_business_docs (profile_id);

COMMENT ON TABLE public.seller_business_docs IS
    'Tier 2 business verification documents (DTI cert, BIR COR, mayor''s/barangay permit). Optional and independent of seller_status — a seller with verification_status ''none'' or ''pending'' can sell normally.';

ALTER TABLE public.seller_business_docs ENABLE ROW LEVEL SECURITY;

-- Owner can read their own row (drives the seller's Tier 2 status screen).
DROP POLICY IF EXISTS "Sellers can view their own business docs" ON public.seller_business_docs;
CREATE POLICY "Sellers can view their own business docs"
    ON public.seller_business_docs FOR SELECT
    USING (auth.uid() = profile_id);

-- Owner can create their row on first submission.
DROP POLICY IF EXISTS "Sellers can insert their own business docs" ON public.seller_business_docs;
CREATE POLICY "Sellers can insert their own business docs"
    ON public.seller_business_docs FOR INSERT
    WITH CHECK (auth.uid() = profile_id);

-- Owner can update their row when re-submitting after a rejection.
-- The trigger below keeps the owner from ever writing 'verified'.
DROP POLICY IF EXISTS "Sellers can update their own business docs" ON public.seller_business_docs;
CREATE POLICY "Sellers can update their own business docs"
    ON public.seller_business_docs FOR UPDATE
    USING (auth.uid() = profile_id);

-- Admins can review every applicant's docs.
DROP POLICY IF EXISTS "Admins can read all business docs" ON public.seller_business_docs;
CREATE POLICY "Admins can read all business docs"
    ON public.seller_business_docs FOR SELECT
    USING (public.is_admin());

-- Admins can set the verification verdict ('verified' / 'rejected').
DROP POLICY IF EXISTS "Admins can update business doc status" ON public.seller_business_docs;
CREATE POLICY "Admins can update business doc status"
    ON public.seller_business_docs FOR UPDATE
    USING (public.is_admin())
    WITH CHECK (public.is_admin());

-- ────────────────────────────────────────────────────────────────
-- 2a. Owner status guard — sellers may only ever write
--     verification_status 'none'/'pending'. Attempting 'verified'
--     (or 'rejected') as the document owner raises a clear error,
--     so a seller can never self-certify. Admins bypass this via
--     the admin UPDATE policy + SECURITY DEFINER helper check below.
-- ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.guard_seller_business_docs_status()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF auth.uid() = NEW.profile_id
       AND NEW.verification_status NOT IN ('none', 'pending') THEN
        RAISE EXCEPTION 'Sellers can only submit business documents for review (status none/pending).';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_seller_business_docs_status
    ON public.seller_business_docs;
CREATE TRIGGER trg_guard_seller_business_docs_status
    BEFORE INSERT OR UPDATE ON public.seller_business_docs
    FOR EACH ROW EXECUTE FUNCTION public.guard_seller_business_docs_status();

-- Admin verdict helper (SECURITY DEFINER so the role check cannot be
-- bypassed through RLS, mirroring public.is_admin() usage elsewhere).
-- The Flutter admin app calls this to verify/reject Tier 2 submissions.
CREATE OR REPLACE FUNCTION public.set_business_verification_status(
    p_doc_id uuid,
    p_status text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Only admins can set business verification status.';
    END IF;
    IF p_status NOT IN ('verified', 'rejected') THEN
        RAISE EXCEPTION 'Admin verdict must be verified or rejected.';
    END IF;

    UPDATE public.seller_business_docs
       SET verification_status = p_status,
           verified_at = CASE
               WHEN p_status = 'verified' THEN timezone('utc'::text, now())
               ELSE verified_at
           END,
           submitted_at = CASE
               WHEN p_status = 'rejected' THEN submitted_at
               ELSE submitted_at
           END
     WHERE id = p_doc_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No business document row with id %.', p_doc_id;
    END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.set_business_verification_status(uuid, text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.set_business_verification_status(uuid, text) TO authenticated;

COMMENT ON FUNCTION public.set_business_verification_status(uuid, text) IS
    'Admin-only verdict on a Tier 2 business-document submission. SECURITY DEFINER; re-checks is_admin() internally.';

-- Legacy grant hygiene: new tables are covered by the base schema's
-- ALTER DEFAULT PRIVILEGES, but grant explicitly for the local stack.
GRANT ALL ON public.seller_business_docs TO anon, authenticated, service_role;

-- ────────────────────────────────────────────────────────────────
-- 3. STORAGE — private bucket for verification documents
--    (ID photos, selfies, barangay proofs, DTI/BIR/permits).
--    NOT the public product-images bucket: files are readable only by
--    their owner and by admins. Folder layout: {user_id}/{doc_key}.jpg
--    — every policy keys off the first path segment so cross-user
--    reads are structurally impossible (acceptance criterion #4).
-- ────────────────────────────────────────────────────────────────
INSERT INTO storage.buckets (id, name, public)
VALUES ('seller-verification-docs', 'seller-verification-docs', false)
ON CONFLICT (id) DO NOTHING;

-- Owner can upload into their own folder.
DROP POLICY IF EXISTS "Owners can upload their verification docs" ON storage.objects;
CREATE POLICY "Owners can upload their verification docs"
    ON storage.objects FOR INSERT TO authenticated
    WITH CHECK (
        bucket_id = 'seller-verification-docs'
        AND (storage.foldername(name))[1] = auth.uid()::text
    );

-- Owner can read their own folder (drives their status screens via
-- createSignedUrl — signed URLs require the object SELECT policy).
DROP POLICY IF EXISTS "Owners can read their verification docs" ON storage.objects;
CREATE POLICY "Owners can read their verification docs"
    ON storage.objects FOR SELECT TO authenticated
    USING (
        bucket_id = 'seller-verification-docs'
        AND (storage.foldername(name))[1] = auth.uid()::text
    );

-- Owner can overwrite their own files (upsert re-submission).
DROP POLICY IF EXISTS "Owners can update their verification docs" ON storage.objects;
CREATE POLICY "Owners can update their verification docs"
    ON storage.objects FOR UPDATE TO authenticated
    USING (
        bucket_id = 'seller-verification-docs'
        AND (storage.foldername(name))[1] = auth.uid()::text
    );

-- Owner can delete their own files (replace/remove in the flow).
DROP POLICY IF EXISTS "Owners can delete their verification docs" ON storage.objects;
CREATE POLICY "Owners can delete their verification docs"
    ON storage.objects FOR DELETE TO authenticated
    USING (
        bucket_id = 'seller-verification-docs'
        AND (storage.foldername(name))[1] = auth.uid()::text
    );

-- Admins can read every applicant's files (approval review zoom).
DROP POLICY IF EXISTS "Admins can read all verification docs" ON storage.objects;
CREATE POLICY "Admins can read all verification docs"
    ON storage.objects FOR SELECT TO authenticated
    USING (
        bucket_id = 'seller-verification-docs'
        AND public.is_admin()
    );

-- ══════════════════════════════════════════════════════════════════
-- VERIFICATION QUERIES (run after applying)
-- ══════════════════════════════════════════════════════════════════
-- -- Columns exist:
-- SELECT column_name FROM information_schema.columns
--   WHERE table_schema = 'public' AND table_name = 'profiles'
--     AND column_name IN ('id_document_url','selfie_url','cufmai_member_id',
--                         'barangay_proof_url','store_name','store_description',
--                         'payout_method','payout_details');
--
-- -- Tier 2 table + policies:
-- SELECT tablename, policyname FROM pg_policies
--   WHERE tablename = 'seller_business_docs';
--
-- -- Private bucket + policies (expect bucket public = false):
-- SELECT id, public FROM storage.buckets WHERE id = 'seller-verification-docs';
-- SELECT policyname, cmd FROM pg_policies
--   WHERE schemaname = 'storage' AND tablename = 'objects'
--     AND qual LIKE '%seller-verification-docs%';
--
-- -- Cross-user read test (acceptance criterion #4):
-- --   1. Upload as user A → path 'A/some.jpg'.
-- --   2. As user B (authenticated): SELECT from storage.objects
-- --      WHERE name = 'A/some.jpg' → expect ZERO rows.
-- --   3. As user B: createSignedUrl('A/some.jpg') → expect failure.
-- --   4. As admin: SELECT the same row → expect 1 row.
--
-- -- Owner cannot self-certify:
-- --   SET ROLE authenticated;
-- --   UPDATE public.seller_business_docs
-- --      SET verification_status = 'verified' WHERE profile_id = auth.uid();
-- --   → expect exception 'Sellers can only submit business documents...'
-- --   RESET ROLE;
