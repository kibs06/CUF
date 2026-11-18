-- ══════════════════════════════════════════════════════════════════
-- pgTAP: the proof cooldown also covers bulk reservation deposits
--
-- The deposit RPC's unique indexes stop a reused reference and a second proof
-- for one reservation. Nothing stopped a customer filing attempts for
-- reservation after reservation — the same persistence hole the order proof
-- had. Both RPCs now share one window, so this suite pins three things: the
-- deposit flow is refused inside the window, the window belongs to the
-- customer, and it is one clock across BOTH proof families (a deposit filed a
-- moment ago blocks an order proof, and vice versa).
--
-- Run with: supabase test db
--   or:     psql -d <scratch> -f supabase/tests/bulk_deposit_proof_cooldown.test.sql
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

-- The deposit RPC takes the reservation, the reference and the storage path.
create or replace function pg_temp.file_deposit(
  p_customer uuid, p_reservation uuid, p_ref text
) returns void
language plpgsql as $$
begin
  perform pg_temp.claims(p_customer);
  perform public.submit_bulk_reservation_deposit_proof(
    p_reservation, p_ref, p_reservation::text || '/shot-' || p_ref || '.jpg');
end $$;

-- ── fixtures ──────────────────────────────────────────────────────
select set_config('request.jwt.claims', '{"sub":null,"role":null}', true);

-- A profile insert writes seller_application_audit_log rows stamped with
-- auth.uid(), so a claim must exist while the fixtures are created.
select set_config('request.jwt.claims',
  '{"sub":"f3000000-0000-0000-0000-000000000011","role":"authenticated"}', true);

