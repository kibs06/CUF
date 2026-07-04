-- ═══════════════════════════════════════════════════════════════════
-- SoleVision — Persistent Cart: cart_items table
-- Run this migration in the Supabase SQL Editor.
-- ═══════════════════════════════════════════════════════════════════

-- 1. Create table
create table if not exists public.cart_items (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles(id) on delete cascade,
  product_id  uuid not null references public.products(id) on delete cascade,
  variant_id  uuid references public.product_variants(id) on delete cascade,
  quantity    integer not null check (quantity > 0),
  -- snapshot of customization choices (monogram text, material, etc.)
  customizations jsonb,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- 2. Index for fast per-user reads
create index if not exists idx_cart_items_user on public.cart_items(user_id);

-- 3. Unique constraint: one row per product+variant+customization per user
--    NOTE: NULL variant_id or NULL customizations break the unique constraint
--    in PostgreSQL (NULL != NULL). The service layer handles dedup manually.
do $$
begin
  alter table public.cart_items
    add constraint cart_items_user_product_variant_unique
    unique (user_id, product_id, variant_id, customizations);
exception when duplicate_object then
  -- constraint already exists, skip
end $$;

-- 4. Row-Level Security
alter table public.cart_items enable row level security;

create policy "Users can view own cart"
  on public.cart_items for select
  using (auth.uid() = user_id);

create policy "Users can insert own cart items"
  on public.cart_items for insert
  with check (auth.uid() = user_id);

create policy "Users can update own cart items"
  on public.cart_items for update
  using (auth.uid() = user_id);

create policy "Users can delete own cart items"
  on public.cart_items for delete
  using (auth.uid() = user_id);

-- 5. Auto-update updated_at trigger
create or replace function public.set_cart_item_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

drop trigger if exists trg_cart_items_updated_at on public.cart_items;
create trigger trg_cart_items_updated_at
  before update on public.cart_items
  for each row execute function public.set_cart_item_updated_at();
