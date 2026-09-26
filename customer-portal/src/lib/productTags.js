/**
 * Product tags — a 1:1 port of `lib/widgets/seller/tag_selector.dart`, which is
 * the single place both the Flutter product form and its store forms take their
 * tag vocabulary from.
 *
 * ## The stored form, and why it is not the label
 *
 * `products.tags` is a `TEXT[]`. Three kinds of value live in it:
 *
 *  - a **preset id** — a snake_case string unique across every group
 *    (`handmade`, `eco_friendly`), so it never needs a group prefix;
 *  - a **custom entry** — `custom:<group>:<text>`, where the fixed prefix is what
 *    distinguishes it from a preset id and the group is what lets edit mode put
 *    the chip back in the section it was typed in;
 *  - **anything else** — free text saved before the grouped selector existed. The
 *    app keeps these and renders them raw in a "Custom tags" bucket rather than
 *    dropping a tag that is on a live product.
 *
 * The value stored is an *id*, never the label, because the label is the part
 * that changes: renaming "Made-to-order" must not orphan every product carrying
 * it. This module is the only place those two are related.
 *
 * ## Why a port rather than a shorter list of strings
 *
 * The storefront's search reads `products.tags` directly (`searchRules.js`), so a
 * tag invented on the web is a tag a customer can find — and a divergent
 * vocabulary would mean the same shoe is "eco-friendly" from the phone and
 * "sustainable" from the browser, with search matching only one spelling. The
 * groups, the ids and the `custom:` encoding are copied exactly, including the
 * validation messages, so a tag typed on either surface is byte-identical.
 *
 * ## What save does to the order
 *
 * `serializeTags` normalises: group by group in display order, presets before
 * customs within a group, then the "other" bucket last. So the array written back
 * is not necessarily the array that was read — it is the same *set*, in the order
 * the form draws it. That is the app's behaviour too, and it is what keeps the
 * stored order from drifting every time a chip is tapped.
 */

/**
 * One selectable preset. `id` is the stored value; `label` is what a seller
 * reads. Kept as flat objects rather than a Map so the vocabulary is inspectable
 * in a test without a helper.
 */
export const PRODUCT_TAG_GROUPS = [
  {
    id: 'type',
    label: 'Product type',
    presets: [
      { id: 'handmade', label: 'Handmade' },
      { id: 'made_to_order', label: 'Made-to-order' },
      { id: 'ready_to_wear', label: 'Ready-to-wear' },
      { id: 'limited_edition', label: 'Limited edition' },
    ],
  },
  {
    id: 'material',
    label: 'Material',
    presets: [
      { id: 'leather', label: 'Leather' },
      { id: 'canvas', label: 'Canvas' },
      { id: 'rubber', label: 'Rubber' },
      { id: 'suede', label: 'Suede' },
    ],
  },
  {
    id: 'sustainability',
    label: 'Sustainability',
    presets: [
      { id: 'eco_friendly', label: 'Eco-friendly' },
      { id: 'upcycled_materials', label: 'Upcycled materials' },
      { id: 'recycled_packaging', label: 'Recycled packaging' },
    ],
  },
]

/** The neutral bucket free text from before the grouped selector lands in. */
export const OTHER_TAG_GROUP = { id: 'other', label: 'Custom tags', presets: [] }

/** Every group a stored tag may belong to, the catch-all included. */
export const ALL_TAG_GROUPS = [...PRODUCT_TAG_GROUPS, OTHER_TAG_GROUP]

/** The app's own limit on a hand-typed tag. */
export const MAX_CUSTOM_TAG_LENGTH = 30

/** The stored form of a custom entry: `custom:<group>:<text>`. */
export function customTagValue(groupId, text) {
  return `custom:${groupId}:${String(text ?? '').trim()}`
}

/**
 * One stored tag → an entry `{ group, value, custom }`.
 *
 * Three cases, in the app's order of precedence:
 *
 *  1. a known preset id (**case-insensitive**, the only forgiving comparison
 *     here) → that preset, canonicalised to its own spelling, in its group;
 *  2. `custom:<group>:<text>` with a known group and a non-empty text → that
 *     custom, in that group;
 *  3. anything else → free text in the `other` bucket.
 *
 * A malformed custom entry (`custom:type:`, `custom:material:`) returns an empty
 * value, which `parseTags` then drops — rendering the literal `custom:type:`
 * prefix as a chip is the failure this avoids.
 */
export function parseStoredTag(raw) {
  const text = String(raw ?? '').trim()
  const lower = text.toLowerCase()

  for (const group of PRODUCT_TAG_GROUPS) {
    for (const preset of group.presets) {
      if (preset.id.toLowerCase() === lower) {
        return { group: group.id, value: preset.id, custom: false }
      }
    }
  }

  if (lower.startsWith('custom:')) {
    const parts = text.split(':')
    if (parts.length >= 3) {
      const group = parts[1].toLowerCase()
      const value = parts.slice(2).join(':').trim()
      const knownGroup =
        PRODUCT_TAG_GROUPS.some((entry) => entry.id === group) ||
        group === OTHER_TAG_GROUP.id
      if (knownGroup && value) {
        return { group, value, custom: true }
      }
    }
    return { group: OTHER_TAG_GROUP.id, value: '', custom: true }
  }

  return { group: OTHER_TAG_GROUP.id, value: text, custom: true }
}

