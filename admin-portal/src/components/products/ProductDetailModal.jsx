import { useState } from 'react'
import { X, Package, Cuboid } from 'lucide-react'
import { formatCurrency } from '../../lib/constants'
import Badge from '../ui/Badge.jsx'
import ModelViewerDialog from './ModelViewerDialog.jsx'
import { useProductModels } from '../../hooks/useModelRequests.js'

export default function ProductDetailModal({ product, onClose, onToggleActive, onDelete }) {
  // Declared before the early return: hooks must run on every render.
  const [viewing, setViewing] = useState(null)
  if (!product) return null

  const images = product.product_images ?? []
  const inventory = product.inventory ?? []

  return (
    <>
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
      <div className="absolute inset-0 bg-[#3B2314]/40" onClick={onClose} />
      <div className="relative z-10 flex max-h-[90vh] w-full max-w-2xl flex-col overflow-y-auto rounded-2xl bg-white">
        {/* Header */}
        <div className="flex items-center justify-between border-b border-[#F5F0EB] p-6">
          <h2 className="font-display text-xl font-bold text-[#3B2314]">{product.name}</h2>
          <button
            type="button"
            onClick={onClose}
            className="flex h-8 w-8 items-center justify-center rounded-lg transition-colors hover:bg-[#F5F0EB]"
          >
            <X size={16} className="text-[#6B5C4E]" />
          </button>
        </div>

        <div className="p-6">
          {/* Image gallery */}
          {images.length > 0 && (
            <div className="mb-6 flex gap-2 overflow-x-auto">
              {images.map((img, i) => (
                <img
                  key={i}
                  src={img.image_url}
                  alt=""
                  className={`h-24 w-24 flex-shrink-0 rounded-xl object-cover border-2 ${
                    img.is_primary ? 'border-[#8B5A2B]' : 'border-transparent'
                  }`}
                />
              ))}
            </div>
          )}

          {/* Details grid */}
          <div className="mb-6 grid grid-cols-2 gap-4">
            <div>
              <p className="mb-1 text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">
                Price
              </p>
              <p className="font-mono text-lg font-bold text-[#8B5A2B]">
                {formatCurrency(product.price)}
              </p>
            </div>
            <div>
              <p className="mb-1 text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">
                Category
              </p>
              <p className="text-sm text-[#3B2314]">{product.category}</p>
            </div>
            <div>
              <p className="mb-1 text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">
                Status
              </p>
              <span
                className={`rounded-full px-2.5 py-1 text-xs font-bold ${
                  product.isActive
                    ? 'bg-teal-50 text-teal-700'
                    : 'bg-red-50 text-red-600'
                }`}
              >
                {product.isActive ? 'Active' : 'Inactive'}
              </span>
            </div>
            <div>
              <p className="mb-1 text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">
                Stock
              </p>
              <p className="font-mono text-sm text-[#3B2314]">{product.totalStock ?? 0} units</p>
            </div>
            <div>
              <p className="mb-1 text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">
                Featured
              </p>
              <p className="text-sm text-[#3B2314]">{product.is_featured ? 'Yes ★' : 'No'}</p>
            </div>
            <div>
              <p className="mb-1 text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">
                Store
              </p>
              <p className="text-sm text-[#3B2314]">{product.store_name}</p>
            </div>
          </div>

          {/* Description */}
          {product.description && (
            <div className="mb-6">
              <p className="mb-2 text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">
                Description
              </p>
              <p className="text-sm leading-relaxed text-[#3B2314]">{product.description}</p>
            </div>
          )}

          {/* Variants / sizes */}
          {inventory.length > 0 && (
            <div className="mb-6">
              <p className="mb-2 text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">
                Sizes & Stock
              </p>
              <div className="grid grid-cols-3 gap-2">
                {inventory.map((v, i) => (
                  <div key={i} className="rounded-xl bg-[#F5F0EB] p-3">
                    <p className="font-mono text-sm font-bold text-[#3B2314]">Size {v.size}</p>
                    <p className="mt-1 text-xs text-[#6B5C4E]">Stock: {v.stock}</p>
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* The 3D models — every version and status, drafts included, so the
              team can see what exists and why a product is still on the fallback. */}
          <ProductModelsSection
            productId={product.id}
            name={product.name}
            onView={setViewing}
          />

          {/* Action buttons */}
          <div className="flex gap-3 border-t border-[#F5F0EB] pt-4">
            <button
              type="button"
              onClick={() => onToggleActive?.(product)}
              className="flex-1 rounded-xl border border-[#D9D0C7] py-2.5 text-sm font-semibold text-[#3B2314] transition-colors hover:bg-[#F5F0EB]"
            >
              {product.isActive ? 'Deactivate Product' : 'Activate Product'}
            </button>
            <button
              type="button"
              onClick={() => onDelete?.(product)}
              className="flex-1 rounded-xl bg-[#D64545] py-2.5 text-sm font-semibold text-white transition-colors hover:bg-red-700"
            >
              Delete Product
            </button>
          </div>
        </div>
      </div>
    </div>
    <ModelViewerDialog target={viewing} onClose={() => setViewing(null)} />
    </>
  )
}

// Every model row a product has, whatever its status. The viewer is handed the
// row's own file, so a draft can be inspected before anyone publishes it.
function ProductModelsSection({ productId, name, onView }) {
  const { data: models, isLoading, isError, error } = useProductModels(productId)
  const rows = models ?? []

  return (
    <div className="mb-6">
      <p className="mb-2 text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">
        3D models
      </p>

      {isLoading && <div className="h-12 animate-pulse rounded-xl bg-[#F5F0EB]" />}

      {isError && <p className="text-xs text-[#D64545]">{error.message}</p>}

      {!isLoading && !isError && rows.length === 0 && (
        <p className="text-sm text-[#6B5C4E]">No model has been uploaded for this product.</p>
      )}

      {rows.length > 0 && (
        <div className="space-y-2">
          {rows.map((m) => (
            <div
              key={m.id}
              className="flex items-center gap-3 rounded-xl border border-[#D9D0C7] bg-white px-4 py-3"
            >
              <Cuboid size={16} className="shrink-0 text-[#8B5A2B]" />
              <div className="min-w-0 flex-1">
                <p className="text-sm font-semibold text-[#3B2314]">Version {m.version}</p>
                <p className="mt-0.5 text-xs text-[#6B5C4E]">
                  {m.authored_length_mm
                    ? `${Number(m.authored_length_mm).toFixed(1)} mm`
                    : 'No declared length'}
                  {m.authored_size_eu ? ` · EU ${Number(m.authored_size_eu)}` : ''}
                </p>
              </div>
              <Badge label={m.status} variant={m.status} />
              {m.storage_path && (
                <button
                  type="button"
                  onClick={() =>
                    onView({
                      title: name ?? 'Product',
                      storagePath: m.storage_path,
                      status: m.status,
                      version: m.version,
                    })
                  }
                  className="shrink-0 rounded-lg border border-[#8B5A2B] px-3 py-1.5 text-xs font-semibold text-[#8B5A2B] transition-colors hover:bg-[#8B5A2B]/10"
                >
                  View 3D
                </button>
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
