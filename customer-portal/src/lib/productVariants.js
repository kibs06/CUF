/**
 * Colours, sizes and the stock behind them — the rules for `product_variants`
 * and the `inventory` rows derived from it.
 *
 * ## Two tables, and which one anybody reads
 *
 * `product_variants` is where stock is *written*: one row per (size, colour),
 * each with its own `stock`, `additional_price` and `sku`. `inventory` is where
 * stock is *read*: one row per size, summed across that size's colours, and it is
 * what the storefront's size grid and the checkout decrement. There is no trigger
 * between them — the app derives `inventory` in `_syncInventoryFromVariants()`,
 * and the portal has to do the same arithmetic for the same reason: a portal that
 * wrote only variants would leave the customer's size grid reading stale stock.
 *
 * ## The uncoloured column
 *
 * `product_variants.color` is nullable, and a single-colour product is one row
 * per size with a NULL colour — which is what the portal wrote before it could
 * express colours at all, and still what most products in the catalog are. So the
 * uncoloured column is not a workaround: it is the common case, and it is
 * represented by `UNCOLOURED` (null) rather than by an empty string, because that
 * is what the column holds.
 *
 * A draft's columns are its `colours` when it has any, and the single uncoloured
 * column when it has none. A product carrying *both* — colourless rows alongside
 * named ones, which the app's own form cannot produce but the table can hold —
 * keeps its colourless column as well, so those rows stay visible and editable
 * instead of being dropped by a form that assumed one shape or the other.
 *
 * ## Why `additional_price` and `sku` are here at all
 *
 * Both are per variant, not per size: a size 42 in tan can cost more than the
 * same size in black. The storefront's cart already resolves a variant by (size,
 * colour) and adds its `additional_price` to the line, so a variant the seller
 * could not price from the web would be a price only the phone could set.
 */

import { groupSizes } from './sizeSystems.js'

/** The colour a variant has when it has none — the column's own NULL. */
export const UNCOLOURED = null

/**
 * The colour names the app offers as chips, in its order.
 *
 * Ported rather than invented, and for a reason beyond tidiness: this list is
 * also what makes the duplicate check mean anything. The form refuses a name that
 * is already a colour, and a preset chip is how a seller picks the common ones
 * without typing. A name that is not here is still allowed — a `color` is free
 * text in the column — so this is a shortcut, not a vocabulary.
 */
export const COLOUR_PRESETS = [
  'Black',
  'Brown',
  'Carob',
  'Cream',
  'Burgundy',
  'Gold',
  'Olive',
  'Navy',
  'Grey',
  'White',
  'Beige',
]

/** A raw colour value as it should be stored: trimmed, or UNCOLOURED when blank. */
export function normaliseColour(value) {
  const name = String(value ?? '').trim()
  return name.length > 0 ? name : UNCOLOURED
}

/** A raw size value as it should be stored: trimmed. */
export function normaliseSize(value) {
  return String(value ?? '').trim()
}

/** A variant's colour, normalised. */
export function colourOf(variant) {
  return normaliseColour(variant?.color)
}

/** A variant's size, normalised. */
export function sizeOf(variant) {
  return normaliseSize(variant?.size)
}

/**
 * The colour names in use, in first-appearance order.
 *
 * First appearance rather than alphabetical: the seller added them in an order
 * they have in their head (usually the order the pairs sit on the shelf), and a
 * form that re-sorted them would move a seller's second colour to the front
 * between opening the page and saving it.
 */
export function coloursFromVariants(variants) {
  const names = []
  for (const variant of variants ?? []) {
    const name = colourOf(variant)
    if (name && !names.includes(name)) names.push(name)
  }
  return names
}

/** Every size on the product, in size order — halves in the right place. */
export function sizesFromVariants(variants) {
  const sizes = []
  for (const variant of variants ?? []) {
    const size = sizeOf(variant)
    if (size && !sizes.includes(size)) sizes.push(size)
  }
  return groupSizes(sizes).flatMap((group) => group.sizes)
}

