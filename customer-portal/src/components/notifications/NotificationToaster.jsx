import { useCallback, useEffect, useRef, useState } from 'react'
import { AnimatePresence, motion } from 'motion/react'
import { Link } from 'react-router-dom'
import { Bell, X } from 'lucide-react'

import { DURATION, EASE_OUT_CUBIC, useTransitionTiming } from '../motion/transitions.js'

/**
 * Where the toasts sit, as one fixed slot per corner.
 *
 * Below `sm` every slot is the full width between the page gutters, because a
 * 320px card pinned to the right of a 360px phone is a card that hangs off the
 * screen. `sm:w-80` (the prototype's 320px) is the desktop width, and it is a
 * *maximum* width rather than a fixed one so a long store name still truncates
 * instead of pushing the card wider.
 *
 * There is no `center`: a toast in the middle of the page is a modal that
 * forgot to dim the background, and this component exists to announce something
 * without taking the page away.
 */
const POSITIONS = {
  'bottom-right': 'bottom-5 left-4 right-4 sm:left-auto sm:right-5 sm:w-80',
  'bottom-left': 'bottom-5 left-4 right-4 sm:right-auto sm:left-5 sm:w-80',
  'top-right': 'top-5 left-4 right-4 sm:left-auto sm:right-5 sm:w-80',
  'top-left': 'top-5 left-4 right-4 sm:right-auto sm:left-5 sm:w-80',
}

/**
 * The toast centre — a notification that arrives while you are already looking
 * at something else, shown in the corner.
 *
 * ## One at a time, not a stack
 *
 * The prototype this is ported from stacked up to three cards. This shows one
 * and then the next, and the difference is not taste: a stack is a second
 * notification list, and the portal already has one — with filters, per-kind
 * unread counts, read/unread and undo — at `/notifications` and
 * `/seller/notifications`. What a toast can add to that is immediacy, and three
 * cards arriving together is not immediate; it is a queue drawn as a pile.
 *
 * ## It owns exactly one piece of state: what it has shown
 *
 * The customer feed refetches on window focus, so the same rows come back with
 * the same ids. Without a memory, an unread notification would re-announce
 * itself every time the customer came back to the tab. That memory is a `Set` of
 * ids in a ref — never rendered — and it belongs here rather than in the rules
 * module (which stays pure and testable) or in the host (which is mounted,
 * unmounted and remounted by routing). This component is mounted once by a
 * shell, so its memory lives exactly as long as the session does.
 *
 * ## When the animation is driven by JS, and why that is allowed here
 *
 * `PageTransition` deliberately avoids JS-driven entrances: a stalled frame loop
 * used to leave the site showing an empty page. A toast is the opposite risk —
 * if the animation never runs, the customer misses a toast and reads the same
 * notification on the feed, which is on screen the whole time. So the entrance
 * is worth having (the blur and the small rise are what make a card feel
 * *delivered* rather than pasted into the corner) and the failure is harmless.
 *
 * `mode="popLayout"` rather than `mode="wait"`: waiting for the outgoing card to
 * finish before drawing the next would gate the second notification on an
 * animation completing, which is the exact shape of the bug `PageTransition`
 * documents. The leaving card is pulled out of the flow instead, so the next one
 * can arrive immediately.
 *
 * ## Reduced motion
 *
 * Durations come from `useTransitionTiming` and collapse to zero; the blur is
 * dropped with them, because a 6px filter that snaps to none in a single frame
 * is a flash rather than a transition.
 *
 * ## Screen readers
 *
 * `aria-live="polite"` is on the slot, not on the card, so arriving text is
 * announced without stealing focus. Collapsing a toast announces nothing —
 * removals are not spoken — which is the right amount of noise for something
 * that was already read.
 */
