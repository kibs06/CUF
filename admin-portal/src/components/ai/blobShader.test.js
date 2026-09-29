import { test } from 'node:test'
import assert from 'node:assert/strict'

import { MAX_STRANDS } from '../../lib/aiBlob.js'
import { FRAGMENT_SHADER, VERTEX_SHADER } from './blobShader.js'

// ─── The seam between JavaScript and GLSL ──────────────────────────
//
// This is the one interface in the component that cannot be type-checked, linted
// or compiled anywhere but a browser: the component uploads uniforms **by name**,
// and `gl.getUniformLocation` answers `null` for a name the shader does not
// declare. `gl.uniform1f(null, 0.4)` is then a silent no-op — the page renders,
// nothing errors, and one prop quietly does nothing at all.
//
// So the names are pinned on both sides of the seam here. The list is written out
// rather than imported from the component on purpose: a test that asked the
// component which uniforms it sends would agree with any typo in the component.

const UPLOADED_UNIFORMS = [
  'uResolution',
  'uTime',
  'uColors',
  'uPaletteCount',
  'uCount',
  'uEnergy',
  'uSpin',
  'uWobble',
  'uPulse',
  'uSpread',
  'uGlass',
]

test('every uniform the component uploads is declared by the fragment shader', () => {
  for (const name of UPLOADED_UNIFORMS) {
    assert.match(
      FRAGMENT_SHADER,
      new RegExp(`uniform\\s+\\w+\\s+${name}\\b`),
      `${name} is uploaded but not declared — the upload would be a silent no-op`,
    )
  }
})

test('the shader declares no uniform the component never sets', () => {
  const declared = [...FRAGMENT_SHADER.matchAll(/uniform\s+\w+\s+(u[A-Za-z0-9_]+)/g)].map((m) => m[1])
  assert.ok(declared.length > 0, 'no uniforms found — the shader text moved')

  for (const name of new Set(declared)) {
    assert.ok(
      UPLOADED_UNIFORMS.includes(name),
      `${name} is declared but never uploaded, so it would stay zero forever`,
    )
  }
})

test('the vertex shader is the one attribute the component binds', () => {
  assert.match(VERTEX_SHADER, /attribute\s+vec2\s+aPosition\s*;/)
})

test('neither shader contains a backtick', () => {
  // ⚠️ Both sources are template literals, and a backtick is the delimiter. This
  // component has shipped the same mistake three times: a comment written with
  // markdown backticks around a prop name, which either fails to parse at all or —
  // worse, when the pair is balanced — parses cleanly and hands the driver a
  // shader with JavaScript spliced through it. The syntax error is the lucky case.
  for (const [name, source] of [
    ['VERTEX_SHADER', VERTEX_SHADER],
    ['FRAGMENT_SHADER', FRAGMENT_SHADER],
  ]) {
    assert.ok(!source.includes('`'), `${name} contains a backtick — quote it instead`)
  }
})

test('the uniform array width is the one the prop clamp enforces', () => {
  // Two files, one ceiling: `lib/aiBlob.js` clamps `count` to it and the shader
  // declares an array of it. Drift here would be a shader that cannot hold what
  // the props allow.
  assert.match(FRAGMENT_SHADER, new RegExp(`#define MAX_STRANDS ${MAX_STRANDS}\\b`))
  // The declaration goes through the macro rather than repeating the number, so
  // this is asserting that it is not a literal that could drift from it.
  assert.match(FRAGMENT_SHADER, /uniform\s+vec3\s+uColors\[MAX_STRANDS\]/)
})

test('the glass lens is three samples of one field, one per colour channel', () => {
  // ⚠️ The dispersion IS the phase: a single sample under the glass would be a
  // clean magnifier and would not read as glass at all, so the three refracted
  // reads are pinned rather than assumed.
  const refracted = FRAGMENT_SHADER.match(/refr\.[rgb] = liquidAt\(/g) ?? []
  assert.equal(refracted.length, 3)

  const bends = FRAGMENT_SHADER.match(/dir \* bend \* ([\d.]+)/g) ?? []
  assert.equal(bends.length, 3)
  assert.equal(new Set(bends).size, 3, 'the three channels bend by the same amount — no dispersion')

  assert.match(FRAGMENT_SHADER, /uGlass > 0\.5/)
  // The no-lens branch has to draw something, or `glass={false}` would be a
  // picture of nothing — and it has to be the *bare liquid*, not the sphere with
  // its rim and sheen switched off, which is the difference the prop is named for.
  assert.match(FRAGMENT_SHADER, /\} else \{[\s\S]*?straight\(liquidAt\(q, t\)\)/)
})

test('the shader writes straight alpha, because the canvas is composited over the page', () => {
  // ⚠️ The component asks for `alpha: true, premultipliedAlpha: false`. A shader
  // that wrote an opaque 1.0 here would paint an opaque disc over whatever card it
  // was dropped into — the exact failure the transparent canvas exists to avoid.
  assert.match(FRAGMENT_SHADER, /gl_FragColor = colour;/)
  assert.match(FRAGMENT_SHADER, /vec4 straight\(vec3 emission\)/)

  // The alpha has to be *derived from the light*, or a band's faint tail would be
  // as opaque as its core and the field would read as a flat blob.
  assert.match(FRAGMENT_SHADER, /float a = clamp\(m \* [\d.]+/)
  assert.ok(
    !/gl_FragColor = vec4\([\s\S]*?, 1\.0\);/.test(FRAGMENT_SHADER),
    'an opaque frag colour would be a black or solid disc over the page',
  )
})

test('the fragment shader uses no ES 2-only syntax', () => {

  // ⚠️ ES 1.00 has no integer max/min — the mistake that cost this component its
  // first render, hidden behind the fallback until the DOM was read. `max` on two
  // non-float arguments is the shape to refuse.
  assert.ok(
    !/max\(\s*[A-Za-z_]\w*\s*,\s*\d+\s*\)/.test(FRAGMENT_SHADER),
    'a max() on what might be ints would not compile under ES 1.00',
  )
})
