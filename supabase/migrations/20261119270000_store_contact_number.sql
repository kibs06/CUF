-- ══════════════════════════════════════════════════════════════════
-- 20261119270000_store_contact_number.sql
--
-- A bulk deposit is paid peer-to-peer to the STORE's GCash account, and the
-- store confirms it by hand. When something goes wrong — the transfer landed
-- but the reference does not match, the customer sent a peso short, the hold
-- needs a different pickup time — the customer has nowhere to ask. The app
-- showed only the GCash number, which is a payment rail, not a conversation.
--
-- So: one optional contact number per store, set by the seller in Edit Store,
-- rendered on the bulk deposit screen and on the deposit receipt when present.
--
-- Why a column on `stores` and not `profiles.phone`:
--   • `profiles` is owner-only under RLS (20260901010000_tighten_profiles_rbac),
--     so a customer cannot read the seller's row at all. Making that readable
--     would expose every profile field, not just a shop's number.
--   • This is shop data, not personal identity data. It belongs with the shop's
--     name and location, which are already public on `stores`.
--
-- Additive and idempotent.
-- ══════════════════════════════════════════════════════════════════

begin;

alter table public.stores
  add column if not exists contact_number text;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'stores_contact_number_format'
  ) then
    -- Deliberately loose: PH mobiles are written 0917 123 4567, +63 917 123
    -- 4567 and 09171234567 by different people, and a landline has a leading
    -- area code. The rule only keeps out text that is clearly not a number.
    alter table public.stores
      add constraint stores_contact_number_format
      check (
        contact_number is null
        or contact_number ~ '^[0-9+() -]{7,20}$'
      );
  end if;
end $$;

comment on column public.stores.contact_number is
  'Optional shop contact number the seller sets in Edit Store. Shown to the customer on the bulk deposit screen and on the deposit receipt so they can reach the store about a hold. Not a GCash number — that is `gcash_number`.';

commit;
