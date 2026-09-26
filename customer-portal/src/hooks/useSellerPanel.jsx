import { createContext, useCallback, useContext, useEffect, useMemo, useState } from 'react'
import { useLocation } from 'react-router-dom'

import {
  appliedPanelWidth,
  clampPanelWidth,
  isPanelDocked,
  normalizePanelId,
  normalizePanelState,
  normalizePanelWidth,
  panelMaxRem,
  serializePanelState,
} from '../lib/sellerPanelRules.js'
import useMediaQuery, { DOCKED_PANEL_QUERY } from './useMediaQuery.js'
import useViewportWidth from './useViewportWidth.js'

/**
 * Which side panel is open, whether it is pinned, and whether it is docked.
 *
 * One provider at the top of the seller shell, for two reasons that both matter:
 *
 *  1. **The state outlives a route.** A pinned panel is supposed to stay open
 *     while the seller moves from Orders to Products, so the state cannot live
 *     in the page it is drawn beside.
 *  2. **The control that opens it is not its parent.** The account menu's rows
 *     live inside the bar, the panel is drawn by the shell, and neither is the
 *     other's child — nor is the panel a child of the route that is open, which
 *     is the point: a pinned panel sits beside whichever page is showing.
 *
 * The state is `panel`, `pinned`, `width` and `expanded`, and all four are
 * written to `localStorage`, so a seller who pins the inbox finds it pinned
 * tomorrow on the same machine — see `normalizePanelState` for what is
 * remembered and what is deliberately not.
 *
 * ## Two widths, and only one of them is stored
 *
 * `width` is what the seller dragged to; `maxRem` is what this window will allow
 * — the fixed 40rem ceiling, or the 55%/92% share of the window that is smaller.
 * `panelWidth` is the one to draw at: the ceiling when expanded, the seller's own
 * width clamped to it otherwise. Keeping the choice and the ceiling apart is what
 * makes shrinking a window safe (`clampPanelWidth` is applied when drawing, never
 * when saving, so a panel widened on a big screen does not store a number that
 * breaks a small one) and what makes collapsing an expansion free (the seller's
 * width was never overwritten).
 *
 * ## Unpinned panels close on navigation
 *
 * A drawer that follows you from page to page is a drawer you did not ask to
 * keep. So the panel watches the pathname and closes itself when it changes —
 * unless it is pinned, at which point following you is the entire point.
 *
 * The shell renders *below* the router, so this hook runs inside a route and
 * `useLocation` is always available. It is not available to `sellerPanelRules`,
 * which is why the rule itself stays pure and the navigation effect lives here.
 */

const SellerPanelContext = createContext(null)

/** The key the pin is remembered under. */
export const SELLER_PANEL_STORAGE_KEY = 'cufmai:seller-panel'

function storageOrNull() {
  try {
    return globalThis.localStorage ?? null
  } catch {
    // A blocked storage throws on access, not on use.
    return null
  }
}

function readStoredPanelState() {
  const storage = storageOrNull()
  if (!storage) return normalizePanelState(null)

  try {
    return normalizePanelState(storage.getItem(SELLER_PANEL_STORAGE_KEY))
  } catch {
    return normalizePanelState(null)
  }
}

export function SellerPanelProvider({ children }) {
  const location = useLocation()
  const wide = useMediaQuery(DOCKED_PANEL_QUERY)
  const viewportWidth = useViewportWidth()
  const [state, setState] = useState(readStoredPanelState)

  /* Persist on every change. A full or blocked storage is not worth an error:
     the pin is a convenience, and the panel still works for this visit. */
  useEffect(() => {
    const storage = storageOrNull()
    if (!storage) return
    try {
      storage.setItem(SELLER_PANEL_STORAGE_KEY, serializePanelState(state))
    } catch {
      // Ignored on purpose — see above.
    }
  }, [state])

  /*
    Navigate away, lose the drawer. A no-op for a pinned panel *and* a no-op on
    the first render, because a state restored from storage is already in the
    shape it should be.
  */
  useEffect(() => {
    setState((current) => (!current.pinned && current.panel ? { ...current, panel: null } : current))
  }, [location.pathname])

  const open = useCallback((panel) => {
    const id = normalizePanelId(panel)
    if (!id) return
    setState((current) => ({ ...current, panel: id }))
  }, [])

  const close = useCallback(() => {
    // The pin outlives the panel: closing a docked panel and reopening it from
    // the bar should not silently turn it back into an overlay.
    setState((current) => ({ ...current, panel: null }))
  }, [])

  /** Open a panel, or close it if it is the one already showing. */
  const toggle = useCallback((panel) => {
    const id = normalizePanelId(panel)
    if (!id) return
    setState((current) => (current.panel === id ? { ...current, panel: null } : { ...current, panel: id }))
  }, [])

  const togglePin = useCallback(() => {
    setState((current) => ({ ...current, pinned: !current.pinned }))
  }, [])

  /*
    Resizing is the end of an expansion, not a separate width: a seller who drags
    the edge has just said how wide they want it, so `expanded` goes back to false
    and the drag's width is what the panel keeps.
  */
  const setWidth = useCallback((next) => {
    /*
      Normalized on the way in as well as on the way out. A drag hands over
      numbers like `22.318181818181817`, and while `normalizePanelState` would
      snap them back, storing the raw one means the number in `localStorage` is a
      number nothing else in the app has ever seen.
    */
    setState((current) => ({ ...current, width: normalizePanelWidth(next), expanded: false }))
  }, [])

  const toggleExpand = useCallback(() => {
    setState((current) => ({ ...current, expanded: !current.expanded }))
  }, [])

  /*
    The ceiling is the window's, and it is read here because this is the one
    place that knows both how the panel is drawn (docked or over the page) and
    how wide the window is. `docked` is computed from the media query rather than
    passed in, so the two numbers can never be about different layouts.
  */
  const docked = isPanelDocked({ panel: state.panel, pinned: state.pinned, wide })
  const maxRem = panelMaxRem(viewportWidth === null ? null : viewportWidth / 16, { docked })
  const panelWidth = appliedPanelWidth({
    width: state.width,
    expanded: state.expanded,
    maxRem,
  })

  const value = useMemo(
    () => ({
      panel: state.panel,
      pinned: state.pinned,
      docked,
      expanded: state.expanded,
      width: state.width,
      panelWidth,
      maxRem,
      open,
      close,
      toggle,
      togglePin,
      setWidth,
      toggleExpand,
    }),
    [
      state.panel,
      state.pinned,
      state.expanded,
      state.width,
      docked,
      panelWidth,
      maxRem,
      open,
      close,
      toggle,
      togglePin,
      setWidth,
      toggleExpand,
    ],
  )

  return <SellerPanelContext.Provider value={value}>{children}</SellerPanelContext.Provider>
}

/**
 * The panel's state — which one is open, whether it is pinned, how wide it is —
 * for the controls that open it and the shell that draws it.
 *
 * `panelWidth` is the number to draw at and `width` is the seller's own; a
 * caller that resizes wants the first to clamp from and the second to remember.
 *
 * Throws outside the provider rather than returning a default, because every
 * caller here is a control that would otherwise be a button that does nothing:
 * a bar icon that silently fails to open anything is a bug that hides itself.
 */
export function useSellerPanel() {
  const context = useContext(SellerPanelContext)
  if (!context) throw new Error('useSellerPanel must be used inside a SellerPanelProvider')
  return context
}
