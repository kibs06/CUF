import { useEffect, useMemo, useState } from 'react'
import { Link, useNavigate, useParams } from 'react-router-dom'
import { Footprints, ImageOff, Info, PackageOpen, Ruler, Truck } from 'lucide-react'

import Price from '../components/ui/Price'
import ProductGrid from '../components/product/ProductGrid'
import SaleBadge from '../components/ui/SaleBadge'
import EmptyState from '../components/ui/EmptyState'
import Reveal from '../components/ui/Reveal'
import { ProductGridSkeleton } from '../components/ui/Skeleton'
import StoreAvatar from '../components/ui/StoreAvatar'
import { DURATION, useTransitionTiming } from '../components/motion/transitions'
import { useAuth } from '../hooks/useAuth.jsx'
import { useCart } from '../hooks/useCart.jsx'
import { useMySize } from '../hooks/useMySize.js'
import { useProduct, useProducts, useStore } from '../hooks/useCatalog'
import { availableSizes, stockForSize } from '../lib/stock'
import { salePercent } from '../lib/pricing'
import { sizeAdvice } from '../lib/sizeMatchRules'

/**
 * One product.
 *
 * The gallery zooms toward the pointer rather than to the centre, and it is the
 * detail that makes a product page feel like a shop rather than a catalog:
 * pointing at the welt means seeing the welt. It is disabled under reduced
 * motion, where a 1.6× scale following the cursor is exactly the kind of
 * movement the preference is asking not to have.
 *
 * The page also answers the one question a size grid cannot: *is it in mine?* A
 * customer with a size on file gets one line under the grid, from
 * `sizeMatchRules.js` — the same rule the home shelf filters with, so the two
 * cannot disagree. It is deliberately the only size-aware thing here: the size
 * is **advice, not a selection**. This page requires a deliberate choice (the
 * buy button is disabled until one is made), and pre-selecting a size would
 * quietly reverse that — see the README.
 */
