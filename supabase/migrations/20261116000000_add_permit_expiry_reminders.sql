-- ══════════════════════════════════════════════════════════════════
-- Migration: Business-permit expiry reminders
-- Date: 2026-11-16
--
-- WHY THIS CHANGE:
--   The Verified Seller badge means "an admin checked this seller's DTI,
--   BIR COR and mayor's permit". A permit lapses, but nothing recorded
--   WHEN — `seller_business_docs` had no expiry column and no reminder.
--   So a seller could trade on an expired permit, with the badge still on
--   their profile and store page, and neither side would know.
--
--   This file adds the missing date and the reminder that goes with it:
--
--     1. `permit_valid_until` — the permit's last valid day, recorded by
--        the seller. Nullable: every existing row (and every seller who
--        never records it) keeps working, and the badge is unaffected.
--     2. `permit_reminder_for` — the expiry date a reminder was already
--        issued for. Idempotency lives here, not in the app: renewing the
--        permit and entering the new date re-arms the reminder, and
--        nothing can post the same notice twice.
--     3. `set_permit_valid_until(date)` — the seller's own write path.
--        There is no UPDATE policy for applicants on this table (it holds
--        private document paths), so a SECURITY DEFINER RPC that takes NO
--        profile id is the narrowest way to record one date.
--     4. `remind_permit_expiry(window)` — callable by the signed-in
--        seller, posts ONE store-bell notice when the permit is inside the
--        window (30 days by default) or already expired. This database has
--        NO pg_cron (see 20260907000000_fix_stale_pending_gcash_intents),
--        so the trigger is the seller app opening its dashboard — the same
--        opportunistic-sweep pattern the pickup and GCash sweeps use. The
--        function is idempotent, so every launch is safe.
--
--   Also fixed here: the "you're a verified seller" notice written by
--   20261115000000 lands in `notifications` (the CUSTOMER feed). Sellers
--   land in SellerShell, whose bell reads `seller_notifications`, so the
--   seller never saw it. `notify_on_seller_verified()` now also writes the
--   store-bell row (`type = 'verified_seller'`).
--
--   The badge itself is NOT revoked when a permit lapses: only an admin's
--   rejection clears `seller_business_docs.verification_status`, and that
--   is the documented rule. The reminder exists so the seller can renew
--   before an admin has to.
--
--   One existing guard had to be narrowed for any of this to be possible:
--   `guard_seller_business_docs_status` blocked EVERY seller update to an
--   already-verified row, so a verified seller could never record a renewal
--   (section 1b keeps every protection it had and allows the date-only
--   edit — see the comment there).
-- ══════════════════════════════════════════════════════════════════

-- ────────────────────────────────────────────────────────────────
-- 1. COLUMNS — the expiry date and its reminder stamp
-- ────────────────────────────────────────────────────────────────
ALTER TABLE public.seller_business_docs
    ADD COLUMN IF NOT EXISTS permit_valid_until DATE;

ALTER TABLE public.seller_business_docs
    ADD COLUMN IF NOT EXISTS permit_reminder_for DATE;

COMMENT ON COLUMN public.seller_business_docs.permit_valid_until IS
    'Last day the mayor''s/barangay business permit is valid, as entered by the seller. NULL = not recorded (the badge does not depend on it).';

COMMENT ON COLUMN public.seller_business_docs.permit_reminder_for IS
    'The permit_valid_until value a reminder was already posted for. Equals permit_valid_until while the current expiry has been reminded; NULL when a new date re-armed the reminder.';

-- The reminder sweep looks rows up by owner and status; keep it a cheap
-- index rather than a table scan on every seller launch.
CREATE INDEX IF NOT EXISTS idx_seller_business_docs_permit_expiry
    ON public.seller_business_docs (profile_id)
    WHERE permit_valid_until IS NOT NULL;

