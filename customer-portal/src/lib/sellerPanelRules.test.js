import assert from 'node:assert/strict'
import { describe, it } from 'node:test'

import {
  PANEL_RESIZE_STEP_REM,
  PANEL_WIDTH,
  SELLER_PANEL_IDS,
  appliedPanelWidth,
  clampPanelWidth,
  isPanelDocked,
  normalizePanelId,
  normalizePanelState,
  normalizePanelWidth,
  panelMaxRem,
  panelWidthForKey,
  sellerPanelPage,
  sellerPanelTitle,
  serializePanelState,
} from './sellerPanelRules.js'

/** The state every fresh panel starts from, spelled out once for the tests. */
const CLOSED = { pinned: false, panel: null, width: PANEL_WIDTH.default, expanded: false }

describe('normalizePanelId', () => {
  it('knows the two panels', () => {
    assert.deepEqual(SELLER_PANEL_IDS, ['notifications', 'messages'])
    for (const id of SELLER_PANEL_IDS) assert.equal(normalizePanelId(id), id)
  })

  it('reads a value that travelled through storage', () => {
    assert.equal(normalizePanelId('  Notifications '), 'notifications')
  })

  it('answers null rather than inventing a panel', () => {
    // A closed panel is `null` — a third name would be a panel with nothing in
    // it, drawn where nothing should be.
    assert.equal(normalizePanelId('orders'), null)
    assert.equal(normalizePanelId(''), null)
    assert.equal(normalizePanelId(null), null)
    assert.equal(normalizePanelId(7), null)
  })
})

describe('the labels a panel carries', () => {
  it('names each panel and the page it stands in for', () => {
    assert.equal(sellerPanelTitle('notifications'), 'Notifications')
    assert.equal(sellerPanelTitle('messages'), 'Messages')
    assert.equal(sellerPanelPage('notifications'), '/seller/notifications')
    assert.equal(sellerPanelPage('messages'), '/seller/messages')
  })

  it('has nothing to say about a panel that is not one', () => {
    assert.equal(sellerPanelTitle(null), '')
    assert.equal(sellerPanelPage('nope'), null)
  })
})

describe('normalizePanelState', () => {
  it('starts closed, unpinned, at the default width', () => {
    assert.deepEqual(normalizePanelState(undefined), CLOSED)
    assert.deepEqual(normalizePanelState(''), CLOSED)
  })

  it('survives junk instead of throwing on the first render', () => {
    // This parses a string a previous version of the app, or a person with
    // devtools, wrote. A throw here is a blank seller shell.
    assert.deepEqual(normalizePanelState('{not json'), CLOSED)
    assert.deepEqual(normalizePanelState('[1,2,3]'), CLOSED)
    assert.deepEqual(normalizePanelState('"a string"'), CLOSED)
    assert.deepEqual(normalizePanelState(null), CLOSED)
    assert.deepEqual(normalizePanelState(42), CLOSED)
  })

  it('keeps a pinned panel, because a layout choice should survive a reload', () => {
    assert.deepEqual(normalizePanelState({ pinned: true, panel: 'messages' }), {
      ...CLOSED,
      pinned: true,
      panel: 'messages',
    })
  })

  it('forgets an UNPINNED panel, because a drawer nobody kept is not a layout', () => {
    // Restoring this would be the site reopening a drawer at somebody who
    // closed the tab on it.
    assert.deepEqual(normalizePanelState({ pinned: false, panel: 'messages' }), CLOSED)
    assert.deepEqual(normalizePanelState({ panel: 'notifications' }), CLOSED)
  })

  it('remembers the width and the expansion even of an unpinned panel', () => {
    // How wide somebody likes this panel is a layout choice, like the pin —
    // unlike "which panel was open", it is not a drawer nobody asked to keep.
    assert.deepEqual(normalizePanelState({ width: 30 }), { ...CLOSED, width: 30 })
    assert.deepEqual(normalizePanelState({ expanded: true }), { ...CLOSED, expanded: true })
  })

  it('only believes `pinned: true`, not a truthy stand-in', () => {
    assert.equal(normalizePanelState({ pinned: 'yes', panel: 'messages' }).pinned, false)
    assert.equal(normalizePanelState({ pinned: 1, panel: 'messages' }).pinned, false)
  })

  it('accepts its own output as input', () => {
    const state = { pinned: true, panel: 'notifications', width: 28.5, expanded: false }
    assert.deepEqual(normalizePanelState(serializePanelState(state)), state)
  })

  it('does not remember a width that the rules would refuse', () => {
    assert.equal(normalizePanelState({ width: 4000 }).width, PANEL_WIDTH.max)
    assert.equal(normalizePanelState({ width: 2 }).width, PANEL_WIDTH.min)
    assert.equal(normalizePanelState({ width: 'wide' }).width, PANEL_WIDTH.default)
    assert.equal(normalizePanelState({ width: NaN }).width, PANEL_WIDTH.default)
  })
})

