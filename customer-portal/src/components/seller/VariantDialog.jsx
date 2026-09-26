import { useEffect, useRef, useState } from 'react'
import { createPortal } from 'react-dom'
import { Minus, Plus, X } from 'lucide-react'

import Chip from '../ui/Chip.jsx'
import {
  applyVariantSheet,
  blankSheetEntry,
  sheetEntriesForColour,
  sheetPreview,
  sheetProblems,
  sheetSaveLabel,
} from '../../lib/productVariants.js'
import {
  SIZING_SYSTEMS,
  SIZING_SYSTEM_NAMES,
  groupSizes,
  sizeValue,
  sizingSystemOf,
  sizingValueOf,
} from '../../lib/sizeSystems.js'
import { swatchColour } from '../../lib/swatchRules.js'

/** The selected treatment every picker in this form uses — see `Chip`. */
const CHIP_PICKED = 'border-clay bg-clay text-ink-inverse'
const CHIP_IDLE =
  'border-hairline bg-raised text-muted-strong hover:border-card-edge hover:text-ink'

/** How a colour is named in a sentence: `Tan`, or nothing at all. */
export function colourLabel(colour) {
  return String(colour ?? '').trim()
}

/**
 * One picked size, and the counts behind it — **for one colour**.
 *
 * The colour is not a field here: the sheet is always opened from a colour's card,
 * every row it writes is that colour, and the app's own variant sheet is scoped the
 * same way (`colorOverride`, reached through `_showVariantSheetForColor`). So the
 * colour is a *label* on each row, which is what keeps the aria-labels honest when
 * a seller has the sheet open for the second colour of the same size.
 *
 * Three things the layout is doing:
 *
 *  1. **The count is one control, not three.** `− count +` sit in a single bordered
 *     pill, because they are one answer — *how many* — and three separate boxes in a
 *     row read as three fields that happen to be adjacent. The native number
 *     spinners are switched off inside it, since doubling our own buttons with the
 *     browser's is the one place the two really are the same control.
 *  2. **`−` stops at zero and does not invent one.** An empty count and a count of
 *     `0` are different things — *nobody has counted this yet* versus *none left* —
 *     so `−` on an empty box is disabled rather than clamping to `0`, which would
 *     quietly replace "not counted" with a claim about the shelf.
 *  3. **The optional fields are on their own line, with their units on the border**,
 *     so the boxes stay the height of everything above them and the price and SKU do
 *     not compete with the count.
 */