-- ────────────────────────────────────────────────────────────────
-- 1b. THE SELF-CERTIFICATION GUARD, NARROWED TO WHAT IT PROTECTS
--    `guard_seller_business_docs_status` refused EVERY update a seller
--    made to a row that was already 'verified' — including the permit
--    expiry this migration exists to collect. Its own message is about
--    the STATUS, so it now fires on an actual status change (or a
--    document swap) and lets a date-only edit through.
--
--    Every protection it had is kept:
--      • a seller can never insert or claim 'verified'/'rejected';
--      • a seller can never move a row INTO those states;
--      • a seller cannot swap the reviewed files while the row stays
--        verified — that needs a re-submission (status → 'pending'),
--        which is the existing, intended path.
--    Admins are unaffected: the guard only ever applied to the row's own
--    profile (auth.uid() = profile_id), and admin verdicts go through
--    set_business_verification_status as an admin.
-- ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.guard_seller_business_docs_status()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF auth.uid() IS DISTINCT FROM NEW.profile_id THEN
        RETURN NEW;
    END IF;

    -- A date-only edit on a verdict that is already in place: not a
    -- re-submission, not a claim of verification.
    IF TG_OP = 'UPDATE'
       AND NEW.verification_status IS NOT DISTINCT FROM OLD.verification_status
       AND NEW.dti_cert_url      IS NOT DISTINCT FROM OLD.dti_cert_url
       AND NEW.bir_cor_url       IS NOT DISTINCT FROM OLD.bir_cor_url
       AND NEW.permit_url        IS NOT DISTINCT FROM OLD.permit_url
    THEN
        RETURN NEW;
    END IF;

    IF NEW.verification_status NOT IN ('none', 'pending') THEN
        RAISE EXCEPTION 'Sellers can only submit business documents for review (status none/pending).';
    END IF;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.guard_seller_business_docs_status() IS
    'Stops a seller self-certifying: they may only hold/claim none or pending, and cannot swap the reviewed files while a row stays verified. A date-only edit (the permit expiry) is allowed on any verdict.';

-- ────────────────────────────────────────────────────────────────
-- 2. SELLER BELL — admit the two new notice types
--    `type` is CHECK-constrained; an unlisted value is a 23514 that would
--    abort the reminder (and the verification trigger) mid-transaction.
--    The list is the one in 20261113000400_replacement_received.sql,
--    plus 'verified_seller' and 'permit_expiring'.
-- ────────────────────────────────────────────────────────────────
ALTER TABLE public.seller_notifications
  DROP CONSTRAINT IF EXISTS seller_notifications_type_check;

ALTER TABLE public.seller_notifications
  ADD CONSTRAINT seller_notifications_type_check
    CHECK (
      type IN (
        'new_order',
        'stale_order',
        'low_stock',
        'custom_order_request',
        'new_message',
        'model_request',
        'return_request',
        'new_review',
        'review_comment',
        'replacement_received',
        'verified_seller',
        'permit_expiring'
      )
    );

-- ────────────────────────────────────────────────────────────────
-- 3. THE SELLER RECORDS THE PERMIT'S LAST VALID DAY
--    Owner-only by construction: the function takes no profile id, it
--    writes `auth.uid()`'s row and nothing else. A seller with no docs
--    row is told to submit first (there is nothing to attach a date to).
--
--    Changing the date clears the reminder stamp, so the new expiry gets
--    its own reminder. Re-saving the SAME date leaves the stamp alone —
--    re-opening the picker must not queue a duplicate notice.
-- ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.set_permit_valid_until(
  p_valid_until date
) RETURNS date
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_profile uuid := auth.uid();
BEGIN
    IF v_profile IS NULL THEN
        RAISE EXCEPTION 'Not authenticated'
            USING ERRCODE = '42501';
    END IF;

    UPDATE public.seller_business_docs
       SET permit_valid_until = p_valid_until,
           permit_reminder_for =
               CASE
                   WHEN permit_valid_until IS DISTINCT FROM p_valid_until
                       THEN NULL
                   ELSE permit_reminder_for
               END
     WHERE profile_id = v_profile;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Submit your business documents first'
            USING ERRCODE = 'P0001';
    END IF;

    RETURN p_valid_until;
END;
$$;

COMMENT ON FUNCTION public.set_permit_valid_until(date) IS
    'Records the signed-in seller''s business-permit expiry. Owner-only (no profile id parameter); a changed date re-arms the expiry reminder.';

