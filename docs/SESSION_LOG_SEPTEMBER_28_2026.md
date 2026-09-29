# Session Log — September 28, 2026

**Date:** September 28, 2026
**Focus:** Shipping v1.0.32 · un-breaking and then proving the migration suite in CI · correcting what the docs claimed about the live project · the admin portal's refusal classification, P2 (publish a model) and P3 (tell the seller) · a paste-ready re-apply bundle for the live database

> **How to read this.** Written from the work itself, not from a timer: there are no wall-clock
> timestamps, and every claim is labelled as *proven* (a command ran and said so), *measured*
> (a `--linked` query read the live project), or *believed* (reviewed, not executed). That
> distinction is the point of this project's documentation, and it is honoured below.
>
> **It is a reconstruction from the session's own record, not a verbatim transcript.** The raw
> turns live in the client; this log keeps what a future reader would need — what was decided,
> what was measured, what it cost, and what is still open — in the same shape as
> `SESSION_LOG_JULY_14_2026.md`.

---

## Executive Summary

Five pieces of work, in the order they happened:

1. **v1.0.32 was cut, tagged and published.** `pubspec.yaml` → `1.0.32+35`, annotated tag `v1.0.32`
   (message = one bullet per line), `main` pushed **before** the tag, release published with the
   asset `app-release-1.0.32.apk`. `Release APK` run **36417024782: success**.

2. **Two red CI runs became three real findings — two in the *suite*, one in the schema.**
   `Supabase Migrations` failed three times (`36417011607`, `36417497345`, `36418276804`) before
   going green (`36418663600`, `60/60`) — and the third failure was the interesting one, because
   it was the only one that was a defect in the migration rather than in its tests.

3. **Five documents were corrected to match verified reality** after the code went green: the
   migration had been *assumed* unapplied, and the truth turned out to be worse and more specific
   (it is applied in an **older revision** that must be re-applied), which is now what they say.

4. **The admin portal gained its refusal classification, its first tests, and its first CI job** —
   then **P2** (an admin can publish a `.glb` against a queued request and close the ask in one
   step, with the Flutter sheet's declaration rules) and **P3** (the seller is told, and the
   portal cannot claim otherwise).

5. **A paste-ready re-apply bundle for the live database was generated, and both halves of it
   were run against the live project read-only** — so the *before* picture is measured rather
   than described, and the re-apply is now one paste instead of a hunt.

The single most useful artefact of the day is arguably the bundle's **PART 2**: a single
verification query whose `ALL CHECKS` row answers "did the re-apply land" with a table instead of
a promise.

---

## Timeline

### 1. v1.0.32 — cut, tagged, published

The release convention held exactly: bump `version:` in `pubspec.yaml`, run
`dart run releases/update_release_files.dart --version … --apk-url … --released-at … --notes "a|b"`,
create an **annotated** tag whose message is one bullet per line, then push `main` **first** and the
tag second.

- Head commit for the release: `0317fb7 feat(models): a second door into the pipeline — ask, queue,
  close, tell` (roadmap V2.10/V2.11/V2.12/V2.13/V2.14 work in the app and the database).
- Verified: `pubspec.yaml` is `1.0.32+35`; tag `v1.0.32` exists and points at `0317fb7`; the GitHub
  release carries `app-release-1.0.32.apk`; `Release APK` succeeded.

### 2. Two red runs, three findings

`Supabase Migrations` is the **only** thing that applies the lineage and runs the pgTAP suite: Docker
is unavailable in this environment, so there is no local `supabase db reset` or `supabase test db`.
That made CI the first and only reader of the new suite — and it found three things.

**(a) A 3-argument `throws_ok` reads its third argument as the *errmsg pattern*, not as a
description.** `throws_ok(sql, '42501', 'the guard refuses a seller')` therefore compares a real
`42501` against the test's own prose and fails. Six assertions were affected. **The fix:**
`throws_ok(sql, '42501', null, 'the guard refuses a seller')` — the shape already used at
`supabase/tests/pickup_codes.test.sql:206`. A header note in
`supabase/tests/shoe_model_requests.test.sql` now records the trap.

**(b) An assertion that named a request by `where product_id = …` stopped being single-row.** The
suite withdraws and refiles product 21's ask to prove the partial unique index, so that read returns
two rows afterwards; `select … into` then raised `21000`, which **aborted the run after 32 of 60
assertions**. This is the finding with a lesson attached: assertions 33–60 had never executed, and
nothing said so — the run looked like a pass with a truncated tail. **The fix:** a
`public.tmp_req_open_id(p_product uuid)` helper that filters `status in ('requested','in_progress')`
with `limit 1`, plus explicit `and status = 'fulfilled'` on the two reads that want the closed row.

