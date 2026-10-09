import { useEffect, useState } from 'react'
import Modal from '../ui/Modal.jsx'
import { supabase } from '../../lib/supabase.js'
import { MODEL_BUCKET } from '../../lib/modelPublish.js'

// The admin's look at a stored model. It draws the same public `.glb` the
// customer portal's viewer draws, so a draft previewed here is the file a
// customer would get once the row is active. Drag to turn, scroll to zoom.
// There is no AR door: the admin only needs to inspect the model.
//
// `target` is `{ title, storagePath, status, version }`, or null when closed.
// The last target is kept while the modal animates out, so the dialog does not
// flash "no file" during its exit.
export default function ModelViewerDialog({ target, onClose }) {
  const [shown, setShown] = useState(null)
  const [ready, setReady] = useState(false)
  const [loadError, setLoadError] = useState(false)

  useEffect(() => {
    if (target) setShown(target)
  }, [target])

  // Load the library once, on first open. It is a few hundred KB of WebGL code,
  // so pages that never open a model do not pay for it.
  useEffect(() => {
    if (!target || ready) return undefined
    let cancelled = false
    import('@google/model-viewer')
      .then(() => {
        if (!cancelled) setReady(true)
      })
      .catch(() => {
        // Shown to the admin, not swallowed: a blocked chunk should be visible.
        if (!cancelled) setLoadError(true)
      })
    return () => {
      cancelled = true
    }
  }, [target, ready])

  const url =
    shown?.storagePath
      ? supabase.storage.from(MODEL_BUCKET).getPublicUrl(shown.storagePath).data.publicUrl
      : null

  return (
    <Modal
      open={!!target}
      onClose={onClose}
      title={shown ? `${shown.title} — 3D model` : '3D model'}
      size="xl"
    >
      <div className="relative aspect-[4/3] w-full overflow-hidden rounded-xl bg-[#F5F5F5]">
        {!url && (
          <div className="absolute inset-0 grid place-items-center p-6 text-center text-sm text-[#6B5C4E]">
            This model has no file on record, so there is nothing to draw.
          </div>
        )}
        {url && loadError && (
          <div className="absolute inset-0 grid place-items-center p-6 text-center text-sm text-[#D64545]">
            The 3D viewer could not load. Check the connection and open it again.
          </div>
        )}
        {url && !loadError && !ready && (
          <div className="absolute inset-0 grid place-items-center text-sm text-[#6B5C4E]">
            Loading the 3D viewer…
          </div>
        )}
        {url && !loadError && ready && (
          <model-viewer
            src={url}
            alt={`${shown?.title ?? 'Product'} — 3D model`}
            camera-controls=""
            touch-action="none"
            interaction-prompt="none"
            camera-orbit="-60deg 72deg 105%"
            exposure="0.85"
            shadow-intensity="0.45"
            style={{ display: 'block', width: '100%', height: '100%' }}
          />
        )}
      </div>
      {shown && (
        <p className="mt-3 text-xs text-[#6B5C4E]">
          Version {shown.version} · {shown.status}. Drag to turn the shoe, scroll to zoom.
        </p>
      )}
    </Modal>
  )
}
