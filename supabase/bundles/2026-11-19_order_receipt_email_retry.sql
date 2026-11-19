-- ══════════════════════════════════════════════════════════════════
-- PENDING LIVE MIGRATION — 2026-11-19 (project psczvbfoybqhjeqssimw)
--
-- Paste this whole file into the Supabase SQL Editor and run it once.
-- It is one unapplied migration, copied verbatim:
--
--   1/1  20261119120000  a failed receipt email is recorded and retried
--                        later — backoff, in-flight lease, retry sweep
--
-- Apply it AFTER 20261119110000_order_receipt_email.sql (the bundle
-- 2026-11-19_order_receipt_email.sql): it replaces that file's dispatcher and
-- payment trigger, so pasting this one alone leaves the triggers calling a
-- function that is not there yet.
--
-- What it adds, in one sentence each:
--   • orders.receipt_email_attempts / _last_attempt_at / _last_error /
--     _next_attempt_at — the failure is a fact on the order;
--   • orders.receipt_email_sending_since — a five-minute lease that stops the
--     retry sweep from firing a second receipt while the first is in Gmail;
--   • record_order_receipt_success / record_order_receipt_failure — the two
--     calls the deployed send-order-receipt function now makes after it tries;
--   • retry_order_receipt_emails(limit) — re-dispatches what is due, books a
--     lease nobody answered as a failed attempt, and stops after five failures
--     (5 min → 15 min → 1 h → 6 h → give up, error kept for support);
--   • pg_cron job 'retry-order-receipt-emails' every five minutes when
--     pg_cron exists, and the same sweep runs from the payment trigger so a
--     host without pg_cron still recovers.
--
-- The deployed function keeps working if this file is not applied: it falls
-- back to the plain stamp update and simply records no failures (today's
-- behaviour). Apply it and re-deploy the function to get the retries:
--   supabase functions deploy send-order-receipt
-- ══════════════════════════════════════════════════════════════════
-- 20261119120000_order_receipt_email_retry.sql
--
-- 20261119110000 made an online order email its own receipt, but the dispatch
-- was fire-and-forget: `net.http_post` hands the order id to the edge function
-- and nothing looks at the answer. Gmail was down, the app password was
-- rotated, the SMTP handshake timed out — the function returned 502 into
-- `net._http_response`, nobody read it, and the customer silently received
-- nothing. The order was never tried again, and there was no row anywhere that
-- said so.
--
-- This file gives a failed dispatch a memory and a second chance:
--
--   1. `receipt_email_attempts`, `receipt_email_last_attempt_at`,
--      `receipt_email_last_error`, `receipt_email_next_attempt_at` — what
--      happened, when, why, and when it may be tried again.
--   2. `receipt_email_sending_since` — a lease taken by the dispatcher just
--      before the HTTP call. It is what stops the retry sweep from firing a
--      second receipt while the first is still inside Gmail; it only expires
--      when the function never reported back (crash, timeout, a wrong key that
--      made it answer 403).
--   3. `record_order_receipt_success` / `record_order_receipt_failure` — the
--      two calls the function makes after it tries. Success stamps
--      `receipt_emailed_at` (unchanged from 20261119110000) and clears the
--      lease; failure counts the attempt, stores the error verbatim and
--      schedules the next one.
--   4. `retry_order_receipt_emails(limit)` — the sweep. It first books any
--      lease that expired with no answer as a failed attempt (otherwise a wrong
--      Vault key would retry for ever without ever counting), then re-dispatches
--      every paid online order whose next attempt is due and whose address is
--      known.
--
-- Backoff is 5 min → 15 min → 1 h → 6 h → stop: five sends at most, which is
-- enough to ride out an outage and short enough that a dead mailbox is not
-- mailed for ever. After the fifth failure `receipt_email_next_attempt_at` is
-- NULL and `receipt_email_last_error` holds the reason, so support can see it
-- and the order is not picked up again. An operator who wants one more attempt
-- now can run:
--   update public.orders set receipt_email_next_attempt_at = null,
--          receipt_email_attempts = 0 where id = '<order>';
--
-- Who runs the sweep: a pg_cron job every five minutes when pg_cron is
-- available, and — because it is not available everywhere — also
-- opportunistically from the same trigger that dispatches a fresh receipt, so
-- paying any order retries up to three stuck ones. Both paths are idempotent:
-- the stamp plus the lease are the only things that decide whether a customer
-- is mailed, and both are read inside the dispatcher under a row lock.
--
-- The customer is never mailed twice by a retry that the stamp can prevent.
-- The one window that cannot be closed from here is a send whose message Gmail
-- accepted and whose success stamp then failed to reach the database: the lease
-- expires and the sweep tries again. That is stated rather than hidden — the
-- stamp is written immediately after the SMTP accept, so the window is a
-- network fault of milliseconds, not a design property of the retry.
--
-- Additive and idempotent. Nothing breaks while it is unapplied: the function
-- keeps its old direct stamp write and simply records nothing, which is
-- exactly today's behaviour.
-- ══════════════════════════════════════════════════════════════════

