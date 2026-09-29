#!/usr/bin/env node
/**
 * Build the paste-ready re-apply bundle for a migration the live project is
 * carrying in an OLDER revision.
 *
 *   node tool/build_live_bundle.mjs 20260928140000_add_shoe_model_requests.sql
 *
 * Writes `supabase/manual/<name>.apply.sql`: the migration **verbatim**, wrapped
 * in the two things the migration cannot carry as comments — a pre-flight that
 * stops before any DDL if the live project is not in the state the file assumes,
 * and a verification query that answers in one paste.
 *
 * ⚠️ Why a generator and not a checked-in copy of the SQL: a hand-kept bundle is
 * a second source of truth for the rules, and the two drift the first time
 * somebody edits the migration. This copies the file at build time and stamps its
 * sha256 into the header, so "the bundle is the file" is checkable rather than
 * promised. The drift guard below also refuses to emit anything if the markers
 * this bundle's checks depend on have moved.
 *
 * Not applied by this script, and never by CI: the live project is updated by
 * hand through the SQL Editor, which is the documented route
 * (`supabase/MIGRATIONS_LIVE_STATUS.md`). `supabase db push` stays off the table.
 */

import { createHash } from 'node:crypto'
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')

const TARGET = '20260928140000_add_shoe_model_requests.sql'

// ─── The spec: what this migration needs, and what proves it landed ──

const MARKERS = [
  'CREATE TABLE IF NOT EXISTS public.shoe_model_requests',
  'CREATE OR REPLACE FUNCTION public.request_shoe_model(',
  'CREATE OR REPLACE FUNCTION public.claim_shoe_model_request(',
  'CREATE OR REPLACE FUNCTION public.fulfil_shoe_model_request(',
  'CREATE OR REPLACE FUNCTION public.decline_shoe_model_request(',
  'INSERT INTO public.notifications',
  'INSERT INTO public.seller_notifications',
  'install_device_gate_policies()',
  "'models'",
]

const HELPERS = ['is_admin', 'set_updated_at', 'install_device_gate_policies', 'device_gate_open']
const ENUM_TYPE = 'notification_category'
const ENUM_LABELS = ['models']

const COLUMNS = [
  'id', 'product_id', 'store_id', 'requested_by', 'status',
  'external_length_mm', 'external_width_mm', 'heel_height_mm', 'measured_size_eu', 'note',
  'assigned_to', 'admin_note', 'model_id', 'reviewed_by', 'reviewed_at',
  'created_at', 'updated_at',
]

const STATUSES = ['requested', 'in_progress', 'fulfilled', 'declined', 'cancelled']
const BELL_TYPES = ['new_order', 'stale_order', 'low_stock', 'custom_order_request', 'model_request', 'new_message']

const CLOSING_RPCS = ['fulfil_shoe_model_request', 'decline_shoe_model_request']

// ─── Read the source, and refuse to build a bundle on a moved marker ──

const name = process.argv[2] ?? TARGET
const sourcePath = path.join(ROOT, 'supabase', 'migrations', name)
const sql = readFileSync(sourcePath, 'utf8')

const missing = MARKERS.filter((marker) => !sql.includes(marker))
if (missing.length > 0) {
  console.error(
    `refusing to build a bundle for ${name}: ${missing.length} marker(s) this bundle's ` +
      `pre-flight and verification depend on are gone —\n  ${missing.join('\n  ')}\n` +
      'Fix the markers or update tool/build_live_bundle.mjs; a stale bundle is worse than none.',
  )
  process.exit(1)
}

const digest = createHash('sha256').update(sql).digest('hex')

const sq = (values) => values.map((value) => `'${value}'`).join(', ')

// ─── Part 0: the pre-flight ──────────────────────────────────────────
//
// The one failure a re-apply cannot repair is named first in the prose below:
// `CREATE TABLE IF NOT EXISTS` is a silent no-op on a table that already exists,
// so a missing column would let the DDL "succeed" and leave the RPCs to fail at
// runtime — with the switches already on. Everything here stops *before* the DDL.

