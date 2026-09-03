-- ══════════════════════════════════════════════════════════════════
-- Migration: Lock seller application content after submission
-- Date: 2026-09-03
--
-- THREAT T3 (seller application records: data tampering), residual
-- hole #1: after the Sep 1 RBAC migration guarded role/seller_status/
-- suspended, an applicant could STILL edit the application's content
-- columns at any status via the "Users can update their own profile"
-- RLS policy — e.g. swap store_name, store_location, or even swap the
-- verification-document URLs (id_document_url, selfie_url,
-- product_photo_urls) AFTER an admin began reviewing or after approval.
-- Confirmed live (2026-09-03): PATCH store_name and PATCH
-- id_document_url on a pending row both returned HTTP 204.
--
-- FIX: extend the existing SECURITY DEFINER guard trigger so a
-- non-admin row owner cannot modify the application-record columns
-- once the application has been submitted (seller_status IN
-- ('pending','approved')). Two statuses stay editable on purpose:
--   • 'none'     — the user has never submitted; the pre-submission
--                  draft is written to these columns freely.
--   • 'rejected' — rejected applicants must be able to re-apply
--                  (the re-apply upsert rewrites these columns), so
--                  the lock must NOT hold here.
-- Admins bypass the whole trigger via the existing is_admin() check,
-- matching the pattern of the original guard.
--
-- NOT locked (legitimate profile fields editable at any time):
--   full_name, email, phone, birthday, gender, avatar_url — and the
--   already-guarded role / seller_status / suspended* columns.
-- ══════════════════════════════════════════════════════════════════

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

            -- T3: once the application is submitted (pending) or already
            -- decided (approved), the application-record columns are
            -- frozen for the owner. The reviewer's verdict must be based
            -- on the exact content that was submitted — no swapping
            -- store details or verification documents mid-review.
            -- 'rejected' is exempt so rejected applicants can re-apply,
            -- and 'none' is exempt so pre-submission drafts still save.
            IF OLD.seller_status IN ('pending', 'approved') THEN
                IF NEW.id_type IS DISTINCT FROM OLD.id_type
                   OR NEW.id_document_url IS DISTINCT FROM OLD.id_document_url
                   OR NEW.selfie_url IS DISTINCT FROM OLD.selfie_url
                   OR NEW.cufmai_member_id IS DISTINCT FROM OLD.cufmai_member_id
                   OR NEW.barangay_proof_url IS DISTINCT FROM OLD.barangay_proof_url
                   OR NEW.store_front_url IS DISTINCT FROM OLD.store_front_url
                   OR NEW.product_photo_urls IS DISTINCT FROM OLD.product_photo_urls
                   OR NEW.store_name IS DISTINCT FROM OLD.store_name
                   OR NEW.store_description IS DISTINCT FROM OLD.store_description
                   OR NEW.store_location IS DISTINCT FROM OLD.store_location
                   OR NEW.store_lat IS DISTINCT FROM OLD.store_lat
                   OR NEW.store_lng IS DISTINCT FROM OLD.store_lng
                   OR NEW.store_tags IS DISTINCT FROM OLD.store_tags
                   OR NEW.rejection_reason IS DISTINCT FROM OLD.rejection_reason
                THEN
                    RAISE EXCEPTION
                        'Application details are locked after submission. Only an admin can change them.';
                END IF;
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

COMMENT ON FUNCTION public.guard_profiles_sensitive_columns IS
    'SECURITY DEFINER guard on profiles: (1) owners cannot change role/seller_status/suspended*, '
    '(2) T3 — once seller_status is pending/approved, owners cannot edit application-record columns '
    '(verification docs, store details, rejection_reason); rejected/none stay editable (re-apply/draft). '
    'Admins bypass via is_admin().';