/**
 * The columns the editor draws: one stock box each.
 *
 * See the module docs for the two shapes this collapses into one.
 */
export function variantColumns(variants, colours = []) {
  const columns = []
  const hasUncoloured = (variants ?? []).some(
    (variant) => colourOf(variant) === UNCOLOURED,
  )
  if (hasUncoloured && (colours ?? []).length > 0) columns.push(UNCOLOURED)
  for (const name of colours ?? []) columns.push(name)
  if (columns.length === 0) columns.push(UNCOLOURED)
  return columns
}

/** One variant as the draft's row: numbers for numbers, text for text. */
function draftRow(variant, overrides = {}) {
  return {
    size: sizeOf(variant),
    color: colourOf(variant),
    stock: Math.max(0, Math.trunc(Number(variant?.stock) || 0)),
    additional_price: Math.max(0, Number(variant?.additional_price) || 0),
    sku: String(variant?.sku ?? '').trim(),
    ...overrides,
  }
}

/**
 * A product's stored variants → the draft's rows, in the editor's own order.
 *
 * Ordered because the editor draws them as a grid: sizes down, colours across —
 * and a product edited twice comes back from Postgres in insertion order, which
 * on a product whose sizes were added out of order is `40, 41, 39, 38, 42`.
 *
 * `colourOrder` is optional and is how a caller that already knows the order says
 * so. Left out, the colours come out in first-appearance order, which is right for
 * a fresh read of the table — and wrong for a merge, where removing one colour's
 * row and appending it again would move that colour in front of the others. A
 * seller's second colour should stay second after an edit nobody made to it.
 */
export function variantsFromProduct(variants, colourOrder) {
  const rows = []
  for (const variant of variants ?? []) rows.push(draftRow(variant))

  const sizeOrder = sizesFromVariants(rows)
  const columns = colourOrder ?? variantColumns(rows, coloursFromVariants(rows))

  return [...rows].sort((a, b) => {
    const sizeDiff = sizeOrder.indexOf(a.size) - sizeOrder.indexOf(b.size)
    if (sizeDiff !== 0) return sizeDiff
    return columns.indexOf(a.color) - columns.indexOf(b.color)
  })
}

/** The row for one (size, colour) cell, or undefined when it has none. */
export function findVariant(variants, size, color) {
  const wanted = normaliseColour(color)
  return (variants ?? []).find(
    (variant) => sizeOf(variant) === size && colourOf(variant) === wanted,
  )
}

/** Set one field of one (size, colour) cell. Only existing rows are changed. */
export function setVariantField(variants, size, color, field, value) {
  const wanted = normaliseColour(color)
  return (variants ?? []).map((variant) => {
    if (sizeOf(variant) !== size || colourOf(variant) !== wanted) return variant
    if (field === 'stock') {
      return { ...variant, stock: Math.max(0, Math.trunc(Number(value) || 0)) }
    }
    if (field === 'additional_price') {
      return { ...variant, additional_price: Math.max(0, Number(value) || 0) }
    }
    if (field === 'sku') return { ...variant, sku: String(value ?? '') }
    return variant
  })
}

/**
 * Turn a size on, in every column.
 *
 * Every column, because a size is turned on for the *product*: a seller who adds
 * EU 42 and then has to remember to add EU 42 in tan as well would end up with a
 * product whose tan column is missing a size it comes in, and the storefront
 * would offer the pair in one colour only.
 */
export function addSize(variants, columns, size) {
  const next = [...(variants ?? [])]
  for (const color of (columns ?? []).length > 0 ? columns : [UNCOLOURED]) {
    if (!findVariant(next, size, color)) {
      next.push(draftRow({ size, color, stock: 0 }))
    }
  }
  return next
}

/** Turn a size off, in every colour. */
export function removeSize(variants, size) {
  return (variants ?? []).filter((variant) => sizeOf(variant) !== size)
}