export function VariantSheetSize({
  size,
  colour,
  entries,
  onChange,
  onAddRow,
  onRemoveSize,
  onRemoveRow,
}) {
  const value = sizingValueOf(size)
  const name = colourLabel(colour)
  const where = name ? `${value} in ${name}` : value

  return (
    <li className="rounded-field border border-hairline bg-subtle/40 p-3">
      <div className="flex items-center gap-2">
        <span className="num inline-flex h-7 min-w-[1.75rem] items-center justify-center rounded-full bg-clay px-1.5 text-xs font-semibold text-ink-inverse">
          {value}
        </span>
        {name ? (
          <span className="flex items-center gap-1.5 text-xs text-muted">
            <span
              aria-hidden="true"
              style={{ backgroundColor: swatchColour(name) }}
              className="h-3 w-3 rounded-full border border-hairline"
            />
            {name}
          </span>
        ) : (
          <span className="text-xs text-muted">no colour</span>
        )}
        {sizingSystemOf(size) === 'Other' && (
          <span className="text-xs text-muted">· custom size</span>
        )}
        <button
          type="button"
          onClick={onRemoveSize}
          aria-label={`Remove the size ${where}`}
          className="ml-auto text-muted transition-colors hover:text-crimson"
        >
          <X className="h-4 w-4" aria-hidden="true" />
        </button>
      </div>

      <div className="mt-2.5 space-y-2">
        {entries.map((entry, index) => {
          const count = Math.max(0, Math.trunc(Number(entry.stock) || 0))
          return (
            <div
              key={`${size}|${index}`}
              className="rounded-field border border-hairline-soft bg-raised p-2.5"
            >
              <div className="flex flex-wrap items-center gap-2">
                <span className="text-xs text-muted">
                  {entries.length > 1 ? `Row ${index + 1}` : 'How many'}
                </span>

                <div className="inline-flex items-center rounded-full border border-hairline bg-raised">
                  <button
                    type="button"
                    onClick={() => onChange(index, null, -1)}
                    disabled={count === 0}
                    aria-label={`One fewer ${where}`}
                    className="inline-flex h-9 w-9 items-center justify-center rounded-l-full text-clay-ink transition-colors duration-200 hover:bg-subtle disabled:cursor-not-allowed disabled:text-muted/40 disabled:hover:bg-transparent"
                  >
                    <Minus className="h-4 w-4" aria-hidden="true" />
                  </button>
                  {/* `placeholder="0"` and not a value of `0` — see the docblock. */}
                  <input
                    type="number"
                    min="0"
                    step="1"
                    inputMode="numeric"
                    value={entry.stock}
                    onChange={(event) => onChange(index, { stock: event.target.value })}
                    placeholder="0"
                    aria-label={`Stock for ${where}`}
                    className="num h-9 w-14 border-x border-hairline bg-transparent text-center text-sm text-ink placeholder:text-muted/50 focus:outline-none focus-visible:ring-2 focus-visible:ring-clay/50 [appearance:textfield] [&::-webkit-inner-spin-button]:appearance-none [&::-webkit-outer-spin-button]:appearance-none"
                  />
                  <button
                    type="button"
                    onClick={() => onChange(index, null, 1)}
                    aria-label={`One more ${where}`}
                    className="inline-flex h-9 w-9 items-center justify-center rounded-r-full text-clay-ink transition-colors duration-200 hover:bg-subtle"
                  >
                    <Plus className="h-4 w-4" aria-hidden="true" />
                  </button>
                </div>

                {entries.length > 1 && (
                  <button
                    type="button"
                    onClick={() => onRemoveRow(index)}
                    aria-label={`Remove row ${index + 1} for ${where}`}
                    className="ml-auto text-muted transition-colors hover:text-crimson"
                  >
                    <X className="h-4 w-4" aria-hidden="true" />
                  </button>
                )}
              </div>

              <div className="mt-2 flex flex-wrap items-center gap-2">
                <label className="flex h-9 w-32 items-center gap-1 rounded-field border border-hairline bg-raised px-2 text-xs text-muted">
                  <span aria-hidden="true">₱</span>
                  <input
                    type="number"
                    min="0"
                    step="0.01"
                    inputMode="decimal"
                    value={entry.additional_price}
                    onChange={(event) =>
                      onChange(index, { additional_price: event.target.value })
                    }
                    placeholder="Extra"
                    aria-label={`Extra price for ${where}`}
                    className="num h-full min-w-0 flex-1 bg-transparent text-sm text-ink placeholder:text-muted/60 focus:outline-none focus-visible:ring-2 focus-visible:ring-clay/50 [appearance:textfield]"
                  />
                </label>
                <label className="flex h-9 min-w-[9rem] flex-1 items-center gap-2 rounded-field border border-hairline bg-raised px-2 text-xs text-muted">
                  <span aria-hidden="true">SKU</span>
                  <input
                    value={entry.sku}
                    onChange={(event) => onChange(index, { sku: event.target.value })}
                    placeholder="optional"
                    aria-label={`SKU for ${where}`}
                    className="h-full min-w-0 flex-1 bg-transparent text-sm text-ink placeholder:text-muted/60 focus:outline-none focus-visible:ring-2 focus-visible:ring-clay/50"
                  />
                </label>
              </div>
            </div>
          )
        })}
      </div>

      <button
        type="button"
        onClick={onAddRow}
        className="mt-2 inline-flex items-center gap-1.5 text-xs font-semibold text-clay-ink underline-offset-4 hover:underline"
      >
        <Plus className="h-3.5 w-3.5" aria-hidden="true" />
        Another count for this size
      </button>
    </li>
  )
}

/** A section's heading, and whatever belongs on the right of it. */
export function SectionHead({ children, aside }) {
  return (
    <div className="flex items-baseline justify-between gap-3">
      <p className="text-xs font-semibold uppercase tracking-[0.08em] text-muted">
        {children}
      </p>
      {aside && <p className="num text-[11px] text-muted">{aside}</p>}
    </div>
  )
}

