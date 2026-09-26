import { useEffect, useRef, useState } from 'react'
import { createPortal } from 'react-dom'
import { AlertTriangle, X } from 'lucide-react'

import { CANCELLATION_REASONS, OTHER_REASON } from '../../lib/orders'

/**
 * Cancelling an order, or asking the maker to.
 *
 * The dialog is deliberately two-step in the same panel — pick a reason, then
 * confirm — rather than a "Confirm?" on top of a reason sheet. The reason IS
 * the decision: "ordered the wrong size" and "the seller is not responding" are
 * different problems, and a customer who picks one by accident has no way to
 * tell from a yes/no dialog.
 *
 * The consequence is stated in the customer's terms, not ours, and it differs
 * by transition: an outright cancel is final, while a request is answered by a
 * person and can be refused. Saying "this cannot be undone" for both would make
 * the second one a lie.
 *
 * It mounts and unmounts with `open`, animating in through CSS (`fade-enter` on
 * the backdrop, `rise-enter` on the panel). This is the one overlay where a
 * stuck exit would be genuinely dangerous rather than merely ugly: the backdrop
 * is `fixed inset-0`, so an invisible dialog left in the DOM is a transparent
 * sheet over the whole site that eats every click — and a stalled frame loop is
 * exactly how that used to happen. It disappears the moment `open` says so.
 *
 * The scroll lock and the Escape handler are keyed to `open` rather than to the
 * animation, so neither can outlive the dialog either.
 *
 * It renders through a portal into `document.body`, which is where a modal
 * belongs: `fixed inset-0` only means "the window" if no ancestor is
 * transformed, filtered or contained, and the page wrapper animates its
 * transform for the first 260ms of every route. Portalling removes the dialog
 * from that risk permanently instead of relying on nobody ever adding a
 * transform above it.
 */