export default function NotificationToaster({
  items = [],
  onOpen,
  position = 'bottom-right',
  visibleMs = 6000,
  allowDismiss = true,
  className = '',
}) {
  const { d, reduce } = useTransitionTiming()
  const [queue, setQueue] = useState([])
  const shown = useRef(new Set())

  /*
    Fold the candidates the host hands over into the queue, once each. The host
    can hand the same rows over on every refetch — that is the point of the
    `shown` set — and it can hand over rows that are already queued behind the
    one on screen, which is why the check is against everything remembered
    rather than against the queue.
  */
  useEffect(() => {
    const fresh = (items ?? []).filter((item) => item?.id && !shown.current.has(item.id))
    if (fresh.length === 0) return

    for (const item of fresh) shown.current.add(item.id)
    setQueue((current) => [...current, ...fresh])
  }, [items])

  const current = queue[0] ?? null

  const dismiss = useCallback((id) => {
    setQueue((current) => current.filter((item) => item.id !== id))
  }, [])

  const open = useCallback(
    (item) => {
      onOpen?.(item)
      dismiss(item.id)
    },
    [onOpen, dismiss],
  )

  /*
    Six seconds: the card is two short lines and a label, and that is long
    enough to read it twice and short enough that a burst of three does not hold
    the corner hostage. `visibleMs = 0` turns the timer off entirely, leaving the
    toast up until it is dismissed or clicked.
  */
  useEffect(() => {
    if (!current || !(visibleMs > 0)) return undefined

    const timer = window.setTimeout(() => dismiss(current.id), visibleMs)
    return () => window.clearTimeout(timer)
  }, [current, visibleMs, dismiss])

  const rise = (position ?? '').startsWith('top') ? -16 : 16
  const entering = {
    opacity: 0,
    y: rise,
    scale: 0.96,
    filter: reduce ? 'blur(0px)' : 'blur(6px)',
  }
  const resting = { opacity: 1, y: 0, scale: 1, filter: 'blur(0px)' }

  return (
    <div
      aria-live="polite"
      className={`pointer-events-none fixed z-50 ${
        POSITIONS[position] ?? POSITIONS['bottom-right']
      } ${className}`}
    >
      <AnimatePresence mode="popLayout" initial={false}>
        {current && (
          <motion.div
            key={current.id}
            initial={entering}
            animate={resting}
            exit={entering}
            transition={{ duration: d(DURATION.base), ease: EASE_OUT_CUBIC }}
            className="pointer-events-auto will-change-transform"
          >
            <Toast
              item={current}
              allowDismiss={allowDismiss}
              onOpen={() => open(current)}
              onDismiss={() => dismiss(current.id)}
            />
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  )
}

/**
 * One card.
 *
 * The layout is the feed card's, deliberately — icon chip, title, relative time,
 * body — because this is the same notification seen from a different place, and
 * a customer who reads it here should recognise it there. What changes is the
 * weight: no previews, no unread rule, a lifted shadow, and a close button that
 * is always drawn (a control only revealed on hover does not exist on a touch
 * screen, and this one sits in the corner of a page the thumb is already using).
 *
 * The whole card is a stretched `Link` when there is somewhere to go, with the
 * close button outside it and above it — a `button` inside an `a` is invalid
 * HTML, and a tap on "dismiss" would also navigate. When there is nowhere to go
 * the card is a panel: the customer's support reply and the seller's custom
 * order request have no web screen, and an inert card is better than a wrong
 * one.
 */
function Toast({ item, allowDismiss, onOpen, onDismiss }) {
  const Icon = item.Icon ?? Bell

  const body = (
    <>
      <span
        aria-hidden="true"
        className="mt-0.5 flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-clay/10 text-clay-ink"
      >
        <Icon size={18} strokeWidth={2} />
      </span>

      <div className="min-w-0 flex-1">
        <div className="flex items-baseline gap-2 pr-6">
          <p className="min-w-0 flex-1 truncate text-sm font-semibold text-ink">
            {item.title}
          </p>
          {item.time && <span className="shrink-0 text-xs text-muted">{item.time}</span>}
        </div>

        {item.message && (
          <p className="mt-1 line-clamp-2 text-sm leading-relaxed text-muted">
            {item.message}
          </p>
        )}

        {item.meta && (
          <p className="mt-1.5 text-[11px] uppercase tracking-[0.08em] text-muted">
            {item.meta}
          </p>
        )}
      </div>
    </>
  )

  const controls = allowDismiss ? (
    <button
      type="button"
      onClick={onDismiss}
      aria-label="Dismiss notification"
      className="absolute right-3 top-3 z-20 flex h-7 w-7 items-center justify-center rounded-full text-muted transition-colors duration-200 ease-out-cubic hover:bg-subtle hover:text-ink"
    >
      <X size={14} strokeWidth={2} />
    </button>
  ) : null

  /*
    Translucent enough to read as a layer floating over the page, opaque enough
    to read through — and drawn from the `raised` token rather than a literal, so
    it follows dark mode like every other card.
  */
  const shell =
    'relative flex gap-3 rounded-card border border-hairline bg-raised/95 p-4 shadow-card-lift backdrop-blur-md'

  if (!item.to) {
    return (
      <div className={shell}>
        {controls}
        {body}
      </div>
    )
  }

  return (
    <div className={shell}>
      <Link
        to={item.to}
        onClick={onOpen}
        aria-label={item.title}
        className="absolute inset-0 z-10 rounded-card"
      />
      {controls}
      {body}
    </div>
  )
}
