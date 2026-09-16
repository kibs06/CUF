-- ══════════════════════════════════════════════════════════════════
-- Pickup codes — pgTAP
-- Run by CI via `supabase test db` (workflow: supabase-migrations.yml)
--
-- Covers `20260916140000_add_pickup_codes.sql` (+ the `pickup_code` column,
-- CHECK and unique index in §3 of `20260915170000`).
--
-- The assertions that matter most are marked ⚠️:
--
--   ⚠️ A code is NOT a secret, but resolving one IS scoped to the store that
--      owns the hold. Without that scoping any seller could enumerate codes and
--      read another store's holds — who is holding what, and when they are
--      coming to collect it.
--   ⚠️ A wrong code never normalises into a right one. Normalisation fixes case
--      and separators only; it must not "helpfully" turn an O into a zero.
--   ⚠️ Fulfil-by-code is a resolver plus a DELEGATION. If it ever grows its own
--      copy of the fulfilment rules, the two will drift, so the rules the
--      delegate enforces are re-asserted here through the code path.
-- ══════════════════════════════════════════════════════════════════

begin;
select plan(45);

-- ── helpers ────────────────────────────────────────────────────────
create or replace function public.tmp_code_claims(p_user uuid)
returns text language sql immutable as $$
  select case when p_user is null then '{"sub":null,"role":null}'
              else json_build_object('sub', p_user, 'role', 'authenticated')::text
         end;
$$;

create or replace function public.tmp_code_stock(p_product uuid, p_size text)
returns integer language sql stable as $$
  select COALESCE(sum(stock), 0)::int from public.inventory
   where product_id = p_product and size = p_size;
$$;

-- The hold the customer places through the RPC at assertion 30. Named rather
-- than re-derived at each use, because the fixture ALSO holds two hand-inserted
-- holds for the same customer and product (sizes 42 and 43, deliberately, so the
-- one-active-hold index stays out of the way) — so a filter of
-- customer+product+active matches three rows, and a scalar subquery over it
-- raises "more than one row returned". Pinning the size here is what makes every
-- later assertion about ONE hold.
create or replace function public.tmp_code_hold_40()
returns uuid language sql stable as $$
  select id from public.pickup_reservations
   where customer_id = 'e0000000-0000-0000-0000-000000000002'
     and product_id = 'e0000000-0000-0000-0000-000000000007'
     and size = '40'
   limit 1;
$$;

-- Before the collection this is the same row; afterwards the hold is 'fulfilled'
-- and only this one still identifies it.
create or replace function public.tmp_code_active_hold()
returns uuid language sql stable as $$
  select id from public.pickup_reservations
   where id = public.tmp_code_hold_40() and status = 'active';
$$;

create or replace function public.tmp_code_hold_code()
returns text language sql stable as $$
  select pickup_code from public.pickup_reservations
   where id = public.tmp_code_hold_40();
$$;

create or replace function public.tmp_code_active_code()
returns text language sql stable as $$
  select pickup_code from public.pickup_reservations
   where id = public.tmp_code_active_hold();
$$;

select set_config('request.jwt.claims', '{"sub":null,"role":null}', true);

