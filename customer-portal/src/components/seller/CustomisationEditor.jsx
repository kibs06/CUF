import { useState } from 'react'
import { Plus, Trash2 } from 'lucide-react'

import Chip from '../ui/Chip.jsx'
import {
  CUSTOMIZATION_TYPES,
  MAX_CUSTOM_TYPE_LENGTH,
  addChoice,
  customizationTypeLabel,
  emptyCustomization,
  removeChoice,
  typeHasChoices,
} from '../../lib/productCustomizations.js'

/**
 * Customisation options — what a customer can ask for on top of the product.
 *
 * ## The shape, and why it is a list of small forms
 *
 * Each option is one row in `product_customizations`: a name, a type, the choices
 * a `select`/`color` offers, an extra price and whether it can be skipped. There
 * is no modal and no sheet — the app's version is a bottom sheet with four steps,
 * and a page that already scrolls can show the four fields instead. Editing in
 * place also means the option a seller is looking at is the option they are
 * editing, which a sheet makes two things.
 *
 * ## The type is a closed set **plus** free text
 *
 * Text / Select / Color are the three the app presets, and the "Other" input is
 * not a loophole: the column's CHECK was deliberately relaxed to
 * `length(option_type) > 0` so a seller could invent `number`, `date` or
 * `file upload`. An unrecognised type is therefore shown as typed rather than
 * repaired to 'Text' — repairing it would silently change what the customer is
 * asked for.
 *
 * ## A default type, so adding is one click
 *
 * A new option starts on `text`, which is what the app's sheet does: adding an
 * option should never require touching the type field first.
 */
