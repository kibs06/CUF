-- ══════════════════════════════════════════════════════════════════
-- Migration: 3D model requests — a seller asks, the CUFMAI team models
-- Date: 2026-09-28
-- Roadmap: docs/RoadMap/VIRTUAL_FITTING_ROADMAP.md, V2.10
-- Design:  docs/RoadMap/VIRTUAL_FITTING_ARCHITECTURE.md §2.5.6
--
-- WHY THIS CHANGE:
--   The seller upload (`product_models` + the `shoe-models` bucket, V2.1–V2.3)
--   assumes a seller who can hand over a contract-compliant `.glb`. That is
--   the wrong assumption for this market: CUFMAI's sellers are local artisans,
--   and producing a compliant model needs a capture/cleanup pipeline that
--   nobody in a workshop has. The evidence is in the roadmap's V2.7 row — the
--   first real partner asset came from a marketplace, not from a workshop, and
--   it still needed a normaliser run before it could pass.
--
--   So the pipeline gets a second door: the seller ASKS, and the team models.
--   This table is that ask. It is deliberately not a work-order system — it is
--   a queue with a state, and every state has a meaning the seller can read.
--
--   Adds:
--     0. (P3/P4/V2.14) the two notices a closed ask writes — see below
--     1. shoe_model_requests table — the ask, its four measurements, and the
--        admin's half (assignee, note, and the model it was fulfilled with)
--     2. request_shoe_model()            — seller files the ask
--     3. cancel_shoe_model_request()     — seller withdraws an open ask
--     4. claim_shoe_model_request()      — admin takes it (requested → in_progress)
--     5. fulfil_shoe_model_request()     — admin closes it against a real model
--     6. decline_shoe_model_request()    — admin closes it with a reason
--     7. (V2.14) seller_notifications.type gains 'model_request' — see below
--
--   ...and, since 2026-09-28: `fulfil_shoe_model_request` (P3) AND
--   `decline_shoe_model_request` (P4) also WRITE THE SELLER'S NOTIFICATION, in
--   the same transaction, under the 'models' category — both endings tell them,
--   because the seller's move after either one is to open the product. That category is added by
--   `20260928130000_add_models_notification_category.sql`, which MUST be
--   applied first — `ALTER TYPE ... ADD VALUE` cannot be used in the
--   transaction that adds it, and this file is one transaction.
--
-- ⚠️  AND TWO NOTICES, NOT ONE (V2.14). Step 7 is the correction of a mistake
--     this file's own first two notices made: they are written to
--     `public.notifications`, keyed to the seller's USER, and the seller app
--     never reads that table — the seller's bell reads
--     `public.seller_notifications`, keyed to their STORE. So a notice that was
--     correct in every particular (right recipient, right sentence, right
--     transaction) landed in a feed its reader cannot open. A seller's model
--     notices now go to both: the per-user row stays (it is the app's generic
--     per-user channel and it is what the V2.12/V2.13 assertions pin), and a
--     store-scoped row is written beside it so the seller actually sees it.
--     The duplication is deliberate and it is the cheap side of the trade: two
--     rows nobody reads is worse than two rows that agree.
--
-- ⚠️  WRITTEN AND **NOT APPLIED** as of 2026-09-28 — see
--     `supabase/MIGRATIONS_LIVE_STATUS.md`, and apply it through the SQL
--     Editor like the rest of that table (never `supabase db push`).
--
-- WHY THE MEASUREMENTS ARE ON THE REQUEST (and why they are the EXTERNAL ones):
--   This is the answer to "the seller shouldn't have to type 3D numbers". They
--   don't. They answer a question they can answer with a ruler, and the tooling
--   turns that into the declaration the contract needs. The four fields are the
--   same four the seller form already asks for in "3D & Fit", with one
--   difference that is easy to get wrong and expensive to get wrong:
--
--     `products.last_length_mm` is the INTERNAL last length — a foot sits in it,
--     and it is what the fit verdict compares. The mesh declaration is the
--     EXTERNAL length — what the shoe measures outside, which is what the
--     renderer scales. SHOE_MODEL_AUTHORING_GUIDE.md §5 measures the gap at
--     8–15 mm on leather shoes and says plainly that confusing them "makes the
--     shoe either oversize or misleading". So this column set is the OUTSIDE
--     measurement, and the column names say so (`external_`).
--
-- ⚠️ NO WRITE POLICIES, ON PURPOSE (the `pickup_reservations` precedent):
--   The rules here are multi-row invariants — one open request per product, no
--   request for a product that already has a live model, only the store's owner
--   may file one. A policy can only check the row being written, so an INSERT
--   policy would let a crafted client bypass every one of them. The RPCs are
--   SECURITY DEFINER and are the only way in; the pgTAP suite asserts that there
--   are zero INSERT/UPDATE/DELETE policies for sellers.
-- ══════════════════════════════════════════════════════════════════