export default function CancelOrderDialog({
  open,
  plan,
  pending = false,
  error = null,
  onClose,
  onConfirm,
}) {
  const [reason, setReason] = useState(CANCELLATION_REASONS[0])
  const [details, setDetails] = useState('')
  const firstRef = useRef(null)

  // Reset on every open: a reason left over from a previous order would be
  // submitted against this one, and the customer would never see it happen.
  useEffect(() => {
    if (open) {
      setReason(CANCELLATION_REASONS[0])
      setDetails('')
    }
  }, [open])

  useEffect(() => {
    if (!open) return undefined

    const onKeyDown = (event) => {
      if (event.key === 'Escape' && !pending) onClose?.()
    }

    const previousOverflow = document.body.style.overflow
    document.body.style.overflow = 'hidden'
    window.addEventListener('keydown', onKeyDown)
    firstRef.current?.focus()

    return () => {
      document.body.style.overflow = previousOverflow
      window.removeEventListener('keydown', onKeyDown)
    }
  }, [open, pending, onClose])

  const needsDetails = reason === OTHER_REASON
  const blocked = needsDetails && details.trim().length === 0
  const isRequest = plan?.kind === 'request'

  if (!open) return null

  return createPortal(
    <div
      className="fade-enter fixed inset-0 z-50 flex items-end justify-center overflow-y-auto bg-scrim p-4 backdrop-blur-[2px] sm:items-center"
      onClick={() => {
        if (!pending) onClose?.()
      }}
    >
      <div
        role="dialog"
        aria-modal="true"
        aria-labelledby="cancel-order-title"
        onClick={(event) => event.stopPropagation()}
        className="rise-enter w-full max-w-lg rounded-card border border-hairline bg-raised shadow-premium"
      >
        <header className="flex items-start gap-3 border-b border-hairline-soft p-5">
          <span className="mt-0.5 flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-crimson/10">
            <AlertTriangle size={17} className="text-crimson" strokeWidth={2} />
          </span>

          <div className="min-w-0 flex-1">
            <h2
              id="cancel-order-title"
              className="font-display text-lg font-semibold text-ink"
            >
              {isRequest ? 'Ask to cancel this order' : 'Cancel this order'}
            </h2>
            <p className="mt-1 text-xs leading-relaxed text-muted">
              {isRequest
                ? 'The maker has begun working on it, so your request goes to them for approval.'
                : 'This cancels the order straight away and cannot be undone.'}
            </p>
            {plan?.closesAt && (
              <p className="mt-1 text-xs font-semibold text-amber">
                You have {remainingLabel(plan.closesAt)} left in the
                cancellation window.
              </p>
            )}
          </div>

          <button
            type="button"
            onClick={() => !pending && onClose?.()}
            aria-label="Close"
            className="-mr-1 -mt-1 inline-flex h-8 w-8 shrink-0 items-center justify-center rounded-full text-muted transition-colors duration-200 hover:bg-subtle hover:text-ink"
          >
            <X size={16} strokeWidth={2} />
          </button>
        </header>

        <div className="max-h-[52vh] overflow-y-auto p-5">
          <fieldset>
            <legend className="text-xs font-semibold uppercase tracking-[0.08em] text-muted">
              Why are you cancelling?
            </legend>

            <div className="mt-3 space-y-1.5">
              {CANCELLATION_REASONS.map((option, index) => (
                <label
                  key={option}
                  className={`flex cursor-pointer items-start gap-3 rounded-field border px-3 py-2.5 text-sm transition-colors duration-200 ease-out-cubic ${
                    reason === option
                      ? 'border-clay/40 bg-clay/[0.06] text-ink'
                      : 'border-hairline text-muted-strong hover:border-card-edge hover:bg-subtle/60'
                  }`}
                >
                  <input
                    ref={index === 0 ? firstRef : undefined}
                    type="radio"
                    name="cancellation-reason"
                    value={option}
                    checked={reason === option}
                    onChange={() => setReason(option)}
                    className="mt-0.5 h-4 w-4 shrink-0 accent-clay"
                  />
                  <span className="leading-snug">{option}</span>
                </label>
              ))}
            </div>
          </fieldset>

          {needsDetails && (
            <div className="mt-4">
              <label
                htmlFor="cancellation-details"
                className="block text-xs font-semibold uppercase tracking-[0.08em] text-muted"
              >
                Tell us a little more
              </label>
              <textarea
                id="cancellation-details"
                rows={3}
                value={details}
                onChange={(event) => setDetails(event.target.value)}
                maxLength={300}
                aria-invalid={blocked ? 'true' : undefined}
                className="mt-2 w-full resize-none rounded-field border border-hairline bg-raised px-4 py-3 text-sm text-ink transition-colors duration-200 ease-out-cubic hover:border-card-edge focus:border-clay"
              />
              <p className="mt-1 text-xs text-muted">
                The maker reads this, so keep it short and specific.
              </p>
            </div>
          )}

          {error && (
            <p
              role="alert"
              className="mt-4 rounded-field border border-crimson/30 bg-crimson/[0.07] px-3 py-2 text-xs leading-relaxed text-ink"
            >
              {error}
            </p>
          )}
        </div>

        <footer className="flex flex-col-reverse gap-2 border-t border-hairline-soft p-5 sm:flex-row sm:justify-end">
          <button
            type="button"
            onClick={() => !pending && onClose?.()}
            className="btn btn-outline"
          >
            Keep the order
          </button>
          <button
            type="button"
            disabled={pending || blocked}
            onClick={() => onConfirm?.({ reason, details: details.trim() })}
            className="btn bg-crimson text-ink-inverse shadow-warm transition-colors duration-200 hover:bg-crimson/90 disabled:cursor-not-allowed disabled:opacity-60"
          >
            {pending
              ? 'Sending…'
              : isRequest
                ? 'Send the request'
                : 'Cancel this order'}
          </button>
        </footer>
      </div>
    </div>,
    document.body,
  )
}

/**
 * `1h 24m` — how long is left in the two-hour window.
 *
 * Minutes, not seconds: the countdown on the cancellation window is a courtesy,
 * and a ticking clock beside a destructive button reads as pressure rather than
 * information. The server is what enforces the deadline either way.
 */
function remainingLabel(closesAt) {
  const msLeft = new Date(closesAt).getTime() - Date.now()
  if (!Number.isFinite(msLeft) || msLeft <= 0) return 'no time'

  const minutes = Math.max(1, Math.floor(msLeft / 60_000))
  const hours = Math.floor(minutes / 60)
  if (hours <= 0) return `${minutes}m`

  const rest = minutes % 60
  return rest > 0 ? `${hours}h ${rest}m` : `${hours}h`
}
