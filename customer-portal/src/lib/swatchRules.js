/**
 * A variant colour's **name** → the colour of the dot that stands in for it.
 *
 * A port of the app's `lib/utils/variant_swatch_color.dart`, which is shared there
 * for the same reason this is a module here: the seller's sheet and the
 * storefront's colour picker have to draw "Brown" the same way, and one mapping is
 * what makes the dot beside a name mean something rather than be decoration. The
 * names are free text written by sellers — `Dark Brown`, `Off-white suede`,
 * `Carob` — so this is a *guess* at what a word looks like, matched on substrings,
 * and it is deliberately the app's guess rather than a better one: a swatch that
 * disagreed with the phone would be two answers to "what colour is Tan?".
 *
 * ## Order is the rule
 *
 * `brown` is checked before `black`, and everything is checked before the
 * fallback, which looks arbitrary and is not: the checks are `contains`, so the
 * order *is* the precedence — and it decides three cases that are easy to get
 * wrong.
 *
 *  * **`Dark Brown` is dark.** The brown branch runs first and has its own
 *    `dark`/`light` cases, so a name that says *dark* gets a different, darker
 *    tone than plain `Brown` — it never reaches a later branch.
 *  * **`Tan suede` is a brown, not an off-white.** The colour word comes first in
 *    the name, and the branch order agrees with the reading.
 *  * **`Carob` is the exception the order creates.** Carob is looked for *after*
 *    the brown branch, so the bare preset is its own dark brown
 *    (`#3e2723`) while `Carob Brown` settles as plain brown. That is the app's
 *    behaviour, kept rather than corrected — the point of this file is that the
 *    dot matches the phone's, including where the phone's rule is odd.
 *
 * The light family is one bucket and not three: `White`, `Cream`, `Beige`,
 * `Off-white` and `Suede` all draw `#f1e8dc`, because they are all the same pair.
 * A picker where Cream and White were two tones would be claiming a difference
 * the product does not have.
 *
 * ## The fallback is deterministic, and it is not the app's
 *
 * An unknown name gets a warm tone keyed off the name, "so the same colour never
 * changes between rebuilds and two different colours rarely collide" — the app's
 * own words. Its arithmetic is Dart's `String.hashCode`, which JS cannot
 * reproduce (it is not a documented algorithm and differs per Dart release), so
 * the hash here is FNV-1a over the code points. That is a **divergence**: an
 * unknown name can be one palette entry away from the phone's dot. It is accepted
 * because the property that matters is the one being kept — stable across
 * renders, roughly spread — and because the alternative is a swatch that changes
 * colour when the file is rebuilt. Every *known* name, which is all eleven presets
 * and the words the app's own branches name, matches the app exactly.
 */

/** What `AppConstants.primary` is — the app's own neutral for a plain `brown`. */
export const SWATCH_BROWN = '#8b5a2b'

/**
 * The warm palette an unrecognised name hashes into. Verbatim from the app, in
 * its order: the order is part of the answer, since the index is a modulo.
 */
export const SWATCH_FALLBACKS = [
  '#8b5a2b',
  '#6b4a2f',
  '#a9703c',
  '#4e342e',
  '#7c5a38',
  '#b8860b',
]

/**
 * FNV-1a over a string's code points — a small, stable, well-known hash.
 *
 * Not `charCodeAt` per UTF-16 unit, because two names that differ only above the
 * BMP should not collide by construction; and not `hashCode`-style multiplication,
 * because the point is that this file's answer never changes.
 */
function fnv1a(text) {
  let hash = 0x811c9dc5
  for (const character of text) {
    hash ^= character.codePointAt(0)
    // `Math.imul` keeps the multiply in 32 bits, which is what makes this hash
    // reproducible rather than a float that loses its low digits.
    hash = Math.imul(hash, 0x01000193)
  }
  return hash >>> 0
}

/**
 * The colour for a variant colour's name, as a `#rrggbb` the caller can put in a
 * `style`. Never throws and never returns nothing: a blank name gets a swatch
 * like any other, because a dot is cheaper than a conditional at every call site.
 */
export function swatchColour(name) {
  const n = String(name ?? '').toLowerCase()

  /*
    The brown family, checked with its own two brightness cases, before anything
    else. `dark` wins over `light`, which is the app's order: a name that somehow
    contains both is a dark one, and silently preferring `light` there would make
    the branch's answer depend on the order of the two `if`s alone.
  */
  if (
    n.includes('brown') ||
    n.includes('tan') ||
    n.includes('camel') ||
    n.includes('cognac') ||
    n.includes('clay') ||
    n.includes('leather')
  ) {
    if (n.includes('dark')) return '#4e342e'
    if (n.includes('light')) return '#a1887f'
    return SWATCH_BROWN
  }

  if (n.includes('black') || n.includes('charcoal')) return '#26221e'
  if (n.includes('carob')) return '#3e2723'

  /*
    `suede` is in here on purpose — the app's product names use it for the
    off-white one. It is checked *after* the brown branch, so `Tan suede` reads
    brown and a bare `Suede` reads off-white; that is the app's order, and it is
    the right way round, because a seller who writes a colour word first means the
    colour word first.
  */
  if (
    n.includes('white') ||
    n.includes('cream') ||
    n.includes('beige') ||
    n.includes('off-white') ||
    n.includes('suede')
  ) {
    return '#f1e8dc'
  }

  if (n.includes('gold') || n.includes('mustard') || n.includes('yellow')) {
    return '#b8860b'
  }
  if (n.includes('red') || n.includes('burgundy') || n.includes('maroon')) {
    return '#9b3b2e'
  }
  if (n.includes('green') || n.includes('olive')) return '#5d6b45'
  if (n.includes('blue') || n.includes('navy')) return '#3f4a63'
  if (n.includes('grey') || n.includes('gray')) return '#9e948a'

  return SWATCH_FALLBACKS[fnv1a(n || ' ') % SWATCH_FALLBACKS.length]
}
