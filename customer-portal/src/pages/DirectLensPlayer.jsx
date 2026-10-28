import { useEffect, useRef, useState } from 'react'
import {
  bootstrapCameraKit,
  createMediaStreamSource,
  Transform2D,
} from '@snap/camera-kit'

/**
 * Production player for the hidden `/try-lens` route.
 *
 * Rear camera + footwear lens, fullscreen, no chrome. Owns its own
 * MediaStream (the `@snap/react-camera-kit` wrapper drops `deviceId` on
 * all mobile and assumes landscape capture). Handles the two phone
 * realities: portrait track (identity transform) or landscape sensor
 * buffer (rotate -90 to upright portrait). Render size always matches
 * the upright frame; the canvas fills the screen with `cover`.
 */
export default function DirectLensPlayer({ apiToken, lensId, lensGroupId, onError }) {
  const containerRef = useRef(null)
  const sessionRef = useRef(null)
  const kitRef = useRef(null)
  const streamRef = useRef(null)
  const sourceRef = useRef(null)
  const [status, setStatus] = useState('Starting camera session…')

  useEffect(() => {
    let cancelled = false
    const openStream = (constraints) =>
      navigator.mediaDevices.getUserMedia({ video: constraints, audio: false })
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
        canvas.style.background = '#000'
        containerRef.current?.appendChild(canvas)
        setStatus('Opening camera…')
        const stream = await openStream({
          facingMode: 'environment',
          width: { ideal: 960 },
          height: { ideal: 1280 },
        })
        if (cancelled) {
          stream.getTracks().forEach((t) => t.stop())
          return
        }
        const track = stream.getVideoTracks()[0]
        const settings = track?.getSettings?.() ?? {}
        const caps = track?.getCapabilities?.() ?? {}
        if (caps.zoom && caps.zoom.max > caps.zoom.min) {
          await track.applyConstraints({ advanced: [{ zoom: caps.zoom.min }] }).catch(() => {})
        }
        const source = createMediaStreamSource(stream, { cameraType: 'environment' })
        try {
          await sourceRef.current?.detach(() => {})
        } catch {}
        sourceRef.current = source
        const trackW = settings.width ?? 720
        const trackH = settings.height ?? 1280
        const needRotate = window.innerHeight >= window.innerWidth && trackW > trackH
        const w = needRotate ? trackH : trackW
        const h = needRotate ? trackW : trackH
        try {
          await session.pause('live')
        } catch {}
        await session.setSource(source)
        await source.setTransform(
          needRotate ? new Transform2D([0, -1, 0, 1, 0, 0, 0, 1, 1]) : Transform2D.Identity,
        )
        await source.setRenderSize(w, h)
        await session.play('live')
        streamRef.current?.getTracks().forEach((t) => t.stop())
        streamRef.current = stream
        const lens = await kit.lensRepository.loadLens(lensId, lensGroupId)
        if (cancelled) return
        await session.applyLens(lens)
        if (cancelled) return
        setStatus('')
      } catch (e) {
        if (cancelled) return
        const message =
          e?.name === 'NotAllowedError'
            ? 'Camera blocked — allow access (tap the lock icon in the address bar), then press Retry below.'
            : `Camera failed: ${e?.message ?? 'unknown error'}`
        setStatus(message)
        onError?.(message)
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

  return (
    <div className="relative h-full w-full">
      <div ref={containerRef} className="h-full w-full" />
      {status !== '' && (
        <div className="pointer-events-none absolute left-3 top-3 max-w-[calc(100%-1.5rem)] rounded-full bg-stone-950/80 px-3 py-1.5 text-xs text-stone-100">
          {status}
        </div>
      )}
    </div>
  )
}
