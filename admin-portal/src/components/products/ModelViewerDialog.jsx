import { useEffect, useRef, useState } from 'react'
import Modal from '../ui/Modal.jsx'
import { supabase } from '../../lib/supabase.js'
import { MODEL_BUCKET } from '../../lib/modelPublish.js'
import { useColorPaint } from '../../hooks/useColorPaint.js'
import { paintFactors } from '../../lib/paintGuess.js'

// The admin's look at a stored model. It draws the same public `.glb` the
// customer portal's viewer draws, so a draft previewed here is the file a
// customer would get once the row is active. Drag to turn, scroll to zoom.
// There is no AR door: the admin only needs to inspect the model.
//
// `target` is `{ title, productId, storagePath, status, version }`, or null
// when closed. `productId` is optional — without it there is no paint to
// preview, and the dialog is exactly the model viewer it always was.
// The last target is kept while the modal animates out, so the dialog does not
// flash "no file" during its exit.
//
// Paint preview: the confirmed `product_color_paint` rows become chips under
// the shoe. Picking one tints every material by the same multiply factor the
// app's viewers use, so the preview IS the customer render — "As-authored"
// restores the file's own factors. Colours with no confirmed paint get no
// chip: a guess is not a look, and previewing one would bless a colour that
// exists nowhere in reality.
export default function ModelViewerDialog({ target, onClose }) {
  const [shown, setShown] = useState(null)
  const [ready, setReady] = useState(false)
  const [loadError, setLoadError] = useState(false)
  // The previewed colour NAME, not its hex: two colours may share a hex
  // (blue and Navy shipped the same guess), and the ring must mark the
  // choice, not the value. Null is the as-authored file, untouched.
  const [tintName, setTintName] = useState(null)
  const viewerRef = useRef(null)
  const originalsRef = useRef(new Map())

  useEffect(() => {
    if (target) setShown(target)
  }, [target])

  // A new file is a new preview: the tint and the stashed originals belong
  // to the old model, and applying them to this one would paint a stranger.
  useEffect(() => {
    setTintName(null)
    originalsRef.current = new Map()
  }, [shown?.storagePath])

  const productId = shown?.productId ?? null
  const { data: paintData } = useColorPaint(productId)
  const paints = paintData?.paints ?? {}
  const paintedColors = Object.keys(paints)
    .filter((name) => paints[name])
    .sort((a, b) => a.localeCompare(b))
  const tintHex = tintName ? paints[tintName] ?? null : null

  // Tint every material by the paint's factors — the same multiply the app
  // applies — stashing each material's own factor first so As-authored
  // restores the file instead of assuming white. The model may arrive after
  // the choice (slow `.glb`) or the choice after the model, so this runs on
  // both the viewer's `load` event and every tint/url/ready change; each
  // run converges rather than stacking.
  const applyTint = () => {
    const materials = viewerRef.current?.model?.materials
    if (!materials) return
    for (const material of materials) {
      const pbr = material?.pbrMetallicRoughness
      if (!pbr || typeof pbr.setBaseColorFactor !== 'function') continue
      if (!originalsRef.current.has(material)) {
        let original = [1, 1, 1, 1]
        try {
          const current = pbr.baseColorFactor
          if (Array.isArray(current) && current.length === 4) original = [...current]
        } catch {
          // An unreadable factor keeps the white default: a near-miss
          // restore beats leaving a stranger's tint behind.
        }
        originalsRef.current.set(material, original)
      }
      const factors = tintHex ? paintFactors(tintHex) : null
      pbr.setBaseColorFactor(factors ? [...factors, 1] : originalsRef.current.get(material))
    }
  }

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

  useEffect(() => {
    const el = viewerRef.current
    if (!el || !ready || !url) return undefined
    el.addEventListener('load', applyTint)
    applyTint()
    return () => {
      el.removeEventListener('load', applyTint)
    }
  }, [ready, url, tintHex])

  return (
    <Modal
      open={!!target}
      onClose={onClose}
      title={shown ? `${shown.title} — 3D model` : '3D model'}
      size="xl"
      scrim="bg-secondary/30"
    >
      {/* No stage box: the shoe floats on the card itself, so what the admin
          sees is the file and nothing else. The viewer is transparent by
          default — the grey backdrop it used to sit on is gone, and the
          dialog is taller with a closer default orbit so the pair fills it. */}
      <div className="relative h-[58vh] min-h-[420px] w-full overflow-hidden">
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
            ref={viewerRef}
            src={url}
            alt={`${shown?.title ?? 'Product'} — 3D model`}
            camera-controls=""
            touch-action="none"
            interaction-prompt="none"
            camera-orbit="-60deg 72deg 88%"
            min-camera-orbit="auto auto 55%"
            max-camera-orbit="auto auto 160%"
            exposure="0.9"
            shadow-intensity="0.5"
            style={{ display: 'block', width: '100%', height: '100%', backgroundColor: 'transparent' }}
          />
        )}
      </div>
      {paintedColors.length > 0 && (
        <div className="mt-3 flex flex-wrap items-center gap-2">
          <span className="text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">
            Preview paint
          </span>
          <button
            type="button"
            onClick={() => setTintName(null)}
            aria-pressed={tintName === null}
            className={`rounded-full border px-3 py-1 text-xs font-semibold transition-colors ${
              tintName === null
                ? 'border-[#8B5A2B] bg-[#8B5A2B] text-white'
                : 'border-[#D9D0C7] text-[#3B2314] hover:bg-[#F5F0EB]'
            }`}
          >
            As-authored
          </button>
          {paintedColors.map((name) => (
            <button
              key={name}
              type="button"
              onClick={() => setTintName(name)}
              aria-pressed={tintName === name}
              title={`${name} — ${paints[name]}`}
              className={`flex items-center gap-1.5 rounded-full border px-2.5 py-1 text-xs font-medium transition-colors ${
                tintName === name
                  ? 'border-[#8B5A2B] bg-[#8B5A2B]/10 text-[#3B2314]'
                  : 'border-[#D9D0C7] text-[#3B2314] hover:bg-[#F5F0EB]'
              }`}
            >
              <span
                className="h-3.5 w-3.5 rounded-full border border-black/10"
                style={{ backgroundColor: paints[name] }}
              />
              {name}
            </button>
          ))}
        </div>
      )}
      {shown && (
        <p className="mt-3 text-xs text-[#6B5C4E]">
          Version {shown.version} · {shown.status}. Drag to turn the shoe, scroll to zoom.
          {paintedColors.length > 0 && ' Chips preview the confirmed paints — the tint is what the app shows.'}
        </p>
      )}
    </Modal>
  )
}
