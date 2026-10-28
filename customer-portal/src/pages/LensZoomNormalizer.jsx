import { useEffect } from 'react'
import { useCameraKit } from '@snap/react-camera-kit'

/**
 * Best-effort un-zoomer for the hidden `/try-lens` mount.
 *
 * On several phones the rear camera boots over-zoomed — feet unframeable —
 * and Camera Kit documents no zoom prop. The magnification lives on the
 * underlying `MediaStreamTrack`, so once the session is ready we ask that
 * track for its real range and dial it to minimum (1x) where the browser
 * exposes zoom. Phones without track-zoom support keep their current frame;
 * the 4:3 `cameraConstraints` on the player are the fallback there.
 */
export default function LensZoomNormalizer() {
  const { sdkStatus, source } = useCameraKit()

  useEffect(() => {
    if (sdkStatus !== 'ready' || source?.status !== 'ready') return
    let cancelled = false
    ;(async () => {
      try {
        const stream = await navigator.mediaDevices.getUserMedia({
          video: { facingMode: { ideal: 'environment' } },
        })
        const track = stream.getVideoTracks()[0]
        // Inspect only — the track we can see is a sibling of the session's,
        // but capabilities (zoom range or none) match the same camera.
        const caps = track.getCapabilities?.()
        track.stop()
        if (cancelled || !caps || !('zoom' in caps)) return
        const sessionTrack = document
          .querySelector('[data-testid="lens-mount"] video')
          ?.srcObject?.getVideoTracks?.()[0]
        await sessionTrack?.applyConstraints?.({
          advanced: [{ zoom: caps.zoom.min }],
        })
      } catch {
        // Zoom unsupported or denied mid-flight: keep the current frame.
      }
    })()
    return () => {
      cancelled = true
    }
  }, [sdkStatus, source?.status])

  return null
}
