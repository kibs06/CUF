-- ══════════════════════════════════════════════════════════════════
-- 20261119100000_orders_customer_email.sql
--
-- The POS receipt can be emailed, but the address lived only in the dialog
-- that asked for it: closed the dialog or left the screen and the next send
-- started from an empty field, and no server-side delivery could ever be
-- added because the database never learned who the sale belonged to.
--
-- This file gives the address a home on the order:
--
--   1. orders.customer_email — nullable, so every existing order (and every
--      online checkout, which does not collect one) is untouched.
--   2. A shape CHECK on the column, because the app is not the only writer
--      that will ever exist and a half-typed address is worse than none.
--   3. set_order_customer_email(order, address) — the one write path. It
--      derives the store from the order and requires the caller to own it,
--      so a seller can only address a receipt from their own till; admin
--      sessions pass through the same ownership test only where they own
--      the store, which keeps the function free of an admin bypass a sale
--      does not need.
--
-- The address is stored trimmed and lowercased: it is a delivery target, not
-- a display name, and two casings of one mailbox must not look like two
-- customers.
--
-- Additive and idempotent. Nothing breaks while it is unapplied: the app
-- selects customer_email first and retries without it (OrderService), and the
-- save is best-effort — the email still opens either way.
-- ══════════════════════════════════════════════════════════════════

begin;

-- ──────────────────────────────────────────────────────────────────
-- 1. The column
-- ──────────────────────────────────────────────────────────────────
alter table public.orders
  add column if not exists customer_email text;

-- ──────────────────────────────────────────────────────────────────
-- 2. The shape it may hold
--
--    Same rule the app's dialog applies (one @, a dot in the domain, no
--    whitespace), expressed where every writer meets it. NULL stays legal:
--    a walk-in who did not want a copy is the ordinary case.
-- ──────────────────────────────────────────────────────────────────
alter table public.orders
  drop constraint if exists orders_customer_email_shape;

alter table public.orders
  add constraint orders_customer_email_shape
  check (
    customer_email is null
    or (
      length(customer_email) between 3 and 254
      and customer_email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]{2,}$'
    )
  );

comment on column public.orders.customer_email is
  'Where the customer copy of this sale''s receipt was sent, typed at the POS receipt screen and stored so a re-send prefills it and a server-side delivery can find it. Trimmed and lowercased. NULL when no receipt was emailed.';

-- ──────────────────────────────────────────────────────────────────
-- 3. The write path
--
--    Returns jsonb rather than void so the caller can confirm what was
--    stored (the normalised address, not the one it sent).
-- ──────────────────────────────────────────────────────────────────
create or replace function public.set_order_customer_email(
  p_order_id uuid,
  p_email    text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_store uuid;
  v_email text;
begin
  -- The order's store decides who may write: the till that made the sale.
  select o.store_id into v_store
    from public.orders o
   where o.id = p_order_id;

  if v_store is null then
    raise exception 'Order % does not exist', p_order_id
      using errcode = 'P0002';
  end if;

  if not exists (
    select 1 from public.stores s
     where s.id = v_store
       and s.owner_id = auth.uid()
  ) then
    raise exception 'Only the store that made this sale can record its receipt email'
      using errcode = '42501';
  end if;

  v_email := lower(btrim(coalesce(p_email, '')));

  if v_email = '' then
    raise exception 'The customer email is empty'
      using errcode = 'P0001';
  end if;

  if length(v_email) > 254
     or v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]{2,}$' then
    raise exception '% is not an email address', p_email
      using errcode = 'P0001';
  end if;

  update public.orders
     set customer_email = v_email
   where id = p_order_id
     and customer_email is distinct from v_email;

  return jsonb_build_object(
    'order_id', p_order_id,
    'customer_email', v_email
  );
end;
$$;

comment on function public.set_order_customer_email(uuid, text) is
  'Records the email a POS receipt was sent to. The caller must own the order''s store (stores.owner_id = auth.uid()); the address is trimmed, lowercased and shape-checked. The only write path for orders.customer_email.';

-- ──────────────────────────────────────────────────────────────────
-- 4. Grants — seller-authenticated only
-- ──────────────────────────────────────────────────────────────────
revoke all on function public.set_order_customer_email(uuid, text)
  from public, anon;

grant execute on function public.set_order_customer_email(uuid, text)
  to authenticated;

commit;
