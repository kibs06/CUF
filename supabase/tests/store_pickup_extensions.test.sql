-- ══════════════════════════════════════════════════════════════════
-- Store GOODWILL pickup extensions — pgTAP
-- Run by CI via `supabase test db` (supabase-migrations.yml)
--
-- Covers `20260916120000_add_store_pickup_extensions.sql`. The assertions that
-- matter most are marked ⚠️ — they are the difference between a store grant and
-- an unexplained deadline change:
--
--   ⚠️ a grant is RECORDED: exactly one audit row, naming the actor, the
--      customer, the store, the reason, and the before/after deadlines. A
--      deadline the store cannot explain is what this feature exists to prevent.
--   ⚠️ a grant is BOUNDED: the store's own budget is separate from the
--      customer's, both are table CHECKs, and the total ceiling is their sum
--      (72 h) — a grant cannot push a hold past it even by direct UPDATE.
--   ⚠️ a grant is EXPLICIT: no reason, no grant; and only the store that owns
--      the hold may give one (not another seller, not the customer, not an admin
--      acting silently).
--   ⚠️ the customer is TOLD, with the reason, and the new deadline gets its own
--      T-2h warning (the old stamp is cleared).
-- ══════════════════════════════════════════════════════════════════

begin;
select plan(60);

-- ── helpers ────────────────────────────────────────────────────────
create or replace function public.tmp_grant_claims(p_user uuid)
returns text language sql immutable as $$
  select json_build_object('sub', p_user, 'role', 'authenticated')::text;
$$;

create or replace function public.tmp_grant_stock(p_size text)
returns integer language sql stable as $$
  select stock from public.inventory
   where product_id = 'f0000000-0000-0000-0000-000000000007' and size = p_size;
$$;

create or replace function public.tmp_grant_notices(p_user uuid, p_title text)
returns integer language sql stable as $$
  select count(*)::int from public.notifications
   where user_id = p_user and title = p_title;
$$;

create or replace function public.tmp_grant_rows()
returns integer language sql stable as $$
  select count(*)::int from public.pickup_reservation_extension_grants;
$$;

select set_config('request.jwt.claims', '{"sub":null,"role":null}', true);
select set_config('request.headers', '{}', true);

