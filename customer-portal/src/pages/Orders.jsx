import { Link, useSearchParams } from 'react-router-dom'
import { motion } from 'motion/react'
import { PackageSearch } from 'lucide-react'

import EmptyState from '../components/ui/EmptyState'
import Reveal from '../components/ui/Reveal'
import OrderCard from '../components/orders/OrderCard'
import { OrderCardSkeleton } from '../components/ui/Skeleton'
import { fadeUp, staggerChildren } from '../components/motion/transitions'
import { useMyOrders } from '../hooks/useOrders.js'
import {
  availableOrderFilters,
  filterOrders,
  sortOrders,
} from '../lib/orders'

/**
 * The order history.
 *
 * ## Why the filter lives in the URL
 *
 * `?status=ready` rather than `useState`, for two reasons that are both about
 * the customer: the browser's back button returns them to the tab they were on
 * instead of the whole page, and a link they paste to a friend — or to
 * themselves — opens on the same view. State that only exists in memory makes a
 * filter feel like a detour.
 *
 * ## Why the tabs come from the data
 *
 * `availableOrderFilters` drops a tab with nothing behind it. A "Ready" tab
 * that opens onto an empty list is the interface telling the customer they have
 * lost something.
 */
export default function Orders() {
  const [params, setParams] = useSearchParams()
  const { data: orders, isLoading, isError, error, refetch } = useMyOrders()

  const list = sortOrders(orders ?? [])
  const filters = availableOrderFilters(list)

  const requested = params.get('status') ?? 'all'
  // An unknown or now-empty value falls back to the full list rather than
  // rendering nothing: a stale bookmarked `?status=shipped` must still show the
  // customer their orders.
  const active = filters.some((filter) => filter.id === requested)
    ? requested
    : 'all'
  const visible = filterOrders(list, active)

  const select = (id) => {
    const next = new URLSearchParams(params)
    if (id === 'all') next.delete('status')
    else next.set('status', id)
    setParams(next, { replace: true })
  }

  return (
    <div className="mx-auto max-w-4xl px-4 py-10 sm:px-6 lg:px-8">
      <header>
        <p className="overline">Your account</p>
        <h1 className="mt-2 font-display text-3xl font-semibold text-ink sm:text-4xl">
          Your orders
        </h1>
        <p className="mt-2 max-w-xl text-sm leading-relaxed text-muted">
          The same orders as the CUFMAI app — whatever you buy here shows up
          there too.
        </p>
      </header>

      {isLoading && (
        <div className="mt-8 space-y-4">
          {Array.from({ length: 3 }).map((_, index) => (
            <OrderCardSkeleton key={index} />
          ))}
        </div>
      )}

      {isError && (
        <div
          role="alert"
          className="mt-8 rounded-field border border-crimson/30 bg-crimson/[0.07] px-4 py-3 text-sm text-ink"
        >
          <p className="font-semibold">We could not load your orders.</p>
          <p className="mt-1 text-xs leading-relaxed text-muted-strong">
            {error?.message ?? 'Please check your connection and try again.'}
          </p>
          <button
            type="button"
            onClick={() => refetch()}
            className="mt-3 text-xs font-semibold text-crimson underline-offset-4 hover:underline"
          >
            Try again
          </button>
        </div>
      )}

      {!isLoading && !isError && list.length === 0 && (
        <div className="mt-8">
          <EmptyState
            Icon={PackageSearch}
            title="No orders yet"
            description="When you order a pair from one of the makers, it will appear here with everything that happens to it."
            action={
              <Link to="/shop" className="btn btn-primary">
                Browse the catalog
              </Link>
            }
          />
        </div>
      )}

      {!isLoading && !isError && list.length > 0 && (
        <>
          {filters.length > 1 && (
            <div className="mt-8 flex flex-wrap gap-2" role="tablist" aria-label="Filter orders">
              {filters.map((filter) => {
                const here = filter.id === active
                const count = filterOrders(list, filter.id).length

                return (
                  <button
                    key={filter.id}
                    type="button"
                    role="tab"
                    aria-selected={here}
                    onClick={() => select(filter.id)}
                    className={`inline-flex items-center gap-2 rounded-full border px-4 py-2 text-xs font-semibold transition-[background-color,border-color,color] duration-200 ease-out-cubic ${
                      here
                        ? 'border-clay bg-clay text-ink-inverse'
                        : 'border-hairline bg-raised text-muted-strong hover:border-card-edge hover:text-ink'
                    }`}
                  >
                    {filter.label}
                    <span
                      className={`num text-[10px] ${
                        here ? 'text-ink-inverse/75' : 'text-muted/70'
                      }`}
                    >
                      {count}
                    </span>
                  </button>
                )
              })}
            </div>
          )}

          <motion.ul
            key={active}
            variants={staggerChildren(0.04)}
            initial="hidden"
            animate="show"
            className="mt-6 space-y-4"
          >
            {visible.map((order) => (
              <motion.li key={order.id} variants={fadeUp}>
                <OrderCard order={order} />
              </motion.li>
            ))}
          </motion.ul>

          {visible.length === 0 && (
            <Reveal className="mt-6">
              <p className="rounded-card border border-hairline bg-subtle/60 px-6 py-10 text-center text-sm text-muted">
                Nothing in this group right now.
              </p>
            </Reveal>
          )}
        </>
      )}
    </div>
  )
}
