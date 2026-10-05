import { test } from 'node:test'
import assert from 'node:assert/strict'

import {
  MATERIAL_PLAN,
  MAX_TRIANGLES,
  TARGET_TRIANGLES,
  compressFailureMessage,
  compressionSummary,
  decimationRatio,
  formatBytes,
  planCompression,
  planMaterials,
  readGlbPlan,
} from './modelCompress.js'

// ─── The planning read ─────────────────────────────────────────────
//
// These are the decisions made *before* any bytes move, and each one is a
// place where being wrong is quiet rather than loud: a bad ratio makes a
// smaller-looking shoe, a bad material plan repaints the wrong part. So the
// tests are about the two rules that keep the guessing out — refuse what needs
// a person, do nothing the file does not need.

/** A GLB with a real header and one JSON chunk, built the way a writer would. */
function buildGlb(json, { version = 2, magic = 0x46546c67 } = {}) {
  const jsonBytes = Buffer.from(JSON.stringify(json), 'utf8')
  const padding = (4 - (jsonBytes.length % 4)) % 4
  const padded = Buffer.concat([jsonBytes, Buffer.alloc(padding, 0x20)])

  const chunkHeader = Buffer.alloc(8)
  chunkHeader.writeUInt32LE(padded.length, 0)
  chunkHeader.writeUInt32LE(0x4e4f534a, 4)

  const header = Buffer.alloc(12)
  header.writeUInt32LE(magic, 0)
  header.writeUInt32LE(version, 4)
  header.writeUInt32LE(12 + 8 + padded.length, 8)

  return Buffer.concat([header, chunkHeader, padded])
}

/** A mesh with `triangles` triangles per primitive, as the accessor count. */
function shoeJson({ triangles = 300, materials = [{ name: 'upper' }, { name: 'sole' }] } = {}) {
  const json = {
    asset: { version: '2.0', generator: 'modelCompress test' },
    meshes: [
      {
        primitives: [{ attributes: { POSITION: 0 }, indices: 1, material: 0, mode: 4 }],
      },
    ],
    accessors: [
      { componentType: 5126, count: 3, type: 'VEC3' },
      { componentType: 5125, count: triangles * 3, type: 'SCALAR' },
    ],
  }
  if (materials !== null) json.materials = materials
  return json
}

test('the triangle count is read from the index accessor', () => {
  const plan = readGlbPlan(buildGlb(shoeJson({ triangles: 1500000 })))
  assert.equal(plan.triangleCount, 1500000)
})

test('a primitive without indices falls back to the position accessor', () => {
  // Non-indexed geometry is legal glTF and the count is still the answer —
  // reading it as zero would silently skip decimation on a huge file.
  const json = shoeJson()
  delete json.meshes[0].primitives[0].indices
  json.accessors[0].count = 900
  assert.equal(readGlbPlan(buildGlb(json)).triangleCount, 300)
})

test('a non-triangle primitive is skipped, not guessed at', () => {
  const json = shoeJson()
  json.meshes[0].primitives[0].mode = 1 // LINES
  assert.equal(readGlbPlan(buildGlb(json)).triangleCount, 0)
})

test('the material names are read in order, blanks included', () => {
  const plan = readGlbPlan(
    buildGlb(shoeJson({ materials: [{ name: 'upper' }, { name: '  sole  ' }, {}] })),
  )
  // Trimmed, and the unnamed one is kept as '' so "no materials" and "one
  // unnamed material" stay distinguishable — they get different advice.
  assert.deepEqual(plan.materialNames, ['upper', 'sole', ''])
})

test('a wrong file is named by what is wrong with it', () => {
  // This runs the moment a file is picked, so every one of these is a sentence
  // an admin reads rather than a stack trace in a console.
  assert.throws(
    () => readGlbPlan(new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])),
    /not a GLB/,
  )
  assert.throws(() => readGlbPlan(buildGlb(shoeJson(), { version: 1 })), /version 1/)
  assert.throws(() => readGlbPlan(new Uint8Array(4)), /too short/)
})

