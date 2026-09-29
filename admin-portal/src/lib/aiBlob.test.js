import { test } from 'node:test'
import assert from 'node:assert/strict'

import {
  BLOB_DEFAULTS,
  BLOB_PRESETS,
  BLOB_SIZE_LIMITS,
  BLOB_VARIANTS,
  DEFAULT_BLOB_COLORS,
  MAX_STRANDS,
  REDUCED_MOTION_PHASE_SECONDS,
  VARIANT_MOTION,
  MIC_BAR_COUNT,
  MIC_BAR_MOTION,
  blobSnippet,
  blobUniformColors,
  micBarHeights,
  micBarMotion,
  micOrbSize,
  clampBlobSize,
  clampStrandCount,
  frameTimeSeconds,
  normalizeColors,
  paletteCount,
  parseHexColor,
  resolveBlobProps,
  shouldAnimate,
  variantMotion,
} from './aiBlob.js'

// ─── Colour parsing ────────────────────────────────────────────────

test('a hex colour is read as 0..1 floats, in the three shapes it arrives in', () => {
  assert.deepEqual(parseHexColor('#ffffff'), [1, 1, 1])
  assert.deepEqual(parseHexColor('#000000'), [0, 0, 0])
  assert.deepEqual(parseHexColor('10B981'), parseHexColor('#10B981'))
  assert.deepEqual(parseHexColor('  #3b82f6  '), parseHexColor('#3B82F6'))

  // Three digits are expanded per channel, not read as a short number.
  assert.deepEqual(parseHexColor('#abc'), parseHexColor('#aabbcc'))

  // The mid-grey check: a wrong bit shift still yields *a* number, so pin one
  // known value rather than trusting the shape.
  const [r, g, b] = parseHexColor('#808080')
  assert.ok(Math.abs(r - 128 / 255) < 1e-9)
  assert.equal(r, g)
  assert.equal(g, b)
})

test('anything that is not a colour is refused rather than guessed at', () => {
  for (const bad of ['', '   ', 'red', '#12', '#12345', '#1234567', '#gggggg', null, undefined, 42, {}]) {
    assert.equal(parseHexColor(bad), null, `${String(bad)} must not parse`)
  }
})

// ─── Palettes ──────────────────────────────────────────────────────

test('a palette keeps what it can use and drops the rest', () => {
  const colors = normalizeColors(['#10B981', 'nope', '#abc', 7, '#6366F1'])
  assert.deepEqual(colors, ['#10B981', '#AABBCC', '#6366F1'])
})

test('an empty or unusable palette falls back to the documented default', () => {
  // ⚠️ Not a black canvas: a caller cannot debug "no colour" from a screenshot.
  assert.deepEqual(normalizeColors([]), DEFAULT_BLOB_COLORS)
  assert.deepEqual(normalizeColors(undefined), DEFAULT_BLOB_COLORS)
  assert.deepEqual(normalizeColors(['not-a-colour']), DEFAULT_BLOB_COLORS)
})

test('a palette is capped at the shader’s array width', () => {
  const many = Array.from({ length: 20 }, (_, i) => `#${i.toString(16).padStart(2, '0')}0000`)
  assert.equal(normalizeColors(many).length, MAX_STRANDS)
  assert.equal(paletteCount(many), MAX_STRANDS)
})

test('normalized colours are upper-case six-digit hex, so the snippet is stable', () => {
  assert.deepEqual(normalizeColors(['#abc', '10b981']), ['#AABBCC', '#10B981'])
})

test('every preset palette survives normalization, so no swatch can lie', () => {
  // A mistyped hex is dropped silently and the picker falls back to the default —
  // which looks like the preset "not working" rather than like a typo.
  for (const preset of BLOB_PRESETS) {
    const colors = normalizeColors(preset.colors)
    assert.equal(
      colors.length,
      preset.colors.length,
      `${preset.name} lost a colour to normalization`,
    )
    assert.ok(new Set(colors).size > 1, `${preset.name} is a single colour`)
    assert.ok(preset.name.length > 0)
  }
})

// ─── Size and strand count ─────────────────────────────────────────

test('size clamps into the drawable band instead of being trusted', () => {
  assert.equal(clampBlobSize(320), 320)
  assert.equal(clampBlobSize(260.4), 260)
  // An invisible component and a melted GPU are both a typo, not a request.
  assert.equal(clampBlobSize(0), BLOB_SIZE_LIMITS.min)
  assert.equal(clampBlobSize(40000), BLOB_SIZE_LIMITS.max)
  assert.equal(clampBlobSize('abc'), BLOB_DEFAULTS.size)
  assert.equal(clampBlobSize(undefined), BLOB_DEFAULTS.size)
})

test('the strand count is whole, between one and the shader’s ceiling', () => {
  assert.equal(clampStrandCount(4), 4)
  assert.equal(clampStrandCount(0), 1)
  assert.equal(clampStrandCount(-3), 1)
  assert.equal(clampStrandCount(99), MAX_STRANDS)
  // A fraction of a strand is not drawable, so it floors rather than rounding up.
  assert.equal(clampStrandCount(3.9), 3)
  assert.equal(clampStrandCount('nope'), BLOB_DEFAULTS.count)
})

