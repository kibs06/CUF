import { useEffect, useMemo, useState } from 'react'
import { Link, useNavigate, useParams } from 'react-router-dom'
import {
  Eye,
  Footprints,
  ImageOff,
  Info,
  PackageOpen,
  Rotate3d,
  Ruler,
  Truck,
} from 'lucide-react'

import Price from '../components/ui/Price'
import Product3DViewer from '../components/product/Product3DViewer'
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
import useProductModel from '../hooks/useProductModel'
import { availableSizes, stockForSize } from '../lib/stock'
import { salePercent } from '../lib/pricing'
import { sellerProductPreviewPath } from '../lib/sellerPaths.js'
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
 *
 * **And it can show the shoe itself** (2026-10-03): a product whose model the
 * workshop has published gets a "View in 3D" button under the gallery, opening
 * `Product3DViewer` — the web half of the app's box, the same verified `.glb`
 * from the same public bucket. The rule is the app's own: a product with no live
 * model shows **neither** a viewer nor a button, and a read that fails draws
 * nothing rather than an apology.
 *
 * ## The same page, drawn for the seller (`preview`)
 *
 * The seller's product menu offers *View on your storefront*, and the shop is
 * closed to sellers — `AppLayout` sends an approved seller back to the portal
 * from every customer route, which is why that item used to flash this page for
 * a moment and then replace it with the dashboard. So the preview has its own
 * route under `/seller`, and it renders **this component**, not a copy of it:
 * what a seller checks is whether the photographs, the price and the sizes look
 * right, and a second implementation would be free to look right about different
 * things.
 *
 * `preview` changes exactly two things:
 *
 *  1. **Nothing can be bought.** The purchase button is disabled. This is what
 *     keeps the route an exception in the *routing* rather than a hole in the
 *     marketplace rule — a seller still cannot put their own stock in a cart. It
 *     is drawn rather than removed, because "is the buy button there and does it
 *     say the right thing" is part of what a preview is for.
 *  2. **Links that leave stay put.** The breadcrumb and the maker chip lead into
 *     the shop, where the seller would be redirected out of the page they are
 *     reading, so in preview they are plain text. The related grid links to
 *     other products' previews instead (`sellerProductPreviewPath`).
 */