test('a truncated chunk is refused rather than read past the end', () => {
  const whole = buildGlb(shoeJson())
  assert.throws(() => readGlbPlan(whole.subarray(0, whole.length - 8)), /truncated/)
})

// ─── Which materials need what ─────────────────────────────────────

test('names already inside the approved set are left alone', () => {
  // The most important case: a correctly authored file must come out the other
  // side with the modeller's own names, not renamed into a house style.
  const plan = planMaterials({ materialNames: ['upper', 'sole'] })
  assert.equal(plan.kind, MATERIAL_PLAN.KEEP)
  assert.equal(plan.soleBandMm, null)

  const withExtras = planMaterials({ materialNames: ['upper', 'sole', 'laces', 'lining', 'heel', 'midsole'] })
  assert.equal(withExtras.kind, MATERIAL_PLAN.KEEP)
})

test('one material gets the geometric sole cut', () => {
  // The documented route for a single-material scan, and the only case the
  // portal decides for itself: one material cannot be two parts, and the cut is
  // reported as the approximation it is.
  const one = planMaterials({ materialNames: ['Material.001'] })
  assert.equal(one.kind, MATERIAL_PLAN.SPLIT)
  assert.equal(one.soleBandMm, 12)

  // No materials at all lands in the same place — the normalizer names the
  // default `upper` and the cut makes the `sole`.
  assert.equal(planMaterials({ materialNames: [] }).kind, MATERIAL_PLAN.SPLIT)
  assert.equal(planMaterials({ materialNames: ['', ''] }).kind, MATERIAL_PLAN.SPLIT)
})

test('two unapproved names are refused, because guessing repaints a shoe', () => {
  // ⚠️ The rule that keeps this honest. `Material.001` and `Material.002` could
  // be upper and sole in either order, and the bytes cannot say which — a wrong
  // guess ships a model whose sole takes the upper's colour.
  const plan = planMaterials({ materialNames: ['Material.001', 'Material.002'] })
  assert.equal(plan.kind, MATERIAL_PLAN.UNKNOWN)
  assert.equal(plan.soleBandMm, null)

  // Even one approved name among unknowns is not enough: `upper` being right
  // says nothing about what the other one is.
  assert.equal(planMaterials({ materialNames: ['upper', 'Material.002'] }).kind, MATERIAL_PLAN.UNKNOWN)
  // And a missing required part is the same problem seen from the other side.
  assert.equal(planMaterials({ materialNames: ['upper', 'laces'] }).kind, MATERIAL_PLAN.UNKNOWN)
})

// ─── The ratio ─────────────────────────────────────────────────────

test('a mesh inside the cap is not decimated at all', () => {
  // The interesting case: a file can be far too big with the size in its
  // textures, and the normalizer re-bakes those. Decimating a mesh that is
  // already inside the budget throws away detail for nothing.
  assert.equal(decimationRatio({ triangleCount: 1000 }), null)
  assert.equal(decimationRatio({ triangleCount: MAX_TRIANGLES }), null)
  assert.equal(decimationRatio({ triangleCount: 0 }), null)
  assert.equal(decimationRatio({ triangleCount: null }), null)
})

test('over the cap, the ratio aims at the middle of the target band', () => {
  // 1.5 M → 40 k is the file this was written against: ratio 0.027, which is
  // the number that produced 40,500 triangles in the CLI run.
  const ratio = decimationRatio({ triangleCount: 1500000 })
  assert.equal(ratio, TARGET_TRIANGLES / 1500000)
  assert.ok(Math.abs(ratio - 0.0267) < 0.001)

  // Just over the cap is a small trim, not a rebuild.
  assert.equal(decimationRatio({ triangleCount: 60001 }), TARGET_TRIANGLES / 60001)
})