// ─── The prop contract ─────────────────────────────────────────────

test('the documented defaults survive an empty props object', () => {
  assert.deepEqual(resolveBlobProps(), {
    size: BLOB_DEFAULTS.size,
    colors: DEFAULT_BLOB_COLORS,
    count: BLOB_DEFAULTS.count,
    variant: BLOB_DEFAULTS.variant,
    glass: BLOB_DEFAULTS.glass,
  })
  assert.deepEqual(resolveBlobProps({}), resolveBlobProps())
})

test('an unknown variant falls back rather than blanking the surface', () => {
  // Decoration on a dashboard: a state name from a newer release of somebody
  // else's component should leave a working blob, not an empty box.
  assert.equal(resolveBlobProps({ variant: 'teleporting' }).variant, BLOB_DEFAULTS.variant)
  assert.equal(resolveBlobProps({ variant: undefined }).variant, BLOB_DEFAULTS.variant)
  for (const variant of BLOB_VARIANTS) {
    assert.equal(resolveBlobProps({ variant }).variant, variant)
  }
})

test('glass is on unless it is explicitly off', () => {
  assert.equal(resolveBlobProps({}).glass, true)
  assert.equal(resolveBlobProps({ glass: false }).glass, false)
  // A missing prop is `undefined`, and `glass` written bare in JSX is `true`.
  assert.equal(resolveBlobProps({ glass: undefined }).glass, true)
  assert.equal(resolveBlobProps({ glass: true }).glass, true)
})

// ─── The five states are five states ───────────────────────────────

test('every variant has a full, finite motion profile', () => {
  for (const variant of BLOB_VARIANTS) {
    const motion = VARIANT_MOTION[variant]
    assert.ok(motion, `${variant} has no motion profile`)
    for (const key of ['energy', 'spin', 'wobble', 'pulse', 'spread']) {
      assert.ok(Number.isFinite(motion[key]), `${variant}.${key} is not a number`)
    }
  }
  assert.equal(variantMotion('nope'), VARIANT_MOTION[BLOB_DEFAULTS.variant])
})

test('the states do not move alike, or the prop would be decoration', () => {
  // `speaking` is the agitated one and `thinking` the wandering one: if either
  // lost its distinguishing number the two would read the same on screen.
  assert.ok(VARIANT_MOTION.speaking.energy > VARIANT_MOTION.thinking.energy)
  assert.ok(VARIANT_MOTION.speaking.pulse > VARIANT_MOTION.listening.pulse)
  assert.ok(VARIANT_MOTION.thinking.wobble > VARIANT_MOTION.orbit.wobble)
  assert.ok(VARIANT_MOTION.orbit.spread > VARIANT_MOTION.thinking.spread)
  assert.ok(VARIANT_MOTION.pulse.pulse > VARIANT_MOTION.orbit.pulse)

  const shapes = BLOB_VARIANTS.map((v) => JSON.stringify(VARIANT_MOTION[v]))
  assert.equal(new Set(shapes).size, BLOB_VARIANTS.length)
})

// ─── Reduced motion, and the render loop ───────────────────────────

test('reduced motion freezes the field at a composed phase, not at zero', () => {
  assert.equal(frameTimeSeconds({ elapsedMs: 9000, reducedMotion: true }), REDUCED_MOTION_PHASE_SECONDS)
  // Zero is the instant every sinusoid lines up and the strands collapse into one
  // ring — a plain circle, which is the one frame worth avoiding.
  assert.notEqual(REDUCED_MOTION_PHASE_SECONDS, 0)

  // Still moving otherwise, and elapsed drives it.
  assert.equal(frameTimeSeconds({ elapsedMs: 2500, reducedMotion: false }), 2.5)
  assert.equal(frameTimeSeconds({ elapsedMs: -5, reducedMotion: false }), 0)
  assert.equal(frameTimeSeconds({ elapsedMs: 'x', reducedMotion: false }), 0)
  assert.equal(frameTimeSeconds({}), 0)
})

test('the loop stops for reduced motion and for an offscreen canvas', () => {
  assert.equal(shouldAnimate({ reducedMotion: false, visible: true }), true)
  assert.equal(shouldAnimate({ reducedMotion: true, visible: true }), false)
  // A dashboard tab in the background has no business burning a GPU.
  assert.equal(shouldAnimate({ reducedMotion: false, visible: false }), false)
  assert.equal(shouldAnimate({}), true)
})

// ─── What the GPU is handed ────────────────────────────────────────

