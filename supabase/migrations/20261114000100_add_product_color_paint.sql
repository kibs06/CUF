-- Mission: swipe-the-colour, see-it-in-3D — Phase A (paint storage).
--
-- One model per product, painted by the app: each product COLOUR gets one
-- real paint value (`paint_hex`) that the viewers tint the shared mesh with
-- live. This table is that value's home.
--
-- WHY A SEPARATE TABLE, not a column on `product_color_images`: that table
-- holds one row per PHOTO (a colour repeats per gallery image), while paint
-- is one row per COLOUR. A column there would either duplicate the hex on
-- every photo row or disagree with itself; the PK here —
-- (product_id, color_name) — says "one paint per colour" where a photo
-- table cannot. `color_name` (TEXT, exact spelling) is the join key for the
-- same reason the photo table's own migration records: `product_variants.color`
-- stays the single source of truth for colour identity, so no new FK can
-- drift from it.
--
-- WHY NULLABLE-ABSENT rather than defaulted: a colour with no row renders
-- the model AS-AUTHORED (the hero colourway, untouched). A guessed tint —
-- the swatch map's hash fallback included — would show a customer a colour
-- that exists nowhere in reality, which is worse than no tint. The admin
-- portal prefills the picker from the swatch guess; a human confirms the hex.
--
-- RLS mirrors `product_color_images` exactly: paint is catalogue content
-- (like the colour names and photos), world-readable, writable only by the
-- product's own seller and by admins. Device-gate: EXEMPT, same line as
-- `product_color_images` — the product page reads paint beside the photos
-- it already reads, on devices that never ran the native app.

-- ═══════════════════════════════════════════════════════════════════
-- 1. NEW TABLE: product_color_paint
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.product_color_paint (
    product_id      UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    color_name      TEXT NOT NULL,
    paint_hex       TEXT NOT NULL,
    created_at      TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    CONSTRAINT product_color_paint_pkey PRIMARY KEY (product_id, color_name),
    -- A paint value is a web hex or it is nothing: '#1A1A1A' in, 'red' or
    -- '1A1A1A' refused. The viewers parse this straight into a color
    -- factor, and an unparseable row would tint every shoe it touches.
    CONSTRAINT product_color_paint_hex_format CHECK (paint_hex ~ '^#[0-9A-Fa-f]{6}$')
);

ALTER TABLE public.product_color_paint ENABLE ROW LEVEL SECURITY;

-- ═══════════════════════════════════════════════════════════════════
-- 2. ROW LEVEL SECURITY POLICIES (mirrors product_color_images)
-- ═══════════════════════════════════════════════════════════════════

-- Everyone can read paint (public storefront — the product page tints the
-- 3D box with it for anonymous shoppers too).
DROP POLICY IF EXISTS "Product color paint is viewable by everyone"
  ON public.product_color_paint;
CREATE POLICY "Product color paint is viewable by everyone"
    ON public.product_color_paint FOR SELECT USING (true);

-- Sellers can manage paint for their own products.
DROP POLICY IF EXISTS "Sellers can manage their product color paint"
  ON public.product_color_paint;
CREATE POLICY "Sellers can manage their product color paint"
    ON public.product_color_paint FOR ALL USING (
        EXISTS (
            SELECT 1 FROM public.products
            WHERE id = product_id AND seller_id = auth.uid()
        )
    );

-- Admins can manage all paint.
DROP POLICY IF EXISTS "Admins can manage all product color paint"
  ON public.product_color_paint;
CREATE POLICY "Admins can manage all product color paint"
    ON public.product_color_paint FOR ALL USING (public.is_admin());

-- ═══════════════════════════════════════════════════════════════════
-- 3. DEVICE GATE: exempt (catalogue content, like product_color_images)
-- ═══════════════════════════════════════════════════════════════════
-- Full re-declaration, the repo's established pattern (see
-- 20261110070000, 20261111080000): the function is the single list the
-- installer, the verification queries and the pgTAP guard all read, so a
-- new table joins it here or gets gated silently on the next re-run.
CREATE OR REPLACE FUNCTION public.device_gate_exempt_tables()
RETURNS text[]
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT ARRAY[
    -- ── identity / the step-up flow itself ──
    'profiles',
    'trusted_devices',
    'device_secrets',
    'device_enforcement_policy',
    'failed_logins',
    'account_session_log',

    -- ── public catalog: readable by anon already ──
    'products', 'product_images', 'product_variants', 'product_color_images',
    -- Phase A of the colour-paint mission (this file): the per-colour hex
    -- beside the colour names and photos above — read on the same product
    -- page, holding nothing customer-private.
    'product_color_paint',
    'product_customizations', 'product_review_images',
    'stores', 'banners', 'inventory', 'story_entries', 'store_follows',
    'reviews', 'store_reviews', 'review_images', 'product_reviews',
    'payment_fee_config',
    'product_models',
    'foot_scan_jobs',
    'product_ar_effects',
    'review_votes',
    'review_comments',
    'device_tokens'
  ];
$$;

COMMENT ON FUNCTION public.device_gate_exempt_tables() IS
  'Tables deliberately outside the trusted-device gate, each for a concrete '
  'reason (see the comments at each entry). Shared by '
  'install_device_gate_policies() and the pgTAP guard so the two cannot drift.';

-- Re-converge: gate anything still ungated, leave the exempt list alone.
SELECT public.install_device_gate_policies();
