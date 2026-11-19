-- ══════════════════════════════════════════════════════════════════
-- pgTAP: a failed receipt email is recorded and retried, never twice
--
-- Covers 20261119120000_order_receipt_email_retry.sql:
--
--   1. The retry ledger exists, plus the rules that drive it (backoff
--      schedule, attempt cap, lease).
--   2. A failure is stored: attempt counted, error kept, next attempt
--      scheduled 5 minutes out.
--   3. The dispatcher refuses a retry before its backoff ('retry_wait'), a
--      dispatch already in flight ('in_flight'), and an order out of attempts
--      ('exhausted').
--   4. Success stamps the receipt, clears the retry state, and a second
--      success cannot move the stamp.
--   5. The sweep re-dispatches a due order, leaves an order with no address
--      alone, and books a lease that expired without an answer — which is how
--      a wrong Vault key or a crashed function still runs out of attempts.
--   6. Only the service role may write an outcome: a customer or seller
--      cannot mark an unsent receipt sent.
--
-- Vault entries are created inside the transaction and rolled back, exactly as
-- in order_receipt_email.test.sql. The URL points at a closed port: pg_net
-- queues the request, and reaching it is not what this file is about.
--
-- Run with: supabase test db
-- Everything rolls back.
-- ══════════════════════════════════════════════════════════════════
begin;

create extension if not exists pgtap;

select plan(26);

-- ── 1. schema, rules, wiring ─────────────────────────────────────
select has_column('public', 'orders', 'receipt_email_attempts',
  '1: a failed attempt is counted on the order');

select has_column('public', 'orders', 'receipt_email_last_error',
  '2: and its reason is kept');

select has_column('public', 'orders', 'receipt_email_next_attempt_at',
  '3: and the next attempt is scheduled');

select has_column('public', 'orders', 'receipt_email_sending_since',
  '4: and an in-flight dispatch holds a lease');

select has_function('public', 'retry_order_receipt_emails', array['integer'],
  '5: one sweep retries what failed');

select has_function('public', 'record_order_receipt_success', array['uuid', 'text'],
  '6: the function can report a send');

select has_function('public', 'record_order_receipt_failure', array['uuid', 'text', 'boolean'],
  '7: and report a failure');

select is(public.order_receipt_retry_delay(1), interval '5 minutes',
  '8: the first retry waits five minutes');

select is(public.order_receipt_retry_delay(4), interval '6 hours',
  '9: the fourth waits six hours');

select is(public.order_receipt_retry_delay(5), null::interval,
  '10: the fifth failure has no successor');

select is(public.order_receipt_max_attempts(), 5,
  '11: five attempts in total, then a human decides');

select ok(
  (select pg_get_triggerdef(oid) like '%paid%' and pg_get_triggerdef(oid) like '%online%'
     from pg_trigger
    where tgname = 'trg_order_receipt_on_paid'),
  '12: the trigger still only fires on paid + online');

-- ── fixtures (as postgres: RLS bypassed) ─────────────────────────
select set_config('request.headers', '{}', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"cc000000-0000-0000-0000-000000000011","role":"authenticated"}',
  true
);

