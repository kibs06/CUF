import { createContext, useCallback, useContext, useMemo, useRef, useState } from 'react'
import { CheckCircle2 } from 'lucide-react'

import NotificationToaster from '../components/notifications/NotificationToaster.jsx'

/**
 * The seller portal's confirmation cards — "Product added", "Product updated" —
 * the ones a write puts in the corner so the seller is told it landed.
 *
 * ## Why a provider in the shell, and not the form's own state
 *
 * A save is followed by a navigation. Creating a product lands on that product's
 * page (the photos a new pair is missing can only be uploaded once the row
 * exists), so a card owned by the form would be unmounted — and its animation
 * cut off — by the very save that raised it. The shell is the one component on
 * every seller page and it outlives a route change, which is the same reason the
 * store query and the side panel's state live there.
 *
 * ## Why the bottom right, when the seller's notifications are bottom left
 *
 * `SellerNotificationToaster` deliberately took the left corner because the
 * seller's notifications and the docked side panel are the same subject seen
 * twice. That reasoning is about *those* cards. A save confirmation has no panel
 * beside it and no feed entry behind it, so it does not need to sit next to
 * anything — it takes the free corner. The one caveat is the docked panel, which
 * is a flex sibling on the right; a card in this corner floats over its lower
 * edge while it is open. That is a card about something the panel is not showing,
 * it is dismissible, and it leaves on its own.
 *
 * ## It shows one card at a time, and it only ever tells
 *
 * `NotificationToaster` owns the queue, the entrance and exit animation, the
 * reduced-motion collapse and the `aria-live` slot. This provider owns only what
 * a confirmation needs on top of that: an id per card, the check mark, and how
 * long it stays.
 *
 * The card has no button on it, deliberately. A save navigates — the seller
 * lands on their products — so the destination the card would have offered is
 * already on screen behind it, and a button that navigates to the page you are
 * looking at is a control that does nothing visible. The card's whole job is the
 * sentence.
 */

const SellerFlashContext = createContext(null)

/**
 * How long a confirmation card stays before it slides back out.
 *
 * The notification centre's own six seconds, because there is nothing to reach
 * for on this card: two short lines, no button, and the list it is about is
 * already drawn underneath it.
 */
export const FLASH_VISIBLE_MS = 6000

/** Where the seller's own cards sit — see the note above about the left corner. */
export const FLASH_POSITION = 'bottom-right'

export function SellerFlashProvider({ children }) {
  const [items, setItems] = useState([])
  const nextId = useRef(0)

  const flash = useCallback((item) => {
    const id = `seller-flash-${nextId.current++}`
    setItems((current) => [...current, { id, Icon: CheckCircle2, ...item }])
  }, [])

  const value = useMemo(() => ({ flash }), [flash])

  return (
    <SellerFlashContext.Provider value={value}>
      {children}
      {/*
        Outside whatever `children` drew, for the same reason the shell puts the
        notification centre outside `<main>`: a card that is part of the page's
        layout is a card a page can clip or shift.
      */}
      <NotificationToaster
        items={items}
        position={FLASH_POSITION}
        visibleMs={FLASH_VISIBLE_MS}
        /*
          In from the right edge, because this card is anchored to the right
          corner: a rise from the bottom of a right-hand card reads as coming
          from below it, and the card that just confirmed a save should read as
          arriving from the side of the page it belongs to.
        */
        slideFrom="right"
      />
    </SellerFlashContext.Provider>
  )
}

/**
 * Raise a confirmation card.
 *
 * Throws outside the provider rather than returning a no-op, the same as
 * `useSellerPanel`: every caller is a save that has just happened, and a save
 * that silently confirms nothing is a bug that hides itself.
 */
export function useSellerFlash() {
  const context = useContext(SellerFlashContext)
  if (!context) throw new Error('useSellerFlash must be used inside a SellerFlashProvider')
  return context
}
