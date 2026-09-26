import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
} from 'react'

import {
  DEFAULT_THEME_MODE,
  effectiveTheme,
  readStoredThemeMode,
  resolveThemeMode,
  writeStoredThemeMode,
} from '../lib/themeRules.js'
import {
  THEME_WIPE_EASING,
  themeWipeFrames,
  themeWipePlan,
  wipeOrigin,
  wipeRadius,
} from '../lib/themeWipeRules.js'

const ThemeContext = createContext(null)

const DARK_QUERY = '(prefers-color-scheme: dark)'
const REDUCE_QUERY = '(prefers-reduced-motion: reduce)'

/** The class on `<html>` — the whole of what the theme is. */
function paintTheme(theme) {
  document.documentElement.classList.toggle('dark', theme === 'dark')
}

/** `localStorage`, or null where even touching it throws (cookies blocked). */
function storageOrNull() {
  try {
    return window.localStorage
  } catch {
    return null
  }
}

function prefersDarkNow() {
  return Boolean(window.matchMedia?.(DARK_QUERY)?.matches)
}

/**
 * Appearance.
 *
 * Dark mode is one class on `<html>` plus two columns of CSS variables in
 * `index.css` — no component knows which theme is active, and adding dark
 * support to a new component is a matter of using the tokens it already uses.
 *
 * The mode is three-way rather than a switch, which is the app's decision and
 * the right one: an on/off switch silently stops following the device, so a
 * customer who pins dark in July keeps it when their phone switches at dusk and
 * has no way to say "actually, follow my phone again".
 *
 * Two details are about not flashing:
 *
 *  1. The initial read happens in the state initialiser, so the first render
 *     already knows the answer.
 *  2. `index.html` has an inline pre-paint script that applies the class before
 *     any module loads — the provider re-applies the same class on mount, which
 *     is a no-op when the script already got it right.
 *
 * ## The wipe
 *
 * `setMode(next, origin)` also animates the change: going light, the new theme
 * spreads from `origin` (the click) until it covers the screen; going dark, the
 * light recedes back to that point. It is the View Transitions API — the
 * browser paints a still of the old theme and a still of the new one, and
 * `themeWipeRules.js` decides which of the two is clipped, by which circle.
 *
 * Three things about it are deliberate:
 *
 *  1. **The theme is applied by the transition's own callback, not by a
 *     re-render.** The browser snapshots the page the moment that callback
 *     returns, and a React state update is not guaranteed to have painted by
 *     then — so `commit` writes the class itself and lets the effect above
 *     confirm it. Nothing about the wipe depends on the state update landing in
 *     time, and a state update landing twice is a no-op.
 *  2. **No API, no wipe — the theme still changes.** The animation is a flourish
 *     on a change that has already happened, never a condition of it. See
 *     "Animations must fail open" in the README. A `prefers-reduced-motion`
 *     request shortens the circle rather than removing it — the reason is in
 *     `themeWipeRules.js`, and it is an exception to the rule everywhere else
 *     on this site.
 *  3. **A wipe only runs when the theme actually changes.** Picking `System`
 *     while the device is already dark is a new *mode* and the same *theme*: a
 *     full-screen snapshot to arrive exactly where the page already was would
 *     be half a second of nothing.
 */
