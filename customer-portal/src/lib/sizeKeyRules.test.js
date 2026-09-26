import assert from 'node:assert/strict'
import { readdirSync, readFileSync, statSync } from 'node:fs'
import { join } from 'node:path'
import { describe, it } from 'node:test'
import { fileURLToPath } from 'node:url'

import {
  compareSizes,
  convertSizeNumber,
  euSizeFromUs,
  euToUsChartOffset,
  formatSize,
  formatSizeNumber,
  kDefaultSizeCategory,
  kDefaultSizeSystem,
  kEuMax,
  kEuMin,
  kNearSizeToleranceEu,
  kSizeUnits,
  sizeKey,
  sizeKeyForEu,
  sizeNumber,
  sizeNumberInEu,
  sizeSystem,
  sizeUnitsForCategory,
  usSizeFromEu,
} from './sizeKeyRules.js'

/**
 * A mirror of `test/utils/size_key_test.dart`.
 *
 * See `docs/AI/SIZE_AWARE_SHOPPING_PLAN.md` §4–5: this pins the one rule for
 * what a stored size means, so the shelf and the product page cannot disagree
 * with the app about whether a size is the customer's.
 */
describe('sizeSystem', () => {
  it('prefers an explicit prefix', () => {
    assert.equal(sizeSystem('EU 40'), 'EU')
    assert.equal(sizeSystem('EU40'), 'EU')
    assert.equal(sizeSystem('eu 40'), 'EU')
    assert.equal(sizeSystem('US 8'), 'US')
    assert.equal(sizeSystem('UK 3.5'), 'UK')
    assert.equal(sizeSystem('JP 25'), 'JP')
  })

  it('bare numbers fall back to the default system (decision #1: EU)', () => {
    assert.equal(kDefaultSizeSystem, 'EU')
    assert.equal(sizeSystem('40'), 'EU')
    assert.equal(sizeSystem(' 40'), 'EU')
    assert.equal(sizeSystem('9.5'), 'EU')
    assert.equal(sizeSystem(null), 'EU')
  })

  it('no number → default, never a guessed prefix', () => {
    assert.equal(sizeSystem(''), 'EU')
    assert.equal(sizeSystem('Other'), 'EU')
    assert.equal(sizeSystem('garbage'), 'EU')
  })
})

describe('sizeNumber', () => {
  it('parses prefixed and bare sizes', () => {
    assert.equal(sizeNumber('EU 40'), 40)
    assert.equal(sizeNumber('40'), 40)
    assert.equal(sizeNumber(' 40'), 40)
    assert.equal(sizeNumber('EU40'), 40)
    assert.equal(sizeNumber('US 8'), 8)
    assert.equal(sizeNumber('UK 3.5'), 3.5)
    assert.equal(sizeNumber('JP 25'), 25)
    assert.equal(sizeNumber('9.5'), 9.5)
  })

  it('returns null when there is no number', () => {
    assert.equal(sizeNumber(''), null)
    assert.equal(sizeNumber('EU'), null)
    assert.equal(sizeNumber('Other'), null)
    assert.equal(sizeNumber('garbage'), null)
    assert.equal(sizeNumber(null), null)
  })

  it('a malformed number is not silently truncated', () => {
    // `parseFloat('1.2.3')` would answer 1.2 — a size nobody typed.
    assert.equal(sizeNumber('1.2.3'), null)
  })
})

describe('sizeKey — the DB mirror', () => {
  it("mirrors regexp_replace(size, '\\D', '', 'g')", () => {
    assert.equal(sizeKey('EU 40'), '40')
    assert.equal(sizeKey('40'), '40')
    assert.equal(sizeKey(' 40'), '40')
    assert.equal(sizeKey('US 8'), '8')
    // The dot goes too — `\D` is exactly non-digit, not "non-digit-or-dot".
    assert.equal(sizeKey('UK 3.5'), '35')
    assert.equal(sizeKey('JP 25'), '25')
    assert.equal(sizeKey('9.5'), '95')
    assert.equal(sizeKey(''), '')
    assert.equal(sizeKey('Other'), '')
  })

  it('the DB-mirror invariant: EU 40 and 40 are one size', () => {
    assert.equal(sizeKey('EU 40'), sizeKey('40'))
    assert.equal(sizeKey(' 40'), sizeKey('EU 40'))
  })

  it('sizeKeyForEu keys a profile EU size the same way', () => {
    assert.equal(sizeKeyForEu(40), '40')
    assert.equal(sizeKeyForEu(42), '42')
    assert.equal(sizeKeyForEu(41.5), '415')
  })
})

