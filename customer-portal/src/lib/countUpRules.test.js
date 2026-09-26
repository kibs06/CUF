import assert from 'node:assert/strict'
import { describe, it } from 'node:test'

import {
  COUNTUP_FASTEST_SECONDS,
  COUNTUP_SLOWEST_SECONDS,
  countUpSeconds,
} from './countUpRules.js'

/** Seconds compared to a tolerance — these are floats built from a log. */
function sameSeconds(actual, expected) {
  assert.equal(
    Math.abs(actual - expected) < 1e-9,
    true,
    `expected ${actual} to be ${expected}`,
  )
}

describe('countUpSeconds', () => {
  it('gives a small number longer than a large one', () => {
    // The whole point, stated once here and then as a property below.
    assert.equal(countUpSeconds(3) > countUpSeconds(312), true)
    assert.equal(countUpSeconds(312) > countUpSeconds(12480), true)
  })

  it('never rises as the number grows', () => {
    // Monotonic non-increasing across seven decades, including the awkward
    // values either side of a power of ten.
    const sweep = [0, 1, 2, 9, 10, 11, 99, 100, 101, 999, 1000, 9999, 10000, 1e6]
    for (let index = 1; index < sweep.length; index += 1) {
      assert.equal(
        countUpSeconds(sweep[index]) <= countUpSeconds(sweep[index - 1]),
        true,
        `${sweep[index]} should not count slower than ${sweep[index - 1]}`,
      )
    }
  })

  it('spends the slowest count on a single digit', () => {
    // A `1` is the worst case for this rule, not the best: one increment, so
    // the increment is the whole animation — and it is the case that must not
    // be so slow that the figure looks stuck.
    sameSeconds(countUpSeconds(0), COUNTUP_SLOWEST_SECONDS)
    sameSeconds(countUpSeconds(1), 0.7548455006504029)
    assert.equal(0.7 < countUpSeconds(1) && countUpSeconds(1) < COUNTUP_SLOWEST_SECONDS, true)
  })

  it('lands the decades on the values the curve was built around', () => {
    sameSeconds(countUpSeconds(9), 0.65)
    sameSeconds(countUpSeconds(99), 0.5)
    sameSeconds(countUpSeconds(999), 0.35)
    sameSeconds(countUpSeconds(9999), COUNTUP_FASTEST_SECONDS)
  })

  it('clamps rather than shrinking to nothing past five digits', () => {
    // A month's revenue and a year's revenue must count at the same speed; a
    // duration that kept falling would end at a snap.
    for (const value of [10000, 250000, 1200000, 9.9e8, Infinity]) {
      sameSeconds(countUpSeconds(value), COUNTUP_FASTEST_SECONDS)
    }
  })

  it('counts a refund for as long as a sale', () => {
    sameSeconds(countUpSeconds(-9999), countUpSeconds(9999))
    sameSeconds(countUpSeconds(-3), countUpSeconds(3))
  })

  it('turns a missing figure into a duration, never NaN', () => {
    // `animate(motionValue, value, { duration: NaN })` never completes, and an
    // animation that never completes is the counter stuck on zero — the exact
    // lie `CountUp` fails open to avoid.
    for (const value of [undefined, null, NaN, '', 'not a number', {}]) {
      const seconds = countUpSeconds(value)
      assert.equal(Number.isFinite(seconds), true, `${String(value)} produced ${seconds}`)
      sameSeconds(seconds, COUNTUP_SLOWEST_SECONDS)
    }
  })

  it('stays inside its own bounds for anything it is handed', () => {
    for (const value of [0, 1, 7, 40, 512, 8000, 65000, -12345, 1e12]) {
      const seconds = countUpSeconds(value)
      assert.equal(seconds >= COUNTUP_FASTEST_SECONDS, true, `${value} was too fast`)
      assert.equal(seconds <= COUNTUP_SLOWEST_SECONDS, true, `${value} was too slow`)
    }
  })

  it('is one considered one-off, faster at the top end than the entrance it replaced', () => {
    // The 400ms this rule replaced. A big figure — the hero money on the
    // dashboard — is the case the seller waits on, so it must not have got
    // slower; a small count may, because the movement is what it is for.
    assert.equal(COUNTUP_FASTEST_SECONDS < 0.4, true)
    assert.equal(COUNTUP_SLOWEST_SECONDS > 0.4, true)
  })
})
