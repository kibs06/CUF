import { formatSize, sizeStockChips } from '../../lib/sizeSystems.js'

/**
 * A product's sizes, one chip each, with what is left of it.
 *
 * This is the answer to the question the tile used to answer with a total
 * ("3 sizes · 8 pairs"), and a total is exactly what hides the problem: eight
 * pairs across three sizes reads as healthy until you notice they are all size
 * 39. Per size, the row says *which* size is gone, which is the only form of
 * that answer a seller can act on.
 *
 * The colours are `stockState`'s three states and the dashboard's threshold, so
 * a chip that is amber here and a "Running out" figure that counts 5 are the
 * same rule — see `sizeStockChips` in `lib/sizeSystems.js`, which does the
 * ordering and decides the states.
 *
 * Three details:
 *
 *  1. **The number is the size, the small number is the stock** (`40 2`), and
 *     both are `.num` + tabular, so a column of chips has its digits on the same
 *     lines. The stock is deliberately quieter than the size: a seller reads the
 *     row to find a size, and the count is what they check once they have.
 *  2. **The sizing system is labelled only when there is more than one.** A
 *     single-system product's chips would otherwise carry the same "EU" prefix
 *     on every chip, and the common case is one system.
 *  3. **Out-of-stock is crimson, not grey.** A sold-out size is not a neutral
 *     fact; it is the size that just lost a sale, and it is the reason this row
 *     exists.
 */
const TONE = {
  out: 'bg-crimson/[0.10] text-crimson ring-crimson/25',
  low: 'bg-amber/[0.12] text-amber ring-amber/25',
  in: 'bg-subtle/70 text-muted-strong ring-hairline',
}

/** What a chip means out loud — the visual is `40 2`, which nobody can hear. */
const STATE_WORDS = {
  out: 'sold out',
  low: 'running low',
  in: 'in stock',
}

/**
 * @param {object} props
 * @param {Array<{ size?: string, stock?: number }>} props.inventory
 * @param {number} [props.limit] Chips before the `+N` — fewer in a list row,
 *   which has less width to give away.
 * @param {'sm'|'md'} [props.size]
 */
export default function SizeStockChips({
  inventory,
  limit = 10,
  size = 'md',
  className = '',
}) {
  const { groups, hidden } = sizeStockChips(inventory, { limit })
  const multiSystem = groups.length > 1

  if (groups.length === 0) {
    return (
      <p className={`text-xs text-muted ${className}`}>
        No sizes yet — add them before this can sell.
      </p>
    )
  }

  const chipClass = `${
    size === 'sm' ? 'px-1.5 py-0.5 text-[11px]' : 'px-2 py-1 text-xs'
  } num inline-flex items-baseline gap-1 rounded-field font-semibold ring-1 ring-inset`

  return (
    <div className={`flex flex-wrap items-center gap-1.5 ${className}`}>
      {groups.map((group) => (
        <span key={group.system} className="flex flex-wrap items-center gap-1.5">
          {multiSystem && (
            <span className="text-[10px] font-semibold uppercase tracking-[0.08em] text-muted">
              {group.system}
            </span>
          )}

          {group.chips.map((chip) => (
            <span
              key={chip.size}
              aria-label={`Size ${chip.value}, ${STATE_WORDS[chip.state]}`}
              title={`${formatSize(chip.size)} — ${chip.stock} in stock`}
              className={`${chipClass} ${TONE[chip.state] ?? TONE.in}`}
            >
              {chip.value}
              <span className="text-[10px] font-medium opacity-80">
                {chip.stock}
              </span>
            </span>
          ))}
        </span>
      ))}

      {hidden > 0 && (
        <span
          aria-label={`${hidden} more ${hidden === 1 ? 'size' : 'sizes'}`}
          title={`${hidden} more ${hidden === 1 ? 'size' : 'sizes'}`}
          className={`${chipClass} bg-subtle/70 text-muted ring-hairline`}
        >
          +{hidden}
        </span>
      )}
    </div>
  )
}
