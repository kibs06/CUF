-- ══════════════════════════════════════════════════════════════════
-- Pickup reservations (ANQUI item 14) — pgTAP
-- Run by CI via `supabase test db` (supabase-migrations.yml)
--
-- Covers `20260915170000_add_pickup_reservations.sql`. The assertions that
-- matter most are marked ⚠️ — they are inventory-correctness, not
-- convenience:
--
--   ⚠️ the hold moves exactly the requested units, and release puts back
--      exactly the same number (never more — a double release is a silent
--      inventory inflation bug, and it is the same class of bug the
--      voucher and bulk-reservation work each hit).
--   ⚠️ the sweep running AFTER a manual cancel must not release twice.
--   ⚠️ fulfill must NOT move stock again: the units left `inventory.stock`
--      when the hold was created, so a second draw would double-count.
--      (Verified while writing: `order_items` has no triggers at all in
--      this schema, so nothing else decrements on insert. If that ever
--      changes, this assertion is what catches it.)
--   ⚠️ a customer cannot bypass the cap or the stock check with a direct
--      INSERT: the table has no INSERT policy, so the RPC is the only way
--      in.
-- ══════════════════════════════════════════════════════════════════

begin;
select plan(129);

-- ── helpers ────────────────────────────────────────────────────────
create or replace function public.tmp_pickup_claims(p_user uuid)
returns text language sql immutable as $$
  select json_build_object('sub', p_user, 'role', 'authenticated')::text;
$$;

create or replace function public.tmp_pickup_stock(p_size text)
returns integer language sql stable as $$
  select stock from public.inventory
   where product_id = 'e0000000-0000-0000-0000-000000000004'
     and size = p_size;
$$;

create or replace function public.tmp_pickup_notices(p_user uuid, p_title text)
returns integer language sql stable as $$
  select count(*)::int from public.notifications
   where user_id = p_user and title = p_title;
$$;

select set_config('request.jwt.claims', '{"sub":null,"role":null}', true);
select set_config('request.headers', '{}', true);

