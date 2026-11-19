-- ══════════════════════════════════════════════════════════════════
-- 20261119260000_bulk_vouchers.sql
--
-- Vouchers worked on online orders and nowhere else, so a reseller asking for
-- 40 pairs paid full price on a promo the store was running. This makes a code
-- work on a bulk request the same way it works at checkout — resolved by the
-- same `voucher_evaluate`, subject to the same store scope, window, minimum
-- and usage caps — and makes the discount stick to what the customer owes.
--
-- Where the discount lands, precisely:
--
--   • The request stores the resolved discount (`voucher_discount`), not just
--     the code, exactly like `deposit_amount` is stored resolved. The store
--     therefore honours the price the customer was quoted even if the code
--     expires before the seller gets to the request.
--   • Approval computes the 70% deposit on (price × quantity − voucher
--     discount), so the customer does not pay a deposit on money they were
--     never charged.
--   • The remaining balance at pickup is the discounted value; the seller sees
--     the code on the request and its queue card.
--
-- Usage is consumed at REQUEST time, not at pickup. That is deliberate: the
-- discount changes the deposit quoted immediately, so the code has to be
-- claimed before it is spent elsewhere. The cost of that choice, stated
-- plainly: a request that is later declined, cancelled or expires keeps its
-- redemption (the same way a cancelled order keeps its own), and a customer
-- whose code has `per_user_limit = 1` cannot reuse it on a re-request.
--
-- Requires 20260915120000 + 20260915130000 (vouchers + voucher_evaluate).
-- Read-only against those tables; this file adds the bulk side.
--
-- Additive and idempotent.
-- ══════════════════════════════════════════════════════════════════

begin;

-- ──────────────────────────────────────────────────────────────────
-- 1. The voucher a request was made with
-- ──────────────────────────────────────────────────────────────────
alter table public.bulk_reservations
  add column if not exists voucher_code     text,
  add column if not exists voucher_discount numeric,
  add column if not exists voucher_id       uuid;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'bulk_reservations_voucher_discount_non_negative'
  ) then
    alter table public.bulk_reservations
      add constraint bulk_reservations_voucher_discount_non_negative
      check (voucher_discount is null or voucher_discount >= 0);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'bulk_reservations_voucher_id_fkey'
  ) then
    alter table public.bulk_reservations
      add constraint bulk_reservations_voucher_id_fkey
      foreign key (voucher_id) references public.vouchers(id) on delete set null;
  end if;
end $$;

comment on column public.bulk_reservations.voucher_code is
  'Normalized voucher code snapshotted at request time. Shown to the customer and the store; kept after the voucher is edited or deactivated.';
comment on column public.bulk_reservations.voucher_discount is
  'Peso discount RESOLVED at request time by voucher_evaluate() — not recomputed later, so the store honours the quote even if the code expires. The 70% deposit is computed on (price × quantity − this).';
comment on column public.bulk_reservations.voucher_id is
  'Voucher row that was claimed by this request. ON DELETE SET NULL — voucher_code above is what history reads.';

-- ──────────────────────────────────────────────────────────────────
-- 2. Redemptions: one ledger, two kinds of claim
--    A bulk request has no order, so `order_id` becomes nullable and a
--    `reservation_id` carries the bulk case. Exactly one of them is set —
--    a redemption always points at the thing it discounted, never both and
--    never neither. The existing UNIQUE (voucher_id, order_id) still holds
--    for orders (Postgres treats NULLs as distinct, so bulk rows do not
--    collide in it); the partial index below is its bulk twin.
-- ──────────────────────────────────────────────────────────────────
alter table public.voucher_redemptions
  alter column order_id drop not null;

