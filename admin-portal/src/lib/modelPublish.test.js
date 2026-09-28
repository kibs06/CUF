import { test } from 'node:test'
import assert from 'node:assert/strict'

import {
  BUCKET_CAP_BYTES,
  DECLARATION_FIELD,
  MODELLING_ENDING,
  SERVER_OUTCOME,
  declaredLengthAgreement,
  downloadFailureMessage,
  failedChecks,
  looksLikeGlb,
  modelRow,
  modellingPrefill,
  modellingResult,
  nextVersion,
  readDeclaration,
  reuseMatch,
  rowId,
  serverVerdict,
  sha256Hex,
  sourceUrlAllowed,
  statusAfterVerdict,
  storagePath,
  verdictMessage,
} from './modelPublish.js'

// These rules are ports of Dart (`lib/utils/shoe_model_upload.dart` and
// `lib/utils/shoe_model_request.dart`) — see the module header. The tests exist
// because a port is exactly the kind of code that looks right in review: the
// sentences below are the ones an admin reads on BOTH surfaces, so a drift here
// would tell two people two different things about the same mistake.

// ─── The declaration ───────────────────────────────────────────────

test('a centimetre figure is answered with a message about units', () => {
  // The single most likely typo in this feature: somebody with a tape writes 27.
  // "100–400 mm is plausible" would send them hunting for a different number
  // instead of a different unit, so the sentence names the unit.
  const short = readDeclaration({ externalLengthMm: '27', authoredSizeEu: '' })

  assert.equal(short.externalLengthMm, null)
  assert.match(short.error, /millimetres, not centimetres/i)
  assert.match(short.error, /27 looks like 270 mm/)
  assert.equal(short.errorField, DECLARATION_FIELD.EXTERNAL_LENGTH_MM)

  const right = readDeclaration({ externalLengthMm: '270', authoredSizeEu: '' })
  assert.equal(right.error, null)
  assert.equal(right.externalLengthMm, 270)
})

test('a size without a length is refused, and blamed on the length', () => {
  // The one shape refused outright: the server's scale check needs the length,
  // and an authored size on its own is not a declaration.
  const declaration = readDeclaration({ externalLengthMm: '', authoredSizeEu: '42' })

  assert.equal(declaration.authoredSizeEu, null)
  assert.match(declaration.error, /Add the declared external length/)
  assert.equal(declaration.errorField, DECLARATION_FIELD.EXTERNAL_LENGTH_MM)
})

test('the size is checked first, so a mistyped size is not reported as a missing length', () => {
  const declaration = readDeclaration({ externalLengthMm: '', authoredSizeEu: '9.5' })

  assert.equal(declaration.errorField, DECLARATION_FIELD.AUTHORED_SIZE_EU)
  assert.match(declaration.error, /between 22 and 48/)
})

test('a US or UK number is refused by name', () => {
  // The same trap the fit form refuses: a US 9.5 is a plausible number and the
  // wrong size.
  for (const text of ['US 9', 'UK 8', '9.5 cm']) {
    const declaration = readDeclaration({ externalLengthMm: '270', authoredSizeEu: text })
    assert.equal(declaration.errorField, DECLARATION_FIELD.AUTHORED_SIZE_EU, text)
    assert.match(declaration.error, /EU size/)
  }
})

test('two blank fields are not an error', () => {
  // The length is required to publish, but a blank field is "not filled in yet",
  // not a mistake — and an error here would fire on first render.
  const declaration = readDeclaration({ externalLengthMm: '', authoredSizeEu: '' })

  assert.equal(declaration.error, null)
  assert.equal(declaration.externalLengthMm, null)
  assert.equal(declaration.authoredSizeEu, null)
})

test('the prefill fills the length, unlike the seller-side form', () => {
  // ⚠️ Deliberately the opposite of `shoeModelRequestPrefill`, which leaves the
  // length blank because the only number it had was the INTERNAL last. Here the
  // number is the seller's own external measurement — the figure the mesh is
  // scaled to — so retyping it would only add a way to mistype it.
  const prefill = modellingPrefill({ externalLengthMm: 272, measuredSizeEu: 42 })

  assert.deepEqual(prefill, { externalLengthMm: '272', authoredSizeEu: '42' })
  // 272, not 272.0 — a prefilled field and a typed one must read the same.
  assert.equal(modellingPrefill({ externalLengthMm: 272.0, measuredSizeEu: null }).externalLengthMm, '272')
  assert.equal(modellingPrefill({ externalLengthMm: null, measuredSizeEu: null }).externalLengthMm, '')
})

