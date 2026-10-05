// ─── "Compress it": the one repair an admin can make without a terminal ──
//
// A partner sends back a raw export — the file this was written against was
// 90.1 MB, 1.5 million triangles, three 4096² textures, one material called
// `Material.001`, authored 4.37× life size — and the admin's only route was
// `dart run tool/prepare_shoe_model.dart` in a shell. That is the gap the
// authoring guide's own §C9.1 opens with, and the reason the Flutter screen's
// header says the picker could otherwise "only ever be filled by someone with a
// terminal".
//
// **What this module is: the decisions, not the work.** The bytes are
// transformed in a Web Worker by the *compiled reference normalizer*
// (`glb_normalizer.gen.js`, built from `tool/shoe_model_normalizer_web.dart`)
// plus `@gltf-transform`'s weld/simplify. Everything here is pure and runs on
// the main thread before any of that starts: what the file is, whether it can
// be repaired at all, and what the repair will assume.
//
// **The portal still does not run the authoring contract.** That rule is
// unchanged and this module is careful to stay inside it. The eleven checks
// have exactly two implementations — the Dart reference and the TypeScript
// mirror in `validate-shoe-model`, parity-checked over 22 fixtures — and a third
// would be a third place for eleven rules to drift. Nothing here returns a
// verdict, and the UI never shows a report card: the server judges the stored
// bytes, exactly as before.
//
// What it does do is *read the file well enough to plan a repair*: how many
// triangles there are, and what the materials are called. Those two numbers
// pick a decimation ratio and decide whether the geometric sole cut applies.
// Neither is compared against a cap to produce a pass or a fail. If the count
// is wrong the only consequence is a suboptimal ratio — the server counts for
// real, and its count is the one that decides.
//
// **And it is honest about what it assumes.** Scaling to the declared length
// and cutting a sole band at a fixed height are decisions the file cannot make
// for itself (the normalizer's own header says so), so every one of them is
// reported back as a change line and shown to the admin rather than applied
// quietly.

/** The guide's authoring budget ("≤ 5 MB", §C7). A file over this uploads and
 *  is then refused by the server, which costs a round trip and a download —
 *  which is why it is the number the compress offer appears above, not the
 *  bucket's larger cap. Mirrors `FILE_SIZE_BUDGET_BYTES` in
 *  `supabase/functions/_shared/glb_validator.ts`; the contract test reads that
 *  file rather than trusting this comment. */
export const FILE_SIZE_BUDGET_BYTES = 5 * 1024 * 1024

/** The triangle cap (§C4). Over this, decimation runs. */
export const MAX_TRIANGLES = 60000

/** Where decimation aims: the middle of the guide's 25,000–45,000 target band,
 *  so a file lands inside it whether the simplifier overshoots or undershoots. */
export const TARGET_TRIANGLES = 40000

/** The sole cut line used when a single-material mesh is split (the CLI's
 *  `--sole-band-mm 12`). A starting point, not a measurement: the change log
 *  calls the cut an approximation and the reviewer confirms it (§6). */
export const SOLE_BAND_DEFAULT_MM = 12

/** Guide §C6 — the exact names a colour swap can target. Mirrors the array in
 *  the TypeScript validator, which the contract test reads. */
export const APPROVED_PART_NAMES = ['upper', 'sole', 'midsole', 'laces', 'lining', 'heel']

/** The two parts every shoe has. */
export const REQUIRED_PART_NAMES = ['upper', 'sole']

/** The most a decimated mesh is allowed to deviate, as a fraction of its
 *  radius (the CLI's `--error 0.01`). */
export const SIMPLIFY_ERROR = 0.01

/** Sizes, the way the rest of the portal writes them — `tooLargeMessage` in
 *  `modelPublish.js` uses the same two decimal places. */
export function formatBytes(bytes) {
  // `null`/`undefined` are checked before `Number()`: `Number(null)` is 0, and
  // a missing size rendering as "0 B" would read as an empty file rather than
  // as an unknown one.
  if (bytes === null || bytes === undefined) return '—'
  const value = Number(bytes)
  if (!Number.isFinite(value) || value < 0) return '—'
  if (value < 1024) return `${value} B`
  if (value < 1024 * 1024) return `${(value / 1024).toFixed(1)} KB`
  return `${(value / (1024 * 1024)).toFixed(1)} MB`
}

