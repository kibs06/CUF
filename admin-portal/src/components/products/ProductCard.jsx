import { Package } from 'lucide-react'
import { formatCurrency } from '../../lib/constants'

export default function ProductCard({ product, onView, onToggleActive, onDelete }) {
  const primaryImage =
    product.product_images?.find((i) => i.is_primary)?.image_url ??
    product.product_images?.[0]?.image_url ??
    product.thumbnail

  return (
    <div className="admin-3d-product group overflow-hidden rounded-xl border border-border bg-surface transition-all hover:border-primary/30 hover:shadow-md">
      {/* Image */}
      <div className="relative aspect-square overflow-hidden bg-sand">
        {primaryImage ? (
          <img
            src={primaryImage}
            alt={product.name}
            className="h-full w-full object-cover transition-transform duration-300 group-hover:scale-105"
          />
        ) : (
          <div className="flex h-full w-full items-center justify-center">
            <Package size={32} className="text-primary/30" />
          </div>
        )}

        {/* Status badge — fixed colours, not theme tokens: it sits on the
            product photo, so it must read the same in light and dark mode. */}
        <div className="absolute left-2 top-2">
          <span
            className={`rounded-full px-2 py-0.5 text-xs font-bold shadow-sm ring-1 ring-black/10 ${
              product.isActive
                ? 'bg-[#1E8E82] text-white'
                : 'bg-[#4A4038] text-white'
            }`}
          >
            {product.isActive ? 'Active' : 'Inactive'}
          </span>
        </div>

        {/* Featured badge */}
        {product.is_featured && (
          <div className="absolute right-2 top-2">
            <span className="rounded-full bg-[#E0A300] px-2 py-0.5 text-xs font-bold text-[#1F1B16] shadow-sm ring-1 ring-black/10">
              ★ Featured
            </span>
          </div>
        )}

                {/* Hover overlay actions.

            These controls sit above a PHOTO, so the scrim and the button
            colours are fixed rather than theme tokens: `bg-card` turns
            dark-brown in dark mode and `bg-danger` turns pink, which is why
            the labels used to disappear into the image. Focus-within keeps
            them reachable from the keyboard, where there is no hover. */}
        <div className="absolute inset-0 flex flex-col items-center justify-end gap-2 bg-gradient-to-t from-black/90 via-black/50 to-black/10 px-3 pb-4 opacity-0 transition-opacity duration-200 group-hover:opacity-100 group-focus-within:opacity-100">
          <button
            type="button"
            aria-label={`View details for ${product.name}`}
            onClick={(e) => {
              e.stopPropagation()
              onView?.(product)
            }}
            className="w-full rounded-lg bg-white px-3 py-2 text-xs font-semibold text-[#1F1B16] shadow-lg ring-1 ring-black/10 transition-colors hover:bg-white/90"
          >
            View Details
          </button>
          <div className="flex w-full gap-2">
            <button
              type="button"
              aria-label={`${product.isActive ? 'Deactivate' : 'Activate'} ${product.name}`}
              onClick={(e) => {
                e.stopPropagation()
                onToggleActive?.(product)
              }}
              className="flex-1 rounded-lg bg-white/95 px-2 py-1.5 text-xs font-semibold text-[#1F1B16] shadow-md ring-1 ring-black/10 transition-colors hover:bg-white"
            >
              {product.isActive ? 'Deactivate' : 'Activate'}
            </button>
            <button
              type="button"
              aria-label={`Delete ${product.name}`}
              onClick={(e) => {
                e.stopPropagation()
                onDelete?.(product)
              }}
              className="flex-1 rounded-lg bg-[#D64545] px-2 py-1.5 text-xs font-semibold text-white shadow-md ring-1 ring-black/10 transition-colors hover:bg-[#B93A3A]"
            >
              Delete
            </button>
          </div>
        </div>
      </div>

      {/* Info */}
      <div className="p-3">
        <p className="truncate text-sm font-semibold text-ink">{product.name}</p>
        <p className="mt-0.5 text-xs text-muted">{product.category}</p>
        <div className="mt-2 flex items-center justify-between">
          <span className="font-mono text-sm font-bold text-primary">
            {formatCurrency(product.price)}
          </span>
          <span className="font-mono text-xs text-muted">
            Stock: {product.totalStock ?? 0}
          </span>
        </div>
      </div>
    </div>
  )
}
