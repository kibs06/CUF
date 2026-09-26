import assert from 'node:assert/strict'
import { describe, it } from 'node:test'

import {
  BANNER_GRADIENT_MIX,
  mixTowardEspresso,
  storeBannerUrl,
  storeCardGradient,
} from './storeBannerRules.js'

const URL = 'https://example.supabase.co/storage/v1/object/public/store-assets/x/banner.jpg'

describe('storeBannerUrl', () => {
  it('returns the banner a store uploaded', () => {
    assert.equal(storeBannerUrl({ banner_url: URL }), URL)
  })

  it('trims it, because the column is free text', () => {
    assert.equal(storeBannerUrl({ banner_url: `  ${URL}\n` }), URL)
  })

  it('treats an empty or blank column as no banner at all', () => {
    // `''` in an `src` makes the browser re-request the current page, so this is
    // not only cosmetic: a blank banner must not become a second page load per
    // card. Live data has one store with a null banner and two with real ones.
    for (const banner_url of [null, undefined, '', '   ', 42, {}, []]) {
      assert.equal(storeBannerUrl({ banner_url }), null)
    }
    assert.equal(storeBannerUrl({}), null)
    assert.equal(storeBannerUrl(null), null)
  })
})

describe('mixTowardEspresso', () => {
  it('is the app’s Color.lerp towards #1A1208', () => {
    // Clay at 0.55, per channel, rounded the way Flutter rounds:
    //   139 + (26 - 139) * 0.55 = 76.85 → 77 (0x4D)
    //    90 + (18 -  90) * 0.55 = 50.4  → 50 (0x32)
    //    43 + ( 8 -  43) * 0.55 = 23.75 → 24 (0x18)
    assert.equal(mixTowardEspresso('#8B5A2B'), '#4d3218')
  })

  it('is the colour itself at 0 and espresso at 1', () => {
    assert.equal(mixTowardEspresso('#8B5A2B', 0), '#8b5a2b')
    assert.equal(mixTowardEspresso('#8B5A2B', 1), '#1a1208')
  })

  it('accepts a colour without the hash', () => {
    assert.equal(mixTowardEspresso('8B5A2B'), mixTowardEspresso('#8B5A2B'))
  })

  it('hands back anything it cannot parse, rather than NaN in a gradient', () => {
    // `rgb(NaN, …)` is dropped by the browser, so the card would silently lose
    // its fallback band instead of showing one.
    for (const value of ['', 'clay', '#12345', '#GGGGGG', null, undefined, 42]) {
      assert.equal(mixTowardEspresso(value), value)
    }
  })
})

describe('storeCardGradient', () => {
  it('blends the store’s own colour into the dark end', () => {
    assert.equal(
      storeCardGradient({ brand_color: '#8B5A2B' }),
      'linear-gradient(135deg, #8B5A2B 0%, #4d3218 100%)',
    )
  })

  it('uses clay for a store that has not set a colour — as its avatar does', () => {
    assert.equal(
      storeCardGradient({ banner_url: null }),
      'linear-gradient(135deg, #8B5A2B 0%, #4d3218 100%)',
    )
  })

  it('survives a malformed brand colour, and a store that is not there', () => {
    assert.equal(
      storeCardGradient({ brand_color: 'not-a-colour' }),
      storeCardGradient({}),
    )
    assert.equal(storeCardGradient(null), storeCardGradient(undefined))
  })

  it('is a gradient the browser can actually parse', () => {
    // Case-insensitive: `storeColor` hands back the store's own spelling, and
    // hex is hex either way — only the blended end is always lowercase.
    const gradient = storeCardGradient({ brand_color: '#0057B8' })
    assert.equal(
      /^linear-gradient\(135deg, #[0-9a-f]{6} 0%, #[0-9a-f]{6} 100%\)$/i.test(gradient),
      true,
    )
  })
})

describe('BANNER_GRADIENT_MIX', () => {
  it('stays in the range a colour blend can be', () => {
    assert.equal(BANNER_GRADIENT_MIX > 0 && BANNER_GRADIENT_MIX < 1, true)
  })
})