-- ── fixtures (as postgres; RLS bypassed) ───────────────────────────
insert into auth.users (instance_id, id, aud, role, email, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000','e0000000-0000-0000-0000-000000000001','authenticated','authenticated','pk-seller@test.local', now(), now()),
  ('00000000-0000-0000-0000-000000000000','e0000000-0000-0000-0000-000000000002','authenticated','authenticated','pk-cust@test.local',   now(), now()),
  ('00000000-0000-0000-0000-000000000000','e0000000-0000-0000-0000-000000000003','authenticated','authenticated','pk-other@test.local',  now(), now());

insert into public.profiles (id, full_name, email, role, seller_status)
values
  ('e0000000-0000-0000-0000-000000000001','Pk Seller','pk-seller@test.local','seller','approved'),
  ('e0000000-0000-0000-0000-000000000002','Pk Customer','pk-cust@test.local','customer','none'),
  ('e0000000-0000-0000-0000-000000000003','Pk Other','pk-other@test.local','customer','none');

insert into public.stores (id, owner_id, name, location)
values ('e0000000-0000-0000-0000-000000000005','e0000000-0000-0000-0000-000000000001','Pk Store','Pk City');

insert into public.products (id, store_id, seller_id, name, price, category, sale_price, sale_starts_at, sale_ends_at)
values ('e0000000-0000-0000-0000-000000000004','e0000000-0000-0000-0000-000000000005',
        'e0000000-0000-0000-0000-000000000001','Pk Shoe', 1500, 'General',
        1200, now() - interval '1 day', now() + interval '1 day');

insert into public.inventory (product_id, size, stock)
values ('e0000000-0000-0000-0000-000000000004','40', 5),
       ('e0000000-0000-0000-0000-000000000004','41', 1),
       ('e0000000-0000-0000-0000-000000000004','42', 3);

-- ══ 1. Structure ═══════════════════════════════════════════════════
select has_table('public','pickup_reservations','1: the table exists');
select has_function('public','request_pickup_reservation',
                    array['uuid','text','integer'],
                    '2: request RPC exists');
select has_function('public','cancel_pickup_reservation', array['uuid'],
                    '3: cancel RPC exists');
select has_function('public','fulfill_pickup_reservation', array['uuid','text'],
                    '4: fulfill RPC exists');
select has_function('public','expire_pickup_reservations', array[]::text[],
                    '5: expiry sweep exists');
select has_function('public','send_pickup_reservation_reminders', array[]::text[],
                    '6: reminder sweep exists');
select is(public.pickup_reservation_max_quantity(), 2,
          '7: the cap is 2 — the checklist''s own "1-2 pairs" framing');

-- ⚠️ The new table must be INSIDE the device gate, not exempt from it: a
-- pickup hold says what a customer is holding.
select is(
  (select count(*)::int from pg_policies
    where schemaname='public' and tablename='pickup_reservations'
      and policyname='Require a trusted device'),
  1,
  '8: the table is device-gated (the migration called install_device_gate_policies)'
);
select ok(
  not ('pickup_reservations' = any (public.device_gate_exempt_tables())),
  '9: …and it is NOT in the exemption list'
);

-- ⚠️ No write policies: the RPC is the only way to create or resolve a hold,
-- so the cap and the stock check cannot be bypassed by a hand-crafted client.
select is(
  (select count(*)::int from pg_policies
    where schemaname='public' and tablename='pickup_reservations'
      and cmd in ('INSERT','UPDATE','DELETE')),
  0,
  '10: no INSERT/UPDATE/DELETE policy exists'
);
select is(
  (select count(*)::int from pg_policies
    where schemaname='public' and tablename='pickup_reservations'
      and cmd = 'SELECT'),
  3,
  '11: exactly three SELECT policies (customer, seller, admin)'
);

-- ══ 2. Request ═════════════════════════════════════════════════════
select set_config('request.jwt.claims',
  public.tmp_pickup_claims('e0000000-0000-0000-0000-000000000002'), true);

select is(public.tmp_pickup_stock('40'), 5,
          '12: size 40 starts with 5 in stock');

select lives_ok(
  $$select public.request_pickup_reservation('e0000000-0000-0000-0000-000000000004','40',2)$$,
  '13: a customer can request a 2-pair hold'
);
-- ⚠️ The hold is real.
select is(public.tmp_pickup_stock('40'), 3,
          '14: the hold moved exactly 2 units out of inventory');
select is(
  (select reserved_stock from public.pickup_reservations
    where status='active' and customer_id='e0000000-0000-0000-0000-000000000002'
      and size='40'),
  2,
  '15: reserved_stock records what was held'
);
select is(
  (select status::text from public.pickup_reservations
    where customer_id='e0000000-0000-0000-0000-000000000002' and size='40'),
  'active',
  '16: the hold is active'
);
select ok(
  (select pickup_deadline between now() + interval '23 hours'
                              and now() + interval '25 hours'
     from public.pickup_reservations
    where customer_id='e0000000-0000-0000-0000-000000000002' and size='40'),
  '17: pickup_deadline is 24 hours out'
);
select is(public.pickup_reserved_stock_for_product(
            'e0000000-0000-0000-0000-000000000004','40'), 2,
          '18: the pickup hold helper reports the held units');
select is(public.pickup_reserved_stock_for_product(
            'e0000000-0000-0000-0000-000000000004'), 2,
          '19: …and the whole-product total');

-- Notifications, reusing the existing `reservations` category.
select is(public.tmp_pickup_notices(
            'e0000000-0000-0000-0000-000000000002','Pickup reservation confirmed'), 1,
          '20: the customer is told the hold is confirmed');
select is(public.tmp_pickup_notices(
            'e0000000-0000-0000-0000-000000000001','New pickup reservation'), 1,
          '21: the seller is told stock left the shelf');
select is(
  (select category::text from public.notifications
    where user_id='e0000000-0000-0000-0000-000000000002'
      and title='Pickup reservation confirmed'),
  'reservations',
  '22: …through the EXISTING reservations category (no new category)'
);

-- Rejections.
select throws_ok(
  $$select public.request_pickup_reservation('e0000000-0000-0000-0000-000000000004','42',3)$$,
  'P0001',
  'ABOVE_PICKUP_CAP (2) — for 3 or more units request a bulk reservation instead',
  '23: above the cap is refused and pointed at the bulk flow'
);
select throws_ok(
  $$select public.request_pickup_reservation('e0000000-0000-0000-0000-000000000004','42',0)$$,
  'P0001', 'INVALID_QUANTITY',
  '24: a zero quantity is refused'
);
select throws_ok(
  $$select public.request_pickup_reservation('00000000-0000-0000-0000-00000000dead','42',1)$$,
  'P0001', 'PRODUCT_NOT_FOUND',
  '25: an unknown product is refused'
);
select throws_ok(
  $$select public.request_pickup_reservation('e0000000-0000-0000-0000-000000000004','   ',1)$$,
  'P0001', 'SIZE_REQUIRED',
  '26: a blank size is refused (a hold is always size-specific)'
);
select throws_ok(
  $$select public.request_pickup_reservation('e0000000-0000-0000-0000-000000000004','99',1)$$,
  'P0001', 'INSUFFICIENT_STOCK (0 available in size 99)',
  '27: a size with no stock is refused'
);
select throws_ok(
  $$select public.request_pickup_reservation('e0000000-0000-0000-0000-000000000004','41',2)$$,
  'P0001', 'INSUFFICIENT_STOCK (1) < 2',
  '28: asking for more than the size has is refused'
);
select throws_ok(
  $$select public.request_pickup_reservation('e0000000-0000-0000-0000-000000000004','40',1)$$,
  'P0001', 'RESERVATION_ALREADY_EXISTS',
  '29: one live hold per customer per size'
);
select is(public.tmp_pickup_stock('41'), 1,
          '30: none of those rejections moved any stock');

-- ⚠️ The RPC's own duplicate check runs in the same statement but is SERIAL:
-- two simultaneous submits both see "no active hold" and both insert, so one
-- customer ends up holding the same pair twice. (The stock compare-and-set
-- still stops them overselling, which is exactly why it would go unnoticed.)
-- The partial unique index is the backstop, and these assertions prove it is
-- real, correctly scoped, and has teeth.
--
-- Uses customer …03, who has no hold, and cleans up after itself so the later
-- seller-view counts are unaffected.
select has_index(
  'public','pickup_reservations',
  'idx_pickup_reservations_one_active_per_customer_product_size',
  '30a: a partial unique index backstops the serial duplicate check'
);
insert into public.pickup_reservations
  (customer_id, store_id, product_id, size, quantity, reserved_stock, pickup_deadline)
values ('e0000000-0000-0000-0000-000000000003','e0000000-0000-0000-0000-000000000005',
        'e0000000-0000-0000-0000-000000000004','41',1,1, now() + interval '1 day');
select throws_ok(
  $$insert into public.pickup_reservations
      (customer_id, store_id, product_id, size, quantity, reserved_stock, pickup_deadline)
    values ('e0000000-0000-0000-0000-000000000003','e0000000-0000-0000-0000-000000000005',
            'e0000000-0000-0000-0000-000000000004','41',1,1, now() + interval '1 day')$$,
  '23505', null,
  '30b: a second ACTIVE hold for the same customer+product+size is impossible (concurrent loser)'
);
-- …but a RESOLVED hold must NOT block a new one: the index is partial on
-- status = 'active', so cancelling and reserving again still works.
update public.pickup_reservations set status = 'cancelled'
 where customer_id = 'e0000000-0000-0000-0000-000000000003' and size = '41';
select lives_ok(
  $$insert into public.pickup_reservations
      (customer_id, store_id, product_id, size, quantity, reserved_stock, pickup_deadline)
    values ('e0000000-0000-0000-0000-000000000003','e0000000-0000-0000-0000-000000000005',
            'e0000000-0000-0000-0000-000000000004','41',1,1, now() + interval '1 day')$$,
  '30c: a cancelled hold does not block a new one (the index is partial)'
);
delete from public.pickup_reservations
 where customer_id = 'e0000000-0000-0000-0000-000000000003';

-- A size-normalized request resolves to the real inventory row, the same
-- way checkout resolves sizes ("EU 40" and "40" are one size).
select lives_ok(
  $$select public.request_pickup_reservation('e0000000-0000-0000-0000-000000000004','EU 42',1)$$,
  '31: a decorated size string is accepted'
);
select is(public.tmp_pickup_stock('42'), 2,
          '32: …and held against the real inventory row');

-- ⚠️ The cap cannot be bypassed by a direct INSERT: there is no INSERT policy.
set local role authenticated;
select throws_ok(
  $$insert into public.pickup_reservations
      (customer_id, store_id, product_id, size, quantity, reserved_stock, pickup_deadline)
    values ('e0000000-0000-0000-0000-000000000002','e0000000-0000-0000-0000-000000000005',
            'e0000000-0000-0000-0000-000000000004','40',99,99, now() + interval '1 day')$$,
  '42501', null,
  '33: a hand-crafted INSERT is denied (RLS has no INSERT policy)'
);
reset role;
select is(public.tmp_pickup_stock('40'), 3,
          '34: …and that attempt moved no stock');

-- Unauthenticated.
select set_config('request.jwt.claims', '{"sub":null,"role":null}', true);
select throws_ok(
  $$select public.request_pickup_reservation('e0000000-0000-0000-0000-000000000004','40',1)$$,
  'P0001', 'NOT_AUTHENTICATED',
  '35: a caller with no session is refused'
);

-- ══ 3. Cancel ══════════════════════════════════════════════════════
-- The OTHER customer cannot cancel this hold.
select set_config('request.jwt.claims',
  public.tmp_pickup_claims('e0000000-0000-0000-0000-000000000003'), true);
select throws_ok(
  $$select public.cancel_pickup_reservation(
      (select id from public.pickup_reservations
        where customer_id='e0000000-0000-0000-0000-000000000002' and size='40'))$$,
  'P0001', 'FORBIDDEN',
  '36: someone else cannot cancel your hold'
);

select set_config('request.jwt.claims',
  public.tmp_pickup_claims('e0000000-0000-0000-0000-000000000002'), true);
select lives_ok(
  $$select public.cancel_pickup_reservation(
      (select id from public.pickup_reservations
        where customer_id='e0000000-0000-0000-0000-000000000002'
          and size='40' and status='active'))$$,
  '37: the customer can cancel their own hold'
);
-- ⚠️ Exactly the held units come back, not more.
select is(public.tmp_pickup_stock('40'), 5,
          '38: cancel returned exactly the 2 held units');
select is(
  (select status::text from public.pickup_reservations
    where customer_id='e0000000-0000-0000-0000-000000000002' and size='40'),
  'cancelled',
  '39: …and the hold is cancelled'
);
select throws_ok(
  $$select public.cancel_pickup_reservation(
      (select id from public.pickup_reservations
        where customer_id='e0000000-0000-0000-0000-000000000002' and size='40'))$$,
  'P0001', 'ALREADY_RESOLVED',
  '40: cancelling twice is refused'
);

-- ⚠️⚠️ THE RACE: the expiry sweep runs AFTER the manual cancel. This is the
-- double-release bug class — the sweep must find nothing to do, and the
-- stock must be exactly what the cancel left.
select is(public.expire_pickup_reservations(), 0,
          '41: the sweep after a manual cancel expires nothing');
select is(public.tmp_pickup_stock('40'), 5,
          '42: …so the stock was NOT released a second time');
select is(
  public._release_pickup_reservation_stock(
    (select id from public.pickup_reservations
      where customer_id='e0000000-0000-0000-0000-000000000002' and size='40'),
    'active', 'expired'),
  false,
  '43: the release core itself no-ops once the status has moved on'
);
select is(public.tmp_pickup_stock('40'), 5,
          '44: …and that no-op moved no stock either');

-- ══ 4. Expiry ══════════════════════════════════════════════════════
-- The remaining active hold (size 42) is still inside its 24h window, so
-- the sweep must leave it alone.
select is(
  (select status::text from public.pickup_reservations
    where customer_id='e0000000-0000-0000-0000-000000000002' and size='42'),
  'active',
  '45: an unexpired hold survives the sweep'
);
select is(public.tmp_pickup_stock('42'), 2,
          '46: …still holding its unit');
select lives_ok(
  $$update public.pickup_reservations
       set pickup_deadline = now() - interval '1 minute'
     where customer_id='e0000000-0000-0000-0000-000000000002'
       and size='42' and status='active'$$,
  '47: (force that hold past its deadline)'
);

select is(public.expire_pickup_reservations(), 1,
          '48: the sweep expires the lapsed hold');
select is(public.tmp_pickup_stock('42'), 3,
          '49: …and returns its unit to inventory');
select is(public.expire_pickup_reservations(), 0,
          '50: the sweep is idempotent');
select is(public.tmp_pickup_stock('42'), 3,
          '51: …with no second release');

-- ══ 5. Fulfill — "the customer arrived" ═════════════════════════════
select set_config('request.jwt.claims',
  public.tmp_pickup_claims('e0000000-0000-0000-0000-000000000002'), true);
select lives_ok(
  $$select public.request_pickup_reservation('e0000000-0000-0000-0000-000000000004','41',1)$$,
  '52: a fresh 1-pair hold to fulfil (size 41 has exactly one)'
);
select is(public.tmp_pickup_stock('41'), 0,
          '53: …which takes the last unit of size 41 off the shelf');

-- Only the store owner may fulfil.
select throws_ok(
  $$select public.fulfill_pickup_reservation(
      (select id from public.pickup_reservations
        where status='active' and size='41'))$$,
  'P0001', 'FORBIDDEN',
  '54: the customer cannot mark their own hold fulfilled'
);
select set_config('request.jwt.claims',
  public.tmp_pickup_claims('e0000000-0000-0000-0000-000000000003'), true);
select throws_ok(
  $$select public.fulfill_pickup_reservation(
      (select id from public.pickup_reservations
        where status='active' and size='41'))$$,
  'P0001', 'FORBIDDEN',
  '55: neither can an unrelated user'
);

select set_config('request.jwt.claims',
  public.tmp_pickup_claims('e0000000-0000-0000-0000-000000000001'), true);
select throws_ok(
  $$select public.fulfill_pickup_reservation(
      (select id from public.pickup_reservations
        where status='active' and size='41'), 'cheque')$$,
  'P0001', 'INVALID_PAYMENT_METHOD',
  '56: an unsupported payment method is refused'
);
select lives_ok(
  $$select public.fulfill_pickup_reservation(
      (select id from public.pickup_reservations
        where status='active' and size='41'), 'cash')$$,
  '57: the store owner marks it collected'
);

select is(
  (select count(*)::int from public.orders o
    join public.pickup_reservations r on r.fulfilled_order_id = o.id
   where r.size = '41'),
  1,
  '58: exactly one order was written'
);
select is(
  (select o.source || '/' || o.status || '/' || o.payment_status || '/' || o.fulfillment
     from public.orders o
     join public.pickup_reservations r on r.fulfilled_order_id = o.id
    where r.size = '41'),
  'pos/received/paid/pickup',
  '59: …as a completed POS pickup sale (so POS sales, revenue and sold counts all see it)'
);
select is(
  (select o.total_amount from public.orders o
    join public.pickup_reservations r on r.fulfilled_order_id = o.id
   where r.size = '41'),
  1200::numeric,
  '60: the total comes from the SERVER''s sale-aware price (1500 → 1200 on sale)'
);
select is(
  (select count(*)::int from public.order_items i
    join public.pickup_reservations r on r.fulfilled_order_id = i.order_id
   where r.size = '41' and i.quantity = 1 and i.unit_price = 1200 and i.size = '41'),
  1,
  '61: …and one order_item carries the size, quantity and the same price'
);
select is(
  (select count(*)::int from public.order_status_history h
    join public.pickup_reservations r on r.fulfilled_order_id = h.order_id
   where r.size = '41' and h.status = 'received'),
  1,
  '62: the POS status-history row is written (the app''s own write parses the uuid as an int and never lands)'
);

-- ⚠️ THE INVARIANT: fulfil must not draw stock a second time. The units were
-- taken when the hold was created; a second decrement would silently lose
-- them from inventory forever.
select is(public.tmp_pickup_stock('41'), 0,
          '63: fulfil did NOT move stock again — the hold already was the draw');
select is(
  (select status::text from public.pickup_reservations where size='41'),
  'fulfilled',
  '64: the hold is fulfilled'
);
select ok(
  (select fulfilled_at is not null and fulfilled_order_id is not null
     from public.pickup_reservations where size='41'),
  '65: …with its fulfilled_at and order id stamped'
);

-- ⚠️ The STEP 6 DECISION, asserted against the real aggregation query:
-- a fulfilled pickup counts toward `units_sold`, because it creates the same
-- paid, non-cancelled order a POS sale does (see fetchUnitsSold()).
select is(
  (select coalesce(sum(i.quantity), 0)::int
     from public.order_items i
     join public.orders o on o.id = i.order_id
    where o.status <> 'cancelled'
      and o.payment_status = 'paid'
      and i.product_id = 'e0000000-0000-0000-0000-000000000004'),
  1,
  '66: the collected pickup counts toward units_sold (paid, non-cancelled order)'
);
select throws_ok(
  $$select public.fulfill_pickup_reservation(
      (select id from public.pickup_reservations where size='41'))$$,
  'P0001', 'ALREADY_RESOLVED',
  '67: fulfilling twice is refused'
);
select throws_ok(
  $$select public.cancel_pickup_reservation(
      (select id from public.pickup_reservations where size='41'))$$,
  'P0001', 'ALREADY_RESOLVED',
  '68: a fulfilled sale cannot be cancelled back into stock'
);
select is(public.tmp_pickup_stock('41'), 0,
          '69: …so no stock was stolen back after the sale'
);

-- ══ 6. The T-2h reminder ═══════════════════════════════════════════
select set_config('request.jwt.claims',
  public.tmp_pickup_claims('e0000000-0000-0000-0000-000000000002'), true);
select lives_ok(
  $$select public.request_pickup_reservation('e0000000-0000-0000-0000-000000000004','40',1)$$,
  '70: a hold to remind about'
);
select lives_ok(
  $$update public.pickup_reservations
       set pickup_deadline = now() + interval '90 minutes'
     where status='active'$$,
  '71: (put it inside the 2-hour window)'
);
select is(public.send_pickup_reservation_reminders(), 1,
          '72: the reminder sweep fires for a hold expiring within 2 hours');
select ok(
  (select reminder_sent_at is not null from public.pickup_reservations
    where status='active'),
  '73: …and stamps reminder_sent_at'
);
select is(public.send_pickup_reservation_reminders(), 0,
          '74: the reminder is exactly-once (a second sweep sends nothing)'
);
select is(public.tmp_pickup_notices(
            'e0000000-0000-0000-0000-000000000002','Your pickup hold expires soon'), 1,
          '75: exactly one reminder notification reached the customer'
);

-- A hold that is NOT near its deadline must not be reminded.
select lives_ok(
  $$select public.request_pickup_reservation('e0000000-0000-0000-0000-000000000004','42',1)$$,
  '76: a second hold, well inside its 24 hours'
);
select is(public.send_pickup_reservation_reminders(), 0,
          '77: nothing is reminded outside the 2-hour window'
);
select is(public.tmp_pickup_stock('40'), 4,
          '78: the reminder sweep touched no stock'
);
select is(
  (select count(*)::int from public.pickup_reservations where status='active'),
  2,
  '79: …and no status (both holds are still active)'
);

-- ══ 7. The STORE's side of the T-2h reminder ════════════════════════
-- The customer is reminded once per hold (a specific pair to go and get). The
-- store must NOT be: twenty holds would mean twenty notifications, and what a
-- seller can act on is the batch — which holds lapse and how much stock comes
-- back. So the store gets ONE aggregated summary per run.
--
-- A SECOND store, so "per store owner" is actually tested: a seller must not be
-- told about another store's holds.
insert into auth.users (instance_id, id, aud, role, email, created_at, updated_at)
values ('00000000-0000-0000-0000-000000000000','e0000000-0000-0000-0000-000000000009','authenticated','authenticated','pk-seller2@test.local', now(), now());
insert into public.profiles (id, full_name, email, role, seller_status)
values ('e0000000-0000-0000-0000-000000000009','Pk Seller Two','pk-seller2@test.local','seller','approved');
insert into public.stores (id, owner_id, name, location)
values ('e0000000-0000-0000-0000-000000000006','e0000000-0000-0000-0000-000000000009','Pk Store Two','Pk City');
insert into public.products (id, store_id, seller_id, name, price, is_active)
values ('e0000000-0000-0000-0000-000000000007','e0000000-0000-0000-0000-000000000006',
        'e0000000-0000-0000-0000-000000000009','Pk Shoe Two', 900, true);
insert into public.inventory (product_id, size, stock)
values ('e0000000-0000-0000-0000-000000000007','40', 3);

select set_config('request.jwt.claims',
  public.tmp_pickup_claims('e0000000-0000-0000-0000-000000000002'), true);
select lives_ok(
  $$select public.request_pickup_reservation('e0000000-0000-0000-0000-000000000007','40',2)$$,
  '80: a hold at a SECOND store, same customer'
);

-- Put every active hold inside the 2-hour window and clear the stamps, so this
-- section measures one sweep on its own terms (section 6 already stamped one).
select lives_ok(
  $$update public.pickup_reservations
       set reminder_sent_at = null, pickup_deadline = now() + interval '90 minutes'
     where status = 'active'$$,
  '81: (all three holds moved into the 2-hour window)'
);

-- Counts are captured BEFORE the sweep: notifications are created inside one
-- transaction, so `created_at` is identical for every row and cannot be used
-- to separate this run's rows from section 6's.
select set_config('tmp.pk_cust_before', (select count(*)::text from public.notifications
   where user_id='e0000000-0000-0000-0000-000000000002'
     and title='Your pickup hold expires soon'), true);
select set_config('tmp.pk_a_before', (select count(*)::text from public.notifications
   where user_id='e0000000-0000-0000-0000-000000000001'
     and title='Pickup holds expiring soon'), true);
select set_config('tmp.pk_b_before', (select count(*)::text from public.notifications
   where user_id='e0000000-0000-0000-0000-000000000009'
     and title='Pickup holds expiring soon'), true);

select is(public.send_pickup_reservation_reminders(), 3,
          '82: the sweep reminds every hold in the window (3 holds, 2 stores)');
select is(public.tmp_pickup_notices(
            'e0000000-0000-0000-0000-000000000002','Your pickup hold expires soon')
          - current_setting('tmp.pk_cust_before')::int,
          3,
          '83: the customer still gets ONE notification PER HOLD, not a summary');
select is(public.tmp_pickup_notices(
            'e0000000-0000-0000-0000-000000000001','Pickup holds expiring soon')
          - current_setting('tmp.pk_a_before')::int,
          1,
          '84: the store owner gets exactly ONE summary for the batch (not 2)');
select is(
  (select count(*)::int from public.notifications
    where user_id='e0000000-0000-0000-0000-000000000001'
      and title='Pickup holds expiring soon'
      and message='2 pickup holds expire in the next 2 hours — 2 pairs return to stock unless collected.'),
  1,
  '85: …stating THIS store''s counts: 2 holds, 2 pairs coming back'
);
select is(
  (select count(*)::int from public.notifications
    where user_id='e0000000-0000-0000-0000-000000000009'
      and title='Pickup holds expiring soon'
      and message='1 pickup hold expires in the next 2 hours — 2 pairs return to stock unless collected.'),
  1,
  '86: a second store''s owner is summarised separately, with singular wording'
);

-- Capture AFTER the first sweep, so the second sweep's effect is measured
-- against it (the counts themselves are cumulative across the whole file).
select set_config('tmp.pk_cust_mid', (select count(*)::text from public.notifications
   where user_id='e0000000-0000-0000-0000-000000000002'
     and title='Your pickup hold expires soon'), true);
select set_config('tmp.pk_a_mid', (select count(*)::text from public.notifications
   where user_id='e0000000-0000-0000-0000-000000000001'
     and title='Pickup holds expiring soon'), true);
select set_config('tmp.pk_b_mid', (select count(*)::text from public.notifications
   where user_id='e0000000-0000-0000-0000-000000000009'
     and title='Pickup holds expiring soon'), true);

select is(public.send_pickup_reservation_reminders(), 0,
          '87: a second sweep reminds nobody (per-row stamps hold)');
select is(
  (public.tmp_pickup_notices('e0000000-0000-0000-0000-000000000002','Your pickup hold expires soon')
     - current_setting('tmp.pk_cust_mid')::int)
  + (public.tmp_pickup_notices('e0000000-0000-0000-0000-000000000001','Pickup holds expiring soon')
     - current_setting('tmp.pk_a_mid')::int)
  + (public.tmp_pickup_notices('e0000000-0000-0000-0000-000000000009','Pickup holds expiring soon')
     - current_setting('tmp.pk_b_mid')::int),
  0,
  '88: …and the aggregate inherits exactly-once from the same stamp'
);
select is(
  (select count(*)::int from public.notifications
    where title = 'Pickup holds expiring soon'
      and user_id not in ('e0000000-0000-0000-0000-000000000001',
                          'e0000000-0000-0000-0000-000000000009')),
  0,
  '89: the summary went to STORE OWNERS only — never to the customer, never to anyone else'
);

-- ── A store with NO owner ───────────────────────────────────────
-- `notifications.user_id` is NOT NULL, so counting an ownerless store's hold
-- into the summary would ABORT the whole sweep — and silently stop every other
-- store's reminders with it, which is exactly the "one bad row kills the batch"
-- shape worth guarding.
--
-- The hold is inserted DIRECTLY on purpose. `stores.owner_id` is nullable but
-- its FK is plain NO ACTION (a profile with a store cannot be deleted), so an
-- ownerless store is not reachable through the app today — and
-- `request_pickup_reservation` cannot even create a hold for one, because its
-- seller heads-up INSERT ... SELECT has the same NULL-recipient hazard the
-- reminder needed a guard for. So this asserts the DEFENSIVE property: if a
-- store ever loses its owner (an `ON DELETE SET NULL` migration would do it),
-- the sweep keeps working.
insert into public.stores (id, owner_id, name, location)
values ('e0000000-0000-0000-0000-000000000008', null, 'Pk Store Orphan', 'Pk City');
insert into public.inventory (product_id, size, stock)
values ('e0000000-0000-0000-0000-000000000004','99', 1);
insert into public.pickup_reservations
  (customer_id, store_id, product_id, size, quantity, reserved_stock,
   status, pickup_deadline, reserved_at)
values ('e0000000-0000-0000-0000-000000000003','e0000000-0000-0000-0000-000000000008',
        'e0000000-0000-0000-0000-000000000004','99',1,1,
        'active', now() + interval '30 minutes', now());

-- lives_ok, not is(), so a raise is reported as a FAILED ASSERTION rather
-- than aborting the file (which is what it did the first time: "you planned 95
-- tests but ran 92", with no line naming the cause).
select lives_ok(
  $$select public.send_pickup_reservation_reminders()$$,
  '90: the sweep still SUCCEEDS with an ownerless store in the batch'
);
select is(
  (select count(*)::int from public.notifications where user_id is null),
  0,
  '91: …and no notification was written without a recipient'
);
select is(public.tmp_pickup_notices(
            'e0000000-0000-0000-0000-000000000003','Your pickup hold expires soon'), 1,
          '92: …and that hold''s CUSTOMER was still reminded'
);

-- ══ 8. EXTENDING A LIVE HOLD ══════════════════════════════════════
-- A customer may ask for more time before a hold lapses — but the store must not
-- end up parking stock indefinitely, so the patience is bounded on both axes and
-- the ceiling is a table CHECK rather than only a rule inside the RPC.
--
-- Fresh fixtures, so every notification count in this section starts at zero.
insert into auth.users (instance_id, id, aud, role, email, created_at, updated_at)
values ('00000000-0000-0000-0000-000000000000','e0000000-0000-0000-0000-000000000010','authenticated','authenticated','pk-seller3@test.local', now(), now()),
       ('00000000-0000-0000-0000-000000000000','e0000000-0000-0000-0000-000000000011','authenticated','authenticated','pk-cust2@test.local',   now(), now()),
       ('00000000-0000-0000-0000-000000000000','e0000000-0000-0000-0000-000000000012','authenticated','authenticated','pk-cust3@test.local',   now(), now());
insert into public.profiles (id, full_name, email, role, seller_status)
values ('e0000000-0000-0000-0000-000000000010','Pk Seller Three','pk-seller3@test.local','seller','approved'),
       ('e0000000-0000-0000-0000-000000000011','Pk Customer Two','pk-cust2@test.local','customer','none'),
       ('e0000000-0000-0000-0000-000000000012','Pk Customer Three','pk-cust3@test.local','customer','none');
insert into public.stores (id, owner_id, name, location)
values ('e0000000-0000-0000-0000-000000000013','e0000000-0000-0000-0000-000000000010','Pk Store Three','Pk City');
insert into public.products (id, store_id, seller_id, name, price, is_active)
values ('e0000000-0000-0000-0000-000000000014','e0000000-0000-0000-0000-000000000013',
        'e0000000-0000-0000-0000-000000000010','Pk Shoe Three', 700, true);
insert into public.inventory (product_id, size, stock)
values ('e0000000-0000-0000-0000-000000000014','40', 4),
       ('e0000000-0000-0000-0000-000000000014','41', 3),
       ('e0000000-0000-0000-0000-000000000014','42', 2);

-- This section's product is NOT the one `tmp_pickup_stock` reads (that helper is
-- pinned to the section-1 product), so stock is read per-size below.
create or replace function public.tmp_extend_stock(p_size text)
returns integer language sql stable as $$
  select stock from public.inventory
   where product_id = 'e0000000-0000-0000-0000-000000000014' and size = p_size;
$$;

select has_function('public','extend_pickup_reservation', array['uuid'],
                    '93: the extend RPC exists');
select is(public.pickup_reservation_hold_hours(), 24,
          '94: the base window is 24 hours — one number, used by the RPC and the CHECK');
select is(public.pickup_reservation_max_extensions(), 1,
          '95: a hold may be extended once');
select is(public.pickup_reservation_extension_hours(), 24,
          '96: an extension buys one more ordinary window');

-- ⚠️ The ceiling must be readable from the SCHEMA, not just from the RPC.
select ok(
  exists (select 1 from pg_constraint
           where conname = 'pickup_reservations_within_max_window'
             and conrelid = 'public.pickup_reservations'::regclass),
  '97: the total-window ceiling is a table CHECK (no RPC can quietly exceed it)'
);
select ok(
  exists (select 1 from pg_constraint
           where conname = 'pickup_reservations_within_extension_cap'
             and conrelid = 'public.pickup_reservations'::regclass),
  '98: the extension count is itself CHECKed against the cap'
);

select set_config('request.jwt.claims',
  public.tmp_pickup_claims('e0000000-0000-0000-0000-000000000011'), true);
select lives_ok(
  $$select public.request_pickup_reservation('e0000000-0000-0000-0000-000000000014','40',2)$$,
  '99: a hold to extend'
);
select is(public.tmp_extend_stock('40'), 2,
          '100: (creates its own stock state: 2 held of 4)');

select is(
  (select extension_count from public.pickup_reservations
    where customer_id='e0000000-0000-0000-0000-000000000011'),
  0,
  '101: a new hold has been extended zero times'
);
select is(
  (select round(extract(epoch from (pickup_deadline - created_at))/3600)::int
     from public.pickup_reservations
    where customer_id='e0000000-0000-0000-0000-000000000011'),
  24,
  '102: and its window is exactly the base 24 hours'
);

select lives_ok(
  $$select public.extend_pickup_reservation(
      (select id from public.pickup_reservations
        where customer_id='e0000000-0000-0000-0000-000000000011'))$$,
  '103: the customer can extend their own live hold'
);
select is(
  (select extension_count from public.pickup_reservations
    where customer_id='e0000000-0000-0000-0000-000000000011'),
  1,
  '104: the extension is counted on the row'
);
select is(
  (select round(extract(epoch from (pickup_deadline - created_at))/3600)::int
     from public.pickup_reservations
    where customer_id='e0000000-0000-0000-0000-000000000011'),
  48,
  '105: and the total window is now 48 hours — the whole commitment, no more'
);
-- ⚠️ More time must not mean more or less stock: the units left the shelf when
-- the hold was created, and an extension only changes the deadline.
select is(public.tmp_extend_stock('40'), 2,
          '106: extending moves no stock (the hold already owns it)');
select is(
  (select status::text from public.pickup_reservations
    where customer_id='e0000000-0000-0000-0000-000000000011'),
  'active',
  '107: and the hold is still simply active'
);

select throws_ok(
  $$select public.extend_pickup_reservation(
      (select id from public.pickup_reservations
        where customer_id='e0000000-0000-0000-0000-000000000011'))$$,
  'P0001', 'EXTENSION_LIMIT_REACHED (1) — this hold has already been extended; reserve again after it lapses',
  '108: a second extension is refused, and says why'
);

-- ⚠️ …and the cap holds even for code that bypasses the RPC entirely.
-- 96 h is past the ABSOLUTE ceiling (72 h = hold + every budget; see §2b and
-- store_pickup_extensions.test.sql, which proves the store's budget is part of
-- that sum and that exactly 72 h is still accepted).
select throws_ok(
  $$update public.pickup_reservations
       set pickup_deadline = created_at + interval '96 hours'
     where customer_id='e0000000-0000-0000-0000-000000000011'$$,
  '23514', null,
  '109: a direct UPDATE past the absolute ceiling is refused by the CHECK, not just by the RPC'
);

-- Notifications: both sides are told, because the store''s commitment grew.
select is(public.tmp_pickup_notices(
            'e0000000-0000-0000-0000-000000000011','Pickup hold extended'), 1,
          '110: the customer is told the hold was extended');
select is(public.tmp_pickup_notices(
            'e0000000-0000-0000-0000-000000000010','Pickup hold extended'), 1,
          '111: the STORE is told too — it is its stock on hold');
select ok(
  (select message like '%That was your last extension%'
     from public.notifications
    where user_id='e0000000-0000-0000-0000-000000000011'
      and title='Pickup hold extended'),
  '112: …and the customer knows there is no more time to ask for'
);

-- ── The rules that bound WHO may extend, and WHEN ──────────────────
select set_config('request.jwt.claims',
  public.tmp_pickup_claims('e0000000-0000-0000-0000-000000000012'), true);
select throws_ok(
  $$select public.extend_pickup_reservation(
      (select id from public.pickup_reservations
        where customer_id='e0000000-0000-0000-0000-000000000011'))$$,
  'P0001', 'FORBIDDEN',
  '113: another customer cannot extend someone else''s hold'
);
select set_config('request.jwt.claims',
  public.tmp_pickup_claims('e0000000-0000-0000-0000-000000000010'), true);
select throws_ok(
  $$select public.extend_pickup_reservation(
      (select id from public.pickup_reservations
        where customer_id='e0000000-0000-0000-0000-000000000011'))$$,
  'P0001', 'FORBIDDEN',
  '114: the STORE cannot extend on the customer''s behalf — that is a bulk reservation'
);
select set_config('request.jwt.claims', '{"sub":null,"role":null}', true);
select throws_ok(
  $$select public.extend_pickup_reservation(
      (select id from public.pickup_reservations
        where customer_id='e0000000-0000-0000-0000-000000000011'))$$,
  'P0001', 'NOT_AUTHENTICATED',
  '115: no session, no extension'
);
select set_config('request.jwt.claims',
  public.tmp_pickup_claims('e0000000-0000-0000-0000-000000000011'), true);

-- ⚠️ A LAPSED hold must not be extendable: the sweep may release it at any
-- moment, so promising more time would promise stock nobody can guarantee.
-- A second hold on a DIFFERENT size (one live hold per customer per
-- product+size is enforced by the partial unique index).
select lives_ok(
  $$select public.request_pickup_reservation('e0000000-0000-0000-0000-000000000014','41',1)$$,
  '116: a second hold, to let lapse'
);
select lives_ok(
  $$update public.pickup_reservations
       set pickup_deadline = now() - interval '1 minute'
     where customer_id='e0000000-0000-0000-0000-000000000011'
       and size = '41'$$,
  '117: (pushed past its deadline; the sweep has not run yet)'
);
select throws_ok(
  $$select public.extend_pickup_reservation(
      (select id from public.pickup_reservations
        where customer_id='e0000000-0000-0000-0000-000000000011'
          and size = '41'))$$,
  'P0001', 'HOLD_LAPSED — this hold has already run out; reserve again',
  '118: a hold past its deadline cannot be extended — only live holds can'
);

-- Reminders: an extended hold has a NEW deadline and is owed a NEW warning.
-- A THIRD hold (size 42) so this part is not competing with the extension cap
-- already spent by size 40 above.
select lives_ok(
  $$select public.request_pickup_reservation('e0000000-0000-0000-0000-000000000014','42',1)$$,
  '119: a third hold, whose reminder has already fired'
);
select lives_ok(
  $$update public.pickup_reservations
       set reminder_sent_at = now()
     where customer_id='e0000000-0000-0000-0000-000000000011'
       and size = '42'$$,
  '120: (simulate the T-2h reminder having gone out for the OLD deadline)'
);
select lives_ok(
  $$select public.extend_pickup_reservation(
      (select id from public.pickup_reservations
        where customer_id='e0000000-0000-0000-0000-000000000011'
          and size = '42'))$$,
  '121: extend it'
);
select ok(
  (select reminder_sent_at is null from public.pickup_reservations
    where customer_id='e0000000-0000-0000-0000-000000000011' and size = '42'),
  '122: the old reminder stamp is CLEARED, so the new deadline can be warned about'
);
select lives_ok(
  $$update public.pickup_reservations
       set pickup_deadline = now() + interval '90 minutes'
     where customer_id='e0000000-0000-0000-0000-000000000011' and size = '42'$$,
  '123: (bring the NEW deadline inside the 2-hour window)'
);
select ok(
  public.send_pickup_reservation_reminders() >= 1,
  '124: …and the T-2h reminder fires again for it'
);
select is(public.tmp_pickup_notices(
            'e0000000-0000-0000-0000-000000000011','Your pickup hold expires soon'), 1,
          '125: exactly one warning reaches the customer — the one for the new deadline'
);

-- ══ 9. THE SHAPE A REPAIR MUST RESTORE ═════════════════════════════
-- The migration's §3b (`ALTER TABLE … ADD COLUMN IF NOT EXISTS`) exists because
-- `CREATE TABLE IF NOT EXISTS` is a NO-OP when the table already exists: a
-- re-apply over a `pickup_reservations` created by an EARLIER revision of the
-- same file silently kept the old shape and died on
-- `42703: column "extension_count" does not exist` (live, 2026-09-16).
--
-- The two ways that can regress are guarded from both ends, deliberately:
--   file text — the Dart contract test asserts §3 and §3b declare the SAME
--               columns, which is the only place the CREATE TABLE branch is
--               observable (test/services/pickup_reservation_contract_test.dart)
--   database  — this, the live table's column set exactly, both directions,
--               so a repair can be checked against a statement of intent rather
--               than against the error message it produced
-- A clean `db reset` builds the table through §3, so it cannot fail on a stale
-- table; what it CAN do is refuse to let the declared shape drift silently.
select is(
  (select array_agg(column_name order by column_name)::text
     from information_schema.columns
    where table_schema = 'public' and table_name = 'pickup_reservations'),
  (select array_agg(c order by c)::text
     from unnest(array[
            'id','customer_id','store_id','product_id','size','quantity',
            'reserved_stock','status','pickup_deadline','reserved_at',
            'released_at','fulfilled_at','fulfilled_order_id',
            'reminder_sent_at','extension_count','store_extension_count',
            'pickup_code','created_at'
          ]) as c),
  '129: pickup_reservations has exactly the columns §3/§3b declare'
);

select * from finish();
rollback;
