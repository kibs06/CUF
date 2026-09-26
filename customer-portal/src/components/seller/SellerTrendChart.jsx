import { Minus, TrendingDown, TrendingUp } from 'lucide-react'

import { formatCurrency, formatCurrencyCompact } from '../../lib/constants.js'

/**
 * A week of takings, as bars.
 *
 * ## Why a chart and not a sentence
 *
 * The dashboard used to say "3 orders today · 2 still open", which is true and
 * tells a maker nothing about whether this week is going well. The shape of a
 * week is the one thing a summary line cannot carry: seven bars make a good
 * Saturday, a dead Monday and a slide obvious in a glance, and no arrangement of
 * numbers does that at 8am.
 *
 * ## No chart library
 *
 * `recharts` is in the admin portal and deliberately not here. What this needs
 * is seven heights — a bar chart with one series, no axes, no legend, no
 * tooltips and no zoom. A dependency for that would be 300kB of layout engine to
 * draw seven `<span>`s, and it would be the only place in this portal where a
 * number's *position* was decided by something other than a Tailwind class.
 *
 * ## The three states, and what each one honestly says
 *
 *  1. **A bar is scaled to the window's own peak**, not to a fixed ceiling.
 *     Against a fixed ceiling every small week draws as an empty chart, so a
 *     maker who had one good week could never read the others.
 *  2. **Today is drawn lighter, because it is not over.** `isProjected` comes
 *     from the rule (the app's own `SalesDataPoint` flag), and a partly finished
 *     day drawn at full weight reads as "sales collapsed after lunch". The
 *     caption names it instead, so the legend is a sentence rather than a key.
 *  3. **A day with nothing is a hairline, not a gap.** A zero-height bar would
 *     leave the axis looking broken; the 2px baseline keeps the week continuous
 *     and still reads as nothing.
 *
 * ## The one structural rule
 *
 * A bar's percentage is measured against its **own plot box**, not against the
 * whole column. Each column is therefore a fixed-height `h-24` plot area with
 * the weekday label *outside* it — putting the label inside would make `100%`
 * mean "the plot plus the label", so the tallest day of the week would overflow
 * its own column by exactly the height of its caption. That is the shape of bug
 * that only shows up on the one day it matters.
 *
 * ## Accessibility
 *
 * The bars are `aria-hidden` decoration and each day carries its real figures in
 * visually-hidden text inside its own `<li>` — so the week is a list of seven
 * readings to a screen reader, not an image with a summary. That is also why
 * this is an `<ol>` rather than a `<div>`: the data is content, and hiding it
 * behind one `aria-label` would throw away the day-by-day detail a sighted user
 * gets from reading across.
 */
export default function SellerTrendChart({
  trend,
  label = 'Sales, last 7 days',
  className = '',
}) {
  const { points, total, hasComparison, percentChange, isEmpty } = trend

  const peak = Math.max(0, ...points.map((point) => point.revenue))

  return (
    <figure className={className}>
      <div className="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1">
        <figcaption className="overline">{label}</figcaption>
        <p className="num text-sm font-semibold text-ink">
          {formatCurrency(total)}
        </p>
      </div>

      <div className="mt-4">
        {isEmpty ? (
          <div className="flex h-24 items-center justify-center rounded-card border border-dashed border-hairline bg-subtle/40">
            <p className="px-4 text-center text-xs text-muted">
              Nothing sold in the last {points.length} days.
            </p>
          </div>
        ) : (
          <ol className="flex items-end gap-1.5">
            {points.map((point) => (
              <DayBar key={point.key} point={point} peak={peak} />
            ))}
          </ol>
        )}
      </div>

      <div className="mt-3 flex flex-wrap items-center gap-x-3 gap-y-1.5">
        <TrendChip
          hasComparison={hasComparison}
          percentChange={percentChange}
          days={points.length}
        />
        <p className="text-xs text-muted">Peak {formatCurrencyCompact(peak)}</p>
      </div>
    </figure>
  )
}

