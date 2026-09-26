import { useState } from 'react'
import { Link, NavLink, useNavigate } from 'react-router-dom'

import AccountMenu from './AccountMenu'
import CartIconButton from '../cart/CartIconButton'
import SearchField from '../search/SearchField'
import { navLinkClass } from './navLinkClass.js'
import { useScrolledHeader } from '../../hooks/useScrolledHeader.js'

const NAV_LINKS = [
  { to: '/shop', label: 'Shop' },
  { to: '/makers', label: 'Makers' },
]

/*
  There is deliberately no "Seller" link here.

  There was one, briefly, and it is gone because it could never be clicked: this
  header only renders inside `AppLayout`, and `AppLayout` sends an approved
  seller straight to `/seller`. A seller therefore never sees this bar, and a
  link to the portal on a bar they cannot see is not a shortcut — it is dead
  code that reads like a feature. Sellers reach their portal by signing in.
*/

/**
 * The site header.
 *
 * Three behaviours are worth naming:
 *
 *  1. **The backdrop firms up on scroll.** At the top the header is a
 *     transparent wash over the hero; once the page moves it gains a blur, a
 *     hairline and a shadow. The transition is what makes the page feel like it
 *     is sliding *under* a fixed pane of glass rather than colliding with a bar.
 *     See `useScrolledHeader`, which the seller portal's bar shares — one
 *     threshold for both, so they cannot react to a scroll differently.
 *
 *  2. **Search is one control at every size**, in `SearchField`: a 40px pill
 *     that opens into the field (and its suggestion panel) when clicked, or on
 *     `⌘K`. There used to be two mechanisms — an always-visible field on desktop
 *     and a separate expanding row below `md` — which is why the panel below
 *     `md` had no suggestions: that row animated its own `max-height` and was
 *     `overflow-hidden`, so a dropdown inside it would have been clipped.
 *     One control means one behaviour everywhere, and the phone gets the same
 *     suggestions the desktop has.
 *
 *  3. **An open pill takes the row below `md`.** This is the part that costs
 *     something: on a 390px screen the logo, the nav and the buttons leave
 *     while the field is open, because a field *and* a header does not fit
 *     (`max-md:hidden` on each). It is the same barber's-pole the app's
 *     full-screen search page uses, and it is undone the moment the pill
 *     closes — Escape, a click outside, or running the search.
 *
 * From `lg` up the bar is a **three-track grid** — `1fr auto 1fr` — so the
 * search sits in the middle of the header rather than in whatever space the nav
 * left over. Two things follow from that, and both are why the grid is `lg`
 * only: the tracks either side are equal only while their contents fit, and a
 * 288px pill in the middle needs the room that a 768px bar does not have. So
 * below `lg` the row is still a flex row with the pill on the right, and an open
 * pill takes the row.
 *
 * Below `lg` the slack lives to the *right of the nav* (`max-lg:mr-auto`), not
 * in front of the search: with it in front, collapsing the pill 248px would
 * slide the cart and the account button across the bar on every open and close.
 */
export default function SiteHeader() {
  const navigate = useNavigate()
  const [searchExpanded, setSearchExpanded] = useState(false)
  const scrolled = useScrolledHeader()

  const submitSearch = (term) => {
    navigate(term ? `/shop?q=${encodeURIComponent(term)}` : '/shop')
  }

  /* Below `lg`, an open search takes the row: these are the things it takes it
     from. `max-lg:hidden` rather than a JS breakpoint, so the rule is the same
     one the rest of the header uses. */
  const yieldsToSearch = searchExpanded ? 'max-lg:hidden' : ''

  return (
    <header
      className={`sticky top-0 z-50 border-b transition-[background-color,border-color,box-shadow] duration-300 ease-out-cubic ${
        scrolled
          ? 'border-hairline bg-page/85 shadow-warm backdrop-blur-md'
          : 'border-transparent bg-page/60 backdrop-blur-sm'
      }`}
    >
      <div className="mx-auto flex h-16 max-w-7xl items-center gap-3 px-4 sm:px-6 lg:grid lg:grid-cols-[1fr_auto_1fr] lg:px-8">
        {/*
          Track one: who we are and where you can go.

          `shrink-0`, because a group compressed below its own text does not get
          narrower — it overlaps the search: the nav's box ends at 167px while
          its links still reach 187px, which is two controls on top of each
          other. Below ~340px the header is a few pixels short of room and
          overflows honestly instead. Above that width there is room to spare.
        */}
        <div className={`flex shrink-0 items-center gap-3 max-lg:mr-auto ${yieldsToSearch}`}>
        <Link
          to="/"
          className="group flex shrink-0 items-center gap-2.5"
          aria-label="CUFMAI — home"
        >
          {/*
            Two files, one shown per theme. The mark is an espresso tile with a
            sand symbol in it, and an espresso tile on a #111111 page is a
            square of almost the same colour — so dark swaps the two fills
            (cream tile, espresso symbol) rather than inverting the artwork,
            which would tint the brand blue.

            The tile is *shown* in both files, and that is load-bearing: hide it
            and the bare sand symbol is 1.74:1 against this bar on a light page,
            and 1.08:1 against the dark one. With the tile the same 32px mark
            measures 8.9:1 light and 14.9:1 dark.
          */}
          <img
            src="/logo.svg"
            alt=""
            className="h-8 w-8 transition-transform duration-300 ease-out-cubic group-hover:scale-105 dark:hidden"
          />
          <img
            src="/logo-dark.svg"
            alt=""
            className="hidden h-8 w-8 transition-transform duration-300 ease-out-cubic group-hover:scale-105 dark:block"
          />
          {/*
            The wordmark goes below `sm`, the mark stays. The mark is the brand
            and the wordmark is the courtesy, and on a 390px bar the courtesy
            is what pushes the nav into the search: the header's own row needed
            `422px` of content in a 390px viewport before this, which is why
            every page scrolled sideways on a phone.
          */}
          <span className="font-display text-lg font-semibold tracking-tight text-ink max-sm:hidden">
            CUFMAI
          </span>
        </Link>

        <nav className="ml-3 flex items-center gap-0.5" aria-label="Main">
          {NAV_LINKS.map((link) => (
            <NavLink key={link.to} to={link.to} className={navLinkClass}>
              {link.label}
            </NavLink>
          ))}
        </nav>

        </div>

        {/* Track two: the pill, the field and the suggestion panel — the middle
            of the bar from `lg` up. See `SearchField`. */}
        <SearchField
          id="header-search"
          placeholder="Search shoes, sandals, makers…"
          onSubmit={submitSearch}
          onExpandedChange={setSearchExpanded}
        />

        {/* Track three: the customer's own things, pinned right. */}
        <div className={`flex shrink-0 items-center justify-end gap-2 ${yieldsToSearch}`}>
          <CartIconButton />
          <AccountMenu />
        </div>
      </div>

    </header>
  )
}