export default function CustomisationEditor({
  customizations,
  onChange,
  disabled = false,
}) {
  const [otherType, setOtherType] = useState(null) // the index typing a custom type
  const [drafts, setDrafts] = useState({}) // `${index}` and `${index}:type` inputs
  const [errors, setErrors] = useState({}) // `${index}` → a refusal, per option

  const replace = (index, next) => {
    onChange(customizations.map((entry, at) => (at === index ? next : entry)))
  }

  const remove = (index) => {
    onChange(customizations.filter((entry, at) => at !== index))
  }

  /*
    Adding a choice is the one action here that can be refused, and the refusal
    is a sentence under the input. The typed text is KEPT on a refusal, so the
    seller can edit `Red` into `Reddish` rather than retyping it.
  */
  const addChoiceAt = (index) => {
    const { customization, error } = addChoice(
      customizations[index],
      drafts[index] ?? '',
    )
    setErrors((current) => ({ ...current, [index]: error ?? null }))
    if (error) return
    setDrafts((current) => ({ ...current, [index]: '' }))
    replace(index, customization)
  }

  return (
    <div className="space-y-5">
      {customizations.length === 0 && (
        <p className="text-sm text-muted">
          Nothing yet. An option is something a customer picks or types — an
          engraving, a different sole, a gift note.
        </p>
      )}

      <ul className="space-y-4">
        {customizations.map((customization, index) => {
          const choices = customization.options ?? []
          const type = String(customization.option_type ?? '').trim()
          const custom = type && !CUSTOMIZATION_TYPES.some((entry) => entry.value === type)
          const typingOther = otherType === index || custom

          return (
            <li
              key={index}
              className="rounded-field border border-hairline bg-subtle/40 p-4"
            >
              <div className="flex items-start gap-3">
                <label className="flex-1">
                  <span className="block text-xs font-semibold uppercase tracking-[0.08em] text-muted">
                    Option name
                  </span>
                  <input
                    value={customization.option_name}
                    disabled={disabled}
                    onChange={(event) =>
                      replace(index, {
                        ...customization,
                        option_name: event.target.value,
                      })
                    }
                    placeholder="e.g. Engraving text, Sole colour"
                    className="mt-2 h-10 w-full rounded-field border border-hairline bg-raised px-3 text-sm text-ink placeholder:text-muted/60"
                  />
                </label>

                <button
                  type="button"
                  onClick={() => remove(index)}
                  disabled={disabled}
                  aria-label={`Remove the option ${customization.option_name || index + 1}`}
                  className="mt-6 text-muted transition-colors hover:text-crimson"
                >
                  <Trash2 className="h-4 w-4" aria-hidden="true" />
                </button>
              </div>

              <p className="mt-3 text-xs font-semibold uppercase tracking-[0.08em] text-muted">
                Kind
              </p>
              <div className="mt-2 flex flex-wrap gap-2">
                {CUSTOMIZATION_TYPES.map((entry) => (
                  <Chip
                    key={entry.value}
                    label={entry.label}
                    selected={type === entry.value}
                    disabled={disabled}
                    onClick={() => {
                      setOtherType(null)
                      replace(index, {
                        ...customization,
                        option_type: entry.value,
                      })
                    }}
                  />
                ))}
                {/*
                  The custom type is a chip too, and tapping it reopens the
                  input with what it holds — so a type invented here stays
                  editable instead of becoming a dead chip the moment it is set.
                */}
                <Chip
                  label={custom ? customizationTypeLabel(type) : 'Other'}
                  selected={Boolean(custom)}
                  disabled={disabled}
                  onClick={() => {
                    setOtherType(index)
                    setDrafts((current) => ({
                      ...current,
                      [`${index}:type`]: custom ? type : '',
                    }))
                  }}
                />
              </div>

              {typingOther && (
                <div className="mt-2 flex gap-2">
                  <input
                    value={drafts[`${index}:type`] ?? ''}
                    disabled={disabled}
                    maxLength={MAX_CUSTOM_TYPE_LENGTH}
                    onChange={(event) =>
                      setDrafts((current) => ({
                        ...current,
                        [`${index}:type`]: event.target.value,
                      }))
                    }
                    onKeyDown={(event) => {
                      if (event.key !== 'Enter') return
                      event.preventDefault()
                      const value = (drafts[`${index}:type`] ?? '').trim()
                      if (!value) return
                      replace(index, { ...customization, option_type: value })
                      setOtherType(null)
                      setDrafts((current) => ({ ...current, [`${index}:type`]: '' }))
                    }}
                    placeholder="e.g. number, date, file upload"
                    aria-label="Your own kind of option"
                    className="h-10 flex-1 rounded-field border border-hairline bg-raised px-3 text-sm text-ink placeholder:text-muted/60"
                  />
                  <button
                    type="button"
                    disabled={disabled || !(drafts[`${index}:type`] ?? '').trim()}
                    onClick={() => {
                      const value = (drafts[`${index}:type`] ?? '').trim()
                      if (!value) return
                      replace(index, { ...customization, option_type: value })
                      setOtherType(null)
                      setDrafts((current) => ({ ...current, [`${index}:type`]: '' }))
                    }}
                    className="btn btn-outline h-10 py-0"
                  >
                    Use
                  </button>
                </div>
              )}

              {typeHasChoices(type) && (
                <>
                  <p className="mt-3 text-xs font-semibold uppercase tracking-[0.08em] text-muted">
                    Choices
                  </p>
                  <div className="mt-2 flex gap-2">
                    <input
                      value={drafts[index] ?? ''}
                      disabled={disabled}
                      onChange={(event) => {
                        setDrafts((current) => ({
                          ...current,
                          [index]: event.target.value,
                        }))
                        setErrors((current) => ({ ...current, [index]: null }))
                      }}
                      onKeyDown={(event) => {
                        if (event.key !== 'Enter') return
                        event.preventDefault()
                        addChoiceAt(index)
                      }}
                      placeholder="Add a choice…"
                      aria-label={`A choice for ${customization.option_name || 'this option'}`}
                      className="h-10 flex-1 rounded-field border border-hairline bg-raised px-3 text-sm text-ink placeholder:text-muted/60"
                    />
                    <button
                      type="button"
                      onClick={() => addChoiceAt(index)}
                      disabled={disabled || !(drafts[index] ?? '').trim()}
                      className="btn btn-outline h-10 py-0"
                    >
                      <Plus className="h-4 w-4" aria-hidden="true" />
                      Add
                    </button>
                  </div>

                  {errors[index] && (
                    <p role="alert" className="mt-2 text-xs font-medium text-crimson">
                      {errors[index]}
                    </p>
                  )}

                  {choices.length > 0 && (
                    <div className="mt-2.5 flex flex-wrap gap-2">
                      {choices.map((choice) => (
                        <Chip
                          key={choice}
                          label={choice}
                          disabled={disabled}
                          onRemove={() => replace(index, removeChoice(customization, choice))}
                        />
                      ))}
                    </div>
                  )}
                </>
              )}

              <div className="mt-4 flex flex-wrap items-center gap-4">
                <label className="flex items-center gap-2 text-xs font-semibold uppercase tracking-[0.08em] text-muted">
                  Extra ₱
                  <input
                    type="number"
                    min="0"
                    step="0.01"
                    inputMode="decimal"
                    value={customization.additional_price}
                    disabled={disabled}
                    onChange={(event) =>
                      replace(index, {
                        ...customization,
                        additional_price: Math.max(
                          0,
                          Number(event.target.value) || 0,
                        ),
                      })
                    }
                    aria-label={`Extra price for ${customization.option_name || 'this option'}`}
                    className="num h-9 w-24 rounded-field border border-hairline bg-raised px-2 text-sm font-normal normal-case tracking-normal text-ink"
                  />
                </label>

                <label className="flex items-center gap-2 text-xs font-semibold uppercase tracking-[0.08em] text-muted">
                  <input
                    type="checkbox"
                    checked={customization.is_required === true}
                    disabled={disabled}
                    onChange={(event) =>
                      replace(index, {
                        ...customization,
                        is_required: event.target.checked,
                      })
                    }
                    className="h-4 w-4 rounded border-hairline accent-clay"
                  />
                  Required
                </label>
              </div>
            </li>
          )
        })}
      </ul>

      <button
        type="button"
        onClick={() => onChange([...customizations, emptyCustomization()])}
        disabled={disabled}
        className="btn btn-outline w-full"
      >
        <Plus className="h-4 w-4" aria-hidden="true" />
        Add an option
      </button>
    </div>
  )
}
