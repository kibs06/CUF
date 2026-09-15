-- ══════════════════════════════════════════════════════════════════
-- Admin account-security diagnostics (pgTAP) — run by CI via
-- `supabase test db` (workflow: supabase-migrations.yml)
--
-- Covers migration 20260915160000_add_admin_account_security.sql:
--
--   1. Access: granted to `authenticated` only, and the function itself
--      refuses a non-admin / unauthenticated caller (42501) and an
--      unknown account (P0002).
--   2. The devices block: one phone with a credential and one WITHOUT —
--      the "known device that the gate will refuse" state a support
--      ticket is usually about.
--   3. The event timeline: it must match all THREE identification shapes
--      GoTrue uses. `user_recovery_requested` (the OTP send) carries
--      `actor_id`, while `user_signedup` carries `actor_id` of
--      00000000-…-0000 (the SERVICE ROLE) and puts the real user in
--      `traits.user_id`. A filter on actor_id alone silently drops every
--      signup event, which is exactly the kind of miss this suite exists
--      to catch — so one of the assertions below inserts a service-role-
--      shaped row on purpose.
--   4. Hygiene: no secret hash (or field name) ever reaches the payload,
--      the device objects carry only their documented keys, and the
--      "what we cannot know" notes are present.
--   5. The invariant that makes the gate hold for FUTURE tables: every
--      RLS-enabled public table is either gated or explicitly exempt.
--      A later migration that adds a table without calling
--      install_device_gate_policies() fails here rather than shipping a
--      silently unprotected table.
-- ══════════════════════════════════════════════════════════════════

begin;
select plan(31);

-- ── helpers ───────────────────────────────────────────────────────
create or replace function public.tmp_claims(p_user uuid)
returns text language sql immutable as $$
  select json_build_object('sub', p_user, 'role', 'authenticated')::text;
$$;

-- ── fixtures (as postgres; RLS bypassed) ──────────────────────────
select set_config('request.jwt.claims', '{"sub":null,"role":null}', true);
select set_config('request.headers', '{}', true);

insert into auth.users (instance_id, id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
                        email_confirmed_at, recovery_sent_at, last_sign_in_at)
values
  ('00000000-0000-0000-0000-000000000000', 'a1000000-0000-0000-0000-00000000000a', 'authenticated', 'authenticated', 'sec-admin@test.local',    '{}', '{}', now() - interval '90 days', now(), now(), null, null),
  -- The customer's last_sign_in_at is a FIXED timestamp on purpose: it is
  -- asserted below while the session is switched to `authenticated`, which
  -- has no SELECT on auth.users, so the expected value has to be a literal
  -- rather than a sub-select of the row just inserted.
  ('00000000-0000-0000-0000-000000000000', 'a1000000-0000-0000-0000-00000000000b', 'authenticated', 'authenticated', 'sec-customer@test.local', '{}', '{}', now() - interval '60 days', now(), now() - interval '30 days', now() - interval '1 hour', '2026-07-01 08:30:00+00'::timestamptz),
  ('00000000-0000-0000-0000-000000000000', 'a1000000-0000-0000-0000-00000000000c', 'authenticated', 'authenticated', 'sec-other@test.local',    '{}', '{}', now() - interval '10 days', now(), now(), null, null);

insert into public.profiles (id, full_name, email, role, seller_status)
values
  ('a1000000-0000-0000-0000-00000000000a', 'Sec Admin',    'sec-admin@test.local',    'admin',    'none'),
  ('a1000000-0000-0000-0000-00000000000b', 'Sec Customer', 'sec-customer@test.local', 'customer', 'none'),
  ('a1000000-0000-0000-0000-00000000000c', 'Sec Other',    'sec-other@test.local',    'customer', 'none');

