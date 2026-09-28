import assert from 'node:assert/strict'
import { describe, it } from 'node:test'

import { CONTEXT_MENU_MARGIN, contextMenuPosition } from './contextMenuRules.js'

const viewport = { width: 1200, height: 800 }
const menu = { width: 224, height: 180 }

describe('contextMenuPosition', () => {
  it('hangs the menu from the pointer, down and to the right, when there is room', () => {
    const placed = contextMenuPosition({ x: 200, y: 300, ...menu, viewport })
    assert.equal(placed.left, 200)
    assert.equal(placed.top, 300)
    assert.equal(placed.flippedX, false)
    assert.equal(placed.flippedY, false)
  })

  it('flips left when the menu would run off the right edge, so its right edge meets the pointer', () => {
    const x = viewport.width - 40
    const placed = contextMenuPosition({ x, y: 300, ...menu, viewport })
    assert.equal(placed.left, x - menu.width)
    assert.equal(placed.flippedX, true)
  })

  it('flips up when the menu would run off the bottom edge', () => {
    const y = viewport.height - 40
    const placed = contextMenuPosition({ x: 200, y, ...menu, viewport })
    assert.equal(placed.top, y - menu.height)
    assert.equal(placed.flippedY, true)
  })

  it('flips both ways in a corner instead of clamping the menu against the pointer', () => {
    const x = viewport.width - 4
    const y = viewport.height - 4
    const placed = contextMenuPosition({ x, y, ...menu, viewport })

    // It opened back towards the middle of the screen on both axes, rather than
    // sitting past the pointer with its far edge off screen.
    assert.ok(placed.left + menu.width <= x)
    assert.ok(placed.top + menu.height <= y)
    assert.ok(placed.left + menu.width + CONTEXT_MENU_MARGIN <= viewport.width)
    assert.ok(placed.top + menu.height + CONTEXT_MENU_MARGIN <= viewport.height)
  })

  it('still fits inside the viewport after flipping, with the margin kept', () => {
    const placed = contextMenuPosition({
      x: viewport.width - 1,
      y: viewport.height - 1,
      ...menu,
      viewport,
    })
    assert.ok(placed.left >= CONTEXT_MENU_MARGIN)
    assert.ok(placed.top >= CONTEXT_MENU_MARGIN)
    assert.ok(placed.left + menu.width + CONTEXT_MENU_MARGIN <= viewport.width)
    assert.ok(placed.top + menu.height + CONTEXT_MENU_MARGIN <= viewport.height)
  })

  it('clamps to the margin when the menu is taller than the viewport, which a flip cannot fix', () => {
    const placed = contextMenuPosition({
      x: 200,
      y: 700,
      width: 224,
      height: 1200,
      viewport,
    })
    assert.equal(placed.top, CONTEXT_MENU_MARGIN)
  })

  it('places at the pointer when the viewport is unknown rather than throwing', () => {
    const placed = contextMenuPosition({ x: 120, y: 90, ...menu })
    assert.equal(placed.left, 120)
    assert.equal(placed.top, 90)
  })

  it('treats nonsense measurements as zero instead of producing NaN coordinates', () => {
    const placed = contextMenuPosition({
      x: Number.NaN,
      y: undefined,
      width: 'wide',
      height: null,
      viewport: { width: Number.NaN, height: undefined },
    })
    assert.equal(placed.left, 0)
    assert.equal(placed.top, 0)
  })

  it('honours a custom margin', () => {
    const y = viewport.height - 10
    const placed = contextMenuPosition({ x: 200, y, ...menu, viewport, margin: 24 })
    assert.equal(placed.flippedY, true)
    assert.ok(placed.top + menu.height <= y)
    assert.ok(placed.top + menu.height + 24 <= viewport.height)
  })
})