export default function ProductDetail() {
  const { productId } = useParams()
  const productQuery = useProduct(productId)
  const product = productQuery.data

  const storeQuery = useStore(product?.store_id)
  const storeProductsQuery = useProducts({ storeId: product?.store_id })

  const navigate = useNavigate()
  const { isSignedIn } = useAuth()
  const { addItem } = useCart()

  const [activeImage, setActiveImage] = useState(0)
  const [selectedSize, setSelectedSize] = useState(null)
  const [adding, setAdding] = useState(false)
  const [added, setAdded] = useState(false)
  const [addError, setAddError] = useState(null)

  // A new product is a new gallery and a new size to choose.
  useEffect(() => {
    setActiveImage(0)
    setSelectedSize(null)
    setAdded(false)
    setAddError(null)
  }, [productId])

  const images = product?.images ?? []

  const sizes = useMemo(() => (product ? availableSizes(product) : []), [product])

  const related = useMemo(
    () =>
      (storeProductsQuery.data ?? [])
        .filter((row) => row.id !== productId)
        .slice(0, 4),
    [storeProductsQuery.data, productId],
  )

  /*
    "My size" and what this product says about it. Both are derived, never
    fetched: the profile is already on hand, and a browse surface must not wait
    on a network call to say something it can already know.

    `mySize` is null for a signed-out visitor and for a customer who never gave
    a size — and `sizeAdvice` then returns null, so nothing renders. The draft
    rule the app follows (plan §8 R6): absent size, absent UI. No skeleton, no
    guess.
  */
  const mySize = useMySize()
  const advice = useMemo(
    () => (product ? sizeAdvice(product, mySize) : null),
    [product, mySize],
  )

  if (productQuery.isLoading) {
    return (
      <div className="mx-auto max-w-7xl px-4 py-10 sm:px-6 lg:px-8">
        <div className="grid gap-10 lg:grid-cols-2">
          <div className="shimmer aspect-square rounded-premium" />
          <div className="space-y-4 pt-4">
            <div className="shimmer h-6 w-1/3 rounded-lg" />
            <div className="shimmer h-10 w-3/4 rounded-lg" />
            <div className="shimmer h-8 w-1/4 rounded-lg" />
            <div className="shimmer h-28 w-full rounded-lg" />
          </div>
        </div>
      </div>
    )
  }

  if (!product) {
    return (
      <div className="mx-auto max-w-3xl px-4 py-20 sm:px-6">
        <EmptyState
          Icon={PackageOpen}
          title="This product is no longer available"
          description="It may have sold out, or the maker may have retired it."
          action={
            <Link to="/shop" className="btn btn-outline">
              Browse the catalog
            </Link>
          }
        />
      </div>
    )
  }

  const percent = salePercent(product)
  const selectedStock =
    selectedSize === null ? null : stockForSize(product, selectedSize)
  const soldOutEntirely = sizes.every((size) => stockForSize(product, size) <= 0)
  const needsSize = sizes.length > 0 && selectedSize === null

  /**
   * Add to cart.
   *
   * The size check happens before the sign-in check on purpose: a customer who
   * has not chosen a size should be told that, not sent to a sign-in page and
   * then still not have chosen one.
   *
   * The variant is resolved inside the cart provider, not here — one place, so
   * no screen can write a cart row with a null `variant_id`.
   */
  const onAddToCart = async () => {
    if (needsSize || soldOutEntirely) return

    if (!isSignedIn) {
      navigate('/signin', {
        state: { from: `/product/${productId}` },
      })
      return
    }

    setAdding(true)
    setAdded(false)
    setAddError(null)
    try {
      await addItem({ product, size: selectedSize, quantity: 1 })
      setAdded(true)
    } catch (error) {
      setAddError(
        error?.message === 'sign-in-required'
          ? 'Please sign in to add items to your cart.'
          : 'We could not add that to your cart. Please try again.',
      )
    } finally {
      setAdding(false)
    }
  }

  return (
    <>
      <div className="mx-auto max-w-7xl px-4 py-8 sm:px-6 lg:px-8">
        <nav aria-label="Breadcrumb" className="mb-7">
          <ol className="flex flex-wrap items-center gap-1.5 text-xs text-muted">
            <li>
              <Link to="/shop" className="transition-colors duration-200 hover:text-clay-ink">
                Shop
              </Link>
            </li>
            {product.category && (
              <>
                <li aria-hidden="true">/</li>
                <li>
                  <Link
                    to={`/shop?category=${encodeURIComponent(product.category)}`}
                    className="transition-colors duration-200 hover:text-clay-ink"
                  >
                    {product.category}
                  </Link>
                </li>
              </>
            )}
            <li aria-hidden="true">/</li>
            <li className="truncate text-muted-strong">{product.name}</li>
          </ol>
        </nav>

        <div className="grid gap-10 lg:grid-cols-2 lg:gap-14">
          <Gallery
            images={images}
            name={product.name}
            activeIndex={activeImage}
            onSelect={setActiveImage}
            badge={percent}
          />

          {/* ── Details ─────────────────────────────────────────── */}
          <div className="lg:pt-2">
            {product.store_id && (
              <Link
                to={`/makers/${product.store_id}`}
                className="group inline-flex items-center gap-3 rounded-full border border-hairline py-1.5 pl-1.5 pr-4 transition-colors duration-200 ease-out-cubic hover:border-card-edge hover:bg-subtle"
              >
                <StoreAvatar store={storeQuery.data} size={28} />
                <span className="text-xs font-medium text-muted-strong">
                  Made by{' '}
                  <span className="font-semibold text-ink">
                    {storeQuery.data?.name ?? product.store_name ?? 'a CUFMAI maker'}
                  </span>
                </span>
              </Link>
            )}

            <h1 className="mt-5 font-display text-3xl font-semibold leading-tight text-ink sm:text-4xl">
              {product.name}
            </h1>

            <div className="mt-5 flex flex-wrap items-baseline gap-3">
              <Price product={product} size="xl" />
              {percent && (
                <SaleBadge percent={percent} className="translate-y-[-2px]" />
              )}
            </div>

            {product.description && (
              <p className="mt-6 whitespace-pre-line text-sm leading-relaxed text-muted">
                {product.description}
              </p>
            )}

            {/* ── Size ──────────────────────────────────────────── */}
            {sizes.length > 0 && (
              <div className="mt-8">
                <div className="flex items-center justify-between">
                  <h2 className="inline-flex items-center gap-1.5 text-xs font-semibold uppercase tracking-[0.08em] text-muted">
                    <Ruler size={13} strokeWidth={2.25} />
                    Size
                  </h2>
                  {selectedStock !== null && selectedStock > 0 && (
                    <span className="text-xs text-muted">
                      {selectedStock} in stock
                    </span>
                  )}
                </div>

                <div className="mt-3 flex flex-wrap gap-2">
                  {sizes.map((size) => {
                    const stock = stockForSize(product, size)
                    const disabled = stock <= 0
                    const active = selectedSize === size

                    return (
                      <button
                        key={size}
                        type="button"
                        disabled={disabled}
                        onClick={() => {
                          setSelectedSize(size)
                          // The previous "added" confirmation belonged to a
                          // different size, so it stops being true here.
                          setAdded(false)
                        }}
                        aria-pressed={active}
                        title={disabled ? `Size ${size} is out of stock` : undefined}
                        className={`num min-w-[3rem] rounded-field border px-3 py-2.5 text-sm font-semibold transition-[background-color,border-color,color,transform] duration-200 ease-out-cubic ${
                          disabled
                            ? 'cursor-not-allowed border-hairline text-muted/40 line-through'
                            : active
                              ? 'border-clay bg-clay text-ink-inverse'
                              : 'border-hairline text-ink hover:border-card-edge hover:bg-subtle'
                        }`}
                      >
                        {size}
                      </button>
                    )
                  })}
                </div>

                {/* The customer's own size, if the product has anything honest
                    to say about it — see `sizeAdvice` for the three allowed
                    sentences. The buy button still needs a size tapped: this
                    line informs a choice, it never makes one. */}
                {advice && (
                  <p
                    className={`mt-3 inline-flex items-center gap-1.5 text-xs font-medium ${
                      advice.tone === 'in-stock'
                        ? 'text-clay-ink'
                        : 'text-muted'
                    }`}
                  >
                    {advice.tone === 'near' ? (
                      <Info size={13} strokeWidth={2.25} className="shrink-0" />
                    ) : (
                      <Footprints
                        size={13}
                        strokeWidth={2.25}
                        className="shrink-0"
                      />
                    )}
                    {advice.text}
                  </p>
                )}

                {selectedSize === null && !soldOutEntirely && (
                  <p className="mt-2.5 text-xs text-muted">
                    Choose a size to check availability.
                  </p>
                )}
              </div>
            )}

            {/* ── Purchase ──────────────────────────────────────── */}
            <div className="mt-8 space-y-3">
              <button
                type="button"
                onClick={onAddToCart}
                disabled={soldOutEntirely || needsSize || adding}
                className="btn btn-primary w-full disabled:cursor-not-allowed disabled:opacity-60"
              >
                {soldOutEntirely
                  ? 'Sold out'
                  : adding
                    ? 'Adding…'
                    : 'Add to cart'}
              </button>

              {needsSize && !soldOutEntirely && (
                <p className="text-center text-xs text-muted">
                  Choose a size to continue.
                </p>
              )}

              {added && (
                <div className="flex items-center justify-between gap-3 rounded-field border border-olive/30 bg-olive/[0.07] px-4 py-3 text-sm text-ink">
                  <span>Added to your cart.</span>
                  <Link
                    to="/cart"
                    className="shrink-0 font-semibold text-clay-ink underline-offset-4 hover:underline"
                  >
                    View cart
                  </Link>
                </div>
              )}

              {addError && (
                <p role="alert" className="text-center text-xs text-crimson">
                  {addError}
                </p>
              )}
            </div>

            <ul className="mt-8 space-y-3 border-t border-hairline pt-6 text-sm text-muted">
              <li className="flex items-start gap-2.5">
                <Truck size={15} strokeWidth={2} className="mt-0.5 shrink-0" />
                Delivery arranged with the maker, or pick up in Carcar City.
              </li>
              <li className="flex items-start gap-2.5">
                <Ruler size={15} strokeWidth={2} className="mt-0.5 shrink-0" />
                Sizes are US/UK labels set by the workshop.
              </li>
            </ul>

            {product.sku && (
              <p className="mt-6 text-xs text-muted/70">
                SKU <span className="num">{product.sku}</span>
              </p>
            )}
          </div>
        </div>
      </div>

      {/* ── More from this workshop ─────────────────────────────── */}
      {storeProductsQuery.isLoading || related.length > 0 ? (
        <section className="mx-auto max-w-7xl px-4 py-14 sm:px-6 lg:px-8">
          <Reveal>
            <h2 className="font-display text-2xl font-semibold text-ink">
              More from this workshop
            </h2>
          </Reveal>
          <div className="mt-8">
            {storeProductsQuery.isLoading ? (
              <ProductGridSkeleton count={4} />
            ) : (
              <ProductGrid products={related} />
            )}
          </div>
        </section>
      ) : null}
    </>
  )
}