/**
 * The app's *Add Sizes* sheet — **one colour's** sizes, as a dialog.
 *
 * ## Why this exists when the colour sheet could draw the counts inline
 *
 * Because the app says so, and because of what a sizing system is: twenty-four
 * sizes to choose from, which is a question of its own. `_showVariantSheet` asks it
 * in three steps — *which system, which sizes, how many of each* — and
 * `_showVariantSheetForColor` reaches it from a colour card with `colorOverride`
 * set, so every row it writes is that colour and no colour field is drawn.
 *
 * ## What it does, precisely
 *
 *  1. **Sizing system** — US, EU, UK, or one typed in. Changing it clears the sizes
 *     below, because `'42'` means EU 42.
 *  2. **Sizes** — every size in the chosen system, multi-select, so the five sizes a
 *     product comes in are five taps. A size this colour already stocks opens with
 *     its own row (`sheetEntriesForColour`), which is what makes this an editor as
 *     well as an adder.
 *  3. **Rows** — a count each, with an optional extra price and SKU, and *Another
 *     count for this size* for the one case that needs two (a size counted in two
 *     batches is still one row per re-count, and `sheetProblems` refuses two rows
 *     that would collide).
 *
 * The save button says what it writes — *Add 6 variants*, *Update variant* — from
 * `sheetSaveLabel`, and **applying replaces only this colour's rows for the sizes it
 * picked** (`applyVariantSheet`). The other colours, and this colour's other sizes,
 * are left exactly as they were.
 *
 * `label` is what the colour is *called* where rows are drawn, and defaults to the
 * scope itself. The two differ in one case: a colour being added has a name the
 * seller has typed but no rows yet, so `colour` is the name its rows would carry
 * while `label` is the name on screen.
 *
 * Two deliberate divergences from the phone: it mounts only while open (so every
 * opening starts blank, and there is no exit animation — see "Animations must fail
 * open"), and the custom-system box takes a comma-separated list, because the
 * alternative is reopening the dialog once per size for a seller whose sizes are in
 * no preset. Each value is stored the app's way, as `'JP 25'`.
 */
