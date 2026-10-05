import { test } from 'node:test'
import assert from 'node:assert/strict'
import { createHash } from 'node:crypto'
import { readFileSync } from 'node:fs'

import {
  APPROVED_PART_NAMES,
  FILE_SIZE_BUDGET_BYTES,
  MAX_TRIANGLES,
} from './modelCompress.js'

// ─── The two things that can silently drift apart ──────────────────
//
// The compress step rests on two files it does not own:
//
//   1. **a generated artifact** — `glb_normalizer.gen.js`, compiled from the
//      Dart reference normalizer. If somebody changes the Dart and forgets to
//      rebuild, the portal keeps compressing with yesterday's rules and nothing
//      anywhere says so. That is the failure this file exists for: it compares
//      the digest stamped into the artifact against the digest of the Dart
//      sources *right now*, and the message is the command to fix it.
//
//   2. **three numbers owned by the contract** — the file budget, the triangle
//      cap and the approved part names. They live in
//      `supabase/functions/_shared/glb_validator.ts`, which is the mirror the
//      server actually runs, so they are read from there rather than kept as a
//      second copy that hopes to stay equal. This is the same class of guard
//      `modelPublish.contract.test.js` puts on the migration: a rule is read
//      out of the file that owns it and asserted against the value this code
//      refuses with.
//
// Neither guard reads the artifact's *behaviour* — that is what the end-to-end
// run does. These are cheap, run on every `npm test`, and fail loudly at the
// moment drift is introduced rather than at the moment a model is refused.

const repoRoot = new URL('../../../', import.meta.url)

/** The same list, and the same order, as the build script. */
const SOURCES = ['tool/shoe_model_normalizer_web.dart', 'lib/utils/glb_normalizer.dart']

function readRepoFile(relative) {
  return readFileSync(new URL(relative, repoRoot))
}

test('the compiled normalizer matches the Dart it was built from', () => {
  const artifact = readFileSync(new URL('./glb_normalizer.gen.js', import.meta.url), 'utf8')

  const stamp = /^\/\/ dart-source-sha256: ([0-9a-f]{64})$/m.exec(artifact)
  assert.ok(
    stamp,
    'glb_normalizer.gen.js has no source stamp — it is not the output of ' +
      '`node tool/build_shoe_model_normalizer_web.mjs`. Rebuild it.',
  )

  const hash = createHash('sha256')
  for (const relative of SOURCES) {
    hash.update(`${relative}\n`)
    hash.update(readRepoFile(relative))
  }
  const current = hash.digest('hex')

  assert.equal(
    stamp[1],
    current,
    'the Dart normalizer has changed since glb_normalizer.gen.js was built, so the portal ' +
      'would compress with rules the CLI no longer agrees with. Run:\n' +
      '  node tool/build_shoe_model_normalizer_web.mjs\n' +
      'and commit the result.',
  )
})

test('the artifact exports the one function the worker calls', () => {
  // A rebuild that silently dropped the export would fail at runtime, in a
  // worker, with an unhelpful message. This is the cheap place to catch it.
  const artifact = readFileSync(new URL('./glb_normalizer.gen.js', import.meta.url), 'utf8')
  assert.match(artifact, /export const soleVisionNormalize = globalThis\.soleVisionNormalize/)
})

test('the artifact carries no source map comment pointing at a file nobody ships', () => {
  // A missing `.map` is a 404 in every devtools session, and the file is
  // 512 KB of compiled Dart — the map is not the thing to ship.
  const artifact = readFileSync(new URL('./glb_normalizer.gen.js', import.meta.url), 'utf8')
  assert.doesNotMatch(artifact, /^\/\/# sourceMappingURL=/m)
})

// ─── The numbers the contract owns ─────────────────────────────────

const validator = readFileSync(
  new URL('../../../supabase/functions/_shared/glb_validator.ts', import.meta.url),
  'utf8',
)

test('the file budget is the validator’s own number', () => {
  // The number the "Compress it" offer appears above. If the server's budget
  // moved, this portal would either offer compression to files that do not need
  // it or stay silent about files that will be refused.
  const match = /export const FILE_SIZE_BUDGET_BYTES = ([^;]+);/.exec(validator)
  assert.ok(match, 'FILE_SIZE_BUDGET_BYTES moved in glb_validator.ts — repoint this guard')
  assert.equal(FILE_SIZE_BUDGET_BYTES, eval(match[1]))
})

test('the triangle cap is the validator’s own number', () => {
  const match = /export const MAX_TRIANGLES = ([^;]+);/.exec(validator)
  assert.ok(match, 'MAX_TRIANGLES moved in glb_validator.ts — repoint this guard')
  assert.equal(MAX_TRIANGLES, eval(match[1]))
})

test('the approved part names are the validator’s own list, in its own order', () => {
  // Order matters for one thing: the refusal sentence lists the set in this
  // order, and the same sentence should read the same wherever it appears.
  const match = /export const APPROVED_PART_NAMES = \[([\s\S]*?)\];/.exec(validator)
  assert.ok(match, 'APPROVED_PART_NAMES moved in glb_validator.ts — repoint this guard')
  const names = [...match[1].matchAll(/"([^"]+)"/g)].map((entry) => entry[1])
  assert.deepEqual(APPROVED_PART_NAMES, names)
})

test('the two required parts are still a subset of the approved ones', () => {
  // The sole-band cut only ever writes `upper` and `sole`; if the contract ever
  // stopped approving one of them the cut would produce a refused file.
  const match = /export const REQUIRED_PART_NAMES = \[([\s\S]*?)\];/.exec(validator)
  assert.ok(match, 'REQUIRED_PART_NAMES moved in glb_validator.ts — repoint this guard')
  const required = [...match[1].matchAll(/"([^"]+)"/g)].map((entry) => entry[1])
  for (const name of required) {
    assert.ok(APPROVED_PART_NAMES.includes(name), `${name} is required but not approved`)
  }
})