insert into auth.users (instance_id, id, aud, role, email, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000','f3000000-0000-0000-0000-000000000001','authenticated','authenticated','bd-a@test.local', now(), now()),
  ('00000000-0000-0000-0000-000000000000','f3000000-0000-0000-0000-000000000002','authenticated','authenticated','bd-b@test.local', now(), now()),
  ('00000000-0000-0000-0000-000000000000','f3000000-0000-0000-0000-000000000011','authenticated','authenticated','bd-s@test.local', now(), now());

insert into public.profiles (id, full_name, email, role)
values
  ('f3000000-0000-0000-0000-000000000001','BD Customer A','bd-a@test.local','customer'),
  ('f3000000-0000-0000-0000-000000000002','BD Customer B','bd-b@test.local','customer'),
  ('f3000000-0000-0000-0000-000000000011','BD Seller','bd-s@test.local','seller')
on conflict (id) do update
  set full_name = excluded.full_name, role = excluded.role;

insert into public.stores (id, owner_id, name, location)
values ('f3000000-0000-0000-0000-0000000000a1',
        'f3000000-0000-0000-0000-000000000011','BD Store','Test City');

insert into public.products (id, store_id, seller_id, name, price, is_active)
values ('f3000000-0000-0000-0000-0000000000b1',
        'f3000000-0000-0000-0000-0000000000a1',
        'f3000000-0000-0000-0000-000000000011','BD Shoe', 1000, true);

update public.platform_settings
   set platform_fee_bps = 0, delivery_fee_amount = 100,
       gcash_proof_cooldown_seconds = 60
 where id = 1;

-- Reservations are inserted directly: the RPCs under test only need a row in
-- 'awaiting_deposit' with a live deadline, and building them through
-- request → approve → deposit would test the seller queue instead.
insert into public.bulk_reservations
  (id, customer_id, store_id, product_id, quantity, status,
   deposit_amount, deposit_status, deposit_deadline)
values
  ('f3000000-0000-0000-0000-0000000000c1','f3000000-0000-0000-0000-000000000001',
   'f3000000-0000-0000-0000-0000000000a1','f3000000-0000-0000-0000-0000000000b1',
   5, 'awaiting_deposit', 500, 'unpaid', now() + interval '1 hour'),
  ('f3000000-0000-0000-0000-0000000000c2','f3000000-0000-0000-0000-000000000001',
   'f3000000-0000-0000-0000-0000000000a1','f3000000-0000-0000-0000-0000000000b1',
   6, 'awaiting_deposit', 600, 'unpaid', now() + interval '1 hour'),
  ('f3000000-0000-0000-0000-0000000000c3','f3000000-0000-0000-0000-000000000002',
   'f3000000-0000-0000-0000-0000000000a1','f3000000-0000-0000-0000-0000000000b1',
   7, 'awaiting_deposit', 700, 'unpaid', now() + interval '1 hour'),
  ('f3000000-0000-0000-0000-0000000000c4','f3000000-0000-0000-0000-000000000001',
   'f3000000-0000-0000-0000-0000000000a1','f3000000-0000-0000-0000-0000000000b1',
   8, 'awaiting_deposit', 800, 'unpaid', now() + interval '1 hour');

-- ── 1. nothing filed → no wait ───────────────────────────────────
select is(
  public.gcash_proof_cooldown_remaining('f3000000-0000-0000-0000-000000000001'),
  0,
  '1: a customer who has filed nothing is not waiting');

-- ── 2. the first deposit file is accepted ────────────────────────
select lives_ok(
  $$select pg_temp.file_deposit('f3000000-0000-0000-0000-000000000001',
      'f3000000-0000-0000-0000-0000000000c1', '404400000001')$$,
  '2: the first deposit proof is accepted');

select ok(
  public.gcash_proof_cooldown_remaining('f3000000-0000-0000-0000-000000000001') > 0,
  '3: filing a deposit starts the same clock');

-- ── 3. a second reservation right after is refused ───────────────
select throws_like(
  $$select pg_temp.file_deposit('f3000000-0000-0000-0000-000000000001',
      'f3000000-0000-0000-0000-0000000000c2', '404400000002')$$,
  '%PROOF_COOLDOWN%',
  '4: a back-to-back deposit proof is refused with the app''s code');

select is(
  (select count(*)::int from public.bulk_reservation_deposits
    where reservation_id = 'f3000000-0000-0000-0000-0000000000c2'),
  0,
  '5: the refused attempt wrote no deposit row');

-- ── 4. the clock is the customer's own ───────────────────────────
select lives_ok(
  $$select pg_temp.file_deposit('f3000000-0000-0000-0000-000000000002',
      'f3000000-0000-0000-0000-0000000000c3', '404400000003')$$,
  '6: another customer is not waiting on somebody else''s clock');

-- ── 5. one clock across BOTH proof families ──────────────────────
-- Age customer A's deposit so only the order proof can be the reason.
update public.bulk_reservation_deposits
   set submitted_at = now() - interval '5 minutes'
 where reservation_id = 'f3000000-0000-0000-0000-0000000000c1';

insert into public.orders
  (id, customer_id, total_amount, status, payment_status, payment_method,
   source, order_code)
values
  ('f3000000-0000-0000-0000-0000000000d1','f3000000-0000-0000-0000-000000000001',
   100, 'payment_under_review', 'paid', 'gcash', 'online', 'BDORDER1');

insert into public.gcash_payment_proofs
  (order_id, reference_number, screenshot_url, submitted_by,
   sender_name, amount_paid, screenshot_hash, attempt_no, status)
values
  ('f3000000-0000-0000-0000-0000000000d1', '404400000004',
   'f3000000-0000-0000-0000-0000000000d1/shot.jpg',
   'f3000000-0000-0000-0000-000000000001', 'Juan Cruz', 100,
   repeat('a', 64), 1, 'verified');

select throws_like(
  $$select pg_temp.file_deposit('f3000000-0000-0000-0000-000000000001',
      'f3000000-0000-0000-0000-0000000000c2', '404400000005')$$,
  '%PROOF_COOLDOWN%',
  '7: a recent order proof blocks a deposit too — one clock, both families');

-- ── 6. the setting governs this path as well ─────────────────────
update public.platform_settings set gcash_proof_cooldown_seconds = 0 where id = 1;

select lives_ok(
  $$select pg_temp.file_deposit('f3000000-0000-0000-0000-000000000001',
      'f3000000-0000-0000-0000-0000000000c2', '404400000006')$$,
  '8: 0 in platform settings turns the window off for deposits too');

select * from finish();
rollback;
