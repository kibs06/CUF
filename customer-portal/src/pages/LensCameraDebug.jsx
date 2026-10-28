import { useEffect, useState } from 'react'

/**
 * Probe overlay for the hidden `/try-lens` mount.
 *
 * The portal feed renders far tighter than the phone's native camera app,
 * and the fix depends on where the magnification lives: browser camera
 * selection (wrong physical camera / zoomed track) vs the Lens render
 * path (Camera Kit cropping/scaling a healthy stream). This opens a
 * throwaway stream with the *same* constraints the player uses, reads the
 * real track settings + zoom capability, then stops it — the session's own
 * track is unreachable (wrapper-owned, canvas-rendered). Report the two
 * lines it prints; they decide the next fix.
 */
export default function LensCameraDebug() {
  const [lines, setLines] = useState(['probing camera…'])

  useEffect(() => {
    let cancelled = false
    ;(async () => {
      try {
        const stream = await navigator.mediaDevices.getUserMedia({
          video: {
            facingMode: 'environment',
            width: { ideal: 960 },
            height: { ideal: 1280 },
            zoom: { ideal: 1 },
          },
          audio: false,
        })
        const track = stream.getVideoTracks()[0]
        const s = track?.getSettings?.() ?? {}
        const c = track?.getCapabilities?.() ?? {}
        track?.stop()
        if (cancelled) return
        const base = [
          `stream: ${s.width ?? '?'}x${s.height ?? '?'} zoom=${s.zoom ?? 'n/a'} facing=${s.facingMode ?? 'n/a'}`,
          `label: ${(track?.label ?? '').slice(0, 42) || 'n/a'}`,
          `zoom cap: ${c.zoom ? `${c.zoom.min}–${c.zoom.max}` : 'none (browser exposes no zoom)'}`,
        ]
        // Inventory every physical camera so we can pick the ultrawide
        // (0.5x) instead of the default wide. Labels need the granted
        // permission above, which is why this runs second.
        try {
          const devices = (await navigator.mediaDevices.enumerateDevices()).filter(
            (d) => d.kind === 'videoinput',
          )
          const rows = []
          for (let i = 0; i < devices.length; i += 1) {
            const dev = devices[i]
            const shortLabel = (dev.label || `camera ${i}`).slice(0, 40)
            try {
              const ds = await navigator.mediaDevices.getUserMedia({
                video: { deviceId: { exact: dev.deviceId }, width: { ideal: 1280 } },
                audio: false,
              })
              const dt = ds.getVideoTracks()[0]
              const dset = dt?.getSettings?.() ?? {}
              const dcap = dt?.getCapabilities?.() ?? {}
              dt?.stop()
              const z = dcap.zoom ? `zoom ${dcap.zoom.min}–${dcap.zoom.max}` : 'zoom n/a'
              rows.push(`cam${i}: ${shortLabel} ${dset.width ?? '?'}x${dset.height ?? '?'} ${z}`)
            } catch {
              rows.push(`cam${i}: ${shortLabel} (unavailable)`)
            }
            if (cancelled) return
          }
          setLines([...base, ...rows])
        } catch {
          setLines(base)
        }
      } catch (e) {
        if (!cancelled) setLines([`probe failed: ${e?.name ?? 'error'} ${e?.message ?? ''}`.slice(0, 120)])
      }
    })()
    return () => {
      cancelled = true
    }
  }, [])

  return (
    <div className="pointer-events-none absolute bottom-3 left-3 max-w-[calc(100%-1.5rem)] rounded-lg bg-stone-950/80 px-2.5 py-1.5 font-mono text-[11px] leading-snug text-lime-200">
      {lines.map((l) => (
        <div key={l}>{l}</div>
      ))}
    </div>
  )
}