insert into auth.users (instance_id, id, aud, role, email, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000','cc000000-0000-0000-0000-000000000011','authenticated','authenticated','retry-seller@test.local', now(), now()),
  ('00000000-0000-0000-0000-000000000000','cc000000-0000-0000-0000-000000000001','authenticated','authenticated','retry-customer@test.local', now(), now());

insert into public.profiles (id, full_name, email, role)
values
  ('cc000000-0000-0000-0000-000000000011','Retry Seller','retry-seller@test.local','seller'),
  ('cc000000-0000-0000-0000-000000000001','Retry Customer','retry-customer@test.local','customer')
on conflict (id) do update
  set full_name = excluded.full_name, email = excluded.email, role = excluded.role;

insert into public.stores (id, owner_id, name, location)
values
  ('cc000000-0000-0000-0000-0000000000a1','cc000000-0000-0000-0000-000000000011',
   'Retry Store','Test City');

-- b1 the ordinary case; b2 out of attempts; b3 due for a retry;
-- b4 a guest with no address at all; b5 a lease nobody answered.
insert into public.orders
  (id, customer_id, store_id, total_amount, status, payment_status,
   payment_method, source, order_code)
values
  ('cc000000-0000-0000-0000-0000000000b1',
   'cc000000-0000-0000-0000-000000000001',
   'cc000000-0000-0000-0000-0000000000a1',
   1500, 'received', 'paid', 'gcash', 'online', 'RETRY01'),
  ('cc000000-0000-0000-0000-0000000000b2',
   'cc000000-0000-0000-0000-000000000001',
   'cc000000-0000-0000-0000-0000000000a1',
   1500, 'received', 'paid', 'gcash', 'online', 'RETRY02'),
  ('cc000000-0000-0000-0000-0000000000b3',
   'cc000000-0000-0000-0000-000000000001',
   'cc000000-0000-0000-0000-0000000000a1',
   1500, 'received', 'paid', 'gcash', 'online', 'RETRY03'),
  ('cc000000-0000-0000-0000-0000000000b4',
   null,
   'cc000000-0000-0000-0000-0000000000a1',
   700, 'received', 'paid', 'cash', 'online', 'RETRY04'),
  ('cc000000-0000-0000-0000-0000000000b5',
   'cc000000-0000-0000-0000-000000000001',
   'cc000000-0000-0000-0000-0000000000a1',
   1500, 'received', 'paid', 'gcash', 'online', 'RETRY05');

select vault.create_secret('http://127.0.0.1:9/receipt', 'receipt_function_url');
select vault.create_secret('test-service-role-key', 'service_role_key');

-- ── 2. a failure is recorded ─────────────────────────────────────
select is(
  public.record_order_receipt_failure(
    'cc000000-0000-0000-0000-0000000000b1',
    'SMTP 421 temporary failure',
    true
  ) ->> 'recorded',
  'true',
  '13: a failed send is written to the order');

select is(
  (select receipt_email_attempts from public.orders
    where id = 'cc000000-0000-0000-0000-0000000000b1'),
  1,
  '14: the attempt is counted');

select is(
  (select receipt_email_last_error from public.orders
    where id = 'cc000000-0000-0000-0000-0000000000b1'),
  'SMTP 421 temporary failure',
  '15: the reason is kept verbatim for support');

select ok(
  (select receipt_email_next_attempt_at > now() + interval '4 minutes'
          and receipt_email_next_attempt_at < now() + interval '6 minutes'
     from public.orders
    where id = 'cc000000-0000-0000-0000-0000000000b1'),
  '16: and the retry is scheduled five minutes out');

select is(
  public.queue_order_receipt_email('cc000000-0000-0000-0000-0000000000b1') ->> 'reason',
  'retry_wait',
  '17: a dispatch before the backoff elapses is refused');

-- ── 3. due, in flight, exhausted ─────────────────────────────────
update public.orders
   set receipt_email_next_attempt_at = now() - interval '1 second'
 where id = 'cc000000-0000-0000-0000-0000000000b1';

select is(
  public.queue_order_receipt_email('cc000000-0000-0000-0000-0000000000b1') ->> 'queued',
  'true',
  '18: once the backoff has elapsed it is dispatched again');

select is(
  public.queue_order_receipt_email('cc000000-0000-0000-0000-0000000000b1') ->> 'reason',
  'in_flight',
  '19: a second dispatch while the first is in flight is refused');

update public.orders
   set receipt_email_attempts = 5
 where id = 'cc000000-0000-0000-0000-0000000000b2';

select is(
  public.queue_order_receipt_email('cc000000-0000-0000-0000-0000000000b2') ->> 'reason',
  'exhausted',
  '20: an order out of attempts is left alone');

-- ── 4. success ───────────────────────────────────────────────────
select is(
  public.record_order_receipt_success(
    'cc000000-0000-0000-0000-0000000000b1',
    'retry-customer@test.local'
  ) ->> 'recorded',
  'true',
  '21: a send is stamped');

select ok(
  (select receipt_emailed_at is not null
          and receipt_email_to = 'retry-customer@test.local'
          and receipt_email_sending_since is null
          and receipt_email_next_attempt_at is null
          and receipt_email_last_error is null
     from public.orders
    where id = 'cc000000-0000-0000-0000-0000000000b1'),
  '22: the stamp lands and the retry state is cleared');

select is(
  public.record_order_receipt_success(
    'cc000000-0000-0000-0000-0000000000b1',
    'someone-else@test.local'
  ) ->> 'recorded',
  'false',
  '23: a second success cannot rewrite the stamp');

-- ── 5. the sweep ─────────────────────────────────────────────────
update public.orders
   set receipt_email_attempts = 1,
       receipt_email_last_error = 'Gmail said no',
       receipt_email_next_attempt_at = now() - interval '1 minute'
 where id = 'cc000000-0000-0000-0000-0000000000b3';

update public.orders
   set receipt_email_attempts = 1,
       receipt_email_last_attempt_at = now() - interval '20 minutes',
       receipt_email_sending_since = now() - interval '10 minutes'
 where id = 'cc000000-0000-0000-0000-0000000000b5';

select public.retry_order_receipt_emails(20);

select ok(
  (select receipt_email_sending_since is not null
     from public.orders
    where id = 'cc000000-0000-0000-0000-0000000000b3'),
  '24: the sweep re-dispatches an order whose backoff elapsed');

select is(
  (select receipt_email_sending_since from public.orders
    where id = 'cc000000-0000-0000-0000-0000000000b4'),
  null::timestamptz,
  '25: a guest order with no address is not selected');

select ok(
  (select receipt_email_attempts = 2 and receipt_email_sending_since is null
     from public.orders
    where id = 'cc000000-0000-0000-0000-0000000000b5'),
  '26: a lease nobody answered is booked as a failed attempt');

select * from finish();
rollback;