/**
 * One day.
 *
 * Everything above the weekday initial is decoration; the reading lives in the
 * `sr-only` span. `title` is set as well because a maker who wants to check one
 * bar against another should not have to open the orders list to do it.
 */
function DayBar({ point, peak }) {
  const share = peak > 0 ? (point.revenue / peak) * 100 : 0
  const weekday = point.date.toLocaleDateString('en-PH', { weekday: 'narrow' })

  const reading = `${point.date.toLocaleDateString('en-PH', {
    weekday: 'long',
    day: 'numeric',
    month: 'short',
  })}: ${formatCurrency(point.revenue)}, ${
    point.orderCount === 1 ? '1 order' : `${point.orderCount} orders`
  }${point.isProjected ? ', so far today' : ''}`

  return (
    <li className="flex min-w-0 flex-1 flex-col items-center gap-2">
      <span className="sr-only">{reading}</span>

      {/* The plot box. `items-end` is what makes a bar grow upward. */}
      <span
        aria-hidden="true"
        className="flex h-24 w-full items-end"
        title={reading}
      >
        <span
          style={point.revenue > 0 ? { height: `${Math.max(6, share)}%` } : undefined}
          className={[
            'w-full rounded-t-[4px] transition-[height] duration-300 ease-out-cubic',
            point.revenue > 0
              ? point.isProjected
                ? // Lighter: the day is still running.
                  'bg-rust/45'
                : 'bg-rust'
              : // A hairline rather than nothing — see the docblock.
                'h-0.5 bg-hairline',
          ].join(' ')}
        />
      </span>

      <span
        aria-hidden="true"
        className={[
          'text-[10px] font-semibold uppercase tracking-[0.08em]',
          point.isProjected ? 'text-ink' : 'text-muted',
        ].join(' ')}
      >
        {weekday}
      </span>
    </li>
  )
}

/**
 * "18% up on the week before", or nothing.
 *
 * Two deliberate choices about colour and words:
 *
 *  - **A fall is not an error.** It is drawn in `text-muted-strong`, never
 *    crimson. Crimson on this site means a thing is broken or a thing will be
 *    lost, and a quieter week is neither — it is information. Colouring it like
 *    a failure teaches a seller to dread opening their own dashboard.
 *  - **With nothing to compare against, it says nothing.** `hasComparison` is
 *    false on a store's first week, where any percentage is arithmetic on zero;
 *    the chip then just names the period. `0%` or `+100%` would both be wrong,
 *    and a wrong growth figure is the number a maker would act on.
 */
function TrendChip({ hasComparison, percentChange, days }) {
  if (!hasComparison) {
    return (
      <span className="rounded-full bg-subtle px-2.5 py-1 text-xs font-medium text-muted">
        First {days} days with sales
      </span>
    )
  }

  const rounded = Math.round(percentChange)
  const Icon = rounded > 0 ? TrendingUp : rounded < 0 ? TrendingDown : Minus

  /*
    `bg-olive/[0.12]`, not `bg-olive/12`. Tailwind's opacity scale steps by five
    (`/5`, `/10`, `/15`…), so a bare `/12` is not a class it can generate — and a
    class it cannot generate is not an error, it is silence. Verified in the
    built stylesheet: `/12` produced zero rules and the chip rendered with no
    tint at all.
  */
  const tone =
    rounded > 0
      ? 'bg-olive/[0.12] text-olive'
      : rounded < 0
        ? 'bg-subtle text-muted-strong'
        : 'bg-subtle text-muted'

  return (
    <span
      className={`inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-xs font-semibold ${tone}`}
    >
      <Icon className="h-3.5 w-3.5" aria-hidden="true" />
      {rounded === 0 ? 'Level with' : `${Math.abs(rounded)}% ${rounded > 0 ? 'up on' : 'down on'}`}{' '}
      the {days} days before
    </span>
  )
}
