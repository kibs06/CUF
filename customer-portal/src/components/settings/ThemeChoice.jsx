import { useRef } from 'react'
import { Check, MonitorSmartphone, Moon, Sun } from 'lucide-react'

import { useTheme } from '../../hooks/useTheme.jsx'
import { THEME_EXPLANATION, THEME_MODES, themeModeLabel } from '../../lib/themeRules.js'

/* `Moon` and `Sun` are in lucide; the app's System icon is `brightness_auto`. */
const OPTIONS = [
  {
    mode: 'system',
    Icon: MonitorSmartphone,
    description: 'Match your device setting',
  },
  { mode: 'light', Icon: Sun, description: 'Always the light theme' },
  { mode: 'dark', Icon: Moon, description: 'Always the dark theme' },
]

/**
 * System / Light / Dark.
 *
 * Inline rather than behind a disclosure, which is the one place this differs
 * from the app: a bottom sheet exists because a phone screen is small, and a
 * web page that hides three radio buttons behind a tap is inventing a step.
 *
 * It stays three-way for the reason the app gives — an on/off switch silently
 * stops following the device, and there is then no way back to "follow my
 * phone". `system` is therefore a real option, not a default.
 *
 * A radiogroup, so arrow keys move between the options and a screen reader
 * announces "1 of 3" — a row of buttons would leave both out.
 *
 * ## The wipe starts where the customer pointed
 *
 * Changing the theme wipes the new one across the screen, out of the cursor
 * (`useTheme` → `themeWipeRules.js`). The origin is captured on `pointerdown`
 * because that is the only event guaranteed to carry the real pointer position:
 * `change` fires from the radio, which is `sr-only` — a 1px input whose own
 * geometry says nothing about where the customer clicked. A keyboard selection
 * has no pointer at all, so it falls back to the centre of the row that was
 * chosen, which is where the eye already is.
 */
export default function ThemeChoice() {
  const { mode, setMode } = useTheme()
  const pointer = useRef(null)

  /** Where the wipe should start: the click, or the row the customer chose. */
  const originFor = (element) => {
    if (pointer.current) return pointer.current
    const rect = element?.closest('label')?.getBoundingClientRect()
    if (!rect) return undefined
    return { x: rect.left + rect.width / 2, y: rect.top + rect.height / 2 }
  }

  return (
    <fieldset className="mt-3">
      <legend className="sr-only">Appearance</legend>

      <div className="overflow-hidden rounded-card border border-hairline bg-raised shadow-card">
        {OPTIONS.map(({ mode: value, Icon, description }, index) => {
          const selected = mode === value
          const id = `theme-${value}`

          return (
            <label
              key={value}
              htmlFor={id}
              onPointerDown={(event) => {
                pointer.current = { x: event.clientX, y: event.clientY }
              }}
              className={`flex cursor-pointer items-center gap-4 px-5 py-4 transition-colors duration-200 ease-out-cubic ${
                index > 0 ? 'border-t border-hairline-soft' : ''
              } ${selected ? 'bg-clay/[0.06]' : 'hover:bg-subtle/70'}`}
            >
              <Icon
                size={20}
                strokeWidth={1.75}
                className={selected ? 'shrink-0 text-clay-ink' : 'shrink-0 text-muted'}
              />

              <span className="min-w-0 flex-1">
                <span
                  className={`block text-sm ${selected ? 'font-semibold text-ink' : 'font-medium text-ink'}`}
                >
                  {themeModeLabel(value)}
                </span>
                <span className="mt-0.5 block text-xs text-muted">
                  {description}
                </span>
              </span>

              <input
                id={id}
                type="radio"
                name="theme-mode"
                value={value}
                checked={selected}
                onChange={(event) => setMode(value, originFor(event.currentTarget))}
                className="sr-only"
              />

              {selected && (
                <Check size={18} strokeWidth={2.5} className="shrink-0 text-clay-ink" />
              )}
            </label>
          )
        })}
      </div>

      <p className="mt-2 text-xs leading-relaxed text-muted">{THEME_EXPLANATION}</p>
      <p className="mt-1 text-xs leading-relaxed text-muted">
        Your choice is remembered on this device. Ordering stays the same in
        either theme.
      </p>
    </fieldset>
  )
}

/** Kept beside the options so a new mode cannot be added without a label here. */
export { THEME_MODES }