-- ── Table ────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.shoe_model_requests (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  -- What the ask is about. `store_id` is denormalised deliberately: the RLS
  -- policy and the admin queue would otherwise join `products → stores` on
  -- every row, and the RPC is the only writer, so it cannot drift from
  -- `products.store_id` the way a hand-written row could.
  product_id         uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  store_id           uuid NOT NULL REFERENCES public.stores(id) ON DELETE CASCADE,
  requested_by       uuid NOT NULL REFERENCES auth.users(id),

  status             text NOT NULL DEFAULT 'requested',

  -- The seller's half: what they measured, with a ruler, outside the shoe.
  -- `external_length_mm` is the one required number, for the same reason the
  -- fit spec requires a length — it is what everything else hangs off, and it
  -- is the number the normaliser scales the mesh to.
  external_length_mm numeric NOT NULL,
  external_width_mm  numeric,
  heel_height_mm     numeric,
  measured_size_eu   numeric,
  note               text,

  -- The team's half.
  assigned_to        uuid REFERENCES auth.users(id),
  admin_note         text,
  -- BIGINT, not uuid: `product_models.id` is a GENERATED BY DEFAULT AS IDENTITY
  -- column. Getting this wrong is not theoretical — `product_models.variant_id`
  -- shipped as `BIGINT REFERENCES product_variants(id)` and the first apply
  -- failed with 42804 because the hosted `product_variants.id` is UUID. The
  -- type was checked against the CREATE TABLE, not from memory.
  model_id           bigint REFERENCES public.product_models(id),
  reviewed_by        uuid REFERENCES auth.users(id),
  reviewed_at        timestamptz,
  created_at         timestamptz NOT NULL DEFAULT timezone('utc'::text, now()),
  updated_at         timestamptz NOT NULL DEFAULT timezone('utc'::text, now())
);

-- The constraints are written explicitly (inline + DROP/ADD) because a table is
-- NOT re-created by re-running a migration: an inline CHECK beside a
-- `CREATE TABLE IF NOT EXISTS` is a silent no-op the second time, which is the
-- trap `MIGRATIONS_LIVE_STATUS.md` names. Written this way the file converges
-- whether the table is new or was created by hand.
ALTER TABLE public.shoe_model_requests
  DROP CONSTRAINT IF EXISTS shoe_model_requests_status_check;
ALTER TABLE public.shoe_model_requests
  ADD CONSTRAINT shoe_model_requests_status_check
  CHECK (status IN ('requested', 'in_progress', 'fulfilled', 'declined', 'cancelled'));

-- The bounds mirror the code, so a typo cannot be saved: `external_length_mm`
-- uses the mesh declaration's band (`glb_validator.dart` kPlausibleLengthMinMm/
-- MaxMm — this number BECOMES the declaration), and the other three use
-- `fit_engine.dart`'s bands, which are also the CHECKs on `products`.
ALTER TABLE public.shoe_model_requests
  DROP CONSTRAINT IF EXISTS shoe_model_requests_external_length_mm_check;
ALTER TABLE public.shoe_model_requests
  ADD CONSTRAINT shoe_model_requests_external_length_mm_check
  CHECK (external_length_mm BETWEEN 100 AND 400);

ALTER TABLE public.shoe_model_requests
  DROP CONSTRAINT IF EXISTS shoe_model_requests_external_width_mm_check;
ALTER TABLE public.shoe_model_requests
  ADD CONSTRAINT shoe_model_requests_external_width_mm_check
  CHECK (external_width_mm IS NULL OR external_width_mm BETWEEN 40 AND 200);

ALTER TABLE public.shoe_model_requests
  DROP CONSTRAINT IF EXISTS shoe_model_requests_heel_height_mm_check;
