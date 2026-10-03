import { useEffect } from 'react'

/**
 * Lock the page against background scroll while a dialog is open — and hand it
 * back only when the LAST dialog closes.
 *
 * ## Why a count, when every dialog could just save and restore one value
 *
 * Because dialogs nest, and the obvious version is wrong the moment two of them
 * do. `ColourDialog` carries the app's own nesting: *Add sizes* opens
 * `VariantDialog` over it. A lock that re-runs when that sheet opens captures
 * whatever `document.body.style.overflow` is at that instant — which, with the
 * inner sheet already locked, is `'hidden'`. The colour sheet therefore
 * "remembered" `hidden` as the page's own state, and when the seller finally
 * closed it, it faithfully restored a locked page: one size applied and the
 * whole portal could not be scrolled again (measured — see the README).
 *
 * Counting removes the ordering question rather than fixing one instance of it.
 * The first lock records the page's real inline value; every further lock only
 * counts; the last unlock puts the recorded value back. No dialog reads
 * `body.style.overflow` after another one has touched it.
 *
 * The count lives at module scope because it describes the page, not any one
 * component: a dialog that unmounts has to know whether a sibling is still
 * open, and React props cannot carry that.
 *
 * @param {boolean} [active] — false leaves the page alone (a dialog mounted
 *   with an `open` prop rather than conditionally is always in the tree).
 */
let openLocks = 0
let pageOverflow = ''

export function useScrollLock(active = true) {
  useEffect(() => {
    if (!active) return undefined

    if (openLocks === 0) pageOverflow = document.body.style.overflow
    openLocks += 1
    document.body.style.overflow = 'hidden'

    return () => {
      openLocks -= 1
      if (openLocks === 0) document.body.style.overflow = pageOverflow
    }
  }, [active])
}
