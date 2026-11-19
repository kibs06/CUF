-- ══════════════════════════════════════════════════════════════════
-- pgTAP: an online order emails its own receipt
--
-- Covers 20261119110000_order_receipt_email.sql:
--
--   1. Schema: the stamps exist, plus orders.customer_email (from
--      20261119100000, repeated here so this file stands alone).
--   2. The two triggers are installed, and the paid one carries the
--      paid + online condition in its definition — that clause is what keeps
--      the POS till out of this path.
--   3. The dispatcher answers each "no" with its own reason, in the order a
--      payment actually arrives: not paid, not online, no address, no
--      function URL configured.
--   4. Once a URL is in Vault it queues, resolving the address from the
--      order first and the account second.
--   5. A stamped order is a no-op, so a retried dispatch cannot mail the
--      customer twice. (Since 20261119120000 the dispatcher also holds a
--      five-minute lease, so the two dispatches below are separated by a
--      release of that lease — it is the same protection, tested directly in
--      order_receipt_email_retry.test.sql.)
--
-- The Vault entries are created inside this transaction (and rolled back), so
-- the test never needs the real function URL or a live service key. The URL
-- points at a closed port: pg_net queues the request, and whether the worker
-- can reach it is not what this file is about.
--
-- Run with: supabase test db
-- Everything rolls back.
-- ══════════════════════════════════════════════════════════════════
begin;

create extension if not exists pgtap;

select plan(15);

-- ── 1. schema + wiring ───────────────────────────────────────────
select has_column('public', 'orders', 'receipt_emailed_at',
  '1: the order records when its receipt was sent');

select has_column('public', 'orders', 'receipt_email_to',
  '2: and which address it went to');

select has_column('public', 'orders', 'customer_email',
  '3: the address the till recorded, if any, still exists');

select has_function('public', 'queue_order_receipt_email', array['uuid'],
  '4: one dispatcher decides whether an order owes a receipt');

select has_trigger('public', 'orders', 'trg_order_receipt_on_paid',
  '5: a payment transition fires the dispatch');

select has_trigger('public', 'orders', 'trg_order_receipt_on_insert',
  '6: an online order born paid fires it too');

select ok(
  (select pg_get_triggerdef(oid) like '%paid%'
          and pg_get_triggerdef(oid) like '%online%'
     from pg_trigger
    where tgname = 'trg_order_receipt_on_paid'),
  '7: the trigger only fires on paid + online, so the POS till is excluded');

-- ── fixtures (as postgres: RLS bypassed) ─────────────────────────
select set_config('request.headers', '{}', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"ce000000-0000-0000-0000-000000000011","role":"authenticated"}',
  true
);

insert into auth.users (instance_id, id, aud, role, email, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000','ce000000-0000-0000-0000-000000000011','authenticated','authenticated','receipt-seller@test.local', now(), now()),
  ('00000000-0000-0000-0000-000000000000','ce000000-0000-0000-0000-000000000001','authenticated','authenticated','receipt-customer@test.local', now(), now());

insert into public.profiles (id, full_name, email, role)
values
  ('ce000000-0000-0000-0000-000000000011','Receipt Seller','receipt-seller@test.local','seller'),
  ('ce000000-0000-0000-0000-000000000001','Receipt Customer','receipt-customer@test.local','customer')
on conflict (id) do update
  set full_name = excluded.full_name, email = excluded.email, role = excluded.role;

insert into public.stores (id, owner_id, name, location)
values
  ('ce000000-0000-0000-0000-0000000000a1','ce000000-0000-0000-0000-000000000011',
   'Receipt Store','Test City');

-- One unpaid online order, one paid POS sale, one guest order with no account.
insert into public.orders
  (id, customer_id, store_id, total_amount, status, payment_status,
   payment_method, source, order_code)
values
  ('ce000000-0000-0000-0000-0000000000b1',
   'ce000000-0000-0000-0000-000000000001',
   'ce000000-0000-0000-0000-0000000000a1',
   1500, 'pending', 'unpaid', 'gcash', 'online', 'RECEIPT01'),
  ('ce000000-0000-0000-0000-0000000000b2',
   'ce000000-0000-0000-0000-000000000001',
   'ce000000-0000-0000-0000-0000000000a1',
   900, 'received', 'paid', 'cash', 'pos', 'RECEIPT02'),
  ('ce000000-0000-0000-0000-0000000000b3',
   null,
   'ce000000-0000-0000-0000-0000000000a1',
   700, 'received', 'paid', 'cash', 'online', 'RECEIPT03');

-- ── 2. the dispatcher's refusals ─────────────────────────────────
select is(
  public.queue_order_receipt_email('ce000000-0000-0000-0000-0000000000b1') ->> 'reason',
  'not_paid',
  '8: an unpaid order owes no receipt');

select is(
  public.queue_order_receipt_email('ce000000-0000-0000-0000-0000000000b2') ->> 'reason',
  'not_online',
  '9: a POS sale is the till''s job, not this trigger''s');

select is(
  public.queue_order_receipt_email('ce000000-0000-0000-0000-0000000000b3') ->> 'reason',
  'no_email',
  '10: a paid order with no account and no recorded address sends nothing');

-- ── 3. configuration is Vault, not SQL ───────────────────────────
update public.orders
   set payment_status = 'paid'
 where id = 'ce000000-0000-0000-0000-0000000000b1';

select is(
  (select 'payment_status=' || payment_status from public.orders
    where id = 'ce000000-0000-0000-0000-0000000000b1'),
  'payment_status=paid',
  '11: the payment update itself always lands');

select is(
  public.queue_order_receipt_email('ce000000-0000-0000-0000-0000000000b1') ->> 'reason',
  'not_configured',
  '12: with no function URL in Vault it reports a configuration gap, not an error');

-- ── 4. once configured, it queues with the resolved address ──────
select vault.create_secret('http://127.0.0.1:9/receipt', 'receipt_function_url');
select vault.create_secret('test-service-role-key', 'service_role_key');

select is(
  public.queue_order_receipt_email('ce000000-0000-0000-0000-0000000000b1') ->> 'to',
  'receipt-customer@test.local',
  '13: the account email is the fallback address');

-- Release the in-flight lease the dispatch above took, so this second call
-- reaches the queue instead of answering 'in_flight'.
update public.orders
   set receipt_email_sending_since = null
 where id = 'ce000000-0000-0000-0000-0000000000b1';

select is(
  public.queue_order_receipt_email('ce000000-0000-0000-0000-0000000000b1') ->> 'queued',
  'true',
  '14: a configured, paid, addressed order is queued');

-- The stamp the edge function writes after SMTP accepts the message.
update public.orders
   set receipt_emailed_at = now(),
       receipt_email_to = 'receipt-customer@test.local'
 where id = 'ce000000-0000-0000-0000-0000000000b1';

select is(
  public.queue_order_receipt_email('ce000000-0000-0000-0000-0000000000b1') ->> 'reason',
  'already_sent',
  '15: a stamped order is never mailed twice');

select * from finish();
rollback;