describe('normalizePanelWidth', () => {
  it('snaps to a quarter of a rem', () => {
    // A drag produces numbers like 22.318181818181817, and every one of them
    // would otherwise be written to storage and to a style attribute.
    assert.equal(normalizePanelWidth(22.318181818181817), 22.25)
    assert.equal(normalizePanelWidth(22.4), 22.5)
    assert.equal(normalizePanelWidth(30), 30)
  })

  it('holds the two walls', () => {
    assert.equal(normalizePanelWidth(1), PANEL_WIDTH.min)
    assert.equal(normalizePanelWidth(9999), PANEL_WIDTH.max)
  })

  it('falls back to the default for anything that is not a number', () => {
    assert.equal(normalizePanelWidth(undefined), PANEL_WIDTH.default)
    assert.equal(normalizePanelWidth(null), PANEL_WIDTH.default)
    assert.equal(normalizePanelWidth('28rem'), PANEL_WIDTH.default)
  })
})

describe('panelMaxRem', () => {
  it('gives the docked panel a smaller share, because a page sits beside it', () => {
    // 1536px is 96rem: 55% is 52.8, over the 40rem ceiling of its own.
    assert.equal(panelMaxRem(96, { docked: true }), PANEL_WIDTH.max)
    // 1024px is 64rem: 55% is 35.2, under it.
    assert.equal(panelMaxRem(64, { docked: true }), 35.2)
  })

  it('leaves a strip of the page showing when it is not docked', () => {
    // 390px is 24.375rem: 92% is 22.425, which still leaves 8% of the shop
    // behind the drawer. A panel that covers the window is a navigation, and
    // this exists so it does not have to be one.
    assert.equal(panelMaxRem(24.375), 22.425)
    assert.ok(panelMaxRem(24.375) < 24.375)
  })

  it('never goes below the floor, however small the window', () => {
    assert.equal(panelMaxRem(10, { docked: true }), PANEL_WIDTH.min)
    assert.equal(panelMaxRem(10), PANEL_WIDTH.min)
  })

  it('assumes there is room when there is no window to ask', () => {
    // A server has no viewport. The element also carries a CSS `max-width`, so
    // this is the belt and the stylesheet is the braces.
    assert.equal(panelMaxRem(null, { docked: true }), PANEL_WIDTH.max)
    assert.equal(panelMaxRem(undefined), PANEL_WIDTH.max)
    assert.equal(panelMaxRem(0), PANEL_WIDTH.max)
    assert.equal(panelMaxRem(NaN), PANEL_WIDTH.max)
  })
})

describe('clampPanelWidth', () => {
  it('applies the window\u2019s ceiling on top of the fixed walls', () => {
    assert.equal(clampPanelWidth(38, 35.2), 35.2)
    assert.equal(clampPanelWidth(30, 35.2), 30)
  })

  it('clamps after snapping, so the ceiling is never exceeded by a quarter rem', () => {
    // 35.2 snaps to 35.25, which would be two pixels past the rule.
    assert.equal(clampPanelWidth(35.2, 35.2), 35.2)
  })

  it('is happy with no ceiling at all', () => {
    assert.equal(clampPanelWidth(30), 30)
    assert.equal(clampPanelWidth(9999, undefined), PANEL_WIDTH.max)
  })
})

