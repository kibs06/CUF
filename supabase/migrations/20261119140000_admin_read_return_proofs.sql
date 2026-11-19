-- ══════════════════════════════════════════════════════════════════
-- Admins can read customer return photos
-- Date: 2026-11-19
--
-- Return photos sit in the private `return-proofs` bucket, whose SELECT
-- policy named only the order's customer and its store's seller (see
-- 20261110010000_add_return_proof.sql). Storage evaluates that policy for the
-- signed-in admin too, so the admin portal could not sign a URL for a return
-- row: every "Photo" click ended with "The screenshot could not be signed."
--
-- This mirrors the admin read policy already used for `platform-payment-qr`
-- and `payout-receipts`: is_admin() may read the objects it needs in order to
-- review a customer's request. Uploads, replacements and deletes stay
-- restricted to the order's customer.
-- ══════════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS "Admins can read return proofs" ON storage.objects;

CREATE POLICY "Admins can read return proofs"
  ON storage.objects FOR SELECT
  USING (
    bucket_id = 'return-proofs'
    AND public.is_admin()
  );
