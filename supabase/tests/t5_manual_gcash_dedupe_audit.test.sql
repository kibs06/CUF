-- ══════════════════════════════════════════════════════════════════
-- T5 manual-GCash hardening tests (pgTAP) — run by CI via
-- `supabase test db` (workflow: supabase-migrations.yml).
--
-- Covers migration 20260905000000_fix_t5_manual_gcash_dedupe_audit:
--   1. POS reference-number dedupe (partial unique index on paid
--      orders) — reuse rejected, no over-blocking of pending rows.
--   2. gcash_payment_decision_audit — POS confirm trigger writes
--      correct rows once (and not again on a no-op update); the
--      queue confirm/reject RPCs write source='queue' rows with
--      reference + amount captured at decision time.
--   3. create_gcash_checkout EXECUTE revoked from authenticated
--      (remote route closed) while submit/confirm/reject stay
--      executable so legacy awaiting orders can still resolve.
--   4. RLS: non-admin sees 0 audit rows and cannot insert; admin
--      sees them.
-- ══════════════════════════════════════════════════════════════════

begin;
select plan(30);

-- ── clear any JWT context ─────────────────────────────────────────
select set_config('request.jwt.claims', '{"sub":null,"role":null}', true);

-- ── fixtures (as postgres; RLS bypassed) ──────────────────────────
insert into auth.users (instance_id, id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000aa', 'authenticated', 'authenticated', 't5-customer@test.local', '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000bb', 'authenticated', 'authenticated', 't5-customer2@test.local', '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000cc', 'authenticated', 'authenticated', 't5-seller@test.local', '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000dd', 'authenticated', 'authenticated', 't5-admin@test.local', '{}', '{}', now(), now());

insert into public.profiles (id, full_name, email, role, seller_status)
values
  ('00000000-0000-0000-0000-0000000000aa', 'T5 Customer',   't5-customer@test.local',  'customer', 'none'),
  ('00000000-0000-0000-0000-0000000000bb', 'T5 Customer 2', 't5-customer2@test.local', 'customer', 'none'),
  ('00000000-0000-0000-0000-0000000000cc', 'T5 Seller',     't5-seller@test.local',    'seller',   'approved'),
  ('00000000-0000-0000-0000-0000000000dd', 'T5 Admin',      't5-admin@test.local',     'admin',    'none');

insert into public.stores (id, name, location, owner_id)
values ('00000000-0000-0000-0000-0000000000ee', 'T5 Store', 'Manila', '00000000-0000-0000-0000-0000000000cc');

-- ── structural checks ─────────────────────────────────────────────
select is(
  to_regindex('public.uq_orders_gcash_reference_number_paid') IS NOT NULL,
  true,
  '1: dedupe partial unique index exists on orders'
);

select ok(
  exists (
    select 1 from pg_trigger
    where tgname = 'trg_log_pos_gcash_confirm_audit'
      and tgrelid = 'public.orders'::regclass
  ),
  '2: POS confirm audit trigger exists on orders'
);

select is(
  (select relrowsecurity from pg_class
    where oid = 'public.gcash_payment_decision_audit'::regclass),
  true,
  '3: gcash_payment_decision_audit has RLS enabled'
);

-- ── RPC grants (remote route closed, legacy resolution preserved) ─
select is(
  has_function_privilege('authenticated', 'public.create_gcash_checkout(jsonb,text,jsonb)', 'EXECUTE'),
  false,
  '4: create_gcash_checkout revoked from authenticated (remote order creation closed)'
);

select is(
  has_function_privilege('authenticated', 'public.submit_gcash_proof(uuid,text,text)', 'EXECUTE'),
  true,
  '5: submit_gcash_proof still executable (legacy awaiting orders resolve)'
);

select is(
  has_function_privilege('authenticated', 'public.confirm_gcash_payment(uuid)', 'EXECUTE'),
  true,
  '6: confirm_gcash_payment still executable'
);

select is(
  has_function_privilege('authenticated', 'public.reject_gcash_payment(uuid,text)', 'EXECUTE'),
  true,
  '7: reject_gcash_payment still executable'
);

-- ── dedupe behavior (POS) ─────────────────────────────────────────
-- First use of a reference on a PAID order is accepted.
select lives_ok(
  $sql$
    insert into public.orders
      (id, customer_id, store_id, status, total_amount, payment_method,
       payment_status, fulfillment, source, gcash_reference_number)
    values
      ('11111111-1111-1111-1111-111111111101', '00000000-0000-0000-0000-0000000000aa',
       '00000000-0000-0000-0000-0000000000ee', 'received', 500.00, 'gcash',
       'paid', 'pickup', 'pos', '1111111111111')
  $sql$,
  '8: first use of a reference on a paid order is accepted'
);

-- Reuse of that reference on a SECOND paid order is rejected (23505).
select throws_ok(
  $sql$
    insert into public.orders
      (id, customer_id, store_id, status, total_amount, payment_method,
       payment_status, fulfillment, source, gcash_reference_number)
    values
      ('11111111-1111-1111-1111-111111111102', '00000000-0000-0000-0000-0000000000aa',
       '00000000-0000-0000-0000-0000000000ee', 'received', 600.00, 'gcash',
       'paid', 'pickup', 'pos', '1111111111111')
  $sql$,
  null,
  'duplicate key value violates unique constraint "uq_orders_gcash_reference_number_paid"',
  '9: reused reference on a second paid order is rejected (23505)'
);

-- A PENDING order may carry the same reference — not yet confirmed.
select lives_ok(
  $sql$
    insert into public.orders
      (id, customer_id, store_id, status, total_amount, payment_method,
       payment_status, fulfillment, source, gcash_reference_number)
    values
      ('11111111-1111-1111-1111-111111111103', '00000000-0000-0000-0000-0000000000aa',
       '00000000-0000-0000-0000-0000000000ee', 'received', 400.00, 'gcash',
       'pending', 'pickup', 'pos', '1111111111111')
  $sql$,
  '10: pending (unconfirmed) order may carry the same reference — dedupe does not over-block'
);

-- A different reference on a second paid order is accepted.
select lives_ok(
  $sql$
    insert into public.orders
      (id, customer_id, store_id, status, total_amount, payment_method,
       payment_status, fulfillment, source, gcash_reference_number)
    values
      ('11111111-1111-1111-1111-111111111104', '00000000-0000-0000-0000-0000000000aa',
       '00000000-0000-0000-0000-0000000000ee', 'received', 700.00, 'gcash',
       'paid', 'pickup', 'pos', '2222222222222')
  $sql$,
  '11: a different reference on a paid order is accepted'
);

-- ── POS confirm audit trigger ─────────────────────────────────────
insert into public.orders
  (id, customer_id, store_id, status, total_amount, payment_method,
   payment_status, fulfillment, source)
values
  ('11111111-1111-1111-1111-111111111105', '00000000-0000-0000-0000-0000000000aa',
   '00000000-0000-0000-0000-0000000000ee', 'received', 750.00, 'gcash',
   'pending', 'pickup', 'pos');

-- Seller confirms: flips payment_status to paid and types the ref.
update public.orders
   set payment_status = 'paid', gcash_reference_number = '3333333333333'
 where id = '11111111-1111-1111-1111-111111111105';

select is(
  (select count(*) from public.gcash_payment_decision_audit
    where order_id = '11111111-1111-1111-1111-111111111105'),
  1,
  '12: POS confirm writes exactly one audit row'
);

select is(
  (select decision from public.gcash_payment_decision_audit
    where order_id = '11111111-1111-1111-1111-111111111105'),
  'confirmed',
  '13: POS audit decision = confirmed'
);

select is(
  (select source from public.gcash_payment_decision_audit
    where order_id = '11111111-1111-1111-1111-111111111105'),
  'pos',
  '14: POS audit source = pos'
);

select is(
  (select reference_number from public.gcash_payment_decision_audit
    where order_id = '11111111-1111-1111-1111-111111111105'),
  '3333333333333',
  '15: POS audit reference_number captured'
);

select is(
  (select amount_shown_to_seller from public.gcash_payment_decision_audit
    where order_id = '11111111-1111-1111-1111-111111111105'),
  750.00,
  '16: POS audit amount_shown_to_seller = order total at decision time'
);

-- No double-log: re-setting the same paid status writes nothing more.
update public.orders set payment_status = 'paid' where id = '11111111-1111-1111-1111-111111111105';

select is(
  (select count(*) from public.gcash_payment_decision_audit
    where order_id = '11111111-1111-1111-1111-111111111105'),
  1,
  '17: no-op re-confirmation does not duplicate the audit row'
);

-- ── queue flow RPCs (dormant direct flow) ─────────────────────────
-- Two awaiting orders + proofs for the seller to decide on.
insert into public.orders
  (id, customer_id, store_id, status, total_amount, payment_method,
   payment_status, fulfillment, source, payment_confirmation_deadline)
values
  ('11111111-1111-1111-1111-111111111106', '00000000-0000-0000-0000-0000000000aa',
   '00000000-0000-0000-0000-0000000000ee', 'awaiting_payment_confirmation', 900.00, 'gcash',
   'pending', 'pickup', 'online', now() + interval '30 minutes'),
  ('11111111-1111-1111-1111-111111111107', '00000000-0000-0000-0000-0000000000bb',
   '00000000-0000-0000-0000-0000000000ee', 'awaiting_payment_confirmation', 800.00, 'gcash',
   'pending', 'pickup', 'online', now() + interval '30 minutes');

insert into public.gcash_payment_proofs
  (order_id, reference_number, screenshot_url, submitted_by)
values
  ('11111111-1111-1111-1111-111111111106', '4444444444444', '11111111-1111-1111-1111-111111111106/shot.jpg', '00000000-0000-0000-0000-0000000000aa'),
  ('11111111-1111-1111-1111-111111111107', '5555555555555', '11111111-1111-1111-1111-111111111107/shot.jpg', '00000000-0000-0000-0000-0000000000bb');

-- Non-owner (the customer) cannot confirm — owner-only guard intact.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-0000000000aa","role":"authenticated"}',
  true
);
set role authenticated;

