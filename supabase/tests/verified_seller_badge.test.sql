-- ══════════════════════════════════════════════════════════════════
-- Verified Seller badge (pgTAP) — covers
-- 20261115000000_add_verified_seller_badge.sql.
--
-- The migration is the only place the "approved ⇒ verified" rule lives, so
-- these assertions run against the real triggers rather than a Dart mock:
--
--   1. Schema: the column and all three triggers exist.
--   2. Approving a seller whose docs are `pending` AND hold a file flips the
--      docs to `verified`, stamps the row's `verified_at`, stamps
--      `profiles.seller_verified_at`, and writes EXACTLY ONE
--      "You're a verified seller ✅" notification under `approval`.
--   3. A docs row the admin explicitly `rejected` survives approval — no
--      verification, no badge, no notice. An approval must not overturn a
--      deliberate verdict.
--   4. A legacy seller is never claimed as verified: neither with no docs
--      row at all, nor with a row that holds no document file.
--   5. The docs-level transitions: `pending` keeps an already-granted badge
--      (a re-review must not strip it), `rejected`/`none` clear it, and a
--      fresh `verified` restores it.
--   6. The backfill stamps profiles already verified before the migration
--      and leaves every unverified profile alone.
-- ══════════════════════════════════════════════════════════════════

begin;
select plan(23);

