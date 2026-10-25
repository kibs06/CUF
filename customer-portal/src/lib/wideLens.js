/**
 * Wide-lens camera helper - the one place both camera surfaces agree on
 * "which lens" and "how far zoomed out".
 *
 * Phones love the tight lens: the default rear camera is often the
 * telephoto, so the subject fills the frame before the user is in
 * position (foot scan) or the shoe renders huge next to the camera app
 * (try-on). Used by `FootScan.jsx` (guided sweep) and `FootTryOnViewer.jsx`
 * (beta overlay) - a lens quirk fixed here is fixed in both places.
 * Pure picking, injectable opening: tests pass fakes, pages pass
 * `navigator.mediaDevices`.
 */

/**
 * Widest rear lens picker - pure over an enumerated device list.
 *
 * Given `enumerateDevices()` output as plain `{ deviceId, label, kind }`
 * objects, picks the ultrawide rear lens when its label says so and
 * otherwise the first rear lens - never a front/selfie lens unless the
 * phone exposes nothing else. Returns a deviceId or null.
 */
export function pickWidestRearLens(devices) {
  const videos = (Array.isArray(devices) ? devices : []).filter(
    (d) => d && d.kind === 'videoinput' && d.deviceId,
  )
  if (!videos.length) return null
  const rear = videos.filter(
    (d) => !/front|user|selfie|internal/i.test(d.label ?? ''),
  )
  const pool = rear.length ? rear : videos
  const ultra = pool.find((d) =>
    /ultra|0\.5|0\.6|wide.*angle/i.test(d.label ?? ''),
  )
  return (ultra ?? pool[0]).deviceId ?? null
}

/**
 * Zoom range of a video track, or null when the hardware says nothing.
 * Never throws - a missing capability is a normal phone, not an error.
 */
export function getZoomRange(track) {
  try {
    const zoom = track?.getCapabilities?.()?.zoom
    if (zoom && Number.isFinite(zoom.min)) {
      return {
        min: zoom.min,
        max: Number.isFinite(zoom.max) ? zoom.max : zoom.min,
      }
    }
  } catch {
    // Unreadable capabilities - treat as no zoom control.
  }
  return null
}

/**
 * Open the widest rear lens, stopping the current stream on success.
 * Returns the live stream - the opened wide stream, or the base stream
 * when already widest. `open` is `(constraints) => Promise<MediaStream>`
 * (page passes a `getUserMedia` wrapper), `enumerate` lists devices.
 * Throws on failure so the caller can keep its base stream - refusal
 * is routine.
 */
export async function openWidestLensStream({ open, enumerate, stream, width = 1280, height = 720 }) {
  const devices = await enumerate()
  const currentId = stream.getVideoTracks()[0]?.getSettings?.()?.deviceId ?? null
  const wideId = pickWidestRearLens(devices)
  if (!wideId || wideId === currentId) return stream
  const wide = await open({
    deviceId: { exact: wideId },
    width: { ideal: width },
    height: { ideal: height },
  })
  stream.getTracks().forEach((t) => t.stop())
  return wide
}

/**
 * Pin a video track to its minimum zoom. Returns true when a zoom was
 * actually applied, false when the hardware refused or has no control.
 * Never throws - zoom is advisory, framing must survive its absence.
 */
export async function pinMinZoom(track) {
  try {
    const range = getZoomRange(track)
    if (!range || !track) return false
    await track.applyConstraints({ advanced: [{ zoom: range.min }] })
    return true
  } catch {
    return false
  }
}
