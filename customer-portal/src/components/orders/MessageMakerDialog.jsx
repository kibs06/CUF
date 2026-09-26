import { useEffect, useRef, useState } from 'react'
import { createPortal } from 'react-dom'
import { MessageSquare, X } from 'lucide-react'

import { quickOrderMessages } from '../../lib/messages.js'

/**
 * Writing to the maker about one order — the app's
 * `order_quick_message_sheet.dart`.
 *
 * ## Why the questions are a list and not a blank box
 *
 * A customer who opens this has one of a handful of questions — where is my
 * pair, can I change the size, can I change the address — and a blank textarea
 * makes them write it out in their own words, in a language the maker may not
 * share, from a phone keyboard. The four canned lines are the app's own, in its
 * own order, and they are a *starting* point: picking one fills the box rather
 * than sending it, so anything can be edited before it goes.
 *
 * The list changes with the order's state (`quickOrderMessages`): "When will my
 * order ship?" is a strange question about a cancelled order, and "I have an
 * issue" is a strange opener on one still being made.
 *
 * ## The message carries the order
 *
 * It is sent with `order_reference_id`, so the maker's side can see which order
 * is meant without the customer typing a number — and the thread stays one
 * thread per maker, in order, like every other conversation with them.
 *
 * Mounts and unmounts with `open`, animating in through CSS (`fade-enter` on the
 * backdrop, `rise-enter` on the panel); the scroll lock and the Escape handler
 * are keyed to `open` too, so a stuck exit cannot leave a transparent
 * `fixed inset-0` sheet over the whole site. See "Animations must fail open" in
 * the README.
 */
export default function MessageMakerDialog({
  open,
  storeName = 'the maker',
  orderStatus,
  pending = false,
  error = null,
  onClose,
  onSend,
}) {
  const [body, setBody] = useState('')
  const firstRef = useRef(null)

  // Reset on every open: a draft left from a previous order would be sent
  // against this one, and the customer would never see it happen.
  useEffect(() => {
    if (open) setBody('')
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

  if (!open) return null

  const suggestions = quickOrderMessages(orderStatus)
  const blocked = body.trim().length === 0

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
        aria-labelledby="message-maker-title"
        onClick={(event) => event.stopPropagation()}
        className="rise-enter w-full max-w-lg rounded-card border border-hairline bg-raised shadow-premium"
      >
        <header className="flex items-start gap-3 border-b border-hairline-soft p-5">
          <span className="mt-0.5 flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-clay/12">
            <MessageSquare size={17} className="text-clay-ink" strokeWidth={2} />
          </span>

          <div className="min-w-0 flex-1">
            <h2 id="message-maker-title" className="font-display text-lg font-semibold text-ink">
              Message {storeName}
            </h2>
            <p className="mt-1 text-xs leading-relaxed text-muted">
              It goes into your thread with them, tagged with this order. Pick a
              question or write your own.
            </p>
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
          <div className="flex flex-wrap gap-2" role="group" aria-label="Common questions">
            {suggestions.map((suggestion) => (
              <button
                key={suggestion}
                type="button"
                onClick={() => {
                  setBody(suggestion)
                  firstRef.current?.focus()
                }}
                aria-pressed={body === suggestion}
                className={`rounded-full border px-3 py-1.5 text-left text-xs font-medium transition-colors duration-200 ease-out-cubic ${
                  body === suggestion
                    ? 'border-clay bg-clay text-ink-inverse'
                    : 'border-hairline text-muted-strong hover:border-card-edge hover:text-ink'
                }`}
              >
                {suggestion}
              </button>
            ))}
          </div>

          <label
            htmlFor="message-maker-body"
            className="mt-5 block text-xs font-semibold uppercase tracking-[0.08em] text-muted"
          >
            Your message
          </label>
          <textarea
            id="message-maker-body"
            ref={firstRef}
            rows={4}
            value={body}
            onChange={(event) => setBody(event.target.value)}
            maxLength={1000}
            placeholder="Tell the maker what you need…"
            className="mt-2 w-full resize-none rounded-field border border-hairline bg-raised px-4 py-3 text-sm text-ink transition-colors duration-200 ease-out-cubic hover:border-card-edge focus:border-clay"
          />

          {error && (
            <p
              role="alert"
              className="mt-3 rounded-field border border-crimson/30 bg-crimson/[0.07] px-3 py-2 text-xs leading-relaxed text-ink"
            >
              {error}
            </p>
          )}
        </div>

        <footer className="flex flex-col-reverse gap-2 border-t border-hairline-soft p-5 sm:flex-row sm:justify-end">
          <button type="button" onClick={() => !pending && onClose?.()} className="btn btn-outline">
            Cancel
          </button>
          <button
            type="button"
            disabled={pending || blocked}
            onClick={() => onSend?.({ body: body.trim() })}
            className="btn btn-primary disabled:cursor-not-allowed disabled:opacity-60"
          >
            {pending ? 'Sending…' : 'Send message'}
          </button>
        </footer>
      </div>
    </div>,
    document.body,
  )
}
