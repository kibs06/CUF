-- ══════════════════════════════════════════════════════════════════
-- 3D model requests (roadmap V2.10) — pgTAP
-- Run by CI via `supabase test db` (supabase-migrations.yml)
--
-- Covers `20260928140000_add_shoe_model_requests.sql` and
-- `20260929120000_add_request_size_run_and_upper_height.sql`. The assertions that
-- matter most are marked ⚠️ — each is a way the feature could look right
-- and be wrong:
--
--   ⚠️ The size run is CANONICALISED, not stored as sent (section 10): a
--      hand-written call cannot put a `0` in a column the admin queue renders as
--      fact, and the element-wise band is enforced by the column's own CHECK as
--      well as by the RPC — which is why the constraint's element-wise half is
--      an IMMUTABLE function (a CHECK cannot contain a subquery: 0A000).
--
--   ⚠️ "fulfilled" cannot be a note somebody typed. The status is only
--      reachable through an RPC that requires the model to belong to THIS
--      product AND to be active, and the table's own CHECK refuses
--      `status='fulfilled'` with a NULL `model_id`. Both halves are
--      asserted here, including the CHECK by direct UPDATE.
--   ⚠️ One open ask per product. The partial unique index is asserted by a
--      direct INSERT past the RPC, not only through the RPC path — an
--      index that exists but does not constrain is worse than no index,
--      because the docs would claim it did.
--   ⚠️ A seller cannot write the table directly. There are no seller
--      INSERT / UPDATE / DELETE policies, so the RPCs are the only way in
--      and a crafted client cannot skip the rules.
--   ⚠️ The table is device-gated and NOT exempt. It holds what a seller
--      asked for and what the team wrote back — private business data, the
--      `deletion_requests` side of the line rather than the
--      `product_models` one. (This is the assertion whose absence let
--      `product_models` be gated silently; see the note in the migration.)
--   ⚠️ The seller is TOLD — BOTH endings (V2.12 P3, V2.13 P4). Fulfilling
--      AND declining write the seller a 'models' notification in the same
--      transaction, so "closed" and "told" cannot disagree. The notices that
--      must NOT exist are the point as much as the ones that must: the two
--      refused closes (35/36) write none (assertion 46), and a decline that
--      changed nothing writes none either (assertion 52).
--   ⚠️ …on the bell the seller CAN read (V2.14). The per-user rows above go to
--      `public.notifications`, which the seller app never renders — its feed
--      belongs to the customer shell — so the seller's bell,
--      `public.seller_notifications`, gets the same news written beside it in
--      the same transaction. Asserted with the constraint that makes it
--      possible (53): a type the CHECK refuses is not a notification, it is a
--      failed CLOSE, because the insert runs inside the transaction that
--      answers the ask.
--
-- A NOTE ON ROLES, because this suite is not shaped like the others: the
-- RPC bodies read the caller from `auth.uid()`, which resolves out of the
-- `request.jwt.claims` GUC — NOT out of the SQL role. So the ownership,
-- admin-only and state-machine assertions run as the harness user with the
-- claims switched, and only the two assertions whose SUBJECT is RLS (a
-- hand-crafted INSERT, and a read that must not see another store's row)
-- switch to `authenticated`. Switching for every call would have meant
-- granting the harness's temp table to a client role just to record what an
-- RPC returned, which is noise in a suite about policy.
--
-- A NOTE ON THROWS_OK, because it cost this suite a run: pgTAP's 3-argument
-- `throws_ok(sql, errcode, x)` reads `x` as the ERRMSG pattern, not the
-- description, so every call below puts the description in the FOURTH slot
-- behind an explicit `null` (the `pickup_codes.test.sql`:206 shape). Through
-- the 3-arg form the two failing closing RPCs still raised 42501 and the suite
-- still reported a mismatch — against its own prose.
--
-- AND ON ROW IDENTITY: an RPC argument that names a request resolves through
-- `tmp_req_open_id()`, never through `where product_id = …` alone. This suite
-- files, withdraws, then REFILES product 21 (assertion 28, which is how the
-- partial index is proved), so from the team's half of the run onwards that
-- product carries a cancelled row beside the open one. The bare subquery then
-- returns two rows — a 21000 that aborts the run at whatever assertion happens
-- to be next, instead of failing the one assertion that is wrong.
-- ══════════════════════════════════════════════════════════════════

begin;
select plan(76);

-- ── helpers ────────────────────────────────────────────────────────
create or replace function public.tmp_req_claims(p_user uuid)
returns text language sql immutable as $$
  select json_build_object('sub', p_user, 'role', 'authenticated')::text;
$$;

-- RPC results are captured once and read from here: calling an RPC twice to
-- assert two things about it would trip the very rules under test (the
-- second `request_shoe_model` for a product is refused on purpose).
create temp table tmp_req_results (k text primary key, v json) on commit drop;

create or replace function public.tmp_req_ok(p_result json)
returns boolean language sql immutable as $$
  select coalesce((p_result ->> 'success')::boolean, false);
$$;

create or replace function public.tmp_req_msg(p_result json)
returns text language sql immutable as $$
  select coalesce(p_result ->> 'message', '');
$$;

-- The queue's identity is the OPEN ask, and a product can carry a closed one
-- beside it (assertion 28 asks again after a withdrawal). `uq_shoe_model_requests_open`
-- is what makes this unique; the `limit 1` is belt and braces for the reader.
create or replace function public.tmp_req_open_id(p_product uuid)
returns uuid language sql stable as $$
  select id from public.shoe_model_requests
   where product_id = p_product
     and status in ('requested', 'in_progress')
   limit 1;
$$;

select set_config('request.jwt.claims', '{"sub":null,"role":null}', true);
select set_config('request.headers', '{}', true);

-- ── fixtures (RLS bypassed) ────────────────────────────────────────
insert into auth.users (instance_id, id, aud, role, email, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000','f1000000-0000-0000-0000-000000000001','authenticated','authenticated','rq-seller@test.local', now(), now()),
  ('00000000-0000-0000-0000-000000000000','f1000000-0000-0000-0000-000000000002','authenticated','authenticated','rq-other@test.local',  now(), now()),
  ('00000000-0000-0000-0000-000000000000','f1000000-0000-0000-0000-000000000003','authenticated','authenticated','rq-admin@test.local',  now(), now()),
  ('00000000-0000-0000-0000-000000000000','f1000000-0000-0000-0000-000000000004','authenticated','authenticated','rq-cust@test.local',   now(), now());

insert into public.profiles (id, full_name, email, role, seller_status)
values
  ('f1000000-0000-0000-0000-000000000001','Rq Seller','rq-seller@test.local','seller','approved'),
  ('f1000000-0000-0000-0000-000000000002','Rq Other','rq-other@test.local','seller','approved'),
  ('f1000000-0000-0000-0000-000000000003','Rq Admin','rq-admin@test.local','admin','none'),
  ('f1000000-0000-0000-0000-000000000004','Rq Customer','rq-cust@test.local','customer','none');

insert into public.stores (id, owner_id, name, location)
values
  ('f1000000-0000-0000-0000-000000000011','f1000000-0000-0000-0000-000000000001','Rq Store','Rq City'),
  ('f1000000-0000-0000-0000-000000000012','f1000000-0000-0000-0000-000000000002','Rq Store Two','Rq City');

insert into public.products (id, store_id, seller_id, name, price, is_active)
values
  -- The product the main flow runs on: no live model.
  ('f1000000-0000-0000-0000-000000000021','f1000000-0000-0000-0000-000000000011','f1000000-0000-0000-0000-000000000001','Rq Shoe', 1500, true),
  -- Has a live model from the start, for the "nothing to request" branch.
  ('f1000000-0000-0000-0000-000000000022','f1000000-0000-0000-0000-000000000011','f1000000-0000-0000-0000-000000000001','Rq Shoe Live', 1500, true),
  -- Another store's product, for ownership and cross-store reads.
  ('f1000000-0000-0000-0000-000000000023','f1000000-0000-0000-0000-000000000012','f1000000-0000-0000-0000-000000000002','Rq Shoe Two', 900, true);

-- Product 21 gets a DRAFT model: a draft must not block a request (the seller
-- tried, it was not published, they still need help). Product 22 gets an
-- ACTIVE one, which must block it. Version 2 is kept for the live model added
-- later, because `uq_product_models_default_version` constrains
-- (product_id, version) whatever the status — so version 1 is taken here.
insert into public.product_models (product_id, storage_path, sha256, version, status, authored_length_mm)
values
  ('f1000000-0000-0000-0000-000000000021',
   'shoe-models/f1000000-0000-0000-0000-000000000011/f1000000-0000-0000-0000-000000000021/' || repeat('a',64) || '.glb',
   repeat('a',64), 1, 'draft', 270),
  ('f1000000-0000-0000-0000-000000000022',
   'shoe-models/f1000000-0000-0000-0000-000000000011/f1000000-0000-0000-0000-000000000022/' || repeat('b',64) || '.glb',
   repeat('b',64), 1, 'active', 268);

-- ══ 1. Structure ═══════════════════════════════════════════════════
select has_table('public','shoe_model_requests','1: the table exists');
-- ⚠️ EIGHT arguments since 2026-09-29, and the count is the assertion: adding
-- the height and the run meant DROP + CREATE (a replaced function cannot change
-- its argument list), so the six-argument signature must be GONE. A leftover
-- one beside it would make the app's named-argument call ambiguous — the reason
-- `20260929120000` drops before it creates.
select has_function('public','request_shoe_model',
                    array['uuid','numeric','numeric','numeric','numeric','text','numeric','numeric[]'],
                    '2: the seller''s request RPC exists (8-arg, height and run included)');
select has_function('public','cancel_shoe_model_request', array['uuid'],
                    '3: the seller can withdraw an ask');
select has_function('public','claim_shoe_model_request', array['uuid'],
                    '4: an admin can take an ask');
select has_function('public','fulfil_shoe_model_request',
                    array['uuid','bigint','text'],
                    '5: fulfil takes a BIGINT model id — product_models.id is an identity column');
select has_function('public','decline_shoe_model_request', array['uuid','text'],
                    '6: an admin can decline with a reason');
select has_index('public','shoe_model_requests','uq_shoe_model_requests_open',
                 '7: one open ask per product is an index, not a convention');
select is(
  (select count(*)::int from pg_constraint
    where conrelid = 'public.shoe_model_requests'::regclass and contype = 'c'),
  8,
  '8: all eight CHECK constraints are present (status, five bounds, the run, fulfilled-needs-model)'
);

-- ⚠️ The device gate: gated, and not exempt.
select is(
  (select count(*)::int from pg_policies
    where schemaname='public' and tablename='shoe_model_requests'
      and policyname='Require a trusted device'),
  1,
  '9: the table is device-gated (the migration called install_device_gate_policies)'
);
select ok(
  not ('shoe_model_requests' = any (public.device_gate_exempt_tables())),
  '10: …and it is NOT in the exemption list'
);

-- ⚠️ No seller write policies. Exactly one write policy exists and it is the
-- admin's, so the RPCs are the only way a seller can change anything.
select is(
  (select count(*)::int from pg_policies
    where schemaname='public' and tablename='shoe_model_requests'
      and cmd in ('INSERT','UPDATE','DELETE')),
  1,
  '11: one write policy only, and it is the admin''s'
);
select is(
  (select count(*)::int from pg_policies
    where schemaname='public' and tablename='shoe_model_requests'
      and policyname = 'Admins can update model requests'),
  1,
  '12: …and that write policy is `Admins can update model requests`'
);

-- ══ 2. The seller files the ask ════════════════════════════════════
select set_config('request.jwt.claims',
  public.tmp_req_claims('f1000000-0000-0000-0000-000000000001'), true);

insert into tmp_req_results (k, v)
select 'file', public.request_shoe_model(
  'f1000000-0000-0000-0000-000000000021'::uuid, 272.0, 105.0, 25.0, 42.0,
  'Samples are with the team already.');

select is((select tmp_req_ok(v) from tmp_req_results where k='file'), true,
          '13: the store owner can file an ask');
select is(
  (select status from public.shoe_model_requests
    where product_id = 'f1000000-0000-0000-0000-000000000021'),
  'requested',
  '14: …and it lands as `requested`');
-- Denormalised on purpose: the policy and the queue read it without a join.
select is(
  (select store_id from public.shoe_model_requests
    where product_id = 'f1000000-0000-0000-0000-000000000021'),
  'f1000000-0000-0000-0000-000000000011'::uuid,
  '15: …with the store taken from the product, not from the caller'
);
select is(
  (select note from public.shoe_model_requests
    where product_id = 'f1000000-0000-0000-0000-000000000021'),
  'Samples are with the team already.',
  '16: …and the seller''s note came through'
);
-- The length here is the EXTERNAL one: the figure the renderer scales to, not
-- the internal last length the fit verdict uses (guide §5).
select is(
  (select external_length_mm from public.shoe_model_requests
    where product_id = 'f1000000-0000-0000-0000-000000000021'),
  272.0::numeric,
  '17: …and the external length is stored as given'
);

-- A second ask for the same product: refused in the seller's language, not as
-- a 23505 from the index underneath.
insert into tmp_req_results (k, v)
select 'dup', public.request_shoe_model(
  'f1000000-0000-0000-0000-000000000021'::uuid, 272.0);
select is((select tmp_req_ok(v) from tmp_req_results where k='dup'), false,
          '18: a second ask for the same product is refused');
select ok(
  position('already asked' in (select tmp_req_msg(v) from tmp_req_results where k='dup')) > 0,
  '19: …and the sentence says so rather than naming a constraint'
);

-- A 40 mm shoe is a typo, and the band is the mesh declaration's.
insert into tmp_req_results (k, v)
select 'short', public.request_shoe_model(
  'f1000000-0000-0000-0000-000000000021'::uuid, 40.0);
select is((select tmp_req_ok(v) from tmp_req_results where k='short'), false,
          '20: an implausible length is refused with something to do about it');

-- A product that already has a LIVE model has nothing to ask for.
insert into tmp_req_results (k, v)
select 'live', public.request_shoe_model(
  'f1000000-0000-0000-0000-000000000022'::uuid, 268.0);
select is((select tmp_req_ok(v) from tmp_req_results where k='live'), false,
          '21: a product with an active model cannot be asked about');
select ok(
  position('already has a 3D model' in (select tmp_req_msg(v) from tmp_req_results where k='live')) > 0,
  '22: …and the seller is told why instead of the ask vanishing'
);

-- ⚠️ Another store's product is not the caller's to ask about.
select throws_ok(
  $$select public.request_shoe_model('f1000000-0000-0000-0000-000000000023'::uuid, 260.0)$$,
  '42501',
  null,
  '23: asking about another store''s product is refused'
);

-- ⚠️ RLS IS THE SUBJECT HERE, so this one runs as a real client role: no
-- INSERT policy exists, so a hand-crafted write cannot skip the rules the
-- RPCs enforce.
set local role authenticated;
select throws_ok(
  $$insert into public.shoe_model_requests
      (product_id, store_id, requested_by, external_length_mm)
    values ('f1000000-0000-0000-0000-000000000023'::uuid,
            'f1000000-0000-0000-0000-000000000011'::uuid,
            'f1000000-0000-0000-0000-000000000001'::uuid, 260.0)$$,
  '42501',
  null,
  '24: a hand-crafted INSERT is refused, so the rules cannot be skipped'
);
reset role;

-- The other store files its own ask, so the cross-store read has something to
-- hide. Filed directly for the same reason: this suite is about one store's
-- view of the queue.
insert into public.shoe_model_requests
  (product_id, store_id, requested_by, external_length_mm, status)
values ('f1000000-0000-0000-0000-000000000023'::uuid,
        'f1000000-0000-0000-0000-000000000012'::uuid,
        'f1000000-0000-0000-0000-000000000002'::uuid, 258.0, 'requested');

-- ⚠️ …and the seller reads exactly one row, not two.
set local role authenticated;
select is(
  (select count(*)::int from public.shoe_model_requests),
  1,
  '25: the seller reads their own store''s ask and only that one'
);
reset role;

-- ══ 3. The seller withdraws, and can ask again ═════════════════════
select set_config('request.jwt.claims',
  public.tmp_req_claims('f1000000-0000-0000-0000-000000000001'), true);

insert into tmp_req_results (k, v)
select 'cancel', public.cancel_shoe_model_request(
  public.tmp_req_open_id('f1000000-0000-0000-0000-000000000021'));
select is((select tmp_req_ok(v) from tmp_req_results where k='cancel'), true,
          '26: the owner can withdraw an open ask');
select is(
  (select status from public.shoe_model_requests
    where product_id = 'f1000000-0000-0000-0000-000000000021'),
  'cancelled',
  '27: …and it reads as cancelled, not deleted'
);

-- The unique index is PARTIAL, which is what makes a re-ask possible.
insert into tmp_req_results (k, v)
select 'refile', public.request_shoe_model(
  'f1000000-0000-0000-0000-000000000021'::uuid, 272.0);
select is((select tmp_req_ok(v) from tmp_req_results where k='refile'), true,
          '28: after a withdrawal the seller can ask again (the index is partial)');

-- ⚠️ A duplicate OPEN ask is blocked by the index itself, past the RPC.
select throws_ok(
  $$insert into public.shoe_model_requests
      (product_id, store_id, requested_by, external_length_mm, status)
    values ('f1000000-0000-0000-0000-000000000021'::uuid,
            'f1000000-0000-0000-0000-000000000011'::uuid,
            'f1000000-0000-0000-0000-000000000001'::uuid, 272.0, 'in_progress')$$,
  '23505',
  null,
  '29: one open ask per product holds even against a direct INSERT'
);

-- ⚠️ Admins only, and the guard is in the function body.
select throws_ok(
  $$select public.claim_shoe_model_request(
      public.tmp_req_open_id('f1000000-0000-0000-0000-000000000021'))$$,
  '42501',
  null,
  '30: a seller cannot claim an ask'
);
select throws_ok(
  $$select public.decline_shoe_model_request(
      public.tmp_req_open_id('f1000000-0000-0000-0000-000000000021'), 'no')$$,
  '42501',
  null,
  '31: a seller cannot decline an ask'
);
select throws_ok(
  $$select public.fulfil_shoe_model_request(
      public.tmp_req_open_id('f1000000-0000-0000-0000-000000000021'), 1)$$,
  '42501',
  null,
  '32: a seller cannot close an ask as fulfilled'
);

-- ══ 4. The team's half ═════════════════════════════════════════════
select set_config('request.jwt.claims',
  public.tmp_req_claims('f1000000-0000-0000-0000-000000000003'), true);

insert into tmp_req_results (k, v)
select 'claim', public.claim_shoe_model_request(
  public.tmp_req_open_id('f1000000-0000-0000-0000-000000000021'));
select is((select tmp_req_ok(v) from tmp_req_results where k='claim'), true,
          '33: an admin can claim an ask');
select is(
  (select status || ':' || assigned_to::text from public.shoe_model_requests
    where id = public.tmp_req_open_id('f1000000-0000-0000-0000-000000000021')),
  'in_progress:f1000000-0000-0000-0000-000000000003',
  '34: …and the queue now says who has it'
);

-- ⚠️ Closing as fulfilled is a claim about a specific artifact, so both halves
-- of that claim are refused here: the wrong product's model, and one that is
-- not live yet.
insert into tmp_req_results (k, v)
select 'wrong_product', public.fulfil_shoe_model_request(
  public.tmp_req_open_id('f1000000-0000-0000-0000-000000000021'),
  (select id from public.product_models
    where product_id = 'f1000000-0000-0000-0000-000000000022'));
select is((select tmp_req_ok(v) from tmp_req_results where k='wrong_product'), false,
          '35: a model belonging to another product cannot close the request');

insert into tmp_req_results (k, v)
select 'draft_model', public.fulfil_shoe_model_request(
  public.tmp_req_open_id('f1000000-0000-0000-0000-000000000021'),
  (select id from public.product_models
    where product_id = 'f1000000-0000-0000-0000-000000000021'
      and status = 'draft'));
select is((select tmp_req_ok(v) from tmp_req_results where k='draft_model'), false,
          '36: …and a model that is still a draft cannot close it either');
select ok(
  position('draft' in (select tmp_req_msg(v) from tmp_req_results where k='draft_model')) > 0,
  '37: …and the sentence names the state, so the fix is obvious'
);

-- The team's upload, in miniature. The claims are cleared first because
-- `enforce_product_model_server_validation()` refuses `status='active'` to any
-- session carrying a JWT role — that door is checked against the GUC, not the
-- SQL role, so it is the same door the Edge Function uses.
select set_config('request.jwt.claims', '{"sub":null,"role":null}', true);
insert into public.product_models
  (product_id, storage_path, sha256, version, status, authored_length_mm)
values ('f1000000-0000-0000-0000-000000000021',
        'shoe-models/f1000000-0000-0000-0000-000000000011/f1000000-0000-0000-0000-000000000021/' || repeat('c',64) || '.glb',
        repeat('c',64), 2, 'active', 272);

select set_config('request.jwt.claims',
  public.tmp_req_claims('f1000000-0000-0000-0000-000000000003'), true);

insert into tmp_req_results (k, v)
select 'fulfil', public.fulfil_shoe_model_request(
  public.tmp_req_open_id('f1000000-0000-0000-0000-000000000021'),
  (select id from public.product_models
    where product_id = 'f1000000-0000-0000-0000-000000000021'
      and status = 'active'),
  'Modelled from the samples; length checked on the bench.');
select is((select tmp_req_ok(v) from tmp_req_results where k='fulfil'), true,
          '38: …and the same request closes against a live model of the right product');
-- Read by the row that CLOSED, not the open one: product 21 carries the
-- cancelled ask from assertion 26 as well, which is why these two filter on
-- the status they are asserting rather than on the product alone.
select is(
  (select status from public.shoe_model_requests
    where product_id = 'f1000000-0000-0000-0000-000000000021'
      and status = 'fulfilled'),
  'fulfilled',
  '39: …reading as fulfilled'
);
select ok(
  (select model_id is not null from public.shoe_model_requests
    where product_id = 'f1000000-0000-0000-0000-000000000021'
      and status = 'fulfilled'),
  '40: …and naming the model, so the status is a fact rather than a claim'
);

-- ⚠️ The CHECK is the backstop for a hand-written UPDATE that skips the RPC.
-- The other store's ask is still open, so it is the honest candidate.
select throws_ok(
  $$update public.shoe_model_requests set status = 'fulfilled'
     where product_id = 'f1000000-0000-0000-0000-000000000023'$$,
  '23514',
  null,
  '41: a direct UPDATE cannot reach `fulfilled` without a model_id'
);

-- ══ 7. The seller is told (V2.11, P3) ══════════════════════════════
-- The claim being tested is not "a notification exists" but "the person who
-- asked is the person told, once, by the same transaction that closed it".
-- The recipient is asserted by id rather than by count alone, because a notice
-- sent to the wrong seller is worse than none: they would go looking for a
-- model on a product that is not theirs.
select is(
  (select count(*) from public.notifications
    where category = 'models'
      and user_id = 'f1000000-0000-0000-0000-000000000001'),
  1::bigint,
  '42: closing as fulfilled notifies the seller who asked — exactly once'
);

select is(
  (select title from public.notifications
    where category = 'models'
      and user_id = 'f1000000-0000-0000-0000-000000000001'),
  'Your 3D model is ready',
  '43: …with the sentence the seller reads in their notification feed'
);

select ok(
  position('Rq Shoe' in (
    select message from public.notifications
     where category = 'models'
       and user_id = 'f1000000-0000-0000-0000-000000000001')) > 0,
  '44: …naming the product, so the notice is about a specific pair'
);

-- The metadata is the payload a deep link would need. Nothing reads it yet
-- (P3 deliberately does not route), which is exactly why it is pinned here:
-- an unread field that is silently wrong stays wrong forever.
select is(
  (select metadata ->> 'product_id' from public.notifications
    where category = 'models'
      and user_id = 'f1000000-0000-0000-0000-000000000001'),
  'f1000000-0000-0000-0000-000000000021',
  '45: …and carrying the product id, for the deep link this phase does not build'
);

-- ⚠️ One ask, one notice. The two refused closes (35: another product's model,
-- 36: a model that is still a draft) must have written nothing — a seller told
-- "it is ready" about a model that never went live would open the page and find
-- nothing there, and would distrust the next notice.
select is(
  (select count(*) from public.notifications where category = 'models'),
  1::bigint,
  '46: and the two refused closes told nobody — one ask, one notice'
);

-- ══ 8. A decline tells the seller too (V2.13, P4) ══════════════════
-- The other half of the same act, and the LARGER silence of the two: "we could
-- not make one" is the outcome a seller most needs early, and before this it
-- waited in the row for whoever happened to open the product's action sheet.
-- The two notices share a category on purpose — the subject is the seller's 3D
-- model request — so the TITLE is what says which way it went (assertion 50).
--
-- The other store's ask is this section's subject, which also proves the
-- recipient is the filer and not the admin who acted: it was filed by Rq Other
-- (…0002) and the decline is run as Rq Admin (…0003).
select set_config('request.jwt.claims',
  public.tmp_req_claims('f1000000-0000-0000-0000-000000000003'), true);

insert into tmp_req_results (k, v)
select 'decline', public.decline_shoe_model_request(
  public.tmp_req_open_id('f1000000-0000-0000-0000-000000000023'),
  'The samples were not clear enough to model from.');
select is((select tmp_req_ok(v) from tmp_req_results where k='decline'), true,
          '47: an admin declines an open ask, with a reason');

select is(
  (select count(*) from public.notifications
    where category = 'models'
      and user_id = 'f1000000-0000-0000-0000-000000000002'),
  1::bigint,
  '48: …and the seller who asked is told — not the admin who declined it'
);

select ok(
  position('not clear enough' in (
    select message from public.notifications
     where category = 'models'
       and user_id = 'f1000000-0000-0000-0000-000000000002')) > 0,
  '49: …reading the reason the admin typed, which is why a reason is required'
);

select is(
  (select title from public.notifications
    where category = 'models'
      and user_id = 'f1000000-0000-0000-0000-000000000002'),
  'Your 3D model request was declined',
  '50: …under a title that says which way it went, since both endings share a category'
);

-- ⚠️ A decline that changed nothing must tell nobody. The fulfilled ask is the
-- honest candidate: it is closed, so the RPC reports not-found-or-closed and
-- writes nothing. A notice here would be the worst kind of wrong — a seller
-- told "declined" about a model that is live on their product.
insert into tmp_req_results (k, v)
select 'decline_closed', public.decline_shoe_model_request(
  (select id from public.shoe_model_requests
    where product_id = 'f1000000-0000-0000-0000-000000000021'
      and status = 'fulfilled'),
  'already done');
select is((select tmp_req_ok(v) from tmp_req_results where k='decline_closed'), false,
          '51: declining an already-closed ask is refused');

select is(
  (select count(*) from public.notifications where category = 'models'),
  2::bigint,
  '52: …and wrote no notice — two real endings, two notices, ever'
);

-- ══ 9. …and on the bell the seller actually reads (V2.14) ══════════
-- The two notices above are addressed to the seller's USER, in
-- `public.notifications` — which the seller app never renders: that feed
-- belongs to the customer shell, while a seller's session lands in
-- `SellerShell`, whose bell reads `public.seller_notifications`, keyed by
-- STORE. So V2.12/V2.13 told the right person on a channel they cannot open,
-- and this section is the correction: both endings now also write the
-- store-scoped row the bell renders, in the same transaction.
--
-- ⚠️ The constraint first, because everything below depends on it: a type the
-- CHECK refuses is a row that is never written, and the insert failure would
-- take the whole CLOSE down with it — the seller's ask would stay open because
-- the database declined to file a notification about it.
select ok(
  (select pg_get_constraintdef(oid) from pg_constraint
    where conrelid = 'public.seller_notifications'::regclass
      and conname = 'seller_notifications_type_check') like '%model_request%',
  '53: the seller-notification type CHECK admits model_request'
);

-- ⚠️ The rows the bell lights up on. `is_read` is asserted because a notice the
-- seller is never told about (an already-read row) is the silent version of
-- this whole feature.
select is(
  (select count(*) from public.seller_notifications
    where store_id = 'f1000000-0000-0000-0000-000000000011'
      and type = 'model_request'),
  1::bigint,
  '54: fulfilling puts one model notice on the ASKING store''s bell'
);

select is(
  (select is_read from public.seller_notifications
    where store_id = 'f1000000-0000-0000-0000-000000000011'
      and type = 'model_request'),
  false,
  '55: …unread, so the badge on the bell actually lights'
);

-- The tap: the seller centre routes `reference_id` to the product's actions
-- sheet, which is where the request row and the model both live.
select is(
  (select reference_id from public.seller_notifications
    where store_id = 'f1000000-0000-0000-0000-000000000011'
      and type = 'model_request'),
  'f1000000-0000-0000-0000-000000000021'::uuid,
  '56: …pointing at the product, which is what tapping it opens'
);

-- The decline's row, and the one thing this whole path exists to carry: the
-- admin's own reason. The admin screen refuses to decline without one, and a
-- notice that dropped it would make that requirement cosmetic.
select is(
  (select count(*) from public.seller_notifications
    where store_id = 'f1000000-0000-0000-0000-000000000012'
      and type = 'model_request'),
  1::bigint,
  '57: declining puts one on the OTHER store''s bell — the asker''s, not the admin''s'
);

select ok(
  position('not clear enough' in (
    select body from public.seller_notifications
     where store_id = 'f1000000-0000-0000-0000-000000000012'
       and type = 'model_request')) > 0,
  '58: …carrying the reason the admin typed, on the bell as in the feed'
);

select is(
  (select title from public.seller_notifications
    where store_id = 'f1000000-0000-0000-0000-000000000012'
      and type = 'model_request'),
  'Your 3D model request was declined',
  '59: …under a title that says which way it went'
);

-- ⚠️ Two endings, two bell rows — and crucially the refused decline (51) wrote
-- none: `seller_notifications` has no category or status of its own, so a row
-- written for a close that did not happen would light a bell for nothing.
select is(
  (select count(*) from public.seller_notifications
    where type = 'model_request'),
  2::bigint,
  '60: …and the refused decline left both bells alone — two real endings, two rows'
);

-- ══ 10. The run and the shoe height (2026-09-29) ═══════════════════
-- The two questions the sheet gained after the first one shipped
-- (`20260929120000`). Both optional, both about the seller's catalogue rather
-- than the pair on the bench, and neither scales anything: one model serves
-- every size. What is worth proving here is the pair of failures a hand-written
-- call could reach and a seller could not — a stray value in the run and a
-- height outside the band — and the fact that the run is CANONICALISED rather
-- than stored as sent.
--
-- ⚠️ On their own products: section 2's product 21 carries the open ask the
-- whole file runs on, and a second ask for it is refused on purpose (18).
insert into public.products (id, store_id, seller_id, name, price, is_active)
values
  ('f1000000-0000-0000-0000-000000000024','f1000000-0000-0000-0000-000000000011','f1000000-0000-0000-0000-000000000001','Rq Shoe Run', 1500, true),
  ('f1000000-0000-0000-0000-000000000025','f1000000-0000-0000-0000-000000000011','f1000000-0000-0000-0000-000000000001','Rq Shoe Height', 1500, true),
  ('f1000000-0000-0000-0000-000000000026','f1000000-0000-0000-0000-000000000011','f1000000-0000-0000-0000-000000000001','Rq Shoe Empty', 1500, true),
  ('f1000000-0000-0000-0000-000000000027','f1000000-0000-0000-0000-000000000011','f1000000-0000-0000-0000-000000000001','Rq Shoe Wide', 1500, true);

select has_column('public','shoe_model_requests','upper_height_mm',
                  '61: the request carries the shoe''s overall height');
select has_column('public','shoe_model_requests','sizes_eu',
                  '62: …and the run of EU sizes the shoe is made in');

select set_config('request.jwt.claims',
  public.tmp_req_claims('f1000000-0000-0000-0000-000000000001'), true);

-- The run arrives as a hand-written caller would send it: out of order, with a
-- duplicate and a value outside the band. The seller's chips cannot produce that
-- shape, which is exactly why the RPC has to.
insert into tmp_req_results (k, v)
select 'run', public.request_shoe_model(
  'f1000000-0000-0000-0000-000000000024'::uuid, 270.0, null, null, null, null,
  40.0, array[42.0, 40.0, 42.0, 0.0, 43.0]::numeric[]);

select is((select tmp_req_ok(v) from tmp_req_results where k='run'), true,
          '63: an ask carrying the height and a run is accepted');
select is(
  (select cardinality(sizes_eu) from public.shoe_model_requests
    where product_id = 'f1000000-0000-0000-0000-000000000024'),
  3,
  '64: …and the run is stored deduplicated — five values sent, three stored'
);
-- Ascending and in band, which is what "canonicalised" means here: element 1 is
-- the smallest, so the stray 0 is provably gone rather than merely not last.
select is(
  (select sizes_eu[1] from public.shoe_model_requests
    where product_id = 'f1000000-0000-0000-0000-000000000024'),
  40::numeric,
  '65: …ascending, with the out-of-band value trimmed'
);
select is(
  (select sizes_eu[3] from public.shoe_model_requests
    where product_id = 'f1000000-0000-0000-0000-000000000024'),
  43::numeric,
  '66: …and the largest last'
);
select is(
  (select upper_height_mm from public.shoe_model_requests
    where product_id = 'f1000000-0000-0000-0000-000000000024'),
  40::numeric,
  '67: …and the height is stored, the one dimension no other column carries'
);

-- A 900 mm shoe is a slip, not a very tall sandal, and the band is the column's.
insert into tmp_req_results (k, v)
select 'tall', public.request_shoe_model(
  'f1000000-0000-0000-0000-000000000025'::uuid, 270.0, null, null, null, null, 900.0);
select is((select tmp_req_ok(v) from tmp_req_results where k='tall'), false,
          '68: a shoe height outside the band is refused');
select ok(
  position('10 and 400' in (select tmp_req_msg(v) from tmp_req_results where k='tall')) > 0,
  '69: …in the same sentence the sheet would give, so the fix is obvious'
);

-- ⚠️ A run that said nothing usable is NOT an error: the seller answered a
-- question they were not required to answer, and refusing the whole ask over it
-- would throw away the measurement the request exists for.
insert into tmp_req_results (k, v)
select 'junk', public.request_shoe_model(
  'f1000000-0000-0000-0000-000000000025'::uuid, 270.0, null, null, null, null,
  null, array[0.0, 999.0]::numeric[]);
select is((select tmp_req_ok(v) from tmp_req_results where k='junk'), true,
          '70: a run with nothing usable in it still files the request');
select ok(
  (select sizes_eu is null from public.shoe_model_requests
    where product_id = 'f1000000-0000-0000-0000-000000000025'),
  '71: …stored as not stated, which is what NULL means here'
);

-- ⚠️ The column's own CHECK, past the RPC — the two shapes the RPC can never
-- produce. This is where the element-wise test had to become an IMMUTABLE
-- FUNCTION: the obvious writing of it returns
-- `0A000: cannot use subquery in check constraint`, and `array_length` cannot
-- see an empty array at all (`array_length('{}',1)` is NULL, and a CHECK is
-- satisfied by NULL).
--
-- Two products rather than one, so a future edit that lets the first INSERT
-- through reports the second as its own failure instead of as a 23505 from the
-- unique open-ask index.
select throws_ok(
  $$insert into public.shoe_model_requests
      (product_id, store_id, requested_by, external_length_mm, sizes_eu)
    values ('f1000000-0000-0000-0000-000000000026'::uuid,
            'f1000000-0000-0000-0000-000000000011'::uuid,
            'f1000000-0000-0000-0000-000000000001'::uuid, 270.0, '{}')$$,
  '23514',
  null,
  '72: an EMPTY run is refused — `{}` claims the shoe is made in no sizes'
);
select throws_ok(
  $$insert into public.shoe_model_requests
      (product_id, store_id, requested_by, external_length_mm, sizes_eu)
    values ('f1000000-0000-0000-0000-000000000027'::uuid,
            'f1000000-0000-0000-0000-000000000011'::uuid,
            'f1000000-0000-0000-0000-000000000001'::uuid, 270.0, array[40.0, 999.0])$$,
  '23514',
  null,
  '73: …and so is a run holding a size no shoe is made in'
);

-- The helper's own edges, called directly. A CHECK is satisfied by NULL, so the
-- one answer this function must never give is NULL — not for an empty array, and
-- not for one holding a null element.
select is(public.numeric_array_within_band(array[40.0, 42.5]::numeric[], 22, 48), true,
          '74: the element-wise helper accepts a run inside the band');
select is(public.numeric_array_within_band(array[]::numeric[], 22, 48), false,
          '75: …answers false (never NULL) for an empty array');
select is(public.numeric_array_within_band(array[null, 42.0]::numeric[], 22, 48), false,
          '76: …and for a run carrying a null element');

select * from finish();
rollback;
