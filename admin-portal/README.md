# SoleVision Admin Portal

Web-only admin dashboard for SoleVision. Connects to the same Supabase project as the Flutter mobile app.

## Setup

```bash
cd admin-portal
npm install
cp .env.example .env
```

Edit `.env` with your Supabase credentials (same as the Flutter app):

```
VITE_SUPABASE_URL=https://psczvbfoybqhjeqssimw.supabase.co
VITE_SUPABASE_ANON_KEY=your_anon_key_here
```

## Run

```bash
npm run dev
```

Open http://localhost:5173 and sign in with an admin account (`profiles.role = 'admin'`).

## Test

```bash
npm test
```

Node's own test runner (`node --test`) over the pure rules in `src/lib/` — no test framework and no extra dependency. `.github/workflows/admin-portal.yml` runs it, plus `npm run build`, on every push that touches this folder.

## Build

```bash
npm run build
npm run preview
```

## Supabase requirements

- Admin RLS policies on `profiles`, `orders`, and `products` (see project prompt)
- Optional: add `suspended` boolean column on `profiles` for user suspension
- Optional: add `rejection_reason` text column on `profiles` for seller rejections
- Enable Realtime on `profiles` table for live seller application updates

## When a request is refused

Every failure is classified before it reaches a screen, so the portal can say what to *do* rather than only what happened (`src/lib/errors.js`, tested by `npm test`):

| The server sent | What the page says |
|---|---|
| `42501` | the session is not an admin's — sign out and back in |
| `PGRST301` / `401` / "JWT expired" | the session expired; nothing was sent |
| `42804`, `42883`, `42P01`, `PGRST202` | the database is behind this build — apply the migration |
| `PGRST200`, `PGRST204`, `42703` | the page and the database have drifted apart |
| a fetch failure | the server is unreachable; nothing was sent |
| anything else | the server's own words, verbatim |

The raw server text is never discarded — it travels as `detail` and is printed under the sentence whenever it differs from it, because a screenshot of the server's words is often the only route to a fix.

And a queue that comes back **empty** is checked against `device_gate_open()` before the page calls it "nothing waiting": the device gate hides *rows* instead of raising, so a gated session and an idle queue look identical from the client.

## Publishing a model from the portal

The `/model-requests` queue does not only *point at* a model — an admin can publish one and close the ask in the same step. Off unless `VITE_ADMIN_MODEL_UPLOAD=true` is set in `.env` (see `src/lib/constants.js`), matching the app's own "ships dark" convention for this pipeline.

Two sources, because a browser and a phone are not the same client: a **file picker** for a `.glb` on disk (reliable), and a **link** (what the Flutter sheet uses, since no picker dependency can select a `.glb` there). A link download can be refused by the host's CORS rules, and the refusal says so.

The **declaration** — the model's external length in millimetres, and optionally an EU size — is enforced exactly as the Flutter upload sheet enforces it (`src/lib/modelPublish.js`, tested against the migration that owns the numbers):

- the length is written in **millimetres, not centimetres** — `27` is refused as a likely `270`, because 27 mm is not a shoe;
- the band is the column's own: 100–400 mm, and 22–48 EU;
- a size with no length is refused, since the size alone cannot be checked against the mesh;
- a length that disagrees with the seller's measurement by more than ±5 mm is a **warning, not a gate** — the seller measured the outside of a shoe, and a last is not a shoe;
- the request's own measurement is prefilled, so the field starts at the seller's number rather than empty.

It is **not** a third implementation of the 11-check authoring contract: the Dart reference and the TypeScript mirror inside `validate-shoe-model` already cover those rules, so the portal sends the bytes, asks the server, and shows the server's answer. A refusal arrives with the failing rows named, the row stays hidden as a `draft`, and the ask stays open.

### A 90 MB export, without a terminal

The queue used to assume the model arrived ready. A partner's raw export does not: the file this was written against was 90.1 MB, 1.5 million triangles, three 4096² textures, one material called `Material.001`, and authored 4.37× life size. Every one of those is a refusal, and the only route to a fixed file was `dart run tool/prepare_shoe_model.dart` in a shell — which is exactly the gap the Flutter screen's own header describes ("only ever be filled by someone with a terminal").

So when a picked file is over the **5 MB authoring budget**, the modal offers **Compress it**, and it runs in the browser:

