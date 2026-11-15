-- ══════════════════════════════════════════════════════════════════
-- Business-document resubmission tracking (pgTAP) — covers
-- 20261117000000_add_business_docs_resubmission.sql.
--
-- The stamp is what lifts a second attempt out of the queue's backlog, so
-- the transition rules are proved against the real trigger:
--
--   1. Schema: both columns exist; a first submission carries no stamp and
--      a zero count.
--   2. rejected → pending stamps `resubmitted_at` and increments the count.
--   3. A pending → pending edit (the seller replacing one file) is NOT a
--      resubmission and changes neither.
--   4. A second rejection-and-retry increments again, so a third attempt is
--      distinguishable from the first retry.
--   5. The admin alert's own count query sees the resubmitted seller.
--   6. A verdict on the retry leaves the stamp in place (it is the record
--      of the attempt that was reviewed).
-- ══════════════════════════════════════════════════════════════════

begin;
select plan(12);

-- Fixtures run as an admin reviewer: a profile born 'pending' is logged to
-- seller_application_audit_log with actor_id = auth.uid(), which is NOT NULL.
select set_config(
  'request.jwt.claims',
  '{"sub":"cf000000-0000-0000-0000-0000000000fa","role":"authenticated"}',
  true
);
select set_config('request.headers', '{}', true);

insert into auth.users (instance_id, id, aud, role, email, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000','cf000000-0000-0000-0000-0000000000fa','authenticated','authenticated','cf-admin@test.local',   now(), now()),
  ('00000000-0000-0000-0000-000000000000','cf000000-0000-0000-0000-000000000001','authenticated','authenticated','cf-retry@test.local',   now(), now()),
  ('00000000-0000-0000-0000-000000000000','cf000000-0000-0000-0000-000000000002','authenticated','authenticated','cf-first@test.local',   now(), now());

insert into public.profiles (id, full_name, email, role, seller_status)
values
  ('cf000000-0000-0000-0000-0000000000fa','Cf Admin', 'cf-admin@test.local', 'admin', 'none');

insert into public.profiles (id, full_name, email, role, seller_status)
values
  ('cf000000-0000-0000-0000-000000000001','Cf Retry', 'cf-retry@test.local', 'seller', 'approved'),
  ('cf000000-0000-0000-0000-000000000002','Cf First', 'cf-first@test.local', 'seller', 'approved');

-- A: rejected, about to retry.
insert into public.seller_business_docs (profile_id, dti_cert_url, verification_status)
values ('cf000000-0000-0000-0000-000000000001',
        'cf000000-0000-0000-0000-000000000001/dti.jpg', 'rejected');

-- B: a first submission still under review.
insert into public.seller_business_docs (profile_id, dti_cert_url, verification_status)
values ('cf000000-0000-0000-0000-000000000002',
        'cf000000-0000-0000-0000-000000000002/dti.jpg', 'pending');

-- ══ 1. SCHEMA + FIRST SUBMISSION ═════════════════════════════════
select has_column('public', 'seller_business_docs', 'resubmitted_at',
                  'the resubmission stamp exists');
select has_column('public', 'seller_business_docs', 'resubmission_count',
                  'the attempt counter exists');

select ok(
  (select resubmitted_at from public.seller_business_docs
    where profile_id = 'cf000000-0000-0000-0000-000000000002') is null,
  'a first submission carries no resubmission stamp'
);
select is(
  (select resubmission_count from public.seller_business_docs
    where profile_id = 'cf000000-0000-0000-0000-000000000002'),
  0,
  'and a zero count'
);

-- ══ 2. THE RETRY IS STAMPED ══════════════════════════════════════
update public.seller_business_docs
   set verification_status = 'pending'
 where profile_id = 'cf000000-0000-0000-0000-000000000001';

select ok(
  (select resubmitted_at from public.seller_business_docs
    where profile_id = 'cf000000-0000-0000-0000-000000000001') is not null,
  'rejected → pending stamps the retry'
);
select is(
  (select resubmission_count from public.seller_business_docs
    where profile_id = 'cf000000-0000-0000-0000-000000000001'),
  1,
  'and counts it as the first retry'
);

-- Keep the stamp to prove the next edit does not move it.
create temp table cf_stamp as
  select resubmitted_at from public.seller_business_docs
   where profile_id = 'cf000000-0000-0000-0000-000000000001';

-- ══ 3. A FILE SWAP IS NOT A RESUBMISSION ═════════════════════════
update public.seller_business_docs
   set verification_status = 'pending',
       dti_cert_url = 'cf000000-0000-0000-0000-000000000001/dti-v2.jpg'
 where profile_id = 'cf000000-0000-0000-0000-000000000001';

select is(
  (select resubmitted_at from public.seller_business_docs
    where profile_id = 'cf000000-0000-0000-0000-000000000001'),
  (select resubmitted_at from cf_stamp),
  'a pending → pending edit leaves the stamp alone'
);
select is(
  (select resubmission_count from public.seller_business_docs
    where profile_id = 'cf000000-0000-0000-0000-000000000001'),
  1,
  'and does not invent another retry'
);

-- ══ 4. A SECOND CYCLE INCREMENTS ════════════════════════════════
update public.seller_business_docs
   set verification_status = 'rejected'
 where profile_id = 'cf000000-0000-0000-0000-000000000001';

update public.seller_business_docs
   set verification_status = 'pending'
 where profile_id = 'cf000000-0000-0000-0000-000000000001';

select is(
  (select resubmission_count from public.seller_business_docs
    where profile_id = 'cf000000-0000-0000-0000-000000000001'),
  2,
  'a second rejection-and-retry is the second attempt'
);

-- ══ 5. THE ADMIN ALERT'S QUERY ═══════════════════════════════════
select is(
  (select count(*) from public.seller_business_docs
    where verification_status = 'pending'
      and resubmitted_at is not null)::int,
  1,
  'the alert count sees the resubmitted seller and not the first timer'
);

-- ══ 6. THE STAMP SURVIVES THE VERDICT ═══════════════════════════
update public.seller_business_docs
   set verification_status = 'verified', verified_at = now()
 where profile_id = 'cf000000-0000-0000-0000-000000000001';

select ok(
  (select resubmitted_at from public.seller_business_docs
    where profile_id = 'cf000000-0000-0000-0000-000000000001') is not null,
  'verifying the retry keeps the record of the attempt'
);
select is(
  (select resubmission_count from public.seller_business_docs
    where profile_id = 'cf000000-0000-0000-0000-000000000001'),
  2,
  'and the attempt count'
);

select * from finish();
rollback;
