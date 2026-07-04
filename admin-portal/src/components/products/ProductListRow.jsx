import { Eye, EyeOff, Trash2, Package } from 'lucide-react'
import { formatCurrency } from '../../lib/constants'

export default function ProductListRow({ product, onView, onToggleActive, onDelete }) {
  const primaryImage =
    product.product_images?.find((i) => i.is_primary)?.image_url ??
    product.product_images?.[0]?.image_url ??
    product.thumbnail

  return (
    <div className="group flex items-center gap-4 rounded-xl border border-transparent p-3 transition-colors hover:border-[#D9D0C7] hover:bg-[#F5F0EB]">
      {/* Thumbnail */}
      <div className="h-14 w-14 flex-shrink-0 overflow-hidden rounded-xl bg-[#E8DDD5]">
        {primaryImage ? (
          <img src={primaryImage} className="h-full w-full object-cover" alt="" />
        ) : (
          <div className="flex h-full w-full items-center justify-center">
            <Package size={20} className="text-[#8B5A2B]/30" />
          </div>
        )}
      </div>

      {/* Name + category */}
      <div className="min-w-0 flex-1">
        <p className="truncate text-sm font-semibold text-[#3B2314]">{product.name}</p>
        <p className="text-xs text-[#6B5C4E]">{product.category}</p>
      </div>

      {/* Price */}
      <span className="w-24 text-right font-mono text-sm font-bold text-[#8B5A2B]">
        {formatCurrency(product.price)}
      </span>

      {/* Stock */}
      <span className="w-20 text-center font-mono text-xs text-[#6B5C4E]">
        {product.totalStock ?? 0} in stock
      </span>

      {/* Status */}
      <span
        className={`w-20 rounded-full px-2.5 py-1 text-center text-xs font-bold ${
          product.isActive
            ? 'bg-teal-50 text-teal-700'
            : 'bg-red-50 text-red-600'
        }`}
      >
        {product.isActive ? 'Active' : 'Inactive'}
      </span>

      {/* Actions */}
      <div className="flex items-center gap-1.5 opacity-0 transition-opacity group-hover:opacity-100">
        <button
          type="button"
          onClick={() => onView?.(product)}
          className="rounded-lg p-1.5 text-[#6B5C4E] transition-all hover:bg-white hover:shadow-sm"
        >
          <Eye size={14} />
        </button>
        <button
          type="button"
          onClick={() => onToggleActive?.(product)}
          className="rounded-lg p-1.5 text-[#8B5A2B] transition-all hover:bg-white hover:shadow-sm"
        >
          {product.isActive ? <EyeOff size={14} /> : <Eye size={14} />}
        </button>
        <button
          type="button"
          onClick={() => onDelete?.(product)}
          className="rounded-lg p-1.5 text-[#D64545] transition-all hover:bg-red-50"
        >
          <Trash2 size={14} />
        </button>
      </div>
    </div>
  )
}