-- ── fixtures ───────────────────────────────────────────────────────
insert into auth.users (instance_id, id, aud, role, email, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000','e0000000-0000-0000-0000-000000000001','authenticated','authenticated','code-seller-a@test.local', now(), now()),
  ('00000000-0000-0000-0000-000000000000','e0000000-0000-0000-0000-000000000002','authenticated','authenticated','code-cust@test.local',     now(), now()),
  ('00000000-0000-0000-0000-000000000000','e0000000-0000-0000-0000-000000000003','authenticated','authenticated','code-seller-b@test.local', now(), now());

insert into public.profiles (id, full_name, email, role, seller_status)
values
  ('e0000000-0000-0000-0000-000000000001','C Seller A','code-seller-a@test.local','seller','approved'),
  ('e0000000-0000-0000-0000-000000000002','C Customer','code-cust@test.local','customer','none'),
  ('e0000000-0000-0000-0000-000000000003','C Seller B','code-seller-b@test.local','seller','approved');

insert into public.stores (id, owner_id, name, location)
values ('e0000000-0000-0000-0000-000000000005','e0000000-0000-0000-0000-000000000001','C Store A','C City'),
       ('e0000000-0000-0000-0000-000000000006','e0000000-0000-0000-0000-000000000003','C Store B','C City');

insert into public.products (id, store_id, seller_id, name, price, category)
values ('e0000000-0000-0000-0000-000000000007','e0000000-0000-0000-0000-000000000005',
        'e0000000-0000-0000-0000-000000000001','C Shoe A', 1000, 'General'),
       ('e0000000-0000-0000-0000-000000000008','e0000000-0000-0000-0000-000000000006',
        'e0000000-0000-0000-0000-000000000003','C Shoe B', 1000, 'General');

insert into public.inventory (product_id, size, stock)
values ('e0000000-0000-0000-0000-000000000007','40', 5),
       ('e0000000-0000-0000-0000-000000000008','40', 5);

-- ══ 1. Structure ═══════════════════════════════════════════════════
select has_column('public','pickup_reservations','pickup_code',
                  '1: the hold carries a pickup code');
select is(
  (select count(*)::int from pg_indexes
    where schemaname='public' and tablename='pickup_reservations'
      and indexname='uq_pickup_reservations_pickup_code'),
  1,
  '2: the code is unique across the whole table (a resolved hold still resolves)'
);
select ok(
  (select pg_get_indexdef(indexrelid) like '%UNIQUE%'
     from pg_index where indexrelid = 'public.uq_pickup_reservations_pickup_code'::regclass),
  '3: …and that index is actually UNIQUE'
);
select is(
  (select count(*)::int from pg_trigger
    where tgname='trg_pickup_reservations_assign_code'
      and tgrelid='public.pickup_reservations'::regclass and not tgisinternal),
  1,
  '4: assignment is a trigger, so EVERY insert path gets a code'
);
select has_function('public','generate_pickup_code', array[]::text[],
                    '5: the generator exists');
select has_function('public','find_pickup_reservation_by_code', array['text'],
                    '6: the resolver exists');
select has_function('public','fulfill_pickup_reservation_by_code', array['text','text'],
                    '7: the one-action fulfil exists');

-- ⚠️ The two entry points must not be reachable anonymously.
select is(
  has_function_privilege('anon','public.find_pickup_reservation_by_code(text)','EXECUTE'),
  false,
  '8: the resolver is not executable by anon'
);
select is(
  has_function_privilege('anon','public.fulfill_pickup_reservation_by_code(text,text)','EXECUTE'),
  false,
  '9: …nor is the fulfil-by-code'
);

-- ══ 2. The shape, as one definition ════════════════════════════════
select is(public.pickup_code_alphabet(), '23456789ABCDEFGHJKMNPQRSTVWXYZ',
          '10: the alphabet is the documented one');
select is(length(public.pickup_code_alphabet()), 30,
          '11: …of 30 symbols');
select is(public.pickup_code_length(), 6,
          '12: a code is six characters');
select is(
  (select count(*)::int from regexp_split_to_table(
      public.pickup_code_alphabet(), '') c
    where c IN ('I','L','O','U','0','1')),
  0,
  '13: …and contains none of I, L, O, U, 0, 1 — the six that get misread'
);

-- ⚠️ The column CHECK is a LITERAL (a CHECK cannot read a function defined in a
-- later migration), so it is a second copy of the rule. This is the assertion
-- that keeps the copy honest.
select ok(
  (select pg_get_constraintdef(oid) like '%23456789ABCDEFGHJKMNPQRSTVWXYZ%'
     from pg_constraint where conname='pickup_reservations_pickup_code_check'),
  '14: the column CHECK uses the same alphabet as the constant'
);
select ok(
  (select pg_get_constraintdef(oid) like '%{6}%'
     from pg_constraint where conname='pickup_reservations_pickup_code_check'),
  '15: …and the same length'
);

-- ══ 3. Normalisation ═══════════════════════════════════════════════
select is(public.normalize_pickup_code('4f7k2q'), '4F7K2Q',
          '16: a lowercase code becomes uppercase');
select is(public.normalize_pickup_code('  4f 7k-2q '), '4F7K2Q',
          '17: …and spaces and dashes are stripped (a code is read aloud)');
select is(public.normalize_pickup_code('4f7k2q'), public.normalize_pickup_code(' 4F-7K 2Q '),
          '18: …so every way of writing it lands on the same code');
-- (The two direct inserts above deliberately use SIZES 42 and 43 rather than
-- 40: `idx_pickup_reservations_one_active_per_customer_product_size` would
-- otherwise block the RPC's own request later in this file, and that index
-- working is not what this suite is testing.)

-- ⚠️ THE ONE THAT MATTERS: no look-alike substitution.
select is(public.normalize_pickup_code('O0I1'), 'O0I1',
          '19: a wrong code is NOT rewritten into a right one (O stays O, 0 stays 0)');
select is(public.normalize_pickup_code(null), '',
          '20: a null code normalises to empty rather than blowing up');

-- ══ 4. Generation ══════════════════════════════════════════════════
select ok(
  (select bool_and(c ~ '^[23456789ABCDEFGHJKMNPQRSTVWXYZ]{6}$')
     from (select public.generate_pickup_code() c from generate_series(1, 200)) s),
  '21: 200 generated codes all match the column CHECK'
);
select is(
  (select count(distinct c)::int
     from (select public.generate_pickup_code() c from generate_series(1, 200)) s),
  200,
  '22: …and no two of them collided'
);

-- A direct insert with a bad code is refused — the CHECK is the shape rule, not
-- the generator.
select throws_ok(
  $$insert into public.pickup_reservations
      (customer_id, store_id, product_id, size, quantity, reserved_stock,
       status, pickup_deadline, pickup_code, reserved_at)
    values ('e0000000-0000-0000-0000-000000000002',
            'e0000000-0000-0000-0000-000000000005',
            'e0000000-0000-0000-0000-000000000007','40',1,1,'active',
            timezone('utc', now()) + interval '24 hours', 'ABC123', now())$$,
  '23514', null,
  '23: a code outside the alphabet is refused (1 and 3 are not symbols)'
);
select throws_ok(
  $$insert into public.pickup_reservations
      (customer_id, store_id, product_id, size, quantity, reserved_stock,
       status, pickup_deadline, pickup_code, reserved_at)
    values ('e0000000-0000-0000-0000-000000000002',
            'e0000000-0000-0000-0000-000000000005',
            'e0000000-0000-0000-0000-000000000007','40',1,1,'active',
            timezone('utc', now()) + interval '24 hours', 'ABCDE', now())$$,
  '23514', null,
  '24: a five-character code is refused'
);
select lives_ok(
  $$insert into public.pickup_reservations
      (id, customer_id, store_id, product_id, size, quantity, reserved_stock,
       status, pickup_deadline, pickup_code, reserved_at)
    values ('f0000000-0000-0000-0000-0000000000c1',
            'e0000000-0000-0000-0000-000000000002',
            'e0000000-0000-0000-0000-000000000005',
            'e0000000-0000-0000-0000-000000000007','42',1,1,'active',
            timezone('utc', now()) + interval '24 hours', '234567', now())$$,
  '25: a well-formed code is accepted'
);
select is(
  (select pickup_code from public.pickup_reservations
    where id = 'f0000000-0000-0000-0000-0000000000c1'),
  '234567',
  '26: …and stored as given (already normalised)'
);
-- A hand-supplied code is NORMALISED by the trigger and then validated by the
-- CHECK, so the same code written any way lands on one row.
--
-- (This insert also proves the uniqueness assertion below is about the
-- NORMALISED value: an earlier draft of this fixture passed `' 2-3 4.5 67 '`,
-- which normalises to the same `234567` as the hold above, and the unique index
-- refused it — which is the correct behaviour and the wrong fixture.)
select lives_ok(
  $$insert into public.pickup_reservations
      (id, customer_id, store_id, product_id, size, quantity, reserved_stock,
       status, pickup_deadline, pickup_code, reserved_at)
    values ('f0000000-0000-0000-0000-0000000000c2',
            'e0000000-0000-0000-0000-000000000002',
            'e0000000-0000-0000-0000-000000000005',
            'e0000000-0000-0000-0000-000000000007','43',1,1,'active',
            timezone('utc', now()) + interval '24 hours', ' 5-4 E.3 F 2 ', now())$$,
  '27: a typed-with-separators code inserted by hand is accepted'
);
select is(
  (select pickup_code from public.pickup_reservations
    where id = 'f0000000-0000-0000-0000-0000000000c2'),
  '54E3F2',
  '28: …normalised first (and the unique index is on the NORMALISED value)'
);

-- The unique index is the backstop behind the generator's loop.
select throws_ok(
  $$update public.pickup_reservations
       set pickup_code = '234567'
     where id = 'f0000000-0000-0000-0000-0000000000c2'$$,
  '23505', null,
  '29: two holds can never share a code (unique index)'
);

-- ══ 5. The customer's own hold gets a code ═════════════════════════
select set_config('request.jwt.claims',
  public.tmp_code_claims('e0000000-0000-0000-0000-000000000002'), true);
select lives_ok(
  $$select public.request_pickup_reservation(
      'e0000000-0000-0000-0000-000000000007'::uuid, '40', 1)$$,
  '30: a customer can still place a hold through the normal RPC'
);
select ok(
  public.tmp_code_active_code() ~ '^[23456789ABCDEFGHJKMNPQRSTVWXYZ]{6}$',
  '31: …and the RPC''s own insert path assigned a well-formed code'
);

-- ⚠️ …and the SELLER of that store can resolve it.
select set_config('request.jwt.claims',
  public.tmp_code_claims('e0000000-0000-0000-0000-000000000001'), true);
select is(
  public.find_pickup_reservation_by_code(public.tmp_code_active_code()),
  public.tmp_code_active_hold(),
  '32: the owning store''s seller resolves the code to that exact hold'
);
-- …as written however the counter reads it.
select is(
  public.find_pickup_reservation_by_code(lower(public.tmp_code_active_code())),
  public.tmp_code_active_hold(),
  '33: …and a lowercase, unpunctuated reading of it resolves to the same hold'
);

-- ⚠️ ANOTHER STORE'S SELLER CANNOT. This is the scoping that makes a code safe to
-- be non-secret.
select set_config('request.jwt.claims',
  public.tmp_code_claims('e0000000-0000-0000-0000-000000000003'), true);
select throws_ok(
  $$select public.find_pickup_reservation_by_code(
      (select pickup_code from public.pickup_reservations
        where id = 'f0000000-0000-0000-0000-0000000000c1'))$$,
  'P0001', 'NOT_FOUND — no pickup hold for your store matches that code',
  '34: another store''s seller gets NOT_FOUND — and cannot tell it from a real miss'
);
-- The customer is not a seller, so the resolver is not theirs either.
select set_config('request.jwt.claims',
  public.tmp_code_claims('e0000000-0000-0000-0000-000000000002'), true);
select throws_ok(
  $$select public.find_pickup_reservation_by_code('234567')$$,
  'P0001', 'NOT_FOUND — no pickup hold for your store matches that code',
  '35: the customer cannot resolve a code (it is a counter tool, not a lookup for them)'
);
-- A short or empty code is answered without a scan of anything.
select set_config('request.jwt.claims',
  public.tmp_code_claims('e0000000-0000-0000-0000-000000000001'), true);
select throws_ok(
  $$select public.find_pickup_reservation_by_code('4F7')$$,
  'P0001',
  'NOT_FOUND — no pickup hold matches that code (a code is 6 characters)',
  '36: a part-typed code says how long a code is'
);

-- ══ 6. One action: resolve + fulfil ════════════════════════════════
-- ONE call, and what it RETURNS must be the new ORDER's id. `lives_ok` alone was
-- too weak here: a function that resolved the code and then returned the HOLD's
-- id (i.e. never collected anything) passes it — the mutation `return v_id` did
-- exactly that while this assertion stayed green. So the call is captured and
-- the id is checked against `orders`.
create temporary table tmp_code_collected as
select public.fulfill_pickup_reservation_by_code(
         public.tmp_code_active_code()) as order_id;

select is(
  (select count(*)::int from public.orders
    where id = (select order_id from tmp_code_collected)),
  1,
  '37: one call with the code collects the hold, returning the new ORDER'
);
select isnt(
  (select order_id from tmp_code_collected),
  public.tmp_code_active_hold(),
  '38: …and NOT the hold it came from (a UI would report success on nothing)'
);
select is(
  (select status::text from public.pickup_reservations
    where id = public.tmp_code_hold_40()),
  'fulfilled',
  '39: …the hold is fulfilled'
);

-- ⚠️ THE DELEGATION IS REAL. Everything below is a rule owned by
-- `fulfill_pickup_reservation`; asserting it through the by-code path is what
-- stops that path from quietly becoming a second implementation.
select throws_ok(
  $$select public.fulfill_pickup_reservation_by_code(public.tmp_code_hold_code())$$,
  'P0001', 'ALREADY_RESOLVED',
  '40: a second collection with the same code is refused ALREADY_RESOLVED'
);
select is(
  public.find_pickup_reservation_by_code(public.tmp_code_hold_code()),
  public.tmp_code_hold_40(),
  '41: …while the code still RESOLVES after collection (the dispute case)'
);
select is(
  (select o.source || '/' || o.payment_status || '/' || o.status::text
     from public.orders o
    where o.id = (select fulfilled_order_id from public.pickup_reservations
                   where id = public.tmp_code_hold_40())),
  'pos/paid/received',
  '42: …and the collection is a real POS sale (source/paid/received)'
);
select is(
  (select count(*)::int from public.order_items oi
    where oi.order_id = (select fulfilled_order_id from public.pickup_reservations
                          where id = public.tmp_code_hold_40())),
  1,
  '43: …with one line item, written once'
);
-- ⚠️ THE HOLD IS THE DRAW: the units left `inventory.stock` when the hold was
-- created, so fulfilment must NOT decrement again (5 → 4 at request, 4 here).
select is(
  public.tmp_code_stock('e0000000-0000-0000-0000-000000000007','40'), 4,
  '44: collecting does NOT draw the stock a second time'
);
select set_config('request.jwt.claims',
  public.tmp_code_claims('e0000000-0000-0000-0000-000000000003'), true);
select throws_ok(
  $$select public.fulfill_pickup_reservation_by_code('234567')$$,
  'P0001', 'NOT_FOUND — no pickup hold for your store matches that code',
  '45: another store cannot collect a hold from its code'
);

select * from finish();
rollback;
