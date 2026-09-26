import { Link } from 'react-router-dom'
import { Banknote, Truck } from 'lucide-react'

/**
 * The footer.
 *
 * Its real job is to say who the sellers are. CUFMAI is an association, not a
 * store — the customer is buying from artisans in Carcar City, and the
 * storefront should not hide that behind a generic "About us" link.
 *
 * Two structural choices worth naming, because a footer is the easiest thing on
 * a site to make look like an afterthought:
 *
 *  1. **The columns are weighted, not equal.** The brand block takes five of
 *     twelve columns; the three link lists share the rest. Four equal columns
 *     would give the two-link "Shop" list the same width as the paragraph that
 *     explains what CUFMAI is, which is how a footer ends up full of white
 *     space with a ragged right edge.
 *
 *  2. **"Good to know" is not a link list.** It is the two facts a customer
 *     wants before paying — the currency and who ships the parcel — so they
 *     carry icons and read as statements rather than as a column of links that
 *     go nowhere. The currency one matters most: ₱ prices and a Philippine
 *     address are the whole point of the line.
 */
export default function SiteFooter() {
  const year = new Date().getFullYear()

  return (
    <footer className="mt-20 border-t border-hairline bg-subtle/50">
      <div className="mx-auto max-w-7xl px-4 py-12 sm:px-6 lg:px-8">
        <div className="grid gap-10 sm:grid-cols-2 lg:grid-cols-12 lg:gap-8">
          <div className="sm:col-span-2 lg:col-span-5">
            <div className="flex items-center gap-2.5">
              <img src="/logo.svg" alt="" className="h-8 w-8 dark:hidden" />
              <img src="/logo-dark.svg" alt="" className="hidden h-8 w-8 dark:block" />
              <span className="font-display text-lg font-semibold tracking-tight text-ink">
                CUFMAI
              </span>
            </div>
            <p className="mt-4 max-w-md text-sm leading-relaxed text-muted">
              The official marketplace of the Carcar United Footwear
              Manufacturers Association, Inc. Handcrafted footwear, direct from
              the makers of Carcar City, Cebu — the footwear capital of the
              south.
            </p>
            <p className="mt-4 text-xs text-muted">
              Member workshops in Poblacion 3, Liburon and Valladolid.
            </p>
          </div>

          <nav aria-labelledby="footer-shop" className="lg:col-span-2">
            <h2 id="footer-shop" className="overline">
              Shop
            </h2>
            <ul className="mt-4 space-y-2.5 text-sm">
              <li>
                <Link
                  to="/shop"
                  className="text-muted-strong transition-colors duration-200 hover:text-clay-ink"
                >
                  All products
                </Link>
              </li>
              <li>
                <Link
                  to="/makers"
                  className="text-muted-strong transition-colors duration-200 hover:text-clay-ink"
                >
                  Meet the makers
                </Link>
              </li>
            </ul>
          </nav>

          {/*
            Real routes, and the same three the account menu offers: a customer
            who scrolled to the bottom of a page looking for their order should
            not have to scroll back up to the header for it. Every one of them
            sits behind `RequireAuth`, which turns an anonymous click into a
            sign-in prompt that returns here afterwards.
          */}
          <nav aria-labelledby="footer-account" className="lg:col-span-2">
            <h2 id="footer-account" className="overline">
              Your account
            </h2>
            <ul className="mt-4 space-y-2.5 text-sm">
              <li>
                <Link
                  to="/orders"
                  className="text-muted-strong transition-colors duration-200 hover:text-clay-ink"
                >
                  Your orders
                </Link>
              </li>
              <li>
                <Link
                  to="/settings/addresses"
                  className="text-muted-strong transition-colors duration-200 hover:text-clay-ink"
                >
                  Delivery addresses
                </Link>
              </li>
              <li>
                <Link
                  to="/settings"
                  className="text-muted-strong transition-colors duration-200 hover:text-clay-ink"
                >
                  Settings
                </Link>
              </li>
            </ul>
          </nav>

          <div className="lg:col-span-3">
            <h2 className="overline">Good to know</h2>
            <ul className="mt-4 space-y-3 text-sm text-muted-strong">
              <li className="flex items-start gap-2.5">
                <Banknote
                  size={15}
                  strokeWidth={2}
                  className="mt-0.5 shrink-0 text-clay-ink"
                />
                All prices in Philippine Peso (₱)
              </li>
              <li className="flex items-start gap-2.5">
                <Truck
                  size={15}
                  strokeWidth={2}
                  className="mt-0.5 shrink-0 text-clay-ink"
                />
                Sold and shipped by CUFMAI member artisans
              </li>
            </ul>
          </div>
        </div>

        <div className="mt-10 flex flex-col gap-3 border-t border-hairline pt-6 text-xs text-muted sm:flex-row sm:items-center sm:justify-between">
          <p>© {year} Carcar United Footwear Manufacturers Association, Inc.</p>
          <p>Carcar City, Cebu, Philippines</p>
        </div>
      </div>
    </footer>
  )
}
