import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import test from 'node:test'
import assert from 'node:assert/strict'

import {
  DEFAULT_THEME_MODE,
  THEME_MODES,
  THEME_STORAGE_KEY,
  effectiveTheme,
  readStoredThemeMode,
  resolveThemeMode,
  themeModeLabel,
  themeModeSubtitle,
  writeStoredThemeMode,
} from './themeRules.js'

/** A `Storage` stand-in. */
function fakeStorage(initial = {}) {
  const map = new Map(Object.entries(initial))
  return {
    getItem: (key) => (map.has(key) ? map.get(key) : null),
    setItem: (key, value) => map.set(key, String(value)),
    get size() {
      return map.size
    },
  }
}

test('resolveThemeMode accepts the three modes, in any casing', () => {
  for (const mode of THEME_MODES) {
    assert.equal(resolveThemeMode(mode), mode)
    assert.equal(resolveThemeMode(mode.toUpperCase()), mode)
    assert.equal(resolveThemeMode(`  ${mode}  `), mode)
  }
})

test('resolveThemeMode falls back to system for anything unrecognised', () => {
  for (const value of [null, undefined, '', '   ', 'auto', 'sepia', 42, {}, []]) {
    assert.equal(resolveThemeMode(value), DEFAULT_THEME_MODE)
  }
  // Explicitly NOT light: a device that prefers dark must not be forced light
  // because a stored value was corrupt.
  assert.equal(resolveThemeMode('nonsense'), 'system')
})

test('a pinned mode ignores the device', () => {
  assert.equal(effectiveTheme('light', true), 'light')
  assert.equal(effectiveTheme('dark', false), 'dark')
  assert.equal(effectiveTheme('nonsense', true), 'dark')
})

test('system follows the device', () => {
  assert.equal(effectiveTheme('system', true), 'dark')
  assert.equal(effectiveTheme('system', false), 'light')
})

test('label is one word, subtitle says what system currently means', () => {
  assert.equal(themeModeLabel('system'), 'System')
  assert.equal(themeModeLabel('light'), 'Light')
  assert.equal(themeModeLabel('dark'), 'Dark')

  assert.equal(themeModeSubtitle('system', true), 'System · Dark (device)')
  assert.equal(themeModeSubtitle('system', false), 'System · Light (device)')
  // A pinned mode says nothing about the device, because it is not following it.
  assert.equal(themeModeSubtitle('dark', false), 'Dark')
  assert.equal(themeModeSubtitle('light', true), 'Light')
})

test('storage round-trips a mode', () => {
  const storage = fakeStorage()
  assert.equal(readStoredThemeMode(storage), 'system')
  assert.equal(writeStoredThemeMode(storage, 'dark'), true)
  assert.equal(readStoredThemeMode(storage), 'dark')
  assert.equal(writeStoredThemeMode(storage, 'nonsense'), true)
  // Written normalised, so a corrupt value can never be persisted.
  assert.equal(storage.getItem(THEME_STORAGE_KEY), 'system')
})

test('a write reports whether it landed', () => {
  // "Nowhere to write" is not "written". A caller that logs or retries needs
  // to be able to tell the two apart, and a store that refuses is caught
  // rather than thrown — a theme preference is never worth a blank page.
  assert.equal(writeStoredThemeMode(null, 'dark'), false)
  assert.equal(writeStoredThemeMode(undefined, 'dark'), false)
  assert.equal(writeStoredThemeMode({}, 'dark'), false)
  assert.equal(writeStoredThemeMode(fakeStorage(), 'dark'), true)
})

test('a storage that throws is survivable, in both directions', () => {
  const hostile = {
    getItem() {
      throw new Error('Access to storage is not allowed')
    },
    setItem() {
      throw new Error('Access to storage is not allowed')
    },
  }

  assert.equal(readStoredThemeMode(hostile), DEFAULT_THEME_MODE)
  assert.equal(writeStoredThemeMode(hostile, 'dark'), false)
  // A missing store (server render, an old browser) is the same case.
  assert.equal(readStoredThemeMode(undefined), DEFAULT_THEME_MODE)
  assert.equal(writeStoredThemeMode(null, 'dark'), false)
})

/*
  The pre-paint script in `index.html` cannot import this module — it has to run
  before any module does — so the storage key and the mode names are duplicated
  there. This is the test that keeps the two copies honest: if the key is
  renamed in one place and not the other, every dark-mode visit gets a white
  flash for as long as it takes the bundle to load.
*/
test('index.html reads the same key and the same modes', () => {
  const html = readFileSync(
    fileURLToPath(new URL('../../index.html', import.meta.url)),
    'utf8',
  )

  assert.ok(
    html.includes(THEME_STORAGE_KEY),
    `index.html must reference ${THEME_STORAGE_KEY} in its pre-paint script`,
  )
  assert.ok(
    html.includes("classList.add('dark')") || html.includes('classList.add("dark")'),
    'index.html must apply the dark class before paint',
  )
  for (const mode of THEME_MODES) {
    assert.ok(html.includes(`'${mode}'`), `index.html must know the '${mode}' mode`)
  }
})
