-- ══════════════════════════════════════════════════════════════════
-- pgTAP: marking an order delivered emails the receipt, and the seller can
-- send it in one tap
--
-- Covers 20261119130000_order_receipt_on_delivery.sql:
--
--   1. The delivered trigger exists and carries its `delivered` + `online`
--      condition, so the POS till's own flow is untouched.
--   2. Marking an unpaid cash-on-delivery order delivered queues a receipt —
--      the case 20261119110000 could not reach, because that order never
--      passes through payment_status = 'paid'.
--   3. Marking an already-stamped order delivered mails nothing (the customer
--      is never mailed twice by the paid and delivered triggers both firing).
--   4. The seller's RPC dispatches with the registered address, gives an
--      exhausted order a fresh budget, and refuses another seller and the
--      customer themselves with 42501.
--   5. A stamped order answers `already_sent` with the address it went to.
--   6. `anon` cannot execute the seller's RPC.
--
-- Vault entries are created inside the transaction and rolled back. The URL
-- points at a closed port: reaching it is not what this file is about.
--
-- Run with: supabase test db
-- Everything rolls back.
-- ══════════════════════════════════════════════════════════════════
begin;

create extension if not exists pgtap;

select plan(13);

-- ── 1. wiring ────────────────────────────────────────────────────
select has_trigger('public', 'orders', 'trg_order_receipt_on_delivered',
  '1: a handover fires the receipt dispatch');

select ok(
  (select pg_get_triggerdef(oid) like '%delivered%'
          and pg_get_triggerdef(oid) like '%online%'
     from pg_trigger
    where tgname = 'trg_order_receipt_on_delivered'),
  '2: and only for a delivered online order');

select has_function('public', 'send_order_receipt_to_customer', array['uuid'],
  '3: the seller has one call that sends a receipt');

select ok(
  not has_function_privilege(
    'anon',
    'public.send_order_receipt_to_customer(uuid)',
    'EXECUTE'
  ),
  '4: and anon cannot call it');

-- ── fixtures (as postgres: RLS bypassed) ─────────────────────────
select set_config('request.headers', '{}', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"cd000000-0000-0000-0000-000000000011","role":"authenticated"}',
  true
);

