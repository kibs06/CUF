-- ══════════════════════════════════════════════════════════════════
-- 20261119130000_order_receipt_on_delivery.sql
--
-- 20261119110000 mailed the receipt when an online order became paid, and
-- 20261119120000 made a failed send retry. Both are server-side, but neither
-- gave the seller a say: a cash-on-delivery order is created `unpaid`, is
-- handed over at the door, and — because it never passes through
-- `payment_status = 'paid'` — would never have received a receipt at all.
--
-- This file makes the handover the receipt's moment, and puts it one tap away:
--
--   1. The dispatcher now considers a receipt owed when the order is paid
--      **or** delivered. Delivery is the sale reaching the customer; it is the
--      last moment the seller is certain who to thank.
--   2. `trg_order_receipt_on_delivered` fires on the transition INTO
--      'delivered' for online orders, so marking the order delivered emails the
--      receipt with no further taps. An order already stamped at payment stays
--      stamped — the trigger and the stamp are unchanged from 20261119110000,
--      so a paid-then-delivered order is mailed once, not twice.
--   3. `send_order_receipt_to_customer(order)` — the seller's own button. It
--      resolves the address the database already knows (`orders.customer_email`
--      if the till recorded one, otherwise the customer's registered
--      `profiles.email`), ignores a pending retry clock, and dispatches through
--      the same queue. The caller must own the order's store (or be an admin),
--      and a stamped order still answers `already_sent`, so a double tap cannot
--      mail the customer twice.
--   4. The retry sweep from 20261119120000 is re-stated with the same
--      paid-or-delivered rule, so a failed delivery receipt is retried on the
--      same 5 min → 15 min → 1 h → 6 h → stop schedule.
--
-- The dispatcher's own refusals are unchanged (`not_paid` now means "neither
-- paid nor delivered"), and every failure path still records instead of
-- raising: a receipt problem must never roll back the delivered update.
--
-- Additive and idempotent. Nothing breaks while it is unapplied: no new trigger
-- exists, and the app's button simply fails with the function-missing error it
-- already catches.
-- ══════════════════════════════════════════════════════════════════

begin;

-- ──────────────────────────────────────────────────────────────────
-- 1. The dispatcher — a delivered order owes a receipt too
--
--    Same contract as 20261119120000 ({queued, reason, to}; never raises),
--    with the one condition widened. `already_sent` now names the address it
--    went to, which is what the seller's button reports back.
-- ──────────────────────────────────────────────────────────────────
create or replace function public.queue_order_receipt_email(
  p_order_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order        jsonb;
  v_paid         text;
  v_status       text;
  v_source       text;
  v_emailed_at   text;
  v_customer     uuid;
  v_email        text;
  v_url          text;
  v_key          text;
  v_request_id   bigint;
  v_attempts     integer;
  v_sending      timestamptz;
  v_next         timestamptz;
  v_claimed      boolean := false;
begin
  -- to_jsonb keeps this function working on a database where the receipt
  -- columns have not been added yet: the key is simply absent.
  select to_jsonb(o) into v_order
    from public.orders o
   where o.id = p_order_id;

  if v_order is null then
    return jsonb_build_object('queued', false, 'reason', 'order_missing');
  end if;

  v_paid       := v_order ->> 'payment_status';
  v_status     := coalesce(v_order ->> 'status', '');
  v_source     := coalesce(v_order ->> 'source', '');
  v_emailed_at := v_order ->> 'receipt_emailed_at';
  v_customer   := (v_order ->> 'customer_id')::uuid;
  v_email      := nullif(btrim(coalesce(v_order ->> 'customer_email', '')), '');
  v_attempts   := coalesce((v_order ->> 'receipt_email_attempts')::integer, 0);
  v_sending    := (v_order ->> 'receipt_email_sending_since')::timestamptz;
  v_next       := (v_order ->> 'receipt_email_next_attempt_at')::timestamptz;

  -- A receipt is owed when the money is in OR the goods are in the customer's
  -- hands. Cash-on-delivery is the second case, and it is the common one.
  if v_paid is distinct from 'paid' and v_status <> 'delivered' then
    return jsonb_build_object('queued', false, 'reason', 'not_paid');
  end if;
  if v_source <> 'online' then
    return jsonb_build_object('queued', false, 'reason', 'not_online');
  end if;
  if v_emailed_at is not null then
    return jsonb_build_object(
      'queued', false,
      'reason', 'already_sent',
      'to', v_order ->> 'receipt_email_to'
    );
  end if;
  if v_attempts >= public.order_receipt_max_attempts() then
    return jsonb_build_object(
      'queued', false,
      'reason', 'exhausted',
      'attempts', v_attempts,
      'error', v_order ->> 'receipt_email_last_error'
    );
  end if;
  if v_sending is not null and v_sending > now() - public.order_receipt_lease() then
    return jsonb_build_object('queued', false, 'reason', 'in_flight');
  end if;
  if v_next is not null and v_next > now() then
    return jsonb_build_object(
      'queued', false,
      'reason', 'retry_wait',
      'next_attempt_at', v_next,
      'attempts', v_attempts
    );
  end if;

  -- The address: what the till recorded for this order, else the account's.
  if v_email is null and v_customer is not null then
    select nullif(btrim(coalesce(p.email, '')), '') into v_email
      from public.profiles p
     where p.id = v_customer;
  end if;
  if v_email is null then
    return jsonb_build_object('queued', false, 'reason', 'no_email');
  end if;

  if not exists (select 1 from pg_extension where extname = 'pg_net') then
    return jsonb_build_object('queued', false, 'reason', 'not_configured');
  end if;

  select nullif(btrim(ds.decrypted_secret), '') into v_url
    from vault.decrypted_secrets ds
   where ds.name = 'receipt_function_url'
   limit 1;

  if v_url is null then
    return jsonb_build_object('queued', false, 'reason', 'not_configured');
  end if;

  select nullif(btrim(ds.decrypted_secret), '') into v_key
    from vault.decrypted_secrets ds
   where ds.name = 'service_role_key'
   limit 1;

  -- Take the lease under a row lock. Two dispatches racing for the same order
  -- (the delivered trigger and the sweep) cannot both win: the loser sees the
  -- freshly written lease and answers 'in_flight'.
  update public.orders o
     set receipt_email_sending_since = now()
   where o.id = p_order_id
     and o.receipt_emailed_at is null
     and (
       o.receipt_email_sending_since is null
       or o.receipt_email_sending_since < now() - public.order_receipt_lease()
     )
  returning true into v_claimed;

  if not coalesce(v_claimed, false) then
    return jsonb_build_object('queued', false, 'reason', 'in_flight');
  end if;

  begin
    select net.http_post(
      url := v_url,
      body := jsonb_build_object('order_id', p_order_id),
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || coalesce(v_key, '')
      ),
      timeout_milliseconds := 15000
    ) into v_request_id;
  exception when others then
    -- Nothing left the database: release the lease so the sweep is not blocked
    -- for five minutes by a claim nothing owns.
    update public.orders o
       set receipt_email_sending_since = null
     where o.id = p_order_id;
    raise;
  end;

  return jsonb_build_object(
    'queued', true,
    'reason', 'queued',
    'to', v_email,
    'attempt', v_attempts + 1,
    'request_id', v_request_id
  );
