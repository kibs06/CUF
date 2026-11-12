-- ══════════════════════════════════════════════════════════════════
-- Cash settles at handover — pgTAP
-- Run by CI via `supabase test db` (supabase-migrations.yml)
--
-- Covers `20261113000500_settle_cod_on_delivery.sql`: the seller marking
-- an order delivered is the moment the sale exists, so a cash order must
-- be 'paid' from then on — not only after the buyer taps Confirm receipt.
--
-- The assertions marked ⚠️ are the ways this could look right and be
-- wrong:
--   ⚠️ Settling every transition, not just handover (1-3): an unpaid cash
--      order still 'preparing' is not a sale yet.
--   ⚠️ Settling every payment method (4-5): a GCash order nobody verified
--      must stay unpaid; counting it would report money that never came.
--   ⚠️ Counting a sale the counters cannot see (6-8): paid is only worth
--      something if sales_service's filter and product_sales() agree.
-- ══════════════════════════════════════════════════════════════════

begin;
select plan(13);

-- ── helpers ────────────────────────────────────────────────────────
create or replace function public.tmp_cod_claims(p_user uuid)
returns text language sql immutable as $$
  select json_build_object('sub', p_user, 'role', 'authenticated')::text;
$$;

-- The seller's own UPDATE path (RLS in force): returns the row count, and
-- the payment status the write left behind, as 'rows|status'.
create or replace function public.tmp_cod_move(p_order uuid, p_status text)
returns text language plpgsql as $$
declare v_n int; v_pay text;
begin
  update public.orders set status = p_status where id = p_order;
  get diagnostics v_n = row_count;
  select payment_status into v_pay from public.orders where id = p_order;
  return v_n || '|' || coalesce(v_pay, '');
end;
$$;

select set_config('request.jwt.claims', '{"sub":null,"role":null}', true);

