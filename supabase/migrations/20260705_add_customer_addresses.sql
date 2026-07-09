-- ══════════════════════════════════════════════════════════════════
-- Migration: Add customer_addresses table + shipping_address snapshot
-- Date: July 5, 2026
-- Context: Customers need a saved address book for delivery. Each
--   user can store multiple addresses but only one can be default.
--   The table follows the same RLS pattern as orders (users can
--   only access their own rows). Also adds a shipping_address JSONB
--   column to orders so placed orders retain a snapshot of the
--   address at time of order (future edits don't retrochange).
-- ══════════════════════════════════════════════════════════════════

-- ── Add shipping_address snapshot to orders ────────────────────────
ALTER TABLE public.orders
    ADD COLUMN IF NOT EXISTS shipping_address JSONB;

-- ── Table ──────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.customer_addresses (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    label               TEXT NOT NULL DEFAULT 'Home',
    recipient_name      TEXT NOT NULL,
    recipient_phone     TEXT NOT NULL,
    region              TEXT NOT NULL,
    province            TEXT NOT NULL,
    city_municipality   TEXT NOT NULL,
    barangay            TEXT NOT NULL,
    street_address      TEXT NOT NULL,
    landmark            TEXT,
    latitude            DOUBLE PRECISION NOT NULL,
    longitude           DOUBLE PRECISION NOT NULL,
    is_default          BOOLEAN NOT NULL DEFAULT false,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── Index on user_id ───────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_customer_addresses_user_id
    ON public.customer_addresses (user_id);

-- ── RLS ────────────────────────────────────────────────────────────
ALTER TABLE public.customer_addresses ENABLE ROW LEVEL SECURITY;

-- Users can view their own addresses
CREATE POLICY "Users can view their own addresses"
    ON public.customer_addresses FOR SELECT USING (
        auth.uid() = user_id
    );

-- Users can insert their own addresses
CREATE POLICY "Users can insert their own addresses"
    ON public.customer_addresses FOR INSERT WITH CHECK (
        auth.uid() = user_id
    );

-- Users can update their own addresses
CREATE POLICY "Users can update their own addresses"
    ON public.customer_addresses FOR UPDATE USING (
        auth.uid() = user_id
    );

-- Users can delete their own addresses
CREATE POLICY "Users can delete their own addresses"
    ON public.customer_addresses FOR DELETE USING (
        auth.uid() = user_id
    );

-- ── Trigger: enforce only one default address per user ─────────────
-- When a row is inserted or updated with is_default = true,
-- unset all other defaults for that user.
CREATE OR REPLACE FUNCTION public.enforce_single_default_address()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.is_default = true THEN
        UPDATE public.customer_addresses
        SET is_default = false, updated_at = now()
        WHERE user_id = NEW.user_id
          AND id != NEW.id
          AND is_default = true;
    END IF;
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Attach trigger to INSERT and UPDATE
DROP TRIGGER IF EXISTS trg_enforce_single_default ON public.customer_addresses;
CREATE TRIGGER trg_enforce_single_default
    BEFORE INSERT OR UPDATE ON public.customer_addresses
    FOR EACH ROW
    EXECUTE FUNCTION public.enforce_single_default_address();
