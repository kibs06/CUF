import { Check } from 'lucide-react'

/**
 * Where a multi-step form stands, in words — not just bars.
 *
 * Bars alone are decoration to a screen reader and a guessing game to everyone
 * else ("am I on documents or the store?"). Each step names itself, the current
 * one is marked with `aria-current="step"`, finished steps show a check, and
 * finished steps are buttons when `onSelect` is given — going back to fix an
 * earlier answer is the reason the state was kept, so the indicator should
 * offer the trip.
 *
 * On narrow screens the names collapse to a single "Step X of N — Label" line
 * with compact dots: the information survives, the layout does not break.
 */
export default function StepIndicator({ steps, current, onSelect }) {
  return (
    <div className="mb-6">
      <p className="text-xs font-semibold text-muted sm:hidden" aria-live="polite">
        Step {current + 1} of {steps.length} — {steps[current]}
      </p>
      <ol
        aria-label="Application progress"
        className="mt-2 flex items-center gap-1.5 sm:mt-0"
      >
        {steps.map((label, index) => {
          const done = index < current
          const active = index === current
          const item = (
            <>
              <span
                aria-hidden="true"
                className={`flex h-6 w-6 shrink-0 items-center justify-center rounded-full text-[11px] font-bold transition-colors duration-200 ease-out-cubic ${
                  done
                    ? 'bg-olive/15 text-olive'
                    : active
                      ? 'bg-clay text-white'
                      : 'bg-subtle text-muted'
                }`}
              >
                {done ? <Check className="h-3.5 w-3.5" strokeWidth={3} /> : index + 1}
              </span>
              <span
                className={`hidden text-xs font-semibold md:inline ${
                  active ? 'text-ink' : 'text-muted'
                }`}
              >
                {label}
              </span>
              {index < steps.length - 1 && (
                <span
                  aria-hidden="true"
                  className={`mx-1 h-px flex-1 transition-colors duration-200 ease-out-cubic ${
                    done ? 'bg-olive/40' : 'bg-hairline'
                  }`}
                />
              )}
            </>
          )

          return (
            <li
              key={label}
              aria-current={active ? 'step' : undefined}
              className={`flex items-center gap-1.5 ${index < steps.length - 1 ? 'flex-1' : ''}`}
            >
              {done && onSelect ? (
                <button
                  type="button"
                  onClick={() => onSelect(index)}
                  title={`Back to ${label}`}
                  aria-label={`Back to step ${index + 1}: ${label}`}
                  className="flex cursor-pointer items-center gap-1.5 rounded-field outline-none transition-opacity duration-200 ease-out-cubic hover:opacity-75 focus-visible:ring-2 focus-visible:ring-clay/60"
                >
                  {item}
                </button>
              ) : (
                <span className="flex items-center gap-1.5">{item}</span>
              )}
            </li>
          )
        })}
      </ol>
    </div>
  )
}
