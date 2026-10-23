import { test } from 'node:test'
import assert from 'node:assert/strict'

import {
  isSocialProvider,
  socialCallbackUrl,
  socialCallbackErrorMessage,
  socialStartErrorMessage,
  SOCIAL_PROVIDERS,
} from './socialAuth.js'

// Run with `npm test` (Node's own runner — no framework, no new dependency).

test('only google and facebook are offered as social providers', () => {
  assert.deepEqual([...SOCIAL_PROVIDERS].sort(), ['facebook', 'google'])
  assert.equal(isSocialProvider('google'), true)
  assert.equal(isSocialProvider('facebook'), true)
  assert.equal(isSocialProvider('apple'), false)
  assert.equal(isSocialProvider(''), false)
})

test('callback url strips a trailing slash before appending the route', () => {
  assert.equal(
    socialCallbackUrl('https://portal.example.com'),
    'https://portal.example.com/auth/callback',
  )
  assert.equal(
    socialCallbackUrl('http://localhost:5173/'),
    'http://localhost:5173/auth/callback',
  )
})

test('provider-not-enabled reads as a setup problem, not a user error', () => {
  assert.equal(
    socialStartErrorMessage(new Error('Identity provider is not enabled')),
    'Social sign-in is not switched on yet. Use your email and password for now.',
  )
  assert.equal(
    socialStartErrorMessage(new Error('network down')),
    'network down',
  )
})

test('cancelled consent reads as a cancellation, other returns pass through', () => {
  const denied = new URLSearchParams('error=access_denied&error_description=user+denied+it')
  assert.equal(
    socialCallbackErrorMessage(denied),
    'You cancelled the sign-in. Try again when ready.',
  )
  const other = new URLSearchParams('error=server_error&error_description=Something+broke')
  assert.equal(socialCallbackErrorMessage(other), 'Something broke')
  assert.equal(
    socialCallbackErrorMessage(new URLSearchParams('')),
    'That sign-in link did not work. Please try again.',
  )
})
