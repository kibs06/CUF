/**
 * Customisation options — the rules for `product_customizations`, a port of the
 * add/edit sheet in the app's product form.
 *
 * ## What an option is
 *
 * One row per option: a name the customer reads ("Engraving text"), a **type**
 * that says how it is answered, the choices a `select`/`color` type offers, an
 * extra price, and whether it can be skipped.
 *
 *   `text`   — a free-text field. No choices: there is nothing to choose from.
 *   `select` — a list of choices.
 *   `color`  — a list of choices that are colours.
 *
 * The type is a **closed vocabulary plus free text**, and that is the app's
 * design rather than this port's: the column's CHECK was relaxed to
 * `length(option_type) > 0` precisely so a seller could invent `number` or
 * `file upload`, and the app offers those presets with an "e.g. number, date,
 * file upload" hint. So an unrecognised type is not a bad value to be repaired —
 * it is a value to be shown as typed, which is why `customizationTypeLabel`
 * falls back to the raw string rather than to 'Text'.
 *
 * ## Choices belong to two types only
 *
 * The app's sheet hides the choice editor for `text`, and so does this: offering
 * a choice list for a free-text option is offering something the customer can
 * never pick. The list is kept on the row when the type changes away and back, so
 * a mis-tap does not cost a seller their typed choices — and it is still written
 * for a `text` option, because the column keeps what the row holds and dropping
 * it would make switching type a destructive act.
 */

/** The three built-in types, in the order the app offers them. */
export const CUSTOMIZATION_TYPES = [
  { value: 'text', label: 'Text' },
  { value: 'select', label: 'Select' },
  { value: 'color', label: 'Color' },
]

/** The app's default for a new option — never nothing, so a save can proceed. */
export const DEFAULT_CUSTOMIZATION_TYPE = 'text'

/** A hand-typed type, the app's own limit. */
export const MAX_CUSTOM_TYPE_LENGTH = 30

/** The label for a type: the preset's, or the typed text itself. */
export function customizationTypeLabel(value) {
  const text = String(value ?? '').trim()
  if (!text) return ''
  for (const type of CUSTOMIZATION_TYPES) {
    if (type.value === text) return type.label
  }
  return text
}

/** Whether a type can carry choices — the two the app shows a list for. */
export function typeHasChoices(value) {
  const text = String(value ?? '').trim()
  return text === 'select' || text === 'color'
}

/** A blank option, ready to edit. */
export function emptyCustomization(overrides = {}) {
  return {
    option_name: '',
    option_type: DEFAULT_CUSTOMIZATION_TYPE,
    options: [],
    is_required: false,
    additional_price: 0,
    ...overrides,
  }
}

/** One stored row → the draft's shape, coerced. */
export function customizationFromRow(row) {
  const options = Array.isArray(row?.options) ? row.options : []
  return {
    option_name: String(row?.option_name ?? '').trim(),
    option_type: String(row?.option_type ?? '').trim() || DEFAULT_CUSTOMIZATION_TYPE,
    options: options
      .map((option) => String(option ?? '').trim())
      .filter((option) => option.length > 0),
    is_required: row?.is_required === true,
    additional_price: Math.max(0, Number(row?.additional_price) || 0),
  }
}

/** A product's stored options, in the order the id gives them back. */
export function customizationsFromProduct(rows) {
  return (rows ?? []).map(customizationFromRow)
}

/**
 * Add one choice, or explain why it cannot be.
 *
 * The app's add button silently ignores a blank and happily takes a duplicate;
 * this refuses the duplicate instead, because two chips reading "Red" under a
 * colour option is a picker showing the same choice twice and nothing downstream
 * can tell them apart. The refusal is a sentence under the input, so the seller
 * is told rather than ignored.
 */
export function addChoice(customization, text) {
  const value = String(text ?? '').trim()
  const current = customization?.options ?? []

  if (!value) return { customization, error: null }
  if (current.some((option) => option.toLowerCase() === value.toLowerCase())) {
    return { customization, error: 'That choice is already added.' }
  }

  return {
    customization: { ...customization, options: [...current, value] },
    error: null,
  }
}

/** Remove one choice. */
export function removeChoice(customization, choice) {
  return {
    ...customization,
    options: (customization?.options ?? []).filter((option) => option !== choice),
  }
}

/**
 * What would keep this option from being saved, and what is worth saying anyway.
 *
 * The errors are the app's own two — a name and a type, both of which it refuses
 * to save without, in its own words. The note is about a save that will land but
 * is probably not what was meant.
 */
export function customizationProblems(customization) {
  const errors = []
  const notes = []

  if (!String(customization?.option_name ?? '').trim()) {
    errors.push('Give the option a name.')
  }
  if (!String(customization?.option_type ?? '').trim()) {
    errors.push('Choose a kind of option.')
  }
  if (
    typeHasChoices(customization?.option_type) &&
    (customization?.options ?? []).length === 0
  ) {
    notes.push(
      `${String(customization.option_name ?? '').trim() || 'This option'} has no choices yet, so the list a customer picks from would be empty.`,
    )
  }

  return { errors, notes }
}

/**
 * Every option, as `product_customizations` rows.
 *
 * An option with no name or no type is dropped rather than written: both columns
 * are load-bearing (the type is NOT NULL with a CHECK, the name is what a
 * customer reads), and the form blocks the save before this is reached — this is
 * the guard for the caller that did not.
 */
export function customizationRowsForInsert(customizations) {
  const rows = []
  for (const customization of customizations ?? []) {
    const name = String(customization?.option_name ?? '').trim()
    const type = String(customization?.option_type ?? '').trim()
    if (!name || !type) continue
    rows.push({
      option_name: name,
      option_type: type,
      options: (customization?.options ?? []).map((option) =>
        String(option ?? '').trim(),
      ),
      is_required: customization?.is_required === true,
      additional_price: Math.max(0, Number(customization?.additional_price) || 0),
    })
  }
  return rows
}

/** `{ count, required, withExtra }` — the line under the editor. */
export function customizationTotals(customizations) {
  const rows = customizationRowsForInsert(customizations)
  return {
    count: rows.length,
    required: rows.filter((row) => row.is_required).length,
    withExtra: rows.filter((row) => row.additional_price > 0).length,
  }
}
