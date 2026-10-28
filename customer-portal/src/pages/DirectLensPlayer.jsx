import { useEffect, useRef, useState } from 'react'
import {
  bootstrapCameraKit,
  createMediaStreamSource,
  Transform2D,
} from '@snap/camera-kit'

/**
 * Camera Kit player with full camera control (hidden `/try-lens` only).
 *
 * Why this exists instead of `LensPlayer` from `@snap/react-camera-kit`:
 * the wrapper drops `deviceId` on ALL mobile and swaps w/h when deriving
 * the render size, so on phones it can only ever open the default rear
 * camera at an assumed orientation. This player owns its own MediaStream,
 * so it can open any physical camera by `deviceId` (e.g. the widest-FOV
 * rear camera for foot fitting) and dial zoom to minimum.
 */
export default function DirectLensPlayer({ apiToken, lensId, lensGroupId, onError }) {
  const containerRef = useRef(null)
  const sessionRef = useRef(null)
  const kitRef = useRef(null)
  const streamRef = useRef(null)
  const lensRef = useRef(null)
  const [lensOn, setLensOn] = useState(true)
  const [dbg, setDbg] = useState('')
  const [status, setStatus] = useState('Starting camera session…')
  const [cameras, setCameras] = useState([])
  const [activeId, setActiveId] = useState(null)
  const [zoom, setZoom] = useState(1)
  const [zoomCaps, setZoomCaps] = useState(null)

  const fail = (message) => {
    setStatus(message)
    onError?.(message)
  }

  const openStream = (constraints) =>
    navigator.mediaDevices.getUserMedia({ video: constraints, audio: false })

  const startCamera = async (deviceId) => {
    const session = sessionRef.current
    if (!session) return
    setStatus('Opening camera…')
    if (deviceId) {
      streamRef.current?.getTracks().forEach((tr) => tr.stop())
      streamRef.current = null
    }
    try {
      const stream = deviceId
        ? await openStream({ deviceId: { exact: deviceId }, width: { ideal: 1280 } })
        : await openStream({ facingMode: 'environment', width: { ideal: 960 }, height: { ideal: 1280 } })
      const track = stream.getVideoTracks()[0]
      const settings = track?.getSettings?.() ?? {}
      const caps = track?.getCapabilities?.() ?? {}
      const source = createMediaStreamSource(stream, { cameraType: 'environment' })
      await session.setSource(source)
      await source.setTransform(Transform2D.Identity)
      await session.play('live')
      const w = settings.width ?? 720
      const h = settings.height ?? 1280
      await source.setRenderSize(w, h).catch(() => {})
      streamRef.current?.getTracks().forEach((t) => t.stop())
      streamRef.current = stream
      setActiveId(deviceId ?? settings.deviceId ?? null)
      if (caps.zoom && caps.zoom.max > caps.zoom.min) {
        setZoomCaps({ min: caps.zoom.min, max: caps.zoom.max })
        setZoom(caps.zoom.min)
        await track.applyConstraints({ advanced: [{ zoom: caps.zoom.min }] }).catch(() => {})
      } else {
        setZoomCaps(null)
      }
      const canvas = session.output.live
      setDbg('src ' + w + 'x' + h + ' canvas ' + canvas.width + 'x' + canvas.height)
      setStatus('')
    } catch (e) {
      fail(
        e?.name === 'NotAllowedError'
          ? 'Camera blocked — allow access (tap the lock icon in the address bar), then press Retry below.'
          : `Camera failed: ${e?.message ?? 'unknown error'}`,
      )
    }
  }

  useEffect(() => {
    let cancelled = false
    ;(async () => {
      try {
        const kit = await bootstrapCameraKit({ apiToken })
        if (cancelled) {
          await kit.destroy().catch(() => {})
          return
        }
        kitRef.current = kit
        const session = await kit.createSession()
        if (cancelled) {
          await kit.destroy().catch(() => {})
          return
        }
        sessionRef.current = session
        const canvas = session.output.live
        canvas.style.width = '100%'
        canvas.style.height = '100%'
        canvas.style.objectFit = 'cover'
        containerRef.current?.appendChild(canvas)
        const lens = await kit.lensRepository.loadLens(lensId, lensGroupId)
        if (cancelled) return
        await session.applyLens(lens)
        lensRef.current = lens
        if (cancelled) return
        await startCamera(null)
        if (cancelled) return
        try {
          const devices = (await navigator.mediaDevices.enumerateDevices()).filter(
            (d) => d.kind === 'videoinput',
          )
          const rows = []
          for (const dev of devices) {
            try {
              const ds = await openStream({ deviceId: { exact: dev.deviceId }, width: { ideal: 1280 } })
              const dt = ds.getVideoTracks()[0]
              const dset = dt?.getSettings?.() ?? {}
              const dcap = dt?.getCapabilities?.() ?? {}
              ds.getTracks().forEach((t) => t.stop())
              rows.push({
                deviceId: dev.deviceId,
                label: dev.label || 'camera',
                width: dset.width ?? null,
                height: dset.height ?? null,
                facing: dset.facingMode ?? '',
                zoomMin: dcap.zoom?.min ?? null,
              })
            } catch {
              rows.push({ deviceId: dev.deviceId, label: dev.label || 'camera', width: null, height: null, facing: '', zoomMin: null })
            }
            if (cancelled) return
          }
          rows.sort((a, b) => {
            const back = (r) => (/back|rear|environment/i.test(r.label) || r.facing === 'environment' ? 0 : 1)
            return back(a) - back(b)
          })
          setCameras(rows)
        } catch {
          // Inventory is a nice-to-have; the default camera already runs.
        }
      } catch (e) {
        if (!cancelled) fail(`Camera Kit failed: ${e?.message ?? 'unknown error'}`)
      }
    })()
    return () => {
      cancelled = true
      streamRef.current?.getTracks().forEach((t) => t.stop())
      streamRef.current = null
      const canvas = sessionRef.current?.output.live
      if (canvas && canvas.parentElement === containerRef.current) containerRef.current.removeChild(canvas)
      sessionRef.current = null
      kitRef.current?.destroy().catch(() => {})
      kitRef.current = null
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  const toggleLens = async () => {
    const session = sessionRef.current
    if (!session) return
    try {
      if (lensOn) {
        await session.removeLens()
        setLensOn(false)
      } else if (lensRef.current) {
        await session.applyLens(lensRef.current)
        setLensOn(true)
      }
    } catch (e) {
      fail('Lens toggle failed: ' + (e?.message ?? 'unknown error'))
    }
  }

  const applyZoom = async (value) => {
    setZoom(value)
    try {
      await streamRef.current?.getVideoTracks()[0]?.applyConstraints({ advanced: [{ zoom: value }] })
    } catch {
      // Track ignores live zoom changes; frame stays as-is.
    }
  }

  return (
    <div className="relative h-full w-full">
      <div ref={containerRef} className="h-full w-full" />
      {status !== '' && (
        <div className="pointer-events-none absolute left-3 top-3 max-w-[calc(100%-1.5rem)] rounded-full bg-stone-950/80 px-3 py-1.5 text-xs text-stone-100">
          {status}
        </div>
      )}
      <div className="absolute inset-x-0 bottom-3 flex flex-col items-center gap-2 px-3">
        {dbg !== '' && (
          <div className="rounded-full bg-stone-950/80 px-3 py-1 font-mono text-[11px] text-lime-200">
            {dbg}
          </div>
        )}
        <button
          type="button"
          onClick={toggleLens}
          className="rounded-full bg-stone-950/80 px-3 py-1.5 text-xs text-stone-100"
        >
          {lensOn ? 'Lens: ON (tap for raw camera)' : 'Lens: OFF (raw camera)'}
        </button>
        {cameras.length > 1 && zoomCaps && (
            <div className="flex w-full max-w-xs items-center gap-2 rounded-full bg-stone-950/80 px-3 py-2">
              <span className="text-[11px] text-stone-300">Wide</span>
              <input
                type="range"
                min={zoomCaps.min}
                max={zoomCaps.max}
                step={0.1}
                value={Math.min(Math.max(zoom, zoomCaps.min), zoomCaps.max)}
                onChange={(e) => applyZoom(Number(e.target.value))}
                className="w-full"
                aria-label="Zoom"
              />
              <span className="font-mono text-[11px] text-stone-300">{zoom.toFixed(1)}x</span>
            </div>
          )}
        {cameras.length > 1 && (
          <div className="flex max-w-full gap-1.5 overflow-x-auto rounded-full bg-stone-950/80 p-1.5">
            {cameras.map((c, i) => {
              const isActive = activeId != null && c.deviceId === activeId
              const tag = c.width && c.height ? `${c.width}x${c.height}` : `cam${i}`
              return (
                <button
                  key={c.deviceId || i}
                  type="button"
                  onClick={() => startCamera(c.deviceId)}
                  className={
                    isActive
                      ? 'shrink-0 rounded-full bg-lime-200 px-2.5 py-1 font-mono text-[11px] text-stone-950'
                      : 'shrink-0 rounded-full bg-stone-800 px-2.5 py-1 font-mono text-[11px] text-stone-200'
                  }
                >
                  {isActive ? `* ${tag}` : tag}
                </button>
              )
            })}
          </div>
        )}
      </div>
    </div>
  )
}
