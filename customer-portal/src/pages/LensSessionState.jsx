import { useCameraKit } from '@snap/react-camera-kit'

/**
 * Status pill for the hidden `/try-lens` mount.
 *
 * The mount used to fail silently: a denied camera or a stuck session left a
 * black box with no message, because `LensPlayer`'s `onError` only fires for
 * lens errors — camera-source and SDK errors surface here instead, through
 * `sdkStatus` / `source.status` / `lens.status` (`none` → `loading` →
 * `ready` | `error`). Rendered inside `CameraKitProvider` (hooks rule), as an
 * overlay that disappears once the lens is ready. Lazy-loaded by `TryLens`
 * so the Camera Kit runtime still stays out of the main bundle.
 */
export default function LensSessionState() {
  const { sdkStatus, sdkError, source, lens } = useCameraKit()

  let text = null
  if (sdkStatus === 'error') {
    text = `Camera Kit failed: ${sdkError?.message ?? 'unknown error'}`
  } else if (sdkStatus !== 'ready') {
    text = 'Starting camera session…'
  } else if (source?.status === 'error') {
    text =
      'Camera blocked — allow access (tap the lock icon in the address bar), then press Retry below.'
  } else if (source?.status !== 'ready') {
    text = 'Setting up camera…'
  } else if (lens?.status === 'error') {
    text = `Lens error: ${lens?.error?.message ?? 'unknown error'}`
  } else if (lens?.status !== 'ready') {
    text = 'Loading the Lens…'
  }

  if (!text) return null

  return (
    <div className="pointer-events-none absolute left-3 top-3 max-w-[calc(100%-1.5rem)] rounded-full bg-stone-950/80 px-3 py-1.5 text-xs text-stone-100">
      {text}
    </div>
  )
}