describe('sizeNumberInEu', () => {
  it('is identity for EU and for bare (default) sizes', () => {
    assert.equal(sizeNumberInEu('EU 40'), 40)
    assert.equal(sizeNumberInEu('40'), 40)
    assert.equal(sizeNumberInEu('41.5'), 41.5)
  })

  it('converts the known systems', () => {
    assert.equal(sizeNumberInEu('US 7'), 40)
    assert.equal(sizeNumberInEu('UK 6.5'), 40)
  })

  it('unknown systems keep their raw value — the band check rejects them', () => {
    assert.equal(sizeNumberInEu('JP 25'), 25)
    assert.equal(kEuMin, 35)
    assert.equal(kEuMax, 48)
    assert.equal(kNearSizeToleranceEu, 0.5)
  })

  it('returns null when there is no number', () => {
    assert.equal(sizeNumberInEu(''), null)
    assert.equal(sizeNumberInEu('Other'), null)
  })
})

describe('formatSize — the one label formatter', () => {
  it('names the system instead of assuming one', () => {
    assert.equal(formatSize('EU 40'), 'EU 40')
    assert.equal(formatSize('40'), 'EU 40')
    assert.equal(formatSize(' 40'), 'EU 40')
    assert.equal(formatSize('EU40'), 'EU 40')
    assert.equal(formatSize('US 8'), 'US 8')
    assert.equal(formatSize('UK 3.5'), 'UK 3.5')
    assert.equal(formatSize('JP 25'), 'JP 25')
    assert.equal(formatSize('9.5'), 'EU 9.5')
  })

  it('converts when asked for a target unit', () => {
    assert.equal(formatSize('EU 40', { unit: 'US' }), 'US 7')
    assert.equal(formatSize('EU 40', { unit: 'EU' }), 'EU 40')
    assert.equal(formatSize('US 8', { unit: 'EU' }), 'EU 41')
    // A bare stored EU 40 must not render as 'US 40'.
    assert.equal(formatSize('40', { unit: 'US' }), 'US 7')
  })

  it('falls back to the raw string when it cannot parse', () => {
    assert.equal(formatSize(''), '')
    assert.equal(formatSize('Other'), 'Other')
    assert.equal(formatSize('garbage'), 'garbage')
  })

  it('formatSizeNumber drops the pointless .0', () => {
    assert.equal(formatSizeNumber(40), '40')
    assert.equal(formatSizeNumber(40.5), '40.5')
    assert.equal(formatSizeNumber(22), '22')
  })
})

describe('compareSizes — half sizes sort numerically', () => {
  it('orders by numeric value, not by string', () => {
    assert.ok(compareSizes('40', '42') < 0)
    assert.ok(compareSizes('42', '40') > 0)
    assert.ok(compareSizes('42.5', '42') > 0)
    assert.ok(compareSizes('9.5', '10.5') < 0)
    assert.ok(compareSizes('EU 40', 'EU 41.5') < 0)
    assert.equal(compareSizes('40', '40'), 0)
  })

  it('unparseable sizes sort last, never to the front', () => {
    assert.ok(compareSizes('Other', 'EU 40') > 0)
    assert.ok(compareSizes('EU 40', 'Other') < 0)
    assert.notEqual(compareSizes('Other', 'garbage'), 0)
  })

  it('the §4.3 regression: half sizes sort in place', () => {
    const sizes = ['42.5', '40', '41.5', '9.5', '39']
    sizes.sort(compareSizes)
    assert.deepEqual(sizes, ['9.5', '39', '40', '41.5', '42.5'])
  })
})

