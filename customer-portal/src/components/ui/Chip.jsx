/**
 * A chip you can select — one option out of a closed set.
 *
 * ## Why this is shared
 *
 * Four pickers on the product form are the same control: the tag presets, the
 * audience, the colour names, and a customisation's choices. They differ only in
 * what they are selecting, and the app treats them as one widget for the same
 * reason (`_TagChip` is reused by the audience and category rows) — a chip that
 * looked selected in one group and not in another would be the most visible kind
 * of inconsistency in a form this long. The colours, radii and states here are the
 * notification filter's, which is the portal's existing chip.
 *
 * ## Two shapes, one component
 *
 *  - **Selectable** (`onClick`) — a `<button>` with `aria-pressed`. Not
 *    `aria-selected`/`role="option"`, because these are never inside a listbox:
 *    the group is a `Wrap` of independent toggles, and a selected toggle is what
 *    `aria-pressed` describes.
 *  - **Removable** (`onRemove`) — a hand-typed value that has no off state to
 *    return to. It is drawn as a span with its own remove `<button>`, never a
 *    button inside a button, which is invalid HTML and announces as one control
 *    with two names.
 */
import { X } from 'lucide-react'

/** The two sizes in use: a chip in a picker, and a chip in a dense list. */
const SIZES = {
  md: 'px-3.5 py-1.5 text-xs',
  sm: 'px-2.5 py-1 text-[11px]',
}

const BASE =
  'inline-flex items-center gap-1.5 rounded-full border font-semibold transition-colors duration-200 ease-out-cubic'

/**
 * @param {object} props
 * @param {string} props.label
 * @param {boolean} [props.selected]
 * @param {() => void} [props.onClick]      absent → a static chip
 * @param {() => void} [props.onRemove]     present → a removable chip
 * @param {boolean} [props.disabled]
 * @param {string} [props.title]
 */
export default function Chip({
  label,
  selected = false,
  onClick,
  onRemove,
  disabled = false,
  title,
  size = 'md',
}) {
  const sizing = SIZES[size] ?? SIZES.md

  if (onRemove) {
    return (
      <span
        className={`${BASE} ${sizing} border-clay/40 bg-clay/10 text-clay-ink`}
      >
        {label}
        <button
          type="button"
          onClick={onRemove}
          disabled={disabled}
          aria-label={`Remove ${label}`}
          className="-mr-1 ml-0.5 inline-flex h-4 w-4 items-center justify-center rounded-full text-clay-ink transition-colors duration-200 hover:bg-clay/20 disabled:opacity-40"
        >
          <X className="h-2.5 w-2.5" aria-hidden="true" />
        </button>
      </span>
    )
  }

  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      aria-pressed={selected}
      title={title}
      className={`${BASE} ${sizing} ${
        selected
          ? 'border-clay bg-clay text-ink-inverse'
          : 'border-hairline text-muted-strong hover:border-card-edge hover:text-ink'
      } ${disabled ? 'cursor-not-allowed opacity-50' : ''}`}
    >
      {label}
    </button>
  )
}
