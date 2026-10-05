# Shoe Model Authoring Guide — Capture to Compliant GLB

**Version:** 1.2.0
**Created:** September 27, 2026
**Updated:** September 28, 2026 — **§C9 has a companion: when a row fails for a mechanical reason, `tool/prepare_shoe_model.dart` fixes the file instead of sending it back to Blender (roadmap V2.7).** It bakes the exporter's node rotation into the vertices, re-axes the shoe so the length runs along +Z, scales it to the declared external length, grounds and centres it at the heel, re-bakes textures down to 1024², renames the parts and strips extensions the shipped renderer has no proven support for — printing every change it made. It is a **recovery** tool for a file already exported out of contract: it cannot know which end is the toe (you must say, or it assumes the positive end and says so) and it cannot invent the declared length. Its first real recovery was a 31.5 MiB marketplace asset that was 4.3× life size, lying on its side with the transform left on the node, textured at 4096² and carrying one material called `Material.001`; it came out 1.66 MiB and 11/11 green (§6, §9)
**Prev. update:** September 28, 2026 — **the same 11 rows now run a second time, server-side, and the two copies are proven to agree (roadmap V2.4).** `validate-shoe-model` re-reads the uploaded row, downloads the stored object and runs the contract over those bytes before the model may go live, and `tool/check_glb_validator_parity.mjs` diffs its rule set against the CLI's over 22 fixtures — so a file that passes here and is refused there is a bug to report, not a judgement call to argue with. Nothing in the contract changed
**Prev. update:** September 27, 2026 — **§C9 is now a real command.** `tool/validate_glb.dart` (roadmap V2.7) is built, so the checks a file must survive are the ones this guide lists as rows; §C6's part table gained the explicit `midsole` name the validator approves
**Audience:** artisan partners, studios/freelancers producing assets, in-house content lead
**Produces:** the `.glb` files the virtual fitting renders (architecture §2.5)
**Contract source of truth:** `docs/RoadMap/VIRTUAL_FITTING_ARCHITECTURE.md` §2.5.1 (this guide is the how; that section is the what)
**Related:** `docs/RoadMap/VIRTUAL_FITTING_ROADMAP.md` (V0.3 freezes the contract, V0.4–V0.5 is the rehearsal capture, V2.7 builds the validator, V2.8–V2.9 are the first three products)

---

## 0. What you are making

One `.glb` per product colourway: a faithful, measured, lightweight 3D copy of the **actual shoe the customer will receive**, sized and oriented so the app can put it on a real foot.

| Item | Requirement | Why |
|---|---|---|
| Format | Single-file **`.glb`** (glTF 2.0 binary), textures embedded | One download, one cache entry, no missing-file class of bug |
| Units / up-axis | **Metres**, Y-up, model scale 1.0 | The renderer's world is metres (ARCore) |
| Origin | **Heel-bottom-centre at (0,0,0)**, sole resting on the ground plane | The app anchors this point to the floor and the foot's heel |
| Forward | **Toe along +Z** | The app aligns it with the forward axis of the measured foot |
| Reference size | Declared (e.g. EU 42) and the **physical sample you scanned must be that size** | Scale math grades from the reference size (6.67 mm per EU step) |
| Dimensions | **True measurements**, mesh length = measured external length ±5 mm | A wrongly scaled shoe is worse than no shoe |
| Parts / materials | Named exactly: `upper`, `sole`, `laces`, `lining`, `heel` (add `midsole` if used) | Colour swapping targets parts by name |
| Budget | ≤ 60 k triangles (target 25–45 k) · ≤ 2 texture sets at ≤ 1024² · ≤ **5 MB** file (8 MB hard bucket limit) | Mid-range Android fps and Cebu mobile data |
| Compression | **Off by default** — see the warning below | Renderer support is unverified until roadmap V0.7 |
| Shoes in the file | **One shoe**, declared side (default right) | The app renders one foot at a time; the left is mirrored |