-- The customer's two phones:
--   old-phone-0001 — cleared the step-up long ago and still holds its secret.
--   new-phone-0002 — a trusted_devices row with NO secret: the support case.
insert into public.trusted_devices (user_id, device_id, device_label, first_seen_at, last_seen_at, trusted_at)
values
  ('a1000000-0000-0000-0000-00000000000b', 'old-phone-0001', 'Samsung A15 · Android 14', now() - interval '30 days', now() - interval '2 days', now() - interval '30 days'),
  ('a1000000-0000-0000-0000-00000000000b', 'new-phone-0002', 'Pixel 8 · Android 15',     now() - interval '1 hour',  now() - interval '1 hour',  now() - interval '1 hour');

insert into public.device_secrets (user_id, device_id, secret_hash, minted_at)
values ('a1000000-0000-0000-0000-00000000000b', 'old-phone-0001',
        extensions.digest(repeat('a', 64), 'sha256'), now() - interval '30 days');

insert into public.failed_logins (user_id, ip_address, user_agent, failed_at, locked_until, status, attempt_count)
values ('a1000000-0000-0000-0000-00000000000b', '203.0.113.9', 'CUFMAI/1.0 (Android 15)',
        now() - interval '10 minutes', now() + interval '20 minutes', 'locked', 5);

-- GoTrue's own event stream, in the three shapes it actually uses.
insert into auth.audit_log_entries (id, payload, ip_address, created_at) values
  -- (a) the OTP send: the user is `actor_id`
  ('b1000000-0000-0000-0000-000000000001',
   '{"action":"user_recovery_requested","actor_id":"a1000000-0000-0000-0000-00000000000b","actor_username":"sec-customer@test.local","log_type":"user"}'::json,
   '', now() - interval '1 hour'),
  -- (b) account creation: `actor_id` is the SERVICE ROLE; the user is only in
  --     traits. An actor_id-only filter misses this row entirely.
  ('b1000000-0000-0000-0000-000000000002',
   '{"action":"user_signedup","actor_id":"00000000-0000-0000-0000-000000000000","actor_username":"service_role","log_type":"team","traits":{"user_id":"a1000000-0000-0000-0000-00000000000b","user_email":"sec-customer@test.local"}}'::json,
   '', now() - interval '60 days'),
  -- (c) the OTHER user's event, which must never appear
  ('b1000000-0000-0000-0000-000000000003',
   '{"action":"user_recovery_requested","actor_id":"a1000000-0000-0000-0000-00000000000c","actor_username":"sec-other@test.local","log_type":"user"}'::json,
   '', now() - interval '5 minutes');

-- ══ 1. Structure + access ═════════════════════════════════════════
select has_function('public', 'admin_account_security_overview',
                    array['uuid'], '1: the diagnostics function exists');
select ok(
  has_function_privilege('authenticated', 'public.admin_account_security_overview(uuid)', 'EXECUTE'),
  '2: authenticated may call it'
);
select ok(
  not has_function_privilege('anon', 'public.admin_account_security_overview(uuid)', 'EXECUTE'),
  '3: anon has no EXECUTE grant (no account enumeration without a session)'
);

-- Unauthenticated: auth.uid() is null ⇒ is_admin() is false.
select throws_ok(
  $$select public.admin_account_security_overview('a1000000-0000-0000-0000-00000000000b')$$,
  '42501', 'Only an admin can read account security diagnostics',
  '4: a caller with no session is refused'
);

-- A normal authenticated user: the gate is the ROLE, not the argument, so a
-- user cannot read their own — or anyone else's — diagnostics.
select set_config('request.jwt.claims',
  public.tmp_claims('a1000000-0000-0000-0000-00000000000b'), true);
set local role authenticated;
select throws_ok(
  $$select public.admin_account_security_overview('a1000000-0000-0000-0000-00000000000b')$$,
  '42501', 'Only an admin can read account security diagnostics',
  '5: a normal user is refused, even for their own account'
);
reset role;

select set_config('request.jwt.claims',
  public.tmp_claims('a1000000-0000-0000-0000-00000000000a'), true);
