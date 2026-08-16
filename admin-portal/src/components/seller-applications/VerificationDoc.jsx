import { useEffect, useState } from 'react'
import { Loader2, Maximize2 } from 'lucide-react'
import Modal from '../ui/Modal.jsx'
import { supabase } from '../../lib/supabase'

const PRIVATE_BUCKET = 'seller-verification-docs'
const PUBLIC_BUCKET = 'store-assets'

/**
 * Resolves a storage path to a viewable URL.
 *
 * - Private bucket (`seller-verification-docs`): short-lived signed URL.
 *   Works for admins because the "Admins can read all verification docs"
 *   storage policy passes the SELECT check (same anon key + admin JWT the
 *   portal already uses everywhere).
 * - Public bucket (`store-assets`, e.g. the store-front photo): plain
 *   public URL — no signing needed.
 */
async function resolveUrl(storagePath, bucket) {
  if (!storagePath) return null
  if (bucket === PUBLIC_BUCKET) {
    const { data } = supabase.storage.from(PUBLIC_BUCKET).getPublicUrl(storagePath)
    return data?.publicUrl ?? null
  }
  const { data, error } = await supabase.storage
    .from(PRIVATE_BUCKET)
    .createSignedUrl(storagePath, 3600) // 1 hour
  if (error) throw error
  return data?.signedUrl ?? null
}

/**
 * A tappable thumbnail for an applicant's submitted document. Resolves the
 * URL once per path, shows a loader/error state, and opens a full-screen
 * zoom on tap so the admin can actually verify the document.
 */
export default function VerificationDoc({
  storagePath,
  label,
  bucket = PRIVATE_BUCKET,
  size = 'h-20 w-20',
}) {
  const [url, setUrl] = useState(null)
  const [error, setError] = useState(false)
  const [loading, setLoading] = useState(false)
  const [zoom, setZoom] = useState(false)

  useEffect(() => {
    let cancelled = false
    setUrl(null)
    setError(false)
    if (!storagePath) return

    setLoading(true)
    resolveUrl(storagePath, bucket)
      .then((resolved) => {
        if (cancelled) return
        setUrl(resolved ?? null)
        setError(!resolved)
      })
      .catch(() => {
        if (!cancelled) setError(true)
      })
      .finally(() => {
        if (!cancelled) setLoading(false)
      })

    return () => {
      cancelled = true
    }
  }, [storagePath, bucket])

  if (!storagePath) {
    return (
      <div
        className={`flex ${size} flex-col items-center justify-center rounded-xl border border-dashed border-[#D9D0C7] bg-[#F5F0EB]`}
      >
        <span className="px-1 text-center text-[10px] text-[#6B5C4E]">Not submitted</span>
      </div>
    )
  }

  const placeholder = (
    <div
      className={`flex ${size} flex-col items-center justify-center rounded-xl border border-[#D9D0C7] bg-[#F5F0EB]`}
    >
      {loading ? (
        <Loader2 size={16} className="animate-spin text-[#8B5A2B]" />
      ) : (
        <span className="px-1 text-center text-[10px] text-[#D64545]">Unavailable</span>
      )}
    </div>
  )

  return (
    <>
      <div className="flex flex-col items-center gap-1">
        <button
          type="button"
          onClick={() => url && setZoom(true)}
          disabled={!url}
          className={`group relative ${size} overflow-hidden rounded-xl border border-[#D9D0C7] bg-white shadow-sm transition-shadow disabled:cursor-default ${
            url ? 'cursor-zoom-in hover:shadow-md' : ''
          }`}
          title={url ? `View ${label}` : undefined}
        >
          {url ? (
            <>
              <img src={url} alt={label} className="h-full w-full object-cover" />
              <span className="absolute inset-0 flex items-center justify-center bg-black/0 opacity-0 transition-opacity group-hover:bg-black/30 group-hover:opacity-100">
                <Maximize2 size={16} className="text-white" />
              </span>
            </>
          ) : (
            placeholder
          )}
        </button>
        <span className="max-w-[96px] truncate text-[10px] font-medium text-[#6B5C4E]">
          {label}
        </span>
      </div>

      {/* Zoom lightbox */}
      <Modal open={zoom} onClose={() => setZoom(false)} title={label} size="xl">
        <div className="flex items-center justify-center rounded-xl bg-[#3B2314] p-2">
          {url && (
            <img
              src={url}
              alt={label}
              className="max-h-[60vh] w-auto rounded-lg object-contain"
            />
          )}
        </div>
      </Modal>
    </>
  )
}
