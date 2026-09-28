import { SELLER_PERIODS } from '../../lib/sellerRules.js'

/**
 * The reporting window, as pills — the dashboard's and the reports page's.
 *
 * One component for the reason `SellerPageHeader` is one component: the two
 * pages report the same money from the same orders, and a seller who switches
 * to the month on the dashboard and to the month on the reports page should not
 * be pressing two controls that look like different things. The windows
 * themselves live in `sellerRules.js` beside the arithmetic that reads them, so
 * "Last 30 days" cannot mean 30 days here and four weeks there.
 *
 * `aria-pressed` rather than a tablist: these are toggles on one view, not
 * panels that appear and disappear, and a screen reader should hear the current
 * window as *pressed* — the same choice the seller's own notification chips make.
 * The visible label is the accessible name, so the group needs only its own
 * `aria-label` to be a control rather than a row of loose buttons.
 */
export default function SellerPeriodPills({
  value,
  onChange,
  periods = SELLER_PERIODS,
  label = 'Reporting period',
  className = '',
}) {
  return (
    <div
      role="group"
      aria-label={label}
      className={`flex flex-wrap gap-1.5 ${className}`}
    >
      {periods.map((period) => {
        const active = period.id === value

        return (
          <button
            key={period.id}
            type="button"
            onClick={() => onChange(period.id)}
            aria-pressed={active}
            className={`rounded-full px-3.5 py-1.5 text-sm font-medium transition-colors duration-200 ease-out-cubic ${
              active
                ? 'bg-clay text-ink-inverse'
                : 'text-muted-strong hover:bg-subtle hover:text-ink'
            }`}
          >
            {period.label}
          </button>
        )
      })}
    </div>
  )
}
