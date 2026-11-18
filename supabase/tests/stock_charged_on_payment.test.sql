-- ══════════════════════════════════════════════════════════════════
-- pgTAP: stock follows the money — including the case it cannot
--
-- Covers 20261118160000_stock_charged_on_payment.sql:
--   • an unpaid checkout takes no stock, so TWO customers can hold an
--     unpaid order for the SAME last unit (no reservation exists by design);
--   • the first seller verification deducts normally (1 → 0, stamped);
--   • the second verification FAILS with the insufficient-stock message
--     instead of going below zero;
--   • that failure leaves the losing order exactly as it was — still
--     payment_under_review, still unpaid, no stock_deducted_at, proof still
--     pending, no seller_verified event — so it can still be rejected and
--     refunded (the money is real, the stock is not);
--   • restocking lets the same order be verified afterwards, which is the
--     documented recovery path.
--
-- Run with: supabase test db. Everything happens inside one transaction and
-- is rolled back.
-- ══════════════════════════════════════════════════════════════════
begin;

create extension if not exists pgtap;

select plan(17);

-- ── identity helper ───────────────────────────────────────────────
create or replace function pg_temp.claims(p_user uuid) returns void
language sql as $$
  select set_config(
    'request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text,
    true
  );
$$;

select set_config('request.jwt.claims', '{"sub":null,"role":null}', true);
select set_config('request.headers', '{}', true);

-- ── fixtures (as postgres: RLS bypassed) ──────────────────────────
-- The seller is the actor for the fixture rows: inserting a store writes a
-- seller_activity_log row keyed to auth.uid(), and a claim with no profile
-- fails that FK.
select set_config(
  'request.jwt.claims',
  '{"sub":"91000000-0000-0000-0000-000000000011","role":"authenticated"}',
  true
);