1. **Decimate** (`@gltf-transform/core` + `functions` with `meshoptimizer`'s WASM simplifier) — the one stage the Dart normalizer cannot do at all. A ratio is picked to land the mesh near 40,000 triangles, and no decimation runs when the mesh is already inside the cap.
2. **Normalize** — the *compiled reference normalizer*, not a port of it: `lib/utils/glb_normalizer.dart`, built to JavaScript by `tool/build_shoe_model_normalizer_web.mjs`. Re-aimed axes, grounded at the heel-bottom-centre, scaled to the declared length, textures re-baked to 1024², materials renamed, sole band cut.

Both stages run in a Web Worker, so the tab stays usable for the ~40 seconds it takes, and the worker is terminated the moment the run ends or the modal closes.

**What comes out is plain, uncompressed glTF.** Draco, meshopt and KTX2 are refused by the contract, so meshopt is used as a *tool* (the simplifier) and never as an output format — the bytes that reach the bucket are ordinary triangles, textures at 1024², parts named `upper`/`sole`.

**What it will not do is guess.** Two unapproved material names are refused with the names and the CLI command to fix them, because which of `Material.001` and `Material.002` is the upper is a modelling question the bytes cannot answer, and a wrong guess repaints a shoe. One material (or none) gets the documented geometric sole cut, reported as the approximation it is. Which end of the long axis is the toe is left to the reviewer, and the change log says so.

⚠️ **A green compress is not acceptance.** The server still judges the stored bytes when you publish — nothing here returns a verdict, and the modal shows no report card. The reviewer rows are untouched by any of it: toe direction, de-lit albedo, likeness and on-device frame rate still need a human eye (guide §5.2).

### Where the artifact lives

The compiled normalizer is **checked in** (`src/lib/glb_normalizer.gen.js`, 512 KB) so `npm install && npm run build` needs Node and nothing else — the portal's CI job installs no Dart SDK. `src/lib/modelCompress.contract.test.js` compares the digest stamped into the artifact against the Dart sources on every `npm test`, and fails with the rebuild command if they have drifted:

```bash
node tool/build_shoe_model_normalizer_web.mjs
```

Run that after any change to `lib/utils/glb_normalizer.dart`, and commit both.

Only a live model can close an ask, so a publish has three endings: **closed**, **not live** (refused — the reason is shown and the modal stays open), and **live but still open** (the model passed the server, the close failed; this one is toasted as an error because somebody has to act on it).

Publishing needs the model-request flow applied to the live database (`supabase/migrations/20260928140000_add_shoe_model_requests.sql`) — see `supabase/MIGRATIONS_LIVE_STATUS.md`.

## The other end of the loop: the seller is told (P3)

Closing an ask — fulfilled *or* declined — writes the seller a notice, and it is written by the **database**, inside the same transaction as the status change, so "closed" and "told" cannot disagree. The portal does not send it, and cannot skip it.

It lands on **two channels**, which is a fix rather than thoroughness: `public.notifications` is the per-user feed, and the seller app never renders it — a seller's shell reads `public.seller_notifications`, keyed by store. A notice on one channel only was correct and unreadable at the same time.

What the portal says per ending (`src/lib/askDelivery.js`, tested by `npm test`):

| How it ended | What the admin is told |
|---|---|
| closed | the seller has been told, and the notice quotes the admin's note as "From the team: …" |
| not live | nobody was told — nothing went live and the ask is untouched |
| live but open | nobody was told *yet* — the ask is still open, so no notice was written |
| declined | the seller has been told, and the notice quotes the reason verbatim |

The portal can never fall back to an empty promise: it **never inserts a notice itself** and **never closes an ask by writing the row**, only through the RPCs that notify. Both are guarded mechanically by `src/lib/askDelivery.contract.test.js`, which reads the migration as well as the portal's own source, so the sentence "the seller has been told" fails CI if the SQL behind it moves.

It will not pretend to show you the notice: both notice tables grant SELECT to the recipient alone and no admin policy exists, so no timestamp here would be readable. The page says that instead of inventing one.

### And a notice row is not a push

Both rows can land correctly, in the same transaction as the close, with the seller's phone in their pocket staying completely silent — which is the report that made `src/lib/askPush.js` exist. After a closing RPC commits, the portal asks `send-notification-push` for the OS-level copy, addressed to `stores.owner_id` and saying exactly what the bell says (the sentences come from `askDelivery.js` and are contract-tested against the RPC bodies).

The distinction is what keeps this honest: the **row is the fact** (written inside the closing transaction, skippable by nobody) and the **push is the wake-up** (best-effort, sent by whichever client is running). This one is sent from the admin's browser, so closing the tab mid-flight skips the push — the bell row does not depend on it, and nothing in the portal's copy claims otherwise. It is fire-and-forget: it is never awaited into the outcome, because the ask is already closed and a failed push must not read as a failed close (`askPush.test.js` drives every dead end through a fake client to prove it).

The tap opens the seller's **Products tab** (`seller_product_detail`, the key the low-stock push already uses); the request row is one long-press away there on the product's actions sheet.

## The AI page (Ai Fluid Blob)

`/ai` is the portal's one surface that reads **nothing** — no Supabase query, no rows, no route params. It is a component page for **Ai Fluid Blob**: a multi-strand chromatic liquid wave under a glass refraction lens, drawn by hand-written WebGL shaders.

- **`src/components/ai/AiFluidBlob.jsx`** — the canvas, the program and the render loop. Props are the documented five: `size` (260), `colors` (`['#10B981','#06B6D4','#3B82F6','#6366F1']`), `count` (4, 1–12), `variant` (`listening` | `thinking` | `speaking` | `orbit` | `pulse`, default `listening`) and `glass` (true).
- **`src/components/ai/blobShader.js`** — the two GLSL sources. The whole drawing lives here.
- **`src/lib/aiBlob.js`** — every rule that is *decidable* rather than drawn: clamping, palettes, the motion profile per state, and the snippet the page prints. Pure, and tested.

Three things worth knowing before changing it:

1. **No dependency was added.** The only libraries here are Tailwind and `recharts`; `ogl` would put a 3D engine in the bundle to draw one quad. It is WebGL1 (GLSL ES 1.00) on a full-screen quad, which costs exactly one thing — a uniform array cannot be indexed by an expression, so the palette lookup is a bounded search.
2. **The loop stops.** It pauses for a canvas scrolled out of view, for a hidden tab, and for `prefers-reduced-motion` — where the field is drawn once at a fixed phase instead of animating, because the blob *is* the panel and removing it would leave a hole.
3. **No WebGL is a fallback, not a blank box.** A refused context or a shader that will not compile renders stacked gradients in the caller's palette and marks the element `data-blob-fallback` — so the difference is visible in the DOM, and the reason is logged rather than swallowed.

**What is on screen** is a glass sphere with a voice orb at its centre. The liquid is `count` chromatic bands, each one an almond — wide and bright on the axis and pinched to a point at both ends, which is what a ring around a sphere looks like from just above its equator — and odd and even bands lean opposite ways, so they cross in the middle instead of nesting. The sphere then samples that liquid through itself, once per colour channel, which is what splits the bands inside it the way a real lens does, and adds a saturated rim, one sheen, and the bright crescent a glass ball focuses underneath itself. The canvas is **transparent**: it writes straight alpha whose alpha *is* its brightness, so the surface sits on a white card as happily as on a dark panel. The orb is part of the component rather than something the page adds — three DOM bars in a frosted disc, animated by one CSS keyframe, sized and timed from `aiBlob.js`.

`blobShader.test.js` pins the JavaScript↔GLSL seam: the uniforms the component uploads must be the ones the shader declares, because `gl.getUniformLocation` returns `null` for a name that does not exist and `gl.uniform1f(null, x)` is a **silent no-op** — a prop would simply do nothing, with no error anywhere. It also refuses a backtick in either source: both are template literals, and a markdown-quoted prop name in a GLSL comment either fails to parse or — worse, when the pair is balanced — parses cleanly and hands the driver JavaScript spliced through the shader.

⚠️ **Provenance, stated plainly.** The published docs for this component are for a Lightswind **Pro** one and ship a comment in place of the source. What is here is an independent implementation of the same documented API — same five props, same defaults, our own pixels — and the page says so where an admin will read it. The install instructions from the original doc are kept there for reference and labelled as not-to-run.

## Pages

| Route | Description |
|-------|-------------|
| `/login` | Admin-only login |
| `/` | Dashboard with stats, recent applications & orders |
| `/users` | User management |
| `/seller-applications` | Approve/reject seller applications |
| `/products` | Product catalog management |
| `/model-requests` | 3D model requests filed by sellers: claim, publish a model and close in one step (P2, dark by default), close as done against a live model, decline with a reason — and the seller is told in both closing cases (P3) |
| `/orders` | Order management |
| `/transactions` | GCash/PayMongo payment transactions (read-only) |
| `/analytics` | Charts and trends |
| `/ai` | Ai Fluid Blob — the AI voice-assistant visual: live controls, the five states side by side, usage and props (reads no data) |
| `/settings` | Admin profile & password |
