-- ══════════════════════════════════════════════════════════════════
-- pgTAP: one GCash proof file per minute, per customer
--
-- The unique indexes stop the same reference, screenshot or order being filed
-- twice. They cannot stop a customer who keeps filing fresh attempts, which is
-- what this cooldown covers. These assertions pin the behaviour that matters:
-- the second file inside the window is refused before anything is written, the
-- wait is a clock rather than a lockout, it is scoped to the customer who
-- filed, and the order's own state still speaks first.
--
-- Run with: supabase test db
--   or:     psql -d <scratch> -f supabase/tests/gcash_proof_cooldown.test.sql
-- Everything rolls back.
-- ══════════════════════════════════════════════════════════════════
begin;

create extension if not exists pgtap;

select plan(8);

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

-- Files a proof for whatever the order actually totals, with the screenshot
-- path the RPC requires (order id first) and a caller-supplied unique hash.
create or replace function pg_temp.file_proof(
  p_customer uuid,
  p_order    uuid,
  p_ref      text,
  p_hash     text
) returns jsonb
language plpgsql as $$
declare
  v_total numeric;
begin
  perform pg_temp.claims(p_customer);
  select total_amount into v_total from public.orders where id = p_order;
  return public.submit_gcash_proof(
    p_order, p_ref, 'Juan Cruz', v_total,
    p_order::text || '/' || p_ref || '.jpg', p_hash, null);
end $$;

-- ── fixtures ──────────────────────────────────────────────────────
select set_config('request.jwt.claims', '{"sub":null,"role":null}', true);

select set_config('request.jwt.claims',
  '{"sub":"f2000000-0000-0000-0000-0000000000fa","role":"authenticated"}', true);

