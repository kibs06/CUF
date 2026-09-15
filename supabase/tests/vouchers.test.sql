-- ══════════════════════════════════════════════════════════════════
-- Voucher / coupon code tests (pgTAP) — run by CI via `supabase test db`
-- (workflow: supabase-migrations.yml).
--
-- Covers migrations 20260915120000 (schema + pricing helpers) and
-- 20260915130000 (evaluation + atomic redemption):
--   1. Schema: tables, orders money columns, triggers, grants.
--   2. voucher_evaluate: happy paths (fixed / percent / percent+cap /
--      clamped to the subtotal) and EVERY failure reason.
--   3. validate_voucher: the preview agrees with the sale-aware subtotal
--      the order will actually be priced from.
--   4. FORGED TOTAL: an online order inserted with a bogus total_amount
--      and a voucher code comes back repriced by the trigger.
--   5. max_uses = 1: the first order wins, the second is refused and
--      nothing is double-counted (the loser of the FOR UPDATE race).
--   6. per_user_limit: the same customer cannot redeem twice while a
--      different customer can.
--   7. POS + voucher, and a voucher without items_snapshot → refused.
--   8. RLS: customers cannot list vouchers; the preview RPC is granted.
-- ══════════════════════════════════════════════════════════════════

begin;
select plan(37);

-- ── clear any JWT context ─────────────────────────────────────────
select set_config('request.jwt.claims', '{"sub":null,"role":null}', true);