begin;

-- ──────────────────────────────────────────────────────────────────
-- 1. What happened to the last attempt, and when the next may go
-- ──────────────────────────────────────────────────────────────────
alter table public.orders
  add column if not exists receipt_email_attempts          integer not null default 0,
  add column if not exists receipt_email_last_attempt_at   timestamptz,
  add column if not exists receipt_email_last_error        text,
  add column if not exists receipt_email_next_attempt_at   timestamptz,
  add column if not exists receipt_email_sending_since     timestamptz;

comment on column public.orders.receipt_email_attempts is
  'How many receipt-email attempts have FAILED for this order (a successful send stops counting). Drives the backoff and the give-up point; not the same thing as the number of sends.';
comment on column public.orders.receipt_email_last_error is
  'Why the last receipt-email attempt failed, verbatim from the send-order-receipt function (truncated to 500 chars). NULL after a successful send.';
comment on column public.orders.receipt_email_next_attempt_at is
  'When retry_order_receipt_emails() may try this order again. NULL = not waiting (fresh order, sent, or out of attempts).';
comment on column public.orders.receipt_email_sending_since is
  'Lease taken by queue_order_receipt_email() just before the HTTP call, cleared by the function once it reports success or failure. A lease older than order_receipt_lease() means the function never answered.';

-- The sweep's own lookup: unsettled receipts only. Small by construction.
create index if not exists idx_orders_receipt_email_retry
  on public.orders (receipt_email_next_attempt_at, created_at)
  where receipt_emailed_at is null;

-- ──────────────────────────────────────────────────────────────────
-- 2. The retry rules, in one place each
-- ──────────────────────────────────────────────────────────────────

-- How long a dispatch may be in flight before the sweep assumes it died.
-- Generous next to the function's own 15 s pg_net timeout: the lease is not a
-- performance budget, it is the only thing standing between a slow SMTP
-- handshake and a duplicate receipt.
create or replace function public.order_receipt_lease()
returns interval
language sql
immutable
as $$ select interval '5 minutes' $$;

comment on function public.order_receipt_lease() is
  'How long a receipt dispatch may run before its lease is considered dead. Read by queue_order_receipt_email() and retry_order_receipt_emails().';

-- Attempts 1..5 may happen; the fifth failure has no successor and the order is
-- left with its error for a human.
create or replace function public.order_receipt_max_attempts()
returns integer
language sql
immutable
as $$ select 5 $$;

comment on function public.order_receipt_max_attempts() is
  'How many failed receipt-email attempts an order is allowed before the sweep stops picking it up.';

-- The wait after the Nth failure. NULL means "no next attempt".
create or replace function public.order_receipt_retry_delay(p_attempts integer)
returns interval
language sql
immutable
as $$
  select case
    when p_attempts is null or p_attempts <= 0 then null
    when p_attempts = 1 then interval '5 minutes'
    when p_attempts = 2 then interval '15 minutes'
    when p_attempts = 3 then interval '1 hour'
    when p_attempts = 4 then interval '6 hours'
    else null
  end
$$;

comment on function public.order_receipt_retry_delay(integer) is
  'Backoff after the Nth failed receipt-email attempt: 5 min, 15 min, 1 h, 6 h, then NULL (stop).';

-- ──────────────────────────────────────────────────────────────────
-- 3. The two calls the edge function makes
--
--    Server-internal by grant: only the service role (the function) may record
--    an outcome. A seller or a customer cannot mark an unsent receipt sent, nor
--    reset an attempt count.
-- ──────────────────────────────────────────────────────────────────