test('the uniform palette is the shader’s full width, filled by cycling', () => {
  const flat = blobUniformColors(DEFAULT_BLOB_COLORS)
  assert.equal(flat.length, MAX_STRANDS * 3)

  const slot = (i) => [flat[i * 3], flat[i * 3 + 1], flat[i * 3 + 2]]
  // Four colours, twelve slots: slot 4 is slot 0 again.
  assert.deepEqual(slot(4), slot(0))
  assert.deepEqual(slot(11), slot(3))

  // ⚠️ No zeroed slot: a black strand among lit ones reads as a bug, and the
  // uniform array is always handed over in full.
  for (let i = 0; i < MAX_STRANDS; i += 1) {
    assert.ok(
      slot(i).some((channel) => channel > 0),
      `slot ${i} is empty`,
    )
  }
})

test('a two-colour palette fills the uniform array the same way', () => {
  const flat = blobUniformColors(['#FF0000', '#00FF00'])
  assert.deepEqual([flat[6], flat[7], flat[8]], [flat[0], flat[1], flat[2]])
  assert.deepEqual([flat[3], flat[4], flat[5]], [0, 1, 0])
})

// ─── The voice orb ─────────────────────────────────────────────────

test('the orb is the share of the component it is at the documented size', () => {
  // The component as it renders at the size its own docs use: an orb of 84px in a
  // 320px sphere. A ratio rather than the pixels, so the orb grows with the blob.
  assert.equal(micOrbSize(320), 84)
  assert.ok(micOrbSize(640) > micOrbSize(320))

  // It goes through the same size clamp as the canvas, so an absurd size cannot
  // produce an orb larger than its own sphere.
  assert.equal(micOrbSize(100000), micOrbSize(BLOB_SIZE_LIMITS.max))
  assert.equal(micOrbSize(0), micOrbSize(BLOB_SIZE_LIMITS.min))
})

test('every state has bars that actually move, and the idle states barely do', () => {
  for (const variant of BLOB_VARIANTS) {
    const motion = MIC_BAR_MOTION[variant]
    assert.ok(motion, `${variant} has no bar motion`)
    assert.ok(motion.low >= 0 && motion.low < motion.high, `${variant} does not rise`)
    assert.ok(motion.high <= 1, `${variant} would draw a bar taller than the orb`)
    assert.equal(motion.offsetsMs.length, MIC_BAR_COUNT)
    assert.ok(motion.durationMs > 0)
  }

  // ⚠️ The picture, not the plumbing: `thinking` and `orbit` show dots because
  // nothing is being heard. If a later edit made them wave, the states would stop
  // being readable as states — which is the only thing `variant` is for.
  assert.ok(MIC_BAR_MOTION.listening.high > MIC_BAR_MOTION.thinking.high * 2)
  assert.ok(MIC_BAR_MOTION.speaking.high > MIC_BAR_MOTION.listening.high)
  assert.ok(MIC_BAR_MOTION.speaking.durationMs < MIC_BAR_MOTION.orbit.durationMs)

  const shapes = BLOB_VARIANTS.map((v) => JSON.stringify(MIC_BAR_MOTION[v]))
  assert.equal(new Set(shapes).size, BLOB_VARIANTS.length)
})

test('the frozen frame is the resting height of each bar, not zero', () => {
  // A reduced-motion visitor gets a still orb that still reads as a voice
  // assistant. Zero would be three invisible spans in a frosted disc.
  for (const variant of BLOB_VARIANTS) {
    const heights = micBarHeights(variant)
    assert.equal(heights.length, MIC_BAR_COUNT)
    for (const height of heights) assert.ok(height > 0 && height <= 1)

    // The middle bar is the tall one, as in the component's own proportions.
    assert.ok(heights[1] > heights[2])
  }

  assert.equal(micBarMotion('nope'), MIC_BAR_MOTION[BLOB_DEFAULTS.variant])
  assert.deepEqual(micBarHeights('nope'), micBarHeights(BLOB_DEFAULTS.variant))
})

// ─── The snippet on the page ───────────────────────────────────────

test('the snippet is generated from the resolved props, so the code matches the blob', () => {
  const snippet = blobSnippet({ size: 320, variant: 'listening', count: 4, glass: true })

  assert.match(snippet, /from "\.\.\/components\/ai\/AiFluidBlob\.jsx"/)
  assert.match(snippet, /size=\{320\}/)
  assert.match(snippet, /variant="listening"/)
  assert.match(snippet, /count=\{4\}/)
  assert.match(snippet, /glass=\{true\}/)
  for (const color of DEFAULT_BLOB_COLORS) {
    assert.ok(snippet.includes(`'${color}'`), `${color} missing from the snippet`)
  }
})

test('the snippet reflects a hostile props object, not the caller’s intent', () => {
  // It prints what the component will draw with, which is the only version that
  // cannot disagree with the blob beside it.
  const snippet = blobSnippet({ size: 5, variant: 'nope', count: 99, colors: ['#abc'], glass: false })
  assert.match(snippet, /size=\{96\}/)
  assert.match(snippet, /variant="listening"/)
  assert.match(snippet, /count=\{12\}/)
  assert.match(snippet, /'#AABBCC'/)
  assert.match(snippet, /glass=\{false\}/)
})
