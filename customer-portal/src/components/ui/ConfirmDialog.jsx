import { useEffect, useRef } from 'react'
import { createPortal } from 'react-dom'
import { AlertTriangle, X } from 'lucide-react'

/**
 * A yes/no dialog for the two destructive things Settings offers.
 *
 * `CancelOrderDialog` is the same shape but a different job (it collects a
 * reason), so this is the plain version: a question, a consequence, and a
 * button that says what it does. The confirm button's label is always the verb
 * — "Log out", "Request deletion" — never "OK", because "OK" on a destructive
 * action is a label the customer has to decode twice.
 *
 * Same three decisions as the order dialog, for the same reasons:
 *
 *  1. **It portals into `document.body`.** `fixed inset-0` only means "the
 *     window" when no ancestor is transformed, and the page wrapper animates a
 *     transform for the first 260ms of every route.
 *  2. **It mounts and unmounts with `open`**, animating in with CSS. No exit
 *     animation, so a stalled frame loop cannot leave a transparent sheet over
 *     the site eating clicks.
 *  3. **The scroll lock is keyed to `open`**, so it cannot outlive the dialog.
 */
export default function ConfirmDialog({
  open,
  title,
  description,
  confirmLabel,
  cancelLabel = 'Cancel',
  tone = 'danger',
  pending = false,
  error = null,
  onConfirm,
  onClose,
}) {
  const confirmRef = useRef(null)

  useEffect(() => {
    if (!open) return undefined

    const onKeyDown = (event) => {
      if (event.key === 'Escape' && !pending) onClose?.()
    }

    const previousOverflow = document.body.style.overflow
    document.body.style.overflow = 'hidden'
    window.addEventListener('keydown', onKeyDown)
    // Focus the confirm button rather than the panel: a keyboard user who
    // opened this wants to answer it, and the first Tab from the panel would
    // otherwise land on the close button.
    confirmRef.current?.focus()

    return () => {
      document.body.style.overflow = previousOverflow
      window.removeEventListener('keydown', onKeyDown)
    }
  }, [open, pending, onClose])

  if (!open) return null

  const confirmClass =
    tone === 'danger'
      ? 'btn bg-crimson text-ink-inverse shadow-warm hover:bg-crimson/90'
      : 'btn btn-primary'

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
        aria-labelledby="confirm-dialog-title"
        onClick={(event) => event.stopPropagation()}
        className="rise-enter w-full max-w-md rounded-card border border-hairline bg-raised shadow-premium"
      >
        <header className="flex items-start gap-3 border-b border-hairline-soft p-5">
          {tone === 'danger' && (
            <span className="mt-0.5 flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-crimson/10">
              <AlertTriangle size={17} className="text-crimson" strokeWidth={2} />
            </span>
          )}

          <div className="min-w-0 flex-1">
            <h2
              id="confirm-dialog-title"
              className="font-display text-lg font-semibold text-ink"
            >
              {title}
            </h2>
            {description && (
              <p className="mt-2 whitespace-pre-line text-sm leading-relaxed text-muted">
                {description}
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

        {error && (
          <p
            role="alert"
            className="border-b border-hairline-soft bg-crimson/[0.07] px-5 py-3 text-xs leading-relaxed text-ink"
          >
            {error}
          </p>
        )}

        <footer className="flex flex-col-reverse gap-2 p-5 sm:flex-row sm:justify-end">
          <button
            type="button"
            onClick={() => !pending && onClose?.()}
            className="btn btn-outline"
          >
            {cancelLabel}
          </button>
          <button
            ref={confirmRef}
            type="button"
            disabled={pending}
            onClick={() => onConfirm?.()}
            className={`${confirmClass} disabled:cursor-not-allowed disabled:opacity-60`}
          >
            {pending ? 'Working…' : confirmLabel}
          </button>
        </footer>
      </div>
    </div>,
    document.body,
  )
}