const preflight = `DO $preflight$
DECLARE
  v_missing text;
BEGIN
  -- 1. The helpers this file calls. It cannot create them, and a missing one
  --    would surface as a 42883 from inside an RPC rather than from here.
  SELECT string_agg(want, ', ') INTO v_missing
    FROM unnest(ARRAY[${sq(HELPERS)}]) AS want
   WHERE NOT EXISTS (
     SELECT 1 FROM pg_proc p
       JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname = want
   );
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION 'PRE-FLIGHT STOP - missing helper function(s): %. Apply the migrations that define them first (is_admin and set_updated_at are old; the device gate is 20260915150000).', v_missing;
  END IF;

  -- 2. The enum label the closing RPCs write. ALTER TYPE ... ADD VALUE cannot be
  --    used in the transaction that adds it, which is why it lives in a file of
  --    its own (20260928130000) - so this bundle must NOT try to add it. Run that
  --    file on its own first, and only then this one.
  SELECT string_agg(want, ', ') INTO v_missing
    FROM unnest(ARRAY[${sq(ENUM_LABELS)}]) AS want
   WHERE NOT EXISTS (
     SELECT 1 FROM pg_enum e
       JOIN pg_type t ON t.oid = e.enumtypid
      WHERE t.typname = '${ENUM_TYPE}' AND e.enumlabel = want
   );
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION 'PRE-FLIGHT STOP - ${ENUM_TYPE} is missing the label(s): %. Run 20260928130000_add_models_notification_category.sql on its own first (the new value cannot be used in the transaction that adds it).', v_missing;
  END IF;

  -- 3. The FK target, and the source of the type the older revision got wrong.
  IF to_regclass('public.product_models') IS NULL THEN
    RAISE EXCEPTION 'PRE-FLIGHT STOP - public.product_models does not exist; apply 20260927180000_add_try_on_models.sql first.';
  END IF;

  -- 4. The table, if it already exists. This is the check that earns its keep:
  --    the CREATE TABLE below is IF NOT EXISTS, so it converges by *doing nothing*
  --    on a table that is already there. A hand-created table that is missing a
  --    column, or that typed model_id as uuid, would pass the DDL and fail at
  --    runtime instead - with customers on it.
  IF to_regclass('public.shoe_model_requests') IS NOT NULL THEN
    SELECT string_agg(want, ', ') INTO v_missing
      FROM unnest(ARRAY[${sq(COLUMNS)}]) AS want
     WHERE NOT EXISTS (
       SELECT 1 FROM pg_attribute a
        WHERE a.attrelid = 'public.shoe_model_requests'::regclass
          AND a.attname = want
          AND NOT a.attisdropped
     );
    IF v_missing IS NOT NULL THEN
      RAISE EXCEPTION 'PRE-FLIGHT STOP - public.shoe_model_requests is missing column(s): %. It was created by hand, and CREATE TABLE IF NOT EXISTS cannot add them. Repair the table by hand (ALTER TABLE ... ADD COLUMN) and re-run this bundle.', v_missing;
    END IF;

    IF (
      SELECT format_type(a.atttypid, a.atttypmod)
        FROM pg_attribute a
       WHERE a.attrelid = 'public.shoe_model_requests'::regclass
         AND a.attname = 'model_id'
    ) <> 'bigint' THEN
      RAISE EXCEPTION 'PRE-FLIGHT STOP - shoe_model_requests.model_id is not bigint (product_models.id is an IDENTITY column). This bundle cannot retype it; ALTER TABLE public.shoe_model_requests ALTER COLUMN model_id TYPE bigint USING model_id::bigint; and re-run.';
    END IF;
  END IF;

  RAISE NOTICE 'PRE-FLIGHT PASSED - the live project is in the state this file assumes. Continue: the rest of this script is the migration.';
END
$preflight$;`