// ─── The ±5 mm agreement: a note, never a gate ─────────────────────

test('inside the tolerance there is nothing to say, at the boundary included', () => {
  assert.equal(declaredLengthAgreement({ measuredMm: 272, declaredMm: 272 }).message, null)
  assert.equal(declaredLengthAgreement({ measuredMm: 272, declaredMm: 277 }).message, null)
  assert.equal(declaredLengthAgreement({ measuredMm: 272, declaredMm: 267 }).message, null)
})

test('outside it, the note names both numbers and which way it is wrong', () => {
  const note = declaredLengthAgreement({ measuredMm: 272, declaredMm: 278 })

  assert.equal(note.disagrees, true)
  assert.match(note.message, /declared 278 mm/)
  assert.match(note.message, /measured 272 mm/)
  assert.match(note.message, /6 mm longer/)
  // Its reason for existing, in the sentence: the declared figure wins.
  assert.match(note.message, /scales every size to the declared figure/)

  assert.match(
    declaredLengthAgreement({ measuredMm: 272, declaredMm: 260 }).message,
    /12 mm shorter/,
  )
})

test('a request with no measurement gets no note rather than a false one', () => {
  assert.equal(declaredLengthAgreement({ measuredMm: null, declaredMm: 270 }).disagrees, false)
  assert.equal(declaredLengthAgreement({ measuredMm: 270, declaredMm: null }).disagrees, false)
})

// ─── The three endings ─────────────────────────────────────────────

test('the three endings are all reachable and each says something different', () => {
  const closed = modellingResult({ modelIsLive: true, fulfilled: true, modelId: 7 })
  assert.equal(closed.ending, MODELLING_ENDING.CLOSED)
  assert.match(closed.message, /Published and closed/)
  assert.equal(closed.modelId, 7)

  // ⚠️ The ending worth having a name for: customers can render the pair, and the
  // seller's row still says somebody is working on it. Not a failure, not a
  // success, and it must not be reported as either.
  const liveButOpen = modellingResult({ modelIsLive: true, fulfilled: false, modelId: 7 })
  assert.equal(liveButOpen.ending, MODELLING_ENDING.LIVE_BUT_OPEN)
  assert.match(liveButOpen.message, /model is live on the product, but the request could not be closed/)
  assert.match(liveButOpen.message, /Close it as done from the queue/)

  const notLive = modellingResult({ modelIsLive: false, fulfilled: false, refusal: 'refused (scale)' })
  assert.equal(notLive.ending, MODELLING_ENDING.NOT_LIVE)
  assert.match(notLive.message, /still waiting/)
  // The server's own sentence travels: "refused: materials, scale" is actionable
  // and "it did not work" is not.
  assert.match(notLive.message, /refused \(scale\)/)

  const noDetail = modellingResult({ modelIsLive: false, fulfilled: false })
  assert.match(noDetail.message, /did not accept the file, so it stays hidden/)
})

// ─── The source of the bytes ───────────────────────────────────────

test('only https is fetched, with loopback as the one exception', () => {
  assert.equal(sourceUrlAllowed('https://cdn.example.com/pair.glb'), true)
  assert.equal(sourceUrlAllowed('  https://cdn.example.com/pair.glb  '), true)
  assert.equal(sourceUrlAllowed('http://localhost:8000/pair.glb'), true)
  assert.equal(sourceUrlAllowed('http://127.0.0.1/pair.glb'), true)
  // Cleartext from a real host is a supply-chain hole, not a convenience: the
  // bytes become what customers see on their feet.
  assert.equal(sourceUrlAllowed('http://cdn.example.com/pair.glb'), false)
  assert.equal(sourceUrlAllowed('file:///C:/pair.glb'), false)
  assert.equal(sourceUrlAllowed('not a url'), false)
  assert.equal(sourceUrlAllowed(''), false)
})

test('a browser that is not allowed to read the link is told the way out', () => {
  // The failure this surface adds and the app has never had: a phone downloads
  // any link it can reach, a browser is refused by the page rules first.
  const cors = downloadFailureMessage({ cors: true })
  assert.match(cors, /not allowed to read that link/)
  assert.match(cors, /choose a \.glb file/)
  // Never "could not reach", which would send somebody to check a working link.
  assert.doesNotMatch(cors, /Could not reach/)

  assert.match(downloadFailureMessage({ status: 404 }), /404/)
  assert.match(downloadFailureMessage({ status: 403 }), /private/)
  assert.match(downloadFailureMessage({ status: 500 }), /HTTP 500/)
  assert.match(downloadFailureMessage({}), /Could not reach that link/)
})

