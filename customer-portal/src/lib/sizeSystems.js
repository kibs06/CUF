import { formatSize, sizeNumber, compareSizes } from './sizeKeyRules.js'

/**
 * The sizing systems a seller can stock, and their size lists — a port of
 * `AddEditProductScreen._sizingSystems`.
 *
 * The lists are copied verbatim, halves included, because they are a
 * *vocabulary* rather than a range: `EU` runs 35–47 by halves and skips 46.5,
 * `US` stops at 11.5 then jumps 12, 13, 14, 15, and `UK` has no 11.5. Generating
 * them from a step would produce sizes the app's own form cannot offer, and a
 * seller who stocks a size the phone cannot edit has created a row they can only
 * fix from the web.
 *
 * A stored size keeps the app's own form: `'{SYSTEM} {VALUE}'` (`'EU 40'`). The
 * database matches sizes digits-only (`regexp_replace(size, '\D', '', 'g')`), so
 * the prefix costs nothing at query time and is the only thing that makes `40`
 * mean EU 40 rather than US 40 on a screen. See `sizeKeyRules.js`.
 */
export const SIZING_SYSTEMS = {
  US: [
    '3', '3.5', '4', '4.5', '5', '5.5', '6', '6.5',
    '7', '7.5', '8', '8.5', '9', '9.5', '10', '10.5',
    '11', '11.5', '12', '13', '14', '15',
  ],
  EU: [
    '35', '35.5', '36', '36.5', '37', '37.5', '38', '38.5',
    '39', '39.5', '40', '40.5', '41', '41.5', '42', '42.5',
    '43', '43.5', '44', '44.5', '45', '45.5', '46', '47',
  ],
  UK: [
    '2', '2.5', '3', '3.5', '4', '4.5', '5', '5.5',
    '6', '6.5', '7', '7.5', '8', '8.5', '9', '9.5',
    '10', '10.5', '11', '12', '13', '14', '15',
  ],
}

/** The system names, in the order the form offers them. */
export const SIZING_SYSTEM_NAMES = Object.keys(SIZING_SYSTEMS)

/** Stable keys for React lists — `'EU 40'` is already unique within a product. */
export function sizeValue(system, value) {
  return `${system} ${value}`
}

/**
 * Which system a stored size belongs to, or `'Other'`.
 *
 * `'Other'` is a real answer, not a failure: the catalog holds sizes whose
 * prefix is a system this form does not offer (`'JP 25'`), and re-labelling one
 * as US or EU would silently change which size a customer is buying. The editor
 * keeps them in a free-text group instead.
 */
export function sizingSystemOf(raw) {
  const text = String(raw ?? '').trim()
  if (!text) return 'Other'

  for (const system of SIZING_SYSTEM_NAMES) {
    if (text.toUpperCase().startsWith(`${system} `)) return system
  }
  return 'Other'
}

/** The numeric value behind a stored size, with its prefix removed. */
export function sizingValueOf(raw) {
  const text = String(raw ?? '').trim()
  const system = sizingSystemOf(text)
  if (system === 'Other') return text
  return text.slice(system.length).trim()
}

/**
 * Group a product's stored sizes by system, each group sorted numerically.
 *
 * Sorted rather than left in whatever order the rows came back in, which is the
 * same fix the storefront's size grid needed: `inventory` returns sizes in
 * insertion order, so an unsorted editor shows `40, 41, 39, 38, 42`. Sorting
 * with `compareSizes` keeps halves in the right place, where a plain string sort
 * puts `'9.5'` before `'10'` and after `'10.5'`.
 */
export function groupSizes(storedSizes) {
  const groups = new Map()
  for (const raw of storedSizes ?? []) {
    const size = String(raw ?? '').trim()
    if (!size) continue
    const system = sizingSystemOf(size)
    if (!groups.has(system)) groups.set(system, [])
    groups.get(system).push(size)
  }

  const ordered = []
  for (const system of [...SIZING_SYSTEM_NAMES, 'Other']) {
    const sizes = groups.get(system)
    if (!sizes || sizes.length === 0) continue
    ordered.push({ system, sizes: [...sizes].sort(compareSizes) })
  }
  return ordered
}

/**
 * Total pairs across a product's size rows — the summary a list row shows.
 *
 * `formatSize` is used for the label so the `EU ` prefix has one owner in this
 * codebase, exactly as the storefront's size badge and Settings row do.
 */
export function stockSummary(inventory) {
  const rows = Array.isArray(inventory) ? inventory : []
  const total = rows.reduce((sum, row) => sum + (Number(row?.stock) || 0), 0)
  return {
    total,
    sizes: rows.length,
    label: rows.length > 0 ? `${rows.length} sizes · ${total} pairs` : 'No sizes',
  }
}

/**
 * What a stock row should say about itself — the same three states the app's
 * `SellerInventoryRow` draws, from the same threshold:
 *
 *   zero        → 'out'   (urgent: unsellable)
 *   1..5        → 'low'
 *   6 and above → 'in'
 *
 * Zero is not "low" here either, for the reason `lowStockRows` gives: it is a
 * different job with a different fix.
 */
