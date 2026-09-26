/**
 * Appearance rules — the pure half of the theme setting.
 *
 * A port of `lib/providers/theme_provider.dart` + `lib/services/theme_service.dart`
 * (the three-way mode, and the subtitle wording), with one deliberate
 * difference: the app persists through SharedPreferences, the portal through
 * `localStorage`, so the *storage contract* is stated here as plain data and
 * both the provider and `index.html`'s pre-paint script obey it.
 *
 * Pure and separate from the provider for the same reason `signupRules` is: the
 * awkward cases are all decisions about strings and unknown values — a stored
 * value that is not a mode, no stored value at all, a `matchMedia` that reports
 * nothing — and none of those need a DOM to be worth being sure about.
 */

/** The three-way choice. `system` follows the device, as the app does. */
export const THEME_MODES = ['system', 'light', 'dark']

/** The default, matching `ThemeProvider({ThemeMode initialMode = ThemeMode.system})`. */
export const DEFAULT_THEME_MODE = 'system'

/**
 * Where the choice lives. Deliberately a single flat key with a product prefix:
 * the browser may host several apps on one origin in development, and a bare
 * `theme` would be shared with whatever else is running on localhost.
 *
 * `index.html` hard-codes this same string in its pre-paint script, because
 * that script has to run before any module loads. The two are pinned together
 * by a test, since a rename that only lands in one of them is a white flash on
 * every dark-mode visit.
 */
export const THEME_STORAGE_KEY = 'cufmai.portal.theme-mode'

/**
 * A stored value as a mode. Anything unrecognised — null, `''`, `'Dark'`,
 * a value from a future version — resolves to `system`, never to a crash and
 * never to a guess at what it meant.
 */
export function resolveThemeMode(stored) {
  if (typeof stored !== 'string') return DEFAULT_THEME_MODE
  const value = stored.trim().toLowerCase()
  return THEME_MODES.includes(value) ? value : DEFAULT_THEME_MODE
}

/**
 * What the mode actually paints, once the device preference is known.
 *
 * Only `system` cares about `prefersDark`; a pinned mode ignores the device
 * entirely, which is the entire reason the setting is three-way rather than an
 * on/off switch.
 */
export function effectiveTheme(mode, prefersDark) {
  const resolved = resolveThemeMode(mode)
  if (resolved === 'system') return prefersDark ? 'dark' : 'light'
  return resolved
}

/** `System` / `Light` / `Dark` — `ThemeProvider.label`. */
export function themeModeLabel(mode) {
  switch (resolveThemeMode(mode)) {
    case 'light':
      return 'Light'
    case 'dark':
      return 'Dark'
    default:
      return 'System'
  }
}

/**
 * The row's subtitle.
 *
 * "System · Dark (device)" is what the app shows, and the explicitness is the
 * point: a bare "System" tells the customer the app is following their device
 * but not what that currently means, so the two states they care about — which
 * theme am I looking at, and is it my choice — are invisible. The suffix marks
 * the ones the DEVICE decided, so the row can be read at a glance.
 */
export function themeModeSubtitle(mode, prefersDark) {
  const resolved = resolveThemeMode(mode)
  const label = themeModeLabel(resolved)
  if (resolved !== 'system') return label
  return `System · ${prefersDark ? 'Dark' : 'Light'} (device)`
}

/** The sentence under the picker — the app's own copy. */
export const THEME_EXPLANATION = 'Dark mode can follow your device or be pinned.'

/**
 * Read the stored mode out of a `Storage`-like object.
 *
 * Takes the store rather than reaching for `window` so the "what happens when
 * storage throws" path is testable: a browser with cookies blocked throws on
 * *access* to `localStorage`, not just on write, and a theme preference is
 * never worth taking a page down for.
 */
export function readStoredThemeMode(storage) {
  try {
    return resolveThemeMode(storage?.getItem(THEME_STORAGE_KEY))
  } catch {
    return DEFAULT_THEME_MODE
  }
}

/**
 * Persist the mode, reporting whether it landed.
 *
 * A missing store returns `false` rather than `true`: "there was nowhere to
 * write" and "it was written" are different answers, and a caller that logs or
 * retries needs the difference. Note the write is NORMALISED, so a corrupt
 * value can never reach storage and come back as a surprise next visit.
 */
export function writeStoredThemeMode(storage, mode) {
  if (!storage || typeof storage.setItem !== 'function') return false
  try {
    storage.setItem(THEME_STORAGE_KEY, resolveThemeMode(mode))
    return true
  } catch {
    return false
  }
}
