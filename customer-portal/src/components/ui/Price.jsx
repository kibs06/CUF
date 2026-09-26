import { formatCurrency } from '../../lib/constants'
import { effectivePrice, isOnSale } from '../../lib/pricing'

const SIZES = {
  sm: { current: 'text-sm', original: 'text-[11px]' },
  md: { current: 'text-base', original: 'text-xs' },
  lg: { current: 'text-2xl', original: 'text-sm' },
  xl: { current: 'text-3xl', original: 'text-base' },
}

/**
 * The price, with the original struck through beside it while a sale is live.
 *
 * The discount is carried by the *clay* colour and the strike-through rather
 * than by a red price or a flashing badge: this is a heritage-craft storefront,
 * and a price that shouts reads as a market stall, not as a maker's shop.
 */
export default function Price({ product, size = 'md', className = '' }) {
  const scale = SIZES[size] ?? SIZES.md
  const onSale = isOnSale(product)
  const current = effectivePrice(product)
  const original = Number(product?.price) || 0

  return (
    <div className={`flex flex-wrap items-baseline gap-x-2 gap-y-0.5 ${className}`}>
      <span
        className={`num font-semibold ${scale.current} ${
          onSale ? 'text-clay-ink' : 'text-ink'
        }`}
      >
        {formatCurrency(current)}
      </span>
      {onSale && (
        <span className={`num ${scale.original} text-muted line-through`}>
          {formatCurrency(original)}
        </span>
      )}
    </div>
  )
}