/**
 * Add a colour — **the name only**, with no stock rows.
 *
 * A colour's sizes are added from its own sheet, which is the app's flow: a new
 * colour card starts at "0 sizes" and the seller says which sizes it comes in.
 * Seeding a row per existing size (which this used to do, back when the grid was
 * the only editor) would invent five zero-stock sizes nobody asked for and then
 * leave the card claiming a size axis the seller never chose — and the card's own
 * summary is the thing they read to see whether a colour is finished.
 *
 * So the colour list can hold a name with no rows, which is a state
 * `variantProblems` already knows about: it is a **note**, not an error, because
 * a colour with no sizes saves exactly as drawn.
 */
export function addColour(variants, colours, name) {
  const colour = normaliseColour(name)
  const current = colours ?? []
  if (!colour || current.includes(colour)) {
    return { variants: variants ?? [], colours: current }
  }
  return { variants: variants ?? [], colours: [...current, colour] }
}

/** Remove a colour and every row that named it. */
export function removeColour(variants, colours, name) {
  const wanted = normaliseColour(name)
  return {
    variants: (variants ?? []).filter(
      (variant) => colourOf(variant) !== wanted,
    ),
    colours: (colours ?? []).filter((colour) => colour !== name),
  }
}

/**
 * Rename a colour everywhere it is written.
 *
 * Refused when the target name is already in use: two columns under one name is a
 * product whose colour selector shows the same colour twice, and merging their
 * stock would be a decision about pairs the seller did not make. Names are
 * compared case-insensitively for the same reason the problems below are —
 * `Black` and `black` are one colour to everybody except this array.
 */
export function renameColour(variants, colours, from, to) {
  const next = String(to ?? '').trim()
  const current = colours ?? []

  if (!next) {
    return {
      variants: variants ?? [],
      colours: current,
      error: 'A colour needs a name.',
    }
  }
  if (next === from) {
    return { variants: variants ?? [], colours: current, error: null }
  }

  const clash = current.some(
    (colour) => colour !== from && colour.toLowerCase() === next.toLowerCase(),
  )
  if (clash) {
    return {
      variants: variants ?? [],
      colours: current,
      error: `You already have a colour called ${next}.`,
    }
  }

  return {
    variants: (variants ?? []).map((variant) =>
      colourOf(variant) === from ? { ...variant, color: next } : variant,
    ),
    colours: current.map((colour) => (colour === from ? next : colour)),
    error: null,
  }
}

/**
 * What gets saved: one `product_variants` row per cell.
 *
 * A variant with a blank size is dropped — it is not a size, and writing an empty
 * string into a NOT NULL column is a 400 the seller cannot act on. Everything
 * else is coerced rather than trusted: stock and `additional_price` are
 * non-negative by CHECK constraint, and a blank SKU is NULL, which is a value the
 * column can hold and is what the app writes.
 */
export function variantRowsForInsert(variants) {
  const rows = []
  for (const variant of variants ?? []) {
    const size = sizeOf(variant)
    if (!size) continue
    const sku = String(variant?.sku ?? '').trim()
    rows.push({
      size,
      color: colourOf(variant),
      stock: Math.max(0, Math.trunc(Number(variant?.stock) || 0)),
      additional_price: Math.max(0, Number(variant?.additional_price) || 0),
      sku: sku.length > 0 ? sku : null,
    })
  }
  return rows
}

/**
 * `inventory` rows derived from the variants: one per size, colours summed.
 *
 * Zero-stock sizes are kept, not dropped. An inventory row is what makes a size
 * *offered* — the storefront's grid draws its sizes from this table — and a
 * seller who has sold out of EU 41 wants it shown as sold out, not quietly
 * removed from the product.
 */
export function inventoryRowsFromVariants(variants) {
  const stockBySize = new Map()
  for (const variant of variants ?? []) {
    const size = sizeOf(variant)
    if (!size) continue
    const stock = Math.max(0, Math.trunc(Number(variant?.stock) || 0))
    stockBySize.set(size, (stockBySize.get(size) ?? 0) + stock)
  }

  return groupSizes([...stockBySize.keys()]).flatMap((group) =>
    group.sizes.map((size) => ({ size, stock: stockBySize.get(size) ?? 0 })),
  )
}