-- ────────────────────────────────────────────────────────────────
-- 4. THE REMINDER
--    One notice per expiry date, posted to the seller's own store bell.
--    Rules, in order:
--      • not verified            → nothing to remind about
--      • no permit date          → nothing to remind about
--      • expiry further than the window → too early
--      • already reminded for this date → no duplicate
--      • expired or inside the window    → post, then stamp
--
--    The stamp is claimed with a single conditional UPDATE (`RETURNING`
--    is the claim token), so two devices opening the app at the same
--    moment cannot both post the notice — one updates, the other matches
--    nothing. `permit_valid_until` is re-read from the row, not from the
--    caller, so a client cannot point the notice at a date of its choice.
-- ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.remind_permit_expiry(
  p_window_days integer DEFAULT 30
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_profile  uuid := auth.uid();
    v_status   text;
    v_until    date;
    v_days     integer;
    v_store_id uuid;
    v_claimed  date;
    v_title    text;
    v_body     text;
BEGIN
    IF v_profile IS NULL THEN
        RAISE EXCEPTION 'Not authenticated'
            USING ERRCODE = '42501';
    END IF;

    -- A window below 1 would never fire; above a year it stops being a
    -- reminder. Both are caller mistakes, not states to paper over.
    IF p_window_days IS NULL OR p_window_days < 1 OR p_window_days > 365 THEN
        RAISE EXCEPTION 'Reminder window must be between 1 and 365 days'
            USING ERRCODE = '22023';
    END IF;

    SELECT verification_status, permit_valid_until
      INTO v_status, v_until
      FROM public.seller_business_docs
     WHERE profile_id = v_profile;

    IF v_status IS DISTINCT FROM 'verified' THEN
        RETURN jsonb_build_object('reminded', false, 'reason', 'not_verified');
    END IF;

    IF v_until IS NULL THEN
        RETURN jsonb_build_object('reminded', false, 'reason', 'no_permit_date');
    END IF;

    v_days := v_until - CURRENT_DATE;

    IF v_days > p_window_days THEN
        RETURN jsonb_build_object(
            'reminded', false,
            'reason', 'not_due',
            'days_left', v_days,
            'permit_valid_until', v_until
        );
    END IF;

    -- The seller's bell is store-scoped. No store yet (an approved seller
    -- who has not finished setup) means no bell to ring; answer honestly
    -- instead of writing to someone else's store or failing the launch.
    SELECT s.id INTO v_store_id
      FROM public.stores s
     WHERE s.owner_id = v_profile
     ORDER BY s.created_at
     LIMIT 1;

    IF v_store_id IS NULL THEN
        RETURN jsonb_build_object(
            'reminded', false,
            'reason', 'no_store',
            'days_left', v_days,
            'permit_valid_until', v_until
        );
    END IF;

    -- Claim: only the first caller for this expiry date updates a row.
    UPDATE public.seller_business_docs
       SET permit_reminder_for = v_until
     WHERE profile_id = v_profile
       AND permit_reminder_for IS DISTINCT FROM v_until
    RETURNING permit_reminder_for INTO v_claimed;

    IF v_claimed IS NULL THEN
        RETURN jsonb_build_object(
            'reminded', false,
            'reason', 'already_reminded',
            'days_left', v_days,
            'permit_valid_until', v_until
        );
    END IF;

    IF v_days < 0 THEN
        v_title := 'Business permit expired';
        v_body  := 'Your business permit lapsed on ' ||
                   to_char(v_until, 'DD Mon YYYY') ||
                   '. Upload the renewed permit to keep your Verified Seller badge.';
    ELSIF v_days = 0 THEN
        v_title := 'Business permit expires today';
        v_body  := 'It lapses today. Upload the renewed permit to keep your ' ||
                   'Verified Seller badge.';
    ELSE
        v_title := 'Business permit expires in ' || v_days || ' day' ||
                   CASE WHEN v_days = 1 THEN '' ELSE 's' END;
        v_body  := 'Renew it before ' || to_char(v_until, 'DD Mon YYYY') ||
                   ' to keep your Verified Seller badge.';
    END IF;

    INSERT INTO public.seller_notifications (store_id, type, title, body, metadata)
    VALUES (
        v_store_id,
        'permit_expiring',
        v_title,
        v_body,
        jsonb_build_object(
            'permit_valid_until', v_until,
            'days_left', v_days
        )
    );

    RETURN jsonb_build_object(
        'reminded', true,
        'days_left', v_days,
        'permit_valid_until', v_until,
        'store_id', v_store_id
    );
END;
$$;

COMMENT ON FUNCTION public.remind_permit_expiry(integer) IS
    'Posts at most one store-bell notice per permit expiry, when a verified seller''s permit is inside the window or already expired. Called opportunistically by the seller app because this database has no pg_cron; idempotent, so every launch is safe.';

