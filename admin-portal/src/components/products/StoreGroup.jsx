import { useState } from 'react'
import { ChevronUp, ChevronDown, Package } from 'lucide-react'
import ProductCard from './ProductCard.jsx'
import ProductListRow from './ProductListRow.jsx'

export default function StoreGroup({
  store,
  products,
  view = 'grid',
  defaultExpanded = true,
  onView,
  onToggleActive,
  onDelete,
}) {
  const [expanded, setExpanded] = useState(defaultExpanded)
  const [showAll, setShowAll] = useState(false)
  const visibleProducts = showAll ? products : products.slice(0, 4)

  return (
    <div className="mb-6 overflow-hidden rounded-2xl border border-[#D9D0C7] bg-white shadow-sm">
      {/* Store Header Banner — h-64 (256px) */}
      <div
        className="relative flex h-64 items-end p-6"
        style={{
          background: store.banner_url
            ? `linear-gradient(to bottom, rgba(0,0,0,0.05) 0%, rgba(0,0,0,0.25) 40%, rgba(0,0,0,0.70) 100%), url(${store.banner_url}) center / cover no-repeat`
            : `linear-gradient(135deg, ${store.brand_color || '#8B5A2B'} 0%, ${store.brand_color || '#3B2314'}CC 60%, #1a0f0a 100%)`,
        }}
      >
        {/* OPEN/CLOSED badge — top right */}
        <span
          className={`absolute right-5 top-5 rounded-full px-3 py-1.5 text-xs font-bold tracking-widest uppercase shadow-md ${
            store.is_open ? 'bg-green-500 text-white' : 'bg-gray-500 text-white'
          }`}
        >
          {store.is_open ? '● Open' : '● Closed'}
        </span>

        {/* Collapse toggle — top left */}
        <button
          type="button"
          onClick={() => setExpanded(!expanded)}
          className="absolute left-5 top-5 flex h-9 w-9 items-center justify-center rounded-xl bg-black/25 text-white backdrop-blur-sm transition-colors hover:bg-black/50"
        >
          {expanded ? <ChevronUp size={16} /> : <ChevronDown size={16} />}
        </button>

        {/* Store rating — top center */}
        {store.rating && (
          <div className="absolute left-1/2 top-5 flex -translate-x-1/2 items-center gap-1 rounded-full bg-black/20 px-3 py-1 backdrop-blur-sm">
            <span className="text-xs text-yellow-400">★</span>
            <span className="font-mono text-xs font-bold text-white">{Number(store.rating).toFixed(1)}</span>
          </div>
        )}

        {/* Store identity — bottom left */}
        <div className="flex items-end gap-4">
          {store.logo_url ? (
            <img
              src={store.logo_url}
              alt={store.name}
              className="h-20 w-20 flex-shrink-0 rounded-2xl border-2 border-white object-cover shadow-xl"
            />
          ) : (
            <div className="flex h-20 w-20 flex-shrink-0 items-center justify-center rounded-2xl border-2 border-white/50 bg-white/15 text-3xl font-bold text-white shadow-xl backdrop-blur-sm">
              {store.name?.[0]?.toUpperCase() ?? 'S'}
            </div>
          )}
          <div className="pb-1">
            <h2 className="font-display text-2xl font-bold leading-tight text-white drop-shadow-lg">
              {store.name}
            </h2>
            {store.tagline && (
              <p className="mt-0.5 text-sm text-white/75 drop-shadow">{store.tagline}</p>
            )}
            <div className="mt-1.5 flex items-center gap-3">
              {store.location && (
                <span className="flex items-center gap-1 text-xs text-white/60">
                  📍 {store.location}
                </span>
              )}
              <span className="text-xs text-white/60">
                {products.length} product{products.length !== 1 ? 's' : ''}
              </span>
            </div>
          </div>
        </div>
      </div>

      {/* Products */}
      {expanded && (
        <div className="p-4">
          {products.length === 0 ? (
            <div className="flex flex-col items-center py-10 text-[#6B5C4E]">
              <Package size={32} className="mb-2 opacity-30" />
              <p className="text-sm">No products in this store yet</p>
            </div>
          ) : (
            <>
              {view === 'grid' ? (
                <div className="grid grid-cols-2 gap-4 md:grid-cols-3 lg:grid-cols-4">
                  {visibleProducts.map((product) => (
                    <ProductCard
                      key={product.id}
                      product={product}
                      onView={onView}
                      onToggleActive={onToggleActive}
                      onDelete={onDelete}
                    />
                  ))}
                </div>
              ) : (
                <div className="divide-y divide-[#F5F0EB]">
                  {visibleProducts.map((product) => (
                    <ProductListRow
                      key={product.id}
                      product={product}
                      onView={onView}
                      onToggleActive={onToggleActive}
                      onDelete={onDelete}
                    />
                  ))}
                </div>
              )}

              {/* Show more / less */}
              {products.length > 4 && (
                <button
                  type="button"
                  onClick={() => setShowAll(!showAll)}
                  className="mt-4 flex w-full items-center justify-center gap-2 rounded-xl border border-[#D9D0C7] py-2.5 text-sm text-[#6B5C4E] transition-colors hover:bg-[#F5F0EB]"
                >
                  {showAll ? (
                    <>
                      <ChevronUp size={14} /> Show less
                    </>
                  ) : (
                    <>
                      <ChevronDown size={14} /> View all {products.length} products
                    </>
                  )}
                </button>
              )}
            </>
          )}
        </div>
      )}
    </div>
  )
}