/** `{ sizes, colours, rows, pairs }` — the line under the editor. */
export function variantTotals(variants, colours = []) {
  const rows = variantRowsForInsert(variants)
  return {
    sizes: sizesFromVariants(rows).length,
    colours: (colours ?? []).length,
    rows: rows.length,
    pairs: rows.reduce((sum, row) => sum + row.stock, 0),
  }
}

/**
 * What would keep this from being saved, and what is worth saying anyway.
 *
 * Two separate lists, because they are two different things. An **error** is a
 * shape the schema or the app cannot express and the seller has to fix here. A
 * **note** is a product that saves exactly as drawn but is probably not what the
 * seller meant — nothing is blocked and nothing is corrected behind their back.
 *
 * The errors are deliberately narrow: a colour with no name, two colours with one
 * name, and one cell named twice. The first two are things the app's own form
 * cannot produce either, so the portal is refusing to store what the phone
 * refuses to store — not inventing a rule the phone disagrees with. The third is
 * narrower than it sounds and is explained where it is checked.
 */
export function variantProblems({ variants, colours }) {
  const errors = []
  const notes = []

  const seen = new Set()
  for (const raw of colours ?? []) {
    const name = String(raw ?? '').trim()
    if (!name) {
      errors.push('Every colour needs a name — give it one, or remove the column.')
      continue
    }
    const key = name.toLowerCase()
    if (seen.has(key)) {
      errors.push(`Two colours are both named ${name}.`)
    } else {
      seen.add(key)
    }
  }

  // A colour exists only in the rows that name it, so a colour with no rows is
  // nothing at all as far as the database — and the storefront — are concerned.
  for (const raw of colours ?? []) {
    const name = normaliseColour(raw)
    if (!name) continue
    const hasRows = (variants ?? []).some(
      (variant) => colourOf(variant) === name && sizeOf(variant),
    )
    if (!hasRows) {
      notes.push(`${name} has no sizes yet, so nothing is stored for that colour.`)
    }
  }

  /*
    One row per (size, colour) is the shape everything downstream assumes. The
    editor draws a box per cell, so two rows for one cell draw ONE box and the
    cell the seller is not looking at is the one that gets written; the storefront
    resolves a variant by (size, colour) — `resolveVariant` takes the first match
    — and `saveProductVariants` would write both rows without complaining. Only
    the sheet can produce this (the grid cannot make a cell twice), which is why
    it is refused there first with a message about the dialog — but the state can
    also arrive from Postgres, so it is refused here as well.
  */
  const cells = new Set()
  for (const variant of variants ?? []) {
    const size = sizeOf(variant)
    if (!size) continue
    const colour = colourOf(variant)
    const key = `${size}\u0000${colour ?? ''}`
    if (cells.has(key)) {
      errors.push(
        colour
          ? `Two variants are both ${colour} in ${size} — keep one.`
          : `Two variants are both ${size} with no colour — keep one.`,
      )
    } else {
      cells.add(key)
    }
  }

  return { errors, notes }
}

/* ── The add-a-size sheet ─────────────────────────────────────────────────────

  The app adds stock in a sheet rather than a grid: pick a sizing system, tap the
  sizes you make, then give each one its colours and its count. Everything from
  here down is that flow's arithmetic, and it is in this module rather than in
  `VariantDialog` for the same reason the rest of it is — the dialog is a form,
  and what the form means is a rule.

  The two shapes differ in one way that matters. The grid edits a cell; the sheet
  edits a **size**, so applying it **replaces that size's rows** with the entries
  the seller gave it. That is the only reading of the sheet that lets a seller say
  "EU 42 comes in Black, and I no longer stock it in Brown" — and it is why the
  dialog says how many variants it is about to write.
*/

