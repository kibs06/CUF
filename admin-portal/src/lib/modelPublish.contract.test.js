import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'

import {
  AUTHORED_SIZE_MAX_EU,
  AUTHORED_SIZE_MIN_EU,
  BUCKET_CAP_BYTES,
  MODEL_CONTENT_TYPE,
  PLAUSIBLE_LENGTH_MAX_MM,
  PLAUSIBLE_LENGTH_MIN_MM,
} from './modelPublish.js'

// ─── The numbers this portal refuses with, read out of the SQL ─────
//
// The same class of guard the Flutter side puts beside its pure rules: instead
// of keeping a second copy of a rule and hoping the two stay equal, read the
// rule out of the migration that owns it and assert against that.
//
// It matters more here than usual, because every one of these numbers produces a
// *refusal sentence* rather than a crash. A band that drifted would tell a
// modeller their plausible 105 mm length is a typo — or accept a 420 mm one and
// let the database refuse the insert with a constraint name they cannot act on.
//
// `20260927180000_add_try_on_models.sql` is the file that owns all of it: the
// `product_models` columns and the `shoe-models` bucket.

const migration = readFileSync(
  new URL('../../../supabase/migrations/20260927180000_add_try_on_models.sql', import.meta.url),
  'utf8',
)

/** The two numbers out of a `BETWEEN a AND b` inside one column's CHECK. */
function bandFor(column) {
  const line = migration
    .split('\n')
    .find((candidate) => candidate.trimStart().startsWith(`${column} `))
  assert.ok(line, `${column} is no longer declared in the migration — repoint this guard`)

  const band = /BETWEEN (\d+) AND (\d+)/.exec(line)
  assert.ok(band, `${column}'s CHECK no longer has a BETWEEN band: ${line.trim()}`)
  return { min: Number(band[1]), max: Number(band[2]) }
}

test('the declared-length band is the column CHECK, not a second opinion', () => {
  const band = bandFor('authored_length_mm')
  assert.equal(PLAUSIBLE_LENGTH_MIN_MM, band.min)
  assert.equal(PLAUSIBLE_LENGTH_MAX_MM, band.max)
})

test('the EU size band is the column CHECK too', () => {
  const band = bandFor('authored_size_eu')
  assert.equal(AUTHORED_SIZE_MIN_EU, band.min)
  assert.equal(AUTHORED_SIZE_MAX_EU, band.max)
})

test('the size cap is the bucket’s own limit, and the MIME type is the one it admits', () => {
  const bucket = /'shoe-models',\s*\n\s*'shoe-models',\s*\n\s*(?:true|false),\s*\n\s*(\d+)/.exec(
    migration,
  )
  assert.ok(bucket, 'the shoe-models bucket block moved — repoint this guard')
  assert.equal(BUCKET_CAP_BYTES, Number(bucket[1]))

  // A `.glb` uploaded as `application/octet-stream` is refused by storage with an
  // opaque error, which is why the content type is set explicitly — so the value
  // this portal sends has to be one the bucket's allowlist names.
  //
  // Read the array belonging to the buckets INSERT rather than the first
  // `ARRAY[…]` in the file: this migration has exactly one today, but an
  // unrelated one added above it must not silently turn this guard into a test
  // of the wrong array.
  const bucketBlock = /INSERT INTO storage\.buckets[\s\S]*?;/.exec(migration)?.[0]
  assert.ok(bucketBlock, 'the storage.buckets INSERT moved — repoint this guard')
  const allowlist = /ARRAY\[([^\]]*)\]/.exec(bucketBlock)
  assert.ok(allowlist?.[1], 'the bucket no longer declares an allowed_mime_types array')
  assert.ok(
    allowlist[1].includes(MODEL_CONTENT_TYPE),
    `the bucket admits ${allowlist[1]}, which does not include ${MODEL_CONTENT_TYPE}`,
  )
})

test('draft is one of the three statuses the column admits, and the only one we write', () => {
  const statusLine = migration
    .split('\n')
    .find((line) => line.trimStart().startsWith('status '))
  assert.ok(statusLine, 'the status column moved — repoint this guard')
  assert.match(statusLine, /CHECK \(status IN \('draft', 'active', 'rejected'\)\)/)
  // The portal writes exactly one of the three, and it is the hidden one: only
  // `validate-shoe-model` may write `active` (V2.4), which is why a publish that
  // skipped the server would fail rather than quietly go live.
  assert.match(statusLine, /'draft'/)
})