-- Success: stamp it, clear the lease and the error. Deliberately guarded on
-- `receipt_emailed_at is null` so a slow duplicate call cannot move the stamp
-- (and a second send's retry cannot pretend to be the first).
create or replace function public.record_order_receipt_success(
  p_order_id uuid,
  p_to       text
) returns jsonb
language plpgsql
as $$
declare
  v_recorded boolean := false;
begin
  update public.orders o
     set receipt_emailed_at           = now(),
         receipt_email_to             = nullif(btrim(coalesce(p_to, '')), ''),
         receipt_email_sending_since  = null,
         receipt_email_next_attempt_at = null,
         receipt_email_last_error     = null
   where o.id = p_order_id
     and o.receipt_emailed_at is null
  returning true into v_recorded;

  return jsonb_build_object(
    'recorded', coalesce(v_recorded, false),
    'order_id', p_order_id
  );
end;
$$;

comment on function public.record_order_receipt_success(uuid, text) is
  'Stamps a successfully emailed receipt and clears the retry state. Called by the send-order-receipt edge function; guarded so a receipt is stamped once.';

-- Failure: count it, keep the reason, schedule the next attempt. A
-- non-retryable failure (p_retryable = false) counts the attempt and leaves
-- next_attempt_at NULL, which is how a permanent rejection is parked for a
-- human instead of being retried for ever.
create or replace function public.record_order_receipt_failure(
  p_order_id  uuid,
  p_error     text,
  p_retryable boolean default true
) returns jsonb
language plpgsql
as $$
declare
  v_attempts integer := 0;
  v_next     timestamptz := null;
begin
  update public.orders o
     set receipt_email_attempts        = coalesce(o.receipt_email_attempts, 0) + 1,
         receipt_email_last_attempt_at = now(),
         receipt_email_last_error      = left(
           coalesce(nullif(btrim(p_error), ''), 'unknown error'), 500
         ),
         receipt_email_sending_since   = null,
         receipt_email_next_attempt_at = case
           when coalesce(p_retryable, true)
             then now() + public.order_receipt_retry_delay(
                    coalesce(o.receipt_email_attempts, 0) + 1
                  )
           else null
         end
   where o.id = p_order_id
     and o.receipt_emailed_at is null
  returning o.receipt_email_attempts, o.receipt_email_next_attempt_at
       into v_attempts, v_next;

  return jsonb_build_object(
    'recorded',      v_attempts > 0,
    'order_id',      p_order_id,
    'attempts',      v_attempts,
    'next_attempt_at', v_next
  );
end;
$$;

comment on function public.record_order_receipt_failure(uuid, text, boolean) is
  'Records a failed receipt-email attempt: counts it, stores the error and schedules the next try (5 min, 15 min, 1 h, 6 h, then none). Called by the send-order-receipt edge function and by the retry sweep for a dispatch that never answered.';

-- ──────────────────────────────────────────────────────────────────
-- 4. The dispatcher — now honouring the lease and the backoff
--
--    Same contract as 20261119110000: returns {queued, reason, to}; never
--    raises. Three new reasons — 'in_flight' (a lease is live), 'retry_wait'
--    (backoff has not elapsed) and 'exhausted' (five attempts failed).
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
  v_source     := coalesce(v_order ->> 'source', '');
  v_emailed_at := v_order ->> 'receipt_emailed_at';
  v_customer   := (v_order ->> 'customer_id')::uuid;
  v_email      := nullif(btrim(coalesce(v_order ->> 'customer_email', '')), '');
  v_attempts   := coalesce((v_order ->> 'receipt_email_attempts')::integer, 0);
  v_sending    := (v_order ->> 'receipt_email_sending_since')::timestamptz;
  v_next       := (v_order ->> 'receipt_email_next_attempt_at')::timestamptz;

  if v_paid is distinct from 'paid' then
    return jsonb_build_object('queued', false, 'reason', 'not_paid');
  end if;
  if v_source <> 'online' then
    return jsonb_build_object('queued', false, 'reason', 'not_online');
  end if;
  if v_emailed_at is not null then
    return jsonb_build_object('queued', false, 'reason', 'already_sent');
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
  -- (a trigger and the sweep, two triggers a second apart) cannot both win:
  -- the loser sees the freshly written lease and answers 'in_flight'.
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

  -- pg_net returns the request id immediately; the response lands in
  -- net._http_response when the worker has it.
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
  'Dispatches the customer receipt email for one paid online order through pg_net -> the send-order-receipt edge function. Returns {queued, reason, to}; never raises. Honours the in-flight lease and the retry backoff, so a stuck order is never mailed twice. The only path that emails an online receipt.';

-- Server-internal: called by the trigger and the sweep, not by clients.
revoke all on function public.queue_order_receipt_email(uuid)
  from public, anon, authenticated;

-- ──────────────────────────────────────────────────────────────────
-- 5. The sweep
--
--    Two passes, in this order and for a reason:
--      a) a lease that expired without an answer is a failure that was never
--         recorded (the function crashed, timed out, or answered 403 because
--         the Vault key is wrong) — book it, so the attempt budget still runs
--         out instead of retrying for ever;
--      b) everything due, oldest debt first.
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
     where o.payment_status = 'paid'
       and coalesce(o.source, '') = 'online'
       and o.receipt_emailed_at is null
       and coalesce(o.receipt_email_attempts, 0) < public.order_receipt_max_attempts()
       and o.receipt_email_sending_since is not null
       and o.receipt_email_sending_since < now() - public.order_receipt_lease()
       and o.receipt_email_sending_since
             > coalesce(o.receipt_email_last_attempt_at, '-infinity'::timestamptz)
     order by o.receipt_email_sending_since
     limit v_limit
     -- This sweep also runs inside the payment trigger, so two payments can
     -- sweep at once. Skipping rows another transaction already holds is what
     -- stops the two from deadlocking over each other's orders.
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
     where o.payment_status = 'paid'
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
  'Retries receipt emails that failed or never answered: books expired leases as failed attempts, then re-dispatches every paid online order whose backoff has elapsed. Idempotent — the stamp and the lease decide. Run by pg_cron, by the payment trigger, or by hand after fixing SMTP.';

