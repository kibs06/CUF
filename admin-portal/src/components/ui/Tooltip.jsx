import { cloneElement, useEffect, useRef, useState } from 'react'
import { createPortal } from 'react-dom'

/**
 * A short explanation on hover or keyboard focus.
 *
 * The bubble is portalled so a tooltip on the last column of a table or the last
 * row of a modal is not clipped by the scrolling box it lives in, and clamped to
 * the viewport so it never hangs off an edge.
 *
 * When the child is a plain DOM element (a `<button>`, `<input>`, `<select>`,
 * `<a>`…) the handlers are cloned onto it rather than wrapped, so adding a
 * tooltip never changes a control's layout or width — important for the
 * full-width search fields and the date pickers. Anything else (a component
 * without a forwarded ref) gets an inline-flex wrapper instead.
 *
 * `label` is plain text on purpose: these explain a control in a sentence, they
 * are not rich content.
 */
export default function Tooltip({ label, children, side = 'top', delay = 180 }) {
  const anchor = useRef(null)
  const timer = useRef(null)
  const [at, setAt] = useState(null)
  const id = useRef(`tip-${Math.random().toString(36).slice(2, 9)}`)

  const show = () => {
    window.clearTimeout(timer.current)
    timer.current = window.setTimeout(() => {
      const rect = anchor.current?.getBoundingClientRect()
      if (!rect) return
      const half = 120
      const x = Math.min(
        Math.max(rect.left + rect.width / 2, half + 8),
        window.innerWidth - half - 8,
      )
      setAt({ x, y: side === 'top' ? rect.top : rect.bottom })
    }, delay)
  }

  const hide = () => {
    window.clearTimeout(timer.current)
    setAt(null)
  }

  useEffect(() => () => window.clearTimeout(timer.current), [])

  if (!label) return children

  const bubble = at
    ? createPortal(
        <span
          role="tooltip"
          id={id.current}
          style={{ left: at.x, top: at.y }}
          className={`pointer-events-none fixed z-[90] w-max max-w-[260px] -translate-x-1/2 rounded-lg bg-secondary px-2.5 py-1.5 text-[11.5px] font-medium leading-snug text-white shadow-lg ${
            side === 'top' ? '-translate-y-[calc(100%+8px)]' : 'translate-y-2'
          }`}
        >
          {label}
        </span>,
        document.body,
      )
    : null

  const isDomElement = typeof children?.type === 'string'

  if (isDomElement) {
    const child = cloneElement(children, {
      ref: (node) => {
        anchor.current = node
        const { ref } = children
        if (typeof ref === 'function') ref(node)
        else if (ref && typeof ref === 'object') ref.current = node
      },
      'aria-describedby': at ? id.current : undefined,
      onMouseEnter: (event) => {
        children.props.onMouseEnter?.(event)
        show()
      },
      onMouseLeave: (event) => {
        children.props.onMouseLeave?.(event)
        hide()
      },
      onFocus: (event) => {
        children.props.onFocus?.(event)
        show()
      },
      onBlur: (event) => {
        children.props.onBlur?.(event)
        hide()
      },
    })
    return (
      <>
        {child}
        {bubble}
      </>
    )
  }

  return (
    <>
      <span
        ref={anchor}
        onMouseEnter={show}
        onMouseLeave={hide}
        onFocusCapture={show}
        onBlurCapture={hide}
        className="inline-flex max-w-full"
      >
        {children}
      </span>
      {bubble}
    </>
  )
}
