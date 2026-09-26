import { useState } from 'react'
import { Link } from 'react-router-dom'
import { ArrowLeft, MapPin, Pencil, Plus, Star, Trash2 } from 'lucide-react'

import AddressForm from '../components/checkout/AddressForm'
import ConfirmDialog from '../components/ui/ConfirmDialog'
import EmptyState from '../components/ui/EmptyState'
import Reveal from '../components/ui/Reveal'
import Skeleton from '../components/ui/Skeleton'
import {
  useDeleteAddress,
  useMyAddresses,
  useSaveAddress,
  useSetDefaultAddress,
} from '../hooks/useAddresses.js'
import {
  addressErrors,
  addressFromRow,
  emptyAddressDraft,
  formatDeliveryAddress,
} from '../lib/checkoutRules'

/**
 * My Addresses.
 *
 * The address book is `customer_addresses`, which is the SAME table checkout
 * already writes to when a customer ticks "save this address" — so this page is
 * the missing other half of a feature that was half-built, not a new store. A
 * saved address here is offered at checkout, and one saved at checkout appears
 * here.
 *
 * The form is the checkout's own `AddressForm`, unchanged and with its
 * save-to-book switch hidden: one address form in the codebase means the field
 * order, the required set and the "we will use Carcar centre" note about the
 * pin cannot disagree between the two places.
 *
 * The default is a database trigger, not client bookkeeping — writing
 * `is_default: true` un-sets the others, and the refetch is what reports it.
 * That is why "Make default" is a one-column write and the list is re-read
 * rather than patched.
 */