/**
 * The image gallery.
 *
 * The main image zooms toward the pointer; the thumbnails sit beneath as a
 * filmstrip whose active frame is *ringed* rather than recoloured, so the
 * photograph is never covered by the state that indicates it.
 */
function Gallery({ images, name, activeIndex, onSelect, badge }) {
  const { reduce } = useTransitionTiming()
  const [origin, setOrigin] = useState({ x: 50, y: 50 })
  const [zoomed, setZoomed] = useState(false)

  const active = images[activeIndex]

  const trackPointer = (event) => {
    if (reduce) return
    const rect = event.currentTarget.getBoundingClientRect()
    setOrigin({
      x: ((event.clientX - rect.left) / rect.width) * 100,
      y: ((event.clientY - rect.top) / rect.height) * 100,
    })
  }

  return (
    <div>
      <div
        onMouseMove={trackPointer}
        onMouseEnter={() => setZoomed(true)}
        onMouseLeave={() => {
          setZoomed(false)
          setOrigin({ x: 50, y: 50 })
        }}
        className={`relative aspect-square overflow-hidden rounded-premium border border-hairline bg-subtle ${
          reduce ? '' : 'cursor-zoom-in'
        }`}
      >
        {active ? (
          <img
            src={active}
            alt={name}
            style={{ transformOrigin: `${origin.x}% ${origin.y}%` }}
            className={`h-full w-full object-cover transition-transform duration-500 ease-out-cubic ${
              zoomed && !reduce ? 'scale-[1.7]' : 'scale-100'
            }`}
          />
        ) : (
          <div className="flex h-full flex-col items-center justify-center gap-2 text-muted">
            <ImageOff size={30} strokeWidth={1.5} />
            <span className="text-xs">No photo yet</span>
          </div>
        )}

        {badge && (
          <SaleBadge
            percent={badge}
            className="absolute left-4 top-4 z-10"
          />
        )}
      </div>

      {images.length > 1 && (
        <ul className="mt-4 flex gap-3 overflow-x-auto pb-1">
          {images.map((url, index) => (
            <li key={url} className="shrink-0">
              <button
                type="button"
                onClick={() => onSelect(index)}
                aria-label={`Show image ${index + 1} of ${images.length}`}
                aria-current={index === activeIndex}
                className={`block h-20 w-20 overflow-hidden rounded-field border transition-[border-color,opacity] ease-out-cubic ${
                  index === activeIndex
                    ? 'border-clay opacity-100'
                    : 'border-hairline opacity-70 hover:border-card-edge hover:opacity-100'
                }`}
                style={{ transitionDuration: `${DURATION.base * 1000}ms` }}
              >
                <img
                  src={url}
                  alt=""
                  loading="lazy"
                  className="h-full w-full object-cover"
                />
              </button>
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}
