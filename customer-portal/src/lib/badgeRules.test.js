import assert from 'node:assert/strict'
import { describe, it } from 'node:test'

import { MAX_BADGE, badgeCount, waitingCount } from './badgeRules.js'

describe('badgeCount', () => {
  it('draws nothing for zero', () => {
    // The decision that stops a pill sitting permanently on the avatar.
    assert.equal(badgeCount(0), null)
  })

  it('draws nothing for anything that is not a count', () => {
    // A count that has not loaded, a string, a NaN — none of them is a claim
    // that something happened, and a visible `NaN` is worse than silence.
    for (const value of [undefined, null, '', 'abc', NaN, Infinity, -Infinity]) {
      assert.equal(badgeCount(value), null, `${String(value)} should draw nothing`)
    }
  })

  it('draws nothing for a negative count', () => {
    // Cannot happen from a HEAD count, and if it ever did the honest reading is
    // "nothing waiting" rather than a badge with a minus in it.
    assert.equal(badgeCount(-1), null)
  })

  it('shows a small count as its own digits', () => {
    assert.equal(badgeCount(1), '1')
    assert.equal(badgeCount(28), '28')
  })

  it('caps at 99+, including exactly 100', () => {
    assert.equal(badgeCount(MAX_BADGE), '99')
    assert.equal(badgeCount(MAX_BADGE + 1), '99+')
    assert.equal(badgeCount(4200), '99+')
  })

  it('never shows a longer string as the count grows', () => {
    // The property the cap exists for: the badge cannot widen past four glyphs,
    // so it cannot push a 240px panel's row around.
    let longest = 0
    for (const value of [1, 9, 10, 99, 100, 999, 1e6]) {
      longest = Math.max(longest, badgeCount(value).length)
    }
    assert.equal(longest, 3)
  })

  it('truncates a fraction rather than rounding it up', () => {
    assert.equal(badgeCount(1.9), '1')
  })

  it('reads a numeric string, because Supabase counts arrive as one', () => {
    // PostgREST returns `count` as a string on some responses; a badge that
    // disappeared because of that would be a bug nobody could see.
    assert.equal(badgeCount('7'), '7')
    assert.equal(badgeCount('0'), null)
  })
})

describe('waitingCount', () => {
  it('adds the two tables the avatar badge answers from', () => {
    assert.equal(waitingCount(28, 3), 31)
  })

  it('treats a count that has not loaded as zero', () => {
    // The half-loaded case: `undefined + 3` is NaN, and NaN would blank a badge
    // that has a good answer in the other hand.
    assert.equal(waitingCount(undefined, 3), 3)
    assert.equal(waitingCount(3, undefined), 3)
    assert.equal(Number.isNaN(waitingCount(undefined, undefined)), false)
    assert.equal(waitingCount(undefined, undefined), 0)
  })

  it('ignores negatives and unreadable parts without poisoning the total', () => {
    assert.equal(waitingCount(-5, 4), 4)
    assert.equal(waitingCount('abc', 2), 2)
  })

  it('feeds the badge directly, so the two cannot disagree', () => {
    assert.equal(badgeCount(waitingCount(120, 8)), '99+')
    assert.equal(badgeCount(waitingCount(0, 0)), null)
  })
})
