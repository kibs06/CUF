/**
 * A menu that opens where you right-clicked.
 *
 * ## Why this exists rather than the browser's own menu
 *
 * The portal is a workspace: every row on it stands for something — an order, a
 * product, a thread — and the things a seller wants to do with that thing are
 * already written somewhere on another page. The browser's menu offers what it
 * can do with *the page* (Reload, Inspect, Save as…), which is never what was
 * meant. A menu that names the row's own actions is the shortest path between
 * seeing a problem and acting on it, and it costs the row no pixels — which
 * matters on the lists that are already seven controls wide.
 *
 * ## Right-click, and nothing else
 *
 * There is **no** "⋯" button. A per-row overflow menu is a thing a seller has to
 * hunt for on every row, and it competes for space in the same cell as the real
 * controls. Right-click is the gesture people already try on a list — and it is
 * additive: a row that has a pointer's menu still has its plain click, its
 * buttons and its links, all untouched.
 *
 * ## What replacing the browser's menu costs, and how this pays it back
 *
 * It takes two things away, and both are put back by the primitive itself, on
 * every menu, without a call site being able to forget them:
 *
 *   - **Copy link address** → *Copy link*, with the tick that says it worked.
 *   - **Open link in a new tab** → *Open in a new tab*, for the seller comparing
 *     two orders side by side.
 *
 * A menu that removed them would be a worse browser, not a better app; a menu
 * that has them is the browser's two useful entries plus the four that matter.
 * Both are derived from the `link` prop, so a surface supplies the URL once.
 *
 * ## The three ways it is dismissed, and the one it is not
 *
 * Escape, a pointer press outside, and scrolling all close it — a menu that only
 * closes by choosing something from it is a trap. **Focus is returned to the row
 * only on Escape**, which is the one dismissal where a keyboard user has not
 * already moved their attention somewhere else: stealing focus back after a click
 * elsewhere would yank it out from under whatever was clicked.
 *
 * ## The menu is measured, then placed
 *
 * A menu's size is its items, and it is placed from the pointer's own
 * coordinates, so it is rendered hidden, measured, and positioned in a layout
 * effect — before paint, so nothing is ever seen in the wrong place. The
 * arithmetic is `contextMenuPosition` (tested on its own); the effect writes
 * straight to the node's style rather than through state, which is what keeps a
 * re-render from re-running placement forever.
 *
 * Keyboard invocation (Shift+F10, or the menu key) carries no pointer position,
 * so the menu opens at the row's own bottom-left corner instead of at 0,0 — the
 * placement the ARIA pattern asks for, and the only one that makes sense for a
 * user who never moved a mouse.
 *
 * ## Items
 *
 * An item is one of three things, and the call site picks by shape:
 *
 *   - `{ to }` — a route, rendered as a real `Link`, so middle-click and
 *     cmd-click open it in a tab the way a link should. Add `newTab: true` for
 *     the items that should *leave* the workspace ("View on your storefront").
 *   - `{ onSelect }` — an action that already exists on the surface.
 *   - `{ copy }` — a string to put on the clipboard, with the same tick.
 *
 * `tone: 'danger'` tints the row crimson for the destructive ones. Nothing here
 * confirms a destructive action: this is a menu, and the surfaces that delete
 * things already open a `ConfirmDialog` for it — an item that fires one is
 * correct, an item that deletes on its own is not this component's job to
 * prevent, so call sites do not put one here.
 */
import { useCallback, useEffect, useLayoutEffect, useRef, useState } from 'react'
import { createPortal } from 'react-dom'
import { Link } from 'react-router-dom'
import { Check, Copy, ExternalLink } from 'lucide-react'

import { contextMenuPosition } from '../../lib/contextMenuRules.js'

/** All the menu's rows share this, so no item can drift from the others. */
const ITEM_BASE =
  'flex w-full items-center gap-2.5 px-3 py-2 text-left text-sm transition-colors duration-200 ease-out-cubic'

const LABEL_MUTED = 'text-muted-strong hover:bg-subtle hover:text-ink'

/**
 * Right-click handling for one row, plus the menu it opens.
 *
 * @param {object} options
 * @param {Array}  options.items  Menus items — see the file docblock.
 * @param {string} [options.link] The row's absolute or app-relative URL; its
 *                                presence is what adds *Copy link* and *Open in
 *                                a new tab*.
 * @param {string} [options.label] What the menu is for, for a screen reader.
 * @returns {{ onContextMenu: Function, menu: object }} Spread the handler on the
 *          row and render `menu` beside it. The menu portals itself to the body,
 *          so where it is rendered in the row does not matter — only that it is
 *          rendered.
 */
