import { useState } from 'react'
import { Crosshair, Loader2, MapPin } from 'lucide-react'

import Field from '../ui/Field'

/**
 * Where the order is going.
 *
 * Two decisions worth stating, both about not inventing data:
 *
 *  1. **The region/province/city fields start empty.** Most customers are in
 *     Carcar, and pre-filling that would be convenient — and would silently
 *     ship a Manila customer's order to Cebu the first time they did not read
 *     the form. The placeholders hint; the values are theirs to type.
 *
 *  2. **The pin is asked for, not assumed.** Only the browser's own location
 *     API fills the coordinates. Without it we say plainly what will be stored
 *     instead of quietly writing the Carcar centre onto somebody's address —
 *     `customer_addresses` requires a coordinate, and the honest way to satisfy
 *     a NOT NULL column is to tell the customer what is going in it.
 */
export default function AddressForm({
  draft,
  errors = {},
  onChange,
  saveToBook = false,
  onSaveToBookChange,
  showSaveToggle = true,
  idPrefix = 'address',
}) {
  const [pinNote, setPinNote] = useState(null)
  const [locating, setLocating] = useState(false)

  const set = (field) => (value) => onChange({ ...draft, [field]: value })

  const hasPin = Number(draft.latitude) !== 0 && Number(draft.latitude) > 0

  const locate = () => {
    if (!navigator.geolocation) {
      setPinNote('This browser cannot share your location — the pin will stay approximate.')
      return
    }

    setLocating(true)
    setPinNote(null)

    navigator.geolocation.getCurrentPosition(
      (position) => {
        setLocating(false)
        setPinNote('Pin set from your device.')
        onChange({
          ...draft,
          latitude: position.coords.latitude,
          longitude: position.coords.longitude,
        })
      },
      () => {
        setLocating(false)
        setPinNote('We could not read your location — the pin will stay approximate.')
      },
      { timeout: 10000, maximumAge: 60000 },
    )
  }

  return (
    <div className="space-y-5">
      <div className="grid gap-5 sm:grid-cols-2">
        <Field
          id={`${idPrefix}-name`}
          label="Recipient name"
          value={draft.recipientName}
          onChange={set('recipientName')}
          error={errors.recipientName}
          autoComplete="name"
          required
          placeholder="Who receives the order"
        />
        <Field
          id={`${idPrefix}-phone`}
          label="Mobile number"
          value={draft.recipientPhone}
          onChange={set('recipientPhone')}
          error={errors.recipientPhone}
          autoComplete="tel"
          required
          placeholder="0917 123 4567"
        />
      </div>

      <Field
        id={`${idPrefix}-street`}
        label="House / building, street, purok"
        value={draft.streetAddress}
        onChange={set('streetAddress')}
        error={errors.streetAddress}
        autoComplete="street-address"
        required
        placeholder="12 Osmeña St., Purok 2"
      />

      <div className="grid gap-5 sm:grid-cols-2">
        <Field
          id={`${idPrefix}-barangay`}
          label="Barangay"
          value={draft.barangay}
          onChange={set('barangay')}
          error={errors.barangay}
          required
          placeholder="Poblacion I"
        />
        <Field
          id={`${idPrefix}-city`}
          label="City / municipality"
          value={draft.cityMunicipality}
          onChange={set('cityMunicipality')}
          error={errors.cityMunicipality}
          required
          placeholder="Carcar City"
        />
        <Field
          id={`${idPrefix}-province`}
          label="Province"
          value={draft.province}
          onChange={set('province')}
          error={errors.province}
          required
          placeholder="Cebu"
        />
        <Field
          id={`${idPrefix}-region`}
          label="Region"
          value={draft.region}
          onChange={set('region')}
          error={errors.region}
          required
          placeholder="Region VII (Central Visayas)"
        />
      </div>

      <Field
        id={`${idPrefix}-landmark`}
        label="Landmark"
        value={draft.landmark}
        onChange={set('landmark')}
        hint="Anything that helps the rider find the door."
        placeholder="Blue gate beside the sari-sari store"
      />

      <div className="rounded-field border border-hairline bg-subtle/60 p-4">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div className="flex items-center gap-2 text-sm text-muted-strong">
            <MapPin size={15} strokeWidth={2} className="text-clay-ink" />
            {hasPin ? (
              <span className="num">
                {Number(draft.latitude).toFixed(5)}, {Number(draft.longitude).toFixed(5)}
              </span>
            ) : (
              <span>No pin yet</span>
            )}
          </div>

          <button
            type="button"
            onClick={locate}
            disabled={locating}
            className="btn btn-outline h-9 px-3 py-0 text-xs"
          >
            {locating ? (
              <Loader2 size={14} className="animate-spin" />
            ) : (
              <Crosshair size={14} strokeWidth={2} />
            )}
            {locating ? 'Locating…' : 'Use my current location'}
          </button>
        </div>

        {pinNote ? (
          <p className="mt-2 text-xs text-muted">{pinNote}</p>
        ) : (
          !hasPin && (
            <p className="mt-2 text-xs leading-relaxed text-muted">
              Optional. The pin helps the rider; everything above is what the
              order is addressed to.
            </p>
          )
        )}
      </div>

      {showSaveToggle && (
        <label className="flex cursor-pointer items-start gap-3 rounded-field border border-hairline p-4 transition-colors duration-200 ease-out-cubic hover:border-card-edge">
          <input
            type="checkbox"
            checked={saveToBook}
            onChange={(event) => onSaveToBookChange(event.target.checked)}
            className="mt-0.5 h-4 w-4 shrink-0 accent-clay"
          />
          <span>
            <span className="block text-sm font-semibold text-ink">
              Save this address to my account
            </span>
            <span className="mt-1 block text-xs leading-relaxed text-muted">
              Then next time it is one tap — in the app as well, because the
              address book is the same one.
              {!hasPin && (
                <>
                  {' '}
                  With no pin shared, it saves pointed at Carcar City centre.
                </>
              )}
            </span>
          </span>
        </label>
      )}

      <Field
        id={`${idPrefix}-label`}
        label="Label"
        value={draft.label}
        onChange={set('label')}
        placeholder="Home"
        hint="Home, Office — how you will recognise it in your address book."
      />
    </div>
  )
}
