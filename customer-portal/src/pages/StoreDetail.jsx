import { Link, useLocation, useNavigate, useParams } from 'react-router-dom'
import { ArrowLeft, Loader2, MapPin, MessageSquare, PackageOpen } from 'lucide-react'

import ProductGrid from '../components/product/ProductGrid'
import EmptyState from '../components/ui/EmptyState'
import Reveal from '../components/ui/Reveal'
import { ProductGridSkeleton } from '../components/ui/Skeleton'
import StoreAvatar from '../components/ui/StoreAvatar'
import { useAuth } from '../hooks/useAuth.jsx'
import { useProducts, useStore } from '../hooks/useCatalog'
import { useMessageActions } from '../hooks/useMessages.js'
import { pluralize, storeColor } from '../lib/constants'

/**
 * One maker's shop.
 *
 * The header is painted with the store's OWN colour, which is the same
 * `brand_color` the Flutter app uses for its store pages. A customer who found
 * a shop on their phone should recognise it here immediately — that continuity
 * is worth more than a uniform template, and it costs one gradient.
 *
 * ## "Message the maker"
 *
 * The button finds or creates the customer's one thread with this workshop and
 * takes them to it. This page is public, so a signed-out visitor is sent to
 * sign-in with a `from` pointing back here rather than being told "sign in" and
 * left to find their way — the same thing `RequireAuth` does for a gated route,
 * done inline because the page itself is not gated.
 */
export default function StoreDetail() {
  const { storeId } = useParams()
  const navigate = useNavigate()
  const location = useLocation()
  const { isSignedIn } = useAuth()
  const storeQuery = useStore(storeId)
  const productsQuery = useProducts({ storeId })
  const { start } = useMessageActions()

  const onMessage = async () => {
    if (!isSignedIn) {
      navigate('/signin', { state: { from: location.pathname } })
      return
    }
    const conversationId = await start.mutateAsync({ storeId })
    if (conversationId) navigate(`/messages/${conversationId}`)
  }

  const store = storeQuery.data
  const products = productsQuery.data ?? []
  const color = storeColor(store)

  if (storeQuery.isLoading) {
    return (
      <div className="mx-auto max-w-7xl px-4 py-10 sm:px-6 lg:px-8">
        <div className="shimmer h-44 rounded-premium" />
        <div className="mt-10">
          <ProductGridSkeleton count={8} />
        </div>
      </div>
    )
  }

  if (!store) {
    return (
      <div className="mx-auto max-w-3xl px-4 py-20 sm:px-6">
        <EmptyState
          Icon={PackageOpen}
          title="This store is not available"
          description="It may have been closed, or the link may be out of date."
          action={
            <Link to="/makers" className="btn btn-outline">
              See all makers
            </Link>
          }
        />
      </div>
    )
  }

  return (
    <>
      <header className="relative overflow-hidden border-b border-hairline">
        {/* The store's colour, washed across a soft band. */}
        <div
          aria-hidden="true"
          className="absolute inset-0"
          style={{
            background: `linear-gradient(135deg, ${color}22 0%, ${color}0A 45%, transparent 100%)`,
          }}
        />

        <div className="relative mx-auto max-w-7xl px-4 py-12 sm:px-6 sm:py-16 lg:px-8">
          <Link
            to="/makers"
            className="group inline-flex items-center gap-1.5 text-xs font-semibold text-muted transition-colors duration-200 hover:text-clay-ink"
          >
            <ArrowLeft
              size={14}
              strokeWidth={2.5}
              className="transition-transform duration-300 ease-out-cubic group-hover:-translate-x-0.5"
            />
            All makers
          </Link>

          <div className="mt-7 flex flex-col gap-6 sm:flex-row sm:items-start">
            <StoreAvatar store={store} size={84} />

            <div className="min-w-0 flex-1">
              <h1 className="font-display text-3xl font-semibold text-ink sm:text-4xl">
                {store.name}
              </h1>
              {store.tagline && (
                <p className="mt-2 text-base text-muted-strong">
                  {store.tagline}
                </p>
              )}

              <div className="mt-4 flex flex-wrap items-center gap-x-5 gap-y-2 text-sm text-muted">
                {store.location && (
                  <span className="inline-flex items-center gap-1.5">
                    <MapPin size={14} strokeWidth={2} />
                    {store.location}
                  </span>
                )}
                {!productsQuery.isLoading && (
                  <span>{pluralize(products.length, 'pair')} available</span>
                )}
              </div>

              {store.description && (
                <p className="mt-5 max-w-3xl text-sm leading-relaxed text-muted">
                  {store.description}
                </p>
              )}

              {/*
                The one action a customer wants from a maker's page that is not
                "buy something": a question. It is a button rather than a form,
                because the answer belongs in the thread — length, colour and
                lead time are exactly the things a chat is for.
              */}
              <button
                type="button"
                onClick={onMessage}
                disabled={start.isPending}
                className="btn btn-primary mt-6 disabled:cursor-not-allowed disabled:opacity-70"
              >
                {start.isPending ? (
                  <Loader2 size={16} strokeWidth={2} className="animate-spin" />
                ) : (
                  <MessageSquare size={16} strokeWidth={2} />
                )}
                {start.isPending ? 'Opening…' : 'Message the maker'}
              </button>
            </div>
          </div>
        </div>
      </header>

      <div className="mx-auto max-w-7xl px-4 py-12 sm:px-6 lg:px-8">
        <Reveal>
          <h2 className="font-display text-2xl font-semibold text-ink">
            From this workshop
          </h2>
        </Reveal>

        <div className="mt-8">
          {productsQuery.isLoading ? (
            <ProductGridSkeleton count={8} />
          ) : products.length > 0 ? (
            <ProductGrid products={products} />
          ) : (
            <EmptyState
              Icon={PackageOpen}
              title="Nothing in stock right now"
              description="This workshop has no products published at the moment. Check back soon."
            />
          )}
        </div>
      </div>
    </>
  )
}
