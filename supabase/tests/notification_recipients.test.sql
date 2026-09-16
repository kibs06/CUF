-- ══════════════════════════════════════════════════════════════════
-- Notification recipients — pgTAP
-- Run by CI via `supabase test db` (workflow: supabase-migrations.yml)
--
-- The rule this file enforces: **`notifications.user_id` is NOT NULL with an
-- FK to `profiles`, so a recipient must be checked before it is used — a NULL
-- recipient is not a skipped notification, it is an aborted statement.** Where
-- that statement sits inside a LOOP, one such row takes the whole batch down
-- with it.
--
-- Every case below has two halves, deliberately:
--   • the TOLERANT half — a NULL recipient must not raise (the abort);
--   • the POSITIVE half — a real recipient must still be notified (so a guard
--     that simply switched the notification off would fail).
-- Only the pair together is evidence. See
-- docs/AI/NOTIFICATION_RECIPIENT_AUDIT.md.
-- ══════════════════════════════════════════════════════════════════

begin;
select plan(27);

-- ── helpers ────────────────────────────────────────────────────────
create or replace function public.tmp_rcpt_claims(p_user uuid)
returns text language sql immutable as $$
  select case when p_user is null
              then '{"sub":null,"role":null}'
              else json_build_object('sub', p_user, 'role', 'authenticated')::text
         end;
$$;

-- Notifications written for one order (any recipient).
create or replace function public.tmp_rcpt_order_notices(p_order uuid)
returns integer language sql stable as $$
  select count(*)::int from public.notifications where order_id = p_order;
$$;

-- ⚠️ A NULL recipient must leave the notifying code with nothing attempted. If
-- a guard were "fixed" by sending to some placeholder, this count would move.
create or replace function public.tmp_rcpt_total()
returns integer language sql stable as $$
  select count(*)::int from public.notifications;
$$;

select set_config('request.jwt.claims', '{"sub":null,"role":null}', true);

