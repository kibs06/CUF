-- ══════════════════════════════════════════════════════════════════
-- Bulk reservation deposit-gate tests (pgTAP) — run by CI via
-- `supabase test db` (workflow: supabase-migrations.yml).
--
-- Covers migrations 20260913130000 (enum value) + 20260913140000
-- (deposit columns / proofs table / RPCs):
--   1. Happy path: approve → awaiting_deposit → submit proof →
--      seller confirm → approved(reserved), stock drawn largest-first.
--   2. Deposit deadline passes unpaid → sweep expires it; NO stock moved.
--   3. Pay (submit/confirm) after the deadline → DEPOSIT_DEADLINE_PASSED.
--   4. Cancel while awaiting_deposit → terminal, no stock release, no
--      forfeiture (deposit stays 'unpaid').
--   5. Cancel while reserved (post-payment) → stock released,
--      deposit_status = 'forfeited'.
--   6. Concurrent confirms on the same row → exactly one wins, the
--      other gets ALREADY_RESOLVED (FOR UPDATE serialization).
--   7. Stock bought by someone else between approval and payment →
--      confirm raises INSUFFICIENT_STOCK_MISSING_n and the row does NOT
--      silently become reserved.
--   8. reserved_stock_for_product ignores awaiting_deposit rows.
-- ══════════════════════════════════════════════════════════════════

begin;
select plan(51);

-- ── clear any JWT context ─────────────────────────────────────────
select set_config('request.jwt.claims', '{"sub":null,"role":null}', true);