-- ────────────────────────────────────────────────────────────────
-- 5. VERIFIED NOTICE — also ring the seller's real bell
--    `notifications` is the customer feed; the seller shell's bell reads
--    `seller_notifications`. Writing only the former meant the seller was
--    "told" in a table their app never renders. Both rows are kept: the
--    customer-feed notice is still the seller's notification record, and
--    the store row is what the bell actually shows.
-- ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.notify_on_seller_verified()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Guarded in stages on purpose: `OLD` is unassigned on INSERT, so it is
    -- only ever touched inside an UPDATE branch rather than as one arm of
    -- an OR that happens to short-circuit.
    IF NEW.verification_status IS DISTINCT FROM 'verified' THEN
        RETURN NEW;
    END IF;
    IF TG_OP = 'UPDATE' AND OLD.verification_status = 'verified' THEN
        RETURN NEW;
    END IF;

    INSERT INTO public.notifications (user_id, category, title, message)
    VALUES (
        NEW.profile_id,
        'approval',
        'You''re a verified seller ✅',
        'Your business documents (DTI, BIR COR, permit) were reviewed and approved. Your Verified Seller badge is now showing on your profile and on your public store page.'
    );

    -- Store bell. Guarded by the SELECT: a seller approved before their
    -- store exists has no row to ring, and a NULL store_id would 23502
    -- the whole docs update.
    INSERT INTO public.seller_notifications (store_id, type, title, body)
    SELECT s.id,
           'verified_seller',
           'You''re a verified seller ✅',
           'Your business documents were reviewed and approved. Your ' ||
           'Verified Seller badge is now showing on your store page.'
      FROM public.stores s
     WHERE s.owner_id = NEW.profile_id
     ORDER BY s.created_at
     LIMIT 1;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.notify_on_seller_verified() IS
    'Writes the in-app "verified seller" notice to the customer feed (approval category) and to the seller''s own store bell (verified_seller) when a business-docs verdict lands on verified.';

REVOKE EXECUTE ON FUNCTION public.notify_on_seller_verified() FROM PUBLIC;

-- ────────────────────────────────────────────────────────────────
-- 6. GRANTS — RPC surface only, never anonymous
--    `REVOKE ... FROM PUBLIC` alone is not enough in this project:
--    Supabase's ALTER DEFAULT PRIVILEGES grants EXECUTE to `anon` by name.
-- ────────────────────────────────────────────────────────────────
REVOKE EXECUTE ON FUNCTION public.set_permit_valid_until(date)
    FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.set_permit_valid_until(date)
    TO authenticated;

REVOKE EXECUTE ON FUNCTION public.remind_permit_expiry(integer)
    FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.remind_permit_expiry(integer)
    TO authenticated;

-- ══════════════════════════════════════════════════════════════════
-- VERIFICATION QUERIES (run after applying)
-- ══════════════════════════════════════════════════════════════════
-- -- Columns:
-- SELECT column_name, data_type FROM information_schema.columns
--   WHERE table_schema = 'public' AND table_name = 'seller_business_docs'
--     AND column_name IN ('permit_valid_until', 'permit_reminder_for');
--
-- -- Grants — anon false, authenticated true:
-- SELECT has_function_privilege('anon',
--          'public.remind_permit_expiry(integer)', 'EXECUTE') AS anon_may,
--        has_function_privilege('authenticated',
--          'public.remind_permit_expiry(integer)', 'EXECUTE') AS auth_may;
--
-- -- Happy path, as a verified seller whose permit is 10 days out:
-- -- BEGIN;
-- --   SET LOCAL request.jwt.claims =
-- --     '{"sub":"<seller uuid>","role":"authenticated"}';
-- --   SELECT public.set_permit_valid_until(current_date + 10);
-- --   SELECT public.remind_permit_expiry();       -- reminded: true, days_left: 10
-- --   SELECT public.remind_permit_expiry();       -- already_reminded
-- --   SELECT type, title FROM public.seller_notifications
-- --     WHERE type = 'permit_expiring' ORDER BY created_at DESC LIMIT 1;
-- -- ROLLBACK;
--
-- ══════════════════════════════════════════════════════════════════
-- ROLLBACK / UNDO (manual — this repository does not auto-revert)
-- ══════════════════════════════════════════════════════════════════
-- DROP FUNCTION IF EXISTS public.remind_permit_expiry(integer);
-- DROP FUNCTION IF EXISTS public.set_permit_valid_until(date);
-- ALTER TABLE public.seller_business_docs
--   DROP COLUMN IF EXISTS permit_reminder_for,
--   DROP COLUMN IF EXISTS permit_valid_until;
