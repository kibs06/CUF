import { Link } from 'react-router-dom'
import { ShoppingBag } from 'lucide-react'

import CountBadge from '../ui/CountBadge.jsx'
import { useCart } from '../../hooks/useCart.jsx'

/**
 * The header's cart button.
 *
 * The count is `cartCount` — UNITS, not lines — because that is what a customer
 * means by "3 things in my cart".
 *
 * The pill is `CountBadge`, shared with the seller's avatar and its two panel
 * rows; what is decided here is where it hangs (the button's top-right corner)
 * and that the link carries the number in its own `aria-label` — which is why the
 * badge is given no `label` and stays silent to a screen reader. The pop replays
 * whenever the count changes, and that is what makes adding to the cart from a
 * product page visible at all: the badge moving is the only confirmation that
 * something happened.
 *
 * It is a plain element with a CSS animation rather than an `AnimatePresence`
 * one, so the number is visible by default and the pop is purely additive — an
 * animation that does not run costs nothing. See "Animations must fail open" in
 * the README.
 */
export default function CartIconButton() {
  const { count } = useCart()

  return (
    <Link
      to="/cart"
      aria-label={count > 0 ? `Cart, ${count} items` : 'Cart, empty'}
      className="relative inline-flex h-10 w-10 items-center justify-center rounded-full border border-hairline text-muted-strong transition-colors duration-200 ease-out-cubic hover:border-card-edge hover:bg-subtle hover:text-ink"
    >
      <ShoppingBag size={18} strokeWidth={2} />

      <CountBadge count={count} className="absolute -right-1 -top-1" />
    </Link>
  )
}
