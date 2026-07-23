-- Add custom_details column for 'Other' category free-text input
ALTER TABLE public.reports ADD COLUMN IF NOT EXISTS custom_details TEXT;

-- Validate: if category = 'other', custom_details must be 10-500 chars
-- Server-side validation via trigger
CREATE OR REPLACE FUNCTION public.validate_custom_details()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.category = 'other' THEN
    IF NEW.custom_details IS NULL OR trim(NEW.custom_details) = '' THEN
      RAISE EXCEPTION 'custom_details_required: Please describe the issue (min 10 characters).';
    END IF;
    IF length(trim(NEW.custom_details)) < 10 THEN
      RAISE EXCEPTION 'custom_details_required: Please add a few more details (min 10 characters).';
    END IF;
    IF length(NEW.custom_details) > 500 THEN
      RAISE EXCEPTION 'custom_details_too_long: Custom details must be 500 characters or fewer.';
    END IF;
    -- Trim the value
    NEW.custom_details := trim(NEW.custom_details);
  ELSE
    -- Strip custom_details for non-'other' categories
    NEW.custom_details := NULL;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_validate_custom_details ON public.reports;
CREATE TRIGGER trg_validate_custom_details
  BEFORE INSERT OR UPDATE OF custom_details, category ON public.reports
  FOR EACH ROW
  EXECUTE FUNCTION public.validate_custom_details();
