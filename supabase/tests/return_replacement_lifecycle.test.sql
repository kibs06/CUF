-- ══════════════════════════════════════════════════════════════════
-- Return → replacement lifecycle — pgTAP
-- Run by CI via `supabase test db` (supabase-migrations.yml)
--
-- Covers `20261112000000_return_replacement.sql`,
-- `20261112000100_return_replacement_inventory.sql`,
-- `20261112000200_return_replacement_method.sql` and
-- `20261112000300_replacement_received.sql` as ONE flow, because each
-- migration only owns a slice of it and the slices have to agree:
--
--   customer asks  →  delivered + paid, 1-4 photo proofs, inside 7 days
--                 →  return_requested  (+ customer feed + seller bell)
--   seller approves →  replaced (+ replacement_method in_store|shipped)
--   stock reconciles →  returned pair in (+qty), replacement out (-qty)
--   seller ships    →  carrier + tracking recorded on the same row
--   customer closes →  replacement_received (+ both feeds, once)
--
-- The assertions marked ⚠️ are the ways this could look right and be
-- wrong:
--
--   ⚠️ The approval writes the timeline row, the client does not (21).
--      `trg_record_order_status_change` already fires on every status
--      change; a client insert on top of it double-logs every approval.
--   ⚠️ The approval writes NO customer feed row (22), because
--      `notify_on_order_status_change` maps only the shipping statuses
--      and returns early for `replaced`. That is not a wish — it is why
--      the app writes its own `replaced` notification, and asserting it
--      stops a future `WHEN 'replaced'` branch from silently
--      double-notifying.
--   ⚠️ A customer cannot write `replacement_received` themselves (24).
--      The only customer UPDATE policy on `orders` is delivered→received
--      (`20261113000000`), and the confirmation is an RPC for exactly
--      that reason. If a future policy ever widens it "just for this
--      status", the row-level hazard (total_amount, payment_status,
--      store_id) comes with it.
--   ⚠️ Stock is net zero for a like-for-like swap, and only once
--      (25-30). A retried approval that moves stock twice is a silent
--      inventory drift on the store's most important number.
--   ⚠️ An in-store swap has nothing left to confirm (38). The app hides
--      the button; the RPC refuses it anyway, because the app is not the
--      authority on which path an order took.
--   ⚠️ An order with no store still closes (48-50). `seller_notifications
--      .store_id` is NOT NULL, so an unguarded insert would 23502 and
--      abort the customer's confirmation —
--      docs/AI/NOTIFICATION_RECIPIENT_AUDIT.md, the same rule the
--      request RPC follows.
--
-- The seller's approval is performed here as a direct UPDATE (the
-- harness role, RLS bypassed): that IS what the app does —
-- `updateOrderStatus` is an UPDATE under the store-scoped policy, not an
-- RPC. Assertion 24 is the only one that switches to `authenticated`,
-- because it is the only one whose subject is the policy itself.
-- ══════════════════════════════════════════════════════════════════

begin;
select plan(53);

-- ── helpers ────────────────────────────────────────────────────────
create or replace function public.tmp_rv_claims(p_user uuid)
returns text language sql immutable as $$
  select json_build_object('sub', p_user, 'role', 'authenticated')::text;
$$;

create or replace function public.tmp_rv_result(p_result jsonb, p_key text)
returns text language sql immutable as $$
  select coalesce(p_result ->> p_key, '');
$$;

select set_config('request.jwt.claims', '{"sub":null,"role":null}', true);
select set_config('request.headers', '{}', true);