/**
 * The entries a picked size starts with — for **one colour**.
 *
 * A size this colour already stocks opens with its row, so the sheet is the app's
 * *Edit Variant* as well as its *Add Variant*: re-picking a size and saving it
 * writes back exactly what was there. A size it does not have opens with one empty
 * entry, which is what "no count yet" looks like.
 *
 * Stock is a **string**, because that is what a text box holds: `''` for a size
 * nobody has counted, `'0'` for a row that genuinely is sold out. The two are
 * different things — the first is a count nobody has made, the second is stock
 * that is gone — and one of them must not be written over the other.
 */
export function sheetEntriesForColour(variants, colour, size) {
  const row = findVariant(variants, normaliseSize(size), colour)
  if (!row) return [blankSheetEntry()]

  const price = Number(row?.additional_price) || 0
  return [
    {
      // An empty box rather than a `0`: most variants charge nothing extra, and
      // zeroes are typing to do.
      stock: String(Math.max(0, Math.trunc(Number(row?.stock) || 0))),
      additional_price: price > 0 ? String(price) : '',
      sku: String(row?.sku ?? '').trim(),
    },
  ]
}

/** One entry with nothing in it — a size nobody has counted yet. */
export function blankSheetEntry() {
  return { stock: '', additional_price: '', sku: '' }
}

/**
 * The sheet's state → the variant rows it would write.
 *
 * `sizes` are stored size labels (`'EU 40'`) and `entries` is keyed by them, one
 * list per size — the shape `newSizeEntries` starts and the dialog edits. A size
 * with no entries at all writes one colourless row at zero, which is the same
 * thing the grid does with a size nobody has counted yet.
 */
export function sheetRows(sheet) {
  /*
    The colour belongs to the SHEET, not to each entry: the sheet is always opened
    from one colour's card and every row it writes is that colour. That is the
    app's `colorOverride` (see `_showVariantSheetForColor`, which exists so the
    variant sheet does not have to be written twice), and it is why an entry no
    longer has a colour to read.
  */
  const colour = normaliseColour(sheet?.colour)
  const rows = []
  for (const raw of sheet?.sizes ?? []) {
    const size = normaliseSize(raw)
    if (!size) continue
    const entries = sheet?.entries?.[size]
    if (!entries || entries.length === 0) {
      rows.push(draftRow({ size, color: colour, stock: 0 }))
      continue
    }
    for (const entry of entries) {
      rows.push(
        draftRow({
          size,
          color: colour,
          stock: entry?.stock,
          additional_price: entry?.additional_price,
          sku: entry?.sku,
        }),
      )
    }
  }
  return rows
}

/**
 * What stops the sheet from being applied at all.
 *
 * Only two things, and both are shapes the product could not express: no sizes
 * picked, and one size given the same colour twice. The second is refused here so
 * the seller is told while the dialog is open, in the dialog's own words, instead
 * of at Save — `variantProblems` refuses the same state, because it can also
 * arrive from the database. Colours and counts are otherwise free: a colourless
 * entry is the common single-colour product, and zero stock is a size that exists
 * and is sold out, which is not an error anywhere else either.
 */
export function sheetProblems(sheet) {
  const errors = []
  const scope = normaliseColour(sheet?.colour)
  const sizes = (sheet?.sizes ?? []).map(normaliseSize).filter(Boolean)
  if (sizes.length === 0) errors.push('Pick at least one size first.')

  for (const size of sizes) {
    const seen = new Set()
    for (const entry of sheet?.entries?.[size] ?? []) {
      // An entry has no colour of its own — the sheet's is every row's — so this
      // is really "one row per (size, colour)", which is the shape everything
      // downstream assumes.
      const name = entry?.color === undefined ? scope : normaliseColour(entry.color)
      const key = name ?? ''
      if (seen.has(key)) {
        errors.push(
          name
            ? `You have two ${name} rows for ${size} — keep one.`
            : `You have two rows with no colour for ${size} — keep one.`,
        )
      } else {
        seen.add(key)
      }
    }
  }

  return { errors }
}