> ⚠️ **Compression warning.** Draco / meshopt geometry compression and KTX2 textures are **not** approved yet — roadmap **V0.7** checks whether the renderer decodes them. Until that check passes, export **uncompressed** and stay under the 5 MB budget with geometry count and texture size. A file the renderer cannot decode is a dead product.
>
> **Where that check stands (2026-09-27):** the renderer we ship (`gltfio-android` 1.72.1, the **non-lite** artifact — note there is a `gltfio-android-lite` that drops these decoders, so never swap that dependency casually) carries real Draco decode paths — `Cannot decompress mesh, Draco decoding error`, `Failed to parse Draco header` — plus a BasisU transcoder and `EXT_meshopt_compression` handling. So the answer is *probably* yes, but it is **not proven** until `GltfioDecodeTest` runs on a physical phone; an emulator cannot load any model at all (`AR_TRY_ON_SPIKE_FINDINGS.md` F14). **Keep compression off until that run lands.**
>
> ⚠️ **Materials are a crash risk, not a style rule.** A material whose requirements the mesh cannot satisfy — parameters gltfio sets that the material lacks, or textures/tangents the mesh does not carry — does not fail the load: it **aborts the process** (`utils::PreconditionPanic` inside `AssetLoader::createAsset`; findings F16). Export with **UVs and tangents on**, one material per named part, and never attach a normal or roughness map whose UV set the mesh does not really have.

### 0.1 Two lengths — never mix them up

This is the single most common mistake, so it is the first thing to get right.

| Number | What it is | How you get it | Where it is used |
|---|---|---|---|
| **External length** | The shoe's outside heel-to-toe length, as measured with a ruler/calipers | Measure the physical sample; also verify against the mesh bbox | **Rendering scale.** The mesh must match the real shoe so it looks right beside a foot |
| **Internal last length** | How long the *inside* is — the length a foot actually sits in | From the maker's pattern/knife, or by measuring inside; usually **8–15 mm shorter** than external for leather shoes | **Fit verdict.** `toeAllowance = internal last length − foot length` |

Deliver both. The app renders using the external figure and judges fit using the internal one; confusing them makes the shoe either oversize or misleading.

---

## 1. Before you start

**Kit**

