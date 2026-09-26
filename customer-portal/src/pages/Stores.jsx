import { useMemo } from 'react'
import { Hammer, Store } from 'lucide-react'

import Reveal from '../components/ui/Reveal'
import EmptyState from '../components/ui/EmptyState'
import { StoreCardSkeleton } from '../components/ui/Skeleton'
import { SeasonalStoreCards } from '../components/stores/SeasonalStoreCards'
import { useProducts, useStores } from '../hooks/useCatalog'
import { ASSOCIATION_INTRO, pluralize } from '../lib/constants'
import { indexProductsByStore, totalPairs } from '../lib/storeIndexRules'

/**
 * The makers.
 *
 * This page is the marketplace's differentiator, not a directory: the thing
 * that makes CUFMAI worth buying from is that the seller is a named artisan in
 * a named barangay rather than an anonymous listing. So each panel leads with
 * the store's identity — its own colour, its own photograph, where it works —
 * and not with a product count.
 *
 * ## What a card shows, and why it is a port
 *
 * The app's Stores tab is a hero carousel: one workshop at a time, with its
 * rating, its product count and where it works. The portal shows all the
 * workshops at once — a page of real URLs has to be scannable — but the content
 * the app chose for a store is what makes a card read as a shop rather than a
 * business card, so it is ported (`storeIndexRules.js`): `★ rating · pairs ·
 * 📍 place`, straight off `StoreHeroCard`'s pill row, with the rating absent
 * until a store actually has one.
 *
 * The shape of the card is a port too — Lightswind UI's `SeasonalHoverCards`,
 * in `components/stores/SeasonalStoreCards.jsx`: a row of full-bleed photo
 * panels a third of the width that grow to two thirds on hover, holding the
 * description back until then. For a page whose whole argument is "the artisan
 * is the differentiator", a workshop's own storefront photograph says it in one
 * glance, which is why the maker's **banner** (`stores.banner_url`) is the panel
 * rather than a band above a product window.
 *
 * A store that has not been photographed is not a hole, and that is
 * `lib/storeBannerRules.js`: the app's brand gradient stands in for a missing
 * banner and for one that fails to load, so a workshop with no photograph still
 * gets a warm panel in its own colour. The store's `brand_color` also stays as
 * the rule across the top, which is what ties the photographed and the
 * unphotographed panels together.
 */
export default function Stores() {
  const storesQuery = useStores()
  const stores = storesQuery.data ?? []

  /*
    One extra query, and it is the one the whole site already shares: the
    catalog. It is what the counts and the page's own numbers come from, it is
    cached by every other surface, and `purchasableProducts` has already dropped
    anything that cannot be bought — so "5 pairs" means five pairs a customer can
    order right now.
  */
  const productsQuery = useProducts()
  const index = useMemo(
    () => indexProductsByStore(productsQuery.data ?? []),
    [productsQuery.data],
  )

  const pairs = totalPairs(index)

  return (
    <div className="mx-auto max-w-7xl px-4 py-10 sm:px-6 lg:px-8">
      <header className="max-w-2xl">
        <p className="overline">The Association</p>
        <h1 className="mt-2 font-display text-3xl font-semibold text-ink sm:text-4xl">
          Meet the makers
        </h1>
        {/* Shared with the home page's makers banner — see `ASSOCIATION_INTRO`,
            which is the one copy of this sentence. */}
        <p className="mt-4 text-sm leading-relaxed text-muted">
          {ASSOCIATION_INTRO}
        </p>
        {/* Counted from the live catalog, never a stored figure: the number has
            to be the shelf a customer can actually order from. */}
        {!storesQuery.isLoading && stores.length > 0 && (
          <p className="mt-3 text-xs text-muted">
            {pluralize(stores.length, 'workshop')}
            {pairs > 0 ? ` · ${pluralize(pairs, 'pair')}` : ''}
          </p>
        )}
      </header>

      <div className="mt-10">
        {storesQuery.isLoading ? (
          <div className="flex flex-wrap gap-5">
            {Array.from({ length: 3 }).map((_, index) => (
              <StoreCardSkeleton key={index} />
            ))}
          </div>
        ) : storesQuery.isError ? (
          <EmptyState
            Icon={Store}
            title="Could not load the makers"
            description="Please check your connection and try again."
          />
        ) : stores.length > 0 ? (
          <SeasonalStoreCards stores={stores} index={index} />
        ) : (
          <EmptyState
            Icon={Store}
            title="No makers are listed yet"
            description="Stores appear here as soon as their applications are approved."
          />
        )}
      </div>

      <Reveal className="mt-12">
        <div className="flex flex-col gap-4 rounded-card border border-hairline bg-raised p-6 shadow-card sm:flex-row sm:items-center sm:gap-5">
          <span
            aria-hidden="true"
            className="flex h-11 w-11 shrink-0 items-center justify-center rounded-full bg-clay/12 text-clay-ink"
          >
            <Hammer size={20} strokeWidth={2} />
          </span>
          <div className="min-w-0 flex-1">
            <p className="font-semibold text-ink">
              Are you a Carcar shoemaker?
            </p>
            <p className="mt-1 text-sm leading-relaxed text-muted">
              Seller registration happens in the CUFMAI app. Stores appear on
              this page as soon as their applications are approved.
            </p>
          </div>
        </div>
      </Reveal>
    </div>
  )
}
