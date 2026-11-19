-- ══════════════════════════════════════════════════════════════════
-- 20261119110000_order_receipt_email.sql
--
-- Online customers had no receipt at all. The PDF/print/share/Gmail work
-- lives in the seller's POS flow and only fires when a cashier taps Email and
-- then Send in Gmail; an order placed in the app produced a tracking screen
-- and nothing else. Nothing emailed a customer after checkout, after GCash
-- verification, or after delivery.
--
-- This file makes the email a fact of the order, not of a phone:
--
--   1. `orders.receipt_emailed_at` / `receipt_email_to` — when and where the
--      receipt went, so a retried dispatch is a no-op and support can answer
--      "was it sent?" without reading mail logs.
--   2. `queue_order_receipt_email(order)` — the one dispatcher. It decides
--      whether this order owes a receipt at all (online, paid, addressed, not
--      already sent), resolves the address (orders.customer_email first, then
--      the customer's account email), and hands the order id to the
--      `send-order-receipt` edge function through pg_net.
--   3. Two triggers on `orders` — INSERT for an order born paid, UPDATE OF
--      payment_status for the ordinary GCash/COD path — both restricted to
--      `source = 'online'` and to a transition INTO 'paid'. The POS till keeps
--      its manual receipt actions and is not touched.
--
-- The function is deliberately forgiving: a missing pg_net, a missing Vault
-- entry, or a dead edge function must never fail the payment update that
-- triggered it. Each of those returns a `reason` instead, and the trigger
-- swallows anything that still escapes as a WARNING.
--
-- Requires two Vault secrets (the edge function does the sending):
--   receipt_function_url  the deployed function URL, e.g.
--                         https://<project-ref>.supabase.co/functions/v1/send-order-receipt
--   service_role_key      the project's service_role key, sent as the bearer
--                         token so the function can refuse everyone else
--
-- Both are read at dispatch time, so they can be added after this migration
-- (and rotated without touching SQL). Add them with:
--   select vault.create_secret('<url>', 'receipt_function_url');
--   select vault.create_secret('<service role key>', 'service_role_key');
--
-- Additive and idempotent. Nothing breaks while it is unapplied: the app never
-- calls this path, and no existing order gains a stamp.
-- ══════════════════════════════════════════════════════════════════

begin;

-- ──────────────────────────────────────────────────────────────────
-- 1. pg_net — the HTTP client a trigger can use
--    Guarded: a database without the extension still applies the rest, and
--    the dispatcher then answers 'not_configured' instead of raising.
-- ──────────────────────────────────────────────────────────────────
do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_net') then
    begin
      create extension pg_net;
    exception when others then
      raise warning 'pg_net could not be enabled (%): online receipts will not dispatch', sqlerrm;
    end;
  end if;
end $$;

-- ──────────────────────────────────────────────────────────────────
-- 2. The paper trail on the order
--    customer_email arrives in 20261119100000; repeated here (IF NOT EXISTS)
--    so this file is safe to apply on its own.
-- ──────────────────────────────────────────────────────────────────
alter table public.orders
  add column if not exists customer_email     text,
  add column if not exists receipt_emailed_at timestamptz,
  add column if not exists receipt_email_to   text;

comment on column public.orders.receipt_emailed_at is
  'When the customer''s receipt email was sent for this order. NULL = never sent. Set by the send-order-receipt edge function after SMTP accepts the message, which is what makes a retried dispatch a no-op.';
comment on column public.orders.receipt_email_to is
  'The address the receipt was actually sent to (orders.customer_email if set, otherwise the customer''s account email). Kept because the account email can change later.';

-- ──────────────────────────────────────────────────────────────────
-- 3. The dispatcher
--
--    Returns jsonb {queued, reason, to} rather than raising: the caller is a
--    trigger on a payment update, and no receipt problem may fail a payment.
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
  v_source       text;
  v_emailed_at   text;
  v_customer     uuid;
  v_email        text;
  v_url          text;
  v_key          text;
  v_request_id   bigint;
begin
  -- to_jsonb keeps this function working on a database where customer_email
  -- has not been added yet: the key is simply absent.
  select to_jsonb(o) into v_order
    from public.orders o
   where o.id = p_order_id;

  if v_order is null then
    return jsonb_build_object('queued', false, 'reason', 'order_missing');
  end if;

  v_paid       := v_order ->> 'payment_status';
  v_source     := coalesce(v_order ->> 'source', '');
  v_emailed_at := v_order ->> 'receipt_emailed_at';
  v_customer   := (v_order ->> 'customer_id')::uuid;
  v_email      := nullif(btrim(coalesce(v_order ->> 'customer_email', '')), '');

  if v_paid is distinct from 'paid' then
    return jsonb_build_object('queued', false, 'reason', 'not_paid');
  end if;
  if v_source <> 'online' then
    return jsonb_build_object('queued', false, 'reason', 'not_online');
  end if;
  if v_emailed_at is not null then
    return jsonb_build_object('queued', false, 'reason', 'already_sent');
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

  -- pg_net returns the request id immediately; the response lands in
  -- net._http_response when the worker has it.
  select net.http_post(
    url := v_url,
    body := jsonb_build_object('order_id', p_order_id),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || coalesce(v_key, '')
    ),
    timeout_milliseconds := 15000
  ) into v_request_id;

  return jsonb_build_object(
    'queued', true,
    'reason', 'queued',
    'to', v_email,
    'request_id', v_request_id
  );
end;
$$;

comment on function public.queue_order_receipt_email(uuid) is
  'Dispatches the customer receipt email for one paid online order through pg_net -> the send-order-receipt edge function. Returns {queued, reason, to}; never raises. The only path that emails an online receipt.';

-- Server-internal: called by the trigger, not by clients.
revoke all on function public.queue_order_receipt_email(uuid)
  from public, anon, authenticated;

-- ──────────────────────────────────────────────────────────────────
-- 4. The triggers
--
--    Only a transition INTO paid fires, and only for online orders: the POS
--    sale is already 'paid' when it is inserted and keeps its manual actions.
-- ──────────────────────────────────────────────────────────────────
create or replace function public.trg_request_order_receipt_email()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- A receipt problem must never roll back the payment that produced it.
  begin
    perform public.queue_order_receipt_email(new.id);
  exception when others then
    raise warning 'receipt email dispatch failed for order %: %', new.id, sqlerrm;
  end;
  return new;
end;
$$;

drop trigger if exists trg_order_receipt_on_insert on public.orders;
create trigger trg_order_receipt_on_insert
  after insert on public.orders
  for each row
  when (new.payment_status = 'paid' and coalesce(new.source, '') = 'online')
  execute function public.trg_request_order_receipt_email();

drop trigger if exists trg_order_receipt_on_paid on public.orders;
create trigger trg_order_receipt_on_paid
  after update of payment_status on public.orders
  for each row
  when (
    new.payment_status = 'paid'
    and old.payment_status is distinct from 'paid'
    and coalesce(new.source, '') = 'online'
  )
  execute function public.trg_request_order_receipt_email();

comment on trigger trg_order_receipt_on_paid on public.orders is
  'Emails the customer their receipt when an online order becomes paid (GCash verification, COD settlement). POS orders are excluded — the till sends its own.';

commit;
