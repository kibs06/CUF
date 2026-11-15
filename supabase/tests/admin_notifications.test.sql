-- ══════════════════════════════════════════════════════════════════
-- Admin notifications (pgTAP) — covers
-- 20261118000000_add_admin_notifications.sql.
--
-- A feed is only useful if it is complete, per-admin and private, so the
-- assertions cover all three rather than just "a row appeared":
--
--   1. Schema: the table and its columns exist.
--   2. A resubmission writes EXACTLY ONE row per admin (two admins → two
--      rows), pointing at the seller and carrying the event metadata.
--   3. Nothing else writes: a first submission and a pending → pending edit
--      leave the feed untouched.
--   4. RLS: an admin reads only their own rows, can mark them read, and a
--      seller sees nothing at all.
--   5. A SECOND resubmission cycle writes a fresh round — the feed is a log,
--      not a flag.
-- ══════════════════════════════════════════════════════════════════

begin;
select plan(16);

-- Fixtures run as an admin reviewer: a profile born 'pending' is logged to
-- seller_application_audit_log with actor_id = auth.uid(), which is NOT NULL.
select set_config(
  'request.jwt.claims',
  '{"sub":"d0000000-0000-0000-0000-0000000000fa","role":"authenticated"}',
  true
);
select set_config('request.headers', '{}', true);

insert into auth.users (instance_id, id, aud, role, email, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000','d0000000-0000-0000-0000-0000000000fa','authenticated','authenticated','an-admin1@test.local', now(), now()),
  ('00000000-0000-0000-0000-000000000000','d0000000-0000-0000-0000-0000000000fb','authenticated','authenticated','an-admin2@test.local', now(), now()),
  ('00000000-0000-0000-0000-000000000000','d0000000-0000-0000-0000-000000000001','authenticated','authenticated','an-retry@test.local',  now(), now()),
  ('00000000-0000-0000-0000-000000000000','d0000000-0000-0000-0000-000000000002','authenticated','authenticated','an-first@test.local',  now(), now());

insert into public.profiles (id, full_name, email, role, seller_status)
values
  ('d0000000-0000-0000-0000-0000000000fa','An Admin One','an-admin1@test.local','admin','none'),
  ('d0000000-0000-0000-0000-0000000000fb','An Admin Two','an-admin2@test.local','admin','none');

insert into public.profiles (id, full_name, email, role, seller_status, store_name)
values
  ('d0000000-0000-0000-0000-000000000001','An Retry','an-retry@test.local','seller','approved','Retry Footwear'),
  ('d0000000-0000-0000-0000-000000000002','An First','an-first@test.local','seller','approved','First Footwear');

-- A: rejected, about to resubmit. B: a first submission under review.
insert into public.seller_business_docs (profile_id, dti_cert_url, verification_status)
values
  ('d0000000-0000-0000-0000-000000000001','d0000000-0000-0000-0000-000000000001/dti.jpg','rejected'),
  ('d0000000-0000-0000-0000-000000000002','d0000000-0000-0000-0000-000000000002/dti.jpg','pending');

-- ══ 1. SCHEMA ════════════════════════════════════════════════════
select has_table('public', 'admin_notifications',
                 'the admin feed has its own table');
select has_column('public', 'admin_notifications', 'user_id',
                  'a notice belongs to one admin');
select has_column('public', 'admin_notifications', 'is_read',
                  'a notice can be marked read');

-- ══ 2. THE RESUBMISSION NOTIFIES EVERY ADMIN ════════════════════
update public.seller_business_docs
   set verification_status = 'pending'
 where profile_id = 'd0000000-0000-0000-0000-000000000001';

select is(
  (select count(*) from public.admin_notifications)::int,
  2,
  'one row per admin, not one row in total'
);
select is(
  (select count(*) from public.admin_notifications
    where reference_id = 'd0000000-0000-0000-0000-000000000001')::int,
  2,
  'both rows point at the seller who resubmitted'
);
select is(
  (select metadata ->> 'kind' from public.admin_notifications limit 1),
  'business_docs_resubmitted',
  'the notice carries the event kind the feed routes on'
);
select is(
  (select count(*) from public.admin_notifications where is_read)::int,
  0,
  'a fresh notice is unread'
);
select is(
  (select body from public.admin_notifications limit 1),
  'An Retry (Retry Footwear) sent new documents after a rejection. Review them in the Business Docs queue.',
  'the body names the seller and their store'
);

-- ══ 3. NOTHING ELSE WRITES ═══════════════════════════════════════
-- The first timer's row was inserted (not updated) as 'pending': no notice.
select is(
  (select count(*) from public.admin_notifications)::int,
  2,
  'a first submission writes no admin notice'
);

-- The seller replaces one file without a rejection in between.
update public.seller_business_docs
   set verification_status = 'pending',
       dti_cert_url = 'd0000000-0000-0000-0000-000000000001/dti-v2.jpg'
 where profile_id = 'd0000000-0000-0000-0000-000000000001';

select is(
  (select count(*) from public.admin_notifications)::int,
  2,
  'a pending → pending edit is not a resubmission'
);

-- ══ 4. RLS — OWN ROWS ONLY ══════════════════════════════════════
select set_config(
  'request.jwt.claims',
  '{"sub":"d0000000-0000-0000-0000-0000000000fa","role":"authenticated"}',
  true
);
set local role authenticated;

select is(
  (select count(*) from public.admin_notifications)::int,
  1,
  'an admin sees only their own notice'
);
select is(
  (select count(*) from public.admin_notifications where not is_read)::int,
  1,
  'and it is unread'
);

update public.admin_notifications set is_read = true;

select is(
  (select count(*) from public.admin_notifications where not is_read)::int,
  0,
  'the admin can mark it read'
);

reset role;

select set_config(
  'request.jwt.claims',
  '{"sub":"d0000000-0000-0000-0000-0000000000fb","role":"authenticated"}',
  true
);
set local role authenticated;

select is(
  (select count(*) from public.admin_notifications where not is_read)::int,
  1,
  'another admin''s read state is their own'
);

reset role;

select set_config(
  'request.jwt.claims',
  '{"sub":"d0000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);
set local role authenticated;

select is(
  (select count(*) from public.admin_notifications)::int,
  0,
  'a seller cannot read the admin feed'
);

reset role;

-- ══ 5. A SECOND CYCLE IS A NEW NOTICE ═══════════════════════════
-- Back to the admin identity: the seller claim from the RLS block would
-- make guard_seller_business_docs_status read this as a self-certification.
select set_config(
  'request.jwt.claims',
  '{"sub":"d0000000-0000-0000-0000-0000000000fa","role":"authenticated"}',
  true
);

update public.seller_business_docs
   set verification_status = 'rejected'
 where profile_id = 'd0000000-0000-0000-0000-000000000001';

update public.seller_business_docs
   set verification_status = 'pending'
 where profile_id = 'd0000000-0000-0000-0000-000000000001';

select is(
  (select count(*) from public.admin_notifications)::int,
  4,
  'a second resubmission writes a second round for both admins'
);

select * from finish();
rollback;
