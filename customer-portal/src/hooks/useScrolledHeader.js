import { useEffect, useState } from 'react'

/**
 * Where the bar stops being a wash and becomes a pane of glass.
 *
 * Not zero: a page that has moved by a single pixel should not flick a shadow
 * on, which reads as a flicker rather than a change of state. Eight is enough
 * that a real scroll has happened.
 */
const SCROLLED_AT = 8

/**
 * "Has the page moved?" — the state both headers share.
 *
 * The storefront's bar (`SiteHeader`) and the seller portal's (`SellerHeader`)
 * are the same bar with different destinations, and this is the half of that
 * claim a class name cannot make: the threshold, the passive listener and the
 * immediate read on mount are one behaviour, and two copies of `scrollY > 8`
 * is how the shop's bar and the seller's bar end up reacting to the same scroll
 * differently.
 *
 * Two details are load-bearing:
 *
 *  1. **It reads once on mount, not only on the next scroll.** The browser
 *     restores the scroll position on a reload, and a listener alone would leave
 *     a page opened halfway down wearing the un-scrolled bar until the customer
 *     moved it again.
 *  2. **`passive: true`.** This listener never calls `preventDefault`, and
 *     saying so lets the browser keep scrolling without waiting on JavaScript —
 *     which on a long catalogue is the difference between a smooth scroll and a
 *     stuttering one.
 */
export function useScrolledHeader() {
  const [scrolled, setScrolled] = useState(false)

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > SCROLLED_AT)
    onScroll()
    window.addEventListener('scroll', onScroll, { passive: true })
    return () => window.removeEventListener('scroll', onScroll)
  }, [])

  return scrolled
}
