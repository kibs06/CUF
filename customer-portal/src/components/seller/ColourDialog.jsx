import { useEffect, useRef, useState } from 'react'
import { createPortal } from 'react-dom'
import { AlertTriangle, ImagePlus, Plus, Trash2, X } from 'lucide-react'

import Chip from '../ui/Chip.jsx'
import VariantDialog, { SectionHead, colourLabel } from './VariantDialog.jsx'
import { ColourPhotoGrid } from './ColourPhotos.jsx'
import {
  MAX_COLOUR_IMAGES,
  addColourImage,
  colourImagesFor,
  colourSheetProblems,
  removeColourImageAt,
} from '../../lib/productColourImages.js'
import { COLOUR_PRESETS } from '../../lib/productVariants.js'
import { colourClash, rowSummary, rowsForColour } from '../../lib/colourSheet.js'
import { swatchColour } from '../../lib/swatchRules.js'

/**
 * The app's *Add Color* / *Edit Color* sheet — one colour, start to finish.
 *
 * ## The order is the point
 *
 * `_showColorSheet` asks for three things in the order a colour is actually made:
 *
 *  1. **A name** — the preset chips, or one typed in. The name is the key in both
 *     tables (see `productColourImages`), so it comes first, and a name another
 *     card already has is refused while typing, in the phone's own words.
 *  2. **Photos** — at least one, because a customer picks a colour by its photo, and
 *     the first is the cover. The sheet marks index 0 *Main*, exactly as the phone
 *     badges it.
 *  3. **Sizes and stock** — which is not asked here but *reached* from here: the
 *     **Add sizes** button opens the size sheet scoped to this colour
 *     (`_showVariantSheetForColor`), and its result comes back as this colour's
 *     rows. The list under the button is the same list the phone draws — a size
 *     chip, `Stock: N`, the extra price when there is one, and a delete.
 *
 * ## Why the rows are held as *this colour's* rows
 *
 * Because every match the size sheet makes is within one colour: a size this colour
 * already stocks opens with its own counts (`sheetEntriesForColour`), and a size it
 * does not opens empty — never seeded from another colour's row for the same size.
 * Holding the colour's own rows is what makes that true by construction rather than
 * by a filter somebody has to remember to apply. The merge back into the product is
 * `applyColourSheet`, which is where a rename moves rows and photos together.
 *
 * ## The one liberty
 *
 * The phone's *Add Sizes* is enabled before a name is typed, and rows collected
 * under an empty name keep it when the seller names the colour afterwards. Here
 * *Add sizes* asks for the name first — one line of hint instead of a colour whose
 * rows and card disagree about what it is called.
 */
