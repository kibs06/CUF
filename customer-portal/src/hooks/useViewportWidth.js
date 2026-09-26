import { useEffect, useState } from 'react'

/**
 * The window's inner width, in pixels, or `null` where there is no window.
 *
 * The seller's panel can be dragged wider, and how wide it is *allowed* to be
 * depends on how much room there is — so the room has to be known as a number,
 * not as a yes/no. That is the difference between this and `useMediaQuery`, which
 * answers the one question its callers ask and answers it with a boolean.
 *
 * ## Why a listener, when nothing else here measures
 *
 * Because the alternative is worse. A dragged width can be clamped in CSS with
 * `max-width: 55vw`, and the panel would *look* right — but then the value the
 * drag handle reports to a screen reader (`aria-valuenow`, `aria-valuemax`) would
 * be a number the panel is not actually drawn at, and a seller pressing End would
 * land somewhere other than the widest it can go. Measuring is what keeps the
 * accessible name of a control true. The stylesheet still carries the same cap as
 * a backstop, because that one costs nothing and covers the frame before this
 * hook has an answer.
 *
 * `null` on a server, where there is no viewport to measure: callers treat it as
 * "assume there is room", which is what `panelMaxRem` does with it.
 */
export default function useViewportWidth() {
  const [width, setWidth] = useState(() =>
    typeof window === 'undefined' ? null : window.innerWidth,
  )

  useEffect(() => {
    /*
      The listener is not throttled: engines already coalesce `resize` to one
      event per frame, and the only work here is a `setState` that React batches
      anyway. A `requestAnimationFrame` guard would add a frame of lag to the one
      moment the value matters.
    */
    const onResize = () => setWidth(window.innerWidth)
    onResize()
    window.addEventListener('resize', onResize)
    return () => window.removeEventListener('resize', onResize)
  }, [])

  return width
}
