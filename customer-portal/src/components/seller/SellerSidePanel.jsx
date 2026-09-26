import { useEffect, useRef, useState } from 'react'
import { Link } from 'react-router-dom'
import { ChevronsLeft, ChevronsRight, Maximize2, Pin, PinOff, X } from 'lucide-react'

import { PANEL_WIDTH, clampPanelWidth, panelWidthForKey } from '../../lib/sellerPanelRules.js'

/**
 * The seller's right-hand panel: a drawer for Notifications or Messages.
 *
 * ## Two modes, one component
 *
 *  * **Overlay** — a fixed drawer beside the page, below the bar, with a scrim
 *    over the content behind it. Escape, a click on the scrim, and navigating
 *    away all close it.
 *  * **Docked** — a real column beside the page: the page keeps its own width
 *    minus the panel's and both are read together. It stays across navigation,
 *    because that is what pinning is for.
 *
 * **Only one of them is ever mounted.** They are not two class sets on one
 * element, because the difference is not only styling: a docked panel is a flex
 * sibling of `<main>`, and an overlay is a fixed layer above it. The shell
 * decides which, in JavaScript, from the pin and the viewport width — see
 * `isPanelDocked`. That is deliberate: rendering both and hiding one with CSS
 * would mount the feed twice, and two mounts means two message subscriptions,
 * two queries under the same key, and two composers whose `id`s collide.
 *
 * ## It is not `aria-modal`
 *
 * It behaves like a drawer — Escape closes it, a click outside closes it — but
 * focus is not trapped inside it, and calling it a modal dialog would promise a
 * screen reader something this does not do. It is an `<aside>` with a name: a
 * complementary region, which is exactly what a side panel is. Focus *is* moved
 * into the panel when it opens, so the next Tab goes through its controls rather
 * than the page behind it; nothing is handed back on close, because the control
 * that opened it (`SellerAccountMenu`'s row) has already closed the menu behind
 * it — focus goes to the panel's close button and stays in the panel's own
 * neighbourhood, which is where the next Tab should be anyway.
 *
 * ## The pin is a real button, not a toggle-looking icon
 *
 * `aria-pressed` on it, and it says what it will do (`Pin` / `Unpin this panel`)
 * in its title and its screen-reader name, because "did I just pin it or unpin
 * it" is not something an outline tells you.
 *
 * ## How wide it is, and how wide it is allowed to be
 *
 * Two ways to change the width, and they end at the same wall. **The grab** is a
 * `role="separator"` splitter on the panel's inner edge: a pointer drags it,
 * ArrowLeft/ArrowRight move it a rem at a time, and Home/End jump to the two
 * ends. **The chevrons** in the header expand the panel to the widest this window
 * allows and put it back. The wall itself is `panelMaxRem` — 55% of the window
 * docked, 92% as an overlay, never more than 40rem and never less than 16rem —
 * and every path goes through `clampPanelWidth`, including the drag.
 *
 * ### Why the drag is drawn from local state
 *
 * A pointer move fires dozens of times a second, and the width lives in the
 * shell's provider. Committing on every move would re-render the shell, and the
 * panel's children — thirty-odd notification cards — with it, once per frame. So
 * the drag keeps its own `draft` here, and the aside is drawn from that; the
 * `children` element is the *same object* throughout, so React bails out of
 * re-rendering that subtree entirely and only this component's own two nodes
 * change. One commit happens, on release, where it belongs.
 *
 * The chevrons and the keyboard commit immediately, which is right: those are
 * discrete choices, not a continuous gesture, so there is nothing to defer.
 */
