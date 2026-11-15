-- ══════════════════════════════════════════════════════════════════
-- Business-permit expiry reminders (pgTAP) — covers
-- 20261116000000_add_permit_expiry_reminders.sql.
--
-- The reminder rules live in SQL (this project has no pg_cron, so the app
-- only triggers them), which means they are proved here against the real
-- functions rather than against a Dart fake:
--
--   1. Schema + the two columns + both RPC grants.
--   2. The seller-bell CHECK admits 'permit_expiring' and 'verified_seller'.
--   3. A verified seller inside the window gets EXACTLY ONE notice, with
--      the days-left and the permit date the row actually holds.
--   4. A second launch prints nothing (already_reminded); re-saving the
--      same date keeps the stamp, a NEW date re-arms it.
--   5. Too-far-out, not-verified and expired permits all behave.
--   6. The write path is owner-only: another seller's call cannot move
--      this seller's date, and a profile with no docs row is refused.
--   7. Verifying documents now rings the SELLER bell ('verified_seller'),
--      not only the customer feed the seller shell never renders.
--   8. The narrowed self-certification guard still guards: no swapping the
--      reviewed files on a verified row, and an admin can still reject.
-- ══════════════════════════════════════════════════════════════════

begin;
select plan(34);

-- Fixtures run as an ADMIN reviewer: a profile born with seller_status
-- 'pending' is logged to seller_application_audit_log with
-- actor_id = auth.uid(), which is NOT NULL. The per-seller stanzas below
-- switch the claim to the seller under test.
select set_config(
  'request.jwt.claims',
  '{"sub":"be000000-0000-0000-0000-0000000000fa","role":"authenticated"}',
  true
);
select set_config('request.headers', '{}', true);