/**
 * The sheet, applied: **one colour's** rows, for the sizes it picked.
 *
 * Scoped to the sheet's colour, and that is the whole subtlety. Applying removes
 * the existing rows for the picked sizes *in this colour* and writes the new ones;
 * rows for those same sizes in other colours are left exactly as they are, because
 * the seller was editing one colour's sizes and not the product's. Getting this
 * wrong is silent and expensive — an unscoped replace deletes the Black rows for
 * EU 42 the moment somebody adds a size to Tan — which is why the sheet carries
 * its colour and this function insists on reading it.
 *
 * The colour list is deliberately not returned. A colour can exist with **no sizes
 * at all** (the app's card says "0 sizes" and `variantProblems` only notes it), so
 * the list belongs to the cards rather than to the rows.
 */
export function applyVariantSheet(variants, sheet) {
  const rows = sheetRows(sheet)
  const scope = normaliseColour(sheet?.colour)
  const touched = new Set(rows.map((row) => row.size))
  /*
    The picked sizes are replaced **in this colour only**. Rows for those sizes in
    other colours, and this colour's rows for the sizes the sheet never mentioned,
    all survive — which is the difference between "EU 42 in Tan is now 9" and
    "EU 42 is now Tan", and the difference between an edit and a deletion.
  */
  const kept = (variants ?? []).filter(
    (variant) => !(touched.has(sizeOf(variant)) && colourOf(variant) === scope),
  )
  return variantsFromProduct([...kept, ...rows], colourOrderWith(variants, scope))
}

/**
 * One colour's rows, swapped for the whole set that colour's sheet returned.
 *
 * The other scoped merge, and deliberately not `applyVariantSheet`: the colour
 * sheet collects a colour's rows from the size sheet and hands back the **entire**
 * set for that colour, so anything not in it really is gone — a size dropped from
 * the colour. The size sheet's merge is per size, this one is per colour.
 */
export function replaceColourRows(variants, colour, rows) {
  const wanted = normaliseColour(colour)
  const kept = (variants ?? []).filter((variant) => colourOf(variant) !== wanted)
  return variantsFromProduct([...kept, ...(rows ?? [])], colourOrderWith(variants, wanted))
}

/**
 * The colour columns as they are, with `colour` appended if it is new to them.
 *
 * Read from the variants **before** a merge and passed into `variantsFromProduct`,
 * so replacing one colour cannot reorder the others — a seller's second colour
 * stays second after an edit nobody made to it. A colour that is not in the order
 * yet (the one being added) is appended rather than sorting in front of all of
 * them, because `indexOf` would have said `-1`.
 */
function colourOrderWith(variants, colour) {
  const before = variantColumns(variants ?? [], coloursFromVariants(variants ?? []))
  return before.includes(colour) ? before : [...before, colour]
}

/**
 * What the sheet is about to do, for the button that does it.
 *
 * Counted from the rows rather than from the sizes, because the number on the
 * button is the number of variants — `3 sizes × 2 colours` is six rows, and a
 * button saying "Add 3 variants" would be wrong about the thing it is writing.
 * `updating` is true as soon as one of the picked sizes is already on the
 * product, which is what swaps the verb: a sheet that only ever said "Add" would
 * be describing a replace as an insert.
 */
export function sheetPreview(variants, sheet) {
  const rows = sheetRows(sheet)
  const scope = normaliseColour(sheet?.colour)
  return {
    count: rows.length,
    // For this colour: a size another colour stocks is a size this colour is
    // adding, and a button that said "Update" for it would be describing the
    // wrong kind of write.
    updating: rows.some((row) => Boolean(findVariant(variants, row.size, scope))),
  }
}

/** The sheet's save button, in the app's own words (`Add 3 Variants`). */
export function sheetSaveLabel(count, updating = false) {
  if (count <= 1) return updating ? 'Update variant' : 'Add variant'
  return updating ? `Update ${count} variants` : `Add ${count} variants`
}