export default function SellerSidePanel({
  panelId,
  title,
  page,
  docked,
  pinned,
  expanded,
  width,
  maxRem,
  onResize,
  onClose,
  onTogglePin,
  onToggleExpand,
  children,
}) {
  /*
    The id the account menu's rows point at with `aria-controls`, so a screen
    reader can tie "Notifications" to the region it opens. It is the panel id
    from `sellerPanelRules`, not a fresh one, because the row and the panel have
    to agree on it without either passing a prop to the other.
  */
  const regionId = `seller-panel-${panelId}`
  /*
    Escape closes the panel in both modes: closing is a dismissal, and a pinned
    panel is still one Escape away from out of the way — the pin outlives it, so
    reopening docks it again.
    The listener is on the document rather than on the panel because the panel is
    not focused when the pointer is over the page beside it, which is where it
    usually is while someone reads.
  */
  useEffect(() => {
    const onKeyDown = (event) => {
      if (event.key === 'Escape') onClose()
    }
    document.addEventListener('keydown', onKeyDown)
    return () => document.removeEventListener('keydown', onKeyDown)
  }, [onClose])

  /*
    Move focus into the panel so the next Tab walks its controls. `preventScroll`
    because the docked panel is at the top of a long page and focusing it should
    not jump the seller's page.
  */
  useEffect(() => {
    document.getElementById('seller-panel-close')?.focus({ preventScroll: true })
  }, [])

  const header = (
    <header className="flex shrink-0 items-center gap-1 border-b border-hairline px-3 py-2.5">
      <h2 className="min-w-0 flex-1 truncate px-1 font-display text-sm font-semibold text-ink">
        {title}
      </h2>

      {/*
        The chevrons point the way the edge is about to move: left to widen,
        right to put it back. A pair of states on one button rather than two
        buttons, and `aria-pressed` because it is a toggle — "which of these am I
        in" is not something an arrow tells you.
      */}
      <button
        type="button"
        onClick={onToggleExpand}
        aria-pressed={Boolean(expanded)}
        title={expanded ? 'Restore the panel’s width' : 'Expand this panel'}
        className={`flex h-8 w-8 items-center justify-center rounded-full transition-colors duration-200 ease-out-cubic ${
          expanded
            ? 'bg-clay/10 text-clay-ink'
            : 'text-muted hover:bg-subtle hover:text-ink'
        }`}
      >
        {expanded ? (
          <ChevronsRight size={15} strokeWidth={2} />
        ) : (
          <ChevronsLeft size={15} strokeWidth={2} />
        )}
        <span className="sr-only">
          {expanded ? 'Restore the panel’s width' : 'Expand this panel'}
        </span>
      </button>

      <button
        type="button"
        onClick={onTogglePin}
        aria-pressed={pinned}
        title={pinned ? 'Unpin this panel' : 'Pin this panel open'}
        className={`flex h-8 w-8 items-center justify-center rounded-full transition-colors duration-200 ease-out-cubic ${
          pinned
            ? 'bg-clay/10 text-clay-ink'
            : 'text-muted hover:bg-subtle hover:text-ink'
        }`}
      >
        {pinned ? <Pin size={15} strokeWidth={2} /> : <PinOff size={15} strokeWidth={2} />}
        <span className="sr-only">{pinned ? 'Unpin this panel' : 'Pin this panel open'}</span>
      </button>

      {/* The panel is a quick view; the page is still the thing that can be
          linked to and bookmarked, so it stays one click away. */}
      {page && (
        <Link
          to={page}
          title="Open as a full page"
          className="flex h-8 w-8 items-center justify-center rounded-full text-muted transition-colors duration-200 ease-out-cubic hover:bg-subtle hover:text-ink"
        >
          <Maximize2 size={15} strokeWidth={2} />
          <span className="sr-only">Open {title} as a full page</span>
        </Link>
      )}

      <button
        type="button"
        id="seller-panel-close"
        onClick={onClose}
        title="Close"
        className="flex h-8 w-8 items-center justify-center rounded-full text-muted transition-colors duration-200 ease-out-cubic hover:bg-subtle hover:text-ink"
      >
        <X size={16} strokeWidth={2} />
        <span className="sr-only">Close {title}</span>
      </button>
    </header>
  )

  const body = (
    <>
      <PanelGrab width={width} maxRem={maxRem} onResize={onResize} />
      {header}
      <div className="min-h-0 flex-1 overflow-y-auto p-4">{children}</div>
    </>
  )

  /*
    The width is an inline style rather than a class, and it has to be: it is a
    number the seller chose, and Tailwind cannot generate a class for a number
    that did not exist when the stylesheet was built. The flow classes stay.

    `maxWidth` is the stylesheet's copy of the ceiling `panelMaxRem` enforces in
    JavaScript. It is deliberate duplication, and cheap: it covers the frame
    before `useViewportWidth` has measured anything and the case of a stored
    width that was fine on a bigger screen than this one.
  */
  const style = {
    width: `${width}rem`,
    maxWidth: docked ? '62vw' : '92vw',
  }

  if (docked) {
    return (
      <aside
        id={regionId}
        aria-label={title}
        style={style}
        /*
          No `lg:` on any of this: the shell only renders the docked form when
          `isPanelDocked` says the viewport is wide enough, so a breakpoint here
          would be the same rule written twice — and the second copy is the one
          that goes stale when the first changes.
        */
        className="relative flex shrink-0 flex-col border-l border-hairline bg-raised sticky top-16 h-[calc(100dvh-4rem)]"
      >
        {body}
      </aside>
    )
  }

  return (
    <>
      {/*
        The scrim closes the panel and is not a button: it is decoration for a
        pointer, and a keyboard user has Escape. A full-screen "close" button in
        the tab order would be the first thing Tab reached, which is worse than
        useless.
      */}
      <div
        aria-hidden="true"
        onClick={onClose}
        className="fade-enter fixed inset-0 z-40 bg-page/60 backdrop-blur-sm"
      />

      <aside
        id={regionId}
        aria-label={title}
        style={style}
        /*
          Under the bar rather than over it — `top-16`, the same row the docked
          form starts at — for two reasons. The store's name and the five
          destinations stay visible, which is the context the panel exists to
          preserve; a drawer that covers the bar covers the answer to "where am
          I". And pinning then moves nothing: the two forms are the same
          rectangle, one `sticky` and one `fixed`, so toggling the pin does not
          also slide the panel up.
        */
        className="slip-enter fixed right-0 top-16 z-50 flex h-[calc(100dvh-4rem)] flex-col border-l border-hairline bg-raised shadow-premium"
      >
        {body}
      </aside>
    </>
  )
}