alter table public.voucher_redemptions
  add column if not exists reservation_id uuid;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'voucher_redemptions_reservation_id_fkey'
  ) then
    alter table public.voucher_redemptions
      add constraint voucher_redemptions_reservation_id_fkey
      foreign key (reservation_id) references public.bulk_reservations(id)
      on delete cascade;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'voucher_redemptions_one_target'
  ) then
    alter table public.voucher_redemptions
      add constraint voucher_redemptions_one_target
      check (num_nonnulls(order_id, reservation_id) = 1);
  end if;
end $$;

create unique index if not exists uq_voucher_redemptions_reservation
  on public.voucher_redemptions (voucher_id, reservation_id)
  where reservation_id is not null;

comment on column public.voucher_redemptions.reservation_id is
  'The bulk reservation this voucher was claimed by. NULL for order redemptions; exactly one of order_id / reservation_id is set.';

-- ──────────────────────────────────────────────────────────────────
-- 3. The request RPC, now with an optional voucher
--
--    The 5-argument version is dropped first: a 6-argument function with a
--    default is a DIFFERENT function to Postgres, and leaving both would make
--    a 5-key RPC call ambiguous ("could not choose the best candidate").
-- ──────────────────────────────────────────────────────────────────
drop function if exists public.request_bulk_reservation(uuid, uuid, integer, jsonb, text);