-- ── fixtures (RLS bypassed) ────────────────────────────────────────
insert into auth.users (instance_id, id, aud, role, email, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000','e2000000-0000-0000-0000-000000000001','authenticated','authenticated','cod-seller@test.local', now(), now()),
  ('00000000-0000-0000-0000-000000000000','e2000000-0000-0000-0000-000000000002','authenticated','authenticated','cod-cust@test.local',  now(), now());

insert into public.profiles (id, full_name, email, role, seller_status)
values
  ('e2000000-0000-0000-0000-000000000001','Cod Seller','cod-seller@test.local','seller','approved'),
  ('e2000000-0000-0000-0000-000000000002','Cod Customer','cod-cust@test.local','customer','none');

insert into public.stores (id, owner_id, name, location)
values ('e2000000-0000-0000-0000-000000000011','e2000000-0000-0000-0000-000000000001','Cod Store','Cod City');

insert into public.products (id, store_id, seller_id, name, price, is_active)
values ('e2000000-0000-0000-0000-000000000021','e2000000-0000-0000-0000-000000000011','e2000000-0000-0000-0000-000000000001','Cod Sandal', 1200, true);

insert into public.inventory (product_id, size, stock)
values ('e2000000-0000-0000-0000-000000000021','9', 10);

insert into public.orders
  (id, customer_id, store_id, status, total_amount, payment_method,
   payment_status, fulfillment, source)
values
  -- The subject: cash, placed, unpaid.
  ('e2000000-0000-0000-0000-000000000031','e2000000-0000-0000-0000-000000000002',
   'e2000000-0000-0000-0000-000000000011','placed',1200,'cash','unpaid','delivery','online'),
  -- A second cash order that goes all the way to the buyer's confirmation.
  ('e2000000-0000-0000-0000-000000000032','e2000000-0000-0000-0000-000000000002',
   'e2000000-0000-0000-0000-000000000011','placed',1200,'cash','unpaid','delivery','online'),
  -- ⚠️ Unverified e-wallet money must never be counted by this rule.
  ('e2000000-0000-0000-0000-000000000033','e2000000-0000-0000-0000-000000000002',
   'e2000000-0000-0000-0000-000000000011','ready',1200,'gcash','unpaid','delivery','online'),
  -- Driven through the seller's own RLS-scoped UPDATE below.
  ('e2000000-0000-0000-0000-000000000034','e2000000-0000-0000-0000-000000000002',
   'e2000000-0000-0000-0000-000000000011','ready',1200,'cash','unpaid','delivery','online');

insert into public.order_items (order_id, product_id, size, quantity, unit_price)
values ('e2000000-0000-0000-0000-000000000031','e2000000-0000-0000-0000-000000000021','9',1,1200);

-- ══ 1. Structure ═══════════════════════════════════════════════════
select is(
  (select count(*)::int from pg_trigger
    where tgrelid = 'public.orders'::regclass
      and tgname = 'trg_settle_cod_on_delivery'
      and not tgisinternal),
  1,
  '1: the handover trigger is on orders'
);
select is(
  (select count(*)::int from pg_trigger
    where tgrelid = 'public.orders'::regclass
      and tgname = 'trg_settle_cod_on_receipt'),
  0,
  '2: …and the receipt-time trigger is gone, so only one rule can fire'
);
select is(
  (select count(*)::int from pg_proc
    where proname = 'settle_cod_on_receipt' and pronamespace = 'public'::regnamespace),
  0,
  '3: the receipt-time function is dropped, not left as a second rule'
);

-- ══ 2. Not a sale until handover ═══════════════════════════════════
select is(
  (select payment_status from public.orders
    where id = 'e2000000-0000-0000-0000-000000000031'),
  'unpaid',
  '4: a cash order waiting to be prepared is not money yet'
);

update public.orders set status = 'preparing'
 where id = 'e2000000-0000-0000-0000-000000000031';
select is(
  (select payment_status from public.orders
    where id = 'e2000000-0000-0000-0000-000000000031'),
  'unpaid',
  '5: …nor while it is being prepared'
);

-- ══ 3. Handover settles it ═════════════════════════════════════════
update public.orders set status = 'ready'
 where id = 'e2000000-0000-0000-0000-000000000031';
update public.orders set status = 'delivered'
 where id = 'e2000000-0000-0000-0000-000000000031';
select is(
  (select payment_status from public.orders
    where id = 'e2000000-0000-0000-0000-000000000031'),
  'paid',
  '6: marking it delivered settles the cash in the same write'
);

-- ══ 4. The buyer's confirmation is still a safe fallback ════════════
update public.orders set status = 'preparing'
 where id = 'e2000000-0000-0000-0000-000000000032';
update public.orders set status = 'delivered'
 where id = 'e2000000-0000-0000-0000-000000000032';
update public.orders set status = 'received'
 where id = 'e2000000-0000-0000-0000-000000000032';
select is(
  (select payment_status from public.orders
    where id = 'e2000000-0000-0000-0000-000000000032'),
  'paid',
  '7: a confirmed receipt leaves an already-settled order paid (no double write)'
);

-- ══ 5. ⚠️ Other payment methods are untouched ══════════════════════
update public.orders set status = 'delivered'
 where id = 'e2000000-0000-0000-0000-000000000033';
select is(
  (select payment_status from public.orders
    where id = 'e2000000-0000-0000-0000-000000000033'),
  'unpaid',
  '8: ⚠️ an unverified GCash order delivered stays unpaid'
);

-- ══ 6. The seller's own path (RLS in force) ════════════════════════
select set_config('request.jwt.claims',
  public.tmp_cod_claims('e2000000-0000-0000-0000-000000000001'), true);
set local role authenticated;
select is(
  public.tmp_cod_move('e2000000-0000-0000-0000-000000000034', 'delivered'),
  '1|paid',
  '9: the store owner''s Mark Delivered both moves the order and settles it'
);
reset role;

-- ══ 7. What the seller''s screens read ═════════════════════════════
-- The sold counter (product_sales) and the revenue rule the app uses
-- (status <> 'cancelled' AND payment_status = 'paid').
select is(
  (select units_sold from public.product_sales()
    where product_id = 'e2000000-0000-0000-0000-000000000021'),
  1::bigint,
  '10: the delivered cash order counts toward the product''s sold total'
);
select is(
  (select count(*)::int from public.orders
    where store_id = 'e2000000-0000-0000-0000-000000000011'
      and status <> 'cancelled'
      and payment_status = 'paid'),
  3,
  '11: …and three orders now feed the seller''s sales, the unverified GCash one excluded'
);
select is(
  (select count(*)::int from public.orders
    where store_id = 'e2000000-0000-0000-0000-000000000011'
      and status = 'received'
      and payment_status = 'paid'),
  1,
  '12: the confirmed order is not counted twice — it is still one row'
);

-- ══ 8. Cancelling takes it back out ════════════════════════════════
update public.orders set status = 'cancelled'
 where id = 'e2000000-0000-0000-0000-000000000034';
select is(
  (select count(*)::int from public.orders
    where store_id = 'e2000000-0000-0000-0000-000000000011'
      and status <> 'cancelled'
      and payment_status = 'paid'),
  2,
  '13: a cancelled order drops out of the sales figure again'
);

select * from finish();
rollback;
