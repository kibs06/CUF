import { Link, NavLink } from 'react-router-dom'

import SellerAccountMenu from './SellerAccountMenu.jsx'
import { navLinkClass } from '../layout/navLinkClass.js'
import { useScrolledHeader } from '../../hooks/useScrolledHeader.js'

/*
  Five destinations, and deliberately not a sixth for the account.

  `/seller/account` is still reachable from the bar — through the avatar on the
  right, which is where every other site puts the signed-in person — but it is
  not a pill here, because "Account" is not a place in the portal the way Orders
  and Products are: it is who is signed in. See `SellerAccountMenu`.
*/
const NAV_ITEMS = [
  { to: '/seller', label: 'Dashboard', end: true },
  { to: '/seller/orders', label: 'Orders' },
  { to: '/seller/products', label: 'Products' },
  { to: '/seller/store', label: 'Storefront' },
  { to: '/seller/reports', label: 'Reports' },
]

/**
 * The seller portal's bar.
 *
 * It is the storefront's header — same sticky blur, same hairline, same 64px
 * row, same 7xl container, same pill for the current page — with the seller's
 * destinations in it instead of Shop and Makers. That is not laziness: this
 * portal used to be a dark 240px sidebar, and a sidebar said the wrong thing.
 * The seller area is not a different product bolted to the side of the shop, it
 * is the same site with a different job, and the customer who becomes a seller
 * should recognise the furniture. The seller's own accent (`rust`) is still on
 * every *figure* they read; the chrome is the site's, so the two portals cannot
 * drift into looking like two brands.
 *
 * Four decisions inside the bar:
 *
 *  1. **The store's name sits where the wordmark does.** A seller with one store
 *     does not need telling which portal they are in — they need reminding which
 *     storefront they are editing, which is the mistake that matters. The logo
 *     tile stays, because it is what makes the bar recognisable as this site.
 *  2. **The logo leads to `/seller`, not `/`.** The storefront's mark leads home;
 *     a seller's home is their dashboard, and `/` would answer with the redirect
 *     in `AppLayout`. A logo that hands you to a redirect is a control that does
 *     nothing.
 *  3. **No search and no cart.** Both are shop things — a seller browsing their
 *     own catalogue can put their own stock in a cart, and that is a support
 *     ticket, not a feature.
 *  4. **The signed-in seller is a face, not a word.** The shop's right-hand
 *     space is a cart and an avatar; here it is the avatar alone — the seller's
 *     own photo, or their initials — and it opens the panel holding the account
 *     page and Sign out. It replaces an "Account" pill that used to sit in the
 *     nav, and it is the shop's own `AccountMenu` in everything but its rows,
 *     for the reason the two bars share a look at all.
 *
 *     The customer `AccountMenu` could not simply be reused: three of its five
 *     rows (`/account`, `/messages`, `/settings`) are answers `AppLayout`
 *     bounces a seller out of, and `/messages` reads `conversations.customer_id`,
 *     so a seller's inbox would render empty. `SellerAccountMenu` keeps the
 *     control and drops the dead links; see its own docblock for what is left.
 *  5. **The alerts are not in the bar.** Notifications and Messages live in the
 *     avatar's own panel, as two rows with their unread counts, and each opens a
 *     drawer on the right of the page rather than navigating — a seller checking
 *     what came in is doing it *from* the order they were reading, and a
 *     navigation throws that away. They were icon buttons here first, twice, and
 *     both times they lost the argument: beside five pills and a face on a 64px
 *     row they are three controls whose meaning is a tooltip, and a bell next to
 *     an inbox next to a person is a lot of 40px circles for two things that are
 *     both "someone is waiting on you". The menu is one click away on every page
 *     and the counts are the first thing in it. See `SellerAccountMenu` and
 *     `SellerSidePanel`.
 *
 * ## Below `lg` the nav is a second row inside the same header
 * *
 * Two reasons, both about honesty rather than taste. Five destinations next to a
 * logo and a 40px avatar do not fit on a phone at any padding, and the usual
 * answer — a hamburger — hides the entire map of the portal behind a tap, which
 * is the one thing a nav exists to prevent. A row that scrolls sideways keeps
 * every destination one gesture away and keeps the work full width below it.
 */
export default function SellerHeader({ storeName, storeId, onSignOut }) {
  const scrolled = useScrolledHeader()

  return (
    <header
      className={`sticky top-0 z-50 border-b transition-[background-color,border-color,box-shadow] duration-300 ease-out-cubic ${
        scrolled
          ? 'border-hairline bg-page/85 shadow-warm backdrop-blur-md'
          : 'border-transparent bg-page/60 backdrop-blur-sm'
      }`}
    >
      <div className="mx-auto flex h-16 max-w-7xl items-center gap-3 px-4 sm:px-6 lg:px-8">
        <Link
          to="/seller"
          className="group flex min-w-0 items-center gap-2.5"
          aria-label="Your seller dashboard"
        >
          {/* Two files, one per theme, exactly as the storefront swaps them: the
              tile is what carries the mark on a dark page. */}
          <img
            src="/logo.svg"
            alt=""
            className="h-8 w-8 shrink-0 transition-transform duration-300 ease-out-cubic group-hover:scale-105 dark:hidden"
          />
          <img
            src="/logo-dark.svg"
            alt=""
            className="hidden h-8 w-8 shrink-0 transition-transform duration-300 ease-out-cubic group-hover:scale-105 dark:block"
          />
          <span className="min-w-0 truncate font-display text-lg font-semibold tracking-tight text-ink">
            {storeName}
          </span>
        </Link>

        {/* From `lg` up, the destinations share the row with the logo. */}
        <nav aria-label="Seller" className="ml-2 hidden items-center gap-0.5 lg:flex">
          <SellerNavLinks />
        </nav>

        <div className="ml-auto flex shrink-0 items-center gap-2">
          <SellerAccountMenu storeId={storeId} onSignOut={onSignOut} />
        </div>
      </div>

      {/* Below `lg`, the same destinations, one row down and scrolling if they
          have to. `overflow-x-auto` rather than a wrap: a wrapped nav turns the
          header's height into something a page has to be right about. */}
      <div className="border-t border-hairline-soft lg:hidden">
        <nav
          aria-label="Seller"
          className="flex gap-1 overflow-x-auto px-4 py-2 sm:px-6"
        >
          <SellerNavLinks />
        </nav>
      </div>
    </header>
  )
}

/**
 * The five destinations, rendered twice — once in the row and once in the
 * strip below it — from one list, so the two can only ever differ in layout.
 * Only one copy is ever displayed, so only one is ever in the accessibility
 * tree.
 */
function SellerNavLinks() {
  return NAV_ITEMS.map((item) => (
    <NavLink
      key={item.to}
      to={item.to}
      end={item.end}
      className={navLinkClass}
    >
      {item.label}
    </NavLink>
  ))
}
