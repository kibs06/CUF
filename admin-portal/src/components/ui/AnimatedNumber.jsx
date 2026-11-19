import { useEffect, useRef, useState } from 'react'
import { useReducedMotion } from 'motion/react'

/**
 * Count-up number for stat cards: tweens from the previous value to the new one
 * in 700ms with an ease-out, and snaps instantly when the reader has asked for
 * reduced motion. `format` receives the interpolated value, so money can round
 * once at display time instead of flickering through fractions.
 */
export default function AnimatedNumber({ value, format = (v) => v }) {
  const reduce = useReducedMotion()
  const [display, setDisplay] = useState(value)
  const prevRef = useRef(value)

  useEffect(() => {
    const from = prevRef.current
    if (reduce || from === value) {
      prevRef.current = value
      setDisplay(value)
      return
    }
    const start = performance.now()
    const duration = 700
    let raf
    const tick = (now) => {
      const t = Math.min(1, (now - start) / duration)
      const eased = 1 - Math.pow(1 - t, 3)
      setDisplay(from + (value - from) * eased)
      if (t < 1) raf = requestAnimationFrame(tick)
      else prevRef.current = value
    }
    raf = requestAnimationFrame(tick)
    return () => cancelAnimationFrame(raf)
  }, [value, reduce])

  return <>{format(display)}</>
}