export function VariantDialogPanel({ colour, label, variants, onApply, onClose }) {
  /*
    What the rows will be *called*, which is not the same as the scope they are
    matched by: a colour being added has a name the seller has typed and no rows
    yet, so `colour` is null while `shown` is `Black` — and a row labelled `42`
    for a colour called Black would be a lie about what is being written.
  */
  const shown = label ?? colour
  const name = colourLabel(shown)
  const [system, setSystem] = useState(
    () =>
      SIZING_SYSTEM_NAMES.find((candidate) =>
        variants.some((variant) => sizingSystemOf(variant.size) === candidate),
      ) ?? SIZING_SYSTEM_NAMES[0],
  )
  const [customSystem, setCustomSystem] = useState('')
  const [sizes, setSizes] = useState([])
  const [entries, setEntries] = useState({})
  const [sizeDraft, setSizeDraft] = useState('')
  const [errors, setErrors] = useState([])
  const systemRef = useRef(null)

  useEffect(() => {
    const onKeyDown = (event) => {
      if (event.key === 'Escape') onClose?.()
    }
    const previousOverflow = document.body.style.overflow
    document.body.style.overflow = 'hidden'
    window.addEventListener('keydown', onKeyDown)
    systemRef.current?.focus()

    return () => {
      document.body.style.overflow = previousOverflow
      window.removeEventListener('keydown', onKeyDown)
    }
  }, [onClose])

  const activeSystem = customSystem.trim() || system
  const presets = SIZING_SYSTEMS[activeSystem]
  const known = Boolean(presets)
  const ordered = groupSizes(sizes).flatMap((group) => group.sizes)
  const sheet = { colour, sizes, entries }
  const preview = sheetPreview(variants, sheet)

  const clearSizes = () => {
    setSizes([])
    setEntries({})
    setSizeDraft('')
  }

  const chooseSystem = (next) => {
    if (next === activeSystem) return
    setCustomSystem('')
    setSystem(next)
    clearSizes()
  }

  const toggleSize = (label) => {
    if (sizes.includes(label)) {
      setSizes((list) => list.filter((size) => size !== label))
      setEntries((map) => {
        const next = { ...map }
        delete next[label]
        return next
      })
      return
    }
    setSizes((list) => [...list, label])
    // What this colour already has for that size, or one empty row.
    setEntries((map) => ({ ...map, [label]: sheetEntriesForColour(variants, colour, label) }))
  }

  const addTypedSizes = () => {
    const values = sizeDraft
      .split(',')
      .map((value) => value.trim())
      .filter(Boolean)
    setSizeDraft('')
    for (const value of values) {
      const label = sizeValue(activeSystem, value)
      if (!sizes.includes(label)) toggleSize(label)
    }
  }

  /** One row changed. `delta` is a step, so both steppers share the setter setter. */
  const changeEntry = (size, index, patch, delta = 0) => {
    setErrors([])
    setEntries((map) => ({
      ...map,
      [size]: (map[size] ?? []).map((entry, at) => {
        if (at !== index) return entry
        if (patch) return { ...entry, ...patch }
        const current = Math.max(0, Math.trunc(Number(entry.stock) || 0))
        return { ...entry, stock: String(Math.max(0, current + delta)) }
      }),
    }))
  }

  const addRow = (size) => {
    setErrors([])
    setEntries((map) => ({ ...map, [size]: [...(map[size] ?? []), blankSheetEntry()] }))
  }

  const removeRow = (size, index) => {
    setErrors([])
    setEntries((map) => ({
      ...map,
      [size]: (map[size] ?? []).filter((entry, at) => at !== index),
    }))
  }

  const save = () => {
    const problems = sheetProblems(sheet)
    if (problems.errors.length > 0) {
      setErrors(problems.errors)
      return
    }
    onApply?.(applyVariantSheet(variants, sheet))
  }

  return (
    <div
      className="fade-enter fixed inset-0 z-50 flex items-end justify-center overflow-y-auto bg-scrim p-4 backdrop-blur-[2px] sm:items-center"
      onClick={() => onClose?.()}
    >
      <div
        role="dialog"
        aria-modal="true"
        aria-labelledby="variant-dialog-title"
        aria-describedby="variant-dialog-lede"
        onClick={(event) => event.stopPropagation()}
        className="rise-enter flex max-h-[90vh] w-full max-w-3xl flex-col rounded-card border border-hairline bg-raised shadow-premium"
      >
        <header className="flex items-start gap-3 border-b border-hairline-soft p-5">
          <div className="min-w-0 flex-1">
            <h2
              id="variant-dialog-title"
              className="font-display text-lg font-semibold text-ink"
            >
              {name ? `Sizes for ${name}` : 'Sizes'}
            </h2>
            <p id="variant-dialog-lede" className="mt-1 text-xs leading-relaxed text-muted">
              Pick the system these sizes are in, tap every one this colour comes
              in, then set how many you have.
            </p>
          </div>
          <button
            type="button"
            onClick={() => onClose?.()}
            aria-label="Close"
            className="-mr-1 -mt-1 inline-flex h-8 w-8 shrink-0 items-center justify-center rounded-full text-muted transition-colors duration-200 hover:bg-subtle hover:text-ink"
          >
            <X size={16} strokeWidth={2} />
          </button>
        </header>

        <div className="min-h-0 flex-1 space-y-5 overflow-y-auto p-5">
          <section>
            <SectionHead>Sizing system</SectionHead>
            <div
              role="group"
              aria-label="Sizing system"
              className="mt-2.5 flex flex-wrap items-center gap-2"
            >
              {SIZING_SYSTEM_NAMES.map((candidate, index) => (
                <span key={candidate} ref={index === 0 ? systemRef : undefined}>
                  <Chip
                    label={candidate}
                    selected={!customSystem.trim() && system === candidate}
                    onClick={() => chooseSystem(candidate)}
                  />
                </span>
              ))}
              <input
                value={customSystem}
                onChange={(event) => {
                  setCustomSystem(event.target.value)
                  if (sizes.length > 0) clearSizes()
                }}
                placeholder="or type one, e.g. JP"
                aria-label="Another sizing system"
                className="h-9 w-40 rounded-full border border-hairline bg-raised px-3 text-xs text-ink placeholder:text-muted/60"
              />
            </div>
          </section>

          <section className="border-t border-hairline-soft pt-5">
            <SectionHead
              aside={`${activeSystem}${sizes.length > 0 ? ` · ${sizes.length} picked` : ''}`}
            >
              Sizes
            </SectionHead>
            <p className="mt-1.5 text-xs leading-relaxed text-muted">
              {known
                ? 'Tap every size this colour comes in. Tapping one again takes it off.'
                : 'This system has no preset sizes — type the values, separated by commas.'}
            </p>

            {known && (
              <div
                role="group"
                aria-label={`Sizes in ${activeSystem}`}
                className="mt-3 flex flex-wrap gap-2"
              >
                {presets.map((value) => {
                  const label = sizeValue(activeSystem, value)
                  const picked = sizes.includes(label)
                  return (
                    <button
                      key={label}
                      type="button"
                      onClick={() => toggleSize(label)}
                      aria-pressed={picked}
                      className={`num rounded-full border px-3 py-1.5 text-sm font-semibold transition-colors duration-200 ease-out-cubic ${
                        picked ? CHIP_PICKED : CHIP_IDLE
                      }`}
                    >
                      {value}
                    </button>
                  )
                })}
              </div>
            )}

            <div className="mt-3 flex flex-wrap items-center gap-2">
              <label className="flex min-w-0 flex-1 items-center gap-2 text-xs text-muted">
                <span className="shrink-0">
                  {known ? 'Another size' : `Sizes in ${activeSystem || 'your system'}`}
                </span>
                <input
                  value={sizeDraft}
                  onChange={(event) => setSizeDraft(event.target.value)}
                  onKeyDown={(event) => {
                    if (event.key !== 'Enter') return
                    event.preventDefault()
                    addTypedSizes()
                  }}
                  placeholder={known ? 'e.g. 48, Kids 12' : 'e.g. 25, 25.5, 26'}
                  className="h-9 min-w-0 flex-1 rounded-field border border-hairline bg-raised px-2.5 text-sm text-ink placeholder:text-muted/60"
                />
              </label>
              <button
                type="button"
                onClick={addTypedSizes}
                disabled={!sizeDraft.trim() || !activeSystem.trim()}
                className="btn btn-outline h-9 shrink-0 py-0 text-xs"
              >
                <Plus className="h-3.5 w-3.5" aria-hidden="true" />
                Add size
              </button>
            </div>
          </section>

          {ordered.length > 0 && (
            <section className="border-t border-hairline-soft pt-5">
              <SectionHead
                aside={`${preview.count} ${preview.count === 1 ? 'variant' : 'variants'}`}
              >
                Stock{name ? ` for ${name}` : ''}
              </SectionHead>
              <ul className="mt-3 space-y-3">
                {ordered.map((size) => (
                  <VariantSheetSize
                    key={size}
                    size={size}
                    colour={shown}
                    entries={entries[size] ?? []}
                    onChange={(index, patch, delta) => changeEntry(size, index, patch, delta)}
                    onAddRow={() => addRow(size)}
                    onRemoveSize={() => toggleSize(size)}
                    onRemoveRow={(index) => removeRow(size, index)}
                  />
                ))}
              </ul>
            </section>
          )}

          {errors.length > 0 && (
            <ul role="alert" className="space-y-1.5">
              {errors.map((error) => (
                <li
                  key={error}
                  className="rounded-field border border-crimson/30 bg-crimson/[0.07] px-3 py-2 text-xs font-medium leading-relaxed text-ink"
                >
                  {error}
                </li>
              ))}
            </ul>
          )}
        </div>

        <footer className="flex flex-col-reverse gap-2 border-t border-hairline-soft p-5 sm:flex-row sm:items-center sm:justify-end">
          <p className="mr-auto text-xs text-muted">
            {preview.count === 0
              ? 'Nothing picked yet.'
              : `${preview.count} ${preview.count === 1 ? 'variant' : 'variants'} across ${
                  ordered.length
                } ${ordered.length === 1 ? 'size' : 'sizes'}.`}
          </p>
          <button type="button" onClick={() => onClose?.()} className="btn btn-outline">
            Cancel
          </button>
          <button
            type="button"
            onClick={save}
            disabled={preview.count === 0}
            className="btn btn-primary disabled:cursor-not-allowed disabled:opacity-60"
          >
            {sheetSaveLabel(preview.count, preview.updating)}
          </button>
        </footer>
      </div>
    </div>
  )
}

/**
 * The sheet, mounted where a modal has to be.
 *
 * The panel is its own component and this is three lines, because React's server
 * renderer refuses a portal outright ("Portals are not currently supported by the
 * server renderer") — so a dialog whose markup lives inside one cannot be read by
 * any harness, while a panel that is its own component can. `document.body` is the
 * container for the same reason `ConfirmDialog` uses it: `fixed inset-0` only means
 * "the window" when no ancestor is transformed, and the page wrapper animates a
 * transform for the first 260ms of every route.
 */
export default function VariantDialog(props) {
  return createPortal(<VariantDialogPanel {...props} />, document.body)
}