insert into auth.users (instance_id, id, aud, role, email, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000','cd000000-0000-0000-0000-000000000011','authenticated','authenticated','delivery-seller@test.local', now(), now()),
  ('00000000-0000-0000-0000-000000000000','cd000000-0000-0000-0000-000000000012','authenticated','authenticated','other-seller@test.local', now(), now()),
  ('00000000-0000-0000-0000-000000000000','cd000000-0000-0000-0000-000000000001','authenticated','authenticated','delivery-customer@test.local', now(), now());

insert into public.profiles (id, full_name, email, role)
values
  ('cd000000-0000-0000-0000-000000000011','Delivery Seller','delivery-seller@test.local','seller'),
  ('cd000000-0000-0000-0000-000000000012','Other Seller','other-seller@test.local','seller'),
  ('cd000000-0000-0000-0000-000000000001','Delivery Customer','delivery-customer@test.local','customer')
on conflict (id) do update
  set full_name = excluded.full_name, email = excluded.email, role = excluded.role;

insert into public.stores (id, owner_id, name, location)
values
  ('cd000000-0000-0000-0000-0000000000a1','cd000000-0000-0000-0000-000000000011',
   'Delivery Store','Test City'),
  ('cd000000-0000-0000-0000-0000000000a2','cd000000-0000-0000-0000-000000000012',
   'Other Store','Test City');

-- b1: cash-on-delivery, never paid — the case this file exists for.
-- b2: already mailed at payment, now being delivered.
-- b3: the seller's button, parked in a long backoff after five failures.
insert into public.orders
  (id, customer_id, store_id, total_amount, status, payment_status,
   payment_method, source, order_code)
values
  ('cd000000-0000-0000-0000-0000000000b1',
   'cd000000-0000-0000-0000-000000000001',
   'cd000000-0000-0000-0000-0000000000a1',
   1500, 'ready', 'unpaid', 'cash', 'online', 'DELIVER01'),
  ('cd000000-0000-0000-0000-0000000000b2',
   'cd000000-0000-0000-0000-000000000001',
   'cd000000-0000-0000-0000-0000000000a1',
   1500, 'ready', 'paid', 'gcash', 'online', 'DELIVER02'),
  ('cd000000-0000-0000-0000-0000000000b3',
   'cd000000-0000-0000-0000-000000000001',
   'cd000000-0000-0000-0000-0000000000a1',
   1500, 'ready', 'paid', 'gcash', 'online', 'DELIVER03');

select vault.create_secret('http://127.0.0.1:9/receipt', 'receipt_function_url');
select vault.create_secret('test-service-role-key', 'service_role_key');

-- b2 was mailed at payment; b3 is out of attempts and waiting six hours.
update public.orders
   set receipt_emailed_at = '2026-01-01 00:00:00+00',
       receipt_email_to = 'delivery-customer@test.local',
       receipt_email_sending_since = null
 where id = 'cd000000-0000-0000-0000-0000000000b2';

update public.orders
   set receipt_email_attempts = 5,
       receipt_email_last_error = 'SMTP 421 temporary failure',
       receipt_email_sending_since = null,
       receipt_email_next_attempt_at = now() + interval '6 hours'
 where id = 'cd000000-0000-0000-0000-0000000000b3';

-- ── 2. delivery queues the receipt, even when the order was never paid ──
update public.orders
   set status = 'delivered'
 where id = 'cd000000-0000-0000-0000-0000000000b1';

select ok(
  (select receipt_email_sending_since is not null
     from public.orders
    where id = 'cd000000-0000-0000-0000-0000000000b1'),
  '5: a delivered cash-on-delivery order is dispatched without being paid');

select is(
  (select receipt_email_sending_since from public.orders
    where id = 'cd000000-0000-0000-0000-0000000000b1') is not null,
  true,
  '6: and the dispatch holds its in-flight lease');

-- ── 3. an order already mailed at payment is not mailed again ────
update public.orders
   set status = 'delivered'
 where id = 'cd000000-0000-0000-0000-0000000000b2';

select is(
  (select receipt_emailed_at from public.orders
    where id = 'cd000000-0000-0000-0000-0000000000b2'),
  '2026-01-01 00:00:00+00'::timestamptz,
  '7: the original stamp is untouched by the delivery');

select is(
  (select receipt_email_sending_since from public.orders
    where id = 'cd000000-0000-0000-0000-0000000000b2'),
  null::timestamptz,
  '8: and nothing was dispatched a second time');

-- ── 4. the seller's one tap ──────────────────────────────────────
select set_config(
  'request.jwt.claims',
  '{"sub":"cd000000-0000-0000-0000-000000000011","role":"authenticated"}',
  true
);

select is(
  public.send_order_receipt_to_customer('cd000000-0000-0000-0000-0000000000b3') ->> 'to',
  'delivery-customer@test.local',
  '9: the store owner sends to the registered address');

select ok(
  (select receipt_email_attempts = 0
          and receipt_email_next_attempt_at is null
          and receipt_email_sending_since is not null
     from public.orders
    where id = 'cd000000-0000-0000-0000-0000000000b3'),
  '10: a deliberate send gives an exhausted order a fresh budget');

select is(
  public.send_order_receipt_to_customer('cd000000-0000-0000-0000-0000000000b2') ->> 'reason',
  'already_sent',
  '11: a stamped order is not mailed again');

-- Another seller, and the customer themselves, are both refused.
select set_config(
  'request.jwt.claims',
  '{"sub":"cd000000-0000-0000-0000-000000000012","role":"authenticated"}',
  true
);
select throws_ok(
  $$ select public.send_order_receipt_to_customer('cd000000-0000-0000-0000-0000000000b1') $$,
  '42501', null,
  '12: another store cannot email this sale');

select set_config(
  'request.jwt.claims',
  '{"sub":"cd000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);
select throws_ok(
  $$ select public.send_order_receipt_to_customer('cd000000-0000-0000-0000-0000000000b1') $$,
  '42501', null,
  '13: the customer cannot email themselves a receipt on demand');

select * from finish();
rollback;
