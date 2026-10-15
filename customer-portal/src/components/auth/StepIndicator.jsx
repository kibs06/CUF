import { Check } from 'lucide-react'

/**
 * Where a multi-step form stands — designed to feel premium, not procedural.
 *
 * Three layers, each doing one job:
 *
 *  - A stage line ("STEP 2 OF 5") with a numeric percent, so progress is
 *    exact rather than vibes. The percent is announced politely on change.
 *  - A gradient progress track that fills with a slow, motion-safe ease —
 *    the movement is the reward for finishing a step.
 *  - Named nodes: finished steps show a check and (with `onSelect`) travel
 *    back, the current step glows clay, the rest wait muted. Labels appear
 *    where there is room for them; the stage line carries the meaning where
 *    there is not.
 */
export default function StepIndicator({ steps, current, onSelect }) {
  const percent = Math.round(((current + 1) / steps.length) * 100)

  return (
    <div className="mb-7">
      <div className="flex items-baseline justify-between gap-3">
        <p className="text-xs font-semibold uppercase tracking-[0.14em] text-muted">
          Step {current + 1} <span className="text-muted/60">of {steps.length}</span>
          <span className="ml-2 normal-case tracking-normal text-muted-strong sm:hidden">
            {steps[current]}
          </span>
        </p>
        <p
          className="font-numeric text-xs font-semibold tabular-nums text-clay-ink"
          aria-live="polite"
          aria-label={`${percent} percent complete`}
        >
          {percent}%
        </p>
      </div>

      <div
        aria-hidden="true"
        className="mt-2.5 h-1 overflow-hidden rounded-full bg-subtle"
      >
        <div
          className="h-full rounded-full bg-gradient-to-r from-clay to-rust motion-safe:transition-[width] motion-safe:duration-500 motion-safe:ease-out-cubic"
          style={{ width: `${percent}%` }}
        />
      </div>

      <ol aria-label="Application progress" className="mt-4 flex items-center gap-1">
        {steps.map((label, index) => {
          const done = index < current
          const active = index === current
          const node = (
            <>
              <span
                aria-hidden="true"
                className={`flex h-7 w-7 shrink-0 items-center justify-center rounded-full text-xs font-bold transition-colors duration-200 ease-out-cubic ${
                  done
                    ? 'bg-clay text-white ring-2 ring-clay/25'
                    : active
                      ? 'bg-clay text-white shadow-warm ring-2 ring-clay/40'
                      : 'bg-subtle text-muted'
                }`}
              >
                {done ? <Check className="h-3.5 w-3.5" strokeWidth={3.5} /> : index + 1}
              </span>
              <span
                className={`hidden whitespace-nowrap text-[10px] font-semibold lg:inline ${
                  active ? 'text-ink' : done ? 'text-muted-strong' : 'text-muted'
                }`}
              >
                {label}
              </span>
              {index < steps.length - 1 && (
                <span
                  aria-hidden="true"
                  className={`mx-0.5 h-px min-w-1 flex-1 transition-colors duration-200 ease-out-cubic ${
                    done ? 'bg-clay/50' : 'bg-hairline'
                  }`}
                />
              )}
            </>
          )

          return (
            <li
              key={label}
              aria-current={active ? 'step' : undefined}
              className={`flex items-center gap-1 ${index < steps.length - 1 ? 'flex-1' : ''}`}
            >
              {done && onSelect ? (
                <button
                  type="button"
                  onClick={() => onSelect(index)}
                  title={`Back to ${label}`}
                  aria-label={`Back to step ${index + 1}: ${label}`}
                  className="flex cursor-pointer items-center gap-1 rounded-field outline-none transition-opacity duration-200 ease-out-cubic hover:opacity-75 focus-visible:ring-2 focus-visible:ring-clay/60"
                >
                  {node}
                </button>
              ) : (
                <span className="flex items-center gap-1">{node}</span>
              )}
            </li>
          )
        })}
      </ol>
    </div>
  )
}