-- ── fixtures (as postgres; RLS bypassed) ──────────────────────────
insert into auth.users (instance_id, id, aud, role, email, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000','be000000-0000-0000-0000-0000000000fa','authenticated','authenticated','pe-admin@test.local',   now(), now()),
  ('00000000-0000-0000-0000-000000000000','be000000-0000-0000-0000-000000000001','authenticated','authenticated','pe-soon@test.local',    now(), now()),
  ('00000000-0000-0000-0000-000000000000','be000000-0000-0000-0000-000000000002','authenticated','authenticated','pe-far@test.local',     now(), now()),
  ('00000000-0000-0000-0000-000000000000','be000000-0000-0000-0000-000000000003','authenticated','authenticated','pe-pending@test.local', now(), now()),
  ('00000000-0000-0000-0000-000000000000','be000000-0000-0000-0000-000000000004','authenticated','authenticated','pe-lapsed@test.local',  now(), now()),
  ('00000000-0000-0000-0000-000000000000','be000000-0000-0000-0000-000000000005','authenticated','authenticated','pe-nodocs@test.local',  now(), now());

insert into public.profiles (id, full_name, email, role, seller_status)
values
  ('be000000-0000-0000-0000-0000000000fa','Pe Admin',   'pe-admin@test.local',   'admin',   'none'),
  ('be000000-0000-0000-0000-000000000001','Pe Soon',    'pe-soon@test.local',    'seller',  'approved'),
  ('be000000-0000-0000-0000-000000000002','Pe Far',     'pe-far@test.local',     'seller',  'approved'),
  ('be000000-0000-0000-0000-000000000003','Pe Pending', 'pe-pending@test.local', 'customer','pending'),
  ('be000000-0000-0000-0000-000000000004','Pe Lapsed',  'pe-lapsed@test.local',  'seller',  'approved'),
  ('be000000-0000-0000-0000-000000000005','Pe NoDocs',  'pe-nodocs@test.local',  'seller',  'approved');

-- Stores first: the verified-docs trigger rings the store bell, and a
-- missing store must simply mean "no bell row" (guarded in the trigger).
insert into public.stores (id, owner_id, name, location)
values
  ('be100000-0000-0000-0000-000000000001','be000000-0000-0000-0000-000000000001','Pe Soon Store',    'Cebu'),
  ('be100000-0000-0000-0000-000000000002','be000000-0000-0000-0000-000000000002','Pe Far Store',     'Cebu'),
  ('be100000-0000-0000-0000-000000000003','be000000-0000-0000-0000-000000000003','Pe Pending Store', 'Cebu'),
  ('be100000-0000-0000-0000-000000000004','be000000-0000-0000-0000-000000000004','Pe Lapsed Store',  'Cebu');

insert into public.seller_business_docs
  (profile_id, dti_cert_url, verification_status, verified_at, permit_valid_until)
values
  ('be000000-0000-0000-0000-000000000001','be000000-0000-0000-0000-000000000001/dti.jpg',
   'verified', now() - interval '30 days', current_date + 10),
  ('be000000-0000-0000-0000-000000000002','be000000-0000-0000-0000-000000000002/dti.jpg',
   'verified', now() - interval '30 days', current_date + 90),
  ('be000000-0000-0000-0000-000000000003','be000000-0000-0000-0000-000000000003/dti.jpg',
   'pending',  null,                       current_date + 5),
  ('be000000-0000-0000-0000-000000000004','be000000-0000-0000-0000-000000000004/dti.jpg',
   'verified', now() - interval '30 days', current_date - 3);

-- E has no docs row at all (legacy seller).

-- ══ 1. SCHEMA ═════════════════════════════════════════════════════
select has_column('public', 'seller_business_docs', 'permit_valid_until',
                  'seller_business_docs records when the permit lapses');
select has_column('public', 'seller_business_docs', 'permit_reminder_for',
                  'the reminder stamp lives beside the date');

-- The bell's CHECK must admit both new types, or the reminder and the
-- verification trigger would 23514 at runtime.
select lives_ok($$
  insert into public.seller_notifications (store_id, type, title, body)
  values ('be100000-0000-0000-0000-000000000001', 'permit_expiring', 'probe', 'probe')
$$, 'seller_notifications admits permit_expiring');

select lives_ok($$
  insert into public.seller_notifications (store_id, type, title, body)
  values ('be100000-0000-0000-0000-000000000001', 'verified_seller', 'probe', 'probe')
$$, 'seller_notifications admits verified_seller');

delete from public.seller_notifications where title = 'probe';

-- ══ 2. GRANTS ═════════════════════════════════════════════════════
select ok(
  not has_function_privilege('anon',
    'public.remind_permit_expiry(integer)', 'EXECUTE'),
  'anon cannot run the reminder'
);
select ok(
  has_function_privilege('authenticated',
    'public.remind_permit_expiry(integer)', 'EXECUTE'),
  'an authenticated seller can run the reminder'
);

-- ══ 3. SOON: one notice, then silence ═════════════════════════════
select set_config('request.jwt.claims',
  '{"sub":"be000000-0000-0000-0000-000000000001","role":"authenticated"}', true);

-- One call, kept in a temp table: the reminder is one-shot by design, so
-- a second call to read another field would already be the repeat.
create temp table pe_first as select public.remind_permit_expiry() as r;

select is((select (r ->> 'reminded')::boolean from pe_first), true,
          'a permit 10 days out is inside the 30-day window');
select is((select (r ->> 'days_left')::int from pe_first), 10,
          'the result reports the real days-left');
select ok(not ((select r from pe_first) ? 'reason'),
          'a successful reminder carries no refusal reason');
select is(
  (select count(*) from public.seller_notifications
    where store_id = 'be100000-0000-0000-0000-000000000001'
      and type = 'permit_expiring')::int,
  1,
  'exactly one reminder reached the store bell'
);
select is(
  (select metadata ->> 'days_left' from public.seller_notifications
    where store_id = 'be100000-0000-0000-0000-000000000001'
      and type = 'permit_expiring' limit 1),
  '10',
  'the bell row carries the days-left'
);
select is(
  (select metadata ->> 'permit_valid_until' from public.seller_notifications
    where store_id = 'be100000-0000-0000-0000-000000000001'
      and type = 'permit_expiring' limit 1),
  (current_date + 10)::text,
  'and the permit date the row actually holds'
);

select is(
  (public.remind_permit_expiry() ->> 'reason')::text,
  'already_reminded',
  'a second launch does not repeat itself'
);
select is(
  (select count(*) from public.seller_notifications
    where store_id = 'be100000-0000-0000-0000-000000000001'
      and type = 'permit_expiring')::int,
  1,
  'and posts nothing new'
);

-- ══ 4. RE-ARMING ═════════════════════════════════════════════════
select is(
  public.set_permit_valid_until(current_date + 10)::text,
  (current_date + 10)::text,
  'the seller can re-save the date'
);
select is(
  (select permit_reminder_for from public.seller_business_docs
    where profile_id = 'be000000-0000-0000-0000-000000000001')::text,
  (current_date + 10)::text,
  're-saving the SAME date keeps the reminder stamp'
);

select public.set_permit_valid_until(current_date + 20);
select ok(
  (select permit_reminder_for from public.seller_business_docs
    where profile_id = 'be000000-0000-0000-0000-000000000001') is null,
  'a NEW date clears the stamp and re-arms the reminder'
);
select is(
  (select permit_valid_until from public.seller_business_docs
    where profile_id = 'be000000-0000-0000-0000-000000000001')::text,
  (current_date + 20)::text,
  'the new date is stored'
);

select is(
  (public.remind_permit_expiry() ->> 'days_left')::int,
  20,
  'the re-armed reminder reports the new days-left'
);
select is(
  (select count(*) from public.seller_notifications
    where store_id = 'be100000-0000-0000-0000-000000000001'
      and type = 'permit_expiring')::int,
  2,
  'the renewed expiry gets its own single notice'
);

-- ══ 5. FAR / PENDING / LAPSED ════════════════════════════════════
select set_config('request.jwt.claims',
  '{"sub":"be000000-0000-0000-0000-000000000002","role":"authenticated"}', true);

select is(
  (public.remind_permit_expiry() ->> 'reason')::text,
  'not_due',
  'a permit 90 days out is too early to remind'
);
select is(
  (select count(*) from public.seller_notifications
    where store_id = 'be100000-0000-0000-0000-000000000002'
      and type = 'permit_expiring')::int,
  0,
  'and writes no reminder'
);

select set_config('request.jwt.claims',
  '{"sub":"be000000-0000-0000-0000-000000000003","role":"authenticated"}', true);

select is(
  (public.remind_permit_expiry() ->> 'reason')::text,
  'not_verified',
  'an unverified seller is not reminded about a badge they do not have'
);
select is(
  (select count(*) from public.seller_notifications
    where store_id = 'be100000-0000-0000-0000-000000000003'
      and type = 'permit_expiring')::int,
  0,
  'and the pending seller''s bell stays untouched'
);

-- A second seller's write must not move the first seller's date.
select public.set_permit_valid_until(current_date + 30);
select is(
  (select permit_valid_until from public.seller_business_docs
    where profile_id = 'be000000-0000-0000-0000-000000000001')::text,
  (current_date + 20)::text,
  'another seller''s write leaves this seller''s permit date alone'
);

select set_config('request.jwt.claims',
  '{"sub":"be000000-0000-0000-0000-000000000004","role":"authenticated"}', true);

select is(
  (public.remind_permit_expiry() ->> 'days_left')::int,
  -3,
  'an expired permit reports negative days-left'
);
select is(
  (select title from public.seller_notifications
    where store_id = 'be100000-0000-0000-0000-000000000004'
      and type = 'permit_expiring' limit 1),
  'Business permit expired',
  'and says so plainly'
);
select is(
  (select count(*) from public.seller_notifications
    where store_id = 'be100000-0000-0000-0000-000000000004'
      and type = 'permit_expiring')::int,
  1,
  'the lapsed permit is announced once'
);

-- ══ 6. NO DOCS ROW ═══════════════════════════════════════════════
select set_config('request.jwt.claims',
  '{"sub":"be000000-0000-0000-0000-000000000005","role":"authenticated"}', true);

select throws_ok(
  $$ select public.set_permit_valid_until(current_date + 5) $$,
  'P0001',
  'Submit your business documents first',
  'a seller with no docs row cannot record a permit date'
);
select is(
  (public.remind_permit_expiry() ->> 'reason')::text,
  'not_verified',
  'and has nothing to be reminded about'
);

-- ══ 7. VERIFICATION RINGS THE SELLER BELL ════════════════════════
select set_config('request.jwt.claims',
  '{"sub":"be000000-0000-0000-0000-0000000000fa","role":"authenticated"}', true);

update public.seller_business_docs
   set verification_status = 'verified', verified_at = now()
 where profile_id = 'be000000-0000-0000-0000-000000000003';

select is(
  (select count(*) from public.seller_notifications
    where store_id = 'be100000-0000-0000-0000-000000000003'
      and type = 'verified_seller')::int,
  1,
  'verifying documents rings the seller''s own bell, not only the customer feed'
);
select is(
  (select count(*) from public.notifications
    where user_id = 'be000000-0000-0000-0000-000000000003'
      and category = 'approval')::int,
  1,
  'the customer-feed notice is still written as before'
);

-- ══ 8. THE GUARD STILL GUARDS ════════════════════════════════════
-- The permit date is editable on a verified row (that is the whole point
-- of section 1b), but the reviewed FILES are not.
select set_config('request.jwt.claims',
  '{"sub":"be000000-0000-0000-0000-000000000001","role":"authenticated"}', true);

select throws_ok($$
  update public.seller_business_docs
     set permit_url = 'be000000-0000-0000-0000-000000000001/renewed.pdf'
   where profile_id = 'be000000-0000-0000-0000-000000000001'
$$, 'P0001',
  'Sellers can only submit business documents for review (status none/pending).',
  'a verified seller still cannot swap the reviewed files');

-- An admin verdict on the same row is never blocked by the seller guard.
select set_config('request.jwt.claims',
  '{"sub":"be000000-0000-0000-0000-0000000000fa","role":"authenticated"}', true);

select lives_ok($$
  select public.set_business_verification_status(
    (select id from public.seller_business_docs
      where profile_id = 'be000000-0000-0000-0000-000000000001'),
    'rejected')
$$, 'an admin can still reject a verified seller''s documents');

select * from finish();
rollback;