ALTER TABLE public.shoe_model_requests
  ADD CONSTRAINT shoe_model_requests_heel_height_mm_check
  CHECK (heel_height_mm IS NULL OR heel_height_mm BETWEEN 0 AND 80);

ALTER TABLE public.shoe_model_requests
  DROP CONSTRAINT IF EXISTS shoe_model_requests_measured_size_eu_check;
ALTER TABLE public.shoe_model_requests
  ADD CONSTRAINT shoe_model_requests_measured_size_eu_check
  CHECK (measured_size_eu IS NULL OR measured_size_eu BETWEEN 22 AND 48);

-- ⚠️ "fulfilled" must NAME the model it was fulfilled with.
--
-- A status an admin can flip by hand is a status that lies, and the seller
-- reads this one as "it's done". Tying it to `model_id` means the only way to
-- close a request as fulfilled is to have actually published a model — which
-- is also what makes the count of open requests worth anything.
ALTER TABLE public.shoe_model_requests
  DROP CONSTRAINT IF EXISTS shoe_model_requests_fulfilled_needs_model;
ALTER TABLE public.shoe_model_requests
  ADD CONSTRAINT shoe_model_requests_fulfilled_needs_model
  CHECK (status <> 'fulfilled' OR model_id IS NOT NULL);

-- ── Indexes ──────────────────────────────────────────────────────

-- ⚠️ ONE OPEN ASK PER PRODUCT.
--
-- Without this, a seller who taps twice files two identical jobs and the queue
-- shows two — the `uq_product_models_default_version` lesson, applied before it
-- could be learned the hard way. Partial, so the history of closed requests
-- (and a re-ask after a decline) is unlimited.
CREATE UNIQUE INDEX IF NOT EXISTS uq_shoe_model_requests_open
  ON public.shoe_model_requests (product_id)
  WHERE status IN ('requested', 'in_progress');

CREATE INDEX IF NOT EXISTS idx_shoe_model_requests_status
  ON public.shoe_model_requests (status);
CREATE INDEX IF NOT EXISTS idx_shoe_model_requests_store
  ON public.shoe_model_requests (store_id, created_at DESC);

-- Keep `updated_at` honest — the shared trigger function the rest of the schema
-- uses (`product_models` has the same one).
DROP TRIGGER IF EXISTS trg_shoe_model_requests_updated_at ON public.shoe_model_requests;
CREATE TRIGGER trg_shoe_model_requests_updated_at
  BEFORE UPDATE ON public.shoe_model_requests
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ── RLS ──────────────────────────────────────────────────────────
ALTER TABLE public.shoe_model_requests ENABLE ROW LEVEL SECURITY;

-- The seller sees their store's asks. Read-only: every write is an RPC above.
DROP POLICY IF EXISTS "Sellers can view their store's model requests"
  ON public.shoe_model_requests;
CREATE POLICY "Sellers can view their store's model requests"
  ON public.shoe_model_requests FOR SELECT
  USING (
    public.is_admin()
    OR EXISTS (
      SELECT 1 FROM public.stores s
       WHERE s.id = store_id
         AND s.owner_id = auth.uid()
    )
  );

-- Admins run the queue, and run it from the app: assign it to themselves, keep
-- a note. The state transitions still go through the RPCs, so "fulfilled"
-- cannot be set without a model even by an admin.
DROP POLICY IF EXISTS "Admins can update model requests" ON public.shoe_model_requests;
CREATE POLICY "Admins can update model requests"
  ON public.shoe_model_requests FOR UPDATE
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

-- ── The seller's bell: allow the notice the closing RPCs write ───
--
-- `seller_notifications.type` was CHECKed against its first four values, and
-- the seller's bell is where a seller actually looks — so the two closing RPCs
-- cannot write a row there until this constraint admits one. Written the house
-- way (DROP then ADD, both idempotent) so a re-run converges rather than
-- erroring on a constraint that is already correct.
--
-- 'new_message' is in the list for a reason that is not this feature: the
-- client has been inserting that type since the messaging work
-- (`SellerNotificationService.createNewMessage`), and the LIVE project's copy
-- of this constraint does not admit it — checked 2026-09-28, the table holds 39
-- `new_order` and 1 `low_stock` rows and ZERO `new_message` rows, because that
-- method's `catch` swallows the failure with a debugPrint. Relaxing this
-- constraint for the model notice while leaving the neighbouring value out
-- would mean writing the same ALTER twice.
--
-- The allowed set is pinned from the Dart side too, by
-- `test/services/model_notice_contract_test.dart`, which reads this constraint
-- back out of the file: there is no compiler between a plpgsql CHECK and a Dart
-- `switch`. Getting this wrong is worse than a missing notification, and that is
-- the reason it is called out here rather than left to review — the insert runs
-- INSIDE the transaction that closes the ask, so a refused type means the
-- seller's request stays OPEN because the database declined to file a notice
-- about it.
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
      'model_request'
    )
  );