-- ── fixtures (as postgres; RLS bypassed) ──────────────────────────
insert into auth.users (instance_id, id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', 'b0000000-0000-0000-0000-00000000005a', 'authenticated', 'authenticated', 'vch-customer@test.local', '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'b0000000-0000-0000-0000-00000000005b', 'authenticated', 'authenticated', 'vch-customer2@test.local', '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'b0000000-0000-0000-0000-00000000005c', 'authenticated', 'authenticated', 'vch-seller@test.local', '{}', '{}', now(), now()),
  -- A second seller: public.stores has a UNIQUE constraint on owner_id
  -- (one store per owner), so "Other Store" needs its own owner.
  ('00000000-0000-0000-0000-000000000000', 'b0000000-0000-0000-0000-00000000005d', 'authenticated', 'authenticated', 'vch-seller2@test.local', '{}', '{}', now(), now());

insert into public.profiles (id, full_name, email, role, seller_status)
values
  ('b0000000-0000-0000-0000-00000000005a', 'Voucher Customer',  'vch-customer@test.local',  'customer', 'none'),
  ('b0000000-0000-0000-0000-00000000005b', 'Voucher Customer 2','vch-customer2@test.local', 'customer', 'none'),
  ('b0000000-0000-0000-0000-00000000005c', 'Voucher Seller',    'vch-seller@test.local',    'seller',   'approved'),
  ('b0000000-0000-0000-0000-00000000005d', 'Voucher Seller 2',  'vch-seller2@test.local',   'seller',   'approved');

insert into public.stores (id, name, location, owner_id)
values
  ('b0000000-0000-0000-0000-00000000005e', 'Voucher Store', 'Manila', 'b0000000-0000-0000-0000-00000000005c'),
  ('b0000000-0000-0000-0000-00000000005f', 'Other Store',   'Cebu',   'b0000000-0000-0000-0000-00000000005d');

-- Product is ON SALE: price 500, sale_price 400, window covering now.
-- The voucher must stack on the SALE price (the stacking rule).
insert into public.products (id, store_id, seller_id, name, price, sale_price, sale_starts_at, sale_ends_at, is_active)
values ('b0000000-0000-0000-0000-0000000000f1', 'b0000000-0000-0000-0000-00000000005e',
        'b0000000-0000-0000-0000-00000000005c', 'Voucher Test Loafer',
        500, 400, now() - interval '1 day', now() + interval '1 day', true);

insert into public.inventory (product_id, size, stock)
values ('b0000000-0000-0000-0000-0000000000f1', '42', 10);

insert into public.vouchers (id, code, store_id, discount_type, discount_value, max_discount_amount, min_order_amount, max_uses, per_user_limit, starts_at, ends_at, funded_by, is_active)
values
  ('b0000000-0000-0000-0000-0000000000e1', 'VCFIXED100',  'b0000000-0000-0000-0000-00000000005e', 'fixed',   100, null,   0, null, 1, null, null, 'store',    true),
  ('b0000000-0000-0000-0000-0000000000e2', 'VCPERC20',    'b0000000-0000-0000-0000-00000000005e', 'percent',  20, null,   0, null, 1, null, null, 'store',    true),
  ('b0000000-0000-0000-0000-0000000000e3', 'VCPERC10CAP', 'b0000000-0000-0000-0000-00000000005e', 'percent',  10, 50.00, 0, null, 1, null, null, 'store',    true),
  ('b0000000-0000-0000-0000-0000000000e4', 'VCEXPIRED',   'b0000000-0000-0000-0000-00000000005e', 'fixed',    50, null,   0, null, 1, null, now() - interval '1 hour', 'store', true),
  ('b0000000-0000-0000-0000-0000000000e5', 'VCFUTURE',    'b0000000-0000-0000-0000-00000000005e', 'fixed',    50, null,   0, null, 1, now() + interval '1 hour', null, 'store', true),
  ('b0000000-0000-0000-0000-0000000000e6', 'VCOFF',       'b0000000-0000-0000-0000-00000000005e', 'fixed',    50, null,   0, null, 1, null, null, 'store',    false),
  ('b0000000-0000-0000-0000-0000000000e7', 'VCMAX1',      'b0000000-0000-0000-0000-00000000005e', 'fixed',    75, null,   0,    1, 1, null, null, 'store',    true),
  ('b0000000-0000-0000-0000-0000000000e8', 'VCMIN1000',   'b0000000-0000-0000-0000-00000000005e', 'fixed',    50, null, 1000, null, 1, null, null, 'store',    true),
  ('b0000000-0000-0000-0000-0000000000e9', 'VCOTHERSTORE','b0000000-0000-0000-0000-00000000005f', 'fixed',    50, null,   0, null, 1, null, null, 'store',    true),
  ('b0000000-0000-0000-0000-0000000000ea', 'VCPERUSER1',  'b0000000-0000-0000-0000-00000000005e', 'fixed',    25, null,   0, null, 1, null, null, 'store',    true),
  -- Platform-wide + platform-funded (admin-created in production).
  ('b0000000-0000-0000-0000-0000000000eb', 'VCPLATFORM',  null,                                   'fixed',   100, null,   0, null, 1, null, null, 'platform', true);

-- ══ 1. SCHEMA ═════════════════════════════════════════════════════
select has_table('public', 'vouchers', '1: vouchers table exists');
select has_table('public', 'voucher_redemptions', '2: voucher_redemptions table exists');
select has_column('public', 'orders', 'discount_amount', '3: orders.discount_amount exists');
select has_trigger('public', 'orders', 'trg_orders_apply_voucher', '4: orders BEFORE INSERT voucher trigger exists');

-- ══ 2. voucher_evaluate ═══════════════════════════════════════════
-- Fixed 100 off a ₱1000 goods subtotal.
select is(
  (public.voucher_evaluate('VCFIXED100', 1000, 'b0000000-0000-0000-0000-00000000005e', 'b0000000-0000-0000-0000-00000000005a') ->> 'discount_amount')::numeric,
  100.00::numeric, '5: fixed voucher discounts its face value');

-- Codes are case-insensitive + trimmed.
select is(
  (public.voucher_evaluate('  vcfixed100 ', 1000, 'b0000000-0000-0000-0000-00000000005e', null) ->> 'ok')::boolean,
  true, '6: code lookup is case-insensitive and trimmed');

-- Percent 20% of 1000.
select is(
  (public.voucher_evaluate('VCPERC20', 1000, 'b0000000-0000-0000-0000-00000000005e', null) ->> 'discount_amount')::numeric,
  200.00::numeric, '7: percent voucher discounts the percentage');

-- Percent 10% of 1000 = 100, capped at ₱50.
select is(
  (public.voucher_evaluate('VCPERC10CAP', 1000, 'b0000000-0000-0000-0000-00000000005e', null) ->> 'discount_amount')::numeric,
  50.00::numeric, '8: percent voucher honours its peso cap');

-- A fixed voucher larger than the cart can never exceed the subtotal.
select is(
  (public.voucher_evaluate('VCFIXED100', 60, 'b0000000-0000-0000-0000-00000000005e', null) ->> 'discount_amount')::numeric,
  60.00::numeric, '9: discount is clamped to the goods subtotal');

select is(
  (public.voucher_evaluate('NOPE', 1000, 'b0000000-0000-0000-0000-00000000005e', null) ->> 'reason'),
  'invalid_code', '10: unknown code → invalid_code');
select is(
  (public.voucher_evaluate('VCOFF', 1000, 'b0000000-0000-0000-0000-00000000005e', null) ->> 'reason'),
  'inactive', '11: switched-off code → inactive');
select is(
  (public.voucher_evaluate('VCFUTURE', 1000, 'b0000000-0000-0000-0000-00000000005e', null) ->> 'reason'),
  'not_started', '12: code before its window → not_started');
select is(
  (public.voucher_evaluate('VCEXPIRED', 1000, 'b0000000-0000-0000-0000-00000000005e', null) ->> 'reason'),
  'expired', '13: code past its end → expired');
select is(
  (public.voucher_evaluate('VCMIN1000', 999, 'b0000000-0000-0000-0000-00000000005e', null) ->> 'reason'),
  'below_minimum', '14: below minimum order → below_minimum');
select is(
  (public.voucher_evaluate('VCMIN1000', 1000, 'b0000000-0000-0000-0000-00000000005e', null) ->> 'ok')::boolean,
  true, '15: exactly at the minimum order passes');
select is(
  (public.voucher_evaluate('VCOTHERSTORE', 1000, 'b0000000-0000-0000-0000-00000000005e', null) ->> 'reason'),
  'wrong_store', '16: other store''s code → wrong_store');
select is(
  (public.voucher_evaluate('VCFIXED100', 0, 'b0000000-0000-0000-0000-00000000005e', null) ->> 'reason'),
  'empty_cart', '17: empty cart → empty_cart');
-- Platform-wide vouchers work on any store (store scope is NULL).
select is(
  (public.voucher_evaluate('VCPLATFORM', 1000, 'b0000000-0000-0000-0000-00000000005e', null) ->> 'ok')::boolean,
  true, '18: platform-wide code works on a store''s cart');

-- ══ 3. validate_voucher (preview == what the order is priced from) ══
-- 1 × ₱400 sale price → subtotal 400, + ₱100 delivery − ₱100 discount = 400.
select is(
  (public.validate_voucher('VCFIXED100', jsonb_build_array(
      jsonb_build_object('product_id', 'b0000000-0000-0000-0000-0000000000f1', 'size', '42', 'quantity', 2)
   )) ->> 'subtotal')::numeric,
  800.00::numeric, '19: preview uses the SALE price, not the list price');
select is(
  (public.validate_voucher('VCFIXED100', jsonb_build_array(
      jsonb_build_object('product_id', 'b0000000-0000-0000-0000-0000000000f1', 'size', '42', 'quantity', 2)
   )) ->> 'total')::numeric,
  800.00::numeric, '20: preview total = subtotal + ₱100 delivery − discount');
select is(
  (public.validate_voucher('NOPE', jsonb_build_array(
      jsonb_build_object('product_id', 'b0000000-0000-0000-0000-0000000000f1', 'size', '42', 'quantity', 1)
   )) ->> 'reason'),
  'invalid_code', '21: preview reports the real reason on failure');

-- ══ 4. FORGED TOTAL IS OVERWRITTEN BY THE TRIGGER ═════════════════
-- 1 × ₱400 (sale) + ₱100 delivery − ₱100 voucher = ₱400 payable. The
-- client claims ₱1 and sends no subtotal/discount at all.
insert into public.orders (id, customer_id, store_id, status, total_amount, payment_method, payment_status, source, items_snapshot, voucher_code)
values ('b0000000-0000-0000-0000-0000000000d1',
        'b0000000-0000-0000-0000-00000000005a',
        'b0000000-0000-0000-0000-00000000005e',
        'pending', 1, 'cash', 'unpaid', 'online',
        jsonb_build_array(jsonb_build_object('product_id', 'b0000000-0000-0000-0000-0000000000f1', 'size', '42', 'quantity', 1)),
        'vcfixed100');
select is(
  (select total_amount from public.orders where id = 'b0000000-0000-0000-0000-0000000000d1'),
  400.00::numeric, '22: forged total_amount is replaced by the server total');
select is(
  (select subtotal_amount from public.orders where id = 'b0000000-0000-0000-0000-0000000000d1'),
  400.00::numeric, '23: subtotal_amount is server-computed from the sale price');
select is(
  (select discount_amount from public.orders where id = 'b0000000-0000-0000-0000-0000000000d1'),
  100.00::numeric, '24: discount_amount is server-computed');
select is(
  (select voucher_code from public.orders where id = 'b0000000-0000-0000-0000-0000000000d1'),
  'VCFIXED100', '25: voucher_code is normalised onto the order');
select is(
  (select count(*) from public.voucher_redemptions
    where order_id = 'b0000000-0000-0000-0000-0000000000d1'
      and discount_amount = 100.00),
  1::bigint, '26: a redemption row records who used what');
select is(
  (select uses_count from public.vouchers where code = 'VCFIXED100'),
  1, '27: voucher uses_count incremented once');

-- ══ 5. max_uses = 1 — the race loser is refused, nothing double-counts ══
insert into public.orders (id, customer_id, store_id, status, total_amount, payment_method, payment_status, source, items_snapshot, voucher_code)
values ('b0000000-0000-0000-0000-0000000000d2',
        'b0000000-0000-0000-0000-00000000005a',
        'b0000000-0000-0000-0000-00000000005e',
        'pending', 500, 'cash', 'unpaid', 'online',
        jsonb_build_array(jsonb_build_object('product_id', 'b0000000-0000-0000-0000-0000000000f1', 'size', '42', 'quantity', 1)),
        'VCMAX1');
select is(
  (select total_amount from public.orders where id = 'b0000000-0000-0000-0000-0000000000d2'),
  425.00::numeric, '28: the first order of a max_uses=1 code gets the discount');

select throws_ok(
  $sql$ insert into public.orders (id, customer_id, store_id, status, total_amount, payment_method, payment_status, source, items_snapshot, voucher_code)
        values ('b0000000-0000-0000-0000-0000000000d3',
                'b0000000-0000-0000-0000-00000000005b',
                'b0000000-0000-0000-0000-00000000005e',
                'pending', 500, 'cash', 'unpaid', 'online',
                jsonb_build_array(jsonb_build_object('product_id', 'b0000000-0000-0000-0000-0000000000f1', 'size', '42', 'quantity', 1)),
                'VCMAX1') $sql$,
  'P0001', 'That code has already been fully claimed.',
  '29: the second order loses the FOR UPDATE race and is refused');
select is(
  (select uses_count from public.vouchers where code = 'VCMAX1'),
  1, '30: the refused order did not double-count the voucher');
select is(
  (select count(*) from public.orders where id = 'b0000000-0000-0000-0000-0000000000d3'),
  0::bigint, '31: the refused order left nothing behind');

-- ══ 6. per_user_limit ═════════════════════════════════════════════
insert into public.orders (id, customer_id, store_id, status, total_amount, payment_method, payment_status, source, items_snapshot, voucher_code)
values ('b0000000-0000-0000-0000-0000000000d4',
        'b0000000-0000-0000-0000-00000000005a',
        'b0000000-0000-0000-0000-00000000005e',
        'pending', 500, 'cash', 'unpaid', 'online',
        jsonb_build_array(jsonb_build_object('product_id', 'b0000000-0000-0000-0000-0000000000f1', 'size', '42', 'quantity', 1)),
        'VCPERUSER1');

select throws_ok(
  $sql$ insert into public.orders (id, customer_id, store_id, status, total_amount, payment_method, payment_status, source, items_snapshot, voucher_code)
        values ('b0000000-0000-0000-0000-0000000000d5',
                'b0000000-0000-0000-0000-00000000005a',
                'b0000000-0000-0000-0000-00000000005e',
                'pending', 500, 'cash', 'unpaid', 'online',
                jsonb_build_array(jsonb_build_object('product_id', 'b0000000-0000-0000-0000-0000000000f1', 'size', '42', 'quantity', 1)),
                'VCPERUSER1') $sql$,
  'P0001', 'You have already used that code.',
  '32: the same customer cannot redeem a once-per-customer code twice');

-- A different customer still can.
insert into public.orders (id, customer_id, store_id, status, total_amount, payment_method, payment_status, source, items_snapshot, voucher_code)
values ('b0000000-0000-0000-0000-0000000000d6',
        'b0000000-0000-0000-0000-00000000005b',
        'b0000000-0000-0000-0000-00000000005e',
        'pending', 500, 'cash', 'unpaid', 'online',
        jsonb_build_array(jsonb_build_object('product_id', 'b0000000-0000-0000-0000-0000000000f1', 'size', '42', 'quantity', 1)),
        'VCPERUSER1');
select is(
  (select total_amount from public.orders where id = 'b0000000-0000-0000-0000-0000000000d6'),
  475.00::numeric, '33: another customer can still redeem it');

-- ══ 7. Misuse is refused, not silently charged full price ═════════
select throws_ok(
  $sql$ insert into public.orders (id, customer_id, store_id, status, total_amount, payment_method, payment_status, source, items_snapshot, voucher_code)
        values ('b0000000-0000-0000-0000-0000000000d7',
                'b0000000-0000-0000-0000-00000000005a',
                'b0000000-0000-0000-0000-00000000005e',
                'received', 500, 'cash', 'paid', 'pos',
                jsonb_build_array(jsonb_build_object('product_id', 'b0000000-0000-0000-0000-0000000000f1', 'size', '42', 'quantity', 1)),
                'VCFIXED100') $sql$,
  'P0001', 'Vouchers can only be redeemed on online orders.',
  '34: a POS order cannot redeem a voucher');

-- Without the items there is nothing to reprice from, so the discount
-- cannot be verified → refuse instead of guessing.
select throws_ok(
  $sql$ insert into public.orders (id, customer_id, store_id, status, total_amount, payment_method, payment_status, source, voucher_code)
        values ('b0000000-0000-0000-0000-0000000000d8',
                'b0000000-0000-0000-0000-00000000005a',
                'b0000000-0000-0000-0000-00000000005e',
                'pending', 500, 'cash', 'unpaid', 'online',
                'VCFIXED100') $sql$,
  'P0001', 'A voucher needs the order items so the discount can be verified.',
  '35: a voucher without items_snapshot is refused');

-- ══ 8. RLS + grants ══════════════════════════════════════════════
select set_config('request.jwt.claims',
  '{"sub":"b0000000-0000-0000-0000-00000000005a","role":"authenticated"}', true);
set role authenticated;
select is(
  (select count(*) from public.vouchers),
  0::bigint, '36: a customer cannot list vouchers (codes stay unenumerable)');
reset role;
select is(
  has_function_privilege('authenticated', 'public.validate_voucher(text, jsonb)', 'EXECUTE'),
  true, '37: authenticated callers may quote a code through the preview RPC');

rollback;