create or replace function public.request_bulk_reservation(
    p_product_id UUID,
    p_store_id UUID,
    p_quantity INTEGER,
    p_requested_sizes JSONB DEFAULT '[]'::jsonb,
    p_note TEXT DEFAULT NULL,
    p_voucher_code TEXT DEFAULT NULL
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
    v_customer   UUID := auth.uid();
    v_available  INTEGER;
    v_id         UUID;
    v_minimum    INTEGER := public.bulk_minimum_quantity();
    v_code       TEXT := nullif(upper(btrim(coalesce(p_voucher_code, ''))), '');
    v_price      NUMERIC;
    v_subtotal   NUMERIC;
    v_verdict    jsonb;
    v_discount   NUMERIC := 0;
begin
    if v_customer is null then
        raise exception 'NOT_AUTHENTICATED';
    end if;
    if p_quantity is null or p_quantity < 1 then
        raise exception 'INVALID_QUANTITY';
    end if;
    if p_quantity < v_minimum then
        raise exception 'BULK_MINIMUM_QUANTITY (%)', v_minimum;
    end if;

    if not exists (
        select 1 from public.products
        where id = p_product_id
          and store_id = p_store_id
          and is_active = true
    ) then
        raise exception 'PRODUCT_NOT_FOUND';
    end if;

    select coalesce(sum(stock), 0) into v_available
    from public.inventory where product_id = p_product_id;
    if v_available < p_quantity then
        raise exception 'INSUFFICIENT_STOCK (%) < %', v_available, p_quantity;
    end if;

    -- One live request per customer per product at a time.
    if exists (
        select 1 from public.bulk_reservations
        where customer_id = v_customer
          and product_id = p_product_id
          and status in ('pending', 'awaiting_deposit', 'approved')
    ) then
        raise exception 'RESERVATION_ALREADY_EXISTS';
    end if;

    -- ── The voucher, resolved NOW ─────────────────────────────────
    -- Same evaluator as checkout, with `p_lock = true`: the row is locked for
    -- the rest of this transaction, so two concurrent requests cannot both
    -- pass a max_uses / per_user_limit check and then both claim it.
    if v_code is not null then
        select public.product_effective_price(
                 p.price, p.sale_price, p.sale_starts_at, p.sale_ends_at, now())
          into v_price
          from public.products p
         where p.id = p_product_id;

        v_subtotal := coalesce(v_price, 0) * p_quantity;

        v_verdict := public.voucher_evaluate(
            v_code, v_subtotal, p_store_id, v_customer, true
        );

        if not coalesce((v_verdict->>'ok')::boolean, false) then
            -- The app validated the code before sending, so landing here means
            -- the code changed under the customer (used up, expired, store
            -- limit). The reason travels in the message; the prefix keeps the
            -- client able to tell this apart from a stock failure.
            raise exception 'VOUCHER_REJECTED %: %',
                coalesce(v_verdict->>'reason', 'invalid_code'),
                coalesce(v_verdict->>'message', 'That code cannot be used on this request.');
        end if;

        v_discount := coalesce((v_verdict->>'discount_amount')::numeric, 0);
    end if;

    insert into public.bulk_reservations (
        customer_id, store_id, product_id, quantity,
        requested_sizes, note, status,
        voucher_code, voucher_id, voucher_discount
    ) values (
        v_customer, p_store_id, p_product_id, p_quantity,
        p_requested_sizes, p_note, 'pending',
        case when v_code is null then null else v_verdict->>'code' end,
        case when v_code is null then null else (v_verdict->>'voucher_id')::uuid end,
        case when v_code is null then null else v_discount end
    ) returning id into v_id;

    -- ── Claim the use ─────────────────────────────────────────────
    -- Same two writes the orders trigger makes (redemption row + uses_count),
    -- pointed at the reservation because a bulk request is not an order.
    if v_code is not null and v_discount > 0 then
        insert into public.voucher_redemptions (
            voucher_id, code, customer_id, reservation_id, store_id,
            discount_amount, funded_by
        ) values (
            (v_verdict->>'voucher_id')::uuid,
            v_verdict->>'code',
            v_customer,
            v_id,
            p_store_id,
            v_discount,
            coalesce(v_verdict->>'funded_by', 'store')
        );

        update public.vouchers
           set uses_count = uses_count + 1
         where id = (v_verdict->>'voucher_id')::uuid;
    end if;

    -- ⚠️ `and s.owner_id is not null` is a RECIPIENT guard: `stores.owner_id` is
    -- NULLABLE and `notifications.user_id` is NOT NULL, so a store with no owner
    -- would fail the CUSTOMER's request outright — the reservation insert above
    -- and this statement are one transaction, so nothing would be requested at
    -- all. An ownerless store simply has nobody to tell.
    insert into public.notifications (user_id, category, title, message)
    select s.owner_id, 'reservations',
           'New bulk reservation request',
           'A customer requested ' || p_quantity || ' units of ' ||
           coalesce(p.name, 'a product') || ' for resale.' ||
           case when v_code is null then ''
                else ' Voucher ' || (v_verdict->>'code') ||
                     ' takes ₱' || round(v_discount)::int ||
                     ' off the price at pickup.'
           end
    from public.stores s
    join public.products p on p.id = p_product_id
    where s.id = p_store_id
      and s.owner_id is not null;

    return v_id;
end;
$$;

comment on function public.request_bulk_reservation(uuid, uuid, integer, jsonb, text, text) is
    'Customer asks for a bulk hold (minimum public.bulk_minimum_quantity() units), optionally with a voucher. The voucher is evaluated and claimed here, and its resolved discount is stored on the reservation so approval prices the deposit on the discounted value.';

revoke all on function public.request_bulk_reservation from public, anon;
grant execute on function public.request_bulk_reservation to authenticated;

-- ──────────────────────────────────────────────────────────────────
-- 4. Approval prices the deposit on the discounted value
--    Everything else is the function from
--    20261119230000_bulk_deposit_seventy_percent.sql.
-- ──────────────────────────────────────────────────────────────────
create or replace function public.decide_bulk_reservation(
    p_reservation_id UUID,
    p_approve BOOLEAN,
    p_days INTEGER DEFAULT NULL,        -- required when approving
    p_rejection_reason TEXT DEFAULT NULL
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    v_reservation public.bulk_reservations%ROWTYPE;
    v_seller UUID := auth.uid();
    v_price NUMERIC;
    v_base NUMERIC;
    v_deposit NUMERIC;
    v_deadline TIMESTAMPTZ;
    v_voucher_note TEXT := '';
begin
    if v_seller is null then
        raise exception 'NOT_AUTHENTICATED';
    end if;

    select * into v_reservation from public.bulk_reservations
    where id = p_reservation_id
    for update;                          -- serialize concurrent decisions

    if not found then
        raise exception 'NOT_FOUND';
    end if;

    if not exists (
        select 1 from public.stores
        where id = v_reservation.store_id and owner_id = v_seller
    ) then
        raise exception 'FORBIDDEN';
    end if;

    if v_reservation.status <> 'pending' then
        raise exception 'ALREADY_DECIDED';
    end if;

    if not p_approve then
        update public.bulk_reservations
        set status = 'rejected',
            rejection_reason = p_rejection_reason
        where id = p_reservation_id;

        insert into public.notifications (user_id, category, title, message)
        values (
            v_reservation.customer_id, 'reservations',
            'Bulk reservation declined',
            'The seller declined your reservation request' ||
            case when p_rejection_reason is not null and p_rejection_reason <> ''
                 then ': ' || p_rejection_reason else '.' end
        );
        return;
    end if;

    -- ── APPROVE: open the deposit window (NO stock moves yet) ──────
    if p_days is null or p_days < 1 then
        raise exception 'INVALID_DEADLINE';
    end if;

    -- Deposit = bulk_reservation_deposit_rate() of the estimated value,
    -- rounded UP to a whole peso. Stored resolved — §2 rule. The ORIGINAL
    -- `price` is used, not the sale price: a reseller hold is priced at
    -- pickup, and the sale could expire before the deposit is even paid.
    --
    -- The voucher discount WAS resolved at request time and is subtracted
    -- here, so the customer never pays a deposit on money they were never
    -- charged. The floor of ₱1 keeps the deposit_amount > 0 constraint
    -- satisfiable when a code covers the whole value.
    select price into v_price
    from public.products where id = v_reservation.product_id;
    if not found then
        raise exception 'PRODUCT_NOT_FOUND';
    end if;

    v_base := v_price * v_reservation.quantity
              - coalesce(v_reservation.voucher_discount, 0);
    v_deposit := greatest(1, ceil(greatest(v_base, 0)
                                  * public.bulk_reservation_deposit_rate()));

    if v_reservation.voucher_code is not null
       and coalesce(v_reservation.voucher_discount, 0) > 0 then
        v_voucher_note := ' Voucher ' || v_reservation.voucher_code ||
                          ' takes ₱' || round(v_reservation.voucher_discount)::int ||
                          ' off the price you pay at pickup.';
    end if;

    -- Deposit window: 24 hours from approval (§2 default).
    v_deadline := timezone('utc'::text, now()) + interval '24 hours';

    update public.bulk_reservations
    set status = 'awaiting_deposit',
        deposit_amount = v_deposit,
        deposit_status = 'unpaid',
        deposit_deadline = v_deadline,
        -- Seller's chosen hold window, stored exactly as the old flow
        -- did; it becomes operative only when the deposit is confirmed.
        expires_at = timezone('utc'::text, now()) + make_interval(days => p_days)
    where id = p_reservation_id;

    insert into public.notifications (user_id, category, title, message)
    values (
        v_reservation.customer_id, 'reservations',
        'Bulk reservation approved — deposit required',
        'Your reservation of ' || v_reservation.quantity || ' units was ' ||
        'approved. Pay the ₱' || v_deposit::int ||
        ' GCash deposit (' ||
        round(public.bulk_reservation_deposit_rate() * 100)::int || '% of the ' ||
        'estimated value) by ' ||
        to_char(v_deadline AT TIME ZONE 'UTC', 'Mon DD, HH24:MI') ||
        ' UTC to hold the stock.' || v_voucher_note ||
        ' The deposit is NON-REFUNDABLE once paid.'
    );
end;
$$;

revoke all on function public.decide_bulk_reservation from public, anon;
grant execute on function public.decide_bulk_reservation to authenticated;

commit;