-- ── fixtures ───────────────────────────────────────────────────────
insert into auth.users (instance_id, id, aud, role, email, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000','f0000000-0000-0000-0000-000000000001','authenticated','authenticated','g-seller-a@test.local', now(), now()),
  ('00000000-0000-0000-0000-000000000000','f0000000-0000-0000-0000-000000000002','authenticated','authenticated','g-cust@test.local',     now(), now()),
  ('00000000-0000-0000-0000-000000000000','f0000000-0000-0000-0000-000000000003','authenticated','authenticated','g-seller-b@test.local', now(), now()),
  ('00000000-0000-0000-0000-000000000000','f0000000-0000-0000-0000-000000000004','authenticated','authenticated','g-admin@test.local',    now(), now());

insert into public.profiles (id, full_name, email, role, seller_status)
values
  ('f0000000-0000-0000-0000-000000000001','G Seller A','g-seller-a@test.local','seller','approved'),
  ('f0000000-0000-0000-0000-000000000002','G Customer','g-cust@test.local','customer','none'),
  ('f0000000-0000-0000-0000-000000000003','G Seller B','g-seller-b@test.local','seller','approved'),
  ('f0000000-0000-0000-0000-000000000004','G Admin','g-admin@test.local','admin','none');

insert into public.stores (id, owner_id, name, location)
values ('f0000000-0000-0000-0000-000000000005','f0000000-0000-0000-0000-000000000001','G Store A','G City'),
       ('f0000000-0000-0000-0000-000000000006','f0000000-0000-0000-0000-000000000003','G Store B','G City');

insert into public.products (id, store_id, seller_id, name, price, category)
values ('f0000000-0000-0000-0000-000000000007','f0000000-0000-0000-0000-000000000005',
        'f0000000-0000-0000-0000-000000000001','G Shoe', 1000, 'General');

insert into public.inventory (product_id, size, stock)
values ('f0000000-0000-0000-0000-000000000007','40', 5),
       ('f0000000-0000-0000-0000-000000000007','41', 5),
       ('f0000000-0000-0000-0000-000000000007','42', 5);

-- ══ 1. Structure ═══════════════════════════════════════════════════
select has_function('public','grant_pickup_extension', array['uuid','text'],
                    '1: the store grant RPC exists');
select has_table('public','pickup_reservation_extension_grants',
                 '2: the audit table exists');

-- ⚠️ The trail must be the three audiences only, and read-only: a row here
-- records something that already happened, so the RPC is the only way in.
select is(
  (select count(*)::int from pg_policies
    where schemaname='public' and tablename='pickup_reservation_extension_grants'
      and cmd in ('INSERT','UPDATE','DELETE')),
  0,
  '3: no INSERT/UPDATE/DELETE policy exists on the trail'
);
select is(
  (select count(*)::int from pg_policies
    where schemaname='public' and tablename='pickup_reservation_extension_grants'
      and cmd = 'SELECT'),
  3,
  '4: exactly three SELECT audiences (customer, store owner, admin)'
);
select is(
  (select count(*)::int from pg_policies
    where schemaname='public' and tablename='pickup_reservation_extension_grants'
      and policyname='Require a trusted device'),
  1,
  '5: the trail is device-gated (the migration called install_device_gate_policies)'
);
select ok(
  not ('pickup_reservation_extension_grants' = any (public.device_gate_exempt_tables())),
  '6: …and it is NOT in the exemption list'
);

-- The budgets, and the ceiling that sums them.
select is(public.pickup_reservation_hold_hours(), 24,
          '7: the base window is 24 hours');
select is(public.pickup_reservation_max_extensions(), 1,
          '8: the customer may extend once');
select is(public.pickup_reservation_max_store_extensions(), 1,
          '9: the store may grant once — its own budget, not the customer''s');
select is(public.pickup_reservation_store_extension_hours(), 24,
          '10: a grant buys one ordinary window');
select is(public.pickup_reservation_max_window_hours(), 72,
          '11: the ceiling is the SUM of every budget (24 × 3)');
select ok(
  exists (select 1 from pg_constraint
           where conname = 'pickup_reservations_within_store_extension_cap'
             and conrelid = 'public.pickup_reservations'::regclass),
  '12: the store count is itself CHECKed against its cap'
);

-- ══ 2. A grant is recorded, explained, and bounded ═════════════════
select set_config('request.jwt.claims',
  public.tmp_grant_claims('f0000000-0000-0000-0000-000000000002'), true);
select lives_ok(
  $$select public.request_pickup_reservation('f0000000-0000-0000-0000-000000000007','40',2)$$,
  '13: the customer holds 2 pairs of size 40'
);
select is(public.tmp_grant_stock('40'), 3,
          '14: (the hold drew them out of stock: 5 → 3)');

-- Pretend the T-2h reminder already went out for the deadline we are about to
-- move, so the re-arming below is observable.
update public.pickup_reservations
   set reminder_sent_at = timezone('utc'::text, now())
 where customer_id = 'f0000000-0000-0000-0000-000000000002' and size = '40';

select is(public.tmp_grant_rows(), 0, '15: no grants have been recorded yet');

select set_config('request.jwt.claims',
  public.tmp_grant_claims('f0000000-0000-0000-0000-000000000001'), true);
select lives_ok(
  $$select public.grant_pickup_extension(
      (select id from public.pickup_reservations
        where customer_id='f0000000-0000-0000-0000-000000000002' and size='40'),
      '  Customer stuck in traffic, told them we would hold it  ')$$,
  '16: the store owner grants 24 more hours, with a reason'
);

select is(
  (select store_extension_count from public.pickup_reservations
    where customer_id='f0000000-0000-0000-0000-000000000002' and size='40'),
  1,
  '17: the grant is counted on the row'
);
-- ⚠️ Independent budgets: a favour from the store must not consume the
-- customer's own allowance (nor the reverse).
select is(
  (select extension_count from public.pickup_reservations
    where customer_id='f0000000-0000-0000-0000-000000000002' and size='40'),
  0,
  '18: …and the CUSTOMER''s own budget is untouched by it'
);
select is(
  (select round(extract(epoch from (pickup_deadline - created_at))/3600)::int
     from public.pickup_reservations
    where customer_id='f0000000-0000-0000-0000-000000000002' and size='40'),
  48,
  '19: the window is now 48 hours (base + the grant)'
);
select is(
  (select status::text from public.pickup_reservations
    where customer_id='f0000000-0000-0000-0000-000000000002' and size='40'),
  'active',
  '20: the hold is still simply active'
);
-- ⚠️ More time is not more stock: the units left the shelf when the hold was
-- created, and a grant only moves the deadline.
select is(public.tmp_grant_stock('40'), 3,
          '21: granting moves no stock');

-- ⚠️ THE TRAIL. One row, and it explains the new deadline on its own.
select is(public.tmp_grant_rows(), 1, '22: exactly one grant was recorded');
select is(
  (select granted_by from public.pickup_reservation_extension_grants
    where reservation_id = (select id from public.pickup_reservations
                             where customer_id='f0000000-0000-0000-0000-000000000002'
                               and size='40')),
  'f0000000-0000-0000-0000-000000000001'::uuid,
  '23: the trail names the seller who granted it'
);
select is(
  (select customer_id from public.pickup_reservation_extension_grants
    where reservation_id = (select id from public.pickup_reservations
                             where customer_id='f0000000-0000-0000-0000-000000000002'
                               and size='40')),
  'f0000000-0000-0000-0000-000000000002'::uuid,
  '24: …and the customer it was granted for'
);
select is(
  (select store_id from public.pickup_reservation_extension_grants
    where reservation_id = (select id from public.pickup_reservations
                             where customer_id='f0000000-0000-0000-0000-000000000002'
                               and size='40')),
  'f0000000-0000-0000-0000-000000000005'::uuid,
  '25: …and the store that gave it'
);
select is(
  (select reason from public.pickup_reservation_extension_grants
    where reservation_id = (select id from public.pickup_reservations
                             where customer_id='f0000000-0000-0000-0000-000000000002'
                               and size='40')),
  'Customer stuck in traffic, told them we would hold it',
  '26: the reason is stored as given, with only the edges trimmed'
);
select is(
  (select hours_granted from public.pickup_reservation_extension_grants
    where reservation_id = (select id from public.pickup_reservations
                             where customer_id='f0000000-0000-0000-0000-000000000002'
                               and size='40')),
  24,
  '27: and how many hours were given'
);
select is(
  (select round(extract(epoch from (new_deadline - previous_deadline))/3600)::int
     from public.pickup_reservation_extension_grants
    where reservation_id = (select id from public.pickup_reservations
                             where customer_id='f0000000-0000-0000-0000-000000000002'
                               and size='40')),
  24,
  '28: the before/after pair records the exact move'
);
select is(
  (select previous_deadline from public.pickup_reservation_extension_grants
    where reservation_id = (select id from public.pickup_reservations
                             where customer_id='f0000000-0000-0000-0000-000000000002'
                               and size='40')),
  (select created_at + interval '24 hours' from public.pickup_reservations
    where customer_id='f0000000-0000-0000-0000-000000000002' and size='40'),
  '29: …and the "before" is the deadline the customer originally had'
);

-- ⚠️ The new deadline is owed its own warning.
select ok(
  (select reminder_sent_at is null from public.pickup_reservations
    where customer_id='f0000000-0000-0000-0000-000000000002' and size='40'),
  '30: the old T-2h stamp is CLEARED, so the new deadline can be warned about'
);
select is(public.tmp_grant_notices(
            'f0000000-0000-0000-0000-000000000002','The store extended your pickup hold'), 1,
          '31: the customer is told the store extended it');
select ok(
  (select message like '%Customer stuck in traffic%' from public.notifications
    where user_id='f0000000-0000-0000-0000-000000000002'
      and title='The store extended your pickup hold'),
  '32: …and told WHY — an unexplained later deadline reads like a glitch'
);
select is(public.tmp_grant_notices(
            'f0000000-0000-0000-0000-000000000001','The store extended your pickup hold'), 0,
          '33: the store is not notified about its own grant');

-- ⚠️ Only once. The second attempt must fail, and must NOT add a trail row.
select throws_ok(
  $$select public.grant_pickup_extension(
      (select id from public.pickup_reservations
        where customer_id='f0000000-0000-0000-0000-000000000002' and size='40'),
      'They asked again')$$,
  'P0001',
  'STORE_EXTENSION_LIMIT_REACHED (1) — this hold already had a goodwill extension',
  '34: a second goodwill grant on the same hold is refused, and says why'
);
select is(public.tmp_grant_rows(), 1,
          '35: …and the refused attempt left no trail row behind');

-- ⚠️ …and the store's budget holds even for code that bypasses the RPC.
select throws_ok(
  $$update public.pickup_reservations
       set store_extension_count = 2
     where customer_id='f0000000-0000-0000-0000-000000000002' and size='40'$$,
  '23514', null,
  '36: a direct UPDATE past the store cap is refused by the CHECK'
);

-- ⚠️ An unexplained grant cannot be inserted by ANY path: the reason is part of
-- the table''s shape, not only of the RPC.
select throws_ok(
  $$insert into public.pickup_reservation_extension_grants
      (reservation_id, customer_id, store_id, granted_by,
       previous_deadline, new_deadline, hours_granted, reason)
    values ((select id from public.pickup_reservations
              where customer_id='f0000000-0000-0000-0000-000000000002' and size='40'),
            'f0000000-0000-0000-0000-000000000002','f0000000-0000-0000-0000-000000000005',
            'f0000000-0000-0000-0000-000000000001',
            now(), now() + interval '1 hour', 1, '  ')$$,
  '23514', null,
  '37: an audit row with a blank reason is impossible'
);

-- ══ 3. A grant is explicit — rules on WHO and WHEN ═════════════════
-- A fresh hold, so the failures below are about the rule under test rather than
-- about a budget already spent.
select set_config('request.jwt.claims',
  public.tmp_grant_claims('f0000000-0000-0000-0000-000000000002'), true);
select lives_ok(
  $$select public.request_pickup_reservation('f0000000-0000-0000-0000-000000000007','41',1)$$,
  '38: a second, untouched hold to test the grant rules against'
);

select set_config('request.jwt.claims',
  public.tmp_grant_claims('f0000000-0000-0000-0000-000000000001'), true);
select throws_ok(
  $$select public.grant_pickup_extension(
      (select id from public.pickup_reservations
        where customer_id='f0000000-0000-0000-0000-000000000002' and size='41'), '')$$,
  'P0001', 'INVALID_REASON — a goodwill extension needs a short reason (3-280 characters)',
  '39: no reason, no grant'
);
select throws_ok(
  $$select public.grant_pickup_extension(
      (select id from public.pickup_reservations
        where customer_id='f0000000-0000-0000-0000-000000000002' and size='41'), 'ok')$$,
  'P0001', 'INVALID_REASON — a goodwill extension needs a short reason (3-280 characters)',
  '40: a two-character reason is not a reason'
);
select throws_ok(
  $$select public.grant_pickup_extension(
      (select id from public.pickup_reservations
        where customer_id='f0000000-0000-0000-0000-000000000002' and size='41'),
      repeat('x', 281))$$,
  'P0001', 'INVALID_REASON — a goodwill extension needs a short reason (3-280 characters)',
  '41: …and an essay is capped too (the CHECK enforces the same 280)'
);
select is(public.tmp_grant_rows(), 1,
          '42: none of those attempts recorded anything');
select is(
  (select store_extension_count from public.pickup_reservations
    where customer_id='f0000000-0000-0000-0000-000000000002' and size='41'),
  0,
  '43: …or moved the deadline'
);

-- ⚠️ Not another seller's hold — being a seller is not enough.
select set_config('request.jwt.claims',
  public.tmp_grant_claims('f0000000-0000-0000-0000-000000000003'), true);
select throws_ok(
  $$select public.grant_pickup_extension(
      (select id from public.pickup_reservations
        where customer_id='f0000000-0000-0000-0000-000000000002' and size='41'),
      'Not my store, but I am feeling generous')$$,
  'P0001', 'FORBIDDEN',
  '44: another store owner cannot grant on this hold'
);

-- ⚠️ …nor the customer approving their own favour…
select set_config('request.jwt.claims',
  public.tmp_grant_claims('f0000000-0000-0000-0000-000000000002'), true);
select throws_ok(
  $$select public.grant_pickup_extension(
      (select id from public.pickup_reservations
        where customer_id='f0000000-0000-0000-0000-000000000002' and size='41'),
      'I would like to grant myself more time')$$,
  'P0001', 'FORBIDDEN',
  '45: the customer cannot grant themselves a goodwill extension'
);

-- ⚠️ …nor an admin doing it silently: support changes go through the same
-- visible, reasoned, recorded path as the store's own.
select set_config('request.jwt.claims',
  public.tmp_grant_claims('f0000000-0000-0000-0000-000000000004'), true);
select throws_ok(
  $$select public.grant_pickup_extension(
      (select id from public.pickup_reservations
        where customer_id='f0000000-0000-0000-0000-000000000002' and size='41'),
      'Support decided to be nice')$$,
  'P0001', 'FORBIDDEN',
  '46: an admin is refused too — no silent support grants'
);

-- ⚠️ The absolute ceiling still holds: after the customer uses their own
-- extension AND the store grants, the window is exactly 72 h — and no more.
select set_config('request.jwt.claims',
  public.tmp_grant_claims('f0000000-0000-0000-0000-000000000002'), true);
select lives_ok(
  $$select public.extend_pickup_reservation(
      (select id from public.pickup_reservations
        where customer_id='f0000000-0000-0000-0000-000000000002' and size='41'))$$,
  '47: the customer adds their own 24 hours (24 → 48)'
);

select set_config('request.jwt.claims',
  public.tmp_grant_claims('f0000000-0000-0000-0000-000000000001'), true);
select lives_ok(
  $$select public.grant_pickup_extension(
      (select id from public.pickup_reservations
        where customer_id='f0000000-0000-0000-0000-000000000002' and size='41'),
      'Customer asked for one more day')$$,
  '48: and the store tops it up, on top of the customer''s own extension'
);
select is(
  (select round(extract(epoch from (pickup_deadline - created_at))/3600)::int
     from public.pickup_reservations
    where customer_id='f0000000-0000-0000-0000-000000000002' and size='41'),
  72,
  '49: the window is now exactly 72 hours — every budget spent, no more'
);
select is(public.tmp_grant_rows(), 2,
          '50: each hold has its own trail row (grants are per hold, not per customer)');
-- ⚠️ The ceiling is a CHECK on the SUM, so no path can exceed it even after a
-- grant: 73 hours is refused, 72 is still accepted.
select throws_ok(
  $$update public.pickup_reservations
       set pickup_deadline = created_at + interval '73 hours'
     where customer_id='f0000000-0000-0000-0000-000000000002' and size='41'$$,
  '23514', null,
  '51: a direct UPDATE one hour past the ceiling is refused by the CHECK'
);
select lives_ok(
  $$update public.pickup_reservations
       set pickup_deadline = created_at + interval '72 hours'
     where customer_id='f0000000-0000-0000-0000-000000000002' and size='41'$$,
  '52: …while exactly the ceiling is still accepted (the bound is inclusive)'
);
-- ⚠️ The reason is checked BEFORE the budget, so a store that already gave one
-- is told about the missing reason rather than being told it has run out — the
-- distinction matters when a seller is on the phone with the customer.
select throws_ok(
  $$select public.grant_pickup_extension(
      (select id from public.pickup_reservations
        where customer_id='f0000000-0000-0000-0000-000000000002' and size='40'), '')$$,
  'P0001', 'INVALID_REASON — a goodwill extension needs a short reason (3-280 characters)',
  '53: on a hold whose budget is spent, the missing reason is still what is reported'
);

-- ══ 4. A grant is live-only ════════════════════════════════════════
-- The two WHO rules are above; these two are the WHEN rules, on a third hold so
-- a spent budget cannot be what the failure is about.
select set_config('request.jwt.claims',
  public.tmp_grant_claims('f0000000-0000-0000-0000-000000000002'), true);
select lives_ok(
  $$select public.request_pickup_reservation('f0000000-0000-0000-0000-000000000007','42',1)$$,
  '54: a third hold to test the WHEN rules against'
);

-- ⚠️ ONCE THE DEADLINE HAS PASSED the hold may lapse at any moment (the sweep
-- just has not run yet), so granting more time would promise stock nobody can
-- guarantee — the same rule the customer path carries. The deadline is
-- backdated directly because the window CHECK bounds only the top.
select lives_ok(
  $$update public.pickup_reservations
       set pickup_deadline = timezone('utc', now()) - interval '1 hour'
     where customer_id='f0000000-0000-0000-0000-000000000002' and size='42'$$,
  '55: the hold''s deadline moves into the past (the CHECK bounds only the top)'
);
select set_config('request.jwt.claims',
  public.tmp_grant_claims('f0000000-0000-0000-0000-000000000001'), true);
select throws_ok(
  $$select public.grant_pickup_extension(
      (select id from public.pickup_reservations
        where customer_id='f0000000-0000-0000-0000-000000000002' and size='42'),
      'They are definitely on the way')$$,
  'P0001',
  'HOLD_LAPSED — this hold has already run out; ask the customer to reserve again',
  '56: a lapsed hold cannot be granted more time'
);
select is(public.tmp_grant_rows(), 2,
          '57: …and the lapsed attempt recorded nothing');

-- ⚠️ …and a RESOLVED hold has nothing left to extend, whatever the status.
-- Cancelled by the customer here, then the store tries anyway.
select set_config('request.jwt.claims',
  public.tmp_grant_claims('f0000000-0000-0000-0000-000000000002'), true);
select lives_ok(
  $$select public.cancel_pickup_reservation(
      (select id from public.pickup_reservations
        where customer_id='f0000000-0000-0000-0000-000000000002' and size='42'))$$,
  '58: the customer cancels the backdated hold'
);
select set_config('request.jwt.claims',
  public.tmp_grant_claims('f0000000-0000-0000-0000-000000000001'), true);
select throws_ok(
  $$select public.grant_pickup_extension(
      (select id from public.pickup_reservations
        where customer_id='f0000000-0000-0000-0000-000000000002' and size='42'),
      'Give them one more day anyway')$$,
  'P0001', 'ALREADY_RESOLVED',
  '59: a cancelled hold cannot be extended by the store either'
);

-- ⚠️ THE FK THE CUSTOMER'S HISTORY READS THROUGH. The app's history query does
-- not join by hand — it embeds the hold (`pickup_reservations(size,
-- products(name, stores(name)))`) and lets PostgREST resolve it, which only works
-- because `reservation_id` is a FOREIGN KEY. Without that constraint the entire
-- query is a 400, so the feature would be dead rather than degraded, and nothing
-- else in the suite would notice.
select is(
  (select count(*)::int
     from pg_constraint c
     join pg_class t on t.oid = c.conrelid
    where c.contype = 'f'
      and t.relname = 'pickup_reservation_extension_grants'
      and pg_get_constraintdef(c.oid) like
          '%REFERENCES pickup_reservations(id)%'),
  1,
  '60: the trail FKs the hold, so the app can embed it (the customer history)'
);

select * from finish();
rollback;