set local role authenticated;
select throws_ok(
  $$select public.admin_account_security_overview('00000000-0000-0000-0000-00000000dead')$$,
  'P0002', 'No account with id 00000000-0000-0000-0000-00000000dead',
  '6: an unknown account is reported, not silently emptied'
);

-- ══ 2. The account block (as the admin) ═══════════════════════════
select is(
  public.admin_account_security_overview('a1000000-0000-0000-0000-00000000000b')
    -> 'account' ->> 'email',
  'sec-customer@test.local',
  '7: the account block reports the subject''s email'
);
select is(
  public.admin_account_security_overview('a1000000-0000-0000-0000-00000000000b')
    -> 'account' ->> 'role',
  'customer',
  '8: …and their role'
);
select is(
  public.admin_account_security_overview('a1000000-0000-0000-0000-00000000000b')
    -> 'account' -> 'email_confirmed',
  'true'::jsonb,
  '9: …and that the address is confirmed'
);
select is(
  public.admin_account_security_overview('a1000000-0000-0000-0000-00000000000b')
    -> 'account' -> 'last_sign_in_at',
  to_jsonb('2026-07-01 08:30:00+00'::timestamptz),
  '10: …and when they last signed in'
);
select is(
  public.admin_account_security_overview('a1000000-0000-0000-0000-00000000000b')
    -> 'account' -> 'has_profile',
  'true'::jsonb,
  '11: …and that a profile row exists'
);

-- ══ 3. The devices block — the actual support question ════════════
select is(
  jsonb_array_length(
    public.admin_account_security_overview('a1000000-0000-0000-0000-00000000000b') -> 'devices'
  )::int,
  2,
  '12: both of the account''s devices are listed'
);
select is(
  public.admin_account_security_overview('a1000000-0000-0000-0000-00000000000b')
    -> 'devices' -> 0 ->> 'device_id',
  'new-phone-0002',
  '13: newest activity first (the phone from the ticket is at the top)'
);
select is(
  public.admin_account_security_overview('a1000000-0000-0000-0000-00000000000b')
    -> 'devices' -> 0 -> 'has_secret',
  'false'::jsonb,
  '14: the new phone is shown as holding NO credential — the gate will refuse it'
);
select is(
  public.admin_account_security_overview('a1000000-0000-0000-0000-00000000000b')
    -> 'devices' -> 1 -> 'has_secret',
  'true'::jsonb,
  '15: the older phone is shown as holding one'
);
select is(
  public.admin_account_security_overview('a1000000-0000-0000-0000-00000000000b')
    -> 'devices' -> 0 -> 'secret_minted_at',
  'null'::jsonb,
  '16: a device with no credential has no mint time'
);
select isnt(
  public.admin_account_security_overview('a1000000-0000-0000-0000-00000000000b')
    -> 'devices' -> 1 -> 'secret_minted_at',
  'null'::jsonb,
  '17: a device with a credential shows when it was minted'
);
select is(
  (select count(*)::int
     from jsonb_object_keys(
       public.admin_account_security_overview('a1000000-0000-0000-0000-00000000000b')
         -> 'devices' -> 0
     )),
  7,
  '18: a device object carries exactly its 7 documented keys'
);

