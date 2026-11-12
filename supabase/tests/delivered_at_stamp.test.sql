-- ══════════════════════════════════════════════════════════════════
-- The sale is dated by the handover — pgTAP
-- Run by CI via `supabase test db` (supabase-migrations.yml)
--
-- Covers `20261113000600_stamp_delivered_at_for_sales.sql`: every seller
-- sales figure buckets by `orders.delivered_at`, the moment the seller
-- marked the order delivered (or received, for pickups) — never by
-- `created_at`, the day the order was placed.
--
-- The assertions marked ⚠️ are the ways this could look right and be
-- wrong:
--   ⚠️ Dating the sale by placement (1-3): an order placed Friday and
--      handed over Monday must not sit in Friday's figure.
--   ⚠️ Moving the date on a second handover (4-5): a declined return
--      that comes back must not re-date the sale to the return week.
--   ⚠️ Dating a sale that never happened (6): rows that never reached
--      handover must stay NULL and out of every figure.
-- ══════════════════════════════════════════════════════════════════

begin;
select plan(9);

-- ── fixtures (RLS bypassed) ────────────────────────────────────────
insert into auth.users (instance_id, id, aud, role, email, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000','e3000000-0000-0000-0000-000000000001','authenticated','authenticated','da-seller@test.local', now(), now()),
  ('00000000-0000-0000-0000-000000000000','e3000000-0000-0000-0000-000000000002','authenticated','authenticated','da-cust@test.local',  now(), now());

insert into public.profiles (id, full_name, email, role, seller_status)
values
  ('e3000000-0000-0000-0000-000000000001','Da Seller','da-seller@test.local','seller','approved'),
  ('e3000000-0000-0000-0000-000000000002','Da Customer','da-cust@test.local','customer','none');

insert into public.stores (id, owner_id, name, location)
values ('e3000000-0000-0000-0000-000000000011','e3000000-0000-0000-0000-000000000001','Da Store','Da City');

insert into public.products (id, store_id, seller_id, name, price, is_active)
values ('e3000000-0000-0000-0000-000000000021','e3000000-0000-0000-0000-000000000011','e3000000-0000-0000-0000-000000000001','Da Sandal', 800, true);

insert into public.inventory (product_id, size, stock)
values ('e3000000-0000-0000-0000-000000000021','9', 10);

-- A cash order placed three days before it is handed over.
insert into public.orders
  (id, customer_id, store_id, status, total_amount, payment_method,
   payment_status, fulfillment, source, created_at)
values
  ('e3000000-0000-0000-0000-000000000031','e3000000-0000-0000-0000-000000000002',
   'e3000000-0000-0000-0000-000000000011','placed',800,'cash','unpaid','delivery','online',
   now() - interval '3 days');
-- Born handed-over, like a POS sale created 'received' at the counter.
insert into public.orders
  (id, customer_id, store_id, status, total_amount, payment_method,
   payment_status, fulfillment, source)
values
  ('e3000000-0000-0000-0000-000000000032','e3000000-0000-0000-0000-000000000002',
   'e3000000-0000-0000-0000-000000000011','received',800,'cash','paid','pickup','pos');

insert into public.order_items (order_id, product_id, size, quantity, unit_price)
values ('e3000000-0000-0000-0000-000000000031','e3000000-0000-0000-0000-000000000021','9',1,800);

-- ══ 1. Structure ═══════════════════════════════════════════════════
select ok(
  (select count(*)::int = 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'orders'
      and column_name = 'delivered_at'
      and data_type = 'timestamp with time zone'),
  '1: orders.delivered_at exists as a timestamptz'
);
select is(
  (select count(*)::int from pg_trigger
    where tgrelid = 'public.orders'::regclass
      and tgname in ('trg_stamp_delivered_at_ins', 'trg_stamp_delivered_at_upd')
      and not tgisinternal),
  2,
  '2: the stamp fires on both inserts and status changes'
);

-- ══ 2. ⚠️ No handover, no date ═════════════════════════════════════
select is(
  (select delivered_at from public.orders
    where id = 'e3000000-0000-0000-0000-000000000031'),
  null,
  '3: ⚠️ a placed order has no sale date — nothing it did is a sale yet'
);

update public.orders set status = 'ready'
 where id = 'e3000000-0000-0000-0000-000000000031';
select is(
  (select delivered_at from public.orders
    where id = 'e3000000-0000-0000-0000-000000000031'),
  null,
  '4: …nor does a ready one waiting at the counter'
);

-- ══ 3. The handover stamps it ══════════════════════════════════════
update public.orders set status = 'delivered'
 where id = 'e3000000-0000-0000-0000-000000000031';
select ok(
  (select delivered_at >= created_at + interval '3 days' - interval '1 minute'
     from public.orders
    where id = 'e3000000-0000-0000-0000-000000000031'),
  '5: marking it delivered stamps the handover — three days after placement'
);

-- ══ 4. ⚠️ First handover wins ══════════════════════════════════════
select delivered_at into temporary tmp_da_first from public.orders
 where id = 'e3000000-0000-0000-0000-000000000031';
-- A declined return traveling back through the handover statuses.
update public.orders set status = 'return_requested'
 where id = 'e3000000-0000-0000-0000-000000000031';
update public.orders set status = 'delivered'
 where id = 'e3000000-0000-0000-0000-000000000031';
select is(
  (select delivered_at from public.orders
    where id = 'e3000000-0000-0000-0000-000000000031'),
  (select * from tmp_da_first),
  '6: ⚠️ coming back through delivered does not re-date the sale'
);

-- ══ 5. Born handed-over ════════════════════════════════════════════
select is(
  (select delivered_at = created_at from public.orders
    where id = 'e3000000-0000-0000-0000-000000000032'),
  true,
  '7: a row born received (POS) is stamped at its own creation'
);

-- ══ 6. What the seller''s screens read ═════════════════════════════
-- The same rule the app uses: paid, not cancelled, and handed over.
select is(
  (select count(*)::int from public.orders
    where store_id = 'e3000000-0000-0000-0000-000000000011'
      and status <> 'cancelled'
      and payment_status = 'paid'
      and delivered_at is not null),
  2,
  '8: both handed-over rows feed sales — a prepaid order that never '
    'shipped would not, its delivered_at still NULL'
);
select is(
  (select delivered_at::date > created_at::date from public.orders
    where id = 'e3000000-0000-0000-0000-000000000031'),
  true,
  '9: the sales date trails placement — Friday''s order lands in Monday''s figure'
);

select * from finish();
rollback;
