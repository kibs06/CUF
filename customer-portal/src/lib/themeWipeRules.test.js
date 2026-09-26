import assert from 'node:assert/strict'
import { describe, it } from 'node:test'

import {
  THEME_WIPE_DURATION,
  THEME_WIPE_REDUCED_DURATION,
  themeWipeFrames,
  themeWipePlan,
  wipeCircle,
  wipeOrigin,
  wipeRadius,
} from './themeWipeRules.js'

const VIEWPORT = { width: 1440, height: 900 }

describe('wipeOrigin', () => {
  it('is the pointer when there is one', () => {
    assert.deepEqual(wipeOrigin({ x: 120, y: 40 }, VIEWPORT), { x: 120, y: 40 })
  })

  it('falls back to the centre of the screen, never to NaN', () => {
    // A keyboard selection has no pointer. `circle(NaNpx at …)` is an invalid
    // clip-path, which the browser ignores — and an ignored clip-path is the
    // full-screen flicker this feature exists to remove.
    for (const point of [null, undefined, {}, { x: 10 }, { x: 'a', y: 'b' }, { x: NaN, y: 0 }]) {
      assert.deepEqual(wipeOrigin(point, VIEWPORT), { x: 720, y: 450 })
    }
  })

  it('clamps a point that is outside the viewport', () => {
    assert.deepEqual(wipeOrigin({ x: -50, y: 2000 }, VIEWPORT), { x: 0, y: 900 })
  })

  it('survives a viewport it was not told about', () => {
    assert.deepEqual(wipeOrigin({ x: 5, y: 5 }, null), { x: 0, y: 0 })
    assert.deepEqual(wipeOrigin({ x: 5, y: 5 }, undefined), { x: 0, y: 0 })
  })
})

describe('wipeRadius', () => {
  it('reaches the farthest corner', () => {
    // From the top-left, the farthest corner is the bottom-right.
    assert.equal(wipeRadius({ x: 0, y: 0 }, VIEWPORT), Math.ceil(Math.hypot(1440, 900)))
    assert.equal(wipeRadius({ x: 1440, y: 900 }, VIEWPORT), Math.ceil(Math.hypot(1440, 900)))
  })

  it('is the nearest corner, not the farthest, from the middle', () => {
    // The middle is the SHORTEST distance to any corner, so this is the case
    // where a "just use the diagonal" shortcut would leave a corner un-wiped.
    assert.equal(wipeRadius({ x: 720, y: 450 }, VIEWPORT), Math.ceil(Math.hypot(720, 450)))
  })

  it('rounds UP, so no sliver of the old theme survives', () => {
    const radius = wipeRadius({ x: Math.PI, y: Math.E }, VIEWPORT)
    assert.equal(Number.isInteger(radius), true)
    assert.equal(radius >= Math.hypot(1440 - Math.PI, 900 - Math.E), true)
  })

  it('is defensible with no origin and no viewport', () => {
    // No origin means the top-left corner, which is as far from the far corner
    // as the viewport allows.
    assert.equal(wipeRadius(null, VIEWPORT), Math.ceil(Math.hypot(1440, 900)))
    // A point outside a viewport of no size is still a positive distance from
    // it: never NaN, never a negative radius. (`wipeOrigin` is what clamps, and
    // it is called first — this is only the arithmetic holding up on its own.)
    assert.equal(wipeRadius({ x: 1, y: 1 }, null), Math.ceil(Math.hypot(1, 1)))
  })
})

describe('wipeCircle', () => {
  it('writes the clip-path the browser expects', () => {
    assert.equal(wipeCircle(300, { x: 10, y: 20 }), 'circle(300px at 10px 20px)')
    assert.equal(wipeCircle(0, { x: 0, y: 0 }), 'circle(0px at 0px 0px)')
  })

  it('never writes a negative radius', () => {
    assert.equal(wipeCircle(-40, { x: 0, y: 0 }), 'circle(0px at 0px 0px)')
  })
})

describe('themeWipeFrames', () => {
  const origin = { x: 100, y: 100 }

  it('grows the light out of the cursor', () => {
    const { pseudoElement, keyframes } = themeWipeFrames('light', origin, 500)

    assert.equal(pseudoElement, '::view-transition-new(root)')
    assert.deepEqual(keyframes, [
      'circle(0px at 100px 100px)',
      'circle(500px at 100px 100px)',
    ])
  })

  it('recedes the light back to the cursor going dark', () => {
    // The OLD (light) snapshot is the one that is clipped, from full to
    // nothing: the dark is what the screen settles on, and it is already
    // underneath, so the last frame matches the live page exactly — no snap.
    const { pseudoElement, keyframes } = themeWipeFrames('dark', origin, 500)

    assert.equal(pseudoElement, '::view-transition-old(root)')
    assert.deepEqual(keyframes, [
      'circle(500px at 100px 100px)',
      'circle(0px at 100px 100px)',
    ])
  })

  it('is exactly two frames, in opposite directions, for the two themes', () => {
    const light = themeWipeFrames('light', origin, 500)
    const dark = themeWipeFrames('dark', origin, 500)

    assert.equal(light.keyframes.length, 2)
    assert.equal(dark.keyframes.length, 2)
    assert.deepEqual(light.keyframes, [...dark.keyframes].reverse())
    assert.notEqual(light.pseudoElement, dark.pseudoElement)
  })
})

describe('themeWipePlan', () => {
  it('runs the full circle for a customer who has not asked for less motion', () => {
    assert.deepEqual(themeWipePlan({ supported: true, reduceMotion: false }), {
      duration: THEME_WIPE_DURATION,
    })
  })

  it('and a SHORTER one — not none — for a customer who has', () => {
    // The deliberate exception in this codebase: elsewhere reduced motion means
    // zero, because the animation is decoration. Here it is the explanation of
    // a full-screen change, so a hard flip would be the bigger sensory event.
    assert.deepEqual(themeWipePlan({ supported: true, reduceMotion: true }), {
      duration: THEME_WIPE_REDUCED_DURATION,
    })
    assert.equal(
      THEME_WIPE_REDUCED_DURATION > 0 &&
        THEME_WIPE_REDUCED_DURATION < THEME_WIPE_DURATION,
      true,
    )
  })

  it('is null — switch instantly — without the API, motion preference or not', () => {
    assert.equal(themeWipePlan({ supported: false, reduceMotion: false }), null)
    assert.equal(themeWipePlan({ supported: false, reduceMotion: true }), null)
  })

  it('fails open on an answer it did not get', () => {
    assert.equal(themeWipePlan({}), null)
  })
})

describe('THEME_WIPE_DURATION', () => {
  it('is long enough to read, and short enough to still be a transition', () => {
    // A full-screen movement at the site's 260ms entrance length reads as a
    // glitch, not a transition. The ceiling is the other failure: past about a
    // second this stops being an animation and becomes a wait, on a change that
    // has already been applied underneath it.
    assert.equal(THEME_WIPE_DURATION >= 400 && THEME_WIPE_DURATION <= 1000, true)
  })

  it('is slower than any entrance on the site, on purpose', () => {
    // Entrances are 150–260ms (see `index.css`). This is the one animation here
    // paced for how it looks rather than for getting out of the way — nothing is
    // waiting on it.
    assert.equal(THEME_WIPE_DURATION > 260, true)
  })

  it('keeps the reduced-motion circle in proportion', () => {
    // Roughly a third: a fast version of the same gesture, not a different one.
    const ratio = THEME_WIPE_REDUCED_DURATION / THEME_WIPE_DURATION
    assert.equal(ratio > 0.2 && ratio < 0.45, true)
  })
})
