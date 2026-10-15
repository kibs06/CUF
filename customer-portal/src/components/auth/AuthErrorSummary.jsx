import { useEffect, useRef } from 'react'
import { TriangleAlert } from 'lucide-react'

/**
 * A failed submit, as a summary rather than a single sentence.
 *
 * Inline field errors stay where they are (they are the ones `aria-describedby`
 * points at) — this sits above the form so keyboard and screen-reader users
 * find it first: it takes focus on appearance, names every problem, and each
 * item links to the field it came from. Nothing here replaces an inline error;
 * a summary without them is a visual-only answer to an accessibility question.
 *
 * `links` maps an error key to the element id to jump to. Keys without a link
 * still render as text — a problem without a field (a refused submit, a lost
 * connection) has nowhere to point, but still deserves a sentence.
 */
export default function AuthErrorSummary({ errors, links = {}, title = 'There is a problem' }) {
  const ref = useRef(null)
  const items = Object.entries(errors ?? {}).filter(([, message]) => message)

  useEffect(() => {
    if (items.length > 0) ref.current?.focus()
    // Focus on appearance only — re-focusing on every keystroke would trap
    // the user at the top of the form while they are fixing it.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  if (items.length === 0) return null

  return (
    <div
      ref={ref}
      role="alert"
      tabIndex={-1}
      aria-labelledby="auth-error-title"
      className="rounded-field border border-crimson/30 bg-crimson/[0.07] px-4 py-3 outline-none focus-visible:ring-2 focus-visible:ring-crimson/50"
    >
      <p
        id="auth-error-title"
        className="flex items-center gap-2 text-sm font-semibold text-ink"
      >
        <TriangleAlert className="h-4 w-4 shrink-0 text-crimson" aria-hidden="true" />
        {title}
      </p>
      <ul className="mt-1.5 space-y-1 text-sm text-ink">
        {items.map(([key, message]) =>
          links[key] ? (
            <li key={key}>
              <a
                href={`#${links[key]}`}
                className="underline decoration-crimson/50 underline-offset-4 transition-colors duration-200 ease-out-cubic hover:text-crimson hover:decoration-crimson"
              >
                {message}
              </a>
            </li>
          ) : (
            <li key={key}>{message}</li>
          ),
        )}
      </ul>
    </div>
  )
}
