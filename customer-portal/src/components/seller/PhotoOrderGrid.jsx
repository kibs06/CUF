import { useRef, useState } from 'react'
import { motion, useReducedMotion } from 'motion/react'
import { GripVertical, X } from 'lucide-react'

import { dropIndexForPoint, moveImage } from '../../lib/productImages.js'

/**
 * A gallery the seller arranges by dragging a photo where they want it.
 *
 * ## What the drag looks like, and why each part of it is there
 *
 * A drag has to say three things at once, and the picture answers all of them
 * without a caption:
 *
 *  1. **Which photo am I holding?** The tile lifts — `scale-1.06` under
 *     `shadow-card-lift`, the portal's own hover-lift shadow, so the photo reads as
 *     the same surface raised rather than a different card arriving — and it follows
 *     the pointer, held from the grip that started the drag.
 *  2. **Where did it come from?** The slot it left keeps a dashed outline, so the
 *     grid does not appear to have lost a tile while one is in the air.
 *  3. **Where will it land?** The slot it would drop into is ringed in clay.
 *
 * On release the lift ends and the tile glides into place (the transform transitions
 * back to nothing), the tiles it passed animate to their new slots (`layout`), and a
 * seller who has asked their system for less motion gets the same moves with no
 * tween at all.
 *
 * ## Why the lift is a wrapper inside the tile rather than the tile itself
 *
 * Because the tile's own rectangle is the measurement. The drop index is computed
 * from `getBoundingClientRect()` of every tile (`dropIndexForPoint`), and a transform
 * on the tile would move its rect with the pointer — the dragged photo would then
 * always be "under" itself and no other slot could ever win. So the `<li>` stays
 * exactly where the grid put it, and the layer inside it is what travels.
 *
 * ## Why the drag is hand-written rather than an HTML5 `draggable`
 *
 * The native attribute is a mouse-only API: on a phone — where a seller is standing
 * at a bench with the product in their other hand — nothing happens, which is the
 * whole audience for a photo ordering control. Pointer events are one code path for
 * mouse, touch and pen, and Chrome, Safari and Firefox all support them.
 *
 * ## The grip, and why the drag does not start on the photo itself
 *
 * A tile that swallows a touch is a page that cannot be scrolled past it: the drag
 * needs `touch-action: none`, and applying that to the whole tile would make the card
 * a dead zone on a phone. So the drag starts on a grip button — the only element that
 * takes the touch — and the photo keeps scrolling the page under it. The grip is
 * always visible rather than revealed on hover, because a control a touch screen
 * never reveals is a control nobody finds.
 *
 * ## Keyboard, because a drag is not an accessible control
 *
 * The grip is a real button: focus it and `←`/`↑`/`→`/`↓` move the photo one place,
 * which is the same `onReorder` call the drop makes. The result is announced through
 * a status line, because a screen reader cannot see a tile move.
 *
 * **What it does not do:** it does not persist anything. A stored photo's new order
 * is a write (`saveProductImageOrder`) and a pending file's is just a list — the two
 * callers differ about that, and this component is the same grid in both.
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
  const reducedMotion = useReducedMotion()
  /** The drag in flight: which tile, where it is now, and where it would land. */
  const [drag, setDrag] = useState(null)
  const [announcement, setAnnouncement] = useState('')
  const tiles = useRef(new Map())

  /* Measured at the moment of the move rather than cached: the grid can reflow
     (a photo is removed, the window is resized, a tile's caption wraps) between
     one pointer event and the next. The lifted tile's own rect is its slot's,
     which is exactly what the drop maths needs — see the class doc. */
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
    setDrag({
      pointerId: event.pointerId,
      from: index,
      over: index,
      // Where the pointer was when it took hold, so the tile travels with it
      // rather than jumping to it.
      originX: event.clientX,
      originY: event.clientY,
      dx: 0,
      dy: 0,
    })
  }

  const duringDrag = (event) => {
    if (!drag || event.pointerId !== drag.pointerId) return
    const over = dropIndexForPoint(rectsNow(), { x: event.clientX, y: event.clientY })
    setDrag({
      ...drag,
      dx: event.clientX - drag.originX,
      dy: event.clientY - drag.originY,
      // A drop that cannot be measured keeps the last place it could be, rather
      // than springing back to its own slot mid-drag.
      over: over === null ? drag.over : over,
    })
  }

  const endDrag = (event) => {
    if (!drag || event.pointerId !== drag.pointerId) return
    const { from, over } = drag
    event.currentTarget.releasePointerCapture?.(event.pointerId)
    /* Dropping the drag state is what lets go: the tile's transform goes back to
       nothing, the transition carries it into its new slot, and the order write
       starts from `move` below. */
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
        {items.map((item, index) => {
          const lifted = drag?.from === index
          const targeted = Boolean(drag) && drag.over === index && drag.from !== index

          return (
            <motion.li
              key={item.key}
              // The tiles a drag pushes along slide into their new slots instead of
              // snapping there. Motion is the seller's to keep: `useReducedMotion`
              // turns the tween off and leaves the moves themselves alone.
              layout={!reducedMotion}
              ref={(node) => {
                if (node) tiles.current.set(item.key, node)
                else tiles.current.delete(item.key)
              }}
              style={lifted ? { zIndex: 30 } : undefined}
              // `group` so the X can stay hidden until the tile is hovered on a
              // pointer device, while a touch screen sees it always.
              className={`group relative rounded-product ${
                targeted ? 'ring-2 ring-clay ring-offset-1 ring-offset-raised' : ''
              }`}
            >
              {/* Where the photo came out of — drawn under the lifted layer. */}
              {lifted && (
                <div
                  className="absolute inset-0 rounded-product border-2 border-dashed border-card-edge"
                  aria-hidden="true"
                />
              )}

              {/* The layer that travels: `transition-transform` is what turns the
                  drop back into a glide, and `transition: none` while the drag is
                  live is what keeps it under the pointer instead of trailing it. */}
              <div
                className={
                  reducedMotion ? '' : 'transition-transform duration-200 ease-out-cubic'
                }
                style={
                  lifted
                    ? {
                        transform: `translate3d(${drag.dx}px, ${drag.dy}px, 0)`,
                        transition: 'none',
                        zIndex: 30,
                      }
                    : undefined
                }
              >
                <div
                  className={`relative overflow-hidden rounded-product ${
                    reducedMotion ? '' : 'transition-transform duration-150 ease-out-cubic'
                  } ${lifted ? 'scale-[1.06] shadow-card-lift' : ''}`}
                >
                  <img
                    src={item.src}
                    alt=""
                    draggable={false}
                    className="aspect-square w-full select-none object-cover"
                  />

                  {index === 0 && coverLabel && (
                    <span className="pointer-events-none absolute inset-x-0 bottom-0 bg-clay/90 py-0.5 text-center text-[10px] font-semibold uppercase tracking-wide text-ink-inverse">
                      {coverLabel}
                    </span>
                  )}
                </div>

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

                {onRemove && (
                  <button
                    type="button"
                    disabled={disabled}
                    onClick={() => onRemove(item)}
                    aria-label={removeLabel?.(item, index) ?? `Remove photo ${index + 1}`}
                    className="absolute right-1 top-1 inline-flex h-6 w-6 items-center justify-center rounded-full bg-chrome/80 text-white transition-opacity duration-200 ease-out-cubic focus-visible:opacity-100 md:opacity-0 md:group-hover:opacity-100 disabled:cursor-not-allowed disabled:opacity-40"
                  >
                    <X className="h-3.5 w-3.5" aria-hidden="true" />
                  </button>
                )}
              </div>
            </motion.li>
          )
        })}
      </ul>

      {/* The only way a screen reader learns that a photo moved. */}
      <span role="status" className="sr-only">
        {announcement}
      </span>
    </div>
  )
}
