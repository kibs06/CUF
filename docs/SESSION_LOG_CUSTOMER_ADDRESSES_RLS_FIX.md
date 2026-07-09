# Session Log — July 8, 2026 (Customer Addresses RLS Fix)

**Date:** July 8, 2026
**Focus:** Fix customer_addresses RLS policy violation blocking address creation

---

## Issue

Customer tries to save a delivery address → PostgrestException 42501 (insufficient_privilege) on `customer_addresses` INSERT.

## Root Cause

The `20260705_add_customer_addresses.sql` migration created the table **and** the RLS policies, but **the policies were never applied to the live database**. This is the same pattern that caused the July 4 checkout bug (SQL migrations written but not deployed).

## Fix

Created `supabase/migrations/20260708_fix_customer_addresses_rls.sql` with all four CRUD policies (INSERT/SELECT/UPDATE/DELETE) using `user_id = auth.uid()` (NOT `customer_id` — that column doesn't exist on this table).

## Changes Made

| File | Change |
|------|--------|
| `supabase/migrations/20260708_fix_customer_addresses_rls.sql` | Created — DROP IF EXISTS + CREATE all 4 RLS policies |
| `docs/AI_PROJECT_SUMMARY.md` | Updated RLS Policy Matrix (added `customer_addresses` row), SQL Migrations table, Bug Fix History, and Known Issues |

## Additional Fix: shipping_address column

The `20260705_add_customer_addresses.sql` migration also included `ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS shipping_address JSONB;` — this was also never applied. Running order placement failed with `PGRST204: Could not find the 'shipping_address' column of 'orders' in the schema cache`. Applied the ALTER TABLE manually.

## Verification

1. ✅ Ran RLS policy SQL in Supabase SQL Editor — success
2. ✅ Ran `ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS shipping_address JSONB;` — success
3. ✅ Tested in app: saved a new address → succeeded
4. ✅ Tested in app: placed an order with shipping_address → succeeded
