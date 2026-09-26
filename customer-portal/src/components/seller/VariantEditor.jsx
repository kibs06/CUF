import { useState } from 'react'
import { AlertTriangle, ImageOff, Pencil, Plus, Trash2 } from 'lucide-react'

import ColourDialog from './ColourDialog.jsx'
import VariantDialog, { colourLabel } from './VariantDialog.jsx'
import { ColourThumbnailStrip } from './ColourPhotos.jsx'
import { variantTotals } from '../../lib/productVariants.js'
import { colourSummaries } from '../../lib/productColourImages.js'
import {
  applyColourSheet,
  removeColourEverywhere,
} from '../../lib/colourSheet.js'
import { swatchColour } from '../../lib/swatchRules.js'

/**
 * Sizes and variants, as the app builds them: **one card per colour**.
 *
 * ## Why cards rather than a grid
 *
 * Because a colour is the thing a seller actually has in front of them, and the app
 * says so: `_buildVariantsSection` draws a card per colour — its cover photo, its
 * name, `photos · sizes · in stock`, and whether it still needs photos — with *Add
 * Color* underneath. Everything that writes stock is reached from a card: the card
 * opens the colour sheet (`ColourDialog`), which asks for a name and photos and then
 * hands off to the size sheet (`VariantDialog`) scoped to that colour. Sizes are
 * never entered against the product, only against a colour of it — which is how the
 * phone works and why its *Sizes & Variants* section is nothing but cards and one
 * button.
 *
 * The grid this replaced was the portal's own invention — a good way to *change* a
 * count, and a poor way to start, because a product with no sizes showed an empty
 * table whose way in was to work out the order the columns had to be added in.
 *
 * ## The one card the phone does not have
 *
 * `product_variants.color` is nullable and most of this catalog is one row per size
 * with a NULL colour — everything the portal wrote before it could express colours,
 * and the shape the storefront reads for a single-colour product. The phone
 * *requires* a colour (`'Please add at least 1 color.'`) and turns those rows into a
 * nameless colour card, which is a colour it cannot then save. So the uncoloured
 * rows get a card too: **No colour**, with its sizes and its stock, and no names or
 * photos to fill in because there is nothing there to name. It is the same card with
 * the two questions removed.
 *
 * ## What each button writes
 *
 *  * **Add colour** → `ColourDialog` for a new colour, applied by `applyColourSheet`.
 *  * **A card** → the same dialog, editing: the name, the photos and the rows, with
 *    a rename moving all three together.
 *  * **A card's trash** → `removeColourEverywhere`: the rows, the photos and the
 *    colour, in one call, because a colour exists in all three places or in none.
 *  * **Add sizes** (inside the colour sheet) → `VariantDialog`, scoped to that one
 *    colour, merging through `applyVariantSheet`. Inside the *No colour* card it is
 *    the same sheet with a NULL scope, which is the uncoloured rows.
 */