-- The suite acts as an ADMIN reviewer, not as an anonymous session.
--
-- Two pre-existing triggers need a caller identity: a profile born in
-- `pending` is logged to `seller_application_audit_log` with
-- `actor_id = auth.uid()` (NOT NULL), and the same is true of every later
-- `seller_status` change. Running as a real admin also matches the real
-- call path — the console approves/writes verdicts as an admin, not as the
-- applicant — and keeps the owner self-certification guard irrelevant
-- (`auth.uid()` is never the docs row's own profile here).
select set_config(
  'request.jwt.claims',
  '{"sub":"ab000000-0000-0000-0000-0000000000fa","role":"authenticated"}',
  true
);
select set_config('request.headers', '{}', true);

-- ── fixtures (as postgres; RLS bypassed) ──────────────────────────
insert into auth.users (instance_id, id, aud, role, email, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000','ab000000-0000-0000-0000-0000000000fa','authenticated','authenticated','vb-admin@test.local',    now(), now()),
  ('00000000-0000-0000-0000-000000000000','ab000000-0000-0000-0000-000000000001','authenticated','authenticated','vb-pending@test.local',  now(), now()),
  ('00000000-0000-0000-0000-000000000000','ab000000-0000-0000-0000-000000000002','authenticated','authenticated','vb-rejected@test.local', now(), now()),
  ('00000000-0000-0000-0000-000000000000','ab000000-0000-0000-0000-000000000003','authenticated','authenticated','vb-legacy@test.local',   now(), now()),
  ('00000000-0000-0000-0000-000000000000','ab000000-0000-0000-0000-000000000004','authenticated','authenticated','vb-nofile@test.local',   now(), now()),
  ('00000000-0000-0000-0000-000000000000','ab000000-0000-0000-0000-000000000005','authenticated','authenticated','vb-verified@test.local', now(), now()),
  ('00000000-0000-0000-0000-000000000000','ab000000-0000-0000-0000-000000000006','authenticated','authenticated','vb-backfill@test.local', now(), now());

-- The reviewer first: the audit log's actor_id references profiles(id).
insert into public.profiles (id, full_name, email, role, seller_status)
values
  ('ab000000-0000-0000-0000-0000000000fa','Vb Admin',    'vb-admin@test.local',    'admin',   'none');

insert into public.profiles (id, full_name, email, role, seller_status)
values
  ('ab000000-0000-0000-0000-000000000001','Vb Pending',  'vb-pending@test.local',  'customer','pending'),
  ('ab000000-0000-0000-0000-000000000002','Vb Rejected', 'vb-rejected@test.local', 'customer','pending'),
  ('ab000000-0000-0000-0000-000000000003','Vb Legacy',   'vb-legacy@test.local',   'customer','pending'),
  ('ab000000-0000-0000-0000-000000000004','Vb NoFile',   'vb-nofile@test.local',   'customer','pending'),
  ('ab000000-0000-0000-0000-000000000005','Vb Verified', 'vb-verified@test.local', 'seller',  'approved'),
  ('ab000000-0000-0000-0000-000000000006','Vb Backfill', 'vb-backfill@test.local', 'seller',  'approved');

-- A — docs under review, with a real file behind them.
insert into public.seller_business_docs (profile_id, dti_cert_url, verification_status)
values ('ab000000-0000-0000-0000-000000000001',
        'ab000000-0000-0000-0000-000000000001/dti_cert.jpg', 'pending');

-- B — the admin already rejected these documents.
insert into public.seller_business_docs (profile_id, bir_cor_url, verification_status)
values ('ab000000-0000-0000-0000-000000000002',
        'ab000000-0000-0000-0000-000000000002/bir_cor.jpg', 'rejected');

-- C — legacy applicant: no docs row at all.

-- D — a docs row that exists but holds no document file.
insert into public.seller_business_docs (profile_id, verification_status)
values ('ab000000-0000-0000-0000-000000000004', 'none');

-- E — verified long ago (the trigger stamps it on insert).
insert into public.seller_business_docs (profile_id, dti_cert_url, verification_status, verified_at)
values ('ab000000-0000-0000-0000-000000000005',
        'ab000000-0000-0000-0000-000000000005/dti_cert.jpg', 'verified', now() - interval '10 days');

-- ══ 1. SCHEMA ═════════════════════════════════════════════════════
select has_column('public', 'profiles', 'seller_verified_at',
  '1: profiles.seller_verified_at exists');

select has_trigger('public', 'seller_business_docs', 'trg_sync_seller_verified_at',
  '2: docs verdict is mirrored onto the profile');
select has_trigger('public', 'seller_business_docs', 'trg_notify_on_seller_verified',
  '3: becoming verified writes a notification');
select has_trigger('public', 'profiles', 'trg_verify_seller_docs_on_approval',
  '4: approving a seller verifies their documents');

-- ══ 2. APPROVAL VERIFIES PENDING DOCS ═════════════════════════════
-- Exactly what the admin console does (role + seller_status together).
update public.profiles
   set role = 'seller', seller_status = 'approved'
 where id = 'ab000000-0000-0000-0000-000000000001';

select results_eq(
  $$select verification_status::text from public.seller_business_docs
     where profile_id = 'ab000000-0000-0000-0000-000000000001'$$,
  $$values ('verified'::text)$$,
  '5: approving a pending docs row verifies it');

select ok(
  (select verified_at is not null from public.seller_business_docs
    where profile_id = 'ab000000-0000-0000-0000-000000000001'),
  '6: the verified verdict carries a verified_at stamp');

select ok(
  (select seller_verified_at is not null from public.profiles
    where id = 'ab000000-0000-0000-0000-000000000001'),
  '7: the seller now carries the public badge flag');

select results_eq(
  $$select count(*)::bigint from public.notifications
     where user_id = 'ab000000-0000-0000-0000-000000000001'
       and title = $q$You're a verified seller ✅$q$::text$$,
  $$values (1::bigint)$$,
  '8: exactly one verified-seller notification is written');

select results_eq(
  $$select distinct category::text from public.notifications
     where user_id = 'ab000000-0000-0000-0000-000000000001'
       and title = $q$You're a verified seller ✅$q$::text$$,
  $$values ('approval'::text)$$,
  '9: it uses the existing approval category');

-- ══ 3. A REJECTED VERDICT SURVIVES APPROVAL ═══════════════════════
update public.profiles
   set role = 'seller', seller_status = 'approved'
 where id = 'ab000000-0000-0000-0000-000000000002';

select results_eq(
  $$select verification_status::text from public.seller_business_docs
     where profile_id = 'ab000000-0000-0000-0000-000000000002'$$,
  $$values ('rejected'::text)$$,
  '10: approving does not overturn an explicit rejection');

select ok(
  (select seller_verified_at is null from public.profiles
    where id = 'ab000000-0000-0000-0000-000000000002'),
  '11: a rejected seller gets no badge');

select results_eq(
  $$select count(*)::bigint from public.notifications
     where user_id = 'ab000000-0000-0000-0000-000000000002'
       and title = $q$You're a verified seller ✅$q$::text$$,
  $$values (0::bigint)$$,
  '12: and no verified-seller notice');

-- ══ 4. LEGACY SELLERS ARE NOT CLAIMED AS VERIFIED ═════════════════
update public.profiles
   set role = 'seller', seller_status = 'approved'
 where id = 'ab000000-0000-0000-0000-000000000003';

select results_eq(
  $$select count(*)::bigint from public.seller_business_docs
     where profile_id = 'ab000000-0000-0000-0000-000000000003'$$,
  $$values (0::bigint)$$,
  '13: approving a docless legacy seller invents no docs row');

select ok(
  (select seller_verified_at is null from public.profiles
    where id = 'ab000000-0000-0000-0000-000000000003'),
  '14: and grants no badge');

update public.profiles
   set role = 'seller', seller_status = 'approved'
 where id = 'ab000000-0000-0000-0000-000000000004';

select results_eq(
  $$select verification_status::text from public.seller_business_docs
     where profile_id = 'ab000000-0000-0000-0000-000000000004'$$,
  $$values ('none'::text)$$,
  '15: a docs row holding no file stays unverified');

select ok(
  (select seller_verified_at is null from public.profiles
    where id = 'ab000000-0000-0000-0000-000000000004'),
  '16: and grants no badge either');

-- ══ 5. PENDING PRESERVES THE BADGE; REJECTED/NONE CLEAR IT ════════
update public.seller_business_docs
   set verification_status = 'pending'
 where profile_id = 'ab000000-0000-0000-0000-000000000005';

select ok(
  (select seller_verified_at is not null from public.profiles
    where id = 'ab000000-0000-0000-0000-000000000005'),
  '17: a re-review (pending) does not strip an existing badge');

update public.seller_business_docs
   set verification_status = 'rejected'
 where profile_id = 'ab000000-0000-0000-0000-000000000005';

select ok(
  (select seller_verified_at is null from public.profiles
    where id = 'ab000000-0000-0000-0000-000000000005'),
  '18: a rejection withdraws the badge');

update public.seller_business_docs
   set verification_status = 'verified', verified_at = now()
 where profile_id = 'ab000000-0000-0000-0000-000000000005';

select ok(
  (select seller_verified_at is not null from public.profiles
    where id = 'ab000000-0000-0000-0000-000000000005'),
  '19: a fresh verified verdict restores it');

update public.seller_business_docs
   set verification_status = 'none'
 where profile_id = 'ab000000-0000-0000-0000-000000000005';

select ok(
  (select seller_verified_at is null from public.profiles
    where id = 'ab000000-0000-0000-0000-000000000005'),
  '20: none clears it too');

-- ══ 6. THE BACKFILL ═══════════════════════════════════════════════
-- Simulate a profile that was verified BEFORE the migration existed: its
-- docs are verified while the profile flag is still null (exactly the state
-- every pre-migration seller was in).
insert into public.seller_business_docs (profile_id, permit_url, verification_status, verified_at)
values ('ab000000-0000-0000-0000-000000000006',
        'ab000000-0000-0000-0000-000000000006/permit.jpg', 'verified', now() - interval '3 days');
update public.profiles set seller_verified_at = null
 where id = 'ab000000-0000-0000-0000-000000000006';

-- The backfill statement, verbatim from the migration.
UPDATE public.profiles p
   SET seller_verified_at = COALESCE(d.verified_at, timezone('utc'::text, now()))
  FROM public.seller_business_docs d
 WHERE d.profile_id = p.id
   AND d.verification_status = 'verified'
   AND p.seller_verified_at IS NULL;

select ok(
  (select seller_verified_at is not null from public.profiles
    where id = 'ab000000-0000-0000-0000-000000000006'),
  '21: the backfill stamps an already-verified seller');

select ok(
  (select seller_verified_at is null from public.profiles
    where id = 'ab000000-0000-0000-0000-000000000002'),
  '22: the backfill leaves a rejected-docs profile alone');

select ok(
  (select seller_verified_at is null from public.profiles
    where id = 'ab000000-0000-0000-0000-000000000003'),
  '23: the backfill leaves a docless profile alone');

select * from finish();
rollback;
