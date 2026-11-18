-- ══════════════════════════════════════════════════════════════════
-- Migration + self-check: Admin read access to manual-GCash payment proofs
-- Date: 2026-11-18
--
-- ONE PASTE. Part 1 applies the policy and COMMITS. Part 2 proves it and
-- ROLLS BACK, so the impersonation used to test RLS cannot outlive the run
-- and nothing in Part 2 can undo the apply.
--
-- WHY THIS EXISTS
--   The admin Payment verification queue reported "No proof submitted yet"
--   on orders whose proof demonstrably exists — including rows it was already
--   showing as "Verified — preparing", which cannot have been verified
--   without a proof.
--
--   The cause is RLS, not the query. The page embeds the proofs through
--   PostgREST (`orders → gcash_payment_proofs(...)`), and the policies from
--   20260808200000 cover only the order's customer and its store's seller.
--   RLS filters rows rather than raising: the embed comes back as `[]`, and
--   the page renders that as "nothing submitted". An admin could therefore
--   never read a reference, a sender or an amount — the three facts this
--   screen exists to check — nor open the receipt.
--
--   The screenshot layer is already covered: 20261118020000 §4 added
--   "Admins can read payment proofs" on storage.objects for this bucket, so
--   createSignedUrl works for an admin. Deliberate: this file adds nothing
--   there rather than ship a second policy that ORs with it and hides which
--   one is doing the work.
--
--   The gate is public.is_admin() — the same helper every other admin surface
--   uses (20260809120000, 20260810000000). It reads the role without
--   re-entering profiles RLS and excludes suspended accounts, so a suspended
--   admin loses the queue again immediately.
--
--   Read-only: no INSERT/UPDATE/DELETE is granted. Proofs stay written by the
--   SECURITY DEFINER submit RPC alone.
-- ══════════════════════════════════════════════════════════════════


-- ══════════════════════════════════════════════════════════════════
-- PART 1 — APPLY (committed)
-- ══════════════════════════════════════════════════════════════════
begin;

-- Idempotent: re-running replaces the policy rather than erroring.
DROP POLICY IF EXISTS "Admins can read all payment proofs"
  ON public.gcash_payment_proofs;
CREATE POLICY "Admins can read all payment proofs"
  ON public.gcash_payment_proofs FOR SELECT
  USING (public.is_admin());

COMMENT ON POLICY "Admins can read all payment proofs"
  ON public.gcash_payment_proofs IS
  'The admin verification queue embeds these rows. Without this policy the embed is filtered to [] and the queue reports "no proof submitted" for orders that have one.';

commit;


-- ══════════════════════════════════════════════════════════════════
-- PART 2 — PROVE IT (read-only; ends in ROLLBACK)
--
-- The SQL Editor session runs as `postgres`, which BYPASSES RLS — so a bare
-- `select count(*) from gcash_payment_proofs` proves nothing about the new
-- policy. These blocks impersonate a real user the way PostgREST does
-- (request.jwt.claims + role authenticated), the same idiom as
-- supabase/tests/*.test.sql. No UUID has to be pasted: the first active
-- admin is discovered from profiles.
--
-- If a statement here errors, the policy from Part 1 is ALREADY applied —
-- read the error, fix the query, re-run only Part 2.
-- ══════════════════════════════════════════════════════════════════
begin;

-- (a) the policy is registered, and what it gates on.
select 'a. policy registered' as check_step,
       polname,
       case polcmd when 'r' then 'SELECT' else polcmd::text end as applies_to,
       pg_get_expr(polqual, polrelid) as using_expression
from pg_policy
where polrelid = 'public.gcash_payment_proofs'::regclass
order by polname;

-- (b) AS ADMIN — must see the table.
--     Pass: is_admin_gate = true, proofs_visible > 0, queue_orders_with_proof > 0.
select set_config(
  'request.jwt.claims',
  json_build_object(
    'sub', (select id from public.profiles
             where role = 'admin' and not coalesce(suspended, false)
             order by created_at nulls last limit 1),
    'role', 'authenticated'
  )::text,
  true
) as claims_set;

set local role authenticated;

select 'b. as admin' as check_step,
       public.is_admin() as is_admin_gate,
       (select count(*) from public.gcash_payment_proofs) as proofs_visible,
       (select count(*) from public.orders o
          join public.gcash_payment_proofs p on p.order_id = o.id
         where o.payment_method = 'gcash' and o.source = 'online'
           and o.status in ('payment_under_review','pending','placed','preparing'))
         as queue_orders_with_proof;

reset role;

-- (c) AS CUSTOMER — must NOT see the whole table.
--     Pass: is_admin_gate = false, proofs_visible = only that customer's own
--     orders' proofs (0 if they have none) — never the full table.
select set_config(
  'request.jwt.claims',
  json_build_object(
    'sub', (select id from public.profiles where role = 'customer' limit 1),
    'role', 'authenticated'
  )::text,
  true
) as claims_set;

set local role authenticated;

select 'c. as customer' as check_step,
       public.is_admin() as is_admin_gate,
       (select count(*) from public.gcash_payment_proofs) as proofs_visible;

reset role;

-- (d) THE QUEUE'S OWN QUESTION, as the table owner — this is the shape the
--     page renders. Pass: orders_with_proof > 0, and each known-paid order
--     carries a reference_number with amount_matches = true.
select count(*) filter (where p.id is not null) as orders_with_proof,
       count(*) filter (where p.id is null)     as orders_without_proof
from public.orders o
left join public.gcash_payment_proofs p on p.order_id = o.id
where o.payment_method = 'gcash'
  and o.source = 'online'
  and o.status in ('payment_under_review','pending','placed','preparing');

select o.id,
       '#' || right(o.id::text, 8) as short_id,
       o.status,
       o.total_amount,
       p.reference_number,
       p.sender_name,
       p.amount_paid,
       (p.amount_paid is not null
        and abs(p.amount_paid - o.total_amount) < 0.01) as amount_matches
from public.orders o
left join public.gcash_payment_proofs p on p.order_id = o.id
where o.payment_method = 'gcash'
  and o.source = 'online'
  and o.status in ('payment_under_review','pending','placed','preparing')
order by o.created_at desc
limit 100;

-- Discard the impersonation. The policy from Part 1 stays.
rollback;