select throws_ok(
  'select public.confirm_gcash_payment(''11111111-1111-1111-1111-111111111106'')',
  null,
  'Only the store owner can confirm this payment',
  '18: non-owner confirm is rejected'
);

reset role;

-- Owner confirms order E.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-0000000000cc","role":"authenticated"}',
  true
);
set role authenticated;

select lives_ok(
  'select public.confirm_gcash_payment(''11111111-1111-1111-1111-111111111106'')',
  '19: store owner can confirm an awaiting order'
);

reset role;

select is(
  (select count(*) from public.gcash_payment_decision_audit
    where order_id = '11111111-1111-1111-1111-111111111106'),
  1,
  '20: queue confirm writes exactly one audit row'
);

select is(
  (select decision from public.gcash_payment_decision_audit
    where order_id = '11111111-1111-1111-1111-111111111106'),
  'confirmed',
  '21: queue audit decision = confirmed'
);

select is(
  (select source from public.gcash_payment_decision_audit
    where order_id = '11111111-1111-1111-1111-111111111106'),
  'queue',
  '22: queue audit source = queue'
);

select is(
  (select seller_id from public.gcash_payment_decision_audit
    where order_id = '11111111-1111-1111-1111-111111111106'),
  '00000000-0000-0000-0000-0000000000cc',
  '23: queue audit seller_id = acting seller'
);

