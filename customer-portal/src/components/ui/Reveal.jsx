import { motion } from 'motion/react'

import { DURATION, EASE_OUT_CUBIC, useTransitionTiming } from '../motion/transitions'

/**
 * Fades content up as it scrolls into view.
 *
 * `once: true` is not an optimisation, it is the whole design: content that
 * re-animates every time it scrolls back into view turns a page the customer is
 * reading into a page that keeps moving under them. It plays once, then the
 * content is simply there.
 *
 * The viewport margin is negative so a section has already begun its fade
 * slightly *before* it reaches the fold — otherwise the first thing a customer
 * sees is an empty box snapping into place.
 */
export default function Reveal({
  children,
  delay = 0,
  y = 14,
  className = '',
  as = 'div',
}) {
  const { d } = useTransitionTiming()
  const Motion = motion[as] ?? motion.div

  return (
    <Motion
      className={className}
      initial={{ opacity: 0, y }}
      whileInView={{ opacity: 1, y: 0 }}
      viewport={{ once: true, margin: '-80px' }}
      transition={{ duration: d(DURATION.slow), ease: EASE_OUT_CUBIC, delay: d(delay) }}
    >
      {children}
    </Motion>
  )
}
