import { useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import { motion } from 'motion/react'
import { ImageOff } from 'lucide-react'

import Price from '../ui/Price'
import SaleBadge from '../ui/SaleBadge'
import SizeBadge from './SizeBadge'
import { fadeUp, useTransitionTiming } from '../motion/transitions'
import { DURATION } from '../motion/transitions'
import { useMySize } from '../../hooks/useMySize.js'
import { sizeBadgeFor } from '../../lib/sizeMatchRules'
import { effectivePrice, isOnSale, salePercent } from '../../lib/pricing'
import { isOutOfStock } from '../../lib/stock'

/**
 * A product tile.
 *
 * Three details carry the "premium" feel, and each is a deliberate choice
 * rather than decoration:
 *
 *  1. **The lift is small** (4px) and the shadow grows into the SAME two-layer
 *     shadow at a wider spread (`shadow-card-lift`). Moving a card far, or
 *     swapping its shadow for a different one, reads as a cartoon; scaling one
 *     shadow reads as a surface rising.
 *
 *  2. **The image is the only thing that moves much** — a slow 1.06 scale over
 *     550ms. It is the largest element, so it carries the most motion, and
 *     slowing it down is what stops the card feeling twitchy under a cursor.
 *
 *  3. **It fades in when decoded.** A grid of images popping in one by one as
 *     they arrive is the single cheapest-looking thing a storefront can do.
 *
 * The whole tile is ONE link, stretched under the content — a card that is also
 * a button is two tab stops and two announcements for one destination.
 *
 * It also carries the "your size" tag when the card is a product the customer's
 * own size exists in. The state comes from `sizeBadgeFor` (the same rule the
 * home shelf and the product page read), and it is appended to the link's label
 * rather than left as separate content, because one destination should be one
 * announcement.
 *
 * The tag is on **every** tile, the home page's "In your size" shelf included.
 * That shelf used to ask for it to be hidden — ten identical tags under a
 * heading that already names the size — but the shelf is the catalog's own grid
 * now, and there a card without the tag reads as a *different* card rather than
 * as an unlabelled one.
 */
export default function ProductCard({ product }) {
  const { d, reduce } = useTransitionTiming()
  const [loaded, setLoaded] = useState(false)

  const onSale = isOnSale(product)
  const percent = salePercent(product)
  const soldOut = isOutOfStock(product)
  const image = product.images?.[0]

  const mySize = useMySize()
  /*
    A product sold out on every size says so from the centre of the tile
    already. Tagging it `EU 42 sold out` underneath that would be the same news
    twice, so the badge's sold-out state is for the useful case: this product is
    for sale, just not in *your* size.
  */
  const sizeBadge = useMemo(
    () => (soldOut ? null : sizeBadgeFor(product, mySize)),
    [product, mySize, soldOut],
  )

  const accessibleLabel = [
    product.name,
    product.store_name ? `by ${product.store_name}` : null,
    onSale
      ? `on sale at ${currencyLabel(effectivePrice(product))}, reduced from ${currencyLabel(product.price)}`
      : currencyLabel(product.price),
    soldOut ? 'sold out' : null,
    sizeBadge
      ? sizeBadge.tone === 'in-stock'
        ? `in your size, ${sizeBadge.label}`
        : `${sizeBadge.label}`
      : null,
  ]
    .filter(Boolean)
    .join(' — ')

  return (
    <motion.article
      variants={fadeUp}
      // The lift is a motion-driven transform, not a CSS one: motion writes an
      // inline transform for the entrance, and an inline transform would win
      // over any `hover:-translate-y-*` class, silently doing nothing.
      whileHover={reduce ? undefined : { y: -4 }}
      transition={{ duration: d(DURATION.base) }}
      className="group relative flex flex-col overflow-hidden rounded-card border border-hairline bg-raised shadow-card transition-[border-color,box-shadow] duration-300 ease-out-cubic hover:border-card-edge hover:shadow-card-lift"
    >
      <Link
        to={`/product/${product.id}`}
        className="absolute inset-0 z-20 rounded-card"
        aria-label={accessibleLabel}
      />

      <div className="relative aspect-square overflow-hidden bg-subtle">
        {image ? (
          <img
            src={image}
            // Decorative: the stretched link above already carries the name.
            alt=""
            loading="lazy"
            decoding="async"
            onLoad={() => setLoaded(true)}
            className={`h-full w-full object-cover transition-[transform,opacity] duration-500 ease-out-cubic group-hover:scale-[1.06] ${
              loaded ? 'opacity-100' : 'opacity-0'
            }`}
          />
        ) : (
          <div className="flex h-full items-center justify-center">
            <ImageOff size={28} className="text-muted/50" strokeWidth={1.5} />
          </div>
        )}

        <div className="pointer-events-none absolute left-2.5 top-2.5 z-30 flex gap-2">
          <SaleBadge percent={percent} />
        </div>

        {sizeBadge && (
          <div className="absolute bottom-2.5 left-2.5 z-30">
            <SizeBadge badge={sizeBadge} />
          </div>
        )}

        {soldOut && (
          <div className="pointer-events-none absolute inset-0 z-30 flex items-center justify-center bg-page/70">
            <span className="rounded-full border border-hairline bg-raised px-3 py-1 text-[11px] font-semibold uppercase tracking-[0.08em] text-muted">
              Sold out
            </span>
          </div>
        )}

        {/*
          The hover affordance. `pointer-events-none` is load-bearing: it sits
          above the stretched link, so without it the pill would swallow the
          click it is inviting. Revealed by `group-focus-within` as well, so
          tabbing to the tile shows the same cue as hovering it.
        */}
        {!soldOut && (
          <div className="pointer-events-none absolute inset-x-0 bottom-0 z-30 flex justify-center pb-3">
            <span className="translate-y-2 rounded-full bg-chrome/85 px-3.5 py-1.5 text-[11px] font-semibold uppercase tracking-[0.08em] text-ink-inverse opacity-0 backdrop-blur-sm transition-[opacity,transform] duration-300 ease-out-cubic group-hover:translate-y-0 group-hover:opacity-100 group-focus-within:translate-y-0 group-focus-within:opacity-100">
              View details
            </span>
          </div>
        )}
      </div>

      <div className="flex flex-1 flex-col gap-1 p-4">
        {product.store_name && (
          <p className="truncate text-[11px] font-medium uppercase tracking-[0.08em] text-muted">
            {product.store_name}
          </p>
        )}
        <h3 className="line-clamp-2 text-[15px] font-semibold leading-snug text-ink">
          {product.name}
        </h3>
        <div className="mt-auto pt-3">
          <Price product={product} />
        </div>
      </div>
    </motion.article>
  )
}

/** Local currency formatting for the screen-reader label only. */
function currencyLabel(value) {
  return `₱${(Number(value) || 0).toLocaleString('en-PH', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  })}`
}
