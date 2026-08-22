-- ══════════════════════════════════════════════════════════════════
-- BANNERS TABLE — admin-managed hero banners for the customer home
-- ══════════════════════════════════════════════════════════════════
-- Banners are displayed in the HomeHero carousel on the customer home
-- screen. The admin app manages them (CRUD). The customer app only
-- reads active, in-schedule banners.
--
-- Storage bucket: `banners` (public read — mirrors product-images pattern)
-- ══════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.banners (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    image_url       TEXT NOT NULL,
    eyebrow_text    TEXT,
    title           TEXT NOT NULL,
    cta_label       TEXT,
    link_type       TEXT NOT NULL DEFAULT 'none'
                        CHECK (link_type IN ('category', 'product', 'url', 'none')),
    link_value      TEXT,
    display_order   INTEGER NOT NULL DEFAULT 0,
    is_active       BOOLEAN NOT NULL DEFAULT true,
    starts_at       TIMESTAMPTZ,
    ends_at         TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

ALTER TABLE public.banners ENABLE ROW LEVEL SECURITY;

-- Index for the common query: active banners in display order
CREATE INDEX IF NOT EXISTS banners_active_order_idx ON public.banners (is_active, display_order);

-- ══════════════════════════════════════════════════════════════════
-- RLS POLICIES
-- ══════════════════════════════════════════════════════════════════

-- Public/anon can only read banners that are:
--   1. is_active = true
--   2. starts_at is null OR starts_at <= now()
--   3. ends_at is null OR ends_at >= now()
-- This enforces visibility at the database level, not just app-side filters.
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Public can view active banners' AND tablename = 'banners') THEN
        CREATE POLICY "Public can view active banners"
            ON public.banners FOR SELECT
            USING (
                is_active = true
                AND (starts_at IS NULL OR starts_at <= now())
                AND (ends_at IS NULL OR ends_at >= now())
            );
    END IF;
END $$;

-- Admins can read ALL banners (including inactive, scheduled, expired)
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Admins can read all banners' AND tablename = 'banners') THEN
        CREATE POLICY "Admins can read all banners"
            ON public.banners FOR SELECT
            USING (
                EXISTS (
                    SELECT 1 FROM public.profiles
                    WHERE id = auth.uid() AND role = 'admin'
                )
            );
    END IF;
END $$;

-- Admins can insert banners
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Admins can insert banners' AND tablename = 'banners') THEN
        CREATE POLICY "Admins can insert banners"
            ON public.banners FOR INSERT
            WITH CHECK (
                EXISTS (
                    SELECT 1 FROM public.profiles
                    WHERE id = auth.uid() AND role = 'admin'
                )
            );
    END IF;
END $$;

-- Admins can update banners
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Admins can update banners' AND tablename = 'banners') THEN
        CREATE POLICY "Admins can update banners"
            ON public.banners FOR UPDATE
            USING (
                EXISTS (
                    SELECT 1 FROM public.profiles
                    WHERE id = auth.uid() AND role = 'admin'
                )
            );
    END IF;
END $$;

-- Admins can delete banners
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Admins can delete banners' AND tablename = 'banners') THEN
        CREATE POLICY "Admins can delete banners"
            ON public.banners FOR DELETE
            USING (
                EXISTS (
                    SELECT 1 FROM public.profiles
                    WHERE id = auth.uid() AND role = 'admin'
                )
            );
    END IF;
END $$;

-- ══════════════════════════════════════════════════════════════════
-- STORAGE BUCKET
-- ══════════════════════════════════════════════════════════════════
-- Create the `banners` storage bucket (public read, same pattern as
-- product-images and store-assets).
--
-- NOTE: Supabase Storage buckets cannot be created via SQL migration.
-- Run this via the Supabase Dashboard or the Storage API after applying
-- this migration:
--
--   supabase storage create-bucket banners --public
--
-- Or via the Dashboard: Storage → New bucket →
--   Name: banners
--   Public: yes (toggle on)
--   File size limit: 5MB (or match product-images)
--   Allowed MIME types: image/png, image/jpeg, image/webp
-- ══════════════════════════════════════════════════════════════════

-- ══════════════════════════════════════════════════════════════════
-- STORAGE RLS POLICIES
-- ══════════════════════════════════════════════════════════════════
-- Public read for all banner images (same as product-images bucket).
-- Admin write (upload/delete) — matches the existing admin auth pattern.

-- Public can read banner images
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Public can view banner images' AND tablename = 'objects') THEN
        CREATE POLICY "Public can view banner images"
            ON storage.objects FOR SELECT
            USING (bucket_id = 'banners');
    END IF;
END $$;

-- Admins can upload banner images
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Admins can upload banner images' AND tablename = 'objects') THEN
        CREATE POLICY "Admins can upload banner images"
            ON storage.objects FOR INSERT
            WITH CHECK (
                bucket_id = 'banners'
                AND EXISTS (
                    SELECT 1 FROM public.profiles
                    WHERE id = auth.uid() AND role = 'admin'
                )
            );
    END IF;
END $$;

-- Admins can update banner images
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Admins can update banner images' AND tablename = 'objects') THEN
        CREATE POLICY "Admins can update banner images"
            ON storage.objects FOR UPDATE
            USING (
                bucket_id = 'banners'
                AND EXISTS (
                    SELECT 1 FROM public.profiles
                    WHERE id = auth.uid() AND role = 'admin'
                )
            );
    END IF;
END $$;

-- Admins can delete banner images
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Admins can delete banner images' AND tablename = 'objects') THEN
        CREATE POLICY "Admins can delete banner images"
            ON storage.objects FOR DELETE
            USING (
                bucket_id = 'banners'
                AND EXISTS (
                    SELECT 1 FROM public.profiles
                    WHERE id = auth.uid() AND role = 'admin'
                )
            );
    END IF;
END $$;
