-- ══════════════════════════════════════════════════════════════════
-- pgTAP: manual GCash — the WHOLE lifecycle, through the real RPCs
--
-- One connected session, one transaction, real Postgres. Nothing here
-- inspects SQL text: every assertion is the observable state after a
-- function ran (or the exact error it raised).
--
-- Path exercised:
--   admin opens the platform account  → one active row only
--   single-store checkout             → order_code, amount, platform
--                                       number + QR, stock reserved
--   cross-store cart                  → refused, nothing reserved
--   proof submit                      → payment_under_review, 24 h SLA
--   duplicate ref / duplicate hash /
--     wrong amount                    → refused by the database
--   reject ×3                         → alive, alive, then cancelled
--                                       exactly once, stock returned
--   verify_gcash_payment (seller)     → pending + paid
--   admin_verify_payment              → pending + paid
--   admin_reconcile_order             → funds_reconciled_at
--   expire_unpaid_gcash_orders        → unpaid order dies, an under-review
--                                       order does NOT
--   generate_daily_payouts            → per-store draft lines
--   mark_payout_paid                  → paid + receipt, idempotent replay
--   RLS                               → other sellers see nothing; non-admins
--                                       cannot call admin_* or write config
--
-- Run with: supabase test db
--   or:     psql -d <scratch> -f supabase/tests/manual_gcash_lifecycle.test.sql
-- (needs `create extension pgtap`). Everything rolls back, so the script can
-- be re-run against the same database as often as you like.
-- ══════════════════════════════════════════════════════════════════
begin;

create extension if not exists pgtap;

select no_plan();

-- ── identity helpers ─────────────────────────────────────────────
-- The repo's chain has no auth.users → profiles trigger, so fixtures are
-- inserted explicitly. Functions run as the session user but read
-- auth.uid() from the JWT claims below, exactly as PostgREST would.
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
  p_amount   numeric,
  p_file     text
) returns jsonb
language plpgsql as $$
begin
  perform pg_temp.claims(p_customer);
  return public.submit_gcash_proof(
    p_order, p_ref, 'Juan Cruz', p_amount,
    p_order::text || '/' || p_file, p_hash, now());
end $$;

select set_config('request.jwt.claims', '{"sub":null,"role":null}', true);
select set_config('request.headers', '{}', true);

-- ── fixtures (as the session user: RLS bypassed) ─────────────────
-- A profile insert writes seller_application_audit_log rows stamped with
-- auth.uid(), so a claim must exist while fixtures are created.
select set_config('request.jwt.claims',
  '{"sub":"e0000000-0000-0000-0000-0000000000fa","role":"authenticated"}', true);

