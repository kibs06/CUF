import { useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import { ArrowLeft, Info, Ruler } from 'lucide-react'

import Reveal from '../components/ui/Reveal'
import { useAuth } from '../hooks/useAuth.jsx'
import {
  FOOT_SIZE_CATEGORIES,
  FOOT_WIDTHS,
  euSizesFor,
  footDraftErrors,
  footDraftFromProfile,
  footProfileError,
  footProfileSummary,
  hasFootSize,
} from '../lib/footRules'

/**
 * Size Your Foot — the manual half of the app's screen.
 *
 * The app leads with an AR scan ("Foot Size 2.0") and offers manual entry as
 * the fallback. A browser has no camera pipeline for that measurement, so this
 * page is the fallback on its own — and it says so, and points at the app for
 * the scan, rather than presenting a lesser thing as the whole feature.
 *
 * It writes the columns the scan would have written, with
 * `foot_profile_source = 'manual'`. That difference is not decoration: it is
 * what the summary sentence reports back ("set manually" vs "from your AR
 * scan"), so a customer can see which number they are trusting before buying.
 */
export default function SettingsFootSize() {
  const { profile, saveFootProfile, skipFootProfile } = useAuth()
  const saved = hasFootSize(profile)

  const [draft, setDraft] = useState(() => footDraftFromProfile(profile))
  const [errors, setErrors] = useState({})
  const [status, setStatus] = useState(null) // { ok, message }
  const [saving, setSaving] = useState(false)

  const sizes = useMemo(() => euSizesFor(draft.category), [draft.category])

  const setField = (field) => (value) =>
    setDraft((current) => ({ ...current, [field]: value }))

  const onSubmit = async (event) => {
    event.preventDefault()
    setStatus(null)

    const found = footDraftErrors(draft)
    setErrors(found)
    if (Object.keys(found).length > 0) return

    setSaving(true)
    try {
      await saveFootProfile(draft)
      setStatus({ ok: true, message: 'Size saved. Product pages will use it.' })
    } catch (failure) {
      setStatus({ ok: false, message: footProfileError(failure) })
    } finally {
      setSaving(false)
    }
  }

  const onSkip = async () => {
    setSaving(true)
    setStatus(null)
    try {
      await skipFootProfile()
      setStatus({
        ok: true,
        message:
          'No problem — we will stop asking. You can set it here any time.',
      })
    } catch (failure) {
      setStatus({ ok: false, message: footProfileError(failure) })
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="mx-auto max-w-2xl px-4 py-10 sm:px-6 lg:px-8">
      <Link
        to="/settings"
        className="inline-flex items-center gap-1.5 text-xs font-semibold text-muted transition-colors duration-200 hover:text-ink"
      >
        <ArrowLeft size={14} strokeWidth={2} />
        Settings
      </Link>

      <header className="mt-4">
        <p className="overline">Account</p>
        <h1 className="mt-2 font-display text-3xl font-semibold text-ink">
          Size Your Foot
        </h1>
      </header>

      <Reveal className="mt-6 rounded-card border border-hairline bg-raised p-6 shadow-card">
        <div className="flex items-center gap-3">
          <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-premium bg-clay/10">
            <Ruler size={18} className="text-clay-ink" strokeWidth={1.75} />
          </span>
          <div className="min-w-0">
            <h2 className="font-display text-lg font-semibold text-ink">
              {saved ? 'Your size on file' : 'No size on file yet'}
            </h2>
            <p className="mt-0.5 text-xs text-muted">
              {footProfileSummary(profile)}
            </p>
          </div>
        </div>

        <p className="mt-4 text-sm leading-relaxed text-muted">
          Stores stock one pair per size, so a size on file is what lets the
          catalog show you pairs that will actually fit — and what stops the
          home page asking you again.
        </p>
      </Reveal>

      <form onSubmit={onSubmit} className="mt-6 space-y-6" noValidate>
        {/* ── Scale ─────────────────────────────────────────────────── */}
        <fieldset className="rounded-card border border-hairline bg-raised p-6 shadow-card">
          <legend className="sr-only">The scale you shop in</legend>
          <h2 className="font-display text-lg font-semibold text-ink">
            Which sizes do you buy?
          </h2>
          <p className="mt-1 text-xs leading-relaxed text-muted">
            A scale, not who you are: EU 42 is EU 42, but it is labelled US 9 on
            the men&apos;s chart and US 10.5 on the women&apos;s. Pick the chart
            you use when you buy.
          </p>

          <div className="mt-4 flex flex-wrap gap-2">
            {FOOT_SIZE_CATEGORIES.map((option) => {
              const active = draft.category === option.value
              return (
                <button
                  key={option.value}
                  type="button"
                  aria-pressed={active}
                  onClick={() => {
                    setField('category')(option.value)
                    // A size from the other band is not a size in this one, so
                    // switching scales clears it rather than leaving an
                    // impossible pair of values on screen.
                    setField('size')('')
                    setErrors((current) => ({ ...current, category: undefined, size: undefined }))
                  }}
                  className={`rounded-full border px-4 py-2 text-sm font-medium transition-colors duration-200 ease-out-cubic ${
                    active
                      ? 'border-clay bg-clay text-ink-inverse'
                      : 'border-hairline text-muted-strong hover:border-card-edge hover:text-ink'
                  }`}
                >
                  {option.label}
                </button>
              )
            })}
          </div>

          {errors.category && (
            <p className="mt-2 text-xs font-medium text-crimson">
              {errors.category}
            </p>
          )}
        </fieldset>

        {/* ── Size and width ────────────────────────────────────────── */}
        <div className="rounded-card border border-hairline bg-raised p-6 shadow-card">
          <h2 className="font-display text-lg font-semibold text-ink">
            Your size
          </h2>

          <div className="mt-4 grid gap-5 sm:grid-cols-2">
            <div>
              <label
                htmlFor="foot-size"
                className="block text-sm font-medium text-ink"
              >
                EU size
              </label>
              <select
                id="foot-size"
                value={draft.size}
                onChange={(event) => {
                  setField('size')(event.target.value)
                  setErrors((current) => ({ ...current, size: undefined }))
                }}
                aria-invalid={errors.size ? 'true' : undefined}
                className="mt-1.5 h-11 w-full rounded-field border border-hairline bg-raised px-3 text-sm text-ink transition-colors duration-200 ease-out-cubic hover:border-card-edge focus:border-clay"
              >
                <option value="">
                  {draft.category === 'kids' ? 'Pick a size' : 'Pick a size'}
                </option>
                {sizes.map((size) => (
                  <option key={size} value={size}>
                    {size}
                  </option>
                ))}
              </select>
              {errors.size && (
                <p className="mt-1.5 text-xs font-medium text-crimson">
                  {errors.size}
                </p>
              )}
              {!draft.category && (
                <p className="mt-1.5 text-xs text-muted">
                  Pick a scale first — it changes the sizes offered.
                </p>
              )}
            </div>

            <div>
              <label
                htmlFor="foot-width"
                className="block text-sm font-medium text-ink"
              >
                Width
                <span className="ml-2 text-xs font-normal text-muted/70">
                  optional
                </span>
              </label>
              <select
                id="foot-width"
                value={draft.width}
                onChange={(event) => {
                  setField('width')(event.target.value)
                  setErrors((current) => ({ ...current, width: undefined }))
                }}
                aria-invalid={errors.width ? 'true' : undefined}
                className="mt-1.5 h-11 w-full rounded-field border border-hairline bg-raised px-3 text-sm text-ink transition-colors duration-200 ease-out-cubic hover:border-card-edge focus:border-clay"
              >
                {/* The app's manual picker stores a width only when one is
                    chosen; "Not sure" leaves the column untouched. */}
                <option value="">Not sure</option>
                {FOOT_WIDTHS.map((width) => (
                  <option key={width} value={width}>
                    {width}
                  </option>
                ))}
              </select>
              {errors.width ? (
                <p className="mt-1.5 text-xs font-medium text-crimson">
                  {errors.width}
                </p>
              ) : (
                <p className="mt-1.5 text-xs text-muted">
                  Leave it if you are not sure.
                </p>
              )}
            </div>
          </div>

          <div className="mt-6 flex flex-wrap items-center gap-3">
            <button type="submit" disabled={saving} className="btn btn-primary">
              {saving ? 'Saving…' : 'Save my size'}
            </button>
            <button
              type="button"
              onClick={onSkip}
              disabled={saving}
              className="btn btn-outline"
            >
              Don&apos;t ask me again
            </button>
          </div>

          {status && (
            <p
              role="status"
              className={`mt-4 rounded-field border px-3 py-2 text-xs leading-relaxed ${
                status.ok
                  ? 'border-olive/30 bg-olive/[0.07] text-ink'
                  : 'border-crimson/30 bg-crimson/[0.07] text-ink'
              }`}
            >
              {status.message}
            </p>
          )}
        </div>
      </form>

      <div className="mt-6 flex items-start gap-2.5 rounded-card border border-hairline bg-subtle/60 p-4">
        <Info size={16} strokeWidth={2} className="mt-0.5 shrink-0 text-clay-ink" />
        <p className="text-xs leading-relaxed text-muted">
          Measuring instead of choosing? The CUFMAI app can scan your foot and
          fill this in for you — it stores the measurement as an AR scan, and
          this page will show it the next time it loads.
        </p>
      </div>
    </div>
  )
}