**(c) Three admin guards raised a bare `RAISE EXCEPTION`, so PostgreSQL reported `P0001` — the same
code as a bug inside the function.** The file's own two seller-side guards already said `42501`.
This one is a genuine schema defect: a caller could not tell "this is not your job" from "this
broke". All five guards now `RAISE EXCEPTION … USING ERRCODE = '42501'` (`3218b15`).

Also fixed on the way: `request_shoe_model`'s live-model probe was declared `uuid` over a `bigint`
column (`beb3786`) — the `42804` trap that had already cost `variant_id` one failed apply.

**Result:** `Supabase Migrations` green, `plan(60)` **60/60**; `CI` (Flutter) green.

### 3. The documents were wrong in a specific, fixable way

Five documents still claimed the migration "was written and never applied". The measured truth was
nastier and more useful: it **had** reached the live project — hand-applied, in an **older
revision** that still had the `uuid` probe and a four-value bell CHECK. Applying it from scratch
was never the missing step; **re-applying** it was.

Corrected: `supabase/MIGRATIONS_LIVE_STATUS.md` (the three newest rows rewritten, plus what CI did
and did not prove), `docs/RoadMap/VIRTUAL_FITTING_ROADMAP.md` and
`docs/RoadMap/VIRTUAL_FITTING_ARCHITECTURE.md`. Dated changelog rows stayed in the past tense.

### 4. The admin portal: refusal classification, its first tests, its first CI job

The portal had no tests, no lint config, and no CI. It now has all three of the first two, plus a
workflow:

- **`src/lib/errors.js`** — `PORTAL_ERROR` = `not_admin | session_expired | db_behind_code |
  schema_drift | offline | unknown`, a `classifyError` keyed on `42501`, `PGRST301/302/401`,
  `42804/42883/42P01/3F000/…`, fetch failures — and `toPortalError`, which is the important one:
  hooks wrap with it rather than `new Error(error.message)`, because the **code** lives on the
  error object and a message-only copy destroys the one field that decides the sentence. The raw
  server text is never discarded; it travels as `detail` and is printed whenever it differs from
  the sentence shown.
- **`src/hooks/useDeviceGate.js`** — `device_gate_open()`, which exists precisely to tell "empty"
  apart from "gated". The device gate hides **rows** rather than raising, so a gated session and an
  idle queue are byte-identical from the client. The probe never throws and reports `null` for
  unknown: a probe whose job is to explain a blank screen must not be able to blank it.
- **`npm test`** (`node --test`, no new dependency) and **`.github/workflows/admin-portal.yml`**
  (Node 22, `npm ci` → `npm test` → `npm run build`, on pushes touching `admin-portal/**`).
  The workflow's YAML was checked by structure only — there is no YAML parser in this environment,
  so its first CI run was the real confirmation (it passed; see §7).

### 5. Portal P2 — publish a model and close the ask in one step

`admin-portal/src/lib/modelPublish.js` ports the declaration rules from the Flutter sheet:
millimetres-not-centimetres (`27` is refused as a likely `270`), the column's own 100–400 mm and
22–48 EU bands, a size with no length refused, and a length more than ±5 mm from the seller's
measurement as a **warning, not a gate**.

**Deliberately not ported: the 11-check authoring contract.** It already exists twice (the Dart
reference and the TypeScript mirror inside `validate-shoe-model`, parity-checked over 22 fixtures);
a third copy would be a third place for eleven rules to drift. The portal uploads, asks the server,
and shows the server's answer.

`usePublishModel.js` runs the app's pipeline in the app's order, for the app's reasons: digest →
**object first, row second** (a row whose object is missing renders as "no model"; an object with no
row is invisible) → row always a **draft** → `validate-shoe-model` (the only caller the database
lets write `active`) → **the close last**, because only a live model can close an ask. That yields
three endings, and `live but open` — published, not closed — is the one that must never be rounded
to "done".