// ─── Part 2: the verification ────────────────────────────────────────
//
// One paste, one table, a last row that answers the whole question. Written as
// facts with an expected value rather than as prose, so "did it land" is not a
// judgement call - and so the output can be pasted back verbatim.
//
// ⚠️ ONE statement, deliberately. A client that runs a multi-statement batch
// returns only the LAST result set — which is how this bundle's first draft lost
// the whole check table behind two informational counts. The counts are rows in
// the same table now, marked `any` so they cannot fail it.

const noticeLike = (rpc, table) =>
  `(SELECT (prosrc LIKE '%INSERT INTO public.${table}%')::text FROM pg_proc WHERE proname = '${rpc}')`

const labelsAdmitted = (constraintName, labels) => `(
      SELECT (count(*) = ${labels.length})::text
        FROM unnest(ARRAY[${sq(labels)}]) AS want
       WHERE (SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname = '${constraintName}')
             LIKE '%''' || want || '''%'
    )`

const checks = [
  [
    'request_shoe_model reads the model id as bigint (the 42804)',
    'true',
    `(SELECT (prosrc LIKE '%bigint%')::text FROM pg_proc WHERE proname = 'request_shoe_model')`,
  ],
  ...CLOSING_RPCS.flatMap((rpc) => [
    [`${rpc} writes the per-user notice`, 'true', noticeLike(rpc, 'notifications')],
    [`${rpc} writes the store-bell notice`, 'true', noticeLike(rpc, 'seller_notifications')],
  ]),
  [
    'the closing RPC takes a bigint model id',
    'true',
    `(SELECT bool_and(pg_get_function_arguments(oid) LIKE '%bigint%')::text FROM pg_proc WHERE proname = 'fulfil_shoe_model_request')`,
  ],
  [
    'seller_notifications.type admits all six types',
    'true',
    labelsAdmitted('seller_notifications_type_check', BELL_TYPES),
  ],
  [
    'the status CHECK admits all five states',
    'true',
    labelsAdmitted('shoe_model_requests_status_check', STATUSES),
  ],
  [
    'the device gate policy is installed',
    '1',
    `(SELECT count(*)::text FROM pg_policies WHERE tablename = 'shoe_model_requests' AND policyname = 'Require a trusted device')`,
  ],
  [
    'no seller write policies (the RPCs are the only door)',
    '0',
    `(SELECT count(*)::text FROM pg_policies WHERE tablename = 'shoe_model_requests' AND cmd IN ('INSERT', 'UPDATE', 'DELETE') AND policyname NOT LIKE 'Admins%')`,
  ],
  [
    'one open ask per product',
    '1',
    `(SELECT count(*)::text FROM pg_indexes WHERE tablename = 'shoe_model_requests' AND indexname = 'uq_shoe_model_requests_open')`,
  ],
  [
    'the updated_at trigger is present',
    '1',
    `(SELECT count(*)::text FROM pg_trigger WHERE tgrelid = 'public.shoe_model_requests'::regclass AND tgname = 'trg_shoe_model_requests_updated_at' AND NOT tgisinternal)`,
  ],
]

const rows = [
  ...checks,
  // Informational, and deliberately unfailable: the flow has never been on for a
  // real seller, so 0 rows is the expected reading today - but a non-zero one is
  // interesting rather than wrong, and must not be dressed up as a failure.
  ["requests now (informational, 'any' expected)", 'any', `(SELECT count(*)::text FROM public.shoe_model_requests)`],
  ["still waiting (informational, 'any' expected)", 'any', `(SELECT count(*) FILTER (WHERE status IN ('requested', 'in_progress'))::text FROM public.shoe_model_requests)`],
]

const values = rows
  .map(([label, expected, actual]) => `    ('${label.replace(/'/g, "''")}', '${expected}', ${actual})`)
  .join(',\n')