-- ── RPC: file the ask (seller) ───────────────────────────────────
CREATE OR REPLACE FUNCTION public.request_shoe_model(
  p_product_id         uuid,
  p_external_length_mm numeric,
  p_external_width_mm  numeric DEFAULT NULL,
  p_heel_height_mm     numeric DEFAULT NULL,
  p_measured_size_eu   numeric DEFAULT NULL,
  p_note               text    DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id  uuid := auth.uid();
  v_store_id uuid;
  v_owner    uuid;
  v_open     uuid;
  -- ⚠️ BIGINT, like `product_models.id` itself — NOT uuid like every other id in
  -- this function. This variable was declared `uuid` in the first version of
  -- this file and the mistake hid behind the common path for a day: the SELECT
  -- below only assigns it when it FINDS a live model, so asking about a product
  -- without one worked perfectly and asking about a product WITH one raised
  -- `invalid input syntax for type uuid: "2"` — a Postgres trying to cast model
  -- id 2 into a uuid. CI's `Supabase Migrations` job is what found it, on the
  -- first run that ever executed this function (`request_shoe_model`, pgTAP
  -- assertion 21). Same trap as `model_id` in the table below, in a local
  -- variable this time.
  v_live     bigint;
  v_new_id   uuid;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- The product must exist, and the caller must own its store (admins file asks
  -- on a seller's behalf, which is how a phone call becomes a row).
  SELECT p.store_id, s.owner_id INTO v_store_id, v_owner
    FROM public.products p
    JOIN public.stores s ON s.id = p.store_id
   WHERE p.id = p_product_id;

  IF v_store_id IS NULL THEN
    RETURN json_build_object('success', false, 'message', 'That product no longer exists.');
  END IF;

  IF v_owner <> v_user_id AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'Only the store owner can request a 3D model'
      USING ERRCODE = '42501';
  END IF;

  -- Asked in the seller's own language, so the sentence says what to do.
  IF p_external_length_mm IS NULL
     OR p_external_length_mm < 100
     OR p_external_length_mm > 400 THEN
    RETURN json_build_object(
      'success', false,
      'message', 'Measure the pair from the back of the heel to the tip of the toe and enter it in millimetres — it should be somewhere between 100 and 400 mm.'
    );
  END IF;

  -- Already has one live: nothing to ask for.
  SELECT pm.id INTO v_live
    FROM public.product_models pm
   WHERE pm.product_id = p_product_id
     AND pm.status = 'active'
   LIMIT 1;

  IF v_live IS NOT NULL THEN
    RETURN json_build_object(
      'success', false,
      'message', 'This product already has a 3D model attached, so there is nothing to request.'
    );
  END IF;

  -- The partial unique index would raise 23505; answering in json keeps the
  -- message one the seller can act on instead of a constraint name.
  SELECT r.id INTO v_open
    FROM public.shoe_model_requests r
   WHERE r.product_id = p_product_id
     AND r.status IN ('requested', 'in_progress')
   LIMIT 1;

  IF v_open IS NOT NULL THEN
    RETURN json_build_object(
      'success', false,
      'message', 'You have already asked for a 3D model for this product. It is with the CUFMAI team.'
    );
  END IF;

  INSERT INTO public.shoe_model_requests (
    product_id, store_id, requested_by,
    external_length_mm, external_width_mm, heel_height_mm, measured_size_eu, note
  ) VALUES (
    p_product_id, v_store_id, v_user_id,
    p_external_length_mm, p_external_width_mm, p_heel_height_mm, p_measured_size_eu,
    nullif(btrim(coalesce(p_note, '')), '')
  )
  RETURNING id INTO v_new_id;

  RETURN json_build_object(
    'success', true,
    'request_id', v_new_id,
    'message', 'Request sent. The CUFMAI team will build the 3D model for this product and let you know here when it is ready.'
  );
END;
$$;

GRANT EXECUTE ON FUNCTION
  public.request_shoe_model(uuid, numeric, numeric, numeric, numeric, text)
  TO authenticated;

COMMENT ON FUNCTION
  public.request_shoe_model(uuid, numeric, numeric, numeric, numeric, text) IS
  'Seller-filed ask for a modelled 3D shoe. Refuses a product that already has
   an active model, and refuses a second open request for the same product
   (uq_shoe_model_requests_open). Takes the EXTERNAL length in millimetres —
   the figure the renderer scales to, not the internal last length the fit
   verdict uses.';

-- ── RPC: withdraw the ask (seller) ───────────────────────────────
CREATE OR REPLACE FUNCTION public.cancel_shoe_model_request(p_request_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_request record;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT * INTO v_request
    FROM public.shoe_model_requests
   WHERE id = p_request_id;

  IF v_request IS NULL THEN
    RETURN json_build_object('success', false, 'message', 'That request no longer exists.');
  END IF;

  IF NOT public.is_admin()
     AND NOT EXISTS (
       SELECT 1 FROM public.stores s
        WHERE s.id = v_request.store_id AND s.owner_id = auth.uid()
     ) THEN
    RAISE EXCEPTION 'Only the store owner can cancel this request'
      USING ERRCODE = '42501';
  END IF;

  IF v_request.status NOT IN ('requested', 'in_progress') THEN
    RETURN json_build_object(
      'success', false,
      'message', 'This request has already been ' || v_request.status || '.'
    );
  END IF;

  UPDATE public.shoe_model_requests
     SET status = 'cancelled',
         reviewed_by = auth.uid(),
         reviewed_at = now(),
         updated_at = now()
   WHERE id = p_request_id;

  RETURN json_build_object('success', true, 'message', 'Request withdrawn.');
END;
$$;

GRANT EXECUTE ON FUNCTION public.cancel_shoe_model_request(uuid) TO authenticated;

COMMENT ON FUNCTION public.cancel_shoe_model_request(uuid) IS
  'The store owner (or an admin) withdraws an open 3D model request. A closed
   request cannot be cancelled — it is history, and the partial unique index
   only constrains the open ones.';

-- ── RPC: take the ask (admin) ────────────────────────────────────
CREATE OR REPLACE FUNCTION public.claim_shoe_model_request(p_request_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Only admins can claim model requests';
  END IF;

  UPDATE public.shoe_model_requests
     SET status = 'in_progress',
         assigned_to = auth.uid(),
         updated_at = now()
   WHERE id = p_request_id
     AND status = 'requested';

  IF NOT FOUND THEN
    RETURN json_build_object(
      'success', false,
      'message', 'Request not found, or somebody has already taken it.'
    );
  END IF;

  RETURN json_build_object('success', true, 'message', 'Request claimed.');
END;
$$;

GRANT EXECUTE ON FUNCTION public.claim_shoe_model_request(uuid) TO authenticated;

COMMENT ON FUNCTION public.claim_shoe_model_request(uuid) IS
  'Admin-only: moves a request from requested to in_progress and records who
   took it, so a two-admin team does not both model the same shoe.';

-- ── RPC: close the ask against a real model (admin) ──────────────
CREATE OR REPLACE FUNCTION public.fulfil_shoe_model_request(
  p_request_id uuid,
  p_model_id   bigint,
  p_admin_note text DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_request record;
  v_model   record;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Only admins can fulfil model requests';
  END IF;

  SELECT * INTO v_request
    FROM public.shoe_model_requests
   WHERE id = p_request_id;

  IF v_request IS NULL THEN
    RETURN json_build_object('success', false, 'message', 'That request no longer exists.');
  END IF;

  IF v_request.status NOT IN ('requested', 'in_progress') THEN
    RETURN json_build_object(
      'success', false,
      'message', 'This request has already been ' || v_request.status || '.'
    );
  END IF;

  -- ⚠️ The model has to be the one this request is about, and it has to be
  -- live. This is what stops "fulfilled" from being a note somebody typed:
  -- the constraint on the table requires a model_id, and this requires that
  -- model to be the right one and published.
  SELECT * INTO v_model
    FROM public.product_models
   WHERE id = p_model_id;

  IF v_model IS NULL THEN
    RETURN json_build_object('success', false, 'message', 'That model no longer exists.');
  END IF;

  IF v_model.product_id <> v_request.product_id THEN
    RETURN json_build_object(
      'success', false,
      'message', 'That model belongs to a different product.'
    );
  END IF;

  IF v_model.status <> 'active' THEN
    RETURN json_build_object(
      'success', false,
      'message', 'That model is still a ' || v_model.status || ' — publish it through the validator first, then close this request.'
    );
  END IF;

  UPDATE public.shoe_model_requests
     SET status = 'fulfilled',
         model_id = p_model_id,
         admin_note = nullif(btrim(coalesce(p_admin_note, '')), ''),
         reviewed_by = auth.uid(),
         reviewed_at = now(),
         updated_at = now()
   WHERE id = p_request_id;

  -- ⚠️ P3 (roadmap V2.12): TELL THE SELLER, in the SAME TRANSACTION.
  --
  -- Before this, a fulfilled ask was silent: the stateful row in the product
  -- action sheet is how a seller learns, and that means opening the sheet. The
  -- whole point of the request flow is that the seller cannot do the modelling
  -- — so leaving them to poll a sheet for a week of work is the same gap the
  -- row was built to close, one level down.
  --
  -- Same transaction, deliberately: a closed ask that nobody was told about is
  -- the one outcome this must not produce, so the notification and the status
  -- change land together or not at all. (The alternative — a notification in a
  -- separate call from the app — would also be forgeable and skippable, which
  -- is why the RPC is the writer rather than the admin screen.)
  --
  -- The recipient is the person who ASKED (`requested_by`, the filer), not the
  -- store's owner: for this table they are the same person — `request_shoe_model`
  -- refuses anyone who does not own the store — and the filer stays the right
  -- recipient if that ever changes. The join to `profiles` is the guard the
  -- recipient audit asks for, in its join form: `user_id` is
  -- `NOT NULL REFERENCES profiles(id)`, so a missing profile row would raise
  -- 23503 and take the whole fulfil with it, while this inserts nothing and
  -- lets the close stand. (`requested_by` itself is NOT NULL, so no `IS NOT
  -- NULL` guard is needed — the nullable-recipient sites the audit ratchets are
  -- the `stores.owner_id` / `orders.customer_id` ones.)
  --
  -- The optional tail quotes `p_admin_note`, the ARGUMENT — not
  -- `v_request.admin_note`. `v_request` is the snapshot read before the UPDATE
  -- above, so its note is the PREVIOUS one; the seller reads this sentence, and
  -- stale would be worse than absent.
  INSERT INTO public.notifications (user_id, category, title, message, metadata)
  SELECT p.id,
         'models',
         'Your 3D model is ready',
         'Your 3D model for ' || COALESCE(prod.name, 'your product') ||
         ' is live. Customers can see it on the product page.' ||
         CASE WHEN nullif(btrim(coalesce(p_admin_note, '')), '') IS NOT NULL
              THEN ' From the team: ' || btrim(p_admin_note)
              ELSE '' END,
         jsonb_build_object(
           'request_id', p_request_id,
           'product_id', v_request.product_id
         )
    FROM public.profiles p
    JOIN public.products prod ON prod.id = v_request.product_id
   WHERE p.id = v_request.requested_by;

  -- ⚠️ V2.14: AND THE SAME NEWS TO THE BELL THE SELLER ACTUALLY READS.
  --
  -- The row above is addressed to the seller's USER, in `public.notifications`
  -- — the app's generic per-user channel. The seller app never renders that
  -- feed: it belongs to the customer shell, and a seller's session lands in
  -- `SellerShell`, whose bell reads `public.seller_notifications`, keyed by
  -- STORE. So the notice above was correct and unreadable at the same time.
  -- This row is the one the seller sees, and it is why the type constraint
  -- above had to widen.
  --
  -- Deliberately NOT a `FROM … WHERE` guard like its sibling: there is no
  -- recipient row here that could be missing. `store_id` is NOT NULL and
  -- references `stores`, and the store is known to exist because the request
  -- row carries it; the product name comes from a scalar subquery, so a product
  -- that somehow vanished costs the name and not the row. Nothing in this
  -- insert can fail, which matters because it runs inside the transaction that
  -- closes the ask — the recipient audit's rule in its simplest form: a notice
  -- must never decide whether the work lands.
  --
  -- `reference_id` is the PRODUCT, not the request: the tap opens the product's
  -- actions sheet, where the request row and the model both live — the same
  -- destination the per-user row's `metadata.product_id` names.
  INSERT INTO public.seller_notifications
    (store_id, type, title, body, reference_id, metadata)
  VALUES (
    v_request.store_id,
    'model_request',
    'Your 3D model is ready',
    COALESCE(
      (SELECT name FROM public.products WHERE id = v_request.product_id),
      'Your product'
    ) || ' — it is live on the product page.' ||
    CASE WHEN nullif(btrim(coalesce(p_admin_note, '')), '') IS NOT NULL
         THEN ' From the team: ' || btrim(p_admin_note)
         ELSE '' END,
    v_request.product_id,
    jsonb_build_object(
      'request_id', p_request_id,
      'product_id', v_request.product_id
    )
  );

  RETURN json_build_object(
    'success', true,
    'message', 'Request closed against a live model.'
  );
END;
$$;

GRANT EXECUTE ON FUNCTION
  public.fulfil_shoe_model_request(uuid, bigint, text) TO authenticated;

COMMENT ON FUNCTION public.fulfil_shoe_model_request(uuid, bigint, text) IS
  'Admin-only: closes a request as fulfilled against a model that belongs to the
   same product AND has status = active. Without both checks "fulfilled" would be
   a claim rather than a fact. Tells the seller in the same transaction, on both
   the per-user and the seller-bell channels (V2.12, V2.14).';

-- ── RPC: close the ask with a reason (admin) ─────────────────────
CREATE OR REPLACE FUNCTION public.decline_shoe_model_request(
  p_request_id uuid,
  p_reason     text DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_recipient uuid;
  v_product   uuid;
  v_store     uuid;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Only admins can decline model requests';
  END IF;

  -- `RETURNING … INTO` rather than a second SELECT: the update is where the
  -- recipient and the product become known, and reading them off the row this
  -- statement just wrote keeps the two in step by construction. `FOUND` is
  -- unchanged by the INTO clause, so the guard below still means "nothing was
  -- declined".
  UPDATE public.shoe_model_requests
     SET status = 'declined',
         admin_note = nullif(btrim(coalesce(p_reason, '')), ''),
         reviewed_by = auth.uid(),
         reviewed_at = now(),
         updated_at = now()
   WHERE id = p_request_id
     AND status IN ('requested', 'in_progress')
  RETURNING requested_by, product_id, store_id
       INTO v_recipient, v_product, v_store;

  IF NOT FOUND THEN
    RETURN json_build_object(
      'success', false,
      'message', 'Request not found or already closed.'
    );
  END IF;

  -- ⚠️ P4 (roadmap V2.13): THE OTHER ENDING TELLS THE SELLER TOO.
  --
  -- P3 notified on `fulfilled`; this is the same act for the ending that is not
  -- good news, and it was the larger silence of the two. "The team could not
  -- make one" is the one outcome a seller most needs early — a decline that
  -- sits unread until they happen to open the product's action sheet is a week
  -- of them waiting on something that already stopped. Their move afterwards is
  -- to ask again, which the partial unique index allows precisely because a
  -- declined ask is closed rather than deleted.
  --
  -- The reason is the reason `p_reason` is asked for at all, so it travels with
  -- the notice: the admin screen refuses to send a decline without one
  -- (`manage_shoe_model_requests_screen.dart`), and a notice that dropped it
  -- would make that requirement cosmetic. A blank reason is still possible from
  -- an older client or a direct RPC call, and the message degrades to a
  -- sentence that stands on its own rather than to a dangling colon.
  --
  -- Same recipient rule, same join guard, same transaction as P3 — see the
  -- comment there; the only difference is which column of the row it reads.
  INSERT INTO public.notifications (user_id, category, title, message, metadata)
  SELECT p.id,
         'models',
         'Your 3D model request was declined',
         'The team could not make a 3D model for ' ||
         COALESCE(prod.name, 'your product') || '.' ||
         CASE WHEN nullif(btrim(coalesce(p_reason, '')), '') IS NOT NULL
              THEN ' They said: ' || btrim(p_reason)
              ELSE '' END ||
         ' You can ask again from the product''s actions.',
         jsonb_build_object(
           'request_id', p_request_id,
           'product_id', v_product
         )
    FROM public.profiles p
    JOIN public.products prod ON prod.id = v_product
   WHERE p.id = v_recipient;

  -- The same row for the bell the seller actually reads, for the reasons
  -- spelled out in the fulfil RPC above, including why it is not a
  -- `FROM … WHERE` guard and why `reference_id` is the product rather than the
  -- request. `store_id` arrives in this RPC's own `RETURNING` clause for the
  -- same reason `requested_by` does: the update is where the row becomes known,
  -- and reading all three fields off the row it just wrote keeps them in step by
  -- construction.
  INSERT INTO public.seller_notifications
    (store_id, type, title, body, reference_id, metadata)
  VALUES (
    v_store,
    'model_request',
    'Your 3D model request was declined',
    COALESCE(
      (SELECT name FROM public.products WHERE id = v_product),
      'Your product'
    ) || ' — the team could not make a model for it.' ||
    CASE WHEN nullif(btrim(coalesce(p_reason, '')), '') IS NOT NULL
         THEN ' They said: ' || btrim(p_reason)
         ELSE '' END ||
    ' You can ask again from the product''s actions.',
    v_product,
    jsonb_build_object(
      'request_id', p_request_id,
      'product_id', v_product
    )
  );

  RETURN json_build_object('success', true, 'message', 'Request declined.');
END;
$$;

GRANT EXECUTE ON FUNCTION public.decline_shoe_model_request(uuid, text) TO authenticated;

COMMENT ON FUNCTION public.decline_shoe_model_request(uuid, text) IS
  'Admin-only: closes a request as declined with a reason the seller reads, and
   notifies that seller in the same transaction (V2.13) — twice, since V2.14:
   the per-user row in public.notifications and the store-scoped row in
   public.seller_notifications that the seller''s own bell actually renders.
   The seller can ask again afterwards, which is why the open-request unique
   index is partial.';

-- ── Device gate ──────────────────────────────────────────────────
-- The table is private business data (what a seller asked for, what the team
-- wrote back), so it must be gated like `deletion_requests` rather than
-- exempted like `product_models` — a customer never reads it.
--
-- The gate's policy sweep only covers the tables that exist when it runs, so a
-- migration that adds an RLS table has to call it. This is the documented
-- procedure (`pickup_reservations` does the same), and the pgTAP invariant
-- ("every RLS table is either device-gated or explicitly exempt") fails if it
-- is forgotten — which is exactly how `product_models` was caught on
-- 2026-09-28, an hour after the V2.1 table shipped.
SELECT public.install_device_gate_policies();

-- ══════════════════════════════════════════════════════════════════
-- VERIFICATION (run after applying, through the SQL Editor or
-- `supabase db query --linked` — never `supabase db push`)
--
-- The table is device-gated and NOT exempt (must list exactly one row):
--   select policyname from pg_policies
--    where schemaname = 'public' and tablename = 'shoe_model_requests'
--      and policyname = 'Require a trusted device';
--   select 'shoe_model_requests' = any (public.device_gate_exempt_tables());
--
-- No seller write policies — the RPCs are the only way in (must be 0):
--   select count(*) from pg_policies
--    where schemaname = 'public' and tablename = 'shoe_model_requests'
--      and cmd in ('INSERT', 'UPDATE', 'DELETE') and policyname not like 'Admins%';
--
-- One open ask per product (must list 1):
--   select indexname from pg_indexes
--    where schemaname = 'public' and tablename = 'shoe_model_requests'
--      and indexname = 'uq_shoe_model_requests_open';
--
-- The queue still empty, and nothing else disturbed:
--   select count(*) from public.shoe_model_requests;
--
-- The seller's bell admits the new type, and still admits the old ones (the
-- constraint definition must list all six values):
--   select pg_get_constraintdef(oid) from pg_constraint
--    where conrelid = 'public.seller_notifications'::regclass
--      and conname = 'seller_notifications_type_check';
--
-- Full proof-of-behaviour, including the four invariants above:
-- supabase/tests/shoe_model_requests.test.sql
-- ══════════════════════════════════════════════════════════════════
