import { useEffect, useRef, useState } from 'react'
import { createPortal } from 'react-dom'
import { Rotate3d, X } from 'lucide-react'

import { useScrollLock } from '../../hooks/useScrollLock.js'
import { useTheme } from '../../hooks/useTheme.jsx'
import { useTransitionTiming } from '../motion/transitions'

/**
 * **The 3D viewer** — the shoe a visitor can turn, on the page where they are
 * deciding.
 *
 * It is the web half of the app's box: the same verified `.glb` out of the same
 * public bucket, drawn by the same library the app's box falls back to
 * (`<model-viewer>` — `ShoePreviewWebView` runs it inside a WebView), clearing to
 * the same stage tone (`bg-stage`, which is `AppPalette.stage`). What a visitor
 * gets here is the **look**: drag to turn, pinch or scroll to zoom. There is no
 * try-on, and that is a limit rather than an omission — the app's fitting screen
 * needs ARCore and a live camera, which is not something this page can ask a
 * browser for, so it is not offered and not pretended.
 *
 * Six decisions worth naming, because a viewer is easy to write badly:
 *
 *  1. **The library is a dynamic import.** `<model-viewer>` is a few hundred
 *     kilobytes of WebGL plumbing, and most visits never open this dialog: a
 *     static import would put it in the bundle every product page pays for. The
 *     import happens on the first open, once; a visit that never taps the button
 *     downloads none of it.
 *  2. **The element is mounted only after the import resolves.** Before it, the
 *     tag is an unknown element that renders nothing but still reserves the box;
 *     the placeholder says "loading the viewer" instead of showing an empty
 *     stage that looks broken.
 *  3. **`interaction-prompt="none"` and no `ar` attribute.** The app switches
 *     off the library's own three-second prompt for the same reason (it has a
 *     hand-drawn tutorial instead) — and `ar` is deliberately absent, because a
 *     second, unmanaged AR door out of a product page is not this component's to
 *     open. The opening **orbit is the app's opening pose** (its
 *     `INITIAL_YAW_DEG = 60`, `INITIAL_PITCH_DEG = 18`): the library's own default
 *     looks straight down the shoe's length, so the first thing a customer saw
 *     was a toe-on blob rather than the three-quarter view a product shot uses.
 *     The radius stays `105%`, the same 5% margin the app's camera law keeps.
 *  4. **The dialog mounts and unmounts with `open`**, portalled to
 *     `document.body` and locked against background scroll through the shared
 *     `useScrollLock` every dialog here uses (counted rather than saved and
 *     restored, because dialogs nest — see the README): `fixed inset-0` only
 *     means "the window" when no ancestor is transformed, and this page's route
 *     wrapper animates one. It is
 *     also **sized by the shorter axis**: 64rem wide — a full step above the
 *     confirmation dialogs, because this one *is* the product — and on the wider
 *     breakpoints additionally never taller than the window can show, which is a
 *     height budget converted into a width (`(100dvh − 11rem) × 1.6`, the header,
 *     the footer and the backdrop's own padding being the 11rem, and 1.6 the
 *     stage's aspect). A viewer that has to be scrolled to see the shoe is not a
 *     viewer.
 *  5. **Reduced motion is honoured by not spinning it** — `auto-rotate` is only
 *     passed when the visitor has not asked for less movement. Turning the shoe
 *     is still theirs to do; nothing moves on its own.
 *  6. **The lighting is theme-aware; the shoe is not.** The library renders the
 *     leather the same in both themes — measured, its pixels are identical to the
 *     third decimal — so what decides whether it *reads* is the stage it is
 *     drawn against, and those two stages are as far apart as tones get (#F5F5F5
 *     and #0E0F12, the app's own values, which this component may not move). On
 *     the dark stage the shoe's lit surfaces separate by themselves and its
 *     shadow is invisible; on the light one the leather's lit surfaces approach
 *     the stage tone and the library's cast shadow lands as a dark pool. Light
 *     therefore renders a touch darker (`exposure` 0.85) and grounds the shoe
 *     with a whisper of a shadow (0.45); dark keeps the library's own exposure
 *     and the shadow nothing can see. Both are properties the library re-reads
 *     live, so a theme flip with the dialog open re-lights the shoe in place.
 *
 * ⚠️ **The size is an inline style, never a class.** `<model-viewer>` is a custom
 * element, and React 18 writes `className` on one as the literal attribute
 * `classname="…"` — a name no stylesheet matches, and one no warning is printed
 * for. The class therefore did nothing, the element kept the library's own
 * `:host { width: 300px; height: 150px }`, and the shoe drew small in the top-left
 * of a full-size dark stage (the shop-window bug this fixed, 2026-10-03). An
 * inline style is set as a DOM property, applies through the shadow boundary, and
 * outranks `:host` — so the element gets the stage's box and `model-viewer`
 * re-frames the model for it.
 */
