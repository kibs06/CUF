import { useRef, useState } from 'react'
import { GripVertical, X } from 'lucide-react'

import { dropIndexForPoint, moveImage } from '../../lib/productImages.js'

/**
 * A gallery the seller arranges by dragging a photo where they want it.
 *
 * ## Why the drag is hand-written rather than an HTML5 `draggable`
 *
 * The native attribute is a mouse-only API: on a phone — where a seller is
 * standing at a bench with the product in their other hand — nothing happens,
 * which is the whole audience for a photo ordering control. Pointer events are
 * one code path for mouse, touch and pen, and Chrome, Safari and Firefox all
 * support them.
 *
 * ## The grip, and why the drag does not start on the photo itself
 *
 * A tile that swallows a touch is a page that cannot be scrolled past it: the
 * drag needs `touch-action: none`, and applying that to the whole tile would make
 * the card a dead zone on a phone. So the drag starts on a grip button — the only
 * element that takes the touch — and the photo keeps scrolling the page under it.
 * The grip is always visible rather than revealed on hover, because a control a
 * touch screen never reveals is a control nobody finds.
 *
 * ## Keyboard, because a drag is not an accessible control
 *
 * The grip is a real button: focus it and `←`/`↑`/`→`/`↓` move the photo one place,
 * which is the same `onReorder` call the drop makes. The result is announced
 * through a status line, because a screen reader cannot see a tile move.
 *
 * **What it does not do:** it does not persist anything. A stored photo's new
 * order is a write (`saveProductImageOrder`) and a pending file's is just a list —
 * the two callers differ about that, and this component is the same grid in both.
 *
 * @param {object} props
 * @param {Array<{key:string, src:string, value:any}>} props.items in the order shown
 * @param {(items:Array) => void} props.onReorder the new order, as items
 * @param {(item:object) => void} [props.onRemove]
 * @param {(item:object, index:number) => string} [props.removeLabel]
 * @param {boolean} [props.disabled] while a write is in flight
 * @param {string} [props.coverLabel] drawn on the first tile, e.g. `Cover`
 */
export function PhotoOrderGrid({
  items = [],
  onReorder,
  onRemove,
  removeLabel,
  disabled = false,
  coverLabel = null,
}) {
  const [drag, setDrag] = useState(null)
  const [announcement, setAnnouncement] = useState('')
  const tiles = useRef(new Map())

  /* Measured at the moment of the move rather than cached: the grid can reflow
     (a photo is removed, the window is resized, a tile's caption wraps) between
     one pointer event and the next. */
  const rectsNow = () =>
    items.map((item) => tiles.current.get(item.key)?.getBoundingClientRect() ?? null)

  const move = (from, to) => {
    if (to === null || to === undefined || to === from) return
    setAnnouncement(`Photo ${from + 1} is now number ${to + 1}.`)
    onReorder?.(moveImage(items, from, to))
  }

  const startDrag = (event, index) => {
    if (disabled || items.length < 2) return
    // A right-click or middle-click is not a drag, and the button that carries a
    // touch or pen is always 0 on those pointer types.
    if (event.pointerType === 'mouse' && event.button !== 0) return
    event.preventDefault()
    event.currentTarget.setPointerCapture?.(event.pointerId)
    setDrag({ pointerId: event.pointerId, from: index, over: index })
  }

  const duringDrag = (event) => {
    if (!drag || event.pointerId !== drag.pointerId) return
    const over = dropIndexForPoint(rectsNow(), { x: event.clientX, y: event.clientY })
    if (over !== null && over !== drag.over) setDrag({ ...drag, over })
  }

  const endDrag = (event) => {
    if (!drag || event.pointerId !== drag.pointerId) return
    const { from, over } = drag
    event.currentTarget.releasePointerCapture?.(event.pointerId)
    setDrag(null)
    move(from, over)
  }

  const keyMove = (event, index) => {
    const step = { ArrowLeft: -1, ArrowUp: -1, ArrowRight: 1, ArrowDown: 1 }[event.key]
    if (!step || disabled || items.length < 2) return
    const to = index + step
    if (to < 0 || to >= items.length) return
    event.preventDefault()
    move(index, to)
  }

  return (
    <div className="space-y-2.5">
      <ul className="grid grid-cols-3 gap-2">
        {items.map((item, index) => (
          <li
            key={item.key}
            ref={(node) => {
              if (node) tiles.current.set(item.key, node)
              else tiles.current.delete(item.key)
            }}
            className={`group relative rounded-product ${
              drag?.from === index ? 'opacity-60' : ''
            } ${
              drag && drag.over === index && drag.from !== index
                ? 'ring-2 ring-clay ring-offset-1 ring-offset-raised'
                : ''
            }`}
          >
            <img
              src={item.src}
              alt=""
              draggable={false}
              className="aspect-square w-full select-none rounded-product object-cover"
            />

            {items.length > 1 && (
              <button
                type="button"
                disabled={disabled}
                onPointerDown={(event) => startDrag(event, index)}
                onPointerMove={duringDrag}
                onPointerUp={endDrag}
                onPointerCancel={endDrag}
                onKeyDown={(event) => keyMove(event, index)}
                aria-label={`Reorder photo ${index + 1} of ${items.length} — drag, or use the arrow keys`}
                className="absolute left-1 top-1 inline-flex h-6 w-6 cursor-grab touch-none items-center justify-center rounded-full bg-chrome/70 text-white opacity-80 transition-opacity duration-200 ease-out-cubic hover:opacity-100 focus-visible:opacity-100 active:cursor-grabbing disabled:cursor-not-allowed disabled:opacity-40"
              >
                <GripVertical className="h-3.5 w-3.5" aria-hidden="true" />
              </button>
            )}

            {index === 0 && coverLabel && (
              <span className="pointer-events-none absolute inset-x-0 bottom-0 bg-clay/90 py-0.5 text-center text-[10px] font-semibold uppercase tracking-wide text-ink-inverse">
                {coverLabel}
              </span>
            )}

            {onRemove && (
              <button
                type="button"
                disabled={disabled}
                onClick={() => onRemove(item)}
                aria-label={
                  removeLabel?.(item, index) ?? `Remove photo ${index + 1}`
                }
                className="absolute right-1 top-1 inline-flex h-6 w-6 items-center justify-center rounded-full bg-chrome/80 text-white transition-opacity duration-200 ease-out-cubic focus-visible:opacity-100 md:opacity-0 md:group-hover:opacity-100 disabled:cursor-not-allowed disabled:opacity-40"
              >
                <X className="h-3.5 w-3.5" aria-hidden="true" />
              </button>
            )}
          </li>
        ))}
      </ul>

      {/* The only way a screen reader learns that a photo moved. */}
      <span role="status" className="sr-only">
        {announcement}
      </span>
    </div>
  )
}