select is(
  (select reference_number from public.gcash_payment_decision_audit
    where order_id = '11111111-1111-1111-1111-111111111106'),
  '4444444444444',
  '24: queue audit reference_number from the proof'
);

select is(
  (select amount_shown_to_seller from public.gcash_payment_decision_audit
    where order_id = '11111111-1111-1111-1111-111111111106'),
  900.00,
  '25: queue audit amount_shown_to_seller = order total at decision time'
);

-- Owner rejects order F.
set role authenticated;

select lives_ok(
  'select public.reject_gcash_payment(''11111111-1111-1111-1111-111111111107'', ''No matching GCash transaction found'')',
  '26: store owner can reject an awaiting order'
);

reset role;

select is(
  (select decision from public.gcash_payment_decision_audit
    where order_id = '11111111-1111-1111-1111-111111111107'),
  'rejected',
  '27: queue audit decision = rejected'
);

-- ── RLS on the audit table ────────────────────────────────────────
-- Non-admin (customer) sees zero rows and cannot insert.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-0000000000aa","role":"authenticated"}',
  true
);
set role authenticated;

select is(
  (select count(*) from public.gcash_payment_decision_audit),
  0,
  '28: non-admin reads zero audit rows'
);

select throws_ok(
  $sql$
    insert into public.gcash_payment_decision_audit
      (order_id, seller_id, reference_number, amount_shown_to_seller, decision, source)
    values
      ('11111111-1111-1111-1111-111111111101', '00000000-0000-0000-0000-0000000000aa',
       '9999999999999', 1.00, 'confirmed', 'pos')
  $sql$,
  null,
  'permission denied',
  '29: non-admin direct insert into the audit table is denied'
);

reset role;

-- Admin sees the audit rows.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-0000000000dd","role":"authenticated"}',
  true
);
set role authenticated;

select ok(
  (select count(*) from public.gcash_payment_decision_audit) > 0,
  '30: admin reads audit rows'
);

reset role;

select * from finish();
rollback;