test('the ratio is clamped, so a huge mesh cannot ask for a zero-triangle one', () => {
  // meshoptimizer's ratio is a fraction of the input, so an absurd input would
  // ask for a mesh with no silhouette left rather than a smaller shoe.
  assert.equal(decimationRatio({ triangleCount: 1e12 }), 0.01)
})

// ─── The plan, end to end ──────────────────────────────────────────

test('a repairable file produces options the normalizer accepts', () => {
  const result = planCompression({
    bytes: buildGlb(shoeJson({ triangles: 1500000, materials: [{ name: 'Material.001' }] })),
    declaredLengthMm: 270,
    authoredSizeEu: 42,
  })

  assert.equal(result.ok, true)
  assert.equal(result.plan.ratio, TARGET_TRIANGLES / 1500000)
  assert.deepEqual(result.plan.options, {
    externalLengthMm: 270,
    authoredSizeEu: 42,
    // Null on purpose: which end of the long axis is the toe is the one thing
    // the normalizer's own header says the bytes cannot answer, so it stays a
    // reviewer row (§5.2) and the change log states the assumption.
    toe: null,
    materialRenames: {},
    soleBandMm: 12,
  })
})

test('the refusal names the parts and the way out', () => {
  const result = planCompression({
    bytes: buildGlb(shoeJson({ materials: [{ name: 'Material.001' }, { name: 'Material.002' }] })),
    declaredLengthMm: 270,
  })

  assert.equal(result.ok, false)
  assert.equal(result.reason, 'materials')
  // Both names, so the admin can see what the file actually says...
  assert.match(result.message, /Material\.001/)
  assert.match(result.message, /Material\.002/)
  // ...the approved set, so they know what to rename to...
  assert.match(result.message, /upper/)
  // ...and the CLI, because a refusal with no route out is a dead end.
  assert.match(result.message, /prepare_shoe_model\.dart/)
  assert.match(result.message, /--material/)
})

// ─── The copy ──────────────────────────────────────────────────────

test('sizes are written the way the rest of the portal writes them', () => {
  assert.equal(formatBytes(0), '0 B')
  assert.equal(formatBytes(900), '900 B')
  assert.equal(formatBytes(2048), '2.0 KB')
  assert.equal(formatBytes(2360084), '2.3 MB')
  assert.equal(formatBytes(94466532), '90.1 MB')
  assert.equal(formatBytes(null), '—')
})

test('the summary leads with the two sizes and ends by saying what it is not', () => {
  const summary = compressionSummary({
    beforeBytes: 94466532,
    afterBytes: 2360084,
    triangleCount: 1500000,
    triangleCountAfter: 40500,
  })

  assert.match(summary, /90\.1 MB → 2\.3 MB/)
  assert.match(summary, /1,500,000 → 40,500 triangles/)
  // ⚠️ The sentence that must not be dropped: a green run is not acceptance.
  assert.match(summary, /not judged yet/)
  assert.match(summary, /guide §5\.2/)
})

test('a summary without a post-decimation count does not invent one', () => {
  const summary = compressionSummary({ beforeBytes: 1024, afterBytes: 512, triangleCount: 300 })
  assert.match(summary, /300 triangles/)
  assert.doesNotMatch(summary, /→ 300/)
})

test('a browser out of memory is told the way out, not the exception', () => {
  // The one failure this surface adds that the CLI has never had: the tab is
  // the runtime, and it can simply run out.
  const message = compressFailureMessage(new Error('Array buffer allocation failed'))
  assert.match(message, /ran out of memory/)
  assert.match(message, /Close some tabs/)
  assert.match(message, /prepare_shoe_model\.dart/)

  // The normalizer's own refusals are written to be forwarded to whoever sent
  // the file, so they pass through untouched.
  const refusal = new Error('KHR_draco_mesh_compression cannot be undone offline — re-export')
  assert.equal(compressFailureMessage(refusal), refusal.message)

  assert.match(compressFailureMessage(null), /stopped without saying why/)
})
