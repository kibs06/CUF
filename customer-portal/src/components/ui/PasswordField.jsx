import { useState } from 'react'
import { Eye, EyeOff } from 'lucide-react'

import Field from './Field'

/**
 * A password input with a reveal toggle.
 *
 * A blind password field is where sign-ins are actually lost — a phone
 * keyboard capitalises the first letter, a password manager fills the wrong
 * box, and the field itself says nothing either way. Revealing it is the fix,
 * so the control belongs inside the field rather than in a "trouble signing
 * in?" note underneath it.
 *
 * Everything else — the label, the error, `aria-invalid`, `aria-describedby`,
 * the border, the focus ring — still comes from `Field`. This only supplies the
 * type switch and the button, which is why the button cannot drift in size or
 * colour from the field it sits in.
 *
 * The toggle reports its state with `aria-pressed` and carries its own
 * accessible name, so it is announced as "Show password, toggle button, not
 * pressed" rather than as an unlabelled icon.
 */
export default function PasswordField({ id, ...props }) {
  const [visible, setVisible] = useState(false)

  return (
    <Field
      id={id}
      {...props}
      type={visible ? 'text' : 'password'}
      trailing={
        <button
          type="button"
          onClick={() => setVisible((was) => !was)}
          aria-pressed={visible}
          aria-label={visible ? 'Hide password' : 'Show password'}
          title={visible ? 'Hide password' : 'Show password'}
          className="inline-flex h-8 w-8 items-center justify-center rounded-field text-muted transition-colors duration-200 ease-out-cubic hover:text-clay-ink"
        >
          {visible ? (
            <EyeOff className="h-[18px] w-[18px]" />
          ) : (
            <Eye className="h-[18px] w-[18px]" />
          )}
        </button>
      }
    />
  )
}