export function useContextMenu({ items = [], link = null, label = 'Actions' } = {}) {
  const [at, setAt] = useState(null)

  const onContextMenu = useCallback((event) => {
    /*
      A text field keeps the browser's own menu, always. Paste, select all and
      spelling live there, and no list row's actions are worth them — the row's
      handler is on a wrapper, so without this guard right-clicking a stock input
      would offer "Open product" and take away paste. `[data-native-menu]` is the
      same escape hatch for anything else that needs the real menu.
    */
    if (
      event.target?.closest?.(
        'input, textarea, select, [contenteditable="true"], [data-native-menu]',
      )
    ) {
      return
    }

    event.preventDefault()
    const trigger = event.currentTarget
    const rect = trigger?.getBoundingClientRect?.()

    /*
      A keyboard invocation reports 0,0 rather than a point, because there was no
      pointer to report. Falling back to the row's bottom-left corner is what
      keeps Shift+F10 opening the menu somewhere a user can actually see.
    */
    const keyboard = !event.clientX && !event.clientY && rect
    setAt({
      x: keyboard ? rect.left : event.clientX,
      y: keyboard ? rect.bottom : event.clientY,
      trigger,
    })
  }, [])

  const menu = at ? (
    <ContextMenu
      items={items}
      link={link}
      label={label}
      x={at.x}
      y={at.y}
      trigger={at.trigger}
      onClose={() => setAt(null)}
    />
  ) : null

  return { onContextMenu, menu }
}

/**
 * The menu itself. Mounted only while open, so the closed state is the absent
 * one and there is no hidden layer to keep in sync with the data behind it.
 */
export function ContextMenu({
  items = [],
  link = null,
  label = 'Actions',
  x = 0,
  y = 0,
  trigger = null,
  onClose,
}) {
  const ref = useRef(null)
  const copyTimer = useRef(null)
  /** Which copy item is showing its result: `{ id, ok }`. */
  const [copyResult, setCopyResult] = useState(null)

  /*
    The browser's own two useful entries are appended here rather than asked for
    at every call site: they belong to the *menu*, not to the row — the row just
    says where it lives.
  */
  const linkEntries = link
    ? [
        {
          id: '__copy-link',
          kind: 'copy',
          label: 'Copy link',
          copy: absoluteUrl(link),
          Icon: Copy,
          divider: true,
        },
        {
          id: '__open-tab',
          kind: 'open',
          label: 'Open in a new tab',
          url: absoluteUrl(link),
          Icon: ExternalLink,
        },
      ]
    : []
  const entries = [...items.filter(Boolean), ...linkEntries]

  const enabled = () =>
    Array.from(ref.current?.querySelectorAll('[role="menuitem"]') ?? []).filter(
      (node) => node.getAttribute('aria-disabled') !== 'true',
    )

  /*
    Measure, then place — before paint, so nothing is ever seen in the wrong
    place — and focus the first item in the same pass, because a menu is entered
    rather than merely shown: Shift+F10 should land inside it, and an arrow key
    pressed immediately should have somewhere to move from.
  */
  useLayoutEffect(() => {
    const node = ref.current
    if (!node) return
    const rect = node.getBoundingClientRect()
    const placed = contextMenuPosition({
      x,
      y,
      width: rect.width,
      height: rect.height,
      viewport: { width: window.innerWidth, height: window.innerHeight },
    })
    node.style.left = `${placed.left}px`
    node.style.top = `${placed.top}px`
    node.style.visibility = 'visible'
    enabled()[0]?.focus({ preventScroll: true })
  }, [x, y])

  const restoreFocus = useCallback(() => {
    trigger?.focus?.({ preventScroll: true })
  }, [trigger])

  const dismiss = useCallback(
    (restore = false) => {
      if (restore) restoreFocus()
      onClose?.()
    },
    [onClose, restoreFocus],
  )

  useEffect(() => {
    /*
      One named handler per listener, and the same reference removed again. A
      bare arrow passed to `addEventListener` and a different one passed to
      `removeEventListener` is how a menu leaks a listener every time it opens —
      and a `scroll` or `resize` on the window is exactly what a menu should not
      leave behind.
    */
    const close = () => dismiss()
    const onPointerDown = (event) => {
      if (!ref.current?.contains(event.target)) dismiss()
    }
    const onKeyDown = (event) => {
      if (event.key === 'Escape') {
        event.preventDefault()
        dismiss(true)
      } else if (event.key === 'Tab') {
        // Leaving the menu is leaving it: focus moves on, the menu does not
        // hang over the page it was opened from.
        dismiss(true)
      }
    }

    document.addEventListener('pointerdown', onPointerDown, true)
    document.addEventListener('keydown', onKeyDown)
    window.addEventListener('resize', close)
    window.addEventListener('blur', close)
    // Capture, because a menu over a scrolled list is positioned from a point
    // that has moved — including when the scroll happens in an inner container.
    window.addEventListener('scroll', close, true)
    return () => {
      document.removeEventListener('pointerdown', onPointerDown, true)
      document.removeEventListener('keydown', onKeyDown)
      window.removeEventListener('resize', close)
      window.removeEventListener('blur', close)
      window.removeEventListener('scroll', close, true)
      if (copyTimer.current) window.clearTimeout(copyTimer.current)
    }
  }, [dismiss])

  const onMenuKeyDown = (event) => {
    const rows = enabled()
    if (rows.length === 0) return
    const index = rows.indexOf(document.activeElement)
    const go = (next) => {
      event.preventDefault()
      rows[next]?.focus({ preventScroll: true })
    }

    if (event.key === 'ArrowDown') go(index < 0 ? 0 : (index + 1) % rows.length)
    else if (event.key === 'ArrowUp') go(index <= 0 ? rows.length - 1 : index - 1)
    else if (event.key === 'Home') go(0)
    else if (event.key === 'End') go(rows.length - 1)
  }

  /**
   * Put text on the clipboard, and **show that it worked** before closing.
   *
   * A menu that vanishes on a copy leaves the seller with no evidence and an
   * empty paste ahead of them; the tick and the held-open 900ms are the receipt.
   * A refused clipboard (a denied permission, an insecure origin) keeps the menu
   * open and says so, which is the one case where the user still has a fallback
   * worth reaching for.
   */
  const runCopy = async (entry) => {
    try {
      await navigator.clipboard.writeText(entry.copy)
      setCopyResult({ id: entry.id, ok: true })
      copyTimer.current = window.setTimeout(() => onClose?.(), 900)
    } catch {
      setCopyResult({ id: entry.id, ok: false })
    }
  }

  const body = (
    <div
      ref={ref}
      role="menu"
      aria-label={label}
      onKeyDown={onMenuKeyDown}
      style={{ left: x, top: y, visibility: 'hidden' }}
      className="drop-enter fixed z-[60] max-h-[min(24rem,100vh-1rem)] w-56 origin-top-left overflow-y-auto overscroll-contain rounded-card border border-hairline bg-raised py-1 shadow-card-lift"
    >
      {entries.map((entry) => {
        const result = copyResult?.id === entry.id ? copyResult : null

        return (
          <div key={entry.id}>
            {entry.divider && <div className="my-1 h-px bg-hairline-soft" />}
            <MenuItem
              entry={entry}
              result={result}
              disabled={Boolean(entry.disabled) || Boolean(result?.ok)}
              onActivate={(event) => {
                if (entry.kind === 'copy') {
                  event.preventDefault()
                  void runCopy(entry)
                  return
                }
                // Navigation closes behind itself; the route change is the
                // feedback, so there is no tick to wait for.
                onClose?.()
              }}
              onSelect={entry.onSelect}
            />
          </div>
        )
      })}
    </div>
  )

  return createPortal(body, document.body)
}

