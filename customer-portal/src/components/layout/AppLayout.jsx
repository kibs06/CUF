import { Navigate, Outlet, useLocation } from 'react-router-dom'

import ErrorBoundary from '../ErrorBoundary'
import PageTransition from '../motion/PageTransition'
import SiteFooter from './SiteFooter'
import SiteHeader from './SiteHeader'
import { useAuth } from '../../hooks/useAuth.jsx'
import { isApprovedSeller } from '../../lib/sellerRules.js'

/**
 * The shell every customer route renders inside.
 *
 * There is no `AnimatePresence` here any more, deliberately. It was used to
 * cross-fade one page out before the next came in, and it could stop doing that
 * halfway and leave `<main>` empty forever — see `PageTransition` for what was
 * happening and why it is now a CSS entrance. The route still carries a `key`:
 * that is what remounts the wrapper (and so replays the entrance, and clears
 * the error boundary) when the customer moves to a different page.
 *
 * The key is `pathname`, NOT the full location: searching or changing a filter
 * rewrites the query string on the *same* page, and keying on the whole URL
 * would throw a page transition over every keystroke.
 *
 * The footer is the one part of the shell that is not global: it renders on the
 * landing page only. See below.
 *
 * ## Why the seller redirect lives here
 *
 * **The shop is closed to sellers.** A seller's account is for selling, and the
 * catalog, the makers gallery and the shopping flow are not their side of the
 * marketplace — a seller who can browse is a seller who can put their own stock
 * in a cart, which is a support ticket rather than a feature.
 *
 * This component is the right place for that rule because it is the single point
 * every customer route passes through: the home page, the catalog, a product
 * page, the cart, checkout, sign-in and the account pages all render inside
 * `AppLayout`, and the seller portal deliberately does not. One check here closes
 * all of them at once and cannot be forgotten by the next customer route someone
 * adds — which the alternative, a redirect on each page, certainly would be.
 *
 * Two details are load-bearing:
 *
 *  1. **`!loading`.** The profile is unknown for the first moment of every page
 *     load, and redirecting on "not yet known" would bounce a signed-in customer
 *     to the sign-in page every time they reloaded. Redirecting only once the
 *     answer has arrived costs a seller a brief glimpse of the shop on a cold
 *     load of a customer URL, which is the honest failure of the two.
 *  2. **Approved sellers only, via `isApprovedSeller`.** A `pending` or
 *     `rejected` applicant is *not* redirected: they have no portal to be sent
 *     to (the gate shows them a waiting page), and taking away the storefront
 *     from someone whose application is still being read would leave them with
 *     nothing at all to look at.
 *
 * Sellers reach their own account page at `/seller/account`, which is why this
 * can close `/settings` too without stranding them.
 */
export default function AppLayout() {
  const location = useLocation()
  const { profile, loading } = useAuth()

  if (!loading && isApprovedSeller(profile)) {
    return <Navigate to="/seller" replace />
  }

  /*
    Home is the page the logo leads to, and the only page that is an
    introduction rather than a task. The footer is the association's closing
    statement — who the makers are, that the prices are in pesos, that an
    artisan ships the pair — which is the right thing to read after the
    landing page and the wrong thing to scroll past on the way to a catalogue,
    a product, a cart or a receipt. Those pages end at the thing the customer
    came for, and both links the footer offers are already in the header.
  */
  const isHome = location.pathname === '/'

  return (
    <div className="flex min-h-dvh flex-col bg-page">
      <SiteHeader />
      <main className="flex-1">
        <PageTransition key={location.pathname}>
          <ErrorBoundary key={location.pathname}>
            <Outlet />
          </ErrorBoundary>
        </PageTransition>
      </main>
      {isHome && <SiteFooter />}
    </div>
  )
}