// `expected = 'any'` is the escape hatch for the informational rows; failures
// sort first, so a broken re-apply is the first line the admin reads.
const verification = `WITH check_results (check_name, expected, actual) AS (
  VALUES
${values}
)
SELECT check_name,
       expected,
       actual,
       (expected = 'any' OR expected = actual) AS ok
  FROM check_results
UNION ALL
SELECT 'ALL CHECKS',
       'true',
       (SELECT bool_and(expected = 'any' OR expected = actual)::text FROM check_results),
       (SELECT bool_and(expected = 'any' OR expected = actual) FROM check_results)
 ORDER BY ok, check_name;`

// ─── Emit ────────────────────────────────────────────────────────────

const built = new Date().toISOString().slice(0, 10)

const bundle = `-- ══════════════════════════════════════════════════════════════════
-- PASTE-READY RE-APPLY BUNDLE - GENERATED, DO NOT EDIT BY HAND
--
--   source : supabase/migrations/${name}
--   sha256 : ${digest}
--   built  : ${built}
--
-- Regenerate with:  node tool/build_live_bundle.mjs ${name}
--
-- ⚠️ WHY THIS EXISTS. The live project is carrying an OLDER revision of the
-- migration below, applied by hand; CI applies the current file from scratch and
-- proves it (Supabase Migrations, green). So the file and the live project
-- disagree, and the disagreement is larger than it looks from the outside:
-- **six of PART 2's twelve checks read false on the day this was generated** —
-- both closing RPCs write *neither* notice row (the older revision predates the
-- notices entirely, which is why the bell CHECK looks like the smaller problem),
-- the model probe inside request_shoe_model has no bigint, and the bell CHECK
-- admits four types instead of six. Re-applying is the only step between the feature and
-- a working flow, and the two revisions cannot be reconciled by reading this
-- file, only by running it.
--
-- HOW TO USE IT
--   1. Open the Supabase SQL Editor for the SoleVision project
--      (psczvbfyoybqhjeqssimw -> SQL Editor -> New query).
--   2. Paste this WHOLE file and run it once. Do not paste it in pieces and do
--      not reorder it: the server runs one batched message as one transaction,
--      so either all of it lands or none of it does. If it does error, nothing
--      was applied - and if anything ever *does* land half-way (an editor that
--      autocommits per statement), just run this file again: it is written to
--      converge (CREATE ... IF NOT EXISTS, DROP CONSTRAINT IF EXISTS, CREATE OR
--      REPLACE FUNCTION), so a second run repairs the first rather than failing.
--   3. Read PART 2's result. The row named ALL CHECKS must say true. Paste that
--      table into the conversation and supabase/MIGRATIONS_LIVE_STATUS.md can be
--      updated from evidence rather than from a promise.
--
-- NEVER \`supabase db push\` against this project (project rule), and never run
-- this through the app: the switches stay off until PART 2 is read.
--
-- WHAT IS IN HERE
--   PART 0  pre-flight - stops before any DDL if the live project is not in the
--           state this file assumes (a missing helper, the enum label, or a
--           hand-created table whose columns or model_id type drifted; the last
--           one is the only failure this bundle cannot repair by itself).
--   PART 1  the migration, byte for byte (digest above).
--   PART 2  verification, as one query with an expected value per check.
-- ══════════════════════════════════════════════════════════════════

-- ══════════ PART 0 - PRE-FLIGHT (must notice "PRE-FLIGHT PASSED") ══════════
${preflight}

-- ══════════ PART 1 - THE MIGRATION, VERBATIM ══════════

${sql.trimEnd()}

-- ══════════ PART 2 - VERIFICATION (one query; ALL CHECKS must be true) ══════════
${verification}
`

const outDir = path.join(ROOT, 'supabase', 'manual')
mkdirSync(outDir, { recursive: true })

const outPath = path.join(outDir, `${name.replace(/\.sql$/, '')}.apply.sql`)
writeFileSync(outPath, bundle, 'utf8')

const lines = bundle.split('\n').length
console.log(`wrote ${path.relative(ROOT, outPath).replace(/\\/g, '/')}`)
console.log(`  source digest ${digest}`)
console.log(`  ${lines} lines, ${bundle.length} bytes - paste the whole file into the SQL Editor`)