`UploadModelModal.jsx` offers both a **file picker** (a browser has one for free; the app cannot,
because no picker dependency there can select a `.glb`) and a **link** (what the app uses, and the
one source a host's CORS rules can refuse — with a sentence that says so). Ships dark behind
`VITE_ADMIN_MODEL_UPLOAD`.

### 6. Portal P3 — the seller is told

The notice already exists and is written **by the database**: `fulfil_shoe_model_request` and
`decline_shoe_model_request` insert it inside the transaction that closes the ask, so "closed" and
"told" cannot disagree. The portal therefore had nothing to *send* — the phase is about not being
able to claim otherwise:

- **`src/lib/askDelivery.js`** — the actual category (`models`) and bell type (`model_request`), both
  channel labels, the two titles **verbatim**, and one sentence per ending: `closed` told the
  seller; `not live` told nobody because nothing changed; `live but open` told nobody *yet*, which
  is exactly the ending a green tick would have hidden. A decline's sentence carries the reason,
  and a blank one degrades to a notice that stands on its own rather than a dangling "They said:".
- **`src/lib/askDelivery.contract.test.js`** — the phase's real deliverable. The page's claim is
  about SQL it does not own, so the test **reads the migration**: both closing RPCs must write
  **both** channels (one row alone was correct and unreadable at the same time — that is V2.14's
  bug), the inserts must sit *after* the `UPDATE` inside the same plpgsql body, `fulfil` must quote
  `p_admin_note` rather than the stale `v_request.admin_note`, and `decline` must carry `p_reason`.
  It then reads the portal's **own source** to prove the claim cannot be short-circuited: no notice
  insert, no direct write to `shoe_model_requests`, and every request RPC it calls exists in the
  migration.
- The UI states the delivery per ending, the decline dialog renders the sentence the seller's bell
  will hold **live as the admin types**, and the page says plainly that it cannot read the notice
  back — both notice tables grant SELECT to the recipient alone with no admin policy, so a "told at
  14:02" stamp would have to be invented.

### 7. Commit, push, and the first Admin Portal CI run

`8f89411 feat(portal): let an admin answer a model request, and tell the seller it is answered` —
19 files, +3006/−29, staged **by explicit path** so `CHANGELOG.md` (another agent's, dirty all
session) was never touched. Pushed `68f3f21..8f89411`.

- **`Admin Portal` run 36424609352: success** — `Checkout → Setup Node → Install dependencies →
  Test (58/58) → Build`. This settled the one thing that could not be checked locally: the YAML
  parses and runs on Node 22.
- **`CI` (Flutter) run 36424609481: success** for the same push, confirming the portal-only diff
  disturbed nothing in the app.

### 8. The live re-apply, made one paste

`20260928140000` must be re-applied to the live project by hand (SQL Editor — **never**
`supabase db push`). Rather than hand over a file and a paragraph of instructions:

- **`tool/build_live_bundle.mjs`** generates **`supabase/manual/20260928140000_add_shoe_model_requests.apply.sql`**
  (979 lines): the migration **verbatim** with its sha256 stamped in the header, wrapped in
  **PART 0** (a pre-flight that stops before any DDL) and **PART 2** (one verification query).
  The generator **refuses to emit anything** if the markers its checks depend on have moved, and
  regeneration is deterministic (checked by diff).
- **PART 0** catches the four assumptions the file makes: the helper functions, the `'models'` enum
  label (which cannot be added in the same transaction that uses it — hence its own earlier file),
  `product_models`, and — the check that earns its keep — a hand-created `shoe_model_requests`
  whose **columns or `model_id` type** have drifted, because `CREATE TABLE IF NOT EXISTS` converges
  on an existing table by doing *nothing*, which is the one failure a re-apply cannot repair.
- **Both halves were run against the live project read-only.** PART 0 raises nothing: every
  assumption holds. PART 2 returns 15 rows, **six true and six false** (see "Measured state").

---

## Commits landed

| Commit | Message |
|---|---|
| `0317fb7` | feat(models): a second door into the pipeline — ask, queue, close, tell *(tagged `v1.0.32`)* |
| `beb3786` | fix(db): declare the live-model probe as BIGINT, not uuid |
| `93f6269` | fix(test): name the row and the error pattern the suite actually meant |
| `3218b15` | fix(db): give the admin guards a privilege code the caller can act on |
| `68f3f21` | docs: say what CI proved and what the live project actually holds |
| `8f89411` | feat(portal): let an admin answer a model request, and tell the seller it is answered |

All pushed to `main`. Local `main` == `origin/main` == `8f89411`.

## What CI proved (and what it did not)

- `Release APK` **36417024782** — v1.0.32 built and attached to the release.
- `Supabase Migrations` **36418663600** — the lineage applies from scratch and
  `supabase/tests/shoe_model_requests.test.sql` passes **60/60**.
- `CI` (Flutter) — green on `68f3f21` (**36419546938**) and on `8f89411` (**36424609481**).
- `Admin Portal` **36424609352** — first run: test 58/58, build clean.

**What CI proves is the file, not the project.** `db reset` builds a *fresh* database; it says
nothing about the hosted one, which was hand-applied and is a revision behind.

## Measured state at the end of the session

Read against the live project (`psczvbfyoybqhjeqssimw`) with `supabase db query --linked`, read-only:

| Fact | Value |
|---|---|
| `shoe_model_requests` | exists, **17 columns**, `model_id` = `bigint`, **0 rows** |
| RPCs / policies / partial index / trigger | 5 RPCs, 3 policies, `uq_shoe_model_requests_open` present, `updated_at` trigger present |
| `notification_category` | includes `'models'` ✅ (so `20260928130000` is applied) |
| `request_shoe_model` source | **no `bigint`** ❌ — still the `42804` revision |
| `seller_notifications_type_check` | admits **four** types ❌ — must widen to six |
| Closing RPCs' notices | `fulfil` and `decline` write **neither** row ❌ — the live revision predates them |
| `product_models` | present, with `status`/`sha256`/`storage_path`/`version` |
| Helpers (`is_admin`, `set_updated_at`, `install_device_gate_policies`, `device_gate_open`) | all present |

**Twelve verification checks: six true, six false.** Re-applying the file is the only step between
the feature and a working flow, and both switches stay **off** until it is done.

## Findings worth keeping

1. **A 3-argument `throws_ok` is a trap.** The third argument is the errmsg *pattern*. Always
   `(sql, errcode, null, description)`.
2. **An aborted pgTAP run can look like a short pass.** Assertions 33–60 had never run and nothing
   said so; the count in the output is the only tell. Read the number, not the colour.
3. **A `RAISE EXCEPTION` with no `ERRCODE` reports `P0001`** — indistinguishable from a bug inside
   the function. Guards that mean "not your job" must say `42501`.
4. **A source scan that finds nothing passes for the wrong reason.** The portal's contract test
   asserts it scanned ≥20 files and that the patterns it guards against *exist* somewhere, so a
   moved directory fails loudly. (The app's `device_gate_contract_test.dart` learned this first.)
5. **A multi-statement batch returns only the last result set.** The bundle's first draft lost its
   entire verification table behind two informational counts; it is now one statement.
6. **The portal's copy makes a claim about SQL it does not own.** That is why P3 shipped with a test
   that reads the migration rather than a comment that says the notices exist.
7. **`CREATE TABLE IF NOT EXISTS` converges by doing nothing.** On a hand-created table it is a
   silent no-op — which is why the bundle's pre-flight checks columns and types *before* the DDL.

## Open items

- **⚠️ `20260928140000` re-apply.** Bundle ready; not yet run. Until it lands, a portal close writes
  **no** seller notice, and both switches stay off.
- **Both switches off:** `AppConstants.shoeModelRequestEnabled` (app) and `VITE_ADMIN_MODEL_UPLOAD`
  (portal). Turning them on is the last step of the request flow.
- **`20260915150000`'s exemption list is also live-behind** (the hosted
  `device_gate_exempt_tables()` still returns 22 names) — recorded in `MIGRATIONS_LIVE_STATUS.md`,
  harmless while the gate is off, and the same generator can build its bundle.
- **Uncommitted:** `tool/build_live_bundle.mjs`, `supabase/manual/…apply.sql`, and the
  `MIGRATIONS_LIVE_STATUS.md` pointer added for them.
- **Needs hardware, not code:** V0.6 fps/memory, V3 exit numbers, the Draco/meshopt verdict (a
  physical ARCore phone); V3's camera feed is blocked on missing `.filamat` assets (F20).
- **`CHANGELOG.md`** remained another agent's dirty file all session and was never staged.

## Files added or changed (this session)

**App / database**
- `supabase/tests/shoe_model_requests.test.sql` — `tmp_req_open_id()`, 4-argument `throws_ok`, the
  status filter on the two closed-row reads, plan intact at 60.
- `supabase/migrations/20260928140000_add_shoe_model_requests.sql` — all five guards `42501`.
- `supabase/MIGRATIONS_LIVE_STATUS.md`, `docs/RoadMap/VIRTUAL_FITTING_ROADMAP.md`,
  `docs/RoadMap/VIRTUAL_FITTING_ARCHITECTURE.md` — corrected to the applied-but-older-revision truth.

**Admin portal** (all in `8f89411`)
- `src/lib/errors.js` + `errors.test.js`, `src/hooks/useDeviceGate.js` — classification and the
  empty-vs-gated probe.
- `src/lib/modelPublish.js` + `.test.js` + `.contract.test.js`, `src/hooks/usePublishModel.js`,
  `src/components/model-requests/UploadModelModal.jsx` — P2.
- `src/lib/askDelivery.js` + `.test.js` + `.contract.test.js` — P3.
- `src/pages/ModelRequests.jsx`, `src/lib/constants.js`, `.env.example`, `package.json`,
  `README.md`, `docs/architecture.md` — wiring, the dark switch, `npm test`, and the docs.
- `.github/workflows/admin-portal.yml` — the portal's first CI job.

**Live-ops**
- `tool/build_live_bundle.mjs` — the generator.
- `supabase/manual/20260928140000_add_shoe_model_requests.apply.sql` — the bundle (979 lines,
  source digest `dbf3ea69c866b73bf39dfad6eb5eb0908461e62cf6d2adb0cdc8c9ac9052930d`).

**Tests run and green at the end of the session:** portal `npm test` **58/58**; `npm run build`
clean; `Supabase Migrations` **60/60**; `CI` green; `Admin Portal` green.
