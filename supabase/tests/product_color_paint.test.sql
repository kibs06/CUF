-- ══════════════════════════════════════════════════════════════════
-- Per-colour 3D paint (mission: swipe-the-colour, see-it-in-3D) — pgTAP
-- Run by CI via `supabase test db` (workflow: supabase-migrations.yml)
--
-- Covers `20261114000100_add_product_color_paint.sql`. The assertions that
-- matter most are marked ⚠️ — each is a way the feature could look right
-- and be wrong:
--
--   ⚠️ The hex is a web hex or nothing (1–3): the viewers parse
--      `paint_hex` straight into a colour factor, so 'red' or a bare
--      '1A1A1A' stored today becomes a wrong-coloured shoe (or a render
--      fault) on every surface tomorrow. The CHECK is asserted by direct
--      INSERT, not by trusting the admin form.
--
--   ⚠️ One paint per colour (4): the PK is what makes "the brown paint"
--      a single answer. Two rows for one colour would tint by luck of
--      read order — asserted by the duplicate INSERT past any upsert.
--
--   ⚠️ A seller paints only their own products (7–9): the policies are
--      the only door (no RPC layer on this table), so a crafted client
--      writing another store's colour is refused here, including the
--      quiet case — an UPDATE that matches nothing must change nothing
--      (10), not throw somewhere the app swallows.
--
--   ⚠️ The table is EXEMPT from the device gate (12): paint is catalogue
--      content read beside the colour photos on the product page, on
--      devices that never ran the native app. (This is the assertion whose
--      absence let `product_models` be gated silently; see the note in
--      that migration.)
-- ══════════════════════════════════════════════════════════════════

begin;
select plan(12);