/**
 * The grab: the panel's inner edge, made draggable.
 *
 * A `role="separator"` with `tabIndex` is ARIA's **window splitter**, which is
 * exactly what this is — a divider between two regions that can be moved. The
 * alternative was making it a `button`, and that would have been a lie in the
 * other direction: this does not perform an action, it changes a boundary, and a
 * splitter announces the boundary's value, which is how a screen reader user
 * learns how wide the panel currently is.
 *
 * It is 8px wide so it can be hit, and it is *drawn* as a 1px hairline and a
 * short grip that both light up on hover or focus — 8px of invisible hit area is
 * a control nobody finds.
 *
 * `touch-none` because a drag that the browser reads as a scroll is not a drag,
 * and `preventDefault` on pointer down because without it the same gesture
 * starts a text selection across the panel and the seller ends up with the
 * notification list highlighted blue.
 */
/* One rem in pixels, for a tab or a document that has no computed style. */
function rootRem() {
  if (typeof window === 'undefined') return 16
  const size = Number.parseFloat(getComputedStyle(document.documentElement).fontSize)
  return Number.isFinite(size) && size > 0 ? size : 16
}

function PanelGrab({ width, maxRem, onResize }) {
  const [draft, setDraft] = useState(null)
  const drag = useRef(null)

  /*
    The root font size, read once rather than assumed. `rem` is the unit the
    whole panel is written in, so both the drag and the numbers this control
    announces have to convert in the same one — and a browser's own "larger text"
    setting changes what a rem is, which would make a hard-coded 16 drift from the
    layout as the panel got wider. Read on mount, because resizing the root font
    is a browser preference and not something that happens mid-session.
  */
  const [remPx] = useState(rootRem)

  /*
    The value being drawn: the live drag while there is one, the committed width
    otherwise. `?? ` rather than `||` on purpose — a draft of 0 would be a real
    value, and `||` would throw it away mid-gesture.
  */
  const shown = draft ?? width

  const onPointerDown = (event) => {
    // Left button only: a right-click here opens a context menu, and a
    // middle-click is a paste, and neither is a resize.
    if (event.pointerType === 'mouse' && event.button !== 0) return
    event.preventDefault()
    drag.current = { from: event.clientX, startRem: shown }
    event.currentTarget.setPointerCapture?.(event.pointerId)
    setDraft(shown)
  }

  const onPointerMove = (event) => {
    const active = drag.current
    if (!active) return
    // Towards the left is wider, because the panel is on the right: the pointer
    // follows the edge it is holding.
    const next = active.startRem + (active.from - event.clientX) / remPx
    setDraft(clampPanelWidth(next, maxRem))
  }

  /*
    One way out of a drag, used by release, by cancellation and by a lost capture
    — a drag that ends because the pointer left the window still has to land
    where the seller last put it, and the three of those are the same moment.

    The `draft` here is read from this render's closure, which is the one that
    attached the handler: the last `pointermove` re-rendered and re-attached it,
    so a release cannot commit a width from two moves ago.
  */
  const endDrag = () => {
    if (!drag.current) return
    drag.current = null
    /*
      Only when the width actually moved. A grab is 8px of edge and one of those
      pixels is easy to hit while reaching for the panel, and `onResize` ends an
      expansion — so committing an unchanged width would mean a stray click
      collapsing a panel somebody had expanded on purpose.
    */
    if (draft !== null && draft !== width) onResize(draft)
    setDraft(null)
  }

  const onKeyDown = (event) => {
    const next = panelWidthForKey({ key: event.key, width: shown, maxRem })
    // `null` means the key was not one of ours, and that is the point: Escape,
    // Tab and every letter have to keep doing what they were going to do.
    if (next === null) return
    event.preventDefault()
    onResize(next)
  }

  return (
    <div
      role="separator"
      aria-orientation="vertical"
      aria-label="Resize this panel"
      aria-valuenow={Math.round(shown * remPx)}
      aria-valuemin={Math.round(PANEL_WIDTH.min * remPx)}
      aria-valuemax={Math.round(maxRem * remPx)}
      tabIndex={0}
      title="Drag to resize"
      onPointerDown={onPointerDown}
      onPointerMove={onPointerMove}
      onPointerUp={endDrag}
      onPointerCancel={endDrag}
      onLostPointerCapture={endDrag}
      onKeyDown={onKeyDown}
      className="group absolute inset-y-0 -left-1 z-10 w-2 cursor-col-resize touch-none select-none"
    >
      {/* The hairline, sitting on the border the panel already draws. */}
      <span className="pointer-events-none absolute inset-y-0 left-1 w-px bg-transparent transition-colors duration-200 ease-out-cubic group-hover:bg-clay/60 group-active:bg-clay" />
      {/* The grip: what says this edge can be moved at all. */}
      <span className="pointer-events-none absolute left-0.5 top-1/2 h-10 w-1 -translate-y-1/2 rounded-full bg-card-edge/60 transition-colors duration-200 ease-out-cubic group-hover:bg-clay group-focus-visible:bg-clay group-active:bg-clay" />
    </div>
  )
}