insert into auth.users (instance_id, id, aud, role, email, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000','e0000000-0000-0000-0000-000000000001','authenticated','authenticated','lc-c1@test.local', now(), now()),
  ('00000000-0000-0000-0000-000000000000','e0000000-0000-0000-0000-000000000002','authenticated','authenticated','lc-c2@test.local', now(), now()),
  ('00000000-0000-0000-0000-000000000000','e0000000-0000-0000-0000-000000000003','authenticated','authenticated','lc-c3@test.local', now(), now()),
  ('00000000-0000-0000-0000-000000000000','e0000000-0000-0000-0000-000000000004','authenticated','authenticated','lc-c4@test.local', now(), now()),
  ('00000000-0000-0000-0000-000000000000','e0000000-0000-0000-0000-000000000005','authenticated','authenticated','lc-c5@test.local', now(), now()),
  ('00000000-0000-0000-0000-000000000000','e0000000-0000-0000-0000-000000000006','authenticated','authenticated','lc-c6@test.local', now(), now()),
  ('00000000-0000-0000-0000-000000000000','e0000000-0000-0000-0000-000000000011','authenticated','authenticated','lc-s1@test.local', now(), now()),
  ('00000000-0000-0000-0000-000000000000','e0000000-0000-0000-0000-000000000012','authenticated','authenticated','lc-s2@test.local', now(), now()),
  ('00000000-0000-0000-0000-000000000000','e0000000-0000-0000-0000-0000000000fa','authenticated','authenticated','lc-admin@test.local', now(), now());

insert into public.profiles (id, full_name, email, role)
values
  ('e0000000-0000-0000-0000-000000000001','LC Customer 1','lc-c1@test.local','customer'),
  ('e0000000-0000-0000-0000-000000000002','LC Customer 2','lc-c2@test.local','customer'),
  ('e0000000-0000-0000-0000-000000000003','LC Customer 3','lc-c3@test.local','customer'),
  ('e0000000-0000-0000-0000-000000000004','LC Customer 4','lc-c4@test.local','customer'),
  ('e0000000-0000-0000-0000-000000000005','LC Customer 5','lc-c5@test.local','customer'),
  ('e0000000-0000-0000-0000-000000000006','LC Customer 6','lc-c6@test.local','customer'),
  ('e0000000-0000-0000-0000-000000000011','LC Seller One','lc-s1@test.local','seller'),
  ('e0000000-0000-0000-0000-000000000012','LC Seller Two','lc-s2@test.local','seller'),
  ('e0000000-0000-0000-0000-0000000000fa','LC Admin','lc-admin@test.local','admin')
on conflict (id) do update
  set full_name = excluded.full_name, role = excluded.role;

insert into public.stores (id, owner_id, name, location)
values
  ('e0000000-0000-0000-0000-0000000000a1','e0000000-0000-0000-0000-000000000011','LC Store One','Test City'),
  ('e0000000-0000-0000-0000-0000000000a2','e0000000-0000-0000-0000-000000000012','LC Store Two','Test City');

insert into public.products (id, store_id, seller_id, name, price, is_active)
values
  ('e0000000-0000-0000-0000-0000000000b1','e0000000-0000-0000-0000-0000000000a1','e0000000-0000-0000-0000-000000000011','LC Shoe One', 1000, true),
  ('e0000000-0000-0000-0000-0000000000b2','e0000000-0000-0000-0000-0000000000a2','e0000000-0000-0000-0000-000000000012','LC Shoe Two',  900, true);

insert into public.inventory (product_id, size, stock)
values
  ('e0000000-0000-0000-0000-0000000000b1','40', 10),
  ('e0000000-0000-0000-0000-0000000000b2','40', 10);

-- Deterministic payout maths: 0 % commission, ₱100 flat delivery.
update public.platform_settings
   set platform_fee_bps = 0, delivery_fee_amount = 100
 where id = 1;

-- Results of RPC calls are parked here and read through scalar subqueries.
create temp table r (k text primary key, j jsonb);
create temp table snap (k text primary key, ts timestamptz);

-- The RLS section reads these as `authenticated`, which owns nothing here.
grant select on r, snap to authenticated;

-- ══ 1. Admin opens the platform account ══════════════════════════
-- Through RLS, as the admin — the same path the portal uses.
select pg_temp.claims('e0000000-0000-0000-0000-0000000000fa');
set local role authenticated;
insert into public.platform_payment_accounts
  (label, gcash_number, account_name, qr_url, is_active)
values
  ('Platform GCash', '09171234567', 'CUFMAI Store',
   'https://example.test/platform-qr.png', true);
reset role;

select is(
  (select count(*)::int from public.platform_payment_accounts where is_active),
  1,
  '1: the admin activated exactly one platform account'
);

-- A second active account must be impossible, not merely discouraged.
select pg_temp.claims('e0000000-0000-0000-0000-0000000000fa');
set local role authenticated;
select throws_ok(
  $$ insert into public.platform_payment_accounts
       (label, gcash_number, account_name, is_active)
     values ('Second account', '09170000000', 'Somebody Else', true) $$,
  '23505',
  null,
  '2: a second ACTIVE platform account is refused by the unique index'
);
reset role;

-- Only admins may write the receiving account at all.
select pg_temp.claims('e0000000-0000-0000-0000-000000000011');
set local role authenticated;
select throws_ok(
  $$ insert into public.platform_payment_accounts
       (label, gcash_number, account_name, is_active)
     values ('Sneaky', '09171234568', 'Sneaky Seller', false) $$,
  '42501',
  null,
  '3: a seller cannot add a platform account'
);
reset role;

-- ══ 2. Checkout: one store, platform account, stock reserved ═════
insert into r values ('o1', pg_temp.checkout(
  'e0000000-0000-0000-0000-000000000001',
  '[{"product_id":"e0000000-0000-0000-0000-0000000000b1","size":"40","quantity":1}]'::jsonb));

select is(
  (select (j ->> 'total_amount')::numeric from r where k = 'o1'),
  1100.00,
  '4: checkout charges price + the configured ₱100 delivery'
);
select is(
  (select j ->> 'gcash_number' from r where k = 'o1'),
  '09171234567',
  '5: the customer is shown the PLATFORM number, not a seller number'
);
select is(
  (select j ->> 'gcash_qr_url' from r where k = 'o1'),
  'https://example.test/platform-qr.png',
  '6: the platform QR comes back with the checkout'
);
select ok(
  (select (j ->> 'order_code') ~ '^[0-9A-F]{8}$' from r where k = 'o1'),
  '7: checkout returns the 8-character order code for the GCash note'
);
select is(
  (select stock from public.inventory
    where product_id = 'e0000000-0000-0000-0000-0000000000b1' and size = '40'),
  9,
  '8: the unit is held for the 30-minute payment window'
);

-- ── cross-store cart: refused before anything is charged or reserved ──
select throws_ok(
  format($$ select pg_temp.checkout(%L::uuid, %L::jsonb) $$,
    'e0000000-0000-0000-0000-000000000002',
    '[{"product_id":"e0000000-0000-0000-0000-0000000000b1","size":"40","quantity":1},
      {"product_id":"e0000000-0000-0000-0000-0000000000b2","size":"40","quantity":1}]'),
  'P0001',
  'Your cart has items from more than one store. Please check out one store at a time.',
  '9: a cart spanning two stores is refused (the payout-attribution bug)'
);
select is(
  (select stock from public.inventory
    where product_id = 'e0000000-0000-0000-0000-0000000000b1' and size = '40'),
  9,
  '10: the refused cart reserved nothing'
);

-- ══ 3. Proof submit → payment_under_review ═══════════════════════
insert into r values ('p1', pg_temp.submit(
  'e0000000-0000-0000-0000-000000000001',
  (select (j ->> 'order_id')::uuid from r where k = 'o1'),
  '111111111111', repeat('1', 64), 1100.00, 'shot1.jpg'));

select is(
  (select j ->> 'status' from r where k = 'p1'),
  'payment_under_review',
  '11: a submitted proof puts the order under review'
);
select is(
  (select status from public.orders
    where id = (select (j ->> 'order_id')::uuid from r where k = 'o1')),
  'payment_under_review',
  '12: the order row agrees'
);
select ok(
  (select review_deadline > now() + interval '23 hours'
     from public.orders
    where id = (select (j ->> 'order_id')::uuid from r where k = 'o1')),
  '13: a 24-hour review SLA replaces the pay-window clock'
);

-- ══ 4. Duplicate ref / duplicate screenshot / wrong amount ═══════
-- o2 gets a good proof; o3 then tries to reuse its reference, its
-- screenshot hash, and finally sends the wrong amount.
insert into r values ('o2', pg_temp.checkout(
  'e0000000-0000-0000-0000-000000000002',
  '[{"product_id":"e0000000-0000-0000-0000-0000000000b1","size":"40","quantity":1}]'::jsonb));
insert into r values ('p2', pg_temp.submit(
  'e0000000-0000-0000-0000-000000000002',
  (select (j ->> 'order_id')::uuid from r where k = 'o2'),
  '222222222222', repeat('2', 64), 1100.00, 'shot2.jpg'));

insert into r values ('o3', pg_temp.checkout(
  'e0000000-0000-0000-0000-000000000003',
  '[{"product_id":"e0000000-0000-0000-0000-0000000000b1","size":"40","quantity":1}]'::jsonb));

select throws_ok(
  format($$ select pg_temp.submit(%L::uuid, %L::uuid, '333333333333', repeat('3',64), 1000.00, 'x.jpg') $$,
    'e0000000-0000-0000-0000-000000000003',
    (select (j ->> 'order_id')::uuid from r where k = 'o3')),
  'P0001',
  null,
  '14: an amount that is not the order total is refused'
);
select throws_ok(
  format($$ select pg_temp.submit(%L::uuid, %L::uuid, '222222222222', repeat('3',64), 1100.00, 'x.jpg') $$,
    'e0000000-0000-0000-0000-000000000003',
    (select (j ->> 'order_id')::uuid from r where k = 'o3')),
  'P0001',
  'That GCash reference number has already been used for another order',
  '15: a reference already used on another order is refused'
);
select throws_ok(
  format($$ select pg_temp.submit(%L::uuid, %L::uuid, '333333333333', repeat('2',64), 1100.00, 'x.jpg') $$,
    'e0000000-0000-0000-0000-000000000003',
    (select (j ->> 'order_id')::uuid from r where k = 'o3')),
  'P0001',
  'That screenshot has already been used for another order. Attach this payment''s own receipt.',
  '16: a screenshot already used on another order is refused'
);
select is(
  (select count(*)::int from public.gcash_payment_proofs
    where order_id = (select (j ->> 'order_id')::uuid from r where k = 'o3')),
  0,
  '17: none of the three refused attempts was recorded'
);

-- ══ 5. Three rejections: alive, alive, then cancelled ════════════
select pg_temp.claims('e0000000-0000-0000-0000-000000000011');
insert into r values ('r1', public.reject_gcash_proof(
  (select (j ->> 'order_id')::uuid from r where k = 'o1'),
  'Reference not found in the platform statement'));
select is(
  (select j ->> 'status' from r where k = 'r1'),
  'awaiting_payment_confirmation',
  '18: rejection 1 returns the order to the customer instead of cancelling'
);
select is(
  (select j ->> 'attempts_left' from r where k = 'r1'),
  '2',
  '19: the customer is told two attempts remain'
);
select is(
  (select stock from public.inventory
    where product_id = 'e0000000-0000-0000-0000-0000000000b1' and size = '40'),
  7,
  '20: a rejected (but live) order keeps its hold — o1, o2 and o3 all hold one'
);

insert into r values ('p1b', pg_temp.submit(
  'e0000000-0000-0000-0000-000000000001',
  (select (j ->> 'order_id')::uuid from r where k = 'o1'),
  '111111111113', repeat('b', 64), 1100.00, 'shot1b.jpg'));
select is(
  (select (j ->> 'attempt_no')::int from r where k = 'p1b'),
  2,
  '21: the resubmission is recorded as attempt 2'
);

select pg_temp.claims('e0000000-0000-0000-0000-000000000011');
insert into r values ('r2', public.reject_gcash_proof(
  (select (j ->> 'order_id')::uuid from r where k = 'o1'),
  'Payer name does not match the GCash record'));
select is(
  (select j ->> 'attempts_left' from r where k = 'r2'),
  '1',
  '22: rejection 2 still leaves one attempt'
);

insert into r values ('p1c', pg_temp.submit(
  'e0000000-0000-0000-0000-000000000001',
  (select (j ->> 'order_id')::uuid from r where k = 'o1'),
  '111111111114', repeat('c', 64), 1100.00, 'shot1c.jpg'));
select is(
  (select (j ->> 'attempt_no')::int from r where k = 'p1c'),
  3,
  '23: the third and final attempt is accepted'
);

select pg_temp.claims('e0000000-0000-0000-0000-000000000011');
insert into r values ('r3', public.reject_gcash_proof(
  (select (j ->> 'order_id')::uuid from r where k = 'o1'),
  'Third attempt still does not match'));
select is(
  (select j ->> 'status' from r where k = 'r3'),
  'cancelled',
  '24: rejection 3 cancels the order'
);
select is(
  (select j ->> 'cancelled' from r where k = 'r3'),
  'true',
  '25: the cancellation really happened (not a silent no-op)'
);
select is(
  (select status from public.orders
    where id = (select (j ->> 'order_id')::uuid from r where k = 'o1')),
  'cancelled',
  '26: the order row is cancelled'
);
select is(
  (select stock from public.inventory
    where product_id = 'e0000000-0000-0000-0000-0000000000b1' and size = '40'),
  8,
  '27: the third rejection released exactly one unit (o2 and o3 still hold one)'
);

-- o3's duplicates are settled: the customer cancels it, so the expiry sweep
-- below has exactly one candidate to expire.
select pg_temp.claims('e0000000-0000-0000-0000-000000000003');
select ok(
  public.cancel_my_pending_gcash_checkout(
    (select (j ->> 'order_id')::uuid from r where k = 'o3')),
  '28: the customer can cancel an unpaid checkout'
);

-- ══ 6. Seller verification → pending + paid ══════════════════════
select pg_temp.claims('e0000000-0000-0000-0000-000000000011');
select is(
  (public.verify_gcash_payment(
     (select (j ->> 'order_id')::uuid from r where k = 'o2')) ->> 'status'),
  'pending',
  '29: the store owner verifies the payment'
);
select is(
  (select payment_status from public.orders
    where id = (select (j ->> 'order_id')::uuid from r where k = 'o2')),
  'paid',
  '30: verification marks the order paid'
);
select ok(
  (select seller_verified_at is not null and review_deadline is null
     from public.orders
    where id = (select (j ->> 'order_id')::uuid from r where k = 'o2')),
  '31: the seller decision is stamped and the SLA cleared'
);

-- Another store's seller cannot verify it.
select pg_temp.claims('e0000000-0000-0000-0000-000000000012');
select throws_ok(
  format($$ select public.verify_gcash_payment(%L::uuid) $$,
    (select (j ->> 'order_id')::uuid from r where k = 'o2')),
  'P0001',
  'Only the store owner can verify this payment',
  '32: a different store''s seller cannot verify someone else''s payment'
);

-- ══ 7. Admin verification on the store's behalf ══════════════════
insert into r values ('o4', pg_temp.checkout(
  'e0000000-0000-0000-0000-000000000004',
  '[{"product_id":"e0000000-0000-0000-0000-0000000000b1","size":"40","quantity":1}]'::jsonb));
insert into r values ('p4', pg_temp.submit(
  'e0000000-0000-0000-0000-000000000004',
  (select (j ->> 'order_id')::uuid from r where k = 'o4'),
  '444444444444', repeat('4', 64), 1100.00, 'shot4.jpg'));

select pg_temp.claims('e0000000-0000-0000-0000-000000000011');
select throws_ok(
  format($$ select public.admin_verify_payment(%L::uuid) $$,
    (select (j ->> 'order_id')::uuid from r where k = 'o4')),
  'P0001',
  'Only admins can verify a payment on the store''s behalf',
  '33: a seller cannot use the admin verification override'
);

select pg_temp.claims('e0000000-0000-0000-0000-0000000000fa');
select is(
  (public.admin_verify_payment(
     (select (j ->> 'order_id')::uuid from r where k = 'o4')) ->> 'status'),
  'pending',
  '34: an admin can verify on the store''s behalf'
);
select is(
  (select payment_status from public.orders
    where id = (select (j ->> 'order_id')::uuid from r where k = 'o4')),
  'paid',
  '35: the admin override also marks it paid'
);

-- ══ 8. Reconciliation ════════════════════════════════════════════
select pg_temp.claims('e0000000-0000-0000-0000-000000000011');
select throws_ok(
  format($$ select public.admin_reconcile_order(%L::uuid) $$,
    (select (j ->> 'order_id')::uuid from r where k = 'o2')),
  'P0001',
  'Only admins can reconcile payments',
  '36: a seller cannot confirm that the money landed'
);

select pg_temp.claims('e0000000-0000-0000-0000-0000000000fa');
select is(
  (public.admin_reconcile_order(
     (select (j ->> 'order_id')::uuid from r where k = 'o2')) ->> 'funds_reconciled'),
  'true',
  '37: an admin reconciles the order against the platform statement'
);
select is(
  (public.admin_reconcile_order(
     (select (j ->> 'order_id')::uuid from r where k = 'o4')) ->> 'funds_reconciled'),
  'true',
  '38: the second paid order is reconciled too'
);
select is(
  (select count(*)::int from public.orders
    where id in ((select (j ->> 'order_id')::uuid from r where k = 'o2'),
                 (select (j ->> 'order_id')::uuid from r where k = 'o4'))
      and funds_reconciled_at is not null),
  2,
  '39: both orders carry the reconciliation stamp'
);

-- ══ 9. Expiry: unpaid dies, under-review does not ════════════════
insert into r values ('o5', pg_temp.checkout(
  'e0000000-0000-0000-0000-000000000005',
  '[{"product_id":"e0000000-0000-0000-0000-0000000000b1","size":"40","quantity":1}]'::jsonb));
insert into r values ('o6', pg_temp.checkout(
  'e0000000-0000-0000-0000-000000000006',
  '[{"product_id":"e0000000-0000-0000-0000-0000000000b1","size":"40","quantity":1}]'::jsonb));
insert into r values ('p6', pg_temp.submit(
  'e0000000-0000-0000-0000-000000000006',
  (select (j ->> 'order_id')::uuid from r where k = 'o6'),
  '666666666666', repeat('6', 64), 1100.00, 'shot6.jpg'));

-- Age both orders: o5 still unpaid, o6 already paid-looking with both
-- clocks in the past.
update public.orders
   set payment_confirmation_deadline = now() - interval '1 minute'
 where id in ((select (j ->> 'order_id')::uuid from r where k = 'o5'),
              (select (j ->> 'order_id')::uuid from r where k = 'o6'));
update public.orders
   set review_deadline = now() - interval '1 minute'
 where id = (select (j ->> 'order_id')::uuid from r where k = 'o6');

select pg_temp.claims('e0000000-0000-0000-0000-000000000005');
select is(
  (public.expire_unpaid_gcash_orders() ->> 'expired')::int,
  1,
  '40: the sweep expires exactly one order'
);
select is(
  (select status from public.orders
    where id = (select (j ->> 'order_id')::uuid from r where k = 'o5')),
  'cancelled',
  '41: the unpaid order whose window elapsed is cancelled'
);
select is(
  (select status from public.orders
    where id = (select (j ->> 'order_id')::uuid from r where k = 'o6')),
  'payment_under_review',
  '42: an order already under review is NEVER expired by the timer'
);

-- ══ 10. Payouts ══════════════════════════════════════════════════
select pg_temp.claims('e0000000-0000-0000-0000-000000000011');
select throws_ok(
  $$ select public.generate_daily_payouts(null::date) $$,
  'P0001',
  'Only admins can generate payouts',
  '43: a seller cannot generate payouts'
);
select throws_ok(
  format($$ select public.mark_payout_paid(%L::uuid, 'REF-0001', null) $$,
    '00000000-0000-0000-0000-0000000000ff'::uuid),
  'P0001',
  'Only admins can mark a payout paid',
  '44: a seller cannot mark a payout paid'
);

select pg_temp.claims('e0000000-0000-0000-0000-0000000000fa');
insert into r values ('gen', public.generate_daily_payouts(
  (now() at time zone 'Asia/Manila')::date));

select is(
  (select (j ->> 'orders_added')::int from r where k = 'gen'),
  2,
  '45: both reconciled orders are batched'
);
select is(
  (select count(*)::int from public.seller_payouts
    where store_id = 'e0000000-0000-0000-0000-0000000000a1'
      and period_date = (now() at time zone 'Asia/Manila')::date),
  1,
  '46: one draft payout per store for the Manila date'
);
select is(
  (select net_amount from public.seller_payouts
    where store_id = 'e0000000-0000-0000-0000-0000000000a1'
      and period_date = (now() at time zone 'Asia/Manila')::date),
  2000.00,
  '47: net = 2 × (1100 − 100 delivery) − 0 % commission'
);
select is(
  (select gross_amount from public.seller_payouts
    where store_id = 'e0000000-0000-0000-0000-0000000000a1'
      and period_date = (now() at time zone 'Asia/Manila')::date),
  2200.00,
  '48: gross is the two order totals'
);
select is(
  (select delivery_fees from public.seller_payouts
    where store_id = 'e0000000-0000-0000-0000-0000000000a1'
      and period_date = (now() at time zone 'Asia/Manila')::date),
  200.00,
  '49: the ₱100 delivery is passed through, not paid out'
);
select is(
  (select count(*)::int from public.seller_payout_items i
     join public.seller_payouts p on p.id = i.payout_id
    where p.store_id = 'e0000000-0000-0000-0000-0000000000a1'
      and p.period_date = (now() at time zone 'Asia/Manila')::date),
  2,
  '50: one line per reconciled order'
);
select is(
  (public.generate_daily_payouts((now() at time zone 'Asia/Manila')::date)
     ->> 'orders_added')::int,
  0,
  '51: re-running the generator adds nothing'
);

-- ── mark paid, then replay the same transfer ──
insert into r values ('paid', public.mark_payout_paid(
  (select id from public.seller_payouts
    where store_id = 'e0000000-0000-0000-0000-0000000000a1'
      and period_date = (now() at time zone 'Asia/Manila')::date),
  'GCASH-TRANSFER-0001', 'payouts/r1.pdf'));

select is(
  (select j ->> 'status' from r where k = 'paid'),
  'paid',
  '52: the admin closes the payout with a transfer reference'
);

-- The timestamp the first (real) mark wrote — the replay must not move it.
insert into snap
select 'paid_at', paid_at from public.seller_payouts
 where store_id = 'e0000000-0000-0000-0000-0000000000a1'
   and period_date = (now() at time zone 'Asia/Manila')::date;
select is(
  (select status || '|' || paid_reference || '|' || receipt_path
     from public.seller_payouts
    where store_id = 'e0000000-0000-0000-0000-0000000000a1'
      and period_date = (now() at time zone 'Asia/Manila')::date),
  'paid|GCASH-TRANSFER-0001|payouts/r1.pdf',
  '53: status, reference and receipt are stored'
);

insert into r values ('paid2', public.mark_payout_paid(
  (select id from public.seller_payouts
    where store_id = 'e0000000-0000-0000-0000-0000000000a1'
      and period_date = (now() at time zone 'Asia/Manila')::date),
  'GCASH-TRANSFER-0001', 'payouts/r1.pdf'));

select is(
  (select j ->> 'idempotent' from r where k = 'paid2'),
  'true',
  '54: replaying the same transfer is an idempotent success'
);
select is(
  (select paid_at from public.seller_payouts
    where store_id = 'e0000000-0000-0000-0000-0000000000a1'
      and period_date = (now() at time zone 'Asia/Manila')::date),
  (select ts from snap where k = 'paid_at'),
  '55: the replay did not rewrite the payment timestamp'
);

select throws_ok(
  format($$ select public.mark_payout_paid(%L::uuid, 'A-DIFFERENT-REF', null) $$,
    (select id from public.seller_payouts
      where store_id = 'e0000000-0000-0000-0000-0000000000a1'
        and period_date = (now() at time zone 'Asia/Manila')::date)),
  'P0001',
  null,
  '56: a DIFFERENT reference on a paid payout is refused, not silently applied'
);

-- ══ 11. Row-level security ═══════════════════════════════════════
-- Positive control first: the owning seller sees their own money rows.
select pg_temp.claims('e0000000-0000-0000-0000-000000000011');
set local role authenticated;
select is(
  (select count(*)::int from public.gcash_payment_proofs
    where order_id = (select (j ->> 'order_id')::uuid from r where k = 'o2')),
  1,
  '57: the owning seller can read their order''s proof'
);
select is(
  (select count(*)::int from public.seller_payouts
    where store_id = 'e0000000-0000-0000-0000-0000000000a1'),
  1,
  '58: the owning seller can read their payout'
);
reset role;

-- Then the denial: another store's seller sees none of it.
select pg_temp.claims('e0000000-0000-0000-0000-000000000012');
set local role authenticated;
select is(
  (select count(*)::int from public.gcash_payment_proofs
    where order_id = (select (j ->> 'order_id')::uuid from r where k = 'o2')),
  0,
  '59: a different seller cannot read another store''s proof'
);
select is(
  (select count(*)::int from public.seller_payouts
    where store_id = 'e0000000-0000-0000-0000-0000000000a1'),
  0,
  '60: a different seller cannot read another store''s payout'
);
select is(
  (select count(*)::int from public.seller_payout_items i
     join public.seller_payouts p on p.id = i.payout_id
    where p.store_id = 'e0000000-0000-0000-0000-0000000000a1'),
  0,
  '61: nor its payout lines'
);
select is(
  (select count(*)::int from public.orders
    where id = (select (j ->> 'order_id')::uuid from r where k = 'o2')),
  0,
  '62: nor the other store''s order row'
);
select is(
  (select count(*)::int from public.gcash_payment_decision_audit
    where order_id = (select (j ->> 'order_id')::uuid from r where k = 'o2')),
  0,
  '63: nor the seller decision audit'
);

-- A non-admin cannot rewrite the money configuration.
update public.platform_settings set platform_fee_bps = 4999 where id = 1;
reset role;
select is(
  (select platform_fee_bps from public.platform_settings where id = 1),
  0,
  '64: a seller cannot change the platform commission'
);

-- A non-admin cannot use the flag path either.
select pg_temp.claims('e0000000-0000-0000-0000-000000000011');
set local role authenticated;
select throws_ok(
  format($$ select public.admin_flag_payment(%L::uuid, 'suspicious') $$,
    (select (j ->> 'order_id')::uuid from r where k = 'o2')),
  'P0001',
  'Only admins can flag a payment',
  '65: a seller cannot flag a payment either'
);
reset role;

-- ══ 12. Stock ends where the money says it should ════════════════
-- 10 to start; o1 released, o2 + o4 paid, o6 under review, o3/o5 cancelled:
-- 3 units are still held.
select is(
  (select stock from public.inventory
    where product_id = 'e0000000-0000-0000-0000-0000000000b1' and size = '40'),
  7,
  '66: held stock equals the live orders, no leak and no inflation'
);

select * from finish();
rollback;
