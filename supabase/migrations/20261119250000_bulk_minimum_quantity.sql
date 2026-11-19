-- ══════════════════════════════════════════════════════════════════
-- 20261119250000_bulk_minimum_quantity.sql
--
-- Bulk buying is a wholesale flow — a reseller holding stock to sell on — but
-- nothing said how much of it a request had to be. A one-pair "bulk" request
-- tied up the seller's attention and the deposit/stock machinery for a single
-- sale, and it is indistinguishable from an ordinary purchase that should have
-- gone through the cart.
--
-- So the floor is now explicit: a bulk reservation must ask for at least
-- **10 units**. Below that the request is refused with
-- `BULK_MINIMUM_QUANTITY (10)`, which the app already maps to a readable
-- message (`friendlyReservationError`), and the customer orders normally.
--
-- What this file changes:
--   1. `public.bulk_minimum_quantity()` — the rule itself, in one place, so the
--      number in the RPC and the number the app prints cannot drift apart. The
--      app mirrors it as `kBulkMinimumQuantity` (lib/constants/bulk_buying.dart).
--   2. `request_bulk_reservation(...)` re-declared with the check. The rest of
--      the function is byte-for-byte the version in
--      20260913140000_add_bulk_reservation_deposits.sql (one live request per
--      customer per product, stock pre-check, seller notification with the
--      ownerless-store guard).
--
-- The check is SERVER-side because it has to hold for every caller: the app
-- disables its own button below 10, and that is a courtesy, not the rule.
--
-- Existing reservations are untouched — a request made under the old rule is
-- still valid, and the seller queue keeps showing it. Only NEW requests are
-- refused, and only the quantity is checked: sizes, deposit rate and deadlines
-- behave exactly as before.
--
-- Additive and idempotent. Safe to run before or after the app build that
-- prints the rule.
-- ══════════════════════════════════════════════════════════════════

begin;

-- ──────────────────────────────────────────────────────────────────
-- 1. The rule, in one place
-- ──────────────────────────────────────────────────────────────────
create or replace function public.bulk_minimum_quantity()
returns integer
language sql
immutable
as $$
    -- 10 units. A bulk hold below this is just a normal purchase: the cart
    -- handles it, and it never needs a deposit.
    select 10
$$;

comment on function public.bulk_minimum_quantity() is
    'The smallest quantity a bulk (reseller) reservation may ask for. Read by request_bulk_reservation, which refuses anything below it with BULK_MINIMUM_QUANTITY. The app mirrors this number as kBulkMinimumQuantity.';

-- The rule is printed in error messages and may be read by any client.
revoke all on function public.bulk_minimum_quantity() from public;
grant execute on function public.bulk_minimum_quantity()
  to anon, authenticated, service_role;

-- ──────────────────────────────────────────────────────────────────
-- 2. The request RPC, with the floor
-- ──────────────────────────────────────────────────────────────────
create or replace function public.request_bulk_reservation(
    p_product_id UUID,
    p_store_id UUID,
    p_quantity INTEGER,
    p_requested_sizes JSONB DEFAULT '[]'::jsonb,
    p_note TEXT DEFAULT NULL
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
    v_customer UUID := auth.uid();
    v_available INTEGER;
    v_id UUID;
    v_minimum INTEGER := public.bulk_minimum_quantity();
begin
    if v_customer is null then
        raise exception 'NOT_AUTHENTICATED';
    end if;
    if p_quantity is null or p_quantity < 1 then
        raise exception 'INVALID_QUANTITY';
    end if;

    -- Bulk buying starts at the minimum. Below it this is an ordinary purchase,
    -- which has its own flow — no hold, no deposit, no stock set aside.
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

    -- One live request per customer per product at a time. Deposit-gate
    -- update: 'awaiting_deposit' is live too (deposit not yet confirmed).
    if exists (
        select 1 from public.bulk_reservations
        where customer_id = v_customer
          and product_id = p_product_id
          and status in ('pending', 'awaiting_deposit', 'approved')
    ) then
        raise exception 'RESERVATION_ALREADY_EXISTS';
    end if;

    insert into public.bulk_reservations (
        customer_id, store_id, product_id, quantity,
        requested_sizes, note, status
    ) values (
        v_customer, p_store_id, p_product_id, p_quantity,
        p_requested_sizes, p_note, 'pending'
    ) returning id into v_id;

    -- ⚠️ `and s.owner_id is not null` is a RECIPIENT guard: `stores.owner_id` is
    -- NULLABLE and `notifications.user_id` is NOT NULL, so a store with no owner
    -- would fail the CUSTOMER's request outright — the reservation insert above
    -- and this statement are one transaction, so nothing would be requested at
    -- all. An ownerless store simply has nobody to tell.
    insert into public.notifications (user_id, category, title, message)
    select s.owner_id, 'reservations',
           'New bulk reservation request',
           'A customer requested ' || p_quantity || ' units of ' ||
           coalesce(p.name, 'a product') || ' for resale.'
    from public.stores s
    join public.products p on p.id = p_product_id
    where s.id = p_store_id
      and s.owner_id is not null;

    return v_id;
end;
$$;

comment on function public.request_bulk_reservation(uuid, uuid, integer, jsonb, text) is
    'Customer asks for a bulk hold. Refuses fewer than public.bulk_minimum_quantity() (10) units with BULK_MINIMUM_QUANTITY, so a small order goes through the normal cart instead.';

revoke all on function public.request_bulk_reservation from public, anon;
grant execute on function public.request_bulk_reservation to authenticated;

commit;
