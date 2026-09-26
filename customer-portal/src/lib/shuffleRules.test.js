import assert from 'node:assert/strict'
import { describe, it } from 'node:test'

import { randomSeed, shuffled } from './shuffleRules.js'

/** A catalog-sized list, so the assertions are about a real shelf. */
const catalog = Array.from({ length: 15 }, (_, index) => `p${index}`)

describe('shuffled', () => {
  it('deals the same hand for the same seed', () => {
    // This is the whole reason the order is a value: the shop memoises it, so a
    // hover, a refetch or a filter chip must not move the cards.
    assert.deepEqual(shuffled(catalog, 12345), shuffled(catalog, 12345))
  })

  it('actually deals a different hand for a different seed', () => {
    assert.notDeepEqual(shuffled(catalog, 1), shuffled(catalog, 2))
  })

  it('is a permutation: every product once, nothing invented', () => {
    const dealt = shuffled(catalog, 42)

    assert.equal(dealt.length, catalog.length)
    assert.deepEqual([...dealt].sort(), [...catalog].sort())
  })

  it('does not deal the order it was given', () => {
    // Not a proof of randomness — a proof that the commonest way to get this
    // wrong (a shuffle that quietly does nothing) is not what happened.
    assert.notDeepEqual(shuffled(catalog, 7), catalog)
  })

  it('never mutates the list it was given', () => {
    // The input is a memoised query result shared with every other surface.
    const source = [...catalog]
    shuffled(source, 99)

    assert.deepEqual(source, catalog)
  })

  it('survives nothing at all, and one thing', () => {
    assert.deepEqual(shuffled([], 3), [])
    assert.deepEqual(shuffled(null, 3), [])
    assert.deepEqual(shuffled(undefined, 3), [])
    assert.deepEqual(shuffled(['only'], 3), ['only'])
  })

  it('handles a seed of zero, and a seed it was not given', () => {
    // `>>> 0` on a bad seed must land on a valid state rather than NaN — a NaN
    // seed that produced NaN indexes would leave products in place and look
    // like a shuffle that half-worked.
    assert.equal(shuffled(catalog, 0).length, 15)
    assert.deepEqual(shuffled(catalog, undefined), shuffled(catalog, 0))
    assert.deepEqual(shuffled(catalog, -1), shuffled(catalog, 4294967295))
    assert.deepEqual(shuffled(catalog, 1.5), shuffled(catalog, 1))
  })
})

describe('randomSeed', () => {
  it('is a 32-bit unsigned integer', () => {
    for (let i = 0; i < 20; i += 1) {
      const seed = randomSeed()
      assert.equal(Number.isInteger(seed), true)
      assert.equal(seed >= 0 && seed <= 4294967295, true)
    }
  })

  it('is usable as a seed straight away', () => {
    assert.equal(shuffled(catalog, randomSeed()).length, 15)
  })
})