end;
$$;

comment on function public.queue_order_receipt_email(uuid) is
  'Dispatches the customer receipt email for one paid OR delivered online order through pg_net -> the send-order-receipt edge function. Returns {queued, reason, to}; never raises. Honours the in-flight lease and the retry backoff, so a stuck order is never mailed twice. The only path that emails an online receipt.';

revoke all on function public.queue_order_receipt_email(uuid)
  from public, anon, authenticated;

-- ──────────────────────────────────────────────────────────────────
-- 2. The delivered trigger
--
--    The seller's handover is the receipt's moment. Only the transition INTO
--    delivered fires (a second edit to an already delivered order does not),
--    and only for online orders — the POS till has its own receipt actions and
--    never uses this status.
-- ──────────────────────────────────────────────────────────────────
drop trigger if exists trg_order_receipt_on_delivered on public.orders;
create trigger trg_order_receipt_on_delivered
  after update of status on public.orders
  for each row
  when (
    new.status = 'delivered'
    and old.status is distinct from 'delivered'
    and coalesce(new.source, '') = 'online'
  )
  execute function public.trg_request_order_receipt_email();

comment on trigger trg_order_receipt_on_delivered on public.orders is
  'Emails the customer their receipt when the seller marks an online order delivered — no cashier step, no typing. A stamped order (already mailed at payment) is a no-op, so the customer is never mailed twice.';

