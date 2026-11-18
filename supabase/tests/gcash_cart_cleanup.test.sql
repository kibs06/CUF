-- ══════════════════════════════════════════════════════════════════
-- pgTAP: a submitted GCash proof clears its own cart lines
--
-- The cart used to be cleaned by the app after a successful submit, so a
-- second device (or the same device after a kill) still showed the product.
-- These assertions are about the database's own state after the real RPC ran:
-- the matching lines are gone, a line the customer re-added keeps its
-- remainder, and nothing belonging to another size, product or customer is
-- touched.
--
-- Run with: supabase test db
--   or:     psql -d <scratch> -f supabase/tests/gcash_cart_cleanup.test.sql
-- Everything rolls back.
-- ══════════════════════════════════════════════════════════════════
begin;

create extension if not exists pgtap;

select no_plan();

create or replace function pg_temp.claims(p_user uuid) returns void
language sql as $$
  select set_config(
    'request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text,
    true
  );
$$;

create or replace function pg_temp.checkout(p_customer uuid, p_items jsonb)
returns jsonb
language plpgsql as $$
begin
  perform pg_temp.claims(p_customer);
  return public.create_gcash_checkout(p_items, 'Test address', null);
end $$;

create or replace function pg_temp.submit(
  p_customer uuid,
  p_order    uuid,
  p_ref      text,
  p_hash     text,
  p_amount   numeric
) returns jsonb
language plpgsql as $$
begin
  perform pg_temp.claims(p_customer);
  return public.submit_gcash_proof(
    p_order, p_ref, 'Juan Cruz', p_amount,
    p_order::text || '/shot.jpg', p_hash, now());
end $$;

select set_config('request.jwt.claims', '{"sub":null,"role":null}', true);

-- ── fixtures (session user: RLS bypassed) ────────────────────────
-- A profile insert writes seller_application_audit_log rows stamped with
-- auth.uid(), so a claim must exist while fixtures are created.
select set_config('request.jwt.claims',
  '{"sub":"f0000000-0000-0000-0000-0000000000fa","role":"authenticated"}', true);

