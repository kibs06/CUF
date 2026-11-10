-- Seller-pinned reviews: each product can spotlight ONE review at the top
-- of its customer review list (the 5-star rave, the photo that sells the
-- fit, ...). The app sorts pinned first; the seller toggles it from the
-- same reply card.
--
-- Only the store owner (or admin) may change the pin. That rule cannot live
-- in RLS alone: customers hold an UPDATE policy on their own reviews (edit
-- window) and could otherwise pin their own words, so a trigger guards any
-- change to the flag, on INSERT and UPDATE alike.
ALTER TABLE public.reviews
  ADD COLUMN IF NOT EXISTS is_pinned BOOLEAN NOT NULL DEFAULT false;

-- One spotlight per product. The app unpins the previous pin first; this
-- index makes a double-pin impossible even under a race.
CREATE UNIQUE INDEX IF NOT EXISTS uq_reviews_pinned_per_product
  ON public.reviews (product_id)
  WHERE is_pinned;

CREATE OR REPLACE FUNCTION public.guard_review_pin()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
BEGIN
  IF (TG_OP = 'INSERT' AND NEW.is_pinned)
     OR (TG_OP = 'UPDATE' AND NEW.is_pinned IS DISTINCT FROM OLD.is_pinned)
  THEN
    IF NOT (
      public.is_admin()
      OR EXISTS (
        SELECT 1 FROM public.stores
        WHERE stores.id = NEW.store_id
          AND stores.owner_id = auth.uid()
      )
    ) THEN
      RAISE EXCEPTION 'Only the seller can pin reviews';
    END IF;
  END IF;
  RETURN NEW;
END;
$fn$;

COMMENT ON FUNCTION public.guard_review_pin() IS
  'Only a store owner (or admin) may set or clear is_pinned on reviews — '
  'the customer edit-window UPDATE policy must never be a pin door.';

DROP TRIGGER IF EXISTS trg_guard_review_pin ON public.reviews;
CREATE TRIGGER trg_guard_review_pin
  BEFORE INSERT OR UPDATE OF is_pinned ON public.reviews
  FOR EACH ROW EXECUTE FUNCTION public.guard_review_pin();
