import test from 'node:test'
import assert from 'node:assert/strict'

import {
  DELETION_CONSEQUENCE,
  deletionResult,
  emailChangeError,
  emailChangeErrors,
  emailChangeSentMessage,
  emailError,
  isSameEmail,
} from './securityRules.js'

test('an email is judged by shape, not by cleverness', () => {
  assert.equal(emailError('shaine@gmail.com'), null)
  assert.equal(emailError('  shaine@gmail.com  '), null)
  // A plus tag and a subdomain are ordinary addresses, not errors.
  assert.equal(emailError('shaine+cufmai@mail.example.com.ph'), null)

  assert.match(emailError(''), /enter the new email/i)
  assert.match(emailError('   '), /enter the new email/i)
  assert.match(emailError('shaine'), /valid email/i)
  assert.match(emailError('shaine@'), /valid email/i)
  assert.match(emailError('shaine@gmail'), /valid email/i)
  assert.match(emailError('@gmail.com'), /valid email/i)
  assert.match(emailError('two words@gmail.com'), /valid email/i)
})

test('the current address is caught before GoTrue is asked', () => {
  assert.equal(isSameEmail('A@Gmail.com', 'a@gmail.com'), true)
  assert.equal(isSameEmail('a@gmail.com', 'b@gmail.com'), false)
  // No current address (a session without an email) is not a match.
  assert.equal(isSameEmail(null, ''), false)

  assert.deepEqual(emailChangeErrors({ next: 'a@gmail.com', current: 'a@gmail.com' }), {
    email: 'That is the address you are already signed in with',
  })
  assert.deepEqual(emailChangeErrors({ next: 'b@gmail.com', current: 'a@gmail.com' }), {})
  // A malformed address reports its own problem rather than the "same" one.
  assert.match(
    emailChangeErrors({ next: 'b', current: 'a@gmail.com' }).email,
    /valid email/i,
  )
})

test('rate limiting is explained, not blamed', () => {
  // The first click worked; this is the second. Saying "too many requests"
  // sends the customer to check a setting that does not exist.
  assert.match(
    emailChangeError({ status: 429, message: 'For security purposes...' }),
    /already sent a confirmation/i,
  )
  assert.match(
    emailChangeError({ message: 'Email rate limit exceeded' }),
    /already sent a confirmation/i,
  )
})

test('an address that is already an account says what to do instead', () => {
  assert.match(
    emailChangeError({ message: 'A user with this email address has already been registered' }),
    /sign in with it instead/i,
  )
  assert.match(emailChangeError({ code: 'email_exists' }), /already has a CUFMAI account/i)
})

test('an expired session and a garbage failure both get sentences', () => {
  assert.match(emailChangeError({ message: 'Not authenticated' }), /sign in again/i)
  assert.match(emailChangeError({}), /try again in a moment/i)
  assert.match(emailChangeError(null), /try again in a moment/i)
})

test('the confirmation says TWO emails arrive and that nothing has changed yet', () => {
  const message = emailChangeSentMessage('new@gmail.com')
  assert.match(message, /new@gmail\.com/)
  assert.match(message, /keep signing in with your current address/i)
})

test('the deletion consequence names what goes with the account', () => {
  for (const line of [
    'Orders and purchase history',
    'Saved delivery addresses',
    'Your foot size and scan data',
    'Profile information and your photo',
  ]) {
    assert.ok(DELETION_CONSEQUENCE.includes(line), `missing: ${line}`)
  }
  assert.match(DELETION_CONSEQUENCE, /within 48 hours/i)
})

test('a pending request is reported as the success it is', () => {
  // THE case that must not show a red box: the row already exists, which is
  // what the customer wanted. Telling them it failed invites a second click
  // that cannot possibly help.
  const pending = deletionResult({
    success: false,
    message: 'You already have a pending deletion request',
  })
  assert.equal(pending.ok, true)
  assert.equal(pending.message, 'You already have a pending deletion request')

  const sent = deletionResult({
    success: true,
    message: 'Your account deletion request has been submitted.',
  })
  assert.equal(sent.ok, true)
  assert.match(sent.message, /submitted/i)

  // The function returning a success with no copy still gets a sentence.
  assert.equal(deletionResult({ success: true }).ok, true)
  assert.ok(deletionResult({ success: true }).message.length > 0)

  const failed = deletionResult({ success: false, message: 'Request failed' })
  assert.equal(failed.ok, false)
  assert.equal(failed.message, 'Request failed')

  assert.equal(deletionResult(null).ok, false)
  assert.match(deletionResult(null).message, /could not send/i)
})