-- ══ 4. The event timeline ═════════════════════════════════════════
select is(
  jsonb_array_length(
    public.admin_account_security_overview('a1000000-0000-0000-0000-00000000000b') -> 'otp_challenges'
  )::int,
  2,
  '19: exactly the subject''s two events — the other account''s is excluded'
);
select ok(
  exists (
    select 1 from jsonb_array_elements(
      public.admin_account_security_overview('a1000000-0000-0000-0000-00000000000b') -> 'otp_challenges'
    ) e where e ->> 'kind' = 'otp_emailed'
  ),
  '20: the emailed OTP is reported (matched via actor_id)'
);
select ok(
  exists (
    select 1 from jsonb_array_elements(
      public.admin_account_security_overview('a1000000-0000-0000-0000-00000000000b') -> 'otp_challenges'
    ) e where e ->> 'kind' = 'account_created'
  ),
  '21: account creation is reported even though its actor_id is the SERVICE '
  'ROLE — the user is only in traits.user_id'
);
select isnt(
  (
    select e ->> 'at' from jsonb_array_elements(
      public.admin_account_security_overview('a1000000-0000-0000-0000-00000000000b') -> 'otp_challenges'
    ) e where e ->> 'kind' = 'otp_emailed'
  ),
  null,
  '22: every event carries its timestamp'
);
select is(
  (
    select e -> 'ip_address' from jsonb_array_elements(
      public.admin_account_security_overview('a1000000-0000-0000-0000-00000000000b') -> 'otp_challenges'
    ) e where e ->> 'kind' = 'otp_emailed'
  ),
  'null'::jsonb,
  '23: an unpopulated ip_address is null, not an empty string'
);

-- ══ 5. Lockouts ══════════════════════════════════════════════════
select is(
  jsonb_array_length(
    public.admin_account_security_overview('a1000000-0000-0000-0000-00000000000b') -> 'lockouts'
  )::int,
  1,
  '24: the password lockout row is reported'
);
select is(
  public.admin_account_security_overview('a1000000-0000-0000-0000-00000000000b')
    -> 'lockouts' -> 0 ->> 'status',
  'locked',
  '25: …with its status'
);
select is(
  public.admin_account_security_overview('a1000000-0000-0000-0000-00000000000b')
    -> 'lockouts' -> 0 -> 'attempt_count',
  '5'::jsonb,
  '26: …and the attempt count'
);

-- ══ 6. The enforcement switch ════════════════════════════════════
select is(
  public.admin_account_security_overview('a1000000-0000-0000-0000-00000000000b')
    -> 'enforcement' -> 'enabled',
  'false'::jsonb,
  '27: an admin can tell whether the gate is even switched on'
);

-- ══ 7. Hygiene ═══════════════════════════════════════════════════
select is(
  jsonb_array_length(
    public.admin_account_security_overview('a1000000-0000-0000-0000-00000000000b') -> 'cannot_answer'
  )::int,
  3,
  '28: the payload states what it cannot know (3 caveats)'
);
select ok(
  position('secret_hash' in
    public.admin_account_security_overview('a1000000-0000-0000-0000-00000000000b')::text) = 0,
  '29: no secret hash FIELD is exposed'
);
select ok(
  position(
    encode(extensions.digest(repeat('a', 64), 'sha256'), 'hex') in
    public.admin_account_security_overview('a1000000-0000-0000-0000-00000000000b')::text
  ) = 0,
  '30: the stored digest VALUE is never returned'
);
reset role;

-- ══ 8. The invariant for future tables ═══════════════════════════
-- The gate policy is installed by a sweep that only sees the tables that
-- exist when it runs, so a later migration adding an RLS table would create
-- it UNGATED. This assertion names any such table, which is what turns
-- "new tables are covered automatically" from a doc claim into a rule.
select is(
  (
    select coalesce(string_agg(c.relname, ', ' order by c.relname), '')
      from pg_class c
      join pg_namespace ns on ns.oid = c.relnamespace
     where c.relkind = 'r'
       and c.relrowsecurity
       and ns.nspname = 'public'
       -- The exemption list is read from the SAME function the installer
       -- uses, so the two can never drift.
       and not (c.relname = any (public.device_gate_exempt_tables()))
       and not exists (
         select 1 from pg_policies p
          where p.schemaname = 'public'
            and p.tablename = c.relname
            and p.policyname = 'Require a trusted device'
       )
  ),
  '',
  '31: every RLS table is either device-gated or explicitly exempt'
);

select * from finish();
rollback;