export function ThemeProvider({ children }) {
  const [mode, setModeState] = useState(() => readStoredThemeMode(storageOrNull()))
  const [prefersDark, setPrefersDark] = useState(prefersDarkNow)

  const resolved = effectiveTheme(mode, prefersDark)

  /*
    Follow the device — while, and only while, `system` is selected. The
    listener is always attached because the preference can change at any moment,
    and `effectiveTheme` is what decides whether it matters.
  */
  useEffect(() => {
    const media = window.matchMedia?.(DARK_QUERY)
    if (!media) return undefined

    const onChange = (event) => setPrefersDark(event.matches)
    setPrefersDark(media.matches)
    media.addEventListener('change', onChange)
    return () => media.removeEventListener('change', onChange)
  }, [])

  useEffect(() => {
    paintTheme(resolved)
  }, [resolved])

  /**
   * Change the appearance, optionally wiping it in from `origin`.
   *
   * `origin` is a viewport point (`{ x, y }`) — the click the customer made.
   * Anything else (a keyboard selection, a caller that only has a mode) wipes
   * from the middle of the screen, and a customer who asked for reduced motion
   * gets no wipe at all.
   */
  const setMode = useCallback(
    (next, origin) => {
      const resolvedNext = resolveThemeMode(next)
      const nextTheme = effectiveTheme(resolvedNext, prefersDarkNow())

      /*
        Write the mode, and paint the class here rather than waiting for the
        effect: this runs inside the view transition's callback, and the
        browser's snapshot is taken as soon as it returns.
      */
      const commit = () => {
        setModeState(resolvedNext)
        writeStoredThemeMode(storageOrNull(), resolvedNext)
        paintTheme(nextTheme)
      }

      const supported = typeof document.startViewTransition === 'function'
      const reduceMotion = Boolean(
        window.matchMedia?.(REDUCE_QUERY)?.matches,
      )
      const plan = themeWipePlan({ supported, reduceMotion })

      if (nextTheme === resolved || !plan) {
        /*
          Both reasons a theme change can arrive without a wipe are not bugs,
          and from the outside they look identical to one. This says which, in
          development only: `Light` on an already-light page changes which radio
          is checked and nothing else, and a browser with no View Transitions
          API cannot run one whatever it was asked for. Without the line, the
          honest answer to "it did not animate" is a shrug.
        */
        if (import.meta.env.DEV) {
          const reason =
            nextTheme === resolved
              ? 'the theme did not change (only the mode did) — nothing to reveal'
              : 'this browser has no View Transitions API'
          console.info(
            `[theme] no wipe: ${reason}. Theme is now “${nextTheme}”; the three-way choice lives in Settings → Appearance.`,
          )
        }
        commit()
        return
      }

      const size = { width: window.innerWidth, height: window.innerHeight }
      const point = wipeOrigin(origin, size)
      const radius = wipeRadius(point, size)

      /*
        The outgoing snapshot has to be stacked above the incoming one for the
        dark half of this (see `index.css`), and the pseudo tree reads this
        attribute when the transition starts — so it goes on first and comes off
        with the transition.
      */
      const root = document.documentElement
      const { pseudoElement, keyframes } = themeWipeFrames(nextTheme, point, radius)

      try {
        root.dataset.themeWipe = nextTheme
        const transition = document.startViewTransition(commit)

        transition.ready
          .then(() => {
            root.animate(
              { clipPath: keyframes },
              {
                // 700ms normally, 220ms when the device asks for less motion.
                duration: plan.duration,
                easing: THEME_WIPE_EASING,
                pseudoElement,
              },
            )
          })
          // A skipped or interrupted transition is not an error worth a page:
          // the class is already applied, so the theme is right either way.
          .catch(() => {})

        /*
          The attribute comes off when the snapshots do, not before: it is what
          stacks the outgoing still above the incoming one. `finish` clears it
          only if it is still OURS — clicking through light → dark faster than
          the wipe takes starts a second transition and skips the first, and the
          first one's cleanup must not strip the second one's stacking.
        */
        const finish = () => {
          if (root.dataset.themeWipe === nextTheme) delete root.dataset.themeWipe
        }
        transition.finished.then(finish, finish)
      } catch {
        // A transition already in flight, or an implementation that refuses:
        // the theme still has to change.
        delete root.dataset.themeWipe
        commit()
      }
    },
    [resolved],
  )

  const value = useMemo(
    () => ({ mode, resolved, isDark: resolved === 'dark', prefersDark, setMode }),
    [mode, resolved, prefersDark, setMode],
  )

  return <ThemeContext.Provider value={value}>{children}</ThemeContext.Provider>
}

export function useTheme() {
  const context = useContext(ThemeContext)
  if (!context) {
    throw new Error('useTheme must be used inside <ThemeProvider>')
  }
  return context
}

export { DEFAULT_THEME_MODE }
