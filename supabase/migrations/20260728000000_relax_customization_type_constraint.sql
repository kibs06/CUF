-- Relax the CHECK constraint on product_customizations.option_type
-- to allow arbitrary type strings beyond the original 'text', 'select', 'color'.
-- This supports the new "Other" option in the customization type dropdown.

-- Drop the old constrained CHECK
ALTER TABLE public.product_customizations
  DROP CONSTRAINT IF EXISTS product_customizations_option_type_check;

-- Re-add with a permissive CHECK that only ensures non-empty text
ALTER TABLE public.product_customizations
  ADD CONSTRAINT product_customizations_option_type_check
  CHECK (length(option_type) > 0);
