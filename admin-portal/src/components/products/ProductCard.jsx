import { Package } from 'lucide-react'
import { formatCurrency } from '../../lib/constants'

export default function ProductCard({ product, onView, onToggleActive, onDelete }) {
  const primaryImage =
    product.product_images?.find((i) => i.is_primary)?.image_url ??
    product.product_images?.[0]?.image_url ??
    product.thumbnail

  return (
    <div className="group overflow-hidden rounded-xl border border-[#D9D0C7] bg-[#F5F0EB] transition-all hover:border-[#8B5A2B]/30 hover:shadow-md">
      {/* Image */}
      <div className="relative aspect-square overflow-hidden bg-[#E8DDD5]">
        {primaryImage ? (
          <img
            src={primaryImage}
            alt={product.name}
            className="h-full w-full object-cover transition-transform duration-300 group-hover:scale-105"
          />
        ) : (
          <div className="flex h-full w-full items-center justify-center">
            <Package size={32} className="text-[#8B5A2B]/30" />
          </div>
        )}

        {/* Status badge */}
        <div className="absolute left-2 top-2">
          <span
            className={`rounded-full px-2 py-0.5 text-xs font-bold ${
              product.isActive
                ? 'bg-[#4ECDC4] text-white'
                : 'bg-gray-400 text-white'
            }`}
          >
            {product.isActive ? 'Active' : 'Inactive'}
          </span>
        </div>

        {/* Featured badge */}
        {product.is_featured && (
          <div className="absolute right-2 top-2">
            <span className="rounded-full px-2 py-0.5 text-xs font-bold bg-[#E8A020] text-white">
              ★ Featured
            </span>
          </div>
        )}

        {/* Hover overlay actions — stacked at bottom with gradient */}
        <div className="absolute inset-0 flex flex-col items-center justify-end gap-2 bg-gradient-to-t from-black/70 via-black/20 to-transparent px-3 pb-4 opacity-0 transition-all duration-200 group-hover:opacity-100">
          <button
            type="button"
            onClick={(e) => {
              e.stopPropagation()
              onView?.(product)
            }}
            className="w-full rounded-xl bg-white py-2 text-xs font-semibold text-[#3B2314] shadow-md transition-colors hover:bg-[#F5F0EB]"
          >
            View Details
          </button>
          <div className="flex w-full gap-2">
            <button
              type="button"
              onClick={(e) => {
                e.stopPropagation()
                onToggleActive?.(product)
              }}
              className="flex-1 rounded-lg bg-white/90 py-1.5 text-xs font-semibold text-[#3B2314] transition-colors hover:bg-white"
            >
              {product.isActive ? 'Deactivate' : 'Activate'}
            </button>
            <button
              type="button"
              onClick={(e) => {
                e.stopPropagation()
                onDelete?.(product)
              }}
              className="flex-1 rounded-lg bg-[#D64545] py-1.5 text-xs font-semibold text-white transition-colors hover:bg-red-700"
            >
              Delete
            </button>
          </div>
        </div>
      </div>

      {/* Info */}
      <div className="p-3">
        <p className="truncate text-sm font-semibold text-[#3B2314]">{product.name}</p>
        <p className="mt-0.5 text-xs text-[#6B5C4E]">{product.category}</p>
        <div className="mt-2 flex items-center justify-between">
          <span className="font-mono text-sm font-bold text-[#8B5A2B]">
            {formatCurrency(product.price)}
          </span>
          <span className="font-mono text-xs text-[#6B5C4E]">
            Stock: {product.totalStock ?? 0}
          </span>
        </div>
      </div>
    </div>
  )
}