export default function SettingsAddresses() {
  const { data: addresses, isLoading, isError, error } = useMyAddresses()
  const saveAddress = useSaveAddress()
  const removeAddress = useDeleteAddress()
  const makeDefault = useSetDefaultAddress()

  const [editing, setEditing] = useState(null) // { id|null, draft }
  const [errors, setErrors] = useState({})
  const [confirmDelete, setConfirmDelete] = useState(null)

  const startNew = () =>
    setEditing({ id: null, draft: emptyAddressDraft({ isDefault: !addresses?.length }) })

  const startEdit = (row) =>
    setEditing({ id: row.id, draft: addressFromRow(row) })

  const onSubmit = async (event) => {
    event.preventDefault()
    const found = addressErrors(editing.draft)
    setErrors(found)
    if (Object.keys(found).length > 0) return

    await saveAddress.mutateAsync({ id: editing.id, draft: editing.draft })
    setEditing(null)
    setErrors({})
  }

  return (
    <div className="mx-auto max-w-3xl px-4 py-10 sm:px-6 lg:px-8">
      <Link
        to="/settings"
        className="inline-flex items-center gap-1.5 text-xs font-semibold text-muted transition-colors duration-200 hover:text-ink"
      >
        <ArrowLeft size={14} strokeWidth={2} />
        Settings
      </Link>

      <header className="mt-4 flex flex-wrap items-end justify-between gap-4">
        <div>
          <p className="overline">Account</p>
          <h1 className="mt-2 font-display text-3xl font-semibold text-ink">
            My Addresses
          </h1>
        </div>

        {!editing && (
          <button type="button" onClick={startNew} className="btn btn-primary">
            <Plus size={16} strokeWidth={2} />
            Add address
          </button>
        )}
      </header>

      {/* ── The list ──────────────────────────────────────────────── */}
      {isLoading ? (
        <div className="mt-8 space-y-3">
          <Skeleton className="h-28 w-full" />
          <Skeleton className="h-28 w-full" />
        </div>
      ) : isError ? (
        <div className="mt-8">
          <EmptyState
            Icon={MapPin}
            title="Could not load your addresses"
            description={error?.message ?? 'Please check your connection and try again.'}
          />
        </div>
      ) : addresses.length === 0 ? (
        <div className="mt-8">
          <EmptyState
            Icon={MapPin}
            title="No saved addresses yet"
            description="Save the places you send orders to and checkout stops asking. You can save them here or while checking out — it is the same list."
            action={
              <button type="button" onClick={startNew} className="btn btn-primary">
                <Plus size={16} strokeWidth={2} />
                Add address
              </button>
            }
          />
        </div>
      ) : (
        <ul className="mt-8 space-y-3">
          {addresses.map((row, index) => (
            <Reveal
              as="li"
              key={row.id}
              delay={Math.min(index * 0.04, 0.2)}
              className="rounded-card border border-hairline bg-raised p-5 shadow-card"
            >
              <div className="flex flex-wrap items-start justify-between gap-4">
                <div className="min-w-0">
                  <div className="flex items-center gap-2">
                    <h2 className="text-sm font-semibold text-ink">
                      {row.label || 'Home'}
                    </h2>
                    {row.is_default && (
                      <span className="inline-flex items-center gap-1 rounded-full bg-clay/10 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-[0.08em] text-clay-ink">
                        <Star size={10} strokeWidth={2.5} />
                        Default
                      </span>
                    )}
                  </div>

                  <p className="mt-1 text-sm text-muted-strong">
                    {row.recipient_name} ·{' '}
                    <span className="num">{row.recipient_phone}</span>
                  </p>
                  <p className="mt-1 text-xs leading-relaxed text-muted">
                    {formatDeliveryAddress(addressFromRow(row))}
                  </p>
                  {row.landmark && (
                    <p className="mt-1 text-xs text-muted">{row.landmark}</p>
                  )}
                </div>

                <div className="flex shrink-0 flex-wrap items-center gap-2">
                  {!row.is_default && (
                    <button
                      type="button"
                      onClick={() => makeDefault.mutate(row.id)}
                      disabled={makeDefault.isPending}
                      className="btn btn-outline h-9 px-3 py-0 text-xs"
                    >
                      Make default
                    </button>
                  )}
                  <button
                    type="button"
                    onClick={() => startEdit(row)}
                    className="btn btn-outline h-9 px-3 py-0 text-xs"
                  >
                    <Pencil size={13} strokeWidth={2} />
                    Edit
                  </button>
                  <button
                    type="button"
                    onClick={() => setConfirmDelete(row)}
                    aria-label={`Delete ${row.label || 'address'}`}
                    className="btn btn-outline h-9 w-9 px-0 py-0 text-crimson hover:border-crimson/40"
                  >
                    <Trash2 size={14} strokeWidth={2} />
                  </button>
                </div>
              </div>
            </Reveal>
          ))}
        </ul>
      )}

      {(saveAddress.isError || makeDefault.isError || removeAddress.isError) && (
        <p
          role="alert"
          className="mt-4 rounded-field border border-crimson/30 bg-crimson/[0.07] px-3 py-2 text-xs leading-relaxed text-ink"
        >
          {(
            saveAddress.error ??
            makeDefault.error ??
            removeAddress.error
          )?.message ?? 'That did not save. Please try again.'}
        </p>
      )}

      {/* ── Add / edit ────────────────────────────────────────────── */}
      {editing && (
        <Reveal className="mt-8 rounded-card border border-hairline bg-raised p-6 shadow-card">
          <h2 className="font-display text-xl font-semibold text-ink">
            {editing.id ? 'Edit address' : 'New address'}
          </h2>
          <p className="mt-1 text-xs leading-relaxed text-muted">
            This is where the rider goes. Everything the order is addressed to
            lives here, so keep it precise.
          </p>

          <form onSubmit={onSubmit} className="mt-6" noValidate>
            <AddressForm
              draft={editing.draft}
              errors={errors}
              onChange={(draft) => setEditing((current) => ({ ...current, draft }))}
              showSaveToggle={false}
              idPrefix="saved-address"
            />

            <label className="mt-5 flex cursor-pointer items-start gap-3 rounded-field border border-hairline p-4 transition-colors duration-200 ease-out-cubic hover:border-card-edge">
              <input
                type="checkbox"
                checked={Boolean(editing.draft.isDefault)}
                onChange={(event) =>
                  setEditing((current) => ({
                    ...current,
                    draft: { ...current.draft, isDefault: event.target.checked },
                  }))
                }
                className="mt-0.5 h-4 w-4 shrink-0 accent-clay"
              />
              <span>
                <span className="block text-sm font-semibold text-ink">
                  Use this as my default address
                </span>
                <span className="mt-1 block text-xs leading-relaxed text-muted">
                  Checkout starts here. Only one address can be the default.
                </span>
              </span>
            </label>

            <div className="mt-6 flex flex-wrap gap-2">
              <button
                type="submit"
                disabled={saveAddress.isPending}
                className="btn btn-primary"
              >
                {saveAddress.isPending ? 'Saving…' : 'Save address'}
              </button>
              <button
                type="button"
                onClick={() => {
                  setEditing(null)
                  setErrors({})
                }}
                className="btn btn-outline"
              >
                Cancel
              </button>
            </div>
          </form>
        </Reveal>
      )}

      <ConfirmDialog
        open={Boolean(confirmDelete)}
        title="Delete this address?"
        description={`"${confirmDelete?.label || 'Address'}" will be removed from your address book. Orders you have already placed keep the address they were sent to.${confirmDelete?.is_default ? '\n\nThis is your default address, so nothing will be pre-filled at checkout until you pick another.' : ''}`}
        confirmLabel="Delete address"
        pending={removeAddress.isPending}
        onClose={() => setConfirmDelete(null)}
        onConfirm={async () => {
          await removeAddress.mutateAsync(confirmDelete.id)
          setConfirmDelete(null)
        }}
      />
    </div>
  )
}
