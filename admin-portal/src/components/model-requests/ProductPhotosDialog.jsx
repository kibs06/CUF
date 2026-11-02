import { useEffect, useMemo, useState } from 'react'
import { ChevronLeft, ChevronRight, X } from 'lucide-react'

// The admin models FROM these photos, so the request row's thumbnail opens
// every picture the seller published — primary first, then display order,
// the same pick the row and the product list use.
export function orderedPhotos(images) {
  return [...(images ?? [])].sort(
    (a, b) =>
      Number(b?.is_primary ?? false) - Number(a?.is_primary ?? false) ||
      (a?.display_order ?? 0) - (b?.display_order ?? 0),
  )
}

export default function ProductPhotosDialog({ request, onClose }) {
  const photos = useMemo(
    () => orderedPhotos(request?.products?.product_images).filter((p) => p?.image_url),
    [request],
  )
  const [index, setIndex] = useState(0)

  // A second row reuses the same dialog: start back on its first photo.
  useEffect(() => {
    setIndex(0)
  }, [request?.id])

  // Escape closes, arrows step — an admin comparing several angles should not
  // have to chase the buttons with the mouse.
  useEffect(() => {
    if (!request) return
    const onKey = (e) => {
      if (e.key === 'Escape') onClose?.()
      if (e.key === 'ArrowRight') setIndex((i) => Math.min(i + 1, photos.length - 1))
      if (e.key === 'ArrowLeft') setIndex((i) => Math.max(i - 1, 0))
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [request, photos.length, onClose])

  if (!request) return null

  const current = photos[index]
  const title = request.products?.name ?? 'Product photos'

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
      <div className="absolute inset-0 bg-[#3B2314]/60" onClick={onClose} />
      <div className="relative z-10 flex max-h-[90vh] w-full max-w-3xl flex-col overflow-hidden rounded-2xl bg-white">
        <div className="flex items-center justify-between border-b border-[#F5F0EB] px-5 py-4">
          <div className="min-w-0">
            <h2 className="truncate font-display text-lg font-bold text-[#3B2314]">{title}</h2>
            {photos.length > 1 && (
              <p className="text-xs tabular-nums text-[#6B5C4E]">
                {index + 1} of {photos.length}
              </p>
            )}
          </div>
          <button
            type="button"
            onClick={onClose}
            aria-label="Close photos"
            className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg transition-colors hover:bg-[#F5F0EB]"
          >
            <X size={16} className="text-[#6B5C4E]" />
          </button>
        </div>

        <div className="flex min-h-0 flex-1 items-center justify-center bg-[#1a1512] p-4">
          {current ? (
            <div className="relative flex w-full items-center justify-center">
              {photos.length > 1 && (
                <button
                  type="button"
                  onClick={() => setIndex((i) => Math.max(i - 1, 0))}
                  disabled={index === 0}
                  aria-label="Previous photo"
                  className="absolute left-1 z-10 flex h-9 w-9 items-center justify-center rounded-full bg-white/90 text-[#3B2314] shadow transition-opacity hover:bg-white disabled:opacity-30"
                >
                  <ChevronLeft size={18} />
                </button>
              )}
              <img
                key={current.image_url}
                src={current.image_url}
                alt={title + ' — photo ' + (index + 1)}
                className="max-h-[55vh] w-auto max-w-full rounded-xl object-contain"
              />
              {photos.length > 1 && (
                <button
                  type="button"
                  onClick={() => setIndex((i) => Math.min(i + 1, photos.length - 1))}
                  disabled={index === photos.length - 1}
                  aria-label="Next photo"
                  className="absolute right-1 z-10 flex h-9 w-9 items-center justify-center rounded-full bg-white/90 text-[#3B2314] shadow transition-opacity hover:bg-white disabled:opacity-30"
                >
                  <ChevronRight size={18} />
                </button>
              )}
            </div>
          ) : (
            <p className="py-10 text-sm text-white/70">This product has no photos.</p>
          )}
        </div>

        {photos.length > 1 && (
          <div className="flex gap-2 overflow-x-auto border-t border-[#F5F0EB] p-3">
            {photos.map((p, i) => (
              <button
                key={p.image_url || i}
                type="button"
                onClick={() => setIndex(i)}
                aria-label={'Photo ' + (i + 1) + (p.is_primary ? ' (primary)' : '')}
                aria-pressed={i === index}
                className={
                  i === index
                    ? 'h-16 w-16 flex-shrink-0 overflow-hidden rounded-xl border-2 border-[#8B5A2B]'
                    : 'h-16 w-16 flex-shrink-0 overflow-hidden rounded-xl border-2 border-transparent hover:border-[#D9D0C7]'
                }
              >
                <img src={p.image_url} alt="" className="h-full w-full object-cover" />
              </button>
            ))}
          </div>
        )}
      </div>
    </div>
  )
}
