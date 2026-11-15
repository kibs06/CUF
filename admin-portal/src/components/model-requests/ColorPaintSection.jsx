import { useEffect, useState } from 'react'
import { Check, Loader2 } from 'lucide-react'
import { useColorPaint } from '../../hooks/useColorPaint.js'
import { describeError } from '../../lib/errors.js'
import { guessPaintHex, isPaintHex } from '../../lib/paintGuess.js'

// ─── 3D paint per colour ───────────────────────────────────────────
// The capture half of the swipe-the-colour mission: one confirmed hex per
// colour, stored in `product_color_paint`, which the app's viewers tint the
// shared mesh with live. The picker opens on the GUESS (the app swatch
// mapper, ported) so the admin adjusts rather than starting from white;
// only a confirmed hex stores, because the guess for an unknown name is a
// hash pick, not a colour.
//
// Deliberately NOT a publish gate: paint is catalogue jewellery, and a
// product with no confirmed paint renders as-authored (the hero colourway,
// untouched) — honest, where a forced guess would be a wrong colour.

function PaintRow({ colorName, savedHex, onSave, saving, saveError, onRemove, removing, removeError }) {
  // Lowercased for DISPLAY as well as storage: the live hex CHECK is
  // lowercase-only, what the box shows is what Confirm sends — and it
  // makes a stale tab obvious (uppercase boxes = old code, reload).
  const [text, setText] = useState(() =>
    (savedHex ?? guessPaintHex(colorName)).toLowerCase(),
  )
  const [localError, setLocalError] = useState(null)
  const [justSaved, setJustSaved] = useState(false)
  // Removing is two clicks on purpose: one stray tap must never unpaint a
  // colour. The arm resets when the stored hex changes (a removal landing
  // from the server disarms the row back to its guess + Confirm).
  const [confirming, setConfirming] = useState(false)

  // A saved hex landing from the server wins over the draft — the picker
  // always shows the stored truth, not a stale edit.
  useEffect(() => {
    if (savedHex) setText(savedHex)
    setConfirming(false)
  }, [savedHex])

  // The "Saved" tick is news, not state: it fades so the next edit reads.
  useEffect(() => {
    if (!justSaved) return
    const t = setTimeout(() => setJustSaved(false), 2500)
    return () => clearTimeout(t)
  }, [justSaved])

  const shown = isPaintHex(text) ? text : guessPaintHex(colorName)
  const dirty = text.trim().toLowerCase() !== (savedHex ?? '').toLowerCase()

  // `describeError` returns `{ kind, message, detail, code }`, never a
  // string — rendering it raw is the "Objects are not valid as a React
  // child" crash. Message first, the server's own words after.
  const rowError = localError
    ? { message: localError, detail: null }
    : saveError
      ? describeError(saveError)
      : removeError
        ? describeError(removeError)
        : null

  const commit = (hex) => {
    setLocalError(null)
    if (!isPaintHex(hex)) {
      setLocalError('A paint is a web hex — e.g. #5C3A21.')
      return
    }
    if (hex.toLowerCase() === (savedHex ?? '').toLowerCase()) return
    onSave(colorName, hex).then(
      () => setJustSaved(true),
      () => {},
    )
  }

  return (
    <div className="flex flex-wrap items-center gap-x-3 gap-y-1 rounded-xl border border-[#F5F0EB] bg-[#FBF8F5] px-3 py-2">
      <span
        className="h-6 w-6 shrink-0 rounded-full border border-black/10"
        style={{ backgroundColor: shown }}
        title={savedHex ? 'Confirmed paint' : 'Prefill guess — confirm it'}
      />
      <span className="min-w-0 flex-1 truncate text-sm font-medium text-[#3B2314]">
        {colorName}
        {!savedHex && (
          <span className="ml-2 text-[11px] font-normal text-[#6B5C4E]">guess — confirm</span>
        )}
      </span>
      <input
        type="color"
        aria-label={`Paint for ${colorName}`}
        value={shown}
        onChange={(e) => {
          setText(e.target.value)
          commit(e.target.value)
        }}
        className="h-8 w-10 shrink-0 cursor-pointer rounded-lg border border-[#D9D0C7] bg-white p-1"
      />
      <input
        aria-label={`Hex for ${colorName}`}
        value={text}
        spellCheck={false}
        onChange={(e) => setText(e.target.value)}
        onBlur={(e) => commit(e.target.value.trim())}
        onKeyDown={(e) => {
          if (e.key === 'Enter') commit(e.target.value.trim())
        }}
        placeholder={guessPaintHex(colorName).toLowerCase()}
        className="w-24 shrink-0 rounded-lg border border-[#D9D0C7] bg-white px-2 py-1.5 font-mono text-xs text-[#3B2314] outline-none focus:border-[#8B5A2B]"
      />
      {/* Confirming is an explicit click: Done only closes the dialog, so an
          untouched "guess — confirm" row must never look savable-by-Done. */}
      {!savedHex && !justSaved ? (
        <button
          type="button"
          disabled={saving || !isPaintHex(text)}
          onClick={() => commit(text.trim())}
          className="shrink-0 rounded-lg bg-[#8B5A2B] px-2.5 py-1.5 text-[11px] font-semibold text-white transition-colors hover:bg-[#6B4423] disabled:opacity-50"
        >
          {saving ? <Loader2 size={13} className="animate-spin" /> : 'Confirm'}
        </button>
      ) : (
        <span className="flex shrink-0 items-center justify-end gap-2 text-[11px]">
          {saving ? (
            <Loader2 size={13} className="animate-spin text-[#8B5A2B]" />
          ) : justSaved || savedHex ? (
            <span className="flex items-center gap-1 text-green-700">
              <Check size={13} /> Saved
            </span>
          ) : null}
          {savedHex && (
            <button
              type="button"
              disabled={removing}
              title={confirming ? 'Click again to remove this paint' : `Remove the ${colorName} paint`}
              onClick={() => {
                if (!confirming) {
                  setConfirming(true)
                  return
                }
                setLocalError(null)
                onRemove(colorName).then(
                  () => {},
                  () => {},
                )
              }}
              className={`rounded-lg px-2 py-1.5 text-[11px] font-semibold transition-colors disabled:opacity-50 ${
                confirming
                  ? 'bg-[#D64545] text-white hover:bg-[#B83535]'
                  : 'text-[#D64545] hover:bg-red-50'
              }`}
            >
              {removing ? (
                <Loader2 size={13} className="animate-spin" />
              ) : confirming ? (
                'Sure?'
              ) : (
                'Remove'
              )}
            </button>
          )}
        </span>
      )}
      {rowError && (
        <span className="basis-full text-[11px] break-words text-[#D64545]">
          {rowError.message}
          {rowError.detail && rowError.detail !== rowError.message ? ` — ${rowError.detail}` : ''}
        </span>
      )}
    </div>
  )
}

