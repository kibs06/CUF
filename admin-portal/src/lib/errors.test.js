import { test } from 'node:test'
import assert from 'node:assert/strict'

import {
  PORTAL_ERROR,
  PortalError,
  classifyError,
  describeError,
  toPortalError,
} from './errors.js'

// The portal's first test, and it exists because the classification is a RULE
// rather than a guess: three of the cases below are conditions this project has
// actually shipped, and each one has a different correct answer.
//
// Run with `npm test` (Node's own runner — no framework, no new dependency).

test('42501 is the admin refusal, and it is not a stale session', () => {
  // What `claim_shoe_model_request` raises now that its guard carries an
  // ERRCODE. Before that it was P0001, which is indistinguishable from a bug.
  const error = { code: '42501', message: 'Only admins can claim model requests' }

  assert.equal(classifyError(error), PORTAL_ERROR.NOT_ADMIN)
  assert.match(describeError(error).message, /not an admin/i)
})

test('an expired session is not an admin refusal', () => {
  // Same blank result, opposite fix: one is "sign in again", the other is
  // "your account is not an admin's". Confusing them sends an admin to the
  // wrong place, which is the whole reason these are separate kinds.
  for (const error of [
    { code: 'PGRST301', message: 'JWT expired' },
    { status: 401, message: 'Unauthorized' },
    // No code at all — the auth service sometimes sends only text.
    new Error('Token has expired'),
  ]) {
    assert.equal(classifyError(error), PORTAL_ERROR.SESSION_EXPIRED, error.message)
  }
  assert.notEqual(classifyError({ code: '42501' }), PORTAL_ERROR.SESSION_EXPIRED)
})

test('42804 reads as "the database is behind this build"', () => {
  // This exact code is why the kind exists: `v_live` was declared uuid over a
  // bigint column, and the app could not have fixed it by retrying.
  const error = {
    code: '42804',
    message: 'column "v_live" is of type uuid but expression is of type bigint',
  }

  assert.equal(classifyError(error), PORTAL_ERROR.DB_BEHIND_CODE)
  assert.match(describeError(error).message, /apply the latest migration/i)
})

test('a function that is not there yet is the same kind as a type mismatch', () => {
  for (const code of ['42883', '42P01', 'PGRST202', 'PGRST205']) {
    assert.equal(classifyError({ code, message: 'nope' }), PORTAL_ERROR.DB_BEHIND_CODE, code)
  }
})

test('a renamed relationship is drift, not a stale database', () => {
  // The queue's embed names its foreign keys, so a rename arrives as PGRST200.
  // Reporting that as "apply the migration" would be half right and would send
  // somebody to the wrong fix: the migration landed, the page did not follow.
  const error = {
    code: 'PGRST200',
    message:
      "Could not find a relationship between 'shoe_model_requests' and 'products' in the schema cache",
  }

  assert.equal(classifyError(error), PORTAL_ERROR.SCHEMA_DRIFT)
  assert.notEqual(classifyError(error), PORTAL_ERROR.DB_BEHIND_CODE)
})

test('a business refusal with no code keeps its own sentence', () => {
  // The RPCs say "already been claimed" by RETURNING a message, and that
  // message is the only correct thing to show. A generic fallback here would
  // throw away the sentence the database wrote for exactly this case.
  const error = new Error('Request not found, or somebody has already taken it.')
  const described = describeError(error, 'Could not claim that request.')

  assert.equal(described.kind, PORTAL_ERROR.UNKNOWN)
  assert.equal(described.message, 'Request not found, or somebody has already taken it.')
  assert.equal(described.detail, described.message)
})

test('the fallback is only for an error that said nothing', () => {
  assert.equal(describeError(null, 'Could not load the queue.').message, 'Could not load the queue.')
  assert.equal(describeError(new Error(''), 'Could not load the queue.').message, 'Could not load the queue.')
  assert.equal(
    describeError({ code: '23505', message: 'duplicate key value' }).message,
    'duplicate key value',
  )
})

test('a network failure says nothing was sent', () => {
  assert.equal(classifyError(new TypeError('Failed to fetch')), PORTAL_ERROR.OFFLINE)
  assert.equal(classifyError('Load failed'), PORTAL_ERROR.OFFLINE)
  assert.match(describeError(new TypeError('Failed to fetch')).message, /nothing was sent/i)
})

test('the server’s own words survive into the detail', () => {
  const error = { code: '42501', message: 'Only admins can decline model requests' }
  const described = describeError(error)

  assert.equal(described.code, '42501')
  assert.equal(described.detail, 'Only admins can decline model requests')
  // The sentence and the raw text are different strings, which is what tells
  // the page it has something extra worth printing.
  assert.notEqual(described.message, described.detail)
})

test('wrapping preserves the code without re-classifying', () => {
  const raw = { code: '42804', message: 'column "v_live" is of type uuid' }
  const wrapped = toPortalError(raw, 'Could not close that request.')

  assert.ok(wrapped instanceof PortalError)
  assert.ok(wrapped instanceof Error)
  assert.equal(wrapped.kind, PORTAL_ERROR.DB_BEHIND_CODE)
  assert.equal(wrapped.code, '42804')
  assert.equal(wrapped.cause, raw)
  // Idempotent: a hook may wrap at its own boundary without knowing whether
  // it was handed a raw PostgREST error or one already wrapped upstream.
  assert.equal(toPortalError(wrapped, 'ignored'), wrapped)
})

test('the kinds do not share a sentence', () => {
  // Non-vacuity. If two kinds resolved to the same sentence, the classification
  // would cost a network round trip of thinking and tell the admin nothing —
  // which is exactly the bug being fixed.
  // `kind` is what `describeError` reads off a PortalError, so the sentence for
  // each kind is reachable without inventing a server error per kind.
  const sentenceFor = (kind) =>
    describeError(new PortalError({ kind, message: 'the server said something' })).message

  const kinds = Object.values(PORTAL_ERROR)
  const sentences = kinds.map(sentenceFor)

  assert.equal(kinds.length, 6)
  assert.equal(new Set(sentences).size, sentences.length)

  for (const kind of kinds.filter((k) => k !== PORTAL_ERROR.UNKNOWN)) {
    assert.ok(
      sentenceFor(kind).length > 20,
      `${kind} needs a sentence of its own — the admin reads that instead of a stack trace`,
    )
  }

  // `unknown` is the one kind with no sentence of its own, on purpose: it hands
  // over the server's text, which is why a business refusal keeps its wording.
  assert.equal(sentenceFor(PORTAL_ERROR.UNKNOWN), 'the server said something')
})
