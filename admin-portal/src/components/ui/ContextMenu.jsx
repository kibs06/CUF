import { useEffect, useLayoutEffect, useRef, useState } from 'react'
import { createPortal } from 'react-dom'

/**
 * A right-click menu.
 *
 * Rendered in a portal at the pointer's viewport coordinates, then nudged back
 * inside the window if it would hang off an edge — a menu opened on the last
 * row of a long table is the normal case, not an edge case. Closes on outside
 * click, Escape, scroll and resize, because a menu pinned to a pixel position
 * is wrong the moment the page moves under it.
 *
 * `items` is a flat list of `{ label, icon, onSelect }` and `{ separator: true }`.
 */
export default function ContextMenu({ position, items, onClose, label = 'Row actions' }) {
  const ref = useRef(null)
  const [pos, setPos] = useState(position)

  useLayoutEffect(() => {
    setPos(position)
    const node = ref.current
    if (!node || !position) return
    const rect = node.getBoundingClientRect()
    const pad = 8
    const left = Math.min(position.x, window.innerWidth - rect.width - pad)
    const top = Math.min(position.y, window.innerHeight - rect.height - pad)
    setPos({ x: Math.max(pad, left), y: Math.max(pad, top) })
  }, [position])

  useEffect(() => {
    const onPointerDown = (event) => {
      if (!ref.current?.contains(event.target)) onClose()
    }
    const onKeyDown = (event) => {
      if (event.key === 'Escape') onClose()
    }
    window.addEventListener('mousedown', onPointerDown)
    window.addEventListener('keydown', onKeyDown)
    window.addEventListener('scroll', onClose, true)
    window.addEventListener('resize', onClose)
    return () => {
      window.removeEventListener('mousedown', onPointerDown)
      window.removeEventListener('keydown', onKeyDown)
      window.removeEventListener('scroll', onClose, true)
      window.removeEventListener('resize', onClose)
    }
  }, [onClose])

  if (!position || !pos) return null

  return createPortal(
    <div
      ref={ref}
      role="menu"
      aria-label={label}
      style={{ top: pos.y, left: pos.x }}
      className="admin-3d-float fixed z-[80] w-60 overflow-hidden rounded-xl border border-border bg-card py-1 shadow-xl"
    >
      {items.filter(Boolean).map((item, index) =>
        item.separator ? (
          <div key={`sep-${index}`} className="my-1 h-px bg-border" role="separator" />
        ) : (
          <button
            key={item.label}
            type="button"
            role="menuitem"
            onClick={() => {
              onClose()
              item.onSelect()
            }}
            className="flex w-full items-center gap-2.5 px-3 py-2 text-left text-[12.5px] text-ink transition-colors hover:bg-canvas focus:bg-canvas focus:outline-none"
          >
            {item.icon && <item.icon size={14} className="shrink-0 text-muted" aria-hidden="true" />}
            <span className="truncate">{item.label}</span>
            {item.hint && <span className="ml-auto shrink-0 text-[10.5px] text-muted">{item.hint}</span>}
          </button>
        ),
      )}
    </div>,
    document.body,
  )
}