/** One row: a link when it goes somewhere, a button when it does something. */
function MenuItem({ entry, result, disabled, onActivate, onSelect }) {
  const Icon = result?.ok ? Check : entry.Icon
  const classes = [
    ITEM_BASE,
    disabled
      ? 'cursor-default text-muted'
      : entry.tone === 'danger'
        ? 'text-crimson hover:bg-crimson/10'
        : LABEL_MUTED,
  ].join(' ')

  const content = (
    <>
      {Icon ? (
        <Icon className="h-4 w-4 shrink-0" aria-hidden="true" />
      ) : (
        <span aria-hidden="true" className="h-4 w-4 shrink-0" />
      )}
      <span className="min-w-0 flex-1 truncate">
        {result ? (result.ok ? 'Copied' : 'Couldn’t copy') : entry.label}
      </span>
    </>
  )

  if (entry.kind === 'open' && entry.url) {
    return (
      <a
        role="menuitem"
        href={entry.url}
        target="_blank"
        rel="noreferrer"
        className={classes}
        onClick={onActivate}
      >
        {content}
      </a>
    )
  }

  /*
    `newTab` items are anchors rather than `Link`s even though they carry a
    route: the point of one is that it takes you out of the workspace (the
    storefront, a receipt), and a router navigation would swap the page under the
    seller instead of leaving the one they were working on open behind it.
  */
  if (entry.to && entry.newTab) {
    return (
      <a
        role="menuitem"
        href={absoluteUrl(entry.to)}
        target="_blank"
        rel="noreferrer"
        className={classes}
        onClick={onActivate}
      >
        {content}
      </a>
    )
  }

  if (entry.to) {
    return (
      <Link
        role="menuitem"
        to={entry.to}
        className={classes}
        onClick={onActivate}
      >
        {content}
      </Link>
    )
  }

  return (
    <button
      type="button"
      role="menuitem"
      disabled={disabled}
      aria-disabled={disabled || undefined}
      className={classes}
      onClick={
        onSelect
          ? (event) => {
              onActivate(event)
              onSelect()
            }
          : onActivate
      }
    >
      {content}
    </button>
  )
}

/** A row's route, as an absolute URL — what a clipboard and a new tab want. */
function absoluteUrl(to) {
  if (/^https?:\/\//i.test(to)) return to
  if (typeof window === 'undefined') return to
  return new URL(to, window.location.origin).toString()
}

export default ContextMenu