-- ── fixtures (as postgres; RLS bypassed) ──────────────────────────
insert into auth.users (instance_id, id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', 'a0000000-0000-0000-0000-00000000000a', 'authenticated', 'authenticated', 'dep-customer@test.local', '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'a0000000-0000-0000-0000-00000000000b', 'authenticated', 'authenticated', 'dep-customer2@test.local', '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'a0000000-0000-0000-0000-00000000000c', 'authenticated', 'authenticated', 'dep-seller@test.local', '{}', '{}', now(), now());

insert into public.profiles (id, full_name, email, role, seller_status)
values
  ('a0000000-0000-0000-0000-00000000000a', 'Dep Customer',  'dep-customer@test.local',  'customer', 'none'),
  ('a0000000-0000-0000-0000-00000000000b', 'Dep Customer 2','dep-customer2@test.local', 'customer', 'none'),
  ('a0000000-0000-0000-0000-00000000000c', 'Dep Seller',    'dep-seller@test.local',    'seller',   'approved');

insert into public.stores (id, name, location, owner_id)
values ('a0000000-0000-0000-0000-00000000000e', 'Dep Store', 'Manila', 'a0000000-0000-0000-0000-00000000000c');

insert into public.products (id, store_id, seller_id, name, price, is_active)
values ('a0000000-0000-0000-0000-00000000aaa1', 'a0000000-0000-0000-0000-00000000000e',
        'a0000000-0000-0000-0000-00000000000c', 'Dep Product', 100.00, true);

-- Sizes: 42 has the most stock (drawn first), 41 mid, 40 least.
insert into public.inventory (product_id, size, stock) values
  ('a0000000-0000-0000-0000-00000000aaa1', '40', 5),
  ('a0000000-0000-0000-0000-00000000aaa1', '41', 10),
  ('a0000000-0000-0000-0000-00000000aaa1', '42', 20);

-- ── structural checks ─────────────────────────────────────────────
select is(
  exists (select 1 from pg_enum e join pg_type t on t.oid = e.enumtypid
          where t.typname = 'bulk_reservation_status' and e.enumlabel = 'awaiting_deposit'),
  true, '1: enum value awaiting_deposit exists');

select is(
  (select count(*) from information_schema.columns
    where table_name = 'bulk_reservations'
      and column_name in ('deposit_amount','deposit_status','deposit_deadline','deposit_paid_at','deposit_proof_id')),
  5::bigint, '2: all five deposit columns exist on bulk_reservations');

select is(
  has_function_privilege('authenticated', 'public.submit_bulk_reservation_deposit_proof(uuid,text,text)', 'EXECUTE'),
  true, '3: submit proof granted to authenticated');
select is(
  has_function_privilege('authenticated', 'public.confirm_bulk_reservation_deposit(uuid)', 'EXECUTE'),
  true, '4: confirm deposit granted to authenticated');
select is(
  has_function_privilege('anon', 'public.submit_bulk_reservation_deposit_proof(uuid,text,text)', 'EXECUTE'),
  false, '5: submit proof revoked from anon');
select is(
  (select count(*) from pg_policy
    where polrelid = 'public.bulk_reservations'::regclass and polcmd = 'UPDATE'),
  0::bigint, '6: still NO UPDATE policy on bulk_reservations (RPC-only writes)');

-- ══ 1. HAPPY PATH ═════════════════════════════════════════════════
-- Seller approves a 10-unit, 7-day hold.
select set_config('request.jwt.claims',
  '{"sub":"a0000000-0000-0000-0000-00000000000c","role":"authenticated"}', true);
select lives_ok(
  $sql$ select public.decide_bulk_reservation(
    public.request_bulk_reservation(
      'a0000000-0000-0000-0000-00000000aaa1', 'a0000000-0000-0000-0000-00000000000e', 10,
      '[{"size":"42","quantity":10}]'::jsonb, null),
    true, 7, null) $sql$,
  '7: seller approves the request');

select is(
  (select status from public.bulk_reservations
    where product_id = 'a0000000-0000-0000-0000-00000000aaa1'),
  'awaiting_deposit', '8: status is awaiting_deposit after approve');
select is(
  (select deposit_status from public.bulk_reservations
    where product_id = 'a0000000-0000-0000-0000-00000000aaa1'),
  'unpaid', '9: deposit_status unpaid after approve');
select is(
  (select deposit_amount from public.bulk_reservations
    where product_id = 'a0000000-0000-0000-0000-00000000aaa1'),
  200.00::numeric, '10: deposit = ceil(20% of 10 × ₱100) = ₱200');
select is(
  (select reserved_stock from public.bulk_reservations
    where product_id = 'a0000000-0000-0000-0000-00000000aaa1'),
  0, '11: approval drew NO stock (reserved_stock still 0)');
select is(
  (select sum(stock) from public.inventory
    where product_id = 'a0000000-0000-0000-0000-00000000aaa1'),
  35::bigint, '12: inventory untouched at approval (35 units)');
select ok(
  (select deposit_deadline > now() + interval '23 hours'
     and deposit_deadline <= now() + interval '24 hours 1 minute'
   from public.bulk_reservations
   where product_id = 'a0000000-0000-0000-0000-00000000aaa1'),
  '13: deposit deadline ≈ 24h from approval');

-- Customer submits proof; seller confirms → stock drawn, largest first.
select set_config('request.jwt.claims',
  '{"sub":"a0000000-0000-0000-0000-00000000000a","role":"authenticated"}', true);
select lives_ok(
  $sql$ select public.submit_bulk_reservation_deposit_proof(
    (select id from public.bulk_reservations
      where product_id = 'a0000000-0000-0000-0000-00000000aaa1'),
    '1234567890123', (select id::text from public.bulk_reservations
      where product_id = 'a0000000-0000-0000-0000-00000000aaa1') || '/shot.jpg') $sql$,
  '14: customer submits deposit proof');

select set_config('request.jwt.claims',
  '{"sub":"a0000000-0000-0000-0000-00000000000c","role":"authenticated"}', true);
select lives_ok(
  $sql$ select public.confirm_bulk_reservation_deposit(
    (select id from public.bulk_reservations
      where product_id = 'a0000000-0000-0000-0000-00000000aaa1')) $sql$,
  '15: seller confirms the deposit');

select is(
  (select status from public.bulk_reservations
    where product_id = 'a0000000-0000-0000-0000-00000000aaa1'),
  'approved', '16: status approved (reserved) after confirm');
select is(
  (select deposit_status from public.bulk_reservations
    where product_id = 'a0000000-0000-0000-0000-00000000aaa1'),
  'paid', '17: deposit_status paid');
select is(
  (select reserved_stock from public.bulk_reservations
    where product_id = 'a0000000-0000-0000-0000-00000000aaa1'),
  10, '18: reserved_stock = 10');
-- Largest-first: 42: 20-10=10, 41: 10, 40: 5.
select is(
  (select (array_agg(stock order by size) from public.inventory
    where product_id = 'a0000000-0000-0000-0000-00000000aaa1')),
  ARRAY[5,10,10], '19: stock drawn largest-size-first (40,41,42 → 5,10,10)');
select ok(
  (select deposit_paid_at is not null and reserved_at is not null
   from public.bulk_reservations
   where product_id = 'a0000000-0000-0000-0000-00000000aaa1'),
  '20: deposit_paid_at and reserved_at stamped');
select is(
  (select deposit_proof_id is not null from public.bulk_reservations
    where product_id = 'a0000000-0000-0000-0000-00000000aaa1'),
  true, '21: accepted proof linked via deposit_proof_id');

-- Platform-wide reference dedupe: same ref on a different deposit → rejected.
select set_config('request.jwt.claims',
  '{"sub":"a0000000-0000-0000-0000-00000000000b","role":"authenticated"}', true);
select lives_ok(
  $sql$ select public.request_bulk_reservation(
    'a0000000-0000-0000-0000-00000000aaa1', 'a0000000-0000-0000-0000-00000000000e', 1,
    '[]'::jsonb, null) $sql$,
  '22: second customer can request (first is now approved, not pending)');
select set_config('request.jwt.claims',
  '{"sub":"a0000000-0000-0000-0000-00000000000c","role":"authenticated"}', true);
select lives_ok(
  $sql$ select public.decide_bulk_reservation(
    (select id from public.bulk_reservations
      where customer_id = 'a0000000-0000-0000-0000-00000000000b'),
    true, 3, null) $sql$,
  '23: seller approves second request');
select set_config('request.jwt.claims',
  '{"sub":"a0000000-0000-0000-0000-00000000000b","role":"authenticated"}', true);
select throws_ok(
  $sql$ select public.submit_bulk_reservation_deposit_proof(
    (select id from public.bulk_reservations
      where customer_id = 'a0000000-0000-0000-0000-00000000000b'),
    '1234567890123', (select id::text from public.bulk_reservations
      where customer_id = 'a0000000-0000-0000-0000-00000000000b') || '/shot.jpg') $sql$,
  'REFERENCE_ALREADY_USED', null,
  '24: an order- or deposit-used reference cannot confirm a second deposit');

-- ══ 5. CANCEL POST-PAYMENT → FORFEIT ══════════════════════════════
select lives_ok(
  $sql$ select public.cancel_bulk_reservation(
    (select id from public.bulk_reservations
      where product_id = 'a0000000-0000-0000-0000-00000000aaa1')) $sql$,
  '25: customer cancels the paid (reserved) hold');
select is(
  (select status from public.bulk_reservations
    where id = (select id from public.bulk_reservations
                where customer_id = 'a0000000-0000-0000-0000-00000000000a'
                order by created_at limit 1)),
  'cancelled', '26: status cancelled');
select is(
  (select deposit_status from public.bulk_reservations
    where id = (select id from public.bulk_reservations
                where customer_id = 'a0000000-0000-0000-0000-00000000000a'
                order by created_at limit 1)),
  'forfeited', '27: paid deposit FORFEITED on cancel');
select is(
  (select sum(stock) from public.inventory
    where product_id = 'a0000000-0000-0000-0000-00000000aaa1'),
  35::bigint, '28: stock restored exactly (5,10,10 → sum 35)');

-- ══ 4. CANCEL WHILE AWAITING_DEPOSIT → no forfeiture ══════════════
select lives_ok(
  $sql$ select public.cancel_bulk_reservation(
    (select id from public.bulk_reservations
      where customer_id = 'a0000000-0000-0000-0000-00000000000b')) $sql$,
  '29: customer cancels while awaiting_deposit');
select is(
  (select deposit_status from public.bulk_reservations
    where customer_id = 'a0000000-0000-0000-0000-00000000000b'),
  'unpaid', '30: deposit untouched (unpaid — nothing was ever paid)');

-- ══ 2 + 3. DEADLINE: pay-after-deadline rejected; sweep expires ═══
-- Fresh request, approved, then force the deadline into the past.
select set_config('request.jwt.claims',
  '{"sub":"a0000000-0000-0000-0000-00000000000a","role":"authenticated"}', true);
select lives_ok(
  $sql$ select public.request_bulk_reservation(
    'a0000000-0000-0000-0000-00000000aaa1', 'a0000000-0000-0000-0000-00000000000e', 2,
    '[]'::jsonb, null) $sql$,
  '31: third request placed');
select set_config('request.jwt.claims',
  '{"sub":"a0000000-0000-0000-0000-00000000000c","role":"authenticated"}', true);
select lives_ok(
  $sql$ select public.decide_bulk_reservation(
    (select id from public.bulk_reservations
      where customer_id = 'a0000000-0000-0000-0000-00000000000a'
        and status = 'pending'),
    true, 7, null) $sql$,
  '32: seller approves third request');
update public.bulk_reservations
   set deposit_deadline = now() - interval '1 hour'
 where customer_id = 'a0000000-0000-0000-0000-00000000000a'
   and status = 'awaiting_deposit';

select set_config('request.jwt.claims',
  '{"sub":"a0000000-0000-0000-0000-00000000000a","role":"authenticated"}', true);
select throws_ok(
  $sql$ select public.submit_bulk_reservation_deposit_proof(
    (select id from public.bulk_reservations
      where customer_id = 'a0000000-0000-0000-0000-00000000000a'
        and status = 'awaiting_deposit'),
    '9999999999999', (select id::text from public.bulk_reservations
      where customer_id = 'a0000000-0000-0000-0000-00000000000a'
        and status = 'awaiting_deposit') || '/late.jpg') $sql$,
  'DEPOSIT_DEADLINE_PASSED', null,
  '33: proof submission after the deadline → DEPOSIT_DEADLINE_PASSED');
select set_config('request.jwt.claims',
  '{"sub":"a0000000-0000-0000-0000-00000000000c","role":"authenticated"}', true);
select throws_ok(
  $sql$ select public.confirm_bulk_reservation_deposit(
    (select id from public.bulk_reservations
      where customer_id = 'a0000000-0000-0000-0000-00000000000a'
        and status = 'awaiting_deposit')) $sql$,
  'DEPOSIT_DEADLINE_PASSED', null,
  '34: confirm after the deadline → DEPOSIT_DEADLINE_PASSED');

-- Sweep expires it; NO stock was ever drawn for it.
select is(
  (select public.expire_bulk_reservations()),
  1, '35: sweep expires the lapsed deposit window');
select is(
  (select status from public.bulk_reservations
    where id = (select id from public.bulk_reservations
                where customer_id = 'a0000000-0000-0000-0000-00000000000a'
                order by created_at desc limit 1)),
  'expired', '36: status expired after sweep');
select is(
  (select deposit_status from public.bulk_reservations
    where id = (select id from public.bulk_reservations
                where customer_id = 'a0000000-0000-0000-0000-00000000000a'
                order by created_at desc limit 1)),
  'unpaid', '37: unpaid deposit stays unpaid (nothing to forfeit)');
select is(
  (select sum(stock) from public.inventory
    where product_id = 'a0000000-0000-0000-0000-00000000aaa1'),
  35::bigint, '38: inventory unchanged by the deposit-window expiry');

-- ══ 6. CONCURRENT CONFIRMS → exactly one wins ═════════════════════
select set_config('request.jwt.claims',
  '{"sub":"a0000000-0000-0000-0000-00000000000a","role":"authenticated"}', true);
select lives_ok(
  $sql$ select public.request_bulk_reservation(
    'a0000000-0000-0000-0000-00000000aaa1', 'a0000000-0000-0000-0000-00000000000e', 3,
    '[]'::jsonb, null) $sql$,
  '39: request for the concurrency race');
select set_config('request.jwt.claims',
  '{"sub":"a0000000-0000-0000-0000-00000000000c","role":"authenticated"}', true);
select lives_ok(
  $sql$ select public.decide_bulk_reservation(
    (select id from public.bulk_reservations
      where customer_id = 'a0000000-0000-0000-0000-00000000000a'
        and status = 'pending'),
    true, 7, null) $sql$,
  '40: approved for the race');
select set_config('request.jwt.claims',
  '{"sub":"a0000000-0000-0000-0000-00000000000a","role":"authenticated"}', true);
select lives_ok(
  $sql$ select public.submit_bulk_reservation_deposit_proof(
    (select id from public.bulk_reservations
      where customer_id = 'a0000000-0000-0000-0000-00000000000a'
        and status = 'awaiting_deposit'),
    '8888888888888', (select id::text from public.bulk_reservations
      where customer_id = 'a0000000-0000-0000-0000-00000000000a'
        and status = 'awaiting_deposit') || '/race.jpg') $sql$,
  '41: proof submitted for the race');

-- Exactly-once serialization: the confirm re-checks status under FOR
-- UPDATE, so a second confirm — whether from a racing session that lost
-- the lock or any later call — sees the row already moved and raises
-- ALREADY_RESOLVED. (True multi-session lock racing isn't expressible in
-- single-session pgTAP; the guarded-status re-check IS the race control,
-- shared with the GCash RPCs it mirrors.)
select set_config('request.jwt.claims',
  '{"sub":"a0000000-0000-0000-0000-00000000000c","role":"authenticated"}', true);
select lives_ok(
  $sql$ select public.confirm_bulk_reservation_deposit(
    (select id from public.bulk_reservations
      where customer_id = 'a0000000-0000-0000-0000-00000000000a'
        and status = 'awaiting_deposit')) $sql$,
  '42: first confirm wins and flips the row');
select throws_ok(
  $sql$ select public.confirm_bulk_reservation_deposit(
    (select id from public.bulk_reservations
      where customer_id = 'a0000000-0000-0000-0000-00000000000a'
        and status = 'approved')) $sql$,
  'ALREADY_RESOLVED', null,
  '43: second confirm → ALREADY_RESOLVED (exactly-once holds)');
select is(
  (select reserved_stock from public.bulk_reservations
    where id = (select id from public.bulk_reservations
                where customer_id = 'a0000000-0000-0000-0000-00000000000a'
                  and status = 'approved'
                order by created_at limit 1)),
  3, '44: stock drawn exactly once (3)');

-- ══ 7. INSUFFICIENT STOCK AT PAYMENT TIME ═════════════════════════
select set_config('request.jwt.claims',
  '{"sub":"a0000000-0000-0000-0000-00000000000b","role":"authenticated"}', true);
select lives_ok(
  $sql$ select public.request_bulk_reservation(
    'a0000000-0000-0000-0000-00000000aaa1', 'a0000000-0000-0000-0000-00000000000e', 30,
    '[]'::jsonb, null) $sql$,
  '45: request for the stock-shrink case');
select set_config('request.jwt.claims',
  '{"sub":"a0000000-0000-0000-0000-00000000000c","role":"authenticated"}', true);
select lives_ok(
  $sql$ select public.decide_bulk_reservation(
    (select id from public.bulk_reservations
      where customer_id = 'a0000000-0000-0000-0000-00000000000b'
        and status = 'pending'),
    true, 7, null) $sql$,
  '46: approved the oversized request');
-- Someone else buys 4 units through another path while the deposit waits
-- (42 had 17 after A's 3-unit hold → 13; total 5+10+13 = 28).
update public.inventory set stock = stock - 4
 where product_id = 'a0000000-0000-0000-0000-00000000aaa1' and size = '42';
select set_config('request.jwt.claims',
  '{"sub":"a0000000-0000-0000-0000-00000000000b","role":"authenticated"}', true);
select lives_ok(
  $sql$ select public.submit_bulk_reservation_deposit_proof(
    (select id from public.bulk_reservations
      where customer_id = 'a0000000-0000-0000-0000-00000000000b'
        and status = 'awaiting_deposit'),
    '7777777777777', (select id::text from public.bulk_reservations
      where customer_id = 'a0000000-0000-0000-0000-00000000000b'
        and status = 'awaiting_deposit') || '/shrink.jpg') $sql$,
  '47: proof submitted for the shrunk-stock reservation');
select set_config('request.jwt.claims',
  '{"sub":"a0000000-0000-0000-0000-00000000000c","role":"authenticated"}', true);
select throws_ok(
  $sql$ select public.confirm_bulk_reservation_deposit(
    (select id from public.bulk_reservations
      where customer_id = 'a0000000-0000-0000-0000-00000000000b'
        and status = 'awaiting_deposit')) $sql$,
  'INSUFFICIENT_STOCK_MISSING_2', null,
  '48: confirm aborts loudly (INSUFFICIENT_STOCK_MISSING_2 — 30 requested, 28 left)');
select is(
  (select status from public.bulk_reservations
    where id = (select id from public.bulk_reservations
                where customer_id = 'a0000000-0000-0000-0000-00000000000b'
                  and status = 'awaiting_deposit'
                order by created_at limit 1)),
  'awaiting_deposit', '49: row does NOT silently become reserved');
-- The RPC's partial draw rolled back (throws_ok runs under a savepoint);
-- inventory shows only the real movements: 35 - 3 (A's paid hold) - 4.
select is(
  (select sum(stock) from public.inventory
    where product_id = 'a0000000-0000-0000-0000-00000000aaa1'),
  28::bigint, '50: failed draw rolled back (28 = 35 - 3 held - 4 bought)');

-- ══ 8. reserved_stock_for_product ignores awaiting_deposit ════════
select is(
  (select public.reserved_stock_for_product('a0000000-0000-0000-0000-00000000aaa1')),
  3, '51: only the paid hold counts (awaiting_deposit contributes 0)');

select * from finish();
rollback;