/** GLB magic `glTF`, little-endian. */
const GLB_MAGIC = 0x46546c67

/** GLB chunk type `JSON`. */
const JSON_CHUNK_TYPE = 0x4e4f534a

/**
 * The two planning numbers out of a GLB, read from its JSON chunk alone.
 *
 * The JSON chunk is the small one — the 90 MB export's is 2.5 KB, against a
 * 90 MB BIN — so this is a few microseconds and no allocation worth mentioning,
 * which is why it happens on the main thread instead of round-tripping the
 * whole file through the worker to ask.
 *
 * Throws with a sentence an admin can act on, never a stack trace: this runs
 * the moment a file is picked, and "it said something went wrong" is the least
 * useful thing a file picker can say.
 */
export function readGlbPlan(bytes) {
  const view = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes)
  if (view.length < 20) {
    throw new Error('That file is too short to be a GLB — check the export and choose it again.')
  }

  const header = new DataView(view.buffer, view.byteOffset, view.byteLength)
  if (header.getUint32(0, true) !== GLB_MAGIC) {
    throw new Error(
      'That file is not a GLB — its first four bytes are not "glTF". Export "glTF Binary ' +
        '(.glb)" and choose it again (guide §C8).',
    )
  }
  if (header.getUint32(4, true) !== 2) {
    throw new Error('That file is glTF version 1. This pipeline reads version 2 only (guide §C8).')
  }

  let json = null
  let offset = 12
  while (offset + 8 <= view.length) {
    const length = header.getUint32(offset, true)
    const type = header.getUint32(offset + 4, true)
    if (offset + 8 + length > view.length) {
      throw new Error(
        'That GLB is truncated — a chunk runs past the end of the file. Re-export it and ' +
          'choose it again.',
      )
    }
    if (type === JSON_CHUNK_TYPE) {
      const chunk = view.subarray(offset + 8, offset + 8 + length)
      try {
        json = JSON.parse(new TextDecoder().decode(chunk))
      } catch {
        throw new Error('That GLB has no readable JSON chunk — re-export it and choose it again.')
      }
      break
    }
    offset += 8 + length
  }

  if (json === null || typeof json !== 'object') {
    throw new Error('That GLB has no JSON chunk — re-export it and choose it again.')
  }

  return { triangleCount: countTriangles(json), materialNames: materialNames(json) }
}

/**
 * The mesh's triangle count, for sizing a decimation ratio.
 *
 * ⚠️ Deliberately **not** a contract check. The validator's rule is
 * `triangles > 60000 → fail`, and this does not evaluate it, does not return a
 * status and is never shown as one. Its single consumer is `decimationRatio`,
 * and the worst case if it disagrees with the server is a ratio that is not
 * quite right. The server's own count is the one that decides.
 */
function countTriangles(json) {
  let triangles = 0
  for (const mesh of asArray(json.meshes)) {
    if (!mesh || typeof mesh !== 'object') continue
    for (const primitive of asArray(mesh.primitives)) {
      if (!primitive || typeof primitive !== 'object') continue
      // 4 = TRIANGLES. Anything else is a note in the real report and is
      // skipped here rather than guessed at.
      if ((primitive.mode ?? 4) !== 4) continue

      const indices = primitive.indices
      const attributes = primitive.attributes
      const position = attributes && typeof attributes === 'object' ? attributes.POSITION : null
      const accessorIndex = typeof indices === 'number' ? indices : position
      if (typeof accessorIndex !== 'number') continue

      const accessor = asArray(json.accessors)[accessorIndex]
      const count = accessor && typeof accessor === 'object' ? accessor.count : null
      if (typeof count === 'number' && Number.isFinite(count)) {
        triangles += Math.floor(count / 3)
      }
    }
  }
  return triangles
}

