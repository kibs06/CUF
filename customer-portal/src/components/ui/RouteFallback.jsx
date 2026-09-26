import { Loader2 } from 'lucide-react'

/**
 * What a lazily-loaded route shows while its chunk arrives.
 *
 * A spinner rather than the shimmering skeleton each page has for its own data,
 * and the distinction is deliberate: a skeleton is a promise about the *shape*
 * of what is coming, and this component genuinely does not know it — the chunk
 * might be the dashboard or the product form. A skeleton that guesses wrong
 * reflows the moment the chunk lands, which reads as a glitch; a small centred
 * spinner reads as waiting, which is what is happening.
 *
 * It is `role="status"` rather than `role="alert"`: this is a normal, brief
 * state, and announcing it as an alert would interrupt a screen reader for a
 * component that is on screen for a few hundred milliseconds on a warm cache and
 * not at all after that.
 */
export default function RouteFallback() {
  return (
    <div
      role="status"
      className="flex min-h-[60vh] items-center justify-center"
      aria-label="Loading"
    >
      <Loader2 className="h-6 w-6 animate-spin text-muted" aria-hidden="true" />
    </div>
  )
}
