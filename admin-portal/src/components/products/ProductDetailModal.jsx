import { useState } from 'react'
import Tooltip from '../ui/Tooltip.jsx'
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
      <div className="absolute inset-0 bg-secondary/40" onClick={onClose} />
      <div className="relative z-10 flex max-h-[90vh] w-full max-w-2xl flex-col overflow-y-auto rounded-2xl bg-card">
        {/* Header */}
        <div className="flex items-center justify-between border-b border-surface p-6">
          <h2 className="font-display text-xl font-bold text-ink">{product.name}</h2>
          <Tooltip label="Close this product.">
            <button
              type="button"
              onClick={onClose}
              className="flex h-8 w-8 items-center justify-center rounded-lg transition-colors hover:bg-surface"
            >
              <X size={16} className="text-muted" />
            </button>
          </Tooltip>
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
                    img.is_primary ? 'border-primary' : 'border-transparent'
                  }`}
                />
              ))}
            </div>
          )}

          {/* Details grid */}
          <div className="mb-6 grid grid-cols-2 gap-4">
            <div>
              <p className="mb-1 text-xs font-semibold uppercase tracking-wider text-muted">
                Price
              </p>
              <p className="font-mono text-lg font-bold text-primary">
                {formatCurrency(product.price)}
              </p>
            </div>
            <div>
              <p className="mb-1 text-xs font-semibold uppercase tracking-wider text-muted">
                Category
              </p>
              <p className="text-sm text-ink">{product.category}</p>
            </div>
            <div>
              <p className="mb-1 text-xs font-semibold uppercase tracking-wider text-muted">
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
              <p className="mb-1 text-xs font-semibold uppercase tracking-wider text-muted">
                Stock
              </p>
              <p className="font-mono text-sm text-ink">{product.totalStock ?? 0} units</p>
            </div>
            <div>
              <p className="mb-1 text-xs font-semibold uppercase tracking-wider text-muted">
                Featured
              </p>
              <p className="text-sm text-ink">{product.is_featured ? 'Yes ★' : 'No'}</p>
            </div>
            <div>
              <p className="mb-1 text-xs font-semibold uppercase tracking-wider text-muted">
                Store
              </p>
              <p className="text-sm text-ink">{product.store_name}</p>
            </div>
          </div>

          {/* Description */}
          {product.description && (
            <div className="mb-6">
              <p className="mb-2 text-xs font-semibold uppercase tracking-wider text-muted">
                Description
              </p>
              <p className="text-sm leading-relaxed text-ink">{product.description}</p>
            </div>
          )}

          {/* Variants / sizes */}
          {inventory.length > 0 && (
            <div className="mb-6">
              <p className="mb-2 text-xs font-semibold uppercase tracking-wider text-muted">
                Sizes & Stock
              </p>
              <div className="grid grid-cols-3 gap-2">
                {inventory.map((v, i) => (
                  <div key={i} className="rounded-xl bg-surface p-3">
                    <p className="font-mono text-sm font-bold text-ink">Size {v.size}</p>
                    <p className="mt-1 text-xs text-muted">Stock: {v.stock}</p>
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
          <div className="flex gap-3 border-t border-surface pt-4">
            <Tooltip label="Hides the product from the storefront, or puts it back.">
              <button
                type="button"
                onClick={() => onToggleActive?.(product)}
                className="flex-1 rounded-xl border border-border py-2.5 text-sm font-semibold text-ink transition-colors hover:bg-surface"
              >
                {product.isActive ? 'Deactivate Product' : 'Activate Product'}
              </button>
            </Tooltip>
            <Tooltip label="Removes the product from the catalog for good.">
              <button
                type="button"
                onClick={() => onDelete?.(product)}
                className="flex-1 rounded-xl bg-[#D64545] py-2.5 text-sm font-semibold text-white transition-colors hover:bg-[#B93A3A]"
              >
                Delete Product
              </button>
            </Tooltip>
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
      <p className="mb-2 text-xs font-semibold uppercase tracking-wider text-muted">
        3D models
      </p>

      {isLoading && <div className="h-12 animate-pulse rounded-xl bg-surface" />}

      {isError && <p className="text-xs text-danger">{error.message}</p>}

      {!isLoading && !isError && rows.length === 0 && (
        <p className="text-sm text-muted">No model has been uploaded for this product.</p>
      )}

      {rows.length > 0 && (
        <div className="space-y-2">
          {rows.map((m) => (
            <div
              key={m.id}
              className="flex items-center gap-3 rounded-xl border border-border bg-card px-4 py-3"
            >
              <Cuboid size={16} className="shrink-0 text-primary" />
              <div className="min-w-0 flex-1">
                <p className="text-sm font-semibold text-ink">Version {m.version}</p>
                <p className="mt-0.5 text-xs text-muted">
                  {m.authored_length_mm
                    ? `${Number(m.authored_length_mm).toFixed(1)} mm`
                    : 'No declared length'}
                  {m.authored_size_eu ? ` · EU ${Number(m.authored_size_eu)}` : ''}
                </p>
              </div>
              <Badge label={m.status} variant={m.status} />
              {m.storage_path && (
                <Tooltip label="Open this model in the 3D viewer.">
                <button
                  type="button"
                  onClick={() =>
                    onView({
                      title: name ?? 'Product',
                      productId,
                      storagePath: m.storage_path,
                      status: m.status,
                      version: m.version,
                    })
                  }
                  className="shrink-0 rounded-lg border border-primary px-3 py-1.5 text-xs font-semibold text-primary transition-colors hover:bg-primary/10"
                >
                  View 3D
                </button>
                </Tooltip>
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