export default function ColorPaintSection({ productId }) {
  const { data, isLoading, isError, savePaint, saveState, removePaint, removeState } =
    useColorPaint(productId)
  const sectionError = saveState.error ? describeError(saveState.error) : null

  // Paint is jewellery, not a gate: no product, no colours, or a failed
  // fetch all render nothing (or one quiet line) rather than blocking the
  // publish this dialog exists for.
  if (!productId) return null
  if (isLoading) {
    return <p className="mt-3 text-xs text-[#6B5C4E]">Loading colours…</p>
  }
  if (isError || !data || data.colors.length === 0) return null

  return (
    <div className="mt-4">
      <p className="mb-1.5 text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">
        3D paint per colour
      </p>
      <div className="grid gap-2">
        {data.colors.map((name) => (
          <PaintRow
            key={name}
            colorName={name}
            savedHex={data.paints[name] ?? null}
            onSave={savePaint}
            saving={saveState.isPending}
            saveError={saveState.error}
            onRemove={removePaint}
            removing={removeState.isPending}
            removeError={removeState.error}
          />
        ))}
      </div>
      <p className="mt-1 text-xs text-[#6B5C4E]">
        The app tints the one model with this hex when the shopper taps the colour.
        Unconfirmed colours show the model as-authored. Dots ringed “guess” are the
        app's own swatch starting point — confirm each one. Removing a paint
        returns the colour to as-authored, in the app and the preview chips.
      </p>
      {sectionError && (
        <p className="mt-1 text-xs text-[#D64545]">
          {sectionError.message}
          {sectionError.detail && sectionError.detail !== sectionError.message
            ? ` — ${sectionError.detail}`
            : ''}
        </p>
      )}
    </div>
  )
}
