import assert from 'node:assert/strict'
import { describe, it } from 'node:test'

import {
  TOAST_LIMIT,
  TOAST_MAX_AGE_MS,
  pickToastNotifications,
  toastIsFresh,
} from './notificationToasts.js'

const AT = '2026-09-25T12:00:00Z'
const NOW = Date.parse(AT)

/** A row the way either feed returns one — only the three fields the rules read. */
const row = (over = {}) => ({
  id: 'n1',
  is_read: false,
  created_at: AT,
  ...over,
})

/** A timestamp `seconds` before the fixed "now" the tests use. */
const ago = (seconds) => new Date(NOW - seconds * 1000).toISOString()

describe('toastIsFresh', () => {
  it('is fresh inside the window and stale outside it', () => {
    assert.equal(toastIsFresh(row({ created_at: ago(0) }), NOW), true)
    assert.equal(toastIsFresh(row({ created_at: ago(60) }), NOW), true)
    assert.equal(
      toastIsFresh(row({ created_at: ago(TOAST_MAX_AGE_MS / 1000 - 1) }), NOW),
      true,
    )
    assert.equal(
      toastIsFresh(row({ created_at: ago(TOAST_MAX_AGE_MS / 1000) }), NOW),
      false,
    )
    assert.equal(toastIsFresh(row({ created_at: ago(90 * 60) }), NOW), false)
  })

  it('counts a future timestamp as fresh', () => {
    // A phone with a clock twenty minutes fast, or a row written a moment
    // before the server's clock was corrected. News, not a reason to drop it.
    assert.equal(toastIsFresh(row({ created_at: ago(-20 * 60) }), NOW), true)
  })

  it('refuses a row with no readable timestamp', () => {
    for (const value of [null, undefined, '', 'not a date', {}]) {
      assert.equal(toastIsFresh(row({ created_at: value }), NOW), false)
    }
    assert.equal(toastIsFresh(null, NOW), false)
  })
})

describe('pickToastNotifications', () => {
  it('takes unread, fresh rows newest first', () => {
    const feed = [
      row({ id: 'old', created_at: ago(20 * 60) }),
      row({ id: 'newest', created_at: ago(10) }),
      row({ id: 'middle', created_at: ago(5 * 60) }),
    ]

    assert.deepEqual(
      pickToastNotifications(feed, { now: NOW }).map((item) => item.id),
      ['newest', 'middle', 'old'],
    )
  })

  it('leaves read rows alone — the toast is a state, not a badge', () => {
    const feed = [
      row({ id: 'read', is_read: true, created_at: ago(10) }),
      row({ id: 'unread', created_at: ago(20) }),
    ]

    assert.deepEqual(
      pickToastNotifications(feed, { now: NOW }).map((item) => item.id),
      ['unread'],
    )
  })

  it('leaves the backlog alone', () => {
    // The feed page is where a customer catches up; the badge is what sends
    // them there. Popping a week of history is not an announcement.
    const feed = [
      row({ id: 'fresh', created_at: ago(60) }),
      row({ id: 'stale', created_at: ago(7 * 86400) }),
    ]

    assert.deepEqual(
      pickToastNotifications(feed, { now: NOW }).map((item) => item.id),
      ['fresh'],
    )
  })

  it('caps a burst at the newest few', () => {
    const feed = Array.from({ length: 9 }, (_, index) =>
      row({ id: `n${index}`, created_at: ago(index) }),
    )

    const picked = pickToastNotifications(feed, { now: NOW })
    assert.equal(picked.length, TOAST_LIMIT)
    assert.deepEqual(picked.map((item) => item.id), ['n0', 'n1', 'n2'])
  })

  it('drops rows it cannot remember popping, and folds duplicate ids', () => {
    // The toaster's memory is keyed by id. A row with no id would pop on every
    // refetch; the same row twice in one array is one row.
    const feed = [
      row({ id: 'a', created_at: ago(10) }),
      row({ id: 'a', created_at: ago(10) }),
      row({ id: null, created_at: ago(5) }),
      row({ id: 'b', created_at: ago(20) }),
    ]

    assert.deepEqual(
      pickToastNotifications(feed, { now: NOW }).map((item) => item.id),
      ['a', 'b'],
    )
  })

  it('survives nothing at all', () => {
    assert.deepEqual(pickToastNotifications(null, { now: NOW }), [])
    assert.deepEqual(pickToastNotifications(undefined, { now: NOW }), [])
    assert.deepEqual(pickToastNotifications([], { now: NOW }), [])
    assert.deepEqual(pickToastNotifications([row()], { now: NOW, limit: 0 }), [])
  })

  it('honours a caller that asks for a different window', () => {
    const feed = [row({ id: 'ten-minutes', created_at: ago(10 * 60) })]

    assert.equal(pickToastNotifications(feed, { now: NOW }).length, 1)
    assert.equal(
      pickToastNotifications(feed, { now: NOW, maxAgeMs: 60 * 1000 }).length,
      0,
    )
  })
})