-- ── fixtures (RLS bypassed) ────────────────────────────────────────
insert into auth.users (instance_id, id, aud, role, email, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000','e1000000-0000-0000-0000-000000000001','authenticated','authenticated','rv-seller@test.local', now(), now()),
  ('00000000-0000-0000-0000-000000000000','e1000000-0000-0000-0000-000000000002','authenticated','authenticated','rv-other@test.local',  now(), now()),
  ('00000000-0000-0000-0000-000000000000','e1000000-0000-0000-0000-000000000003','authenticated','authenticated','rv-admin@test.local',  now(), now()),
  ('00000000-0000-0000-0000-000000000000','e1000000-0000-0000-0000-000000000004','authenticated','authenticated','rv-cust@test.local',   now(), now()),
  ('00000000-0000-0000-0000-000000000000','e1000000-0000-0000-0000-000000000005','authenticated','authenticated','rv-cust2@test.local',  now(), now());

insert into public.profiles (id, full_name, email, role, seller_status)
values
  ('e1000000-0000-0000-0000-000000000001','Rv Seller','rv-seller@test.local','seller','approved'),
  ('e1000000-0000-0000-0000-000000000002','Rv Other','rv-other@test.local','seller','approved'),
  ('e1000000-0000-0000-0000-000000000003','Rv Admin','rv-admin@test.local','admin','none'),
  ('e1000000-0000-0000-0000-000000000004','Rv Customer','rv-cust@test.local','customer','none'),
  ('e1000000-0000-0000-0000-000000000005','Rv Stranger','rv-cust2@test.local','customer','none');

insert into public.stores (id, owner_id, name, location)
values ('e1000000-0000-0000-0000-000000000011','e1000000-0000-0000-0000-000000000001','Rv Store','Rv City');

insert into public.products (id, store_id, seller_id, name, price, is_active)
values
  ('e1000000-0000-0000-0000-000000000021','e1000000-0000-0000-0000-000000000011','e1000000-0000-0000-0000-000000000001','Rv Sandal', 1500, true),
  -- Deleted later, to prove a line whose product is gone is counted, not lost.
  ('e1000000-0000-0000-0000-000000000022','e1000000-0000-0000-0000-000000000011','e1000000-0000-0000-0000-000000000001','Rv Sandal Gone', 900, true);

-- Enough stock for the three order lines the sale trigger will take out.
insert into public.inventory (product_id, size, stock)
values ('e1000000-0000-0000-0000-000000000021','9', 10),
       ('e1000000-0000-0000-0000-000000000022','9', 2);

insert into public.orders
  (id, customer_id, store_id, status, total_amount, payment_method,
   payment_status, fulfillment, source)
values
  -- The main line: shipped replacement, request → approve → stock → ship → confirm.
  ('e1000000-0000-0000-0000-000000000031','e1000000-0000-0000-0000-000000000004',
   'e1000000-0000-0000-0000-000000000011','delivered',1500,'gcash','paid','delivery','online'),
  -- Cash paid at handover: unpaid on paper, but returnable (in-store swap).
  ('e1000000-0000-0000-0000-000000000032','e1000000-0000-0000-0000-000000000004',
   'e1000000-0000-0000-0000-000000000011','delivered',1500,'cash','unpaid','pickup','online'),
  -- Approved before the delivery path was recorded (replacement_method NULL).
  ('e1000000-0000-0000-0000-000000000033','e1000000-0000-0000-0000-000000000004',
   'e1000000-0000-0000-0000-000000000011','replaced',1500,'gcash','paid','delivery','online'),
  -- No store at all (custom/legacy order): the confirmation must still close.
  ('e1000000-0000-0000-0000-000000000034','e1000000-0000-0000-0000-000000000004',
   NULL,'replaced',1500,'gcash','paid','delivery','online'),
  -- Its product is deleted before stock reconciliation (skipped, not lost).
  ('e1000000-0000-0000-0000-000000000035','e1000000-0000-0000-0000-000000000004',
   'e1000000-0000-0000-0000-000000000011','replaced',900,'gcash','paid','delivery','online');

update public.orders set replacement_method = 'shipped'
 where id = 'e1000000-0000-0000-0000-000000000035';

insert into public.order_items (order_id, product_id, size, quantity, unit_price)
values ('e1000000-0000-0000-0000-000000000031','e1000000-0000-0000-0000-000000000021','9',1,1500),
       ('e1000000-0000-0000-0000-000000000032','e1000000-0000-0000-0000-000000000021','9',1,1500),
       ('e1000000-0000-0000-0000-000000000035','e1000000-0000-0000-0000-000000000022','9',1,900);

-- ══ 1. Structure ═══════════════════════════════════════════════════
select has_function('public','request_my_return',
                    array['uuid','text','text','text','text[]'],
                    '1: the request RPC exists with the 5-arg (multi-proof) signature');
select has_function('public','apply_return_replacement_inventory', array['uuid'],
                    '2: stock reconciliation is its own function, not client arithmetic');
select has_function('public','confirm_replacement_received', array['uuid'],
                    '3: the customer can close a shipped replacement');

select ok(
  (select pg_get_constraintdef(oid) like '%replacement_received%'
     from pg_constraint
    where conrelid = 'public.orders'::regclass
      and conname = 'orders_status_check'),
  '4: `replacement_received` is admitted by the status CHECK'
);
select ok(
  (select pg_get_constraintdef(oid) like '%replacement_received%'
     from pg_constraint
    where conrelid = 'public.seller_notifications'::regclass
      and conname = 'seller_notifications_type_check'),
  '5: …and by the bell''s type CHECK (an unlisted type is a failed close)'
);
select is(
  has_function_privilege('anon','public.confirm_replacement_received(uuid)','EXECUTE'),
  false,
  '6: anon cannot close a replacement'
);
select is(
  has_function_privilege('authenticated','public.confirm_replacement_received(uuid)','EXECUTE'),
  true,
  '7: …authenticated can (the customer is the caller)'
);
select is(
  has_function_privilege('anon','public.apply_return_replacement_inventory(uuid)','EXECUTE'),
  false,
  '8: anon cannot move stock'
);

-- ══ 2. The customer files the request ══════════════════════════════
select set_config('request.jwt.claims',
  public.tmp_rv_claims('e1000000-0000-0000-0000-000000000004'), true);

select is(
  public.tmp_rv_result(
    public.request_my_return(
      'e1000000-0000-0000-0000-000000000031','Size issue', null, null,
      array['returns/rv/proof-1.jpg']),
    'status'),
  'return_requested',
  '9: a delivered, paid order can be returned'
);
select ok(
  (select status = 'return_requested' and return_requested_at is not null
     from public.orders where id = 'e1000000-0000-0000-0000-000000000031'),
  '10: …the row moves and is stamped'
);
select is(
  (select array_length(return_proof_paths, 1)
     from public.orders where id = 'e1000000-0000-0000-0000-000000000031'),
  1,
  '11: …and the proof the seller inspects is on the order'
);
select is(
  (select count(*)::int from public.notifications
    where order_id = 'e1000000-0000-0000-0000-000000000031'
      and category = 'returns' and title = 'Return requested'),
  1,
  '12: the customer feed records the request'
);
select is(
  (select count(*)::int from public.seller_notifications
    where reference_id = 'e1000000-0000-0000-0000-000000000031'
      and type = 'return_request'),
  1,
  '13: …and the store''s bell does too — "asked" and "told" cannot disagree'
);

-- ⚠️ No photo, no return: the seller cannot inspect what is not shown.
select throws_ok(
  $$select public.request_my_return(
      'e1000000-0000-0000-0000-000000000032','Size issue', null, null, '{}')$$,
  'P0001', null,
  '14: a request without a photo proof is refused'
);
select throws_ok(
  $$select public.request_my_return(
      'e1000000-0000-0000-0000-000000000032','Size issue', null, null,
      array['a','b','c','d','e'])$$,
  'P0001', null,
  '15: …and one with five proofs is refused (1-4 is the run the seller reads)'
);

select is(
  public.tmp_rv_result(
    public.request_my_return(
      'e1000000-0000-0000-0000-000000000032','Does not fit', null, null,
      array['returns/rv/proof-2.jpg']),
    'status'),
  'return_requested',
  '16: cash paid at handover (unpaid on paper) is still returnable'
);
select throws_ok(
  $$select public.request_my_return(
      'e1000000-0000-0000-0000-000000000032','Does not fit', null, null,
      array['returns/rv/proof-3.jpg'])$$,
  'P0001', null,
  '17: asking twice on the same order is refused'
);

select set_config('request.jwt.claims',
  public.tmp_rv_claims('e1000000-0000-0000-0000-000000000005'), true);
select throws_ok(
  $$select public.request_my_return(
      'e1000000-0000-0000-0000-000000000031','Size issue', null, null,
      array['returns/rv/proof-4.jpg'])$$,
  '42501', null,
  '18: someone else''s order answers "Order not found", not "not yours"'
);

-- ══ 3. The seller approves — shipped path ══════════════════════════
select set_config('request.jwt.claims',
  public.tmp_rv_claims('e1000000-0000-0000-0000-000000000001'), true);

select lives_ok(
  $$update public.orders
       set status = 'replaced',
           replacement_method = 'shipped',
           replacement_carrier = 'J&T',
           replacement_tracking_number = 'JNT-RV-1',
           replacement_shipped_at = now()
     where id = 'e1000000-0000-0000-0000-000000000031'$$,
  '19: approving with the shipped path is a plain UPDATE (no new RPC needed)'
);
select ok(
  (select status = 'replaced'
          and replacement_method = 'shipped'
          and replacement_carrier = 'J&T'
          and replacement_tracking_number = 'JNT-RV-1'
     from public.orders where id = 'e1000000-0000-0000-0000-000000000031'),
  '20: …and the path and tracking came through with it'
);
-- ⚠️ Exactly one timeline row, written by the trigger.
select is(
  (select count(*)::int from public.order_status_history
    where order_id = 'e1000000-0000-0000-0000-000000000031'
      and status = 'replaced'),
  1,
  '21: the approval lands in the order''s timeline exactly once'
);
-- ⚠️ The trigger maps only the shipping statuses; `replaced` is the app's
-- notification to write. Two rows here would mean two notifications.
select is(
  (select count(*)::int from public.notifications
    where order_id = 'e1000000-0000-0000-0000-000000000031'),
  1,
  '22: the approval itself writes no feed row (the request row is still the only one)'
);
select throws_ok(
  $$update public.orders set replacement_method = 'carrier_pigeon'
     where id = 'e1000000-0000-0000-0000-000000000031'$$,
  '23514', null,
  '23: a third delivery path cannot be typed into the column'
);

-- ⚠️ RLS IS THE SUBJECT: the customer's only UPDATE policy is
-- delivered→received, so this matches no row and silently changes nothing.
-- It has to run through a function to report the row count — a
-- data-modifying CTE is only legal at the top level, and pgTAP's is()
-- evaluates its arguments as a subquery. SECURITY INVOKER on purpose: the
-- update then runs with the caller's role and the caller's policies.
create or replace function public.tmp_rv_try_status(p_order uuid, p_status text)
returns int language plpgsql as $$
declare v_n int;
begin
  update public.orders set status = p_status where id = p_order;
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

set local role authenticated;
select is(
  public.tmp_rv_try_status(
    'e1000000-0000-0000-0000-000000000031', 'replacement_received'),
  0,
  '24: a customer cannot write `replacement_received` directly — the RPC is the only way in'
);
reset role;

-- ══ 4. Stock reconciles, once ══════════════════════════════════════
-- Pinned so the assertions do not depend on the sale trigger's arithmetic.
update public.inventory set stock = 5
 where product_id = 'e1000000-0000-0000-0000-000000000021' and size = '9';

select is(
  public.tmp_rv_result(
    public.apply_return_replacement_inventory(
      'e1000000-0000-0000-0000-000000000031'), 'applied'),
  'true',
  '25: the store owner can reconcile an approved replacement'
);
-- The product behind this order's only line is gone by the time stock is
-- reconciled: the units are counted, never silently dropped.
delete from public.products where id = 'e1000000-0000-0000-0000-000000000022';

select is(
  public.tmp_rv_result(
    public.apply_return_replacement_inventory(
      'e1000000-0000-0000-0000-000000000035'), 'skipped'),
  '1',
  '26: a line whose product was deleted is reported as skipped, not lost'
);
select is(
  (select stock from public.inventory
    where product_id = 'e1000000-0000-0000-0000-000000000021' and size = '9'),
  5,
  '27: a like-for-like swap is net zero (pair back in, replacement out)'
);
select ok(
  (select replacement_inventory_at is not null from public.orders
    where id = 'e1000000-0000-0000-0000-000000000031'),
  '28: …and the one-shot marker is stamped'
);
select is(
  public.tmp_rv_result(
    public.apply_return_replacement_inventory(
      'e1000000-0000-0000-0000-000000000031'), 'reason'),
  'already_applied',
  '29: a retried approval is a no-op, not a second stock move'
);
select is(
  (select stock from public.inventory
    where product_id = 'e1000000-0000-0000-0000-000000000021' and size = '9'),
  5,
  '30: …the number is unchanged by the retry'
);
select throws_ok(
  $$select public.apply_return_replacement_inventory(
      'e1000000-0000-0000-0000-000000000032')$$,
  'P0001', null,
  '31: stock is not reconciled for an order that is not approved yet'
);

select set_config('request.jwt.claims',
  public.tmp_rv_claims('e1000000-0000-0000-0000-000000000002'), true);
select throws_ok(
  $$select public.apply_return_replacement_inventory(
      'e1000000-0000-0000-0000-000000000031')$$,
  '42501', null,
  '32: another store''s seller cannot move this store''s stock'
);

select set_config('request.jwt.claims',
  public.tmp_rv_claims('e1000000-0000-0000-0000-000000000001'), true);
select is(
  (select count(*)::int from public.inventory
    where product_id = 'e1000000-0000-0000-0000-000000000022'),
  0,
  '33: the deleted product took its inventory row with it (nothing to hold stock for)'
);
select ok(
  (select count(*) = 1 from public.order_items
    where order_id = 'e1000000-0000-0000-0000-000000000035'
      and product_id is null),
  '34: …and the line survives with no product, so the quantity is still known'
);

-- ══ 5. The customer closes a shipped replacement ═══════════════════
select set_config('request.jwt.claims',
  public.tmp_rv_claims('e1000000-0000-0000-0000-000000000005'), true);
select throws_ok(
  $$select public.confirm_replacement_received(
      'e1000000-0000-0000-0000-000000000031')$$,
  '42501', null,
  '35: someone else cannot confirm the customer''s replacement'
);

select set_config('request.jwt.claims',
  public.tmp_rv_claims('e1000000-0000-0000-0000-000000000004'), true);
select throws_ok(
  $$select public.confirm_replacement_received(
      'e1000000-0000-0000-0000-000000000032')$$,
  'P0001', null,
  '36: an order with no approved replacement has nothing to confirm'
);

-- In-store swap: finished at the counter.
select lives_ok(
  $$update public.orders
       set status = 'replaced', replacement_method = 'in_store'
     where id = 'e1000000-0000-0000-0000-000000000032'$$,
  '37: approving an in-store swap is the same UPDATE with the other path'
);
select throws_ok(
  $$select public.confirm_replacement_received(
      'e1000000-0000-0000-0000-000000000032')$$,
  'P0001', null,
  '38: ⚠️ an in-store swap has nothing left to confirm'
);

select is(
  public.tmp_rv_result(
    public.confirm_replacement_received(
      'e1000000-0000-0000-0000-000000000031'), 'status'),
  'replacement_received',
  '39: the shipped replacement closes on the customer''s word'
);
select ok(
  (select status = 'replacement_received' and replacement_received_at is not null
     from public.orders where id = 'e1000000-0000-0000-0000-000000000031'),
  '40: …the row moves and is stamped'
);
select is(
  (select count(*)::int from public.notifications
    where order_id = 'e1000000-0000-0000-0000-000000000031'
      and category = 'returns' and title = 'Replacement received'),
  1,
  '41: the customer feed records the confirmation'
);
select is(
  (select count(*)::int from public.seller_notifications
    where reference_id = 'e1000000-0000-0000-0000-000000000031'
      and type = 'replacement_received'),
  1,
  '42: …and the store''s bell is told the return is closed'
);
select is(
  (select count(*)::int from public.order_status_history
    where order_id = 'e1000000-0000-0000-0000-000000000031'
      and status = 'replacement_received'),
  1,
  '43: the timeline row comes from the trigger, once'
);
select is(
  (select stock from public.inventory
    where product_id = 'e1000000-0000-0000-0000-000000000021' and size = '9'),
  5,
  '44: confirming moves no stock — the swap was already accounted for'
);
select throws_ok(
  $$select public.confirm_replacement_received(
      'e1000000-0000-0000-0000-000000000031')$$,
  'P0001', null,
  '45: a second confirmation is refused'
);
select throws_ok(
  $$select public.request_my_return(
      'e1000000-0000-0000-0000-000000000031','Size issue', null, null,
      array['returns/rv/proof-5.jpg'])$$,
  'P0001', null,
  '46: …and a closed replacement cannot be returned again'
);

-- ⚠️ Approved before the path was recorded: NULL method, so the customer
-- is allowed to close it (the app shows the button for NULL too).
select is(
  public.tmp_rv_result(
    public.confirm_replacement_received(
      'e1000000-0000-0000-0000-000000000033'), 'status'),
  'replacement_received',
  '47: a legacy approval with no recorded path can still be closed'
);

-- ⚠️ No store: the customer feed row is the only one that can exist, and
-- the confirmation must not die trying to write the impossible one.
select is(
  public.tmp_rv_result(
    public.confirm_replacement_received(
      'e1000000-0000-0000-0000-000000000034'), 'status'),
  'replacement_received',
  '48: an order with no store still closes'
);
select is(
  (select count(*)::int from public.notifications
    where order_id = 'e1000000-0000-0000-0000-000000000034'
      and title = 'Replacement received'),
  1,
  '49: …the customer is still told'
);
select is(
  (select count(*)::int from public.seller_notifications
    where reference_id = 'e1000000-0000-0000-0000-000000000034'),
  0,
  '50: …and no bell row is invented for a store that does not exist'
);

-- ══ 6. The status is terminal for the rest of the app ══════════════
select is(
  (select count(*)::int from public.orders
    where id in ('e1000000-0000-0000-0000-000000000031',
                 'e1000000-0000-0000-0000-000000000033',
                 'e1000000-0000-0000-0000-000000000034')
      and status = 'replacement_received'),
  3,
  '51: every confirmation landed on the status the app filters on'
);
select is(
  (select count(*)::int from public.orders
    where status = 'replacement_received'
      and replacement_received_at is null),
  0,
  '52: …and no confirmed order is missing its timestamp'
);
select is(
  (select count(*)::int from public.seller_notifications
    where type = 'replacement_received'
      and reference_id is null),
  0,
  '53: every bell row points at the order it is about (tap-to-navigate)'
);

select * from finish();
rollback;
