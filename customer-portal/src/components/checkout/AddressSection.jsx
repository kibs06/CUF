import { Check, Plus } from 'lucide-react'

import { formatDeliveryAddress, addressFromRow } from '../../lib/checkoutRules'
import AddressForm from './AddressForm'

/**
 * Where the order goes: a saved address if there is one, the form if there is
 * not, and always the option to use a different one.
 *
 * The saved list is radio-like but built from buttons with `aria-pressed`,
 * because each option is a choice *and* a card with text in it — a real
 * `<input type="radio">` would either be invisible or fight the layout, and
 * `aria-pressed` on a button tells a screen reader the same story.
 *
 * When the book is empty the form is simply there, open. An "Add an address"
 * button that reveals an empty form would be one click to reach the only thing
 * a customer with no addresses can possibly do.
 */
export default function AddressSection({
  addresses,
  selectedId,
  onSelect,
  adding,
  onAddStart,
  onCancelAdd,
  formProps,
}) {
  const rows = (addresses ?? []).map(addressFromRow).filter(Boolean)
  const showForm = adding || rows.length === 0

  return (
    <section className="rounded-card border border-hairline bg-raised p-6 shadow-card">
      <header className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <h2 className="font-display text-xl font-semibold text-ink">
            Delivery address
          </h2>
          <p className="mt-1 text-sm text-muted">
            The maker and the rider both read this, so it needs a reachable
            number.
          </p>
        </div>

        {!showForm && (
          <button type="button" onClick={onAddStart} className="btn btn-outline h-9 px-3 py-0 text-xs">
            <Plus size={14} strokeWidth={2.5} />
            Use a different address
          </button>
        )}
      </header>

      {!showForm && (
        <ul className="mt-5 space-y-3">
          {rows.map((address) => {
            const selected = address.id === selectedId
            return (
              <li key={address.id}>
                <button
                  type="button"
                  onClick={() => onSelect(address.id)}
                  aria-pressed={selected}
                  className={`flex w-full items-start gap-4 rounded-field border p-4 text-left transition-[border-color,background-color,box-shadow] duration-200 ease-out-cubic ${
                    selected
                      ? 'border-clay/45 bg-clay/[0.05] shadow-warm'
                      : 'border-hairline hover:border-card-edge hover:bg-subtle/60'
                  }`}
                >
                  <span
                    aria-hidden="true"
                    className={`mt-0.5 flex h-5 w-5 shrink-0 items-center justify-center rounded-full border transition-colors duration-200 ${
                      selected
                        ? 'border-clay bg-clay text-ink-inverse'
                        : 'border-card-edge bg-raised'
                    }`}
                  >
                    {selected && <Check size={12} strokeWidth={3} />}
                  </span>

                  <span className="min-w-0 flex-1">
                    <span className="flex flex-wrap items-center gap-2">
                      <span className="text-sm font-semibold text-ink">
                        {address.recipientName}
                      </span>
                      <span className="rounded-full bg-subtle px-2 py-0.5 text-[10px] font-semibold uppercase tracking-[0.08em] text-muted">
                        {address.label || 'Home'}
                      </span>
                      {address.isDefault && (
                        <span className="text-[10px] font-semibold uppercase tracking-[0.08em] text-clay-ink">
                          Default
                        </span>
                      )}
                    </span>
                    <span className="num mt-1 block text-xs text-muted">
                      {address.recipientPhone}
                    </span>
                    <span className="mt-1 block text-xs leading-relaxed text-muted">
                      {formatDeliveryAddress(address)}
                      {address.landmark ? ` — ${address.landmark}` : ''}
                    </span>
                  </span>
                </button>
              </li>
            )
          })}
        </ul>
      )}

      {showForm && (
        <div className="mt-5">
          <AddressForm {...formProps} />

          {rows.length > 0 && (
            <button
              type="button"
              onClick={onCancelAdd}
              className="mt-5 text-xs font-semibold text-clay-ink underline underline-offset-4"
            >
              Use one of my saved addresses instead
            </button>
          )}
        </div>
      )}
    </section>
  )
}
