import assert from 'node:assert/strict'
import { describe, it } from 'node:test'

import {
  matchesSearchQuery,
  matchesStorefrontSearch,
  searchPanelRows,
  searchSuggestionsFor,
  searchWords,
  SEARCH_PANEL_ROW,
  SEARCH_SUGGESTION_KIND,
} from './searchRules.js'

/**
 * The customer search rule — what a query matches, and what to suggest.
 *
 * A 1:1 mirror of `test/utils/product_search_test.dart`: the same cases, the
 * same reasons. If the Dart rule changes, these change with it — a storefront
 * that cannot find what the app can find is the same class of bug as one that
 * quotes a different price.
 */
const p = ({ name, category, tags = [] }) => ({
  id: name,
  name,
  category,
  tags,
})

describe('searchWords', () => {
  it('splits on whitespace, lowercases, drops empties', () => {
    assert.deepEqual(searchWords('  Formal   SHOES '), ['formal', 'shoes'])
    assert.deepEqual(searchWords('loafers'), ['loafers'])
    assert.deepEqual(searchWords('   '), [])
    assert.deepEqual(searchWords(''), [])
    assert.deepEqual(searchWords(null), [])
  })
})

describe('matchesSearchQuery — what a query finds', () => {
  it('a whole-phrase name match', () => {
    assert.equal(
      matchesSearchQuery(p({ name: 'Formal Derby' }), 'formal derby'),
      true,
    )
  })

  it('any word of the query in the name', () => {
    // The customer typing more words is narrowing in their head, not asking for
    // a conjunction — so this is an OR, not an AND.
    assert.equal(
      matchesSearchQuery(
        p({ name: 'Formal Leather Derby' }),
        'leather derby',
      ),
      true,
    )
  })

  it('the CATEGORY — the search that used to find nothing', () => {
    const catalog = [
      p({ name: 'Classic Oxford', category: 'Formal' }),
      p({ name: 'Beach Slide', category: 'Sandals' }),
    ]

    const hits = catalog.filter((product) =>
      matchesSearchQuery(product, 'Formal Shoes'),
    )

    assert.deepEqual(
      hits.map((hit) => hit.name),
      ['Classic Oxford'],
    )
  })

  it('a tag word', () => {
    assert.equal(
      matchesSearchQuery(
        p({ name: 'Classic Oxford', tags: ['handmade', 'leather'] }),
        'handmade loafers',
      ),
      true,
    )
  })

  it('is case-insensitive on both sides', () => {
    assert.equal(
      matchesSearchQuery(
        p({ name: 'Classic Oxford', category: 'Formal' }),
        'FORMAL',
      ),
      true,
    )
    assert.equal(
      matchesSearchQuery(p({ name: 'Classic Oxford' }), 'OXFORD'),
      true,
    )
  })

  it('a word the catalog has never heard of does not match', () => {
    const catalog = [
      p({ name: 'Classic Oxford', category: 'Formal', tags: ['leather'] }),
    ]
    for (const query of ['runway pumps 3000', 'xyz123', 'sneaker']) {
      assert.equal(
        catalog.some((product) => matchesSearchQuery(product, query)),
        false,
        `"${query}" must not match anything in this catalog`,
      )
    }
  })

  it('a blank query matches NOTHING, not everything', () => {
    // "No query" is not a search. A caller that wants the whole catalog should
    // ask for the catalog.
    for (const query of ['', '   ', '\n']) {
      assert.equal(matchesSearchQuery(p({ name: 'Classic Oxford' }), query), false)
    }
  })

  it('odd rows do not throw and simply do not match', () => {
    assert.equal(matchesSearchQuery({}, 'formal'), false)
    assert.equal(matchesSearchQuery(null, 'formal'), false)
    assert.equal(
      matchesSearchQuery({ name: 'Oxford', tags: 'not-an-array' }, 'handmade'),
      false,
    )
    assert.equal(
      matchesSearchQuery({ name: 'Oxford', category: null }, 'oxford'),
      true,
    )
  })
})

describe('matchesStorefrontSearch — the portal’s two extra fields', () => {
  const boots = {
    name: 'Everyday Boot',
    category: 'Boots',
    tags: [],
    store_name: 'Janella',
    collection: 'Workshop Collection',
  }

  it('still applies the app’s rule', () => {
    assert.equal(matchesStorefrontSearch(boots, 'boot'), true)
    assert.equal(matchesStorefrontSearch(boots, 'boots shoes'), true)
    assert.equal(matchesStorefrontSearch(boots, 'xyz123'), false)
  })

  it('finds a maker by name, word-wise', () => {
    // "janella boots" is a reason to buy: the customer knows the workshop and
    // the shape they want, and does not have to spell either exactly.
    assert.equal(matchesStorefrontSearch(boots, 'janella'), true)
    assert.equal(matchesStorefrontSearch(boots, 'janella boots'), true)
  })

  it('finds a collection, and ignores the fields when they are absent', () => {
    assert.equal(matchesStorefrontSearch(boots, 'workshop'), true)
    assert.equal(
      matchesStorefrontSearch({ name: 'Oxford', tags: [] }, 'janella'),
      false,
    )
  })

  it('a blank query still matches nothing', () => {
    for (const query of ['', '   ']) {
      assert.equal(matchesStorefrontSearch(boots, query), false)
    }
  })
})