-- ──────────────────────────────────────────────────────────────────
-- 3. The seller's button
--
--    One tap, the address the database already knows. It ignores a pending
--    retry clock (a human is asking now) and gives an exhausted order a fresh
--    budget, but it cannot bypass the stamp or a send already in flight.
-- ──────────────────────────────────────────────────────────────────
create or replace function public.send_order_receipt_to_customer(
  p_order_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_store  uuid;
  v_result jsonb;
begin
  select o.store_id into v_store
    from public.orders o
   where o.id = p_order_id;

  if v_store is null then
    return jsonb_build_object('queued', false, 'reason', 'order_missing');
  end if;

  -- Only the store that made the sale (or an admin) may mail its customer.
  if not exists (
    select 1 from public.stores s
     where s.id = v_store
       and s.owner_id = auth.uid()
  ) and not public.is_admin() then
    raise exception 'Only the store that made this sale can email its receipt'
      using errcode = '42501';
  end if;

  -- A deliberate send is not a scheduled one: clear the backoff and the
  -- give-up counter. The stamp (already_sent) and the lease (in_flight) still
  -- decide whether anything actually goes out.
  update public.orders
     set receipt_email_next_attempt_at = null,
         receipt_email_attempts        = 0
   where id = p_order_id
     and receipt_emailed_at is null;

  v_result := public.queue_order_receipt_email(p_order_id);
  return v_result;
end;
$$;

comment on function public.send_order_receipt_to_customer(uuid) is
  'Emails one order''s receipt to the address on file — orders.customer_email if the till recorded one, else the customer''s registered profiles.email. Store-owner (or admin) only; returns the dispatcher''s {queued, reason, to}. Idempotent: an order already stamped answers already_sent.';

revoke all on function public.send_order_receipt_to_customer(uuid)
  from public, anon;

grant execute on function public.send_order_receipt_to_customer(uuid)
  to authenticated;

-- ──────────────────────────────────────────────────────────────────
-- 4. The retry sweep — same rule, so a delivery receipt retries too
--
--    Re-stated from 20261119120000 with `paid OR delivered`. The two passes and
--    the lease accounting are unchanged.
-- ──────────────────────────────────────────────────────────────────
create or replace function public.retry_order_receipt_emails(
  p_limit integer default 20
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_limit    integer := greatest(1, least(coalesce(p_limit, 20), 100));
  v_order    record;
  v_result   jsonb;
  v_queued   integer := 0;
  v_waiting  integer := 0;
  v_skipped  integer := 0;
  v_orphaned integer := 0;
  v_outcomes jsonb := '[]'::jsonb;
begin
  -- (a) dead leases: dispatched, never reported back.
  for v_order in
    select o.id
      from public.orders o
     where (o.payment_status = 'paid' or o.status = 'delivered')
       and coalesce(o.source, '') = 'online'
       and o.receipt_emailed_at is null
       and coalesce(o.receipt_email_attempts, 0) < public.order_receipt_max_attempts()
       and o.receipt_email_sending_since is not null
       and o.receipt_email_sending_since < now() - public.order_receipt_lease()
       and o.receipt_email_sending_since
             > coalesce(o.receipt_email_last_attempt_at, '-infinity'::timestamptz)
     order by o.receipt_email_sending_since
     limit v_limit
     -- This sweep also runs inside the payment/delivery trigger, so two
     -- transitions can sweep at once. Skipping rows another transaction
     -- already holds is what stops the two from deadlocking.
     for update of o skip locked
  loop
    perform public.record_order_receipt_failure(
      v_order.id,
      'send-order-receipt did not answer before its lease expired',
      true
    );
    v_orphaned := v_orphaned + 1;
  end loop;

  -- (b) everything due. The address is resolved here too, so an order with no
  -- address is never selected — that refusal is not a send failure and must not
  -- eat an attempt.
  for v_order in
    select o.id
      from public.orders o
      left join public.profiles p on p.id = o.customer_id
     where (o.payment_status = 'paid' or o.status = 'delivered')
       and coalesce(o.source, '') = 'online'
       and o.receipt_emailed_at is null
       and coalesce(o.receipt_email_attempts, 0) < public.order_receipt_max_attempts()
       and (
         o.receipt_email_sending_since is null
         or o.receipt_email_sending_since < now() - public.order_receipt_lease()
       )
       and (
         o.receipt_email_next_attempt_at is null
         or o.receipt_email_next_attempt_at <= now()
       )
       and coalesce(
             nullif(btrim(coalesce(o.customer_email, '')), ''),
             nullif(btrim(coalesce(p.email, '')), '')
           ) is not null
     order by o.receipt_email_next_attempt_at nulls first, o.created_at
     limit v_limit
     for update of o skip locked
  loop
    v_result := public.queue_order_receipt_email(v_order.id);

    if coalesce((v_result ->> 'queued')::boolean, false) then
      v_queued := v_queued + 1;
    elsif v_result ->> 'reason' = 'retry_wait' then
      v_waiting := v_waiting + 1;
    else
      v_skipped := v_skipped + 1;
    end if;

    v_outcomes := v_outcomes || jsonb_build_object(
      'order_id', v_order.id,
      'result', v_result
    );
  end loop;

  return jsonb_build_object(
    'queued', v_queued,
    'waiting', v_waiting,
    'skipped', v_skipped,
    'orphaned', v_orphaned,
    'outcomes', v_outcomes
  );
end;
$$;

comment on function public.retry_order_receipt_emails(integer) is
  'Retries receipt emails that failed or never answered, for paid or delivered online orders: books expired leases as failed attempts, then re-dispatches whatever is due. Idempotent — the stamp and the lease decide. Run by pg_cron, by the payment/delivery trigger, or by hand after fixing SMTP.';

revoke all on function public.retry_order_receipt_emails(integer)
  from public, anon, authenticated;

commit;