| Needed | Notes |
|---|---|
| The physical sample shoe | One shoe is enough (the pair's design is what matters). Log which partner, which product, which size, which side, and who holds it |
| Ruler + calipers (or a last gauge) | For external length/width and the internal-length declaration |
| Scale reference | A printed ruler, ArUco marker, or any object of known length that stays in frame. **Mandatory** — reconstructions are unitless without it |
| Reconstruction tool | Phone: Polycam, RealityScan, KIRI Engine. Desktop: RealityCapture, Metashape. Pick one and record which |
| Blender | Any recent version — the glTF 2.0 exporter is built in |
| Lighting | Diffuse, steady daylight or two soft lights. No flash, no hard shadows |
| Turntable **or** a clear walk-around space | Decide one method and stay consistent (§2) |

**Prep the shoe**

1. Lace it as it is sold. Do not tuck, swap or hide laces — they are the hardest part to reconstruct and the most obvious when missing.
2. Clean it. Dust and fingerprints become texture noise.
3. Matte the surface if it is glossy (see §2.2). Shiny leather is the number one cause of holes.
4. Photograph the shoe from 6 canonical angles **before** capture, as reference for the Blender stage and for the acceptance review.

**Folder layout** (create it now; it is part of the handover)

```
capture/<partner-slug>/<product-slug>/<colour-slug>/
  photos/          raw capture frames
  reference/       the 6 pre-capture stills + caliper photos
  work/            reconstruction exports (obj/fbx/ply)
  deliver/         the .glb + .blend + declaration.txt
```

---

## 2. Stage A — Capture the real pair

### 2.1 Coverage

| Pass | Elevation | Shots | Purpose |
|---|---|---|---|
| Low ring | ~15° above the floor | 12–20 | Sole edge, heel curve |
| Mid ring | ~40° | 12–20 | The main surface, laces, side panels |
| High ring | ~70° | 12–20 | Collar, tongue, interior lip |
| Top | Straight down | 2–4 | Toe box and tongue |
| Bottom (optional) | Upside down | 2–4 | Outsole tread — only if the try-on will ever show the sole |

Rules: **≥ 70% overlap** between consecutive shots, the shoe fills the frame, focus locked, no motion blur. Walk around the shoe (do not rotate it) **or** use a turntable plus a reference that rotates with the shoe — never mix the two.

### 2.2 Shiny surfaces

Leather, patent finishes and metal eyelets reflect the room and reconstruct as holes.

- Diffuse the light (softbox, white sheet, open shade) and shoot with a polarising filter where available.
- If holes persist, mark them and fill in Blender (§4 C3). **Do not** coat the sample with matting spray without testing it on a scrap or a hidden area first — artisan samples are not replaceable.
- Never shoot with flash. Never shoot into a window.

### 2.3 Reject-and-reshoot signals

| Signal | Action |
|---|---|
| Blown-out highlights covering a surface | Diffuse the light and re-shoot that pass |
| Motion blur in any frame | Delete the frame; re-shoot (blurry frames poison the reconstruction) |
| Fewer than ~60 usable frames | Re-shoot — density is what makes the mesh clean |
| No scale reference visible anywhere | Re-shoot. The whole capture is unusable |

---

## 3. Stage B — Reconstruct

1. Import the frames into the chosen tool, run the reconstruction, and **set the scale from the reference before anything else**.
2. Verify: measure heel→toe in the reconstructed mesh and compare with your calipers. They must agree within **±3 mm**. If they do not, the reference step failed — fix it before exporting.
3. Export the dense mesh (OBJ/FBX/PLY) with its texture into `work/`.
4. Record in the declaration: tool used, date, frame count, and the scale-verification numbers.

**Reject signals before Blender:** warped or twisted sole, laces melted into a solid lump, the heel hollowed out, a shoe that curves like a banana. Fixing those in Blender costs more than re-shooting.

---

## 4. Stage C — Blender cleanup (the core checklist)

Work through this in order. Each step ends with a check you can see in Blender's own UI.

### C1 — Scene setup and orientation

1. Scene properties → Units: **Metric**, Unit Scale **1.0**, Length: Metres.
2. Import the reconstruction (File → Import).
3. Orient the model: **toe pointing −Y**, **up +Z**, **heel-bottom-centre at (0, 0, 0)**, sole resting on `z = 0`.

```
Blender (top view)                    Shipped .glb (glTF)
        −Y = toe                              +Z = toe
            ↑                                     ↑
   +X ←── (0,0,0) ──→ −X            +X ←── (0,0,0) ──→ −X
        heel at origin                        heel at origin
   sole on z = 0                          sole on y = 0
```

4. Apply all transforms (**Ctrl+A → All Transforms**). Rotation and scale must read 0°/1.0 on every object at export.

> The exporter's "+Y Up" option maps Blender `(x, y, z) → glTF (x, z, −y)`. That is exactly why the toe points along **−Y** here: it becomes **+Z** in the shipped file. Do not "fix" the orientation after export — fix it here.

**Check:** in Blender's front view (Numpad 1) you are looking at the toe; the model sits exactly on the grid floor; the origin gizmo is at the heel, on the ground.

### C2 — Measure and reconcile

1. Enable the Dimensions overlay (N panel → Item → Dimensions).
2. Record external **length (Y), width (X), height (Z)** in millimetres and compare to the calipers.
3. Discrepancy > 5 mm: scale numerically (`scale = measured / actual`), apply, re-measure. Do not eyeball it.

**Check:** declared external length = mesh Y-size ±5 mm. Write the number down — it goes in the declaration.

### C3 — Clean the mesh

1. Delete the scale-reference object, the ground plane, and any stand the shoe rested on.
2. Remove floating fragments (loose parts that are not the shoe).
3. Fill reconstruction holes — especially the interior opening and any glare holes on the upper. Interior surfaces that the try-on never shows may stay simplified, but they must be **closed** or the shading breaks.
4. Remove non-manifold junk: doubled faces, stray vertices, self-intersecting laces. Laces may be rebuilt as simple swept tubes rather than kept from the scan.

**Check:** wireframe view shows no floating islands and no see-through gaps; the silhouette matches the pre-capture reference photos.

### C4 — Retopology / decimation

| Target | Value |
|---|---|
| Hard cap | 60,000 triangles |
| Recommended | 25,000–45,000 |
| Silhouette | Toe box curve, heel curve, collar and sole edge must survive — that is what the customer recognises |

1. Separate the shoe into its parts (upper / sole / laces / lining) so decimation does not destroy critical edges, then decimate each part (Decimate modifier, Collapse) and merge them back by material.
2. Prefer a clean lower-poly rebuild over aggressive decimation when the scan is dense and lumpy — 2,000 triangles of well-shaped geometry beats 60,000 of triangle soup.

**Check:** Blender's statistics (viewport overlay) shows ≤ 60 k triangles; the shoe still reads as *that* shoe from three metres away.

### C5 — UVs and PBR baking

1. UV unwrap the cleaned mesh (Smart UV Project is acceptable for v1; manual layout for hero products).
2. Bake to a PBR set at **1024² max**:
   - **Base colour** — and **de-light it**. Scans bake the capture lighting into the albedo; a baked highlight fights the AR scene lighting and makes the shoe look painted on. Bake with a flat/neutral lighting setup, or repaint the worst-affected areas.
   - **Roughness** — leather is not uniform; keep the variation.
   - **Metallic** — 0 everywhere except eyelets/hardware (if those are separate parts).
   - **Normal** — bake from the high-poly scan if you retopologised.
3. Pack textures into the `.blend` / embed in the GLB. No external files.

**Check:** the base-colour map has no light source visible in it; textures total ≤ 2 sets at ≤ 1024².

### C6 — Materials and part names

Rename materials **exactly**:

| Material name | Covers |
|---|---|
| `upper` | Main upper surface |
| `sole` | Outsole |
| `midsole` | Midsole, when it is a separate part from the outsole |
| `laces` | Laces and their eyelet stitching if not separate |
| `lining` | Interior lining and insole top |
| `heel` | Heel counter/block if visually distinct |

Rules: one Principled BSDF per material; no procedural node trees that the exporter drops; no material assigned to nothing. Each part must be assigned to exactly one of these names — the app's colour swap addresses them by name, and a typo means the colour silently does not change.

**Check:** outliner shows exactly these material slots, no extras, no `Material.001`.

### C7 — Budget audit

| Metric | Limit | Where to read it |
|---|---|---|
| Triangles | ≤ 60 k | Blender statistics overlay |
| Textures | ≤ 2 sets, ≤ 1024² | Image list |
| Exported file | ≤ 5 MB | After export (C8) |

### C8 — Export the GLB

`File → Export → glTF 2.0` with:

| Setting | Value |
|---|---|
| Format | **glTF Binary (.glb)** |
| Include | Selected/Visible objects only — the shoe, nothing else |
| Transform → +Y Up | **On** (default) |
| Apply Modifiers | On |
| Data → Materials / UVs / Normals / Tangents | On |
| Cameras / Lights / Punctual Lights | **Off** |
| Animation | Off |
| Compression (Draco) | **Off** until roadmap V0.7 approves it — that decision is one real-device test away (see the compression warning) |

### C9 — Validate

Run the project validator on the exported file:

```bash
dart run tool/validate_glb.dart deliver/<name>.glb
```

It takes the declared external length from `declaration.txt` beside the model (or `--external-length-mm`), prints an 11-row pass/fail table, and **exits non-zero if anything failed**, so a script can gate on it (`--json` gives the same report to a machine). What each row means:

| Row | Fails when |
|---|---|
| format | not a GLB, glTF ≠ 2.0, a truncated file, or a chunk that runs past the end of the file |
| single file | any `buffers[]`/`images[]` entry has a `uri` — export with textures embedded |
| file size | over **5 MB** (a file between 5 and 8 MB would still upload — the bucket's cap is 8 MB — but it breaks the contract) |
| triangles | over **60 k** |
| materials | a missing or unnamed part, a duplicate name, a name outside the six approved, or no `upper`/`sole` (see §C6) |
| textures | any image over **1024²** (past 8 images the tool only *warns*, because image count cannot be turned into "sets" — a reviewer confirms §C7) |
| compression | Draco, meshopt or KTX2 is declared — all three are on hold until roadmap V0.7 proves the renderer decodes them |
| units | the long axis is outside a plausible 100–400 mm — the usual cause is a file authored in millimetres instead of metres |
| orientation | the mesh is taller than it is long (a Z-up export) or wider than it is long (rotated) |
| origin | the sole is off the ground plane, the heel is not at the origin on Z, or the mesh is off-centre in X (all ±5 mm) |
| scale | the mesh's +Z length differs from the declared external length by more than ±5 mm — **this row fails on purpose when no length is declared**, because that comparison is the whole point of the handover |

Two things it deliberately **cannot** check, which is why §5.2 keeps reviewer rows: **toe-vs-heel direction** (a bounding box is symmetric about that question) and anything about appearance — de-lit albedo (§C6), likeness, on-device frame rate. A green run means the file is *shaped* right, not that it is the shoe.

### C9.1 — When a row fails: the normaliser

A red row is usually one of six mechanical mistakes, and every one of them is cheaper to repair than to re-export. The project's normaliser does that repair:

```bash
dart run tool/prepare_shoe_model.dart deliver/<name>.glb \
    --external-length-mm 278 --authored-size-eu 42 --toe -x \
    --material "Material.001=upper" --sole-band-mm 12
# → deliver/<name>.contract.glb, then re-run §C9 on it
```

| Failed row | What the normaliser does | Why it is safe |
|---|---|---|
| orientation / units / origin | bakes the root node's rotation into the vertices, yaws the length onto +Z, scales to `--external-length-mm`, then grounds the sole to y = 0, heeels onto z = 0 and centres x | it is the same arithmetic §C1–C2 asks a person to do in Blender, done numerically and logged |
| textures | re-bakes every image to ≤ 1024² (aspect preserved) and re-encodes as JPEG unless `--png` is given | a 4096² leather albedo becomes ~180 KB of the budget instead of 12.6 MiB |
| materials | applies `--material from=to` renames; `--sole-band-mm` puts every triangle within that height of the ground in its own `sole` part | for a marketplace or AI-generated asset that ships one material and cannot be re-authored; the cut line is a guess and is reported as one |
| compression | **refuses** — a Draco or meshopt file cannot be decompressed offline, so it tells you to re-export (this is the one row it will not paper over) | a silently mangled decompression is worse than a refusal |

It writes `<name>.contract.glb` and prints before/after size, triangles, part names and L×W×H plus every change it made, so the handover records the surgery rather than hiding it. Two things it will not decide for you:

- **Which end is the toe.** `--toe +x|-x|+z|-z`; without it the tool assumes the positive end of the long axis, says so in its output, and the file may render backwards. This is checklist row 2, and it stays a human row.
- **The declared external length.** Without it the tool re-axes and re-grounds but **does not scale** — the scale row then keeps failing, on purpose, because inventing the number would defeat the check that exists to catch a wrong size.

Do not treat C9.1 as a replacement for §C1–C3. A file that needed the normaliser is a file whose scene was left with an unapplied transform, an unmeasured scale, or an un-split mesh — the fixer repairs the symptom; the next asset should still be authored correctly in Blender.

#### C9.1b — The same repair, from the admin queue (no terminal)

Since 2026-10-03 the portal's `/model-requests` queue runs the same normaliser in the browser, so an admin answering a request no longer needs a shell. When a picked `.glb` is over the 5 MiB authoring budget, the upload dialog offers **Compress it**; it decimates the mesh and then runs **the same `normalizeShoeModel` this guide's CLI runs** — `lib/utils/glb_normalizer.dart`, compiled to JavaScript by `tool/build_shoe_model_normalizer_web.mjs` rather than reimplemented, so there is still exactly one copy of the rules.

What that adds over the CLI, and what it does not:

| | CLI (§C9.1) | Portal (C9.1b) |
|---|---|---|
| Bake node transform, re-axis, ground, re-bake textures, rename parts | yes | yes (same code) |
| **Decimate** a mesh over the 60 k triangle cap | **no** — a manual `gltf-transform simplify` first | yes — ratio chosen to land near 40 k, skipped when already inside the cap |
| `--toe +x/-x/+z/-z` | yes | no — assumes the positive end and says so, exactly as the CLI does without the flag |
| `--material from=to` for several unapproved names | yes | no — it refuses with the names and the CLI command instead, because guessing which is the upper repaints the wrong part |
| `--sole-band-mm` | yes | yes, at the 12 mm default, reported as the approximation it is |
| Runs the §C9 checks and prints a report card | yes | **no** — the portal adds no third implementation of the eleven rules; the server judges the stored bytes on upload, as always |

A run takes roughly 40 s for a 90 MB export and happens in a Web Worker, so the tab stays usable. Its output is the same file the CLI produces (verified byte-identical on the 90 MB recovery below), and **its green is not acceptance any more than the CLI's is**: the four reviewer rows in the table above are untouched by either route.

Optional external sanity checks: the Khronos **glTF-Validator**, and **gltf.report** for a quick visual + structural look.

**Attach the tool's output to the handover** as `validator-output.txt` (§5.1): the same checks run again on upload and in the server-side validator (roadmap V2.3/V2.4), so a mismatch there is an automatic rejection rather than a negotiation.

**Since 2026-09-28, "the same checks" is verifiable rather than promised (V2.4).** The server-side validator runs a TypeScript mirror of this contract — an Edge Function cannot import the Dart library the CLI uses — and `node tool/check_glb_validator_parity.mjs` runs both over 22 fixtures and diffs the reports, check row by check row. Two consequences worth knowing as a partner: the server is the one that pulls the trigger (it is the only thing allowed to make a model visible, and it re-checks the stored bytes against the digest the row recorded, which the CLI cannot see), and **the four reviewer rows stay reviewer rows no matter how green both runs are** — toe-vs-heel direction, de-lit albedo, likeness and on-device frame rate are not decidable from bytes, and the server says so on every answer rather than letting a pass imply approval.

---

## 5. Handover package and acceptance

### 5.1 What you deliver

```
deliver/
  <partner-slug>_<product-slug>_<colour-slug>_v1.glb     ← the shippable asset
  <partner-slug>_<product-slug>_<colour-slug>_v1.blend   ← editable master (kept, never shipped)
  declaration.txt                                        ← the numbers below
  validator-output.txt                                   ← §C9 result
```

Plus `capture/…` and `reference/…` from §1, and the reconstruction export in `work/`.

**`declaration.txt` template**

```
product:              <product name + catalog id>
partner:              <workshop / studio name>
colourway:            <colour name exactly as it appears in the catalog>
shoe_side:            right | left
authored_size_eu:     42
external_length_mm:   <mesh Y size, measured>
external_width_mm:    <mesh X size>
internal_last_mm:     <from the maker's pattern; if unknown, write UNKNOWN>
external_length_source: calipers | mesh | maker
reconstruction_tool:  <name + version>
capture_frames:       <count>
scale_reference:      <object used + its length>
notes:                <holes filled, laces rebuilt, anything a reviewer should know>
```

### 5.2 Acceptance checklist

| # | Check | Pass criteria | Who |
|---|---|---|---|
| 1 | File opens in a glTF viewer without errors | No console errors | Reviewer |
| 2 | Origin / orientation | Heel-bottom-centre at origin, toe +Z, sole on the ground plane | Reviewer |
| 3 | Scale | Mesh external length = calipers ±5 mm, at the declared reference size | Reviewer + validator |
| 4 | Budget | ≤ 60 k tris, ≤ 5 MB, ≤ 2 texture sets at ≤ 1024² | Validator |
| 5 | Parts | Exactly the required material names | Validator |
| 6 | Albedo de-lit | No baked light source visible under neutral lighting | Reviewer |
| 7 | Likeness | Side-by-side with the reference photos, a reviewer says "that is the shoe" | Artisan partner + reviewer |
| 8 | Colour swap | Applies a colour to each part name correctly in a test session | Reviewer |
| 9 | Renders on device | Loads and holds ≥ 30 fps in the app on the mid test device | Mobile team |
| 10 | Declaration complete | Every field filled, `UNKNOWN` allowed only for `internal_last_mm` | Reviewer |

Rejections are recorded on the `product_models` row (`status = 'rejected'`) with the validator output and the checklist line that failed; rework goes back to C3–C9, not back to a blank page.

---

## 6. Common failures

| Symptom | Real cause | Fix | Caught by |
|---|---|---|---|
| Shoe renders twice the size of the foot | Scan never scaled from the reference | Redo §3.1–3.2, re-measure, apply in Blender | Checklist 3, validator |
| Shoe points backwards / stands upright | Orientation "fixed" in the export dialog instead of in Blender | Rotate in Blender to −Y/toe, apply transforms, re-export | Checklist 2 |
| Model floats above or sinks into the floor | Origin not at heel-bottom-centre, or sole not on z = 0 | Move origin (Origin to 3D Cursor at (0,0,0)), drop sole to z = 0 | Checklist 2 |
| Renderer refuses to load the file | Draco/KTX2 used before approval, or external texture references | Re-export uncompressed with embedded textures | C9, `model_parse_failed` telemetry |
| Colour swatch does nothing | Material renamed `Material.001` or misspelled (`Laces`, `upper_2`) | Rename to the exact six names (§C6), one material per part | Checklist 5 |
| Shoe looks painted onto the foot | Capture lighting baked into the albedo | Re-bake base colour de-lit | Checklist 6 |
| Jittery, lumpy surface | Decimated triangle soup, normals broken | Rebuild lower-poly, recompute normals, bake a normal map | Review |
| Huge download, slow first open | 4K textures, 200 k triangles | Re-bake to 1024², retopo to ≤ 45 k | Checklist 4 |
| Holes where the light hit the leather | Specular glare in capture | Re-shoot with diffusion, or fill in Blender (C3.3) | Review |
| Laces are a solid lump or missing | Thin structures + glossy cord | Rebuild laces as simple tubes (C3.4) | Review |
| The model is a *lookalike*, not the product | Asset bought from a marketplace or AI-generated instead of scanned | Re-scan the real pair — a generic shoe misrepresents the product | Checklist 7, partner sign-off |
| Validator says the mesh is taller than it is long | The scene's rotation was left on the node ("+Y Up" applied by the exporter rather than in the scene) | C9.1 (bakes it) or §C1.4 (Ctrl+A → All Transforms, then re-export) | C9 `orientation`, C9.1 |
| Validator says the mesh is 4× life size | The scene was never scaled to metric, or the model came from a marketplace in its own units | C9.1 with `--external-length-mm`, or §C2 numerically | C9 `units`/`scale` |
| The length runs along X, not Z | Shoe modelled sideways rather than toe along −Y | C9.1 (yaws it; **you must pass `--toe`**) or §C1.3 | C9 `orientation` |
| Every part is one material called `Material.001` | Asset could not be re-authored — marketplace, scan, or AI-generated mesh | C9.1 renames it and can cut a `sole` band geometrically; the cut line needs a reviewer | C9 `materials`, checklist 5 |

---

## 7. Quick reference card

```
CAPTURE     60–120 shots · 3 elevation rings + top · ≥70% overlap · scale reference in frame
            diffuse light · no flash · laces as sold · matte glossy leather
RECONSTRUCT set scale from the reference FIRST · verify heel→toe ±3 mm
BLENDER     metric 1.0 · toe −Y · up +Z · origin at heel-bottom-centre · sole on z=0
            apply transforms · clean holes/fragments · retopo ≤60k (target 25–45k)
            UV + bake base colour DE-LIT, roughness, normal · textures ≤1024²
            materials: upper · sole · midsole · laces · lining · heel
EXPORT      GLB · +Y Up ON · no cameras/lights · NO compression until V0.7 approves
VALIDATE    dart run tool/validate_glb.dart <file.glb>
PREPARE     dart run tool/prepare_shoe_model.dart <file.glb> --external-length-mm <mm> --toe <end>
            (only when VALIDATE fails: bakes the node transform, re-axes, scales, grounds,
             re-bakes textures to 1024², renames parts — prints every change)
DECLARE     external length (mesh) + internal last length (fit) + reference size
```

---

## 8. Notes for the internal team

- **V0 placeholder assets:** the V0 renderer spike may use an internal block-out (a few thousand triangles, wrong in every artistic sense, correctly oriented and scaled). Such a model is **never** published to a product and never uploaded to `shoe-models` with `status='active'`.
- **Tooling: the validator exists; the upload path does not.** `tool/validate_glb.dart` (roadmap V2.7) is built, so §C9 is a real command rather than an aspiration. Still to build: the seller upload UI (V2.2), its client-side validation (V2.3 — which reuses the validator's own pure library), and the Edge Function validator (V2.4). Until the upload path exists, an asset reaches `product_models` by hand; keep the validator output with the handover so that manual step stays auditable.
- **Master assets** (`.blend`, raw captures) live in the content store, **not** in the app repo and not in the app bundle. Only the `.glb` reaches `shoe-models` and the device.
- **Mirroring:** the app mirrors the declared side for the other foot. Designs that are visibly asymmetric (a single outer strap) may need a second asset — decide per product at review time, not by default.

---

## 9. Changelog

| Date | Version | Change |
|---|---|---|
| Sep 28, 2026 | 1.2.0 | **C9.1: the normaliser.** `tool/prepare_shoe_model.dart` + the pure `lib/utils/glb_normalizer.dart` (roadmap V2.7) repair a file that fails C9 for a mechanical reason — bake the node transform, re-axis onto +Z, scale to the declared length, ground/centre, re-bake textures to 1024², rename parts (with the optional geometric sole band), strip unsupported extensions — and refuse the two things that cannot be fixed offline (Draco/meshopt, KTX2). §6 gained the four failure rows it repairs and §7 a PREPARE line. First real recovery: a 31.5 MiB marketplace asset → 1.66 MiB, 11/11 green |
| Sep 27, 2026 | 1.1.1 | §C9's rows now run a second time server-side, with `tool/check_glb_validator_parity.mjs` proving the TypeScript mirror against the Dart reference over 22 fixtures (roadmap V2.4) |
| Sep 27, 2026 | 1.0.1 | Compression warning now carries the measured state of the V0.7 check (Draco decode paths and a BasisU transcoder are present in the shipped `gltfio-android`, unproven until the device test runs) and a new **materials are a crash risk** warning from findings F16 |
| Sep 27, 2026 | 1.0.0 | Initial guide — capture, reconstruction, Blender cleanup, export, validation, acceptance checklist |

---

*SoleVision / CUFMAI — Shoe Model Authoring Guide v1.2.0 — September 28, 2026.*
*If a requirement here disagrees with `VIRTUAL_FITTING_ARCHITECTURE.md` §2.5.1, that section wins — then tell the mobile team so both are fixed.*