/** Every material name in the file, trimmed, blanks kept as '' so the caller can
 *  tell "no materials at all" from "one unnamed material". */
function materialNames(json) {
  const names = []
  for (const material of asArray(json.materials)) {
    if (!material || typeof material !== 'object') {
      names.push('')
      continue
    }
    names.push(material.name === undefined || material.name === null ? '' : String(material.name).trim())
  }
  return names
}

function asArray(value) {
  return Array.isArray(value) ? value : []
}

/** How the materials will be handled, and why. */
export const MATERIAL_PLAN = {
  /** Already carries `upper` and `sole` (and nothing outside the approved set):
   *  the names are left exactly as the modeller wrote them. */
  KEEP: 'keep',
  /** One material, or none: the normalizer's documented route for a
   *  single-material scan — a geometric cut at a fixed height, reported as the
   *  approximation it is. */
  SPLIT: 'split',
  /** Several materials, at least one outside the approved set. Which of
   *  `Material.001` and `Material.002` is the upper is a modelling question and
   *  the bytes cannot answer it, so this is refused rather than guessed. */
  UNKNOWN: 'unknown',
}

/**
 * What to do about the file's material names.
 *
 * The rule that keeps this honest: the portal may make a decision the *file*
 * makes obvious (one material cannot be two parts, so the cut is the only
 * route) and may not make one that needs a person (two unapproved names could
 * be any two parts, and guessing swaps the colour of a sole and an upper).
 */
export function planMaterials({ materialNames: names }) {
  const known = asArray(names)
    .map((name) => String(name ?? '').trim())
    .filter((name) => name !== '')

  const approved = known.every((name) => APPROVED_PART_NAMES.includes(name))
  const hasRequired = REQUIRED_PART_NAMES.every((name) => known.includes(name))
  if (approved && hasRequired) {
    return { kind: MATERIAL_PLAN.KEEP, soleBandMm: null, names: known }
  }

  if (known.length <= 1) {
    return { kind: MATERIAL_PLAN.SPLIT, soleBandMm: SOLE_BAND_DEFAULT_MM, names: known }
  }

  return { kind: MATERIAL_PLAN.UNKNOWN, soleBandMm: null, names: known }
}

/**
 * The ratio to hand `simplify`, or null when decimation should not run at all.
 *
 * Null is the interesting case: a file can be far too big and still be under
 * the triangle cap, and then the size is in the textures — which the normalizer
 * re-bakes on its own. Decimating a mesh that is already inside the budget
 * would throw away detail for nothing.
 */
export function decimationRatio({ triangleCount }) {
  const count = Number(triangleCount)
  if (!Number.isFinite(count) || count <= MAX_TRIANGLES) return null
  // Clamped at the bottom: meshoptimizer's ratio is a fraction of the *input*,
  // and a ratio small enough to be a rounding error produces a mesh with no
  // silhouette left rather than a smaller shoe.
  return Math.max(0.01, Math.min(1, TARGET_TRIANGLES / count))
}

/**
 * Everything the worker needs, or the reason there is nothing to do.
 *
 * `declaredLengthMm` is required and comes from the modal's own field — the
 * same number the server's ±5 mm scale check compares the mesh against. Without
 * it the normalizer re-axes and re-grounds but leaves the scale alone, and the
 * model is refused for a reason the admin could have fixed here.
 */
export function planCompression({ bytes, declaredLengthMm, authoredSizeEu = null }) {
  const plan = readGlbPlan(bytes)
  const materials = planMaterials({ materialNames: plan.materialNames })
  const ratio = decimationRatio({ triangleCount: plan.triangleCount })

  if (materials.kind === MATERIAL_PLAN.UNKNOWN) {
    return {
      ok: false,
      reason: 'materials',
      message:
        `This mesh has ${materials.names.length} materials and the portal cannot tell which is ` +
        `the upper and which is the sole (${materials.names.join(', ')}). Guessing would repaint ` +
        'the wrong part. Rename them in the modelling tool to ' +
        `${APPROVED_PART_NAMES.join('/')} (guide §C6), or run the CLI: ` +
        '`dart run tool/prepare_shoe_model.dart <file>.glb --material "Material.001=upper"` ' +
        'with one `--material` per part.',
    }
  }

  return {
    ok: true,
    plan: {
      triangleCount: plan.triangleCount,
      materialNames: plan.materialNames,
      materials,
      ratio,
      options: {
        externalLengthMm: declaredLengthMm,
        authoredSizeEu,
        toe: null,
        materialRenames: {},
        soleBandMm: materials.soleBandMm,
      },
    },
  }
}