export default function VariantEditor({
  variants,
  colours,
  colourImages = {},
  onChange,
  onRemoveStoredPhoto,
  disabled = false,
}) {
  /** Which sheet is open: `{ previous }` for a colour, `'none'` for no colour. */
  const [sheet, setSheet] = useState(null)

  const summaries = colourSummaries({ colours, variants, colourImages })
  const looseRows = variants.filter((variant) => !String(variant.color ?? '').trim())
  const totals = variantTotals(variants, colours)

  /* One commit for all three, because the colour sheet can change any of them. */
  const push = (next) => {
    onChange({
      variants: next.variants ?? variants,
      colours: next.colours ?? colours,
      colourImages: next.colourImages ?? colourImages,
    })
  }

  const saveColour = (payload) => {
    const merged = applyColourSheet({
      variants,
      colours,
      colourImages,
      previous: payload.previous,
      name: payload.name,
      images: payload.images,
      rows: payload.rows,
    })
    // The dialog refuses a blank or duplicate name itself, so this is the belt
    // to its braces — and when it does fire the sheet stays open rather than
    // closing over an edit that was not made.
    if (merged.error) return
    setSheet(null)
    push(merged)
  }

  const cardCount = summaries.length + (looseRows.length > 0 ? 1 : 0)

  return (
    <div className="space-y-3">
      {looseRows.length > 0 && (
        <Card
          name="No colour"
          /* Its own size count and stock, read off its rows — it has no photos, so
             the phone's `photos · sizes · in stock` line would start with a zero. */
          summary={`${new Set(looseRows.map((row) => row.size)).size} size${
            new Set(looseRows.map((row) => row.size)).size === 1 ? '' : 's'
          } · ${looseRows.reduce((sum, row) => sum + (Number(row.stock) || 0), 0)} in stock`}
          note="A single-colour product — every size in one, no colour to pick."
          onEdit={() => setSheet('none')}
          disabled={disabled}
        />
      )}

      {summaries.map((summary) => (
        <Card
          key={summary.name}
          name={summary.name}
          images={colourImages[summary.name] ?? []}
          summary={summary.label}
          swatch={summary.name}
          /* The phone's own warning, in its own place: a colour with no photos is
             a colour the storefront cannot show a picture for. A note, never a
             block — see `colourPhotoNotes`. */
          note={
            summary.photos === 0
              ? 'Add photos — customers pick a colour by its picture.'
              : null
          }
          needsPhoto={summary.photos === 0}
          onEdit={() => setSheet({ previous: summary.name })}
          onRemove={() => push(removeColourEverywhere({ variants, colours, colourImages, name: summary.name }))}
          disabled={disabled}
        />
      ))}

      {cardCount === 0 && (
        <p className="rounded-field border border-dashed border-card-edge bg-subtle/40 px-4 py-6 text-center text-sm leading-relaxed text-muted">
          No sizes yet. A colour holds a product&rsquo;s sizes and their stock — start
          with <span className="font-semibold text-ink">Add colour</span> for a
          product that comes in more than one, or{' '}
          <span className="font-semibold text-ink">Add sizes without colours</span>{' '}
          for a single-colour product.
        </p>
      )}

      <div className="flex flex-wrap gap-2">
        <button
          type="button"
          onClick={() => setSheet({ previous: null })}
          disabled={disabled}
          className="btn btn-outline flex-1 py-0"
        >
          <Plus className="h-4 w-4" aria-hidden="true" />
          Add colour
        </button>
        {/*
          The other half of the empty state, and only offered while there is
          nothing to conflict with: a product that already has colours adds a
          colourless size through the sheet inside one of them only if it means
          "no colour", which is what this button says out loud.
        */}
        {looseRows.length === 0 && (
          <button
            type="button"
            onClick={() => setSheet('none')}
            disabled={disabled}
            className="btn btn-outline flex-1 py-0"
          >
            <Plus className="h-4 w-4" aria-hidden="true" />
            Add sizes without colours
          </button>
        )}
      </div>

      {sheet === 'none' && (
        <VariantDialog
          colour={null}
          label={colourLabel(null)}
          variants={looseRows}
          onApply={(next) => {
            setSheet(null)
            push({ variants: replaceLooseRows(variants, looseRows, next) })
          }}
          onClose={() => setSheet(null)}
        />
      )}

      {sheet && sheet !== 'none' && (
        <ColourDialog
          previous={sheet.previous}
          colours={colours}
          variants={variants}
          colourImages={colourImages}
          onRemoveStoredPhoto={onRemoveStoredPhoto}
          onApply={saveColour}
          onClose={() => setSheet(null)}
        />
      )}

      <p className="text-xs text-muted">
        {totals.rows === 0
          ? 'No sizes yet.'
          : `${totals.sizes} ${totals.sizes === 1 ? 'size' : 'sizes'} · ${
              totals.pairs
            } pair${totals.pairs === 1 ? '' : 's'} in stock${
              totals.colours > 0 ? ` · ${totals.colours} colours` : ''
            }${
              /* The one shape `variantProblems` can only note, said where the
                 seller can still do something about it. */
              looseRows.length > 0 && summaries.length > 0
                ? ' · some sizes have no colour'
                : ''
            }.`}
      </p>
    </div>
  )
}

