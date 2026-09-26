/**
 * Dealing the catalog in a random order — the shop's default.
 *
 * A storefront that opens on the same fifteen products in the same order every
 * time is a shelf nobody walks past the front of: the first row is whatever was
 * listed most recently, and on a small catalog that is the whole visit. Shuffling
 * means the customer meets the catalog rather than its insertion order.
 *
 * ## Why it is seeded rather than `sort(() => Math.random() - 0.5)`
 *
 * Three reasons, in order of how badly each one bites:
 *
 *  1. **`sort` with a random comparator is not a shuffle.** It is not even a
 *     permutation the engine promises: V8's sort may compare an element many
 *     times and against different neighbours, so the bias is real and uneven —
 *     some orders come up far more often than others, and an element can
 *     effectively never move. Fisher–Yates is the shuffle; this is Fisher–Yates.
 *  2. **A shuffle that runs per render reshuffles on every re-render** — a hover,
 *     a filter chip, a TanStack Query refetch — which is intolerable to use:
 *     the card you were about to click moves. A seed makes the order a *value*,
 *     so it can be memoised and only changes when the caller says so.
 *  3. **A seeded order is testable.** The app's own tests can't assert anything
 *     about `Math.random()`; these can assert that the same seed deals the same
 *     hand, that every product appears exactly once, and that the order is not
 *     the input order.
 *
 * The generator is mulberry32 — small, fast, and good enough for arranging
 * cards: this is not cryptography, and nothing here decides a price, a stock
 * level or an entitlement.
 */

/** A new seed for a fresh deal. Any 32-bit value does. */
export function randomSeed() {
  return Math.floor(Math.random() * 4294967296) >>> 0
}

/** mulberry32: returns a function producing numbers in [0, 1). */
function mulberry32(seed) {
  // `>>> 0` so a missing, negative, fractional or oversized seed still lands on
  // a valid state instead of producing NaN and a non-shuffle.
  let state = seed >>> 0

  return function next() {
    state = (state + 0x6d2b79f5) >>> 0
    let t = state
    t = Math.imul(t ^ (t >>> 15), t | 1)
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

/**
 * The same items, in an order decided entirely by `seed`.
 *
 * Pure: the input is never mutated (the caller's array is usually a memoised
 * query result, and mutating it in place would shuffle the catalog for every
 * other surface on the site), and the same seed always deals the same hand.
 *
 * @template T
 * @param {T[]} items
 * @param {number} seed
 * @returns {T[]}
 */
export function shuffled(items, seed) {
  const list = [...(items ?? [])]
  const random = mulberry32(seed)

  // Fisher–Yates, walking from the end: each position is swapped with a
  // uniformly chosen position at or before it, so every permutation is equally
  // likely.
  for (let i = list.length - 1; i > 0; i -= 1) {
    const j = Math.floor(random() * (i + 1))
    const held = list[i]
    list[i] = list[j]
    list[j] = held
  }

  return list
}