describe('appliedPanelWidth', () => {
  it('draws the seller\u2019s own width', () => {
    assert.equal(appliedPanelWidth({ width: 28, expanded: false, maxRem: 40 }), 28)
  })

  it('draws the ceiling when it is expanded', () => {
    assert.equal(appliedPanelWidth({ width: 28, expanded: true, maxRem: 40 }), 40)
  })

  it('keeps the seller\u2019s width underneath the expansion', () => {
    // Which is what makes collapsing free: nothing has to be guessed back.
    const expanded = appliedPanelWidth({ width: 28, expanded: true, maxRem: 40 })
    assert.equal(expanded, 40)
    assert.equal(appliedPanelWidth({ width: 28, expanded: false, maxRem: 40 }), 28)
  })

  it('expands to whatever the window allows, not to the fixed ceiling', () => {
    assert.equal(appliedPanelWidth({ width: 22, expanded: true, maxRem: 35.2 }), 35.2)
  })

  it('behaves with nothing to go on', () => {
    assert.equal(appliedPanelWidth({}), PANEL_WIDTH.default)
    assert.equal(appliedPanelWidth({ expanded: true }), PANEL_WIDTH.max)
  })
})

describe('panelWidthForKey', () => {
  it('moves with the arrow, which is the edge being dragged', () => {
    // The panel is on the right, so its grab is on its left edge: ArrowLeft is
    // wider, exactly as dragging that edge leftwards is.
    assert.equal(panelWidthForKey({ key: 'ArrowLeft', width: 22, maxRem: 40 }), 22 + PANEL_RESIZE_STEP_REM)
    assert.equal(panelWidthForKey({ key: 'ArrowRight', width: 22, maxRem: 40 }), 22 - PANEL_RESIZE_STEP_REM)
  })

  it('stops at the walls instead of running past them', () => {
    assert.equal(panelWidthForKey({ key: 'ArrowLeft', width: PANEL_WIDTH.max, maxRem: 40 }), PANEL_WIDTH.max)
    assert.equal(panelWidthForKey({ key: 'ArrowRight', width: PANEL_WIDTH.min, maxRem: 40 }), PANEL_WIDTH.min)
    // One step from 35 would be 36, which this window does not have.
    assert.equal(panelWidthForKey({ key: 'ArrowLeft', width: 35, maxRem: 35.2 }), 35.2)
  })

  it('jumps to either wall on Home and End', () => {
    assert.equal(panelWidthForKey({ key: 'Home', width: 30, maxRem: 40 }), PANEL_WIDTH.min)
    assert.equal(panelWidthForKey({ key: 'End', width: 18, maxRem: 40 }), PANEL_WIDTH.max)
    assert.equal(panelWidthForKey({ key: 'End', width: 18, maxRem: 35.2 }), 35.2)
  })

  it('has nothing to say about any other key', () => {
    // Which is what lets the handler ignore everything else rather than calling
    // preventDefault on a page a keyboard is also allowed to scroll.
    for (const key of ['Enter', ' ', 'Tab', 'a', 'ArrowUp', 'Escape']) {
      assert.equal(panelWidthForKey({ key, width: 22, maxRem: 40 }), null)
    }
    assert.equal(panelWidthForKey(), null)
  })
})

describe('isPanelDocked', () => {
  it('docks only when there is a panel, a pin and room for it', () => {
    assert.equal(isPanelDocked({ panel: 'messages', pinned: true, wide: true }), true)
  })

  it('falls back to an overlay for any one of the three missing', () => {
    // The overlay is the state that always works, and therefore the one to
    // fail into: a dock with no room beside the page would push the page off
    // the screen, which is worse than covering it.
    assert.equal(isPanelDocked({ panel: null, pinned: true, wide: true }), false)
    assert.equal(isPanelDocked({ panel: 'messages', pinned: false, wide: true }), false)
    assert.equal(isPanelDocked({ panel: 'messages', pinned: true, wide: false }), false)
    assert.equal(isPanelDocked({}), false)
  })

  it('treats an unknown panel name as no panel', () => {
    assert.equal(isPanelDocked({ panel: 'orders', pinned: true, wide: true }), false)
  })
})
