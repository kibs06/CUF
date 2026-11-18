import { useMemo, useState } from 'react'
import { Search, LayoutGrid, List } from 'lucide-react'
import { useToast } from '../components/ui/Toast.jsx'
import EmptyState from '../components/ui/EmptyState.jsx'
import StoreGroup from '../components/products/StoreGroup.jsx'
import ProductDetailModal from '../components/products/ProductDetailModal.jsx'
import Modal from '../components/ui/Modal.jsx'
import {
  useProducts,
  useToggleProductStatus,
  useDeleteProduct,
} from '../hooks/useProducts.js'

export default function Products() {
  const { showToast } = useToast()
  const [search, setSearch] = useState('')
  const [categoryFilter, setCategoryFilter] = useState('')
  const [statusFilter, setStatusFilter] = useState('')
  const [view, setView] = useState('grid')
  const [viewProduct, setViewProduct] = useState(null)
  const [deleteTarget, setDeleteTarget] = useState(null)
  const [actionId, setActionId] = useState(null)

  const filters = useMemo(
    () => ({
      search: search.trim() || undefined,
      category: categoryFilter || undefined,
      status: statusFilter || undefined,
    }),
    [search, categoryFilter, statusFilter],
  )

  const { data, isLoading, isError, error } = useProducts(filters)
  const toggleStatus = useToggleProductStatus()
  const deleteProduct = useDeleteProduct()

  const handleToggleActive = async (product) => {
    setActionId(product.id)
    try {
      await toggleStatus.mutateAsync({
        productId: product.id,
        isPublished: !product.isActive,
      })
      showToast(product.isActive ? 'Product deactivated' : 'Product activated')
    } catch (err) {
      showToast(err.message ?? 'Update failed', 'error')
    } finally {
      setActionId(null)
    }
  }

  const handleDelete = async () => {
    if (!deleteTarget) return
    setActionId(deleteTarget.id)
    try {
      await deleteProduct.mutateAsync(deleteTarget.id)
      showToast('Product deactivated')
      setDeleteTarget(null)
    } catch (err) {
      showToast(err.message ?? 'Delete failed', 'error')
    } finally {
      setActionId(null)
    }
  }

  const grouped = data?.grouped ?? []
  const totalProducts = data?.total ?? 0
  const storeCount = data?.storeCount ?? 0
  const categories = data?.categories ?? []

  return (
    <div className="space-y-4">

      {/* Search & filter bar */}
      <div className="flex flex-wrap gap-3">
        {/* Search */}
        <div className="relative min-w-[200px] flex-1">
          <Search
            size={15}
            className="absolute left-3 top-1/2 -translate-y-1/2 text-muted"
          />
          <input
            type="search"
            placeholder="Search products..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="w-full rounded-xl border border-border bg-card py-2.5 pl-9 pr-4 text-sm text-ink placeholder-muted outline-none transition-colors focus:border-primary focus:ring-2 focus:ring-primary/20"
          />
        </div>

        {/* Category filter */}
        <select
          value={categoryFilter}
          onChange={(e) => setCategoryFilter(e.target.value)}
          className="min-w-[140px] rounded-xl border border-border bg-card px-4 py-2.5 text-sm text-ink outline-none focus:border-primary"
        >
          <option value="">All Categories</option>
          {categories.map((c) => (
            <option key={c} value={c}>
              {c}
            </option>
          ))}
        </select>

        {/* Status filter */}
        <select
          value={statusFilter}
          onChange={(e) => setStatusFilter(e.target.value)}
          className="min-w-[130px] rounded-xl border border-border bg-card px-4 py-2.5 text-sm text-ink outline-none focus:border-primary"
        >
          <option value="">All Status</option>
          <option value="active">Active</option>
          <option value="inactive">Inactive</option>
        </select>

        {/* Fix #6: Connected pill toggle with divider */}
        <div className="flex overflow-hidden rounded-xl border border-border bg-card">
          <button
            type="button"
            onClick={() => setView('grid')}
            className={`flex items-center gap-1.5 px-4 py-2.5 text-sm font-medium transition-colors ${
              view === 'grid'
                ? 'bg-secondary text-white'
                : 'text-muted hover:bg-canvas'
            }`}
          >
            <LayoutGrid size={15} />
            Grid
          </button>
          <div className="w-px bg-border" />
          <button
            type="button"
            onClick={() => setView('list')}
            className={`flex items-center gap-1.5 px-4 py-2.5 text-sm font-medium transition-colors ${
              view === 'list'
                ? 'bg-secondary text-white'
                : 'text-muted hover:bg-canvas'
            }`}
          >
            <List size={15} />
            List
          </button>
        </div>
      </div>

      {/* Loading skeletons */}
      {isLoading && (
        <div className="space-y-4">
          {[1, 2].map((i) => (
            <div key={i} className="overflow-hidden rounded-xl border border-border bg-card">
              <div className="h-40 animate-pulse bg-faint" />
              <div className="grid grid-cols-4 gap-4 p-4">
                {[1, 2, 3, 4].map((j) => (
                  <div key={j} className="overflow-hidden rounded-xl">
                    <div className="aspect-square animate-pulse bg-faint" />
                    <div className="space-y-2 p-3">
                      <div className="h-4 animate-pulse rounded bg-faint" />
                      <div className="h-3 w-2/3 animate-pulse rounded bg-faint" />
                    </div>
                  </div>
                ))}
              </div>
            </div>
          ))}
        </div>
      )}

      {/* Error */}
      {isError && (
        <div className="rounded-xl border border-border bg-card p-8 text-center">
          <p className="text-sm text-error">{error.message}</p>
        </div>
      )}

      {/* Store groups */}
      {!isLoading && !isError && grouped.length === 0 && (
        <EmptyState
          icon="📦"
          title="No products found"
          description="Try adjusting your search or filters."
        />
      )}

      {!isLoading &&
        !isError &&
        grouped.map((group) => (
          <StoreGroup
            key={group.store.id}
            store={group.store}
            products={group.products}
            view={view}
            onView={setViewProduct}
            onToggleActive={handleToggleActive}
            onDelete={setDeleteTarget}
          />
        ))}

      {/* Product detail modal */}
      <ProductDetailModal
        product={viewProduct}
        onClose={() => setViewProduct(null)}
        onToggleActive={(p) => {
          setViewProduct(null)
          handleToggleActive(p)
        }}
        onDelete={(p) => {
          setViewProduct(null)
          setDeleteTarget(p)
        }}
      />

      {/* Delete confirmation modal */}
      <Modal
        open={!!deleteTarget}
        onClose={() => setDeleteTarget(null)}
        title="Deactivate Product"
        footer={
          <>
            <button
              type="button"
              onClick={() => setDeleteTarget(null)}
              className="rounded-xl border border-border px-4 py-2 text-sm text-muted hover:bg-canvas"
            >
              Cancel
            </button>
            <button
              type="button"
              onClick={handleDelete}
              disabled={actionId === deleteTarget?.id}
              className="rounded-xl border border-danger px-4 py-2 text-sm font-semibold text-error transition-colors hover:bg-red-50 disabled:opacity-50"
            >
              Deactivate
            </button>
          </>
        }
      >
        <p className="text-sm text-muted">
          Deactivate <strong className="text-ink">{deleteTarget?.name}</strong>? This will
          hide it from the storefront.
        </p>
      </Modal>
    </div>
  )
}