describe('searchPanelRows — what the panel renders, in order', () => {
  const catalog = [
    p({ name: 'Classic Oxford', category: 'Formal', tags: ['leather'] }),
    p({ name: 'Hiking Boot', category: 'Boots', tags: ['outdoor'] }),
  ]

  it('puts the typed query first, and never as a suggestion', () => {
    const rows = searchPanelRows('formal', catalog)

    assert.deepEqual(rows[0], { term: 'formal', kind: SEARCH_PANEL_ROW.query })
    assert.equal(
      rows.filter((row) => row.term.toLowerCase() === 'formal').length,
      1,
    )
  })

  it('follows it with the catalog words, each labelled with its kind', () => {
    const rows = searchPanelRows('boot', catalog)

    assert.deepEqual(rows.slice(1), [
      { term: 'Boots', kind: SEARCH_PANEL_ROW.category },
      { term: 'Hiking Boot', kind: SEARCH_PANEL_ROW.product },
    ])
  })

  it('is empty for a blank query — no panel, not an empty one', () => {
    assert.deepEqual(searchPanelRows('', catalog), [])
    assert.deepEqual(searchPanelRows('   ', catalog), [])
    assert.deepEqual(searchPanelRows(null, catalog), [])
  })

  it('trims what it echoes back, and survives a missing catalog', () => {
    assert.deepEqual(searchPanelRows('  oxford  ', null), [
      { term: 'oxford', kind: SEARCH_PANEL_ROW.query },
    ])
  })
})

describe('searchSuggestionsFor — the panel under the bar', () => {
  const catalog = [
    p({ name: 'Classic Oxford', category: 'Formal', tags: ['leather'] }),
    p({ name: 'Derby Brogue', category: 'Formal', tags: ['leather'] }),
    p({ name: 'Hiking Boot', category: 'Boots', tags: ['outdoor'] }),
    p({ name: 'School Shoes', category: 'Sneakers' }),
    p({ name: 'Recycled Runner', category: 'Sports', tags: ['eco'] }),
  ]

  const termsFor = (products, query, limit) =>
    searchSuggestionsFor(products, { query, limit }).map(
      (suggestion) => suggestion.term,
    )

  it('suggests the catalog words that would actually return something', () => {
    // A partially typed category, and a partially typed product name.
    assert.ok(termsFor(catalog, 'form').includes('Formal'))
    assert.ok(termsFor(catalog, 'oxford').includes('Classic Oxford'))
  })

  it('a word-prefix match outranks a mid-word one', () => {
    const terms = termsFor(
      [
        // 'boo' starts the word "Boots" ...
        p({ name: 'Trail Boot', category: 'Boots' }),
        // ...but only appears inside "bamboo".
        p({ name: 'Classic Oxford', tags: ['bamboo'] }),
      ],
      'boo',
    )

    assert.equal(terms[0], 'Boots')
    assert.ok(terms.includes('bamboo'))
  })

  it('a term backed by more products outranks a one-off', () => {
    const terms = termsFor(
      [
        p({ name: 'A', category: 'Leather Goods' }),
        p({ name: 'B', category: 'Leather Goods' }),
        p({ name: 'C', tags: ['leatherette'] }),
      ],
      'leat',
    )

    assert.equal(terms[0], 'Leather Goods')
  })

  it('carries the kind, so a panel can label a row', () => {
    const byTerm = new Map(
      searchSuggestionsFor(
        [p({ name: 'Hiking Boot', category: 'Boots', tags: ['outdoor'] })],
        { query: 'boot' },
      ).map((suggestion) => [suggestion.term, suggestion.kind]),
    )

    assert.equal(byTerm.get('Boots'), SEARCH_SUGGESTION_KIND.category)
    assert.equal(byTerm.get('Hiking Boot'), SEARCH_SUGGESTION_KIND.product)
  })

  it('a tag is suggested as a tag', () => {
    const byTerm = new Map(
      searchSuggestionsFor(catalog, { query: 'leath' }).map((suggestion) => [
        suggestion.term,
        suggestion.kind,
      ]),
    )

    assert.equal(byTerm.get('leather'), SEARCH_SUGGESTION_KIND.tag)
  })

  it('never suggests what the customer already typed', () => {
    const terms = termsFor(catalog, 'Formal').map((term) => term.toLowerCase())

    assert.ok(!terms.includes('formal'))
  })

  it('a blank query yields no suggestions (the panel shows recent terms)', () => {
    assert.deepEqual(searchSuggestionsFor(catalog, { query: '' }), [])
    assert.deepEqual(searchSuggestionsFor(catalog, { query: '   ' }), [])
    assert.deepEqual(searchSuggestionsFor(catalog, {}), [])
    assert.deepEqual(searchSuggestionsFor(null, { query: 'boot' }), [])
  })

  it('honours the limit, and never exceeds the catalog vocabulary', () => {
    assert.equal(searchSuggestionsFor(catalog, { query: 'e', limit: 2 }).length, 2)
    assert.equal(searchSuggestionsFor(catalog, { query: 'e', limit: 0 }).length, 0)
    // A negative limit must not fall through to `slice`, which would count
    // backwards from the end and return almost everything.
    assert.equal(searchSuggestionsFor(catalog, { query: 'e', limit: -1 }).length, 0)
    assert.deepEqual(termsFor(catalog, 'zzz'), [])
  })

  it('is deterministic — same input, same order', () => {
    const once = () => termsFor(catalog, 'le')

    assert.deepEqual(once(), once())
  })
})
