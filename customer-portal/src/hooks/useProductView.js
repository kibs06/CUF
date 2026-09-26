import { useCallback, useState } from 'react'

import { normalizeProductView } from '../lib/sellerRules.js'

/** Namespaced the way the theme key is, so two features cannot collide. */
const STORAGE_KEY = 'cufmai.seller.products.view'

/** `localStorage`, or null where even touching it throws (cookies blocked). */
function storageOrNull() {
  try {
    return window.localStorage
  } catch {
    return null
  }
}

/**
 * Photographs or columns — remembered per device.
 *
 * It is a *preference*, not a setting: nothing about the data changes, so it
 * belongs in `localStorage` beside the theme rather than in the database, and it
 * is per device because the two views exist for two situations (a phone is not
 * where anyone reads a chip column).
 *
 * Two details, both about not being clever at the wrong moment:
 *
 *  1. **The stored value is normalised on the way IN**, through the same
 *     `normalizeProductView` the rules module tests. Storage outlives releases —
 *     the string in there may have been written by an older build, by another
 *     tab, or by hand — and a value this version does not recognise has to mean
 *     the default view rather than a page with nothing on it.
 *  2. **A storage failure is not a control failure.** Private mode, a full disk
 *     and blocked cookies all make `setItem` throw; the view still switches for
 *     this visit, and the seller is not told about it, because nothing about the
 *     page's job is affected.
 */
export default function useProductView() {
  const [view, setViewState] = useState(() =>
    normalizeProductView(storageOrNull()?.getItem(STORAGE_KEY)),
  )

  const setView = useCallback((next) => {
    const normalized = normalizeProductView(next)
    setViewState(normalized)
    try {
      storageOrNull()?.setItem(STORAGE_KEY, normalized)
    } catch {
      // Kept for this visit only — see the docblock.
    }
  }, [])

  return [view, setView]
}