insert into auth.users (instance_id, id, aud, role, email, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000','f2000000-0000-0000-0000-000000000001','authenticated','authenticated','cd-a@test.local', now(), now()),
  ('00000000-0000-0000-0000-000000000000','f2000000-0000-0000-0000-000000000002','authenticated','authenticated','cd-b@test.local', now(), now()),
  ('00000000-0000-0000-0000-000000000000','f2000000-0000-0000-0000-000000000011','authenticated','authenticated','cd-s@test.local', now(), now()),
  ('00000000-0000-0000-0000-000000000000','f2000000-0000-0000-0000-0000000000fa','authenticated','authenticated','cd-admin@test.local', now(), now());

insert into public.profiles (id, full_name, email, role)
values
  ('f2000000-0000-0000-0000-000000000001','CD Customer A','cd-a@test.local','customer'),
  ('f2000000-0000-0000-0000-000000000002','CD Customer B','cd-b@test.local','customer'),
  ('f2000000-0000-0000-0000-000000000011','CD Seller','cd-s@test.local','seller'),
  ('f2000000-0000-0000-0000-0000000000fa','CD Admin','cd-admin@test.local','admin')
on conflict (id) do update
  set full_name = excluded.full_name, role = excluded.role;

insert into public.stores (id, owner_id, name, location)
values ('f2000000-0000-0000-0000-0000000000a1',
        'f2000000-0000-0000-0000-000000000011','CD Store','Test City');

insert into public.products (id, store_id, seller_id, name, price, is_active)
values ('f2000000-0000-0000-0000-0000000000b1',
        'f2000000-0000-0000-0000-0000000000a1',
        'f2000000-0000-0000-0000-000000000011','CD Shoe', 1000, true);

insert into public.product_variants (id, product_id, size, color, stock)
values (910001,'f2000000-0000-0000-0000-0000000000b1','40', null, 20);

insert into public.inventory (product_id, size, stock)
values ('f2000000-0000-0000-0000-0000000000b1','40', 20);

update public.platform_settings
   set platform_fee_bps = 0, delivery_fee_amount = 100,
       gcash_proof_cooldown_seconds = 60
 where id = 1;

-- Platform account, opened the way the admin portal does it.
select pg_temp.claims('f2000000-0000-0000-0000-0000000000fa');
set local role authenticated;
insert into public.platform_payment_accounts
  (label, gcash_number, account_name, qr_url, is_active)
values ('CD Platform', '09170000001', 'CD Store',
        'https://example.test/cd-qr.png', true);
reset role;

create temp table r (k text primary key, j jsonb);
create or replace function pg_temp.order_of(p_key text) returns uuid
language sql as $$
  select (j->>'order_id')::uuid from r where k = p_key;
$$;

-- ══ 1. the first file is accepted ════════════════════════════════
insert into r values ('o1', pg_temp.checkout(
  'f2000000-0000-0000-0000-000000000001',
  '[{"product_id":"f2000000-0000-0000-0000-0000000000b1","size":"40","quantity":1}]'::jsonb));

select is(
  pg_temp.file_proof('f2000000-0000-0000-0000-000000000001', pg_temp.order_of('o1'),
    '404300000001', repeat('a', 64))->>'status',
  'payment_under_review',
  '1: the first proof is accepted');

-- ══ 2. the second file inside the window is refused ══════════════
insert into r values ('o2', pg_temp.checkout(
  'f2000000-0000-0000-0000-000000000001',
  '[{"product_id":"f2000000-0000-0000-0000-0000000000b1","size":"40","quantity":1}]'::jsonb));

select throws_like(
  $$select pg_temp.file_proof('f2000000-0000-0000-0000-000000000001',
      (select (j->>'order_id')::uuid from r where k = 'o2'),
      '404300000002', repeat('b', 64))$$,
  '%Try again in%',
  '2: a back-to-back file from the same customer is refused');

select is(
  (select count(*)::int from public.gcash_payment_proofs pr
    where pr.order_id = (select (j->>'order_id')::uuid from r where k = 'o2')),
  0,
  '3: the refused attempt wrote no proof row');

-- ══ 3. the wait is the clock, not a lockout ══════════════════════
-- submitted_at is pinned by trg_pin_gcash_proof_time, which is the point: the
-- only way to age a proof here is to disarm the trigger inside this rolled-back
-- transaction, which a client cannot do.
alter table public.gcash_payment_proofs disable trigger trg_pin_gcash_proof_time;
update public.gcash_payment_proofs
   set submitted_at = now() - interval '5 minutes'
 where order_id = (select (j->>'order_id')::uuid from r where k = 'o1');
alter table public.gcash_payment_proofs enable trigger trg_pin_gcash_proof_time;

select is(
  pg_temp.file_proof('f2000000-0000-0000-0000-000000000001', pg_temp.order_of('o2'),
    '404300000003', repeat('c', 64))->>'status',
  'payment_under_review',
  '4: once the minute has passed, the next file is accepted');

-- ══ 4. the cooldown belongs to the customer who filed ════════════
insert into r values ('o3', pg_temp.checkout(
  'f2000000-0000-0000-0000-000000000002',
  '[{"product_id":"f2000000-0000-0000-0000-0000000000b1","size":"40","quantity":1}]'::jsonb));

select is(
  pg_temp.file_proof('f2000000-0000-0000-0000-000000000002', pg_temp.order_of('o3'),
    '404300000004', repeat('d', 64))->>'status',
  'payment_under_review',
  '5: another customer is not waiting on somebody else''s clock');

-- ══ 5. the order's own state still speaks first ══════════════════
-- Customer A filed for o2 moments ago, so the cooldown is live — but o1 is
-- already with the store, and that is the sentence worth showing.
select throws_like(
  $$select pg_temp.file_proof('f2000000-0000-0000-0000-000000000001',
      (select (j->>'order_id')::uuid from r where k = 'o1'),
      '404300000005', repeat('e', 64))$$,
  '%already with the store for review%',
  '6: the order-state message wins over the cooldown');

-- ══ 6. the cooldown lifts, and it consumes no attempts ═══════════
alter table public.gcash_payment_proofs disable trigger trg_pin_gcash_proof_time;
update public.gcash_payment_proofs
   set submitted_at = now() - interval '5 minutes'
 where order_id = (select (j->>'order_id')::uuid from r where k = 'o2');
alter table public.gcash_payment_proofs enable trigger trg_pin_gcash_proof_time;

insert into r values ('o4', pg_temp.checkout(
  'f2000000-0000-0000-0000-000000000001',
  '[{"product_id":"f2000000-0000-0000-0000-0000000000b1","size":"40","quantity":1}]'::jsonb));

select lives_ok(
  $$select pg_temp.file_proof('f2000000-0000-0000-0000-000000000001',
      (select (j->>'order_id')::uuid from r where k = 'o4'),
      '404300000006', repeat('f', 64))$$,
  '7: a later attempt is accepted, so the cooldown is not a lockout');

select is(
  (select pr.attempt_no from public.gcash_payment_proofs pr
    where pr.order_id = (select (j->>'order_id')::uuid from r where k = 'o4')),
  1,
  '8: a refused or cooled-down attempt still leaves the order on attempt 1');

select * from finish();
rollback;