/**
 * One sentence for the admin after a successful compression, built from what
 * the normalizer reported.
 *
 * It names the size it started at and the size it produced, because that is the
 * number the whole step exists for — and it ends by saying what a green result
 * is *not*, since the reviewer rows (toe direction, likeness, de-lit albedo,
 * on-device frame rate) are the ones no tool can close.
 */
export function compressionSummary({ beforeBytes, afterBytes, triangleCount, triangleCountAfter }) {
  const size = `${formatBytes(beforeBytes)} → ${formatBytes(afterBytes)}`
  const shape =
    triangleCountAfter === null || triangleCountAfter === undefined
      ? `${triangleCount.toLocaleString('en-US')} triangles`
      : `${triangleCount.toLocaleString('en-US')} → ${triangleCountAfter.toLocaleString('en-US')} triangles`

  return (
    `Compressed ${size}, ${shape}. It is not judged yet: the server reads the stored bytes when ` +
    'you publish, and a model that passes is still not a model that looks right — the toe ' +
    'direction, the likeness and the de-lit colour need a human eye (guide §5.2).'
  )
}

/**
 * What each stage of the run is called on screen.
 *
 * The stages are the worker's, not the normalizer's, because the wait is
 * dominated by two things the admin can tell apart: the simplifier chewing
 * through a million triangles, and the re-bake of three 4096² textures. Naming
 * the stage is the difference between a progress line and a hang.
 */
export const COMPRESS_STAGE = {
  READING: 'reading',
  SIMPLIFYING: 'simplifying',
  WRITING: 'writing',
  NORMALIZING: 'normalizing',
}

/** The sentence for one stage, or null for a stage this UI does not know. */
export function compressStageSentence(stage) {
  switch (stage) {
    case COMPRESS_STAGE.READING:
      return 'Reading the mesh…'
    case COMPRESS_STAGE.SIMPLIFYING:
      return 'Decimating the mesh — this is the slow one…'
    case COMPRESS_STAGE.WRITING:
      return 'Writing the smaller mesh…'
    case COMPRESS_STAGE.NORMALIZING:
      return 'Re-baking textures, re-aiming the axes and re-grounding the model…'
    default:
      return null
  }
}

/**
 * One sentence per way the compression can fail, for the causes an admin can
 * act on.
 *
 * The normalizer's own refusals (`GlbNormalizationException`) are already
 * written to be forwarded to whoever sent the file, so they are passed through
 * verbatim — the same way `verdictMessage` passes the server's words through.
 * This function only supplies the sentences for the failures that happen before
 * or after the normalizer runs.
 */
export function compressFailureMessage(error) {
  const detail = error instanceof Error ? error.message : String(error ?? '')

  // A worker that never started, or a browser that will not load one: the tab
  // is the runtime, so this is a failure the CLI route has never had.
  if (/worker|module script|failed to fetch dynamically imported module/i.test(detail)) {
    return (
      'This browser could not start the compression worker, so nothing was read from the file. ' +
      'Compress it on a machine with the toolchain instead: `dart run tool/prepare_shoe_model.dart` ' +
      '(guide §C9.1).'
    )
  }

  if (/memory|allocation|out of/i.test(detail)) {
    return (
      'The browser ran out of memory compressing this file. Close some tabs and try again, or ' +
      'compress it on a machine with more RAM using `dart run tool/prepare_shoe_model.dart` ' +
      '(guide §C9.1).'
    )
  }

  return detail.trim() === ''
    ? 'The compression stopped without saying why. Try again, and if it happens twice use the CLI (guide §C9.1).'
    : detail
}
