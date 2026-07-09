-- ══════════════════════════════════════════════════════════════════
-- Migration: Tighten products RLS to verify store_id ownership
-- Date: July 9, 2026
-- Purpose: The existing products INSERT/UPDATE/DELETE policies only
--          check role = 'seller' OR role = 'admin', but don't verify
--          that the product's store_id belongs to a store owned by
--          the current user. This means a seller could theoretically
--          insert/update/delete products in another seller's store.
--
-- Fix: Replace the role-only policies with ones that also verify
--      store_id ownership via the stores table.
-- ══════════════════════════════════════════════════════════════════

-- Step 1: Drop the existing policies
DROP POLICY IF EXISTS "Sellers and Admins can insert products" ON public.products;
DROP POLICY IF EXISTS "Sellers and Admins can update products" ON public.products;
DROP POLICY IF EXISTS "Sellers and Admins can delete products" ON public.products;

-- Step 2: Create tightened INSERT policy
-- Sellers can only insert products into their own store(s).
-- Admins can insert into any store.
CREATE POLICY "Sellers can insert into own store, admins any"
    ON public.products FOR INSERT WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.profiles
            WHERE id = auth.uid() AND role = 'admin'
        )
        OR EXISTS (
            SELECT 1 FROM public.stores
            WHERE id = store_id AND owner_id = auth.uid()
        )
    );

-- Step 3: Create tightened UPDATE policy
-- Sellers can only update products in their own store(s).
-- Admins can update any product.
CREATE POLICY "Sellers can update own store products, admins any"
    ON public.products FOR UPDATE USING (
        EXISTS (
            SELECT 1 FROM public.profiles
            WHERE id = auth.uid() AND role = 'admin'
        )
        OR EXISTS (
            SELECT 1 FROM public.stores
            WHERE id = store_id AND owner_id = auth.uid()
        )
    );

-- Step 4: Create tightened DELETE policy
-- Sellers can only delete products in their own store(s).
-- Admins can delete any product.
CREATE POLICY "Sellers can delete own store products, admins any"
    ON public.products FOR DELETE USING (
        EXISTS (
            SELECT 1 FROM public.profiles
            WHERE id = auth.uid() AND role = 'admin'
        )
        OR EXISTS (
            SELECT 1 FROM public.stores
            WHERE id = store_id AND owner_id = auth.uid()
        )
    );

-- Verify the new policies:
-- SELECT policyname, cmd, qual, with_check FROM pg_policies WHERE tablename = 'products';
