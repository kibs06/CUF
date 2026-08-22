-- ══════════════════════════════════════════════════════════════════
-- Migration: User-initiated account deletion requests
-- Date: 2026-08-21
--
-- WHY THIS CHANGE:
--   Users should be able to request account deletion from the app.
--   Instead of immediate deletion, requests go into a queue that admins
--   can review before processing. This provides a safety window and
--   audit trail.
--
--   Adds:
--     1. deletion_requests table — stores pending/approved/rejected requests
--     2. request_account_deletion() RPC — authenticated users call this
--     3. approve_deletion_request() RPC — admin calls this to process
-- ══════════════════════════════════════════════════════════════════

-- ── Table ────────────────────────────────────────────────────────
CREATE TABLE public.deletion_requests (
  id          uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id     uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  status      text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  reason      text,
  reviewed_by uuid REFERENCES auth.users(id),
  reviewed_at timestamptz,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

-- Index for admin queries
CREATE INDEX idx_deletion_requests_status ON public.deletion_requests(status);
CREATE INDEX idx_deletion_requests_user_id ON public.deletion_requests(user_id);

-- RLS: users can see their own requests, admins can see all
ALTER TABLE public.deletion_requests ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own deletion requests"
  ON public.deletion_requests FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own deletion requests"
  ON public.deletion_requests FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Admins can view all deletion requests"
  ON public.deletion_requests FOR SELECT
  USING (public.is_admin());

CREATE POLICY "Admins can update deletion requests"
  ON public.deletion_requests FOR UPDATE
  USING (public.is_admin());

-- ── RPC: Request account deletion (authenticated user) ───────────
CREATE OR REPLACE FUNCTION public.request_account_deletion(p_reason text DEFAULT NULL)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_existing uuid;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Check for existing pending request
  SELECT id INTO v_existing
    FROM public.deletion_requests
    WHERE user_id = v_user_id AND status = 'pending';

  IF v_existing IS NOT NULL THEN
    RETURN json_build_object(
      'success', false,
      'message', 'You already have a pending deletion request'
    );
  END IF;

  INSERT INTO public.deletion_requests (user_id, reason)
    VALUES (v_user_id, p_reason);

  RETURN json_build_object(
    'success', true,
    'message', 'Your account deletion request has been submitted. Our team will review it within 48 hours.'
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.request_account_deletion(text) TO authenticated;

COMMENT ON FUNCTION public.request_account_deletion(text) IS
  'Authenticated users submit an account deletion request. Creates a pending
   record in deletion_requests. Only one pending request per user is allowed.';

-- ── RPC: Approve & process deletion request (admin) ─────────────
-- This reuses the same deletion logic as admin_delete_user but first
-- updates the request status.
CREATE OR REPLACE FUNCTION public.approve_deletion_request(p_request_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_request record;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Only admins can approve deletion requests';
  END IF;

  SELECT * INTO v_request
    FROM public.deletion_requests
    WHERE id = p_request_id;

  IF v_request IS NULL THEN
    RAISE EXCEPTION 'Deletion request not found';
  END IF;

  IF v_request.status != 'pending' THEN
    RETURN json_build_object(
      'success', false,
      'message', 'This request has already been ' || v_request.status
    );
  END IF;

  -- Mark as approved first
  UPDATE public.deletion_requests
    SET status = 'approved',
        reviewed_by = auth.uid(),
        reviewed_at = now(),
        updated_at = now()
    WHERE id = p_request_id;

  -- Now delete the user (reuses the admin_delete_user logic inline)
  PERFORM public.admin_delete_user(v_request.user_id);

  RETURN json_build_object(
    'success', true,
    'message', 'User account has been permanently deleted'
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.approve_deletion_request(uuid) TO authenticated;

COMMENT ON FUNCTION public.approve_deletion_request(uuid) IS
  'Admin-only: approves a pending deletion request and permanently deletes
   the user account. Calls admin_delete_user internally.';

-- ── RPC: Reject deletion request (admin) ────────────────────────
CREATE OR REPLACE FUNCTION public.reject_deletion_request(p_request_id uuid, p_reason text DEFAULT NULL)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Only admins can reject deletion requests';
  END IF;

  UPDATE public.deletion_requests
    SET status = 'rejected',
        reviewed_by = auth.uid(),
        reviewed_at = now(),
        updated_at = now()
    WHERE id = p_request_id AND status = 'pending';

  IF NOT FOUND THEN
    RETURN json_build_object(
      'success', false,
      'message', 'Request not found or already processed'
    );
  END IF;

  RETURN json_build_object(
    'success', true,
    'message', 'Deletion request has been rejected'
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.reject_deletion_request(uuid, text) TO authenticated;

COMMENT ON FUNCTION public.reject_deletion_request(uuid, text) IS
  'Admin-only: rejects a pending deletion request. The users account
   remains active.';