-- ── fixtures (as postgres; RLS bypassed) ──────────────────────────
insert into auth.users (instance_id, id, aud, role, email, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000','c1000000-0000-0000-0000-000000000001','authenticated','authenticated','paint-seller@test.local', now(), now()),
  ('00000000-0000-0000-0000-000000000000','c1000000-0000-0000-0000-000000000002','authenticated','authenticated','paint-other@test.local',  now(), now()),
  ('00000000-0000-0000-0000-000000000000','c1000000-0000-0000-0000-000000000003','authenticated','authenticated','paint-admin@test.local',  now(), now()),
  ('00000000-0000-0000-0000-000000000000','c1000000-0000-0000-0000-000000000004','authenticated','authenticated','paint-cust@test.local',   now(), now());

insert into public.profiles (id, full_name, email, role, seller_status)
values
  ('c1000000-0000-0000-0000-000000000001','Paint Seller','paint-seller@test.local','seller','approved'),
  ('c1000000-0000-0000-0000-000000000002','Paint Other','paint-other@test.local','seller','approved'),
  ('c1000000-0000-0000-0000-000000000003','Paint Admin','paint-admin@test.local','admin','none'),
  ('c1000000-0000-0000-0000-000000000004','Paint Customer','paint-cust@test.local','customer','none');

insert into public.stores (id, owner_id, name, location)
values
  ('c1000000-0000-0000-0000-000000000011','c1000000-0000-0000-0000-000000000001','Paint Store','Paint City'),
  ('c1000000-0000-0000-0000-000000000012','c1000000-0000-0000-0000-000000000002','Paint Store Two','Paint City');

insert into public.products (id, store_id, seller_id, name, price, is_active)
values
  ('c1000000-0000-0000-0000-000000000021','c1000000-0000-0000-0000-000000000011','c1000000-0000-0000-0000-000000000001','Paint Shoe', 1500, true),
  ('c1000000-0000-0000-0000-000000000022','c1000000-0000-0000-0000-000000000012','c1000000-0000-0000-0000-000000000002','Paint Shoe Two', 900, true);

-- ══ 1–3. HEX FORMAT ═══════════════════════════════════════════════
select throws_ok(
  $$ insert into public.product_color_paint (product_id, color_name, paint_hex)
     values ('c1000000-0000-0000-0000-000000000021','Brown','red') $$,
  '23514', 'product_color_paint_hex_format',
  '1: a colour name is not a paint value'
);

select throws_ok(
  $$ insert into public.product_color_paint (product_id, color_name, paint_hex)
     values ('c1000000-0000-0000-0000-000000000021','Brown','1A1A1A') $$,
  '23514', 'product_color_paint_hex_format',
  '2: the # is required, not decorative'
);

select lives_ok(
  $$ insert into public.product_color_paint (product_id, color_name, paint_hex)
     values ('c1000000-0000-0000-0000-000000000021','Brown','#5C3A21') $$,
  '3: a web hex stores'
);

-- ══ 4. ONE PAINT PER COLOUR ═══════════════════════════════════════
select throws_ok(
  $$ insert into public.product_color_paint (product_id, color_name, paint_hex)
     values ('c1000000-0000-0000-0000-000000000021','Brown','#4E342E') $$,
  '23505', 'product_color_paint_pkey',
  '4: a second paint for the same colour is refused, not averaged'
);

-- ══ 5. PUBLIC READ ═══════════════════════════════════════════════
select set_config(
  'request.jwt.claims',
  '{"sub":"c1000000-0000-0000-0000-000000000004","role":"authenticated"}',
  true
);
set local role authenticated;

select ok(
  (select paint_hex from public.product_color_paint
   where product_id = 'c1000000-0000-0000-0000-000000000021' and color_name = 'Brown') = '#5C3A21',
  '5: a customer reads the paint beside the photos'
);

reset role;

-- ══ 6–8. SELLER WRITES OWN ═══════════════════════════════════════
select set_config(
  'request.jwt.claims',
  '{"sub":"c1000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);
set local role authenticated;

select lives_ok(
  $$ insert into public.product_color_paint (product_id, color_name, paint_hex)
     values ('c1000000-0000-0000-0000-000000000021','Black','#1A1A1A') $$,
  '6: a seller paints their own product''s colour'
);

select lives_ok(
  $$ update public.product_color_paint set paint_hex = '#26221E'
     where product_id = 'c1000000-0000-0000-0000-000000000021' and color_name = 'Black' $$,
  '7: …and corrects it'
);

select throws_ok(
  $$ insert into public.product_color_paint (product_id, color_name, paint_hex)
     values ('c1000000-0000-0000-0000-000000000022','Brown','#5C3A21') $$,
  '42501', 'policy',
  '8: …but not another store''s product'
);

reset role;

-- ══ 9–10. CROSS-STORE QUIET CASES ═══════════════════════════════
select set_config(
  'request.jwt.claims',
  '{"sub":"c1000000-0000-0000-0000-000000000002","role":"authenticated"}',
  true
);
set local role authenticated;

delete from public.product_color_paint
where product_id = 'c1000000-0000-0000-0000-000000000021' and color_name = 'Brown';

select ok(
  exists (select 1 from public.product_color_paint
          where product_id = 'c1000000-0000-0000-0000-000000000021' and color_name = 'Brown'),
  '9: deleting another store''s paint removes nothing'
);

-- An UPDATE whose policy matches nothing changes nothing rather than
-- throwing somewhere the app would swallow: the row must read back
-- exactly as the owning seller left it.
update public.product_color_paint set paint_hex = '#000000'
where product_id = 'c1000000-0000-0000-0000-000000000021' and color_name = 'Brown';

select ok(
  (select paint_hex from public.product_color_paint
   where product_id = 'c1000000-0000-0000-0000-000000000021' and color_name = 'Brown') = '#5C3A21',
  '10: …and a cross-store update lands nowhere'
);

reset role;

-- ══ 11. ADMIN WRITES ANYWHERE ═════════════════════════════════════
select set_config(
  'request.jwt.claims',
  '{"sub":"c1000000-0000-0000-0000-000000000003","role":"authenticated"}',
  true
);
set local role authenticated;

select lives_ok(
  $$ insert into public.product_color_paint (product_id, color_name, paint_hex)
     values ('c1000000-0000-0000-0000-000000000022','Tan','#A9703C') $$,
  '11: an admin paints any product''s colour'
);

reset role;

-- ══ 12. DEVICE GATE EXEMPTION ═════════════════════════════════════
select ok(
  'product_color_paint' = ANY (public.device_gate_exempt_tables()),
  '12: paint rides the catalogue exemption, beside the colour photos'
);

select * from finish();
rollback;
