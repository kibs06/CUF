// ─── The AI blob's rules, kept out of the shader and out of the canvas ──
//
// The component in `components/ai/AiFluidBlob.jsx` is a WebGL surface: a canvas,
// a program, and a render loop. Everything that can be *decided* rather than
// drawn lives here instead, so it can be tested without a GL context — which is
// the whole reason this file exists. A prop that silently produced a black
// canvas would otherwise be invisible to `npm test`.
//
// The public API is the one the original component documents: `size`, `colors`,
// `count`, `variant`, `glass`. The defaults below are part of that contract and
// must not drift, because they are also what the page's snippet prints.
//
// ⚠️ **This is an in-repo implementation of the documented API, not a copy of
// the Lightswind Pro component.** That source is not redistributable (its docs
// ship `// 🔒 Upgrade to Lightswind Pro to unlock full source code & CLI access`),
// so the drawing is written from the description — multi-strand chromatic
// liquid-wave strands under a glass refraction lens — in hand-written WebGL
// instead of `ogl`. The props table on the page is unchanged; the pixels are
// ours, and the page says so.

/** The five AI voice-assistant states, in the order the page shows them. */
export const BLOB_VARIANTS = ['listening', 'thinking', 'speaking', 'orbit', 'pulse']

/** The documented default palette. */
export const DEFAULT_BLOB_COLORS = ['#10B981', '#06B6D4', '#3B82F6', '#6366F1']

/** ⚠️ The shader's uniform array width, and therefore the hard ceiling on both
 *  `count` and the palette. Raising it means changing the GLSL too. */
export const MAX_STRANDS = 12

export const BLOB_DEFAULTS = {
  size: 260,
  count: 4,
  variant: 'listening',
  glass: true,
}

/** The drawn size is clamped rather than trusted: a `size` of 0 is an invisible
 *  component and a `size` of 40000 is a melted GPU. */
export const BLOB_SIZE_LIMITS = { min: 96, max: 1024 }

/**
 * Curated palettes for the page's picker.
 *
 * Kept beside the defaults rather than typed into the page so `npm test` can
 * prove every preset survives `normalizeColors`: a mistyped hex would otherwise
 * be dropped silently and the swatch would lie about what it does.
 */
export const BLOB_PRESETS = [
  { name: 'Emerald', colors: DEFAULT_BLOB_COLORS },
  { name: 'Ember', colors: ['#F59E0B', '#EF4444', '#EC4899', '#8B5CF6'] },
  { name: 'Ice', colors: ['#E0F2FE', '#7DD3FC', '#38BDF8', '#0284C7'] },
  { name: 'Orchid', colors: ['#A78BFA', '#E879F9', '#F472B6', '#FB7185'] },
  // The portal's own brand four, so the surface can be tried against the palette
  // it will actually sit in rather than against a nicer one.
  { name: 'SoleVision', colors: ['#8B5A2B', '#C4A882', '#4ECDC4', '#3B2314'] },
]

// ─── Props ─────────────────────────────────────────────────────────

/**
 * One hex colour as linear-ish 0..1 floats, or `null` if it is not one.
 *
 * Accepts `#abc`, `#aabbcc`, and the same without the `#`, because a palette
 * pasted out of a design tool arrives in all three shapes. No alpha: the strands
 * are added together as light, so a fourth channel would be a colour decision
 * made in the wrong place.
 */
