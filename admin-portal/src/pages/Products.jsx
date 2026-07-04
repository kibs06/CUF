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
    <div className="space-y-6">

      {/* Search & filter bar */}
      <div className="flex flex-wrap gap-3">
        {/* Search */}
        <div className="relative min-w-[200px] flex-1">
          <Search
            size={15}
            className="absolute left-3 top-1/2 -translate-y-1/2 text-[#6B5C4E]"
          />
          <input
            type="search"
            placeholder="Search products..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="w-full rounded-xl border border-[#D9D0C7] bg-white py-2.5 pl-9 pr-4 text-sm text-[#3B2314] placeholder-[#6B5C4E] outline-none transition-colors focus:border-[#8B5A2B] focus:ring-2 focus:ring-[#8B5A2B]/20"
          />
        </div>

        {/* Category filter */}
        <select
          value={categoryFilter}
          onChange={(e) => setCategoryFilter(e.target.value)}
          className="min-w-[140px] rounded-xl border border-[#D9D0C7] bg-white px-4 py-2.5 text-sm text-[#3B2314] outline-none focus:border-[#8B5A2B]"
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
          className="min-w-[130px] rounded-xl border border-[#D9D0C7] bg-white px-4 py-2.5 text-sm text-[#3B2314] outline-none focus:border-[#8B5A2B]"
        >
          <option value="">All Status</option>
          <option value="active">Active</option>
          <option value="inactive">Inactive</option>
        </select>

        {/* Fix #6: Connected pill toggle with divider */}
        <div className="flex overflow-hidden rounded-xl border border-[#D9D0C7] bg-white shadow-sm">
          <button
            type="button"
            onClick={() => setView('grid')}
            className={`flex items-center gap-1.5 px-4 py-2.5 text-sm font-medium transition-colors ${
              view === 'grid'
                ? 'bg-[#8B5A2B] text-white'
                : 'text-[#6B5C4E] hover:bg-[#F5F0EB]'
            }`}
          >
            <LayoutGrid size={15} />
            Grid
          </button>
          <div className="w-px bg-[#D9D0C7]" />
          <button
            type="button"
            onClick={() => setView('list')}
            className={`flex items-center gap-1.5 px-4 py-2.5 text-sm font-medium transition-colors ${
              view === 'list'
                ? 'bg-[#8B5A2B] text-white'
                : 'text-[#6B5C4E] hover:bg-[#F5F0EB]'
            }`}
          >
            <List size={15} />
            List
          </button>
        </div>
      </div>

      {/* Loading skeletons */}
      {isLoading && (
        <div className="space-y-6">
          {[1, 2].map((i) => (
            <div key={i} className="overflow-hidden rounded-2xl border border-[#D9D0C7] bg-white">
              <div className="h-40 animate-pulse bg-[#E8DDD5]" />
              <div className="grid grid-cols-4 gap-4 p-4">
                {[1, 2, 3, 4].map((j) => (
                  <div key={j} className="overflow-hidden rounded-xl">
                    <div className="aspect-square animate-pulse bg-[#E8DDD5]" />
                    <div className="space-y-2 p-3">
                      <div className="h-4 animate-pulse rounded bg-[#E8DDD5]" />
                      <div className="h-3 w-2/3 animate-pulse rounded bg-[#E8DDD5]" />
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
        <div className="rounded-2xl border border-[#D9D0C7] bg-white p-8 text-center">
          <p className="text-sm text-[#D64545]">{error.message}</p>
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
              className="rounded-xl border border-[#D9D0C7] px-4 py-2 text-sm text-[#6B5C4E] hover:bg-[#F5F0EB]"
            >
              Cancel
            </button>
            <button
              type="button"
              onClick={handleDelete}
              disabled={actionId === deleteTarget?.id}
              className="rounded-xl border border-[#D64545] px-4 py-2 text-sm font-semibold text-[#D64545] transition-colors hover:bg-red-50 disabled:opacity-50"
            >
              Deactivate
            </button>
          </>
        }
      >
        <p className="text-sm text-[#6B5C4E]">
          Deactivate <strong className="text-[#3B2314]">{deleteTarget?.name}</strong>? This will
          hide it from the storefront.
        </p>
      </Modal>
    </div>
  )
}