-- ── fixtures (as postgres; RLS bypassed) ───────────────────────────
insert into auth.users (instance_id, id, aud, role, email, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000','a0000000-0000-0000-0000-000000000001','authenticated','authenticated','rcpt-seller@test.local', now(), now()),
  ('00000000-0000-0000-0000-000000000000','a0000000-0000-0000-0000-000000000002','authenticated','authenticated','rcpt-cust@test.local',   now(), now()),
  ('00000000-0000-0000-0000-000000000000','a0000000-0000-0000-0000-000000000004','authenticated','authenticated','rcpt-admin@test.local',  now(), now());

insert into public.profiles (id, full_name, email, role, seller_status)
values
  ('a0000000-0000-0000-0000-000000000001','R Seller','rcpt-seller@test.local','seller','approved'),
  ('a0000000-0000-0000-0000-000000000002','R Customer','rcpt-cust@test.local','customer','none'),
  ('a0000000-0000-0000-0000-000000000004','R Admin','rcpt-admin@test.local','admin','none');

-- Store A has an owner; store B deliberately has NONE (`stores.owner_id` is
-- NULLABLE, which is the whole point of these cases).
insert into public.stores (id, owner_id, name, location)
values ('a0000000-0000-0000-0000-000000000005','a0000000-0000-0000-0000-000000000001','R Store A','R City'),
       ('a0000000-0000-0000-0000-000000000006', NULL,                                    'R Store B (no owner)','R City');

insert into public.products (id, store_id, seller_id, name, price, category)
values ('a0000000-0000-0000-0000-000000000007','a0000000-0000-0000-0000-000000000005',
        'a0000000-0000-0000-0000-000000000001','R Shoe A', 1000, 'General'),
       ('a0000000-0000-0000-0000-000000000008','a0000000-0000-0000-0000-000000000006',
        NULL,'R Shoe B', 1000, 'General');

insert into public.inventory (product_id, size, stock)
values ('a0000000-0000-0000-0000-000000000007','40', 5),
       ('a0000000-0000-0000-0000-000000000007','41', 5),
       ('a0000000-0000-0000-0000-000000000008','40', 5);

-- ══ 1. THE BATCH — one bad row must not abort the sweep ════════════
-- Two overdue orders; the second has NO customer (`orders.customer_id` is
-- NULLABLE). `expire_overdue_gcash_orders()` loops and calls
-- `cancel_awaiting_gcash_order(..., p_notify_customer => true)` per order.
--
-- Measured WITHOUT the guard: 23502 mid-loop, and because the loop lives inside
-- ONE statement the rollback takes the healthy orders' cancellations with it —
-- BOTH orders stayed `awaiting_payment_confirmation` and 0 notifications were
-- written. The batch is never resolved, on every run, while that row exists.
insert into public.orders
  (id, customer_id, store_id, status, total_amount, payment_method,
   payment_status, fulfillment, source, payment_confirmation_deadline)
values
  ('b0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000002',
   'a0000000-0000-0000-0000-000000000005','awaiting_payment_confirmation',
   500, 'gcash', 'pending', 'pickup', 'online', now() - interval '10 minutes'),
  ('b0000000-0000-0000-0000-000000000002', NULL,
   'a0000000-0000-0000-0000-000000000005','awaiting_payment_confirmation',
   600, 'gcash', 'pending', 'pickup', 'online', now() - interval '10 minutes');

select lives_ok(
  $$select public.expire_overdue_gcash_orders()$$,
  '1: the GCash expiry sweep survives a customer-less order in its batch'
);

select is(
  (select public.expire_overdue_gcash_orders() ->> 'expired'),
  '0',
  '2: …and a second run finds nothing left (the sweep completed, idempotent)'
);

select is(
  (select status::text from public.orders where id = 'b0000000-0000-0000-0000-000000000002'),
  'cancelled',
  '3: the customer-less order is itself cancelled — it is the row that would abort the batch, so an unguarded sweep can never resolve it'
);

select is(
  (select status::text from public.orders where id = 'b0000000-0000-0000-0000-000000000001'),
  'cancelled',
  '4: …and the healthy order in the same batch is cancelled too'
);

select is(
  (select count(*)::int from public.notifications
    where order_id = 'b0000000-0000-0000-0000-000000000001'
      and title = 'Payment window expired'),
  1,
  '5: the customer who exists is still told their window expired'
);

select is(
  public.tmp_rcpt_order_notices('b0000000-0000-0000-0000-000000000002'),
  0,
  '6: …and the order with no customer produced no notification and raised nothing'
);

-- ══ 2. The seller confirming a payment ════════════════════════════
-- Runs in ONE transaction with the state change, so an unguarded NULL recipient
-- rolls the confirmation back: the seller cannot confirm a payment that was
-- really made.
insert into public.orders
  (id, customer_id, store_id, status, total_amount, payment_method,
   payment_status, fulfillment, source, payment_confirmation_deadline)
values
  ('b0000000-0000-0000-0000-000000000003', NULL,
   'a0000000-0000-0000-0000-000000000005','awaiting_payment_confirmation',
   700, 'gcash', 'pending', 'pickup', 'online', now() + interval '30 minutes');

insert into public.gcash_payment_proofs
  (order_id, reference_number, screenshot_url, submitted_by)
values
  ('b0000000-0000-0000-0000-000000000003','993100000001','https://example.test/p.png',
   'a0000000-0000-0000-0000-000000000002');

select set_config('request.jwt.claims',
  public.tmp_rcpt_claims('a0000000-0000-0000-0000-000000000001'), true);

select lives_ok(
  $$select public.confirm_gcash_payment('b0000000-0000-0000-0000-000000000003')$$,
  '7: a customer-less order can still have its payment confirmed'
);
select is(
  (select payment_status from public.orders where id = 'b0000000-0000-0000-0000-000000000003'),
  'paid',
  '8: …the confirmation took effect (not rolled back by the notification)'
);
select is(
  (select status::text from public.orders where id = 'b0000000-0000-0000-0000-000000000003'),
  'pending',
  '9: …and the order entered the seller pipeline'
);
select is(
  public.tmp_rcpt_order_notices('b0000000-0000-0000-0000-000000000003'),
  0,
  '10: …with nothing attempted for a customer that does not exist'
);

-- ══ 3. The two order triggers ═════════════════════════════════════
-- Both fire AFTER INSERT/UPDATE, so an unguarded recipient rejects the order
-- write itself rather than merely skipping the notification.
select set_config('request.jwt.claims', '{"sub":null,"role":null}', true);

select lives_ok(
  $$insert into public.orders
      (id, customer_id, store_id, status, total_amount, payment_method,
       payment_status, fulfillment, source)
    values
      ('b0000000-0000-0000-0000-000000000004', NULL,
       'a0000000-0000-0000-0000-000000000005','pending',
       800, 'cash', 'unpaid', 'pickup', 'online')$$,
  '11: an order with no customer can still be CREATED (the insert trigger tolerates it)'
);
select lives_ok(
  $$update public.orders set status = 'preparing'
     where id = 'b0000000-0000-0000-0000-000000000004'$$,
  '12: …and its status can still be CHANGED (the update trigger tolerates it)'
);
select is(
  public.tmp_rcpt_order_notices('b0000000-0000-0000-0000-000000000004'),
  0,
  '13: …and neither trigger attempted a notification'
);

-- ══ 4. The positive controls ══════════════════════════════════════
-- A guard that simply disabled these notifications would satisfy 1–13. These
-- prove the feature still works for a customer who exists.
select lives_ok(
  $$insert into public.orders
      (id, customer_id, store_id, status, total_amount, payment_method,
       payment_status, fulfillment, source)
    values
      ('b0000000-0000-0000-0000-000000000005','a0000000-0000-0000-0000-000000000002',
       'a0000000-0000-0000-0000-000000000005','pending',
       900, 'cash', 'unpaid', 'pickup', 'online')$$,
  '14: an order WITH a customer is created'
);
select is(
  (select count(*)::int from public.notifications
    where order_id = 'b0000000-0000-0000-0000-000000000005'
      and title = 'Payment pending'),
  1,
  '15: …and the insert trigger still notifies that customer'
);
select lives_ok(
  $$update public.orders set status = 'placed'
     where id = 'b0000000-0000-0000-0000-000000000005'$$,
  '16: its status changes'
);
select is(
  (select count(*)::int from public.notifications
    where order_id = 'b0000000-0000-0000-0000-000000000005'),
  2,
  '17: …and the status trigger adds its notification (2 total, same order)'
);

-- ══ 5. A bulk request to a store with NO owner ═════════════════════
-- The seller notification is a row-select on `stores.owner_id`; without the
-- guard the insert raises and takes the customer's reservation row with it
-- (one transaction), so the request cannot be made at all.
select set_config('request.jwt.claims',
  public.tmp_rcpt_claims('a0000000-0000-0000-0000-000000000002'), true);

select lives_ok(
  $$select public.request_bulk_reservation(
      'a0000000-0000-0000-0000-000000000008'::uuid,
      'a0000000-0000-0000-0000-000000000006'::uuid, 3)$$,
  '18: a bulk reservation can be requested from a store with no owner'
);
select is(
  (select count(*)::int from public.bulk_reservations
    where store_id = 'a0000000-0000-0000-0000-000000000006'
      and customer_id = 'a0000000-0000-0000-0000-000000000002'),
  1,
  '19: …and the reservation itself was written (nothing rolled back)'
);
select lives_ok(
  $$select public.request_bulk_reservation(
      'a0000000-0000-0000-0000-000000000007'::uuid,
      'a0000000-0000-0000-0000-000000000005'::uuid, 3)$$,
  '20: a bulk reservation to a store WITH an owner is still accepted'
);
select is(
  (select count(*)::int from public.notifications
    where user_id = 'a0000000-0000-0000-0000-000000000001'
      and title = 'New bulk reservation request'),
  1,
  '21: …and that owner is still notified'
);

-- ══ 6. Cancelling a pickup hold at a store with no owner ═══════════
-- Here the recipient is chosen by a CASE, and the ELSE branch is the store
-- owner — NULL for an ownerless store. Unguarded, the customer could not
-- cancel their own hold.
select lives_ok(
  $$select public.request_pickup_reservation(
      'a0000000-0000-0000-0000-000000000008'::uuid, '40', 1)$$,
  '22: a pickup hold is placed at the ownerless store'
);

select set_config('request.jwt.claims',
  public.tmp_rcpt_claims('a0000000-0000-0000-0000-000000000002'), true);
select lives_ok(
  $$select public.cancel_pickup_reservation(
      (select id from public.pickup_reservations
        where customer_id = 'a0000000-0000-0000-0000-000000000002'
          and product_id = 'a0000000-0000-0000-0000-000000000008' and status = 'active'))$$,
  '23: …and the customer can still cancel it with nobody to notify'
);
select is(
  (select status::text from public.pickup_reservations
    where customer_id = 'a0000000-0000-0000-0000-000000000002'
      and product_id = 'a0000000-0000-0000-0000-000000000008'),
  'cancelled',
  '24: …the hold is really released'
);

-- …and the positive control for that same CASE: with an owner present, the
-- store's release DOES reach the customer.
select lives_ok(
  $$select public.request_pickup_reservation(
      'a0000000-0000-0000-0000-000000000007'::uuid, '41', 1)$$,
  '25: a pickup hold is placed at the store with an owner'
);
select set_config('request.jwt.claims',
  public.tmp_rcpt_claims('a0000000-0000-0000-0000-000000000001'), true);
select lives_ok(
  $$select public.cancel_pickup_reservation(
      (select id from public.pickup_reservations
        where customer_id = 'a0000000-0000-0000-0000-000000000002'
          and product_id = 'a0000000-0000-0000-0000-000000000007' and status = 'active'))$$,
  '26: the store owner can release it'
);
select is(
  (select count(*)::int from public.notifications
    where user_id = 'a0000000-0000-0000-0000-000000000002'
      and title = 'Pickup reservation cancelled'),
  1,
  '27: …and the customer is told (the CASE still notifies when a recipient exists)'
);

select * from finish();
rollback;
