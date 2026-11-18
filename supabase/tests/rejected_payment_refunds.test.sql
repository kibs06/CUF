-- ══════════════════════════════════════════════════════════════════
-- pgTAP: rejected payments leave a refund to make
--
-- Covers 20261118130000_rejected_payment_refunds.sql:
--   • a 3rd rejection cancels the order as 'refund_pending', not 'failed'
--   • a cancellation with no proof still records 'failed'
--   • admin_list_refund_owed carries the reference, amount and screenshot
--   • admin_mark_refund_refunded closes the task with the GCash reference,
--     writes the payment event and tells the customer
--
-- Run with: supabase test db. Everything happens inside one transaction and
-- is rolled back.
-- ══════════════════════════════════════════════════════════════════
begin;

create extension if not exists pgtap;

select plan(27);

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
-- Creating a profile writes a seller_application_audit_log row whose
-- actor_id is auth.uid(); without a claim the fixture insert is rejected.
select set_config(
  'request.jwt.claims',
  '{"sub":"d0000000-0000-0000-0000-0000000000fa","role":"authenticated"}',
  true
);

insert into auth.users (instance_id, id, aud, role, email, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000','d0000000-0000-0000-0000-000000000001','authenticated','authenticated','rf-customer@test.local', now(), now()),
  ('00000000-0000-0000-0000-000000000000','d0000000-0000-0000-0000-000000000002','authenticated','authenticated','rf-seller@test.local',   now(), now()),
  ('00000000-0000-0000-0000-000000000000','d0000000-0000-0000-0000-0000000000fa','authenticated','authenticated','rf-admin@test.local',    now(), now());

insert into public.profiles (id, full_name, email, role)
values
  ('d0000000-0000-0000-0000-000000000001','RF Customer','rf-customer@test.local','customer'),
  ('d0000000-0000-0000-0000-000000000002','RF Seller','rf-seller@test.local','seller'),
  ('d0000000-0000-0000-0000-0000000000fa','RF Admin','rf-admin@test.local','admin')
on conflict (id) do update
  set full_name = excluded.full_name, role = excluded.role;

insert into public.stores (id, owner_id, name, location)
values ('d0000000-0000-0000-0000-0000000000a1','d0000000-0000-0000-0000-000000000002',
        'RF Store','Test City');

insert into public.products (id, store_id, seller_id, name, price, is_active)
values ('d0000000-0000-0000-0000-0000000000b1','d0000000-0000-0000-0000-0000000000a1',
        'd0000000-0000-0000-0000-000000000002','RF Shoe', 1000, true);

insert into public.inventory (product_id, size, stock)
values ('d0000000-0000-0000-0000-0000000000b1','40', 10);

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

-- ── 1–3. the refund's paper trail exists ─────────────────────────
select has_column('public','orders','refund_reference',
  '1: an order can hold the GCash reference of the refund it was given');
select has_column('public','orders','refunded_at',
  '2: an order records when the refund was sent');
select has_column('public','orders','refunded_by',
  '3: an order records which admin sent it');

-- ── 4. checkout ──────────────────────────────────────────────────
select pg_temp.claims('d0000000-0000-0000-0000-000000000001');

insert into _t (k, order_id)
select 'o1', (j ->> 'order_id')::uuid
  from (
    select public.create_gcash_checkout(
      '[{"product_id":"d0000000-0000-0000-0000-0000000000b1","size":"40","quantity":1}]'::jsonb,
      'Test address', null) as j
  ) s;

select is(
  (select stock from public.inventory
    where product_id = 'd0000000-0000-0000-0000-0000000000b1' and size = '40'),
  10,
  '4: checkout takes no stock — an unpaid order holds nothing'
);

-- ── 5–13. three attempts, each rejected ──────────────────────────
-- Attempt 1
select lives_ok(
  format($$ select public.submit_gcash_proof(
    %L::uuid, '9000000000001', 'Rf Customer', 1100.00,
    %L, repeat('c', 64), now()) $$,
    (select order_id from _t where k = 'o1'),
    (select order_id from _t where k = 'o1')::text || '/shot1.jpg'),
  '5: attempt 1 is accepted'
);

select pg_temp.claims('d0000000-0000-0000-0000-000000000002');
select is(
  (public.reject_gcash_proof(
     (select order_id from _t where k = 'o1'), 'No matching transfer') ->> 'status'),
  'awaiting_payment_confirmation',
  '6: the first rejection gives the order back, it does not cancel it'
);

-- Attempt 2
select pg_temp.claims('d0000000-0000-0000-0000-000000000001');
select lives_ok(
  format($$ select public.submit_gcash_proof(
    %L::uuid, '9000000000002', 'Rf Customer', 1100.00,
    %L, repeat('d', 64), now()) $$,
    (select order_id from _t where k = 'o1'),
    (select order_id from _t where k = 'o1')::text || '/shot2.jpg'),
  '7: attempt 2 is accepted'
);

select pg_temp.claims('d0000000-0000-0000-0000-000000000002');
select is(
  (public.reject_gcash_proof(
     (select order_id from _t where k = 'o1'), 'Still no matching transfer') ->> 'status'),
  'awaiting_payment_confirmation',
  '8: the second rejection gives the order back too'
);

-- Attempt 3 — the one that cancels
select pg_temp.claims('d0000000-0000-0000-0000-000000000001');
select lives_ok(
  format($$ select public.submit_gcash_proof(
    %L::uuid, '9000000000003', 'Rf Customer', 1100.00,
    %L, repeat('e', 64), now()) $$,
    (select order_id from _t where k = 'o1'),
    (select order_id from _t where k = 'o1')::text || '/shot3.jpg'),
  '9: attempt 3 is accepted'
);

select pg_temp.claims('d0000000-0000-0000-0000-000000000002');
select is(
  (public.reject_gcash_proof(
     (select order_id from _t where k = 'o1'), 'Third strike') ->> 'status'),
  'cancelled',
  '10: the third rejection cancels the order'
);

select is(
  (select payment_status from public.orders where id = (select order_id from _t where k = 'o1')),
  'refund_pending',
  '11: a cancelled order that had a proof is a refund owed, not a failed payment'
);

select is(
  (select stock from public.inventory
    where product_id = 'd0000000-0000-0000-0000-0000000000b1' and size = '40'),
  10,
  '12: the cancelled checkout never took stock, so there is nothing to return'
);

select is(
  (select count(*)::int from public.order_items
    where order_id = (select order_id from _t where k = 'o1')),
  0,
  '13: the items were released'
);

-- Every notification in this transaction carries the same now(), so "the
-- newest" is arbitrary; ask whether the notice exists at all.
select ok(
  exists (
    select 1 from public.notifications
     where user_id = 'd0000000-0000-0000-0000-000000000001'
       and order_id = (select order_id from _t where k = 'o1')
       and title = 'Payment rejected — refund on the way'
  ),
  '14: the customer is told the money is coming back'
);

-- ── 15–16. an order with no proof is still a plain failure ───────
select pg_temp.claims('d0000000-0000-0000-0000-000000000001');
insert into _t (k, order_id)
select 'o2', (j ->> 'order_id')::uuid
  from (
    select public.create_gcash_checkout(
      '[{"product_id":"d0000000-0000-0000-0000-0000000000b1","size":"40","quantity":1}]'::jsonb,
      'Test address', null) as j
  ) s;

select public.cancel_my_pending_gcash_checkout((select order_id from _t where k = 'o2'));

select is(
  (select payment_status from public.orders where id = (select order_id from _t where k = 'o2')),
  'failed',
  '15: cancelling an order nobody paid for is still a failure'
);

select is(
  (select count(*)::int from public.notifications
    where order_id = (select order_id from _t where k = 'o2')
      and title like '%refund%'),
  0,
  '16: and it does not promise a refund the customer never paid for'
);

-- ── 17–21. the admin queue ───────────────────────────────────────
select pg_temp.claims('d0000000-0000-0000-0000-0000000000fa');

select is(
  (select count(*)::int from public.admin_list_refund_owed()),
  1,
  '17: the queue lists exactly the order that is owed'
);

select is(
  (select r_reference from public.admin_list_refund_owed()
    where r_order_id = (select order_id from _t where k = 'o1')),
  '9000000000003',
  '18: it carries the reference of the attempt that cancelled the order'
);

select is(
  (select r_amount_paid from public.admin_list_refund_owed()
    where r_order_id = (select order_id from _t where k = 'o1')),
  1100.00::numeric,
  '19: it carries the amount the customer says was sent'
);

select ok(
  (select r_screenshot_path from public.admin_list_refund_owed()
    where r_order_id = (select order_id from _t where k = 'o1'))
  like '%/shot3.jpg',
  '20: it carries the screenshot path of that attempt'
);

select pg_temp.claims('d0000000-0000-0000-0000-000000000002');
select throws_ok(
  $$ select * from public.admin_list_refund_owed() $$,
  '42501',
  'Only admins can see refunds owed',
  '21: a seller cannot read the refund queue'
);

-- ── 22–27. closing the task ─────────────────────────────────────
select pg_temp.claims('d0000000-0000-0000-0000-0000000000fa');

select throws_ok(
  format($$ select public.admin_mark_refund_refunded(%L::uuid, 'ab') $$,
    (select order_id from _t where k = 'o1')),
  'P0001',
  'Record the GCash reference of the refund',
  '22: a refund without a usable reference is refused'
);

select is(
  (public.admin_mark_refund_refunded(
     (select order_id from _t where k = 'o1'), '4047398097426', 'Sent back') ->> 'payment_status'),
  'refunded',
  '23: recording the transfer closes the refund'
);

select is(
  (select refund_reference from public.orders where id = (select order_id from _t where k = 'o1')),
  '4047398097426',
  '24: the refund reference is kept on the order'
);

select is(
  (select count(*)::int from public.order_payment_events
    where order_id = (select order_id from _t where k = 'o1')
      and event_type = 'refunded'),
  1,
  '25: the refund is on the payment event log'
);

select ok(
  exists (
    select 1 from public.notifications
     where user_id = 'd0000000-0000-0000-0000-000000000001'
       and order_id = (select order_id from _t where k = 'o1')
       and title = 'Refund sent'
  ),
  '26: the customer is told the money is back'
);

select is(
  (select count(*)::int from public.admin_list_refund_owed()),
  0,
  '27: a closed refund leaves the default queue (and needs the flag to be seen again)'
);

select * from finish();
rollback;