insert into auth.users (instance_id, id, aud, role, email, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000','91000000-0000-0000-0000-000000000001','authenticated','authenticated','stock-a@test.local', now(), now()),
  ('00000000-0000-0000-0000-000000000000','91000000-0000-0000-0000-000000000002','authenticated','authenticated','stock-b@test.local', now(), now()),
  ('00000000-0000-0000-0000-000000000000','91000000-0000-0000-0000-000000000011','authenticated','authenticated','stock-seller@test.local', now(), now());

insert into public.profiles (id, full_name, email, role)
values
  ('91000000-0000-0000-0000-000000000001','Customer A','stock-a@test.local','customer'),
  ('91000000-0000-0000-0000-000000000002','Customer B','stock-b@test.local','customer'),
  ('91000000-0000-0000-0000-000000000011','Stock Seller','stock-seller@test.local','seller')
on conflict (id) do update
  set full_name = excluded.full_name, role = excluded.role;

insert into public.stores (id, owner_id, name, location)
values ('91000000-0000-0000-0000-0000000000a1','91000000-0000-0000-0000-000000000011',
        'Stock Store','Test City');

insert into public.products (id, store_id, seller_id, name, price, is_active)
values ('91000000-0000-0000-0000-0000000000b1','91000000-0000-0000-0000-0000000000a1',
        '91000000-0000-0000-0000-000000000011','Last Pair Shoe', 1000, true);

-- Exactly ONE unit: the whole point of the test.
insert into public.inventory (product_id, size, stock)
values ('91000000-0000-0000-0000-0000000000b1','40', 1);

update public.platform_settings
   set platform_fee_bps = 0, delivery_fee_amount = 100,
       gcash_proof_cooldown_seconds = 0
 where id = 1;

insert into public.platform_payment_accounts
  (label, gcash_number, account_name, is_active)
values ('Platform GCash', '09171234567', 'CUFMAI Store', true);

create temp table _t (
  k        text primary key,
  order_id uuid
);

select has_column('public','orders','stock_deducted_at',
  '1: orders carry the ledger bit that says whether stock was really taken');

-- ── 2–3. two unpaid checkouts for the same last unit ─────────────
-- Customer A
select pg_temp.claims('91000000-0000-0000-0000-000000000001');
insert into _t (k, order_id)
select 'o1', (j ->> 'order_id')::uuid
  from (
    select public.create_gcash_checkout(
      '[{"product_id":"91000000-0000-0000-0000-0000000000b1","size":"40","quantity":1}]'::jsonb,
      'Address A', null) as j
  ) s;

select is(
  (select stock from public.inventory
    where product_id = '91000000-0000-0000-0000-0000000000b1' and size = '40'),
  1,
  '2: the first checkout takes no stock — an unpaid order holds nothing'
);

-- Customer B, same unit. This is allowed on purpose: nothing is reserved,
-- so the availability check still sees the one unit.
select pg_temp.claims('91000000-0000-0000-0000-000000000002');
select lives_ok(
  $$ select public.create_gcash_checkout(
       '[{"product_id":"91000000-0000-0000-0000-0000000000b1","size":"40","quantity":1}]'::jsonb,
       'Address B', null) $$,
  '3: a second customer can start paying for the same last unit'
);

insert into _t (k, order_id)
select 'o2', id
  from public.orders
 where customer_id = '91000000-0000-0000-0000-000000000002'
   and status = 'awaiting_payment_confirmation';

select is(
  (select stock from public.inventory
    where product_id = '91000000-0000-0000-0000-0000000000b1' and size = '40'),
  1,
  '4: neither unpaid checkout has moved the stock'
);

-- ── 5–6. both pay ────────────────────────────────────────────────
select pg_temp.claims('91000000-0000-0000-0000-000000000001');
select lives_ok(
  format($$ select public.submit_gcash_proof(
    %L::uuid, '9100000000001', 'Customer A', 1100.00,
    %L, repeat('d', 64), now()) $$,
    (select order_id from _t where k = 'o1'),
    (select order_id from _t where k = 'o1')::text || '/shot-a.jpg'),
  '5: customer A submits a proof'
);

select pg_temp.claims('91000000-0000-0000-0000-000000000002');
select lives_ok(
  format($$ select public.submit_gcash_proof(
    %L::uuid, '9100000000002', 'Customer B', 1100.00,
    %L, repeat('e', 64), now()) $$,
    (select order_id from _t where k = 'o2'),
    (select order_id from _t where k = 'o2')::text || '/shot-b.jpg'),
  '6: customer B submits a proof — both payments are real'
);

-- ── 7–9. first verification deducts normally ─────────────────────
select pg_temp.claims('91000000-0000-0000-0000-000000000011');

select is(
  (public.verify_gcash_payment(
     (select order_id from _t where k = 'o1')) ->> 'status'),
  'pending',
  '7: the first verification is accepted'
);

select is(
  (select stock from public.inventory
    where product_id = '91000000-0000-0000-0000-0000000000b1' and size = '40'),
  0,
  '8: it takes the only unit — 1 → 0'
);

select ok(
  (select stock_deducted_at is not null from public.orders
    where id = (select order_id from _t where k = 'o1')),
  '9: the paid order records that its stock has been taken'
);

-- ── 10–14. the loser: refused, not oversold ──────────────────────
select throws_ok(
  format($$ select public.verify_gcash_payment(%L::uuid) $$,
    (select order_id from _t where k = 'o2')),
  'P0001',
  'Insufficient stock for Last Pair Shoe (size 40). It sold out while this payment was pending — reject the proof so the customer is refunded, or restock it and verify again.',
  '10: the second verification fails instead of selling stock that is gone'
);

select is(
  (select stock from public.inventory
    where product_id = '91000000-0000-0000-0000-0000000000b1' and size = '40'),
  0,
  '11: stock never goes negative — the refusal rolled back cleanly'
);

select is(
  (select status::text from public.orders
    where id = (select order_id from _t where k = 'o2')),
  'payment_under_review',
  '12: the losing order stays under review, so it can still be rejected and refunded'
);

select is(
  (select payment_status::text from public.orders
    where id = (select order_id from _t where k = 'o2')),
  'pending',
  '13: the losing order is NOT marked paid'
);

select ok(
  (select stock_deducted_at is null from public.orders
    where id = (select order_id from _t where k = 'o2')),
  '14: and it records that nothing was taken for it'
);

select is(
  (select p.status::text from public.gcash_payment_proofs p
    where p.order_id = (select order_id from _t where k = 'o2')),
  'pending',
  '15: its proof is still awaiting review, not silently verified'
);

-- ── 16–17. restock is the documented recovery path ───────────────
-- No seller_verified event was written for the refused order.
select is(
  (select count(*)::int from public.order_payment_events
    where order_id = (select order_id from _t where k = 'o2')
      and event_type = 'seller_verified'),
  0,
  '16: the refused verification wrote no seller_verified event'
);

update public.inventory
   set stock = 1
 where product_id = '91000000-0000-0000-0000-0000000000b1' and size = '40';

select is(
  (public.verify_gcash_payment(
     (select order_id from _t where k = 'o2')) ->> 'status'),
  'pending',
  '17: once the unit is restocked the same order verifies normally'
);

select * from finish();
rollback;