export function parseHexColor(value) {
  const raw = String(value ?? '')
    .trim()
    .replace(/^#/, '')

  const expanded =
    raw.length === 3
      ? raw
          .split('')
          .map((c) => c + c)
          .join('')
      : raw

  if (!/^[0-9a-fA-F]{6}$/.test(expanded)) return null

  return [0, 2, 4].map((i) => parseInt(expanded.slice(i, i + 2), 16) / 255)
}

/** A palette as hex strings: invalid entries dropped, capped to the shader's
 *  width, defaults on empty. */
export function normalizeColors(colors) {
  const list = Array.isArray(colors) ? colors : []
  const kept = list.map((c) => parseHexColor(c)).filter(Boolean)

  // ⚠️ Invalid *entries* are dropped, but an empty or entirely invalid palette
  // falls back to the documented default rather than to a black canvas — the one
  // outcome a caller cannot debug from a screenshot.
  const source = kept.length > 0 ? kept : DEFAULT_BLOB_COLORS.map((c) => parseHexColor(c))
  const capped = source.slice(0, MAX_STRANDS)

  return capped.map(([r, g, b]) =>
    `#${[r, g, b]
      .map((channel) => Math.round(channel * 255).toString(16).padStart(2, '0'))
      .join('')
      .toUpperCase()}`,
  )
}

/** Pixels: numbers clamp into the band, anything unusable gets the default. */
export function clampBlobSize(value) {
  const size = Number(value)
  if (!Number.isFinite(size)) return BLOB_DEFAULTS.size
  return Math.min(BLOB_SIZE_LIMITS.max, Math.max(BLOB_SIZE_LIMITS.min, Math.round(size)))
}

/** Strands: 1..MAX_STRANDS, because the shader cannot draw a fraction of one. */
export function clampStrandCount(value) {
  const count = Number(value)
  if (!Number.isFinite(count)) return BLOB_DEFAULTS.count
  return Math.min(MAX_STRANDS, Math.max(1, Math.floor(count)))
}

/**
 * Every prop as the component will actually use it.
 *
 * `variant` falls back rather than throwing: this is decoration on a dashboard,
 * and an unknown state name should leave the surface working, not blank.
 * `glass` is on unless it is explicitly `false`, so `glass` (a bare JSX boolean)
 * and `glass={false}` both do what they look like they do.
 */
export function resolveBlobProps({ size, colors, count, variant, glass } = {}) {
  return {
    size: clampBlobSize(size),
    colors: normalizeColors(colors),
    count: clampStrandCount(count),
    variant: BLOB_VARIANTS.includes(variant) ? variant : BLOB_DEFAULTS.variant,
    glass: glass !== false,
  }
}

// ─── Motion ────────────────────────────────────────────────────────

/**
 * What each state looks like, as five numbers the shader reads as uniforms.
 *
 * `energy` brightness and weight of the bands · `spin` how fast they drift and
 * roll · `wobble` how far a band leans off the axis (the lean is what makes
 * neighbouring bands cross) · `pulse` the rate of the vertical breathing ·
 * `spread` how far apart the bands sit.
 *
 * The states are meant to be *readable as states*: `thinking` wanders (the
 * strongest lean, the slowest drift) and gathers its bands in close, `speaking`
 * is agitated and fast, `orbit` is orderly — wide and evenly spaced with almost
 * no lean — and `pulse` breathes. If two of them moved the same way the variant
 * prop would be decoration.
 */
export const VARIANT_MOTION = {
  listening: { energy: 1.0, spin: 0.35, wobble: 0.55, pulse: 0.45, spread: 1.0 },
  thinking: { energy: 0.9, spin: 0.16, wobble: 0.85, pulse: 0.22, spread: 0.55 },
  speaking: { energy: 1.3, spin: 0.7, wobble: 0.7, pulse: 1.6, spread: 1.15 },
  orbit: { energy: 1.05, spin: 0.9, wobble: 0.25, pulse: 0.3, spread: 1.35 },
  pulse: { energy: 1.15, spin: 0.14, wobble: 0.4, pulse: 2.2, spread: 1.0 },
}

/** The five uniforms for one state — never undefined, whatever it is handed. */
export function variantMotion(variant) {
  return VARIANT_MOTION[variant] ?? VARIANT_MOTION[BLOB_DEFAULTS.variant]
}

/**
 * ⚠️ The clock, which is the one input a reduced-motion preference changes.
 *
 * `prefers-reduced-motion` is not "no component" here — the blob is the page, so
 * removing it would leave a blank panel. It is "no *movement*": the field is
 * rendered once at a fixed, composed phase and then left alone. The phase is not
 * zero, because zero is the instant all the sinusoids line up and the strands
 * collapse into a single ring.
 */
export const REDUCED_MOTION_PHASE_SECONDS = 12.5

export function frameTimeSeconds({ elapsedMs, reducedMotion }) {
  if (reducedMotion) return REDUCED_MOTION_PHASE_SECONDS
  const elapsed = Number(elapsedMs)
  return Number.isFinite(elapsed) && elapsed > 0 ? elapsed / 1000 : 0
}

/** Whether the render loop should keep scheduling frames at all. */
export function shouldAnimate({ reducedMotion, visible = true }) {
  return !reducedMotion && visible
}

// ─── The voice orb at the centre ───────────────────────────────────
//
// The sphere's centre is a frosted disc holding three bars, and it is part of the
// component's picture rather than an overlay the page adds: it is what turns a
// field of light into a *voice assistant*. Its sizes and its motion are numbers,
// so they live here with the rest of the numbers.
//
// The shares come from the component as it renders at the documented `size`: an
// orb 0.2625 of the width, holding three bars 0.018 of it wide. Keeping the ratio
// rather than the pixels means a 512px blob gets a proportionally larger orb
// instead of a 84px dot in the middle of it.

export const MIC_BAR_COUNT = 3

/** How tall each bar of the trio is relative to its neighbours. */
export const MIC_BAR_WEIGHTS = [0.82, 1, 0.58]

export const MIC_ORB_RATIO = 0.2625

/**
 * Each state's bars: `low`/`high` are scale factors of the orb's diameter, so
 * 0.46 is a bar 46% of the orb tall — the same figure the component draws.
 *
 * ⚠️ `thinking` and `orbit` are near-flat on purpose. A voice assistant shows
 * *what it is doing*, and the idle states are the ones where nothing is being
 * heard: three dots, not three bars. That is a picture, so it belongs beside the
 * numbers rather than in the JSX.
 */
export const MIC_BAR_MOTION = {
  listening: { low: 0.2, high: 0.47, durationMs: 1200, offsetsMs: [0, 240, 480] },
  thinking: { low: 0.1, high: 0.13, durationMs: 2400, offsetsMs: [0, 600, 1200] },
  speaking: { low: 0.26, high: 0.7, durationMs: 620, offsetsMs: [0, 150, 300] },
  orbit: { low: 0.09, high: 0.12, durationMs: 3000, offsetsMs: [0, 900, 1800] },
  pulse: { low: 0.16, high: 0.44, durationMs: 1700, offsetsMs: [0, 0, 0] },
}

/** The orb's diameter in pixels, for the component's `size`. */
export function micOrbSize(size) {
  return Math.round(clampBlobSize(size) * MIC_ORB_RATIO)
}

/** One state's bar motion — never undefined, whatever it is handed. */
export function micBarMotion(variant) {
  return MIC_BAR_MOTION[variant] ?? MIC_BAR_MOTION[BLOB_DEFAULTS.variant]
}

/**
 * The three bar heights the component draws when nothing is moving — the frozen
 * frame a reduced-motion visitor sees, and the figure the tests can check.
 */
export function micBarHeights(variant) {
  const { low } = micBarMotion(variant)
  return MIC_BAR_WEIGHTS.map((weight) => round4(low * weight))
}

function round4(value) {
  return Math.round(value * 10000) / 10000
}

// ─── What the GPU is handed ────────────────────────────────────────

/**
 * The palette as the shader wants it: `MAX_STRANDS` × RGB, padded by cycling.
 *
 * GL requires the whole uniform array to be supplied even when fewer slots are
 * meaningful, so the palette repeats into the empty ones — which also means a
 * 2-colour palette and an 8-colour one are filled by the same code, and the
 * shader never indexes a zeroed slot (a black strand would look like a bug).
 */
export function blobUniformColors(colors) {
  const palette = normalizeColors(colors)
  const flat = new Float32Array(MAX_STRANDS * 3)

  if (palette.length === 0) return flat

  for (let slot = 0; slot < MAX_STRANDS; slot += 1) {
    const rgb = parseHexColor(palette[slot % palette.length])
    flat[slot * 3] = rgb[0]
    flat[slot * 3 + 1] = rgb[1]
    flat[slot * 3 + 2] = rgb[2]
  }

  return flat
}

/** How many palette entries the shader should actually blend between. */
export function paletteCount(colors) {
  return normalizeColors(colors).length
}

/**
 * The snippet the page shows and the admin copies.
 *
 * Generated from the resolved props rather than typed out, so the code on screen
 * and the blob beside it cannot disagree — which is the only failure mode a
 * "copy this" panel really has.
 */
export function blobSnippet(props) {
  const { size, colors, count, variant, glass } = resolveBlobProps(props)

  return [
    'import { AiFluidBlob } from "../components/ai/AiFluidBlob.jsx"',
    '',
    '<AiFluidBlob',
    `  size={${size}}`,
    `  variant="${variant}"`,
    `  count={${count}}`,
    `  colors={[${colors.map((c) => `'${c}'`).join(', ')}]}`,
    `  glass={${glass}}`,
    '/>',
  ].join('\n')
}