test('a wrong file is caught by its header, before 3 MB goes anywhere', () => {
  const glb = new Uint8Array([0x67, 0x6c, 0x54, 0x46, 0x02, 0, 0, 0, 12, 0, 0, 0])
  assert.equal(looksLikeGlb(glb), true)
  // Version 1, or a PNG — the header says so in a second instead of after an
  // upload that the server would refuse.
  assert.equal(looksLikeGlb(new Uint8Array([0x67, 0x6c, 0x54, 0x46, 0x01, 0, 0, 0, 12, 0, 0, 0])), false)
  assert.equal(looksLikeGlb(new Uint8Array([0x89, 0x50, 0x4e, 0x47])), false)
  assert.equal(looksLikeGlb(new Uint8Array(0)), false)
})

// ─── The row, the version, the reuse ───────────────────────────────

test('the row is always a draft, and no argument can ask for another status', () => {
  // ⚠️ The database refuses `active` from any role but the service role, and
  // before that trigger existed asking for it would have been worse than
  // failing: it would have succeeded and published an unjudged model.
  const row = modelRow({
    productId: 'p1',
    storagePath: 'store/p1/abc.glb',
    sha256: 'ABC'.repeat(20) + '1234',
    version: 2,
    authoredLengthMm: 272,
  })

  assert.equal(row.status, 'draft')
  assert.equal(row.variant_id, null)
  assert.equal(row.sha256, ('abc'.repeat(20) + '1234').toLowerCase())
  assert.equal(row.authored_length_mm, 272)

  // Passing a status in must not leak through — the function has no such field,
  // and this is the test that keeps it that way.
  const forced = modelRow({
    productId: 'p1',
    storagePath: 'x',
    sha256: 'ab'.repeat(32),
    version: 1,
    status: 'active',
  })
  assert.equal(forced.status, 'draft')
})

test('the version counts the default target only, and starts at 1', () => {
  assert.equal(nextVersion([]), 1)
  assert.equal(nextVersion([{ version: 1 }, { version: 3 }, { version: 2 }]), 4)
  // A variant row is a different target: its version must not bump the
  // product-level one, which is what the partial unique indexes encode.
  assert.equal(nextVersion([{ version: 9, variant_id: 'v1' }]), 1)
})

test('the same bytes for the same target are reused, not re-versioned', () => {
  const digest = 'ab'.repeat(32)
  const rows = [
    { id: 4, sha256: digest.toUpperCase(), version: 1, variant_id: null, status: 'active' },
    { id: 9, sha256: digest, version: 7, variant_id: 'other-variant' },
  ]

  const match = reuseMatch(rows, digest)
  assert.equal(match.id, 4)
  assert.equal(reuseMatch(rows, 'cd'.repeat(32)), null)
  // A row for another variant is not a reuse: the object would be shared, the
  // target would not.
  assert.equal(reuseMatch([{ id: 9, sha256: digest, variant_id: 'other' }], digest), null)
})

test('a bigint id is read whether it arrives as a number or a string', () => {
  assert.equal(rowId(12), 12)
  assert.equal(rowId('12'), 12)
  assert.equal(rowId(' 12 '), 12)
  assert.equal(rowId(12.0), 12)
  assert.equal(rowId(null), null)
  assert.equal(rowId(''), null)
  assert.equal(rowId('not-an-id'), null)
  assert.equal(rowId(undefined), null)
})

test('the storage path is <store>/<product>/<sha>.glb, and the segment is trimmed', () => {
  // The seller-write policy reads the FIRST segment as a store the caller owns,
  // so the order is not cosmetic.
  assert.equal(
    storagePath({ storeId: ' s1 ', productId: 'p1', sha256: 'deadbeef' }),
    's1/p1/deadbeef.glb',
  )
})

// ─── The server's verdict ──────────────────────────────────────────