/**
 * The uncoloured rows, swapped for the set the size sheet returned.
 *
 * The colour sheet's merge is `replaceColourRows`, which cannot be used here: it
 * keys on a colour name and the uncoloured rows have none, so filtering by
 * `colourOf(variant) !== null` would take every *other* colour's rows with it.
 * Two steps instead — the uncoloured rows out, the sheet's rows in — and the order
 * is the caller's because those rows sit at the front of the set.
 */
function replaceLooseRows(variants, looseRows, next) {
  const looseSizes = new Set(looseRows.map((row) => row.size))
  const kept = variants.filter(
    (variant) => String(variant.color ?? '').trim() || !looseSizes.has(variant.size),
  )
  return [...next.map((row) => ({ ...row, color: null })), ...kept]
}

/**
 * One colour, as the app's card draws it.
 *
 * A cover photo (or the dashed placeholder that says there isn't one), the name
 * beside its swatch dot, the `photos · sizes · in stock` line, and the two things
 * the phone offers — a pencil and a bin. The whole card is the pencil, and the bin
 * is a button of its own because it is the one action here that cannot be undone by
 * editing again.
 */
function Card({
  name,
  images,
  summary,
  note,
  swatch,
  needsPhoto = false,
  onEdit,
  onRemove,
  disabled = false,
}) {
  return (
    <div
      className={`flex items-center gap-3 rounded-card border bg-raised p-3 shadow-card transition-shadow duration-200 ${
        needsPhoto ? 'border-crimson/40' : 'border-hairline'
      }`}
    >
      {images ? (
        <ColourThumbnailStrip images={images} />
      ) : (
        <span className="flex h-12 w-12 shrink-0 items-center justify-center rounded-field border border-dashed border-card-edge bg-subtle">
          <ImageOff className="h-4 w-4 text-muted" aria-hidden="true" />
        </span>
      )}

      <button
        type="button"
        onClick={onEdit}
        disabled={disabled}
        className="min-w-0 flex-1 text-left"
      >
        <span className="flex items-center gap-1.5">
          {swatch && (
            <span
              aria-hidden="true"
              style={{ backgroundColor: swatchColour(swatch) }}
              className="h-3 w-3 shrink-0 rounded-full border border-hairline"
            />
          )}
          <span className="truncate text-sm font-semibold text-ink">{name}</span>
        </span>
        <span className="num mt-1 block text-xs text-muted">{summary}</span>
        {note && (
          <span
            className={`mt-1 flex items-center gap-1.5 text-xs font-medium ${
              needsPhoto ? 'text-crimson' : 'text-muted'
            }`}
          >
            {needsPhoto && (
              <AlertTriangle className="h-3.5 w-3.5 shrink-0" aria-hidden="true" />
            )}
            {note}
          </span>
        )}
      </button>

      <button
        type="button"
        onClick={onEdit}
        disabled={disabled}
        aria-label={`Edit ${name}`}
        className="inline-flex h-9 w-9 shrink-0 items-center justify-center rounded-full text-clay-ink transition-colors duration-200 hover:bg-subtle"
      >
        <Pencil className="h-4 w-4" aria-hidden="true" />
      </button>
      {onRemove && (
        <button
          type="button"
          onClick={onRemove}
          disabled={disabled}
          aria-label={`Remove ${name} and everything in it`}
          className="inline-flex h-9 w-9 shrink-0 items-center justify-center rounded-full text-muted transition-colors duration-200 hover:bg-crimson/10 hover:text-crimson"
        >
          <Trash2 className="h-4 w-4" aria-hidden="true" />
        </button>
      )}
    </div>
  )
}