insert into auth.users (instance_id, id, aud, role, email, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000','f0000000-0000-0000-0000-000000000001','authenticated','authenticated','cc-a@test.local', now(), now()),
  ('00000000-0000-0000-0000-000000000000','f0000000-0000-0000-0000-000000000002','authenticated','authenticated','cc-b@test.local', now(), now()),
  ('00000000-0000-0000-0000-000000000000','f0000000-0000-0000-0000-000000000011','authenticated','authenticated','cc-s@test.local', now(), now()),
  ('00000000-0000-0000-0000-000000000000','f0000000-0000-0000-0000-0000000000fa','authenticated','authenticated','cc-admin@test.local', now(), now());

insert into public.profiles (id, full_name, email, role)
values
  ('f0000000-0000-0000-0000-000000000001','CC Customer A','cc-a@test.local','customer'),
  ('f0000000-0000-0000-0000-000000000002','CC Customer B','cc-b@test.local','customer'),
  ('f0000000-0000-0000-0000-000000000011','CC Seller','cc-s@test.local','seller'),
  -- The admin row must exist before the store insert: log_seller_activity()
  -- stamps actor_id = auth.uid() (the claim below) onto seller_activity_log.
  ('f0000000-0000-0000-0000-0000000000fa','CC Admin','cc-admin@test.local','admin')
on conflict (id) do update
  set full_name = excluded.full_name, role = excluded.role;

insert into public.stores (id, owner_id, name, location)
values ('f0000000-0000-0000-0000-0000000000a1',
        'f0000000-0000-0000-0000-000000000011','CC Store','Test City');

insert into public.products (id, store_id, seller_id, name, price, is_active)
values
  ('f0000000-0000-0000-0000-0000000000b1','f0000000-0000-0000-0000-0000000000a1',
   'f0000000-0000-0000-0000-000000000011','CC Shoe', 1000, true),
  ('f0000000-0000-0000-0000-0000000000b2','f0000000-0000-0000-0000-0000000000a1',
   'f0000000-0000-0000-0000-000000000011','CC Sock', 100, true);

-- Two sizes of the same product, so a size mismatch is observable.
insert into public.product_variants (id, product_id, size, color, stock)
values
  (900001,'f0000000-0000-0000-0000-0000000000b1','40', null, 10),
  (900002,'f0000000-0000-0000-0000-0000000000b1','41', null, 10);

insert into public.inventory (product_id, size, stock)
values
  ('f0000000-0000-0000-0000-0000000000b1','40', 10),
  ('f0000000-0000-0000-0000-0000000000b1','41', 10);

update public.platform_settings
   set platform_fee_bps = 0, delivery_fee_amount = 100
 where id = 1;

-- Platform account, opened the way the admin portal does it.
select pg_temp.claims('f0000000-0000-0000-0000-0000000000fa');
set local role authenticated;
insert into public.platform_payment_accounts
  (label, gcash_number, account_name, qr_url, is_active)
values ('CC Platform', '09170000000', 'CC Store',
        'https://example.test/cc-qr.png', true);
reset role;

create temp table r (k text primary key, j jsonb);

-- ══ 1. A fully covered line is deleted ═══════════════════════════
-- A has the pair in the cart, checks it out, then pays for it.
insert into public.cart_items (id, user_id, product_id, variant_id, quantity)
values
  ('f0000000-0000-0000-0000-00000000c001', 'f0000000-0000-0000-0000-000000000001',
   'f0000000-0000-0000-0000-0000000000b1', 900001, 1),
  -- same product, other size: must survive
  ('f0000000-0000-0000-0000-00000000c002', 'f0000000-0000-0000-0000-000000000001',
   'f0000000-0000-0000-0000-0000000000b1', 900002, 1),
  -- different product: must survive
  ('f0000000-0000-0000-0000-00000000c003', 'f0000000-0000-0000-0000-000000000001',
   'f0000000-0000-0000-0000-0000000000b2', null, 1),
  -- another customer's line for the same variant: must survive
  ('f0000000-0000-0000-0000-00000000c004', 'f0000000-0000-0000-0000-000000000002',
   'f0000000-0000-0000-0000-0000000000b1', 900001, 1);

insert into r values ('o1', pg_temp.checkout(
  'f0000000-0000-0000-0000-000000000001',
  '[{"product_id":"f0000000-0000-0000-0000-0000000000b1","size":"40","quantity":1}]'::jsonb));

insert into r values ('p1', pg_temp.submit(
  'f0000000-0000-0000-0000-000000000001',
  (select (j ->> 'order_id')::uuid from r where k = 'o1'),
  '900000000001', repeat('a', 64), 1100.00));

select is(
  (select count(*)::int from public.cart_items
    where id = 'f0000000-0000-0000-0000-00000000c001'),
  0,
  '1: the line the order paid for is gone'
);

select is(
  (select quantity from public.cart_items
    where id = 'f0000000-0000-0000-0000-00000000c002'),
  1,
  '2: the same product in another size is untouched'
);

select is(
  (select quantity from public.cart_items
    where id = 'f0000000-0000-0000-0000-00000000c003'),
  1,
  '3: a different product in the cart is untouched'
);

select is(
  (select quantity from public.cart_items
    where id = 'f0000000-0000-0000-0000-00000000c004'),
  1,
  '4: another customer''s cart is untouched'
);

-- ══ 2. A line with more than was bought keeps the remainder ══════
insert into public.cart_items (id, user_id, product_id, variant_id, quantity)
values ('f0000000-0000-0000-0000-00000000c005', 'f0000000-0000-0000-0000-000000000001',
        'f0000000-0000-0000-0000-0000000000b1', 900001, 3);

insert into r values ('o2', pg_temp.checkout(
  'f0000000-0000-0000-0000-000000000001',
  '[{"product_id":"f0000000-0000-0000-0000-0000000000b1","size":"40","quantity":2}]'::jsonb));

insert into r values ('p2', pg_temp.submit(
  'f0000000-0000-0000-0000-000000000001',
  (select (j ->> 'order_id')::uuid from r where k = 'o2'),
  '900000000002', repeat('b', 64), 2100.00));

select is(
  (select quantity from public.cart_items
    where id = 'f0000000-0000-0000-0000-00000000c005'),
  1,
  '5: 3 in the cart minus 2 bought leaves 1, not 0'
);

-- ══ 3. A rejected attempt changes nothing ════════════════════════
-- Wrong amount: the RPC raises before the order update, so the cart must keep
-- the line (the customer may still pay properly).
insert into public.cart_items (id, user_id, product_id, variant_id, quantity)
values ('f0000000-0000-0000-0000-00000000c006', 'f0000000-0000-0000-0000-000000000001',
        'f0000000-0000-0000-0000-0000000000b1', 900002, 1);

insert into r values ('o3', pg_temp.checkout(
  'f0000000-0000-0000-0000-000000000001',
  '[{"product_id":"f0000000-0000-0000-0000-0000000000b1","size":"41","quantity":1}]'::jsonb));

select throws_ok(
  format($$ select pg_temp.submit(%L::uuid, %L::uuid, '900000000003', repeat('c',64), 1.00) $$,
    'f0000000-0000-0000-0000-000000000001',
    (select (j ->> 'order_id')::uuid from r where k = 'o3')),
  'P0001',
  null,
  '6: a wrong amount is still refused'
);

select is(
  (select quantity from public.cart_items
    where id = 'f0000000-0000-0000-0000-00000000c006'),
  1,
  '7: a refused proof leaves the cart alone'
);

-- ══ 4. The helper is not a client-callable RPC ════════════════════
select ok(
  not has_function_privilege(
    'authenticated',
    'public.clear_purchased_cart_items(uuid, uuid)',
    'execute'),
  '8: authenticated cannot empty carts by calling the helper directly'
);

select * from finish();
rollback;
