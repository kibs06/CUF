import assert from 'node:assert/strict'
import { describe, it } from 'node:test'

import {
  indexProductsByStore,
  storeFacts,
  topPicksFor,
  totalPairs,
} from './storeIndexRules.js'

/** The makers page derives every number on a card from this index. */
const product = (id, store_id, images = []) => ({ id, store_id, images })

describe('indexProductsByStore', () => {
  it('counts and groups by store', () => {
    const index = indexProductsByStore([
      product('a', 's1'),
      product('b', 's1'),
      product('c', 's2'),
    ])

    assert.deepEqual(index.counts, { s1: 2, s2: 1 })
    assert.deepEqual(
      index.byStore.s1.map((p) => p.id),
      ['a', 'b'],
    )
  })

  it('keeps the order it was given — newest first, not id order', () => {
    // The query orders by created_at descending, so this IS the newest-first
    // order; the app re-sorts by id only because its own list arrives shuffled.
    const index = indexProductsByStore([
      product('zzz', 's1'),
      product('aaa', 's1'),
    ])

    assert.deepEqual(
      index.byStore.s1.map((p) => p.id),
      ['zzz', 'aaa'],
    )
  })

  it('leaves a product with no store out rather than filing it under undefined', () => {
    const index = indexProductsByStore([product('a', null), product('b', 's1')])

    assert.deepEqual(index.counts, { s1: 1 })
    assert.equal(index.byStore.undefined, undefined)
  })

  it('survives nothing at all', () => {
    assert.deepEqual(indexProductsByStore(null).counts, {})
    assert.deepEqual(indexProductsByStore(undefined).byStore, {})
    assert.equal(totalPairs(indexProductsByStore([])), 0)
  })

  it('totals the pairs across every store', () => {
    const index = indexProductsByStore([
      product('a', 's1'),
      product('b', 's2'),
      product('c', 's2'),
    ])

    assert.equal(totalPairs(index), 3)
  })
})

describe('topPicksFor — the card’s window', () => {
  const index = indexProductsByStore([
    product('p1', 's1', ['photo.jpg']),
    product('p2', 's1'),
    product('p3', 's1', ['photo.jpg']),
    product('p4', 's1', ['photo.jpg']),
    product('p5', 's2'),
  ])

  it('skips products with no photograph, and caps at the limit', () => {
    // A tile with no image is a grey square; three of them look like a broken
    // gallery rather than a shop window.
    assert.deepEqual(
      topPicksFor(index, 's1').map((p) => p.id),
      ['p1', 'p3', 'p4'],
    )
    assert.deepEqual(
      topPicksFor(index, 's1', 2).map((p) => p.id),
      ['p1', 'p3'],
    )
  })

  it('is empty for a store with no photos, and for a store that is not here', () => {
    assert.deepEqual(topPicksFor(index, 's2'), [])
    assert.deepEqual(topPicksFor(index, 'nope'), [])
    assert.deepEqual(topPicksFor(null, 's1'), [])
  })
})

describe('storeFacts — rating, pairs, place', () => {
  const store = {
    name: 'Janella',
    rating: 4,
    review_count: 3,
    location: 'Valladolid, Carcar City, Cebu',
  }

  it('reads like the app’s pill row', () => {
    assert.deepEqual(storeFacts(store, 9), [
      { kind: 'rating', label: '4.0', value: '4' },
      { kind: 'pairs', label: '9 pairs' },
      { kind: 'location', label: 'Valladolid' },
    ])
  })

  it('shows NO rating until the store has one', () => {
    // stores.rating stays NULL until the first review, so 0 reviews must not
    // render as a 0.0 ★. Live data: one store at 4.0, two with no rating.
    for (const rating of [null, undefined, '']) {
      const facts = storeFacts({ ...store, rating }, 3)
      assert.equal(facts.some((fact) => fact.kind === 'rating'), false)
    }
    assert.deepEqual(storeFacts({ ...store, rating: 0 }, 3), [
      { kind: 'rating', label: '0.0', value: '0' },
      { kind: 'pairs', label: '3 pairs' },
      { kind: 'location', label: 'Valladolid' },
    ])
  })

  it('says nothing has been listed rather than "0 pairs"', () => {
    const facts = storeFacts({ name: 'New', location: '' }, 0)

    assert.deepEqual(facts, [{ kind: 'pairs', label: 'No pairs listed yet' }])
  })

  it('uses the first place name, and omits a location it does not have', () => {
    assert.equal(
      storeFacts({ location: 'Carcar City, Cebu' }, 1).at(-1).label,
      'Carcar City',
    )
    assert.equal(
      storeFacts({ location: null }, 1).some((f) => f.kind === 'location'),
      false,
    )
    assert.deepEqual(storeFacts(null, 0), [
      { kind: 'pairs', label: 'No pairs listed yet' },
    ])
  })
})
