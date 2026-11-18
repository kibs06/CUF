-- Purok is below barangay level and is not in PSGC/MapTiler coverage.
-- It is optional because many addresses do not use one, but it is part of
-- the delivery address when the customer provides it.
ALTER TABLE public.customer_addresses
    ADD COLUMN IF NOT EXISTS purok TEXT;

COMMENT ON COLUMN public.customer_addresses.purok IS
    'Optional Purok/Sitio below barangay level.';
