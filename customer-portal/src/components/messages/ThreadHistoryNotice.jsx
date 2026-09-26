import { RefreshCw, TriangleAlert } from 'lucide-react'

/**
 * What a thread says when its history did not load.
 *
 * A chat that cannot load its history has two ways to fail, and both of them
 * used to be silent:
 *
 *  * **Nothing loaded.** The list was empty, so the thread drew its empty state —
 *    *"Say hello to Shaine Jayne"* — over a conversation that may be months deep.
 *    Nothing about that screen says \"something went wrong\", and nothing on it can
 *    be clicked to try again.
 *  * **Only the live messages loaded.** The read failed but Postgres Realtime kept
 *    delivering, so the thread filled up from the bottom: it *looked* complete,
 *    and the older messages were simply absent with no indication they had ever
 *    existed. This is the shape that produces the report \"the history is missing
 *    but new messages arrive\".
 *
 * So the failed read gets a face, and the copy differs because the two cases
 * differ: with nothing to show it is the whole panel, and with live messages in
 * view it is a strip **above** them that says the rest is missing — replacing the
 * live messages with an error would throw away the only messages the reader has.
 *
 * Neither is a modal, neither blocks the composer, and the retry is a real button
 * because \"try again\" is the only thing anyone wants from this notice. `isError`
 * comes from the query, never from an empty array: RLS answers `200 []` for a
 * denied read, so emptiness on its own proves nothing — see `threadHistoryState`.
 */
export default function ThreadHistoryNotice({ state, onRetry, className = '' }) {
  if (state !== 'failed' && state !== 'partial') return null

  const isTotal = state === 'failed'

  return (
    <div
      role="status"
      className={[
        'rounded-card border border-hairline bg-subtle',
        isTotal
          ? 'flex flex-col items-center gap-3 px-5 py-8 text-center'
          : 'flex items-center gap-3 px-3 py-2.5',
        className,
      ].join(' ')}
    >
      <span
        className={[
          'flex shrink-0 items-center justify-center rounded-full bg-amber/10',
          isTotal ? 'h-11 w-11' : 'h-8 w-8',
        ].join(' ')}
      >
        <TriangleAlert
          size={isTotal ? 20 : 15}
          strokeWidth={1.75}
          className="text-amber"
          aria-hidden="true"
        />
      </span>

      <div className={isTotal ? 'min-w-0' : 'min-w-0 flex-1 text-left'}>
        <p
          className={
            isTotal
              ? 'font-display text-lg font-semibold text-ink'
              : 'text-xs font-semibold text-ink'
          }
        >
          {isTotal ? 'Could not load this conversation' : 'Showing only recent messages'}
        </p>
        <p
          className={
            isTotal ? 'mt-1 max-w-sm text-sm leading-relaxed text-muted' : 'text-xs text-muted'
          }
        >
          {isTotal
            ? 'The messages are still there — this is the page failing to read them, not an empty thread.'
            : 'The earlier messages in this thread could not be loaded, so what is below arrived while you were reading.'}
        </p>
      </div>

      <button
        type="button"
        onClick={onRetry}
        className={
          isTotal
            ? 'btn btn-outline'
            : 'inline-flex shrink-0 items-center gap-1.5 text-xs font-semibold text-clay-ink transition-colors duration-200 ease-out-cubic hover:text-ink'
        }
      >
        <RefreshCw size={isTotal ? 15 : 13} strokeWidth={2} aria-hidden="true" />
        Try again
      </button>
    </div>
  )
}