export function ColourDialogPanel({
  previous = null,
  colours = [],
  variants = [],
  colourImages = {},
  onRemoveStoredPhoto,
  onApply,
  onClose,
}) {
  const [name, setName] = useState(previous ?? '')
  const [other, setOther] = useState('')
  const [images, setImages] = useState(() => colourImagesFor(colourImages, previous))
  const [rows, setRows] = useState(() => rowsForColour(variants, previous))
  const [sizeSheetOpen, setSizeSheetOpen] = useState(false)
  const [attempted, setAttempted] = useState(false)
  const nameRef = useRef(null)

  useEffect(() => {
    const onKeyDown = (event) => {
      // Escape belongs to the size sheet while it is open — it is the innermost
      // dialog, and one key press must not close both.
      if (event.key === 'Escape' && !sizeSheetOpen) onClose?.()
    }
    const previousOverflow = document.body.style.overflow
    document.body.style.overflow = 'hidden'
    window.addEventListener('keydown', onKeyDown)
    nameRef.current?.focus()

    return () => {
      document.body.style.overflow = previousOverflow
      window.removeEventListener('keydown', onKeyDown)
    }
  }, [onClose, sizeSheetOpen])

  const trimmed = name.trim()
  const clash = colourClash(colours, trimmed, previous)
  const problems = colourSheetProblems({ name: trimmed, images })
  const totalStock = rows.reduce(
    (sum, row) => sum + Math.max(0, Math.trunc(Number(row?.stock) || 0)),
    0,
  )
  const canSave = problems.errors.length === 0 && !clash

  const pickName = (value) => {
    setName(value)
    setOther('')
  }

  const removeRow = (row) => {
    setRows((list) =>
      list.filter((entry) => !(entry.size === row.size && entry.color === row.color)),
    )
  }

  const removeStoredPhoto = (index, image) => {
    // The row goes from the draft now and from the database now, the phone's own
    // behaviour — an X on a photo takes it out of the bucket, not only off screen.
    setImages((list) => removeColourImageAt(list, index))
    if (image?.id) onRemoveStoredPhoto?.(image)
  }

  const save = () => {
    setAttempted(true)
    if (!canSave) return
    onApply?.({ previous, name: trimmed, images, rows })
  }

  return (
    <div
      className="fade-enter fixed inset-0 z-50 flex items-end justify-center overflow-y-auto bg-scrim p-4 backdrop-blur-[2px] sm:items-center"
      onClick={() => onClose?.()}
    >
      <div
        role="dialog"
        aria-modal="true"
        aria-labelledby="colour-dialog-title"
        aria-describedby="colour-dialog-lede"
        onClick={(event) => event.stopPropagation()}
        className="rise-enter flex max-h-[90vh] w-full max-w-2xl flex-col rounded-card border border-hairline bg-raised shadow-premium"
      >
        <header className="flex items-start gap-3 border-b border-hairline-soft p-5">
          <div className="min-w-0 flex-1">
            <h2
              id="colour-dialog-title"
              className="font-display text-lg font-semibold text-ink"
            >
              {previous ? `Edit ${colourLabel(previous)}` : 'Add a colour'}
            </h2>
            <p id="colour-dialog-lede" className="mt-1 text-xs leading-relaxed text-muted">
              Name the colour, give it at least one photo, then add the sizes it
              comes in.
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
            <SectionHead aside={trimmed ? undefined : 'required'}>Colour name</SectionHead>
            <div
              role="group"
              aria-label="Colour name"
              className="mt-2.5 flex flex-wrap items-center gap-2"
            >
              {COLOUR_PRESETS.map((preset, index) => (
                <span key={preset} ref={index === 0 ? nameRef : undefined}>
                  <Chip
                    label={preset}
                    selected={trimmed === preset}
                    // Tapping the chosen one takes it off, the phone's own
                    // `allowDeselect` — a mis-tap is one tap away from being undone.
                    onClick={() => pickName(trimmed === preset ? '' : preset)}
                  />
                </span>
              ))}
              <input
                value={other}
                onChange={(event) => {
                  setOther(event.target.value)
                  setName(event.target.value)
                }}
                placeholder="or type one, e.g. Burnished Clay"
                aria-label="Another colour name"
                className="h-9 w-52 rounded-full border border-hairline bg-raised px-3 text-xs text-ink placeholder:text-muted/60"
              />
            </div>

            {trimmed && (
              <p className="mt-2 flex items-center gap-1.5 text-xs text-muted">
                <span
                  aria-hidden="true"
                  style={{ backgroundColor: swatchColour(trimmed) }}
                  className="h-3 w-3 rounded-full border border-hairline"
                />
                Customers see this as {colourLabel(trimmed)}.
              </p>
            )}

            {(attempted || clash) && (clash || !trimmed) && (
              <p role="alert" className="mt-2 text-xs font-medium text-crimson">
                {clash ?? 'Type a colour name first.'}
              </p>
            )}
          </section>

          <section className="border-t border-hairline-soft pt-5">
            <SectionHead aside={`${images.length} of ${MAX_COLOUR_IMAGES}`}>
              Photos
            </SectionHead>
            <p className="mt-1.5 text-xs leading-relaxed text-muted">
              At least one, {MAX_COLOUR_IMAGES} at the most. The first is the cover —
              it is what a customer sees before they tap the colour.
            </p>

            {attempted && images.length === 0 && (
              <p className="mt-2.5 flex items-start gap-2 rounded-field border border-crimson/30 bg-crimson/[0.07] px-3 py-2 text-xs leading-relaxed text-ink">
                <AlertTriangle className="mt-0.5 h-3.5 w-3.5 shrink-0 text-crimson" aria-hidden="true" />
                This colour needs at least one photo before it can be saved.
              </p>
            )}

            <div className="mt-3">
              <ColourPhotoGrid
                images={images}
                onAdd={(files) => {
                  setImages((list) =>
                    files.reduce((acc, file) => addColourImage(acc, { file }), list),
                  )
                }}
                onRemoveStored={removeStoredPhoto}
                onRemovePending={(index) =>
                  setImages((list) => removeColourImageAt(list, index))
                }
              />
            </div>
          </section>

          <section className="border-t border-hairline-soft pt-5">
            <SectionHead aside={rows.length > 0 ? `total ${totalStock}` : undefined}>
              Sizes and stock
            </SectionHead>

            {rows.length === 0 ? (
              <p className="mt-3 rounded-field border border-hairline-soft bg-subtle/40 px-3 py-2.5 text-xs leading-relaxed text-muted">
                No sizes for {colourLabel(trimmed) || 'this colour'} yet. Add them
                below — that is where the stock goes.
              </p>
            ) : (
              <ul className="mt-3 space-y-2">
                {rows.map((row) => {
                  const summary = rowSummary(row)
                  return (
                    <li
                      key={`${row.size}|${row.color ?? ''}`}
                      className="flex flex-wrap items-center gap-2 rounded-field border border-hairline-soft bg-subtle/40 px-3 py-2"
                    >
                      <span className="num inline-flex h-7 min-w-[2.5rem] items-center justify-center rounded-full bg-clay/10 px-1.5 text-xs font-semibold text-clay-ink">
                        {summary.size}
                      </span>
                      <span className="num text-xs font-medium text-ink">
                        {summary.label}
                      </span>
                      {summary.extraLabel && (
                        <span className="num text-xs text-clay-ink">
                          {summary.extraLabel}
                        </span>
                      )}
                      <button
                        type="button"
                        onClick={() => removeRow(row)}
                        aria-label={`Remove ${summary.size} from ${colourLabel(trimmed) || 'this colour'}`}
                        className="ml-auto text-muted transition-colors duration-200 hover:text-crimson"
                      >
                        <Trash2 className="h-4 w-4" aria-hidden="true" />
                      </button>
                    </li>
                  )
                })}
              </ul>
            )}

            <div className="mt-3 flex flex-wrap items-center gap-3">
              <button
                type="button"
                onClick={() => setSizeSheetOpen(true)}
                disabled={!trimmed}
                title={trimmed ? undefined : 'Name the colour first'}
                className="btn btn-outline py-0 text-xs"
              >
                <Plus className="h-3.5 w-3.5" aria-hidden="true" />
                Add sizes
              </button>
              {!trimmed && (
                <p className="flex items-center gap-1.5 text-xs text-muted">
                  <ImagePlus className="h-3.5 w-3.5" aria-hidden="true" />
                  Name the colour first — its rows are stored under that name.
                </p>
              )}
              {rows.length > 0 && (
                <p className="num text-xs font-semibold text-ink">
                  Total stock: {totalStock}
                </p>
              )}
            </div>
          </section>

          {attempted && problems.errors.length > 0 && (
            <ul role="alert" className="space-y-1.5">
              {problems.errors.map((error) => (
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
            {canSave
              ? `${rows.length} ${rows.length === 1 ? 'size' : 'sizes'} · ${totalStock} in stock`
              : 'A name and one photo are all it needs.'}
          </p>
          <button type="button" onClick={() => onClose?.()} className="btn btn-outline">
            Cancel
          </button>
          <button
            type="button"
            onClick={save}
            aria-disabled={!canSave}
            className={`btn btn-primary ${canSave ? '' : 'cursor-not-allowed opacity-60'}`}
          >
            {previous ? 'Update colour' : 'Add colour'}
          </button>
        </footer>
      </div>

      {/*
        The size sheet, over this one — the phone's nesting exactly: a colour card
        opens the colour sheet, whose *Add Sizes* opens the variant sheet scoped to
        the colour being edited. Its result is this colour's rows, and nothing else
        on the product is touched.
      */}
      {sizeSheetOpen && (
        <VariantDialog
          colour={previous}
          label={trimmed || previous}
          variants={rows}
          onApply={(next) => {
            setSizeSheetOpen(false)
            setRows(next)
          }}
          onClose={() => setSizeSheetOpen(false)}
        />
      )}
    </div>
  )
}

/**
 * The colour sheet, mounted where a modal has to be — see `VariantDialog` for why
 * the panel and the portal are two components.
 */
export default function ColourDialog(props) {
  return createPortal(<ColourDialogPanel {...props} />, document.body)
}
