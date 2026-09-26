import { DURATION } from '../motion/transitions'
import {
  ORDER_PROGRESS_STEPS,
  progressIndex,
  statusLabel,
  statusTone,
} from '../../lib/orders'

/**
 * Where an order stands, in one pill.
 *
 * The tint carries the meaning and the DOT carries the colour, while the label
 * stays in `text-ink`. That split is deliberate: the accent tones are fills, not
 * text colours — #F59E0B on a 12% wash of itself is roughly 2:1, which fails
 * every contrast rule there is — and a customer reading "Cancellation
 * requested" in amber-on-amber is being told something they cannot read.
 *
 * Classes are a static lookup, not a template string: Tailwind's scanner has to
 * see the literal class name somewhere, so `bg-${tone}/10` would ship as
 * nothing at all in a production build.
 */
const TONE_TINT = {
  amber: 'bg-amber/[0.14] ring-amber/25',
  clay: 'bg-clay/[0.10] ring-clay/20',
  olive: 'bg-olive/[0.14] ring-olive/25',
  crimson: 'bg-crimson/[0.10] ring-crimson/20',
  muted: 'bg-subtle ring-hairline',
}

const TONE_DOT = {
  amber: 'bg-amber',
  clay: 'bg-clay',
  olive: 'bg-olive',
  crimson: 'bg-crimson',
  muted: 'bg-muted/60',
}

export default function StatusPill({ status, className = '' }) {
  const tone = statusTone(status)

  return (
    <span
      className={`inline-flex items-center gap-2 rounded-full px-3 py-1 text-xs font-semibold text-ink ring-1 ring-inset ${
        TONE_TINT[tone] ?? TONE_TINT.muted
      } ${className}`}
    >
      <span
        aria-hidden="true"
        className={`h-1.5 w-1.5 shrink-0 rounded-full ${TONE_DOT[tone] ?? TONE_DOT.muted}`}
      />
      {statusLabel(status)}
    </span>
  )
}

/**
 * The four-step rail under an order card.
 *
 * The same four steps, in the same words, as the app's `_OrderProgressStepper`,
 * and it is rendered only when `progressIndex` is 0–3 — the app's own rule for
 * a cancelled or unpaid order, where a position on a line from "Pending" to
 * "Delivered" would be a fiction.
 *
 * Delivered steps are clay because they happened; the step in hand gets a ring
 * so the eye lands on it. Nothing animates here: a rail that grows every time a
 * card scrolls past turns a list into a light show.
 */
export function OrderProgress({ status, className = '' }) {
  const current = progressIndex(status)
  if (current < 0) return null

  return (
    <div className={className}>
      <ol className="flex items-center" aria-label="Order progress">
        {ORDER_PROGRESS_STEPS.map((step, index) => {
          const done = index < current
          const here = index === current

          return (
            <li
              key={step}
              className={index === 0 ? 'flex items-center' : 'flex flex-1 items-center'}
              aria-current={here ? 'step' : undefined}
            >
              {index > 0 && (
                <span
                  aria-hidden="true"
                  className={`h-px flex-1 transition-colors ${
                    done || here ? 'bg-clay/45' : 'bg-hairline'
                  }`}
                  style={{ transitionDuration: `${DURATION.base}s` }}
                />
              )}

              <span
                aria-hidden="true"
                className={`ml-2 h-2 w-2 shrink-0 rounded-full ${
                  done
                    ? 'bg-clay'
                    : here
                      ? 'bg-clay ring-4 ring-clay/15'
                      : 'bg-hairline'
                }`}
              />
              <span
                className={`ml-2 text-[11px] font-semibold uppercase tracking-[0.06em] ${
                  here ? 'text-ink' : done ? 'text-muted-strong' : 'text-muted/60'
                }`}
              >
                {step}
              </span>
            </li>
          )
        })}
      </ol>
    </div>
  )
}