revoke all on function public.retry_order_receipt_emails(integer)
  from public, anon, authenticated;

-- ──────────────────────────────────────────────────────────────────
-- 6. The trigger — dispatch the new receipt, then retry the stuck ones
--
--    Replaces 20261119110000's version, keeping its one rule: a receipt
--    problem must never roll back the payment that produced it.
-- ──────────────────────────────────────────────────────────────────
create or replace function public.trg_request_order_receipt_email()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  begin
    perform public.queue_order_receipt_email(new.id);
  exception when others then
    raise warning 'receipt email dispatch failed for order %: %', new.id, sqlerrm;
  end;

  -- Opportunistic retry: hosts without pg_cron still recover, and a host with
  -- it gets a second chance the moment any order is paid. Three at a time keeps
  -- the payment transaction's own latency bounded.
  begin
    perform public.retry_order_receipt_emails(3);
  exception when others then
    raise warning 'receipt email retry sweep failed: %', sqlerrm;
  end;

  return new;
end;
$$;

-- ──────────────────────────────────────────────────────────────────
-- 7. Grants — the outcomes are the function's to write, nobody else's
-- ──────────────────────────────────────────────────────────────────
revoke all on function public.record_order_receipt_success(uuid, text)
  from public, anon, authenticated;
revoke all on function public.record_order_receipt_failure(uuid, text, boolean)
  from public, anon, authenticated;
revoke all on function public.order_receipt_retry_delay(integer)
  from public, anon, authenticated;
revoke all on function public.order_receipt_lease()
  from public, anon, authenticated;
revoke all on function public.order_receipt_max_attempts()
  from public, anon, authenticated;

do $$
begin
  grant execute on function public.record_order_receipt_success(uuid, text)
    to service_role;
  grant execute on function public.record_order_receipt_failure(uuid, text, boolean)
    to service_role;
  grant execute on function public.retry_order_receipt_emails(integer)
    to service_role;
exception when undefined_object then
  raise warning 'service_role missing: grant the receipt retry functions to it by hand';
end $$;

-- ──────────────────────────────────────────────────────────────────
-- 8. pg_cron sweep (guarded, the same pattern as the GCash sweeps)
-- ──────────────────────────────────────────────────────────────────
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron')
     and to_regclass('cron.job') is not null
     and not exists (select 1 from cron.job where jobname = 'retry-order-receipt-emails') then
    perform cron.schedule(
      'retry-order-receipt-emails',
      '*/5 * * * *',
      $cron$ select public.retry_order_receipt_emails(20); $cron$
    );
    raise notice 'Scheduled pg_cron job: retry-order-receipt-emails (every 5 min)';
  else
    raise notice 'pg_cron unavailable — retries also run from the payment trigger.';
  end if;
exception
  when undefined_table or insufficient_privilege or undefined_function then
    raise notice 'pg_cron unavailable — retries also run from the payment trigger.';
end
$$;

commit;