/** Every stored tag as an entry, with the empty ones (malformed customs) gone. */
export function parseTags(raw) {
  const entries = []
  for (const tag of Array.isArray(raw) ? raw : []) {
    const entry = parseStoredTag(tag)
    if (entry.value) entries.push(entry)
  }
  return entries
}

/** The entries in one group, in the order they were added. */
export function groupEntries(entries, groupId) {
  return (entries ?? []).filter((entry) => entry.group === groupId)
}

/**
 * The entries → the array written to `products.tags`.
 *
 * Presets first within each group, then that group's customs, groups in display
 * order and the `other` bucket last.
 */
export function serializeTags(entries, groups = ALL_TAG_GROUPS) {
  const stored = []
  for (const group of groups) {
    const inGroup = groupEntries(entries, group.id)
    for (const entry of inGroup) {
      if (!entry.custom) stored.push(entry.value)
    }
    for (const entry of inGroup) {
      if (entry.custom) stored.push(customTagValue(entry.group, entry.value))
    }
  }
  return stored
}

/** Is this preset already selected? */
export function hasPreset(entries, groupId, presetId) {
  return (entries ?? []).some(
    (entry) => !entry.custom && entry.group === groupId && entry.value === presetId,
  )
}

/** Add or remove one preset. Returns a new array; the input is not mutated. */
export function togglePreset(entries, groupId, presetId) {
  const current = entries ?? []
  if (hasPreset(current, groupId, presetId)) {
    return current.filter(
      (entry) =>
        !(!entry.custom && entry.group === groupId && entry.value === presetId),
    )
  }
  return [...current, { group: groupId, value: presetId, custom: false }]
}

/** Remove a custom entry by its text. */
export function removeCustomTag(entries, groupId, value) {
  return (entries ?? []).filter(
    (entry) =>
      !(entry.custom && entry.group === groupId && entry.value === value),
  )
}

/**
 * Add a hand-typed tag, or explain why it cannot be.
 *
 * Returns `{ entries, error }` rather than throwing, because every one of these
 * refusals is a sentence the form shows under the input — and returning the
 * unchanged entries keeps the caller from having to decide what to render on
 * failure.
 *
 * The three refusals are the app's own, messages included. Note which way round
 * the preset check runs: typing "Handmade" into Material is refused because it is
 * a preset *somewhere*, not because it is one in this group, and neither is
 * checked against the group the text was typed in. A tag that exists as a chip
 * anywhere is the one case where a custom entry would be a duplicate the grouped
 * selector cannot draw.
 *
 * ## The portal's one addition: labels count as preset spellings
 *
 * The Dart selector compares the typed text against each preset's **id**
 * (`'eco_friendly'`), so typing the *label* the chip is showing — "Eco-friendly"
 * — slips past it and is stored as `custom:material:Eco-friendly`. The result is
 * two chips reading "Eco-friendly", one of them selected, and the custom one is
 * not the preset: if a surface ever filters by preset id, that product is not in
 * the result. Comparing the label too is stricter than the app and never weaker,
 * and the refusal is a sentence telling the seller exactly which chip to tap — so
 * the only products it can affect are ones whose tags were typed here, on a form
 * that then saves the canonical id instead.
 *
 * This is checked at *entry* time only. A tag already stored in the legacy
 * spelling is parsed and written back untouched, so a product created in the app
 * is never trapped by it.
 */
export function addCustomTag(entries, groupId, text) {
  const current = entries ?? []
  const value = String(text ?? '').trim()

  if (!value) return { entries: current, error: 'Type a tag first.' }
  if (value.length > MAX_CUSTOM_TAG_LENGTH) {
    return {
      entries: current,
      error: `Keep it under ${MAX_CUSTOM_TAG_LENGTH} characters.`,
    }
  }

  const lower = value.toLowerCase()
  for (const group of PRODUCT_TAG_GROUPS) {
    const isPreset = group.presets.some(
      (preset) =>
        preset.id.toLowerCase() === lower ||
        preset.label.toLowerCase() === lower,
    )
    if (isPreset) {
      return {
        entries: current,
        error: 'That is already a preset option — tap it above instead.',
      }
    }
  }

  if (
    groupEntries(current, groupId).some(
      (entry) => entry.custom && entry.value.toLowerCase() === lower,
    )
  ) {
    return { entries: current, error: 'That tag is already added.' }
  }

  return {
    entries: [...current, { group: groupId, value, custom: true }],
    error: null,
  }
}