export default function ProductDetail({ preview = false }) {
  const { productId } = useParams()
  const productQuery = useProduct(productId)
  const product = productQuery.data

  const storeQuery = useStore(product?.store_id)
  const storeProductsQuery = useProducts({ storeId: product?.store_id })

  // The 3D model the workshop published, if there is one — null for most of the
  // catalogue, which is a state this page draws nothing for.
  const { model } = useProductModel(productId)

  const navigate = useNavigate()
  const { isSignedIn } = useAuth()
  const { addItem } = useCart()

  const [activeImage, setActiveImage] = useState(0)
  const [viewerOpen, setViewerOpen] = useState(false)
  const [selectedSize, setSelectedSize] = useState(null)
  const [adding, setAdding] = useState(false)
  const [added, setAdded] = useState(false)
  const [addError, setAddError] = useState(null)

  // A new product is a new gallery and a new size to choose.
  useEffect(() => {
    setActiveImage(0)
    setViewerOpen(false)
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
        <div className="grid grid-cols-1 gap-10 lg:grid-cols-2">
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
    /*
      In the preview this is the stale-link case rather than the shop's own —
      the menu only offers the preview for a published product, so a `null` here
      means the row went away after the list was loaded. Either way the way out
      is the seller's own list: `/shop` is a route their session cannot stay on.
    */
    return (
      <div className="mx-auto max-w-3xl px-4 py-20 sm:px-6">
        <EmptyState
          Icon={PackageOpen}
          title={
            preview
              ? 'We could not find that product'
              : 'This product is no longer available'
          }
          description={
            preview
              ? 'It may have been deleted since this list was loaded.'
              : 'It may have sold out, or the maker may have retired it.'
          }
          action={
            <Link
              to={preview ? '/seller/products' : '/shop'}
              className="btn btn-outline"
            >
              {preview ? 'Back to your products' : 'Browse the catalog'}
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

  /*
    The maker chip's contents, so the preview keeps the chip's shape without
    keeping its link: the same avatar and the same sentence, in a wrapper that is
    a `Link` for a customer and a plain element for the seller.
  */
  const makerChip = (
    <>
      <StoreAvatar store={storeQuery.data} size={28} />
      <span className="text-xs font-medium text-muted-strong">
        Made by{' '}
        <span className="font-semibold text-ink">
          {storeQuery.data?.name ?? product.store_name ?? 'a CUFMAI maker'}
        </span>
      </span>
    </>
  )

  return (
    <>
      <div className="mx-auto max-w-7xl px-4 py-8 sm:px-6 lg:px-8">
        {/*
          First, before the page itself: a seller who does not know this is a
          preview will read the disabled buy button as a bug. It says what the
          page is, what it cannot do, and why the links do not leave.
        */}
        {preview && (
          <p className="mb-7 flex items-start gap-2.5 rounded-field border border-hairline bg-subtle/50 px-4 py-3 text-xs leading-relaxed text-muted">
            <Eye className="mt-0.5 h-4 w-4 shrink-0" aria-hidden="true" />
            <span>
              <span className="font-semibold text-ink">Preview.</span> This is the
              page a customer sees for this pair. Nothing can be bought from
              here, and the links stay inside your portal — your seller account
              is kept out of the shop.
            </span>
          </p>
        )}

        <nav aria-label="Breadcrumb" className="mb-7">
          <ol className="flex flex-wrap items-center gap-1.5 text-xs text-muted">
            <li>
              <CrumbLink to="/shop" preview={preview}>
                Shop
              </CrumbLink>
            </li>
            {product.category && (
              <>
                <li aria-hidden="true">/</li>
                <li>
                  <CrumbLink
                    to={`/shop?category=${encodeURIComponent(product.category)}`}
                    preview={preview}
                  >
                    {product.category}
                  </CrumbLink>
                </li>
              </>
            )}
            <li aria-hidden="true">/</li>
            <li className="truncate text-muted-strong">{product.name}</li>
          </ol>
        </nav>

        <div className="grid grid-cols-1 gap-10 lg:grid-cols-2 lg:gap-14">
          <div className="min-w-0">
            <Gallery
              images={images}
              name={product.name}
              activeIndex={activeImage}
              onSelect={setActiveImage}
              badge={percent}
            />

            {/* ⚠️ The button exists only when the model does. "3D is ready" is a
                claim about a `product_models` row; the entry is drawn from a row
                that is `active` and has bytes to fetch (`useProductModel`), so a
                product with neither a row nor a file shows nothing at all — no
                button, and no gap where one would have been. That is the app's
                rule too: the box and its entry are one decision. */}
            {model && (
              <button
                type="button"
                onClick={() => setViewerOpen(true)}
                className="btn btn-outline mt-4 w-full gap-2"
              >
                <Rotate3d size={16} strokeWidth={2} />
                View in 3D
              </button>
            )}
          </div>

          {/* ── Details ─────────────────────────────────────────── */}
          <div className="min-w-0 lg:pt-2">
            {product.store_id &&
              (preview ? (
                <div className="inline-flex items-center gap-3 rounded-full border border-hairline py-1.5 pl-1.5 pr-4">
                  {makerChip}
                </div>
              ) : (
                <Link
                  to={`/makers/${product.store_id}`}
                  className="group inline-flex items-center gap-3 rounded-full border border-hairline py-1.5 pl-1.5 pr-4 transition-colors duration-200 ease-out-cubic hover:border-card-edge hover:bg-subtle"
                >
                  {makerChip}
                </Link>
              ))}

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
              {/*
                Disabled in preview, not hidden: the paragraph under it is the
                only place that says why, and the label itself ("Add to cart",
                "Sold out") is part of what a seller is checking.
              */}
              <button
                type="button"
                onClick={onAddToCart}
                disabled={preview || soldOutEntirely || needsSize || adding}
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

              {preview && (
                <p className="text-center text-xs text-muted">
                  A customer can add this to their cart. It is disabled here
                  because your seller account cannot buy.
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
              <ProductGrid
                products={related}
                /*
                  A related tile goes to another product. On the storefront that
                  is `/product/:id`; in the preview it has to be that product's
                  own preview, or the first tile a seller clicks bounces them out
                  of the page they just opened.
                */
                productPath={preview ? sellerProductPreviewPath : undefined}
              />
            )}
          </div>
        </section>
      ) : null}

      <Product3DViewer
        open={viewerOpen}
        url={model?.url ?? null}
        name={product.name}
        onClose={() => setViewerOpen(false)}
      />
    </>
  )
}

/**
 * A breadcrumb crumb.
 *
 * A `Link` for a customer, plain text in the seller's preview — where the shop
 * breadcrumb would be a link the seller's own session cannot follow (the portal
 * redirects them out of it). Drawn as a component rather than branched inline
 * three times, so the crumbs cannot end up half-linked.
 */
function CrumbLink({ to, preview, children }) {
  if (preview) return <span className="text-muted">{children}</span>

  return (
    <Link to={to} className="transition-colors duration-200 hover:text-clay-ink">
      {children}
    </Link>
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
