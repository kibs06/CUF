/**
 * A switch: one setting, already on or already off.
 *
 * ## Why this is not an `<input type="checkbox">`
 *
 * The portal has no `@tailwindcss/forms`, so `className="h-4 w-4 text-clay"` on a
 * checkbox sets precisely nothing on the box — `text-clay` is a colour for text
 * and borders, and native checkboxes ignore it. What shipped on the product tile,
 * the product form and the storefront page was therefore the **operating
 * system's** checkbox: a blue-grey box, in the one place the seller is looking
 * when they decide whether a pair is for sale, on a site whose entire palette is
 * brown.
 *
 * The second reason is what the control *means*. A checkbox is a field you fill
 * in and submit; a switch is a state that is already true. "On the storefront" is
 * the second one — it takes effect the moment it moves, with no save button
 * anywhere near it.
 *
 * ## The shape, and the four things it gets right
 *
 *  1. **It is one `<button role="switch">`**, not a styled input plus a label.
 *     That gives one tab stop, and `aria-checked` is what a screen reader
 *     announces — a `<div>` with a sliding knob announces nothing at all.
 *  2. **The label is inside the button** when there is one, so the visible text
 *     *is* the accessible name. A `<label for>` cannot point at a button.
 *  3. **The knob moves with CSS, not JavaScript.** `prefers-reduced-motion` is
 *     honoured by the media query in `index.css` that already shortens every
 *     transition in the portal, so there is nothing to branch on here — and a
 *     switch that fails to animate is still a switch.
 *  4. **`disabled` is real**, because toggling a product is a network write: the
 *     caller disables it while the mutation is in flight, and the knob keeps the
 *     value it was given rather than flickering to the new one and back.
 *
 * The knob is the only hardcoded colour in the file (`bg-white`). It has to read
 * as *the moving part* against both tracks — the clay of on and the grey of off,
 * in both themes — and no token in the palette does that.
 */

/** The two sizes the portal uses: a row control, and a card's footer. */
const SIZES = {
  sm: {
    track: 'h-5 w-9 p-0.5',
    knob: 'h-4 w-4',
    shift: 'translate-x-4',
    label: 'text-xs',
  },
  md: {
    track: 'h-6 w-11 p-0.5',
    knob: 'h-5 w-5',
    shift: 'translate-x-5',
    label: 'text-sm',
  },
}

export default function Switch({
  checked,
  onChange,
  label = null,
  ariaLabel = null,
  disabled = false,
  size = 'md',
  className = '',
}) {
  const sizing = SIZES[size] ?? SIZES.md
  const on = Boolean(checked)

  return (
    <button
      type="button"
      role="switch"
      aria-checked={on}
      aria-label={label ? undefined : ariaLabel}
      disabled={disabled}
      onClick={() => onChange?.(!on)}
      className={`inline-flex items-center gap-2.5 rounded-field text-left transition-colors duration-200 ease-out-cubic disabled:cursor-not-allowed disabled:opacity-60 ${
        label ? `font-medium ${sizing.label} text-muted-strong hover:text-ink` : ''
      } ${className}`}
    >
      <span
        aria-hidden="true"
        className={`relative inline-flex shrink-0 items-center rounded-full transition-colors duration-200 ease-out-cubic ${sizing.track} ${
          on ? 'bg-clay' : 'bg-subtle ring-1 ring-inset ring-hairline'
        }`}
      >
        <span
          className={`block rounded-full bg-white shadow-sm transition-transform duration-200 ease-out-cubic ${sizing.knob} ${
            on ? sizing.shift : 'translate-x-0'
          }`}
        />
      </span>

      {label && <span>{label}</span>}
    </button>
  )
}