export default function Product3DViewer({ open, url, name, onClose }) {
  const { reduce } = useTransitionTiming()
  const { isDark } = useTheme()
  const [ready, setReady] = useState(false)
  const closeRef = useRef(null)

  // See decision 6. `exposure` and `shadow-intensity` are the two knobs this
  // needs; everything else about the rig stays the library's default.
  const lighting = isDark
    ? { exposure: '1', shadow: '0.8' }
    : { exposure: '0.85', shadow: '0.45' }

  // Once per visit at most: the module is cached by the browser and by Vite's
  // chunk cache, so later opens resolve from memory.
  useEffect(() => {
    if (!open || ready) return undefined

    let cancelled = false
    import('@google/model-viewer')
      .then(() => {
        if (!cancelled) setReady(true)
      })
      .catch(() => {
        // A blocked chunk (an offline tab, a strict content filter) is not a
        // broken page: the dialog stays on its placeholder and the customer can
        // close it. The alternative — throwing into the route — would take the
        // product page down over a bonus.
      })

    return () => {
      cancelled = true
    }
  }, [open, ready])

  useEffect(() => {
    if (!open) return undefined

    const onKeyDown = (event) => {
      if (event.key === 'Escape') onClose?.()
    }

    window.addEventListener('keydown', onKeyDown)
    closeRef.current?.focus()

    return () => {
      window.removeEventListener('keydown', onKeyDown)
    }
  }, [open, onClose])

  // Shared with every other dialog — see `useScrollLock`.
  useScrollLock(open)

  if (!open || !url) return null

  return createPortal(
    <div
      className="fade-enter fixed inset-0 z-50 flex items-end justify-center overflow-y-auto bg-scrim p-3 backdrop-blur-[2px] sm:items-center sm:p-6"
      onClick={() => onClose?.()}
    >
      <div
        role="dialog"
        aria-modal="true"
        aria-labelledby="product-3d-title"
        onClick={(event) => event.stopPropagation()}
        className="rise-enter w-full max-w-5xl overflow-hidden rounded-card border border-hairline bg-raised shadow-premium sm:max-w-[min(64rem,calc((100dvh-11rem)*1.6))]"
      >
        <header className="flex items-center gap-2.5 border-b border-hairline-soft px-4 py-3 sm:px-5">
          <Rotate3d size={16} strokeWidth={2} className="shrink-0 text-clay-ink" />
          <h2
            id="product-3d-title"
            className="min-w-0 flex-1 truncate font-display text-base font-semibold text-ink"
          >
            {name}
          </h2>
          <button
            ref={closeRef}
            type="button"
            onClick={() => onClose?.()}
            aria-label="Close the 3D view"
            className="-mr-1 inline-flex h-8 w-8 shrink-0 items-center justify-center rounded-full text-muted transition-colors duration-200 hover:bg-subtle hover:text-ink"
          >
            <X size={16} strokeWidth={2} />
          </button>
        </header>

        {/* The stage. `bg-stage` is the renderer's own tone, so the shoe sits on
            the same surface in the browser that it does inside the app. */}
        <div className="relative aspect-[4/3] w-full bg-stage sm:aspect-[16/10]">
          {ready ? (
            <model-viewer
              src={url}
              alt={`${name} — 3D model`}
              // Presence, not value: the library reads these as attributes.
              camera-controls=""
              touch-action="none"
              interaction-prompt="none"
              camera-orbit="-60deg 72deg 105%"
              exposure={lighting.exposure}
              shadow-intensity={lighting.shadow}
              {...(reduce ? {} : { 'auto-rotate': '' })}
              style={{ display: 'block', width: '100%', height: '100%' }}
            />
          ) : (
            <div className="absolute inset-0 grid place-items-center">
              <p className="shimmer h-3 w-40 rounded-full" aria-hidden="true" />
              <span className="sr-only">Loading the 3D viewer…</span>
            </div>
          )}
        </div>

        <p className="border-t border-hairline-soft px-4 py-3 text-xs leading-relaxed text-muted sm:px-5">
          Drag to turn the shoe · pinch or scroll to zoom. This is the model the
          workshop published, not a photo — try-on with your camera lives in the
          CUFMAI app.
        </p>
      </div>
    </div>,
    document.body
  )
}
