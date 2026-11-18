-- ══════════════════════════════════════════════════════════════════
-- Migration: the delivery line comes from platform_settings
-- Date: 2026-11-18
--
-- Purpose: `public.online_delivery_fee()` — the one place the voucher
--          preview and the orders BEFORE-INSERT repricing take the delivery
--          line from — returned the literal 100.
--
--          `platform_settings.delivery_fee_amount` already exists, is
--          admin-editable, and is what the manual-GCash checkout RPCs charge.
--          Two numbers for one line meant an admin raising the fee changed the
--          amount charged but not the voucher quote, and the repricing trigger
--          would have written the OLD fee back over the new total.
--
--          From here on there is exactly one number: the settings row. 100 is
--          only the fallback when that row is absent — the seeded value, so a
--          database without settings behaves exactly as before.
--
-- STABLE, not IMMUTABLE: it now reads a table, and a function that lies about
-- that can be folded into a plan-time constant. SECURITY DEFINER so the
-- trigger, the signed-in preview and the anon-facing paths all see the same
-- number instead of depending on the caller's RLS grant on platform_settings.
-- ══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.online_delivery_fee()
RETURNS numeric
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    (SELECT ps.delivery_fee_amount
       FROM public.platform_settings ps
      WHERE ps.id = 1),
    100::numeric
  );
$$;

COMMENT ON FUNCTION public.online_delivery_fee() IS
  'The online delivery line, read from platform_settings.delivery_fee_amount — the same admin-editable value the checkout RPCs charge. Falls back to 100 (the seeded default) when no settings row exists. SECURITY DEFINER so the voucher preview and the orders trigger see one number regardless of the caller.';

-- ══════════════════════════════════════════════════════════════════
-- VERIFICATION QUERIES (run after applying)
-- ══════════════════════════════════════════════════════════════════
-- SELECT public.online_delivery_fee();                    -- the current fee
-- SELECT delivery_fee_amount FROM public.platform_settings WHERE id = 1;
-- UPDATE public.platform_settings SET delivery_fee_amount = 150 WHERE id = 1;
-- SELECT public.online_delivery_fee();                    -- now 150