describe('the shopping scale — US labels are chart-dependent', () => {
  it("men's offsets are the default and the only fallback", () => {
    assert.equal(kDefaultSizeCategory, 'men')
    assert.equal(euToUsChartOffset(null), 33)
    assert.equal(euToUsChartOffset('men'), 33)
    assert.equal(euToUsChartOffset('kids'), 33)
    assert.equal(euToUsChartOffset('women'), 31.5)
    // An unrecognised scale is NOT read as women's.
    assert.equal(euToUsChartOffset('unisex'), 33)
  })

  it('the same EU size reads differently per scale', () => {
    assert.equal(usSizeFromEu(42), 9)
    assert.equal(usSizeFromEu(42, { category: 'women' }), 10.5)
    assert.equal(usSizeFromEu(42, { category: 'kids' }), 9)
    assert.equal(euSizeFromUs(10.5, { category: 'women' }), 42)
  })

  it('formatSize labels US on the scale it is given', () => {
    assert.equal(formatSize('EU 42', { unit: 'US' }), 'US 9')
    assert.equal(formatSize('EU 42', { unit: 'US', category: 'women' }), 'US 10.5')
    assert.equal(formatSize('EU 42', { unit: 'US', category: 'kids' }), 'US 9')
    // Bare (EU) sizes take the same path — the product page's size grid.
    assert.equal(formatSize('42', { unit: 'US', category: 'women' }), 'US 10.5')
    assert.equal(formatSize('42.5', { unit: 'US', category: 'women' }), 'US 11')
    // Round-tripping stays exact, so a tapped label maps back to one size.
    assert.equal(
      formatSize(formatSize('EU 41.5', { unit: 'US', category: 'women' }), {
        unit: 'EU',
        category: 'women',
      }),
      'EU 41.5',
    )
  })

  it('UK stays on its single chart — the scale must not move it', () => {
    assert.equal(formatSize('EU 42', { unit: 'UK' }), 'UK 8.5')
    assert.equal(formatSize('EU 42', { unit: 'UK', category: 'women' }), 'UK 8.5')
    assert.equal(convertSizeNumber(42, 'EU', 'UK', { category: 'women' }), 8.5)
  })

  it("convertSizeNumber is unchanged for the men's default", () => {
    assert.equal(convertSizeNumber(40, 'EU', 'US'), 7)
    assert.equal(convertSizeNumber(7, 'US', 'EU'), 40)
    assert.equal(convertSizeNumber(40, 'EU', 'UK'), 6.5)
    assert.equal(convertSizeNumber(6.5, 'UK', 'EU'), 40)
    assert.equal(convertSizeNumber(7, 'US', 'UK'), 6.5)
    assert.equal(convertSizeNumber(6.5, 'UK', 'US'), 7)
    assert.equal(convertSizeNumber(40, 'EU', 'EU'), 40)
  })

  it('units are EU + US + UK — except on the kids chart', () => {
    assert.deepEqual(kSizeUnits, ['EU', 'US', 'UK'])
    assert.deepEqual(sizeUnitsForCategory(null), kSizeUnits)
    assert.deepEqual(sizeUnitsForCategory('men'), kSizeUnits)
    assert.deepEqual(sizeUnitsForCategory('women'), kSizeUnits)
    // Kids' US/UK is a separate, non-linear chart: the men's-derived step would
    // label a child's EU 22 as US -11.
    assert.deepEqual(sizeUnitsForCategory('kids'), ['EU'])
    assert.equal(usSizeFromEu(22, { category: 'kids' }), -11)
  })

  it('an unknown system is still returned unchanged', () => {
    assert.equal(convertSizeNumber(25, 'JP', 'EU'), 25)
    assert.equal(convertSizeNumber(40, 'EU', 'JP'), 40)
    assert.equal(formatSize('JP 25', { unit: 'US' }), 'US 25')
  })
})

describe('guard — sizes are labelled by formatSize, never by a literal', () => {
  it('no shipping source file builds a size label from a hardcoded "EU "', () => {
    // The same guard the Dart suite carries (`grep -rn "'EU $" lib/`), so a
    // surface cannot reintroduce a label that assumes a system.
    const pattern = new RegExp('[\'"`]EU \\$')
    const offenders = []

    for (const file of sourceFiles(fileURLToPath(new URL('..', import.meta.url)))) {
      const lines = readFileSync(file, 'utf8').split('\n')
      lines.forEach((line, index) => {
        const trimmed = line.trimStart()
        if (trimmed.startsWith('//') || trimmed.startsWith('*')) return
        if (pattern.test(line)) offenders.push(`${file}:${index + 1}`)
      })
    }

    assert.deepEqual(
      offenders,
      [],
      'Route size labels through formatSize()/euSizeLabel() in sizeKeyRules.js instead of a hardcoded EU literal.',
    )
  })
})

/** Every shipping `.js`/`.jsx` under `src`, tests and test fixtures excluded. */
function sourceFiles(srcDir) {
  const found = []
  for (const entry of readdirSync(srcDir)) {
    const path = join(srcDir, entry)
    if (statSync(path).isDirectory()) {
      found.push(...sourceFiles(path))
      continue
    }
    if (!/\.(js|jsx)$/.test(entry)) continue
    if (/\.test\.(js|jsx)$/.test(entry)) continue
    found.push(path)
  }
  return found
}
