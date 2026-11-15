// Per-colour 3D paint — the prefill half (see the mission in the app repo:
// one model per product, painted by the app; `product_color_paint`).
//
// `guessPaintHex` is a port of the app's `variantSwatchColor`
// (`lib/utils/variant_swatch_color.dart`) — keyword buckets plus a
// deterministic fallback for unknown names. PREFILL ONLY: the guess fills
// the picker so the admin adjusts rather than starting from white. The
// stored value is always a hex a human confirmed, because the fallback is a
// hash pick, not a colour anyone chose — auto-storing it would paint shoes
// a colour that exists nowhere in reality.
//
// `distinctColorNames` unions the product's two colour spellings (variant
// rows and colour-photo rows) into the list the paint section renders, so a
// colour with photos but no variant row (and vice versa) still gets a
// picker.

const FALLBACKS = ['#8B5A2B', '#6B4A2F', '#A9703C', '#4E342E', '#7C5A38', '#B8860B']

function hashPick(name) {
  let h = 0
  for (let i = 0; i < name.length; i++) {
    h = (h * 31 + name.charCodeAt(i)) | 0
  }
  return FALLBACKS[Math.abs(h) % FALLBACKS.length]
}

/** The picker's starting value for a colour name — a guess, never the truth. */
export function guessPaintHex(name) {
  const n = (name ?? '').toLowerCase()
  if (
    n.includes('brown') ||
    n.includes('tan') ||
    n.includes('camel') ||
    n.includes('cognac') ||
    n.includes('clay') ||
    n.includes('leather')
  ) {
    if (n.includes('dark')) return '#4E342E'
    if (n.includes('light')) return '#A1887F'
    return '#8B5A2B'
  }
  if (n.includes('black') || n.includes('charcoal')) return '#26221E'
  if (n.includes('carob')) return '#3E2723'
  if (
    n.includes('white') ||
    n.includes('cream') ||
    n.includes('beige') ||
    n.includes('off-white') ||
    n.includes('suede')
  ) {
    return '#F1E8DC'
  }
  if (n.includes('gold') || n.includes('mustard') || n.includes('yellow')) {
    return '#B8860B'
  }
  if (n.includes('red') || n.includes('burgundy') || n.includes('maroon')) {
    return '#9B3B2E'
  }
  if (n.includes('green') || n.includes('olive')) return '#5D6B45'
  if (n.includes('blue') || n.includes('navy')) return '#3F4A63'
  if (n.includes('grey') || n.includes('gray')) return '#9E948A'
  return hashPick(n)
}

/** True when the value is storable — the database CHECK, mirrored. */
export function isPaintHex(value) {
  return /^#[0-9A-Fa-f]{6}$/.test((value ?? '').trim())
}

/** `#RRGGBB` → `[r, g, b]` 0..1 factors for a live 3D tint, or null when the
 *  value is not a paint. Case-insensitive — the factors are identical either
 *  way, so the database's lowercase-only CHECK and the repo's mixed-case
 *  guesses converge here instead of disagreeing. */
export function paintFactors(hex) {
  const match = /^#([0-9A-Fa-f]{6})$/.exec((hex ?? '').trim())
  if (!match) return null
  const digits = match[1]
  return [0, 2, 4].map((i) => parseInt(digits.substring(i, i + 2), 16) / 255)
}

/** The row the section upserts — one paint per colour.
 *
 * The hex is lowercased at this boundary, not merely trimmed: the live
 * `product_color_paint_hex_format` CHECK enforces lowercase (`#3f4a63` in,
 * `#3F4A63` refused), while the colour is identical either way and every
 * viewer parses hex case-insensitively. Normalising here satisfies the
 * strictest reading of the constraint no matter which draft built the table. */
export function paintRow(productId, colorName, paintHex) {
  return {
    product_id: productId,
    color_name: (colorName ?? '').trim(),
    paint_hex: (paintHex ?? '').trim().toLowerCase(),
  }
}

/** Sorted unique colour names out of variant + colour-photo rows. */
export function distinctColorNames({ variants = [], colorImages = [] } = {}) {
  const names = new Set()
  for (const v of variants ?? []) {
    const name = v?.color?.toString().trim()
    if (name) names.add(name)
  }
  for (const img of colorImages ?? []) {
    const name = img?.color_name?.toString().trim()
    if (name) names.add(name)
  }
  return [...names].sort((a, b) => a.localeCompare(b))
}