test('422 with failing rows names them', () => {
  const verdict = serverVerdict({
    statusCode: 422,
    body: { ok: false, status: 'rejected', report: { checks: [
      { name: 'materials', status: 'fail' },
      { name: 'scale', status: 'fail' },
      { name: 'size budget', status: 'pass' },
    ] } },
  })

  assert.equal(verdict.outcome, SERVER_OUTCOME.REJECTED)
  assert.deepEqual(verdict.failedChecks, ['materials', 'scale'])
  assert.match(verdictMessage(verdict), /refused it \(materials, scale\)/)
  assert.equal(statusAfterVerdict(verdict), 'rejected')
})

test('422 counts as a judgement even when the body is lost in transit', () => {
  // ⚠️ The status code is the function's own refusal signal, and the gateway
  // returns 401/403/404/502 — so an unparseable 422 is still a verdict.
  // Degrading it to "no verdict" would leave a refused model in drafts with
  // nobody told why.
  const html = serverVerdict({ statusCode: 422, body: '<html>502 Bad Gateway</html>' })
  assert.equal(html.outcome, SERVER_OUTCOME.REJECTED)
  assert.match(verdictMessage(html), /without naming a failing row/)

  const stringy = serverVerdict({
    statusCode: 422,
    body: JSON.stringify({ ok: false, report: { checks: [{ name: 'scale', status: 'fail' }] } }),
  })
  assert.deepEqual(stringy.failedChecks, ['scale'])
})

test('the server-only integrity check is named first when it fails', () => {
  // No client can perform this one: the bytes in the bucket must hash to the
  // digest the row records. A modeller debugging "it passed locally" needs it.
  const verdict = serverVerdict({
    statusCode: 422,
    body: {
      ok: false,
      report: { checks: [{ name: 'scale', status: 'fail' }] },
      integrity: { sha256: { matches: false } },
    },
  })

  assert.deepEqual(verdict.failedChecks, [
    'sha256 (the stored bytes do not match the row)',
    'scale',
  ])
})

test('200 is only success when the body says so', () => {
  const ok = serverVerdict({ statusCode: 200, body: { ok: true, status: 'active' } })
  assert.equal(ok.outcome, SERVER_OUTCOME.VALIDATED)
  assert.equal(verdictMessage(ok), null)
  assert.equal(statusAfterVerdict(ok), 'active')

  // A 200 whose body says otherwise is not a pass. The app's rule for the RPCs
  // is the same one (a missing body is not success), and it applies here too.
  const empty = serverVerdict({ statusCode: 200, body: null })
  assert.equal(empty.outcome, SERVER_OUTCOME.UNDETERMINED)
  assert.equal(statusAfterVerdict(empty), 'draft')
})

test('anything else is "no verdict", and the row keeps its status', () => {
  const gateway = serverVerdict({ statusCode: 502, body: null })
  assert.equal(gateway.outcome, SERVER_OUTCOME.UNDETERMINED)
  assert.equal(gateway.detail, 'HTTP 502')
  assert.match(verdictMessage(gateway), /could not check it \(HTTP 502\)/)

  const busy = serverVerdict({ statusCode: 429, body: { error: 'rate limited' } })
  assert.equal(busy.detail, 'rate limited')

  // A 500 is not a refusal: nothing judged the file, so nothing about the row
  // may change — the difference between this and a rejection is the whole point.
  assert.equal(statusAfterVerdict(serverVerdict({ statusCode: 500, body: null })), 'draft')
})

test('failing rows are read out of either wrapper shape', () => {
  assert.deepEqual(failedChecks([{ name: 'a', status: 'fail' }]), ['a'])
  assert.deepEqual(failedChecks({ checks: [{ name: 'b', status: 'fail' }] }), ['b'])
  assert.deepEqual(failedChecks({ checks: [{ name: 'c', status: 'pass' }] }), [])
  assert.deepEqual(failedChecks(null), [])
  assert.deepEqual(failedChecks([{ status: 'fail' }]), [])
})

// ─── The digest ────────────────────────────────────────────────────

test('the digest is the same lowercase hex the app computes', async () => {
  // One number, three jobs: the storage filename, the cache key and the
  // integrity check `product_models.sha256` CHECKs against `^[0-9a-f]{64}$`.
  const digest = await sha256Hex(new TextEncoder().encode('abc'))
  assert.equal(
    digest,
    'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
  )
  assert.match(digest, /^[0-9a-f]{64}$/)
})

test('the bucket cap is the one the bucket declares', () => {
  assert.equal(BUCKET_CAP_BYTES, 8388608)
})