export function stockState(stock, threshold = 5) {
  const value = Number(stock) || 0
  if (value <= 0) return 'out'
  if (value <= threshold) return 'low'
  return 'in'
}

/**
 * A product's stock, as chips: one per size, in size order, with the colours
 * already decided.
 *
 * This is what lets the product list answer its own question — *how many of each
 * size have I got left?* — at a glance instead of in a sentence. The old tile
 * said "3 sizes · 8 pairs", which is a total, and a total is exactly the number
 * that hides the problem: eight pairs across three sizes reads as healthy until
 * you notice they are all in size 39.
 *
 * Three decisions:
 *
 *  1. **Sizes come from `groupSizes`**, so they are numerically sorted and the
 *     halves stay in the right place (`9.5` before `10`, which a string sort gets
 *     backwards) — the same order the editor and the storefront's size grid use.
 *  2. **The colour is `stockState`'s**, the same three states and the same
 *     threshold the dashboard's "Running out" figure counts. A chip that said
 *     "low" at 6 here and at 5 on the dashboard would be two answers to one
 *     question.
 *  3. **`limit` caps the TOTAL, not each group.** A product with 22 sizes would
 *     otherwise fill a row with chips nobody reads; the leftovers are counted
 *     and the caller renders them as a `+N` chip.
 *
 * @param {Array<{ size?: string, stock?: number }>} inventory
 * @param {{ limit?: number }} [options]
 * @returns {{
 *   groups: Array<{ system: string, chips: Array<{ size: string, value: string, stock: number, state: 'out'|'low'|'in' }> }>,
 *   total: number,
 *   shown: number,
 *   hidden: number,
 * }}
 */
export function sizeStockChips(inventory, { limit = 10 } = {}) {
  const rows = Array.isArray(inventory) ? inventory : []

  const stockBySize = new Map()
  for (const row of rows) {
    const size = String(row?.size ?? '').trim()
    if (!size) continue
    stockBySize.set(size, Number(row?.stock) || 0)
  }

  const grouped = groupSizes([...stockBySize.keys()])
  let budget = Math.max(0, Number(limit) || 0)

  const groups = []
  for (const group of grouped) {
    const chips = []
    for (const size of group.sizes) {
      if (budget <= 0) break
      const stock = stockBySize.get(size) ?? 0
      chips.push({
        size,
        value: sizingValueOf(size),
        stock,
        state: stockState(stock),
      })
      budget -= 1
    }
    if (chips.length > 0) groups.push({ system: group.system, chips })
  }

  const total = grouped.reduce((sum, group) => sum + group.sizes.length, 0)
  const shown = groups.reduce((sum, group) => sum + group.chips.length, 0)

  return { groups, total, shown, hidden: total - shown }
}

/**
 * A product's stock as an editable draft: one row per size, in size order.
 *
 * The ordering matters more here than it looks. `saveProductVariants` replaces a
 * product's whole size set (`product_variants` and the derived `inventory` are
 * both deleted and re-inserted), so the editor has to send **every** size back,
 * not just the ones that changed — and `inventory` arrives in insertion order,
 * which on a product edited twice is `40, 41, 39, 38, 42`. Editing a sorted
 * list is part of not fat-fingering it.
 */
export function stockDraftFrom(inventory) {
  const stockBySize = new Map()
  for (const row of Array.isArray(inventory) ? inventory : []) {
    const size = String(row?.size ?? '').trim()
    if (!size) continue
    stockBySize.set(size, Math.max(0, Math.trunc(Number(row?.stock) || 0)))
  }

  return groupSizes([...stockBySize.keys()]).flatMap((group) =>
    group.sizes.map((size) => ({ size, stock: stockBySize.get(size) ?? 0 })),
  )
}

/**
 * Has the draft moved away from what is saved?
 *
 * This is what decides whether Save is available, and it compares by size rather
 * than by array order or length: a draft with the same numbers in a different
 * order is not a change, and a button that enabled itself for one would train a
 * seller to ignore it. Sizes added or removed count, because the write replaces
 * the set.
 */
export function isStockDraftDirty(draft, inventory) {
  const before = new Map(
    stockDraftFrom(inventory).map((row) => [row.size, row.stock]),
  )
  const after = new Map(
    stockDraftFrom(draft).map((row) => [row.size, row.stock]),
  )

  if (before.size !== after.size) return true
  for (const [size, stock] of before) {
    if (after.get(size) !== stock) return true
  }
  return false
}

/** `{ sizes, pairs }` — the line under an editor, and the row's own summary. */
export function stockDraftTotals(draft) {
  const rows = Array.isArray(draft) ? draft : []
  const pairs = rows.reduce(
    (sum, row) => sum + Math.max(0, Math.trunc(Number(row?.stock) || 0)),
    0,
  )
  return { sizes: rows.length, pairs }
}

export { formatSize, sizeNumber }
