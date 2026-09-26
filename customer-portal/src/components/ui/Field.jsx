/**
 * A labelled form field.
 *
 * The error is wired through `aria-describedby` and `aria-invalid` rather than
 * only coloured red — a customer using a screen reader has to be *told* the
 * password was too short, not shown it.
 *
 * Two slots exist so callers do not have to re-implement the field to add
 * something to it:
 *
 *  - `labelAction` sits on the label's own line, right-aligned. It is where
 *    "Forgot?" goes: the link belongs beside the thing it rescues rather than
 *    as a second button under the form, where it competes with submit.
 *  - `trailing` sits inside the control, right-aligned. The password reveal in
 *    `PasswordField` is the only current user; keeping it here is what lets the
 *    toggle inherit the field's height, radius and focus treatment instead of
 *    restating them somewhere that will drift.
 *
 * `children` still replaces the control entirely — a `<select>`, a composite
 * date row — and in that case the two slots are the caller's business.
 */
export default function Field({
  id,
  label,
  type = 'text',
  value,
  onChange,
  error,
  hint,
  required = false,
  autoComplete,
  placeholder,
  labelAction,
  trailing,
  children,
  ...rest
}) {
  return (
    <div>
      <div className="flex items-baseline justify-between gap-3">
        <label
          htmlFor={id}
          className="block text-xs font-semibold uppercase tracking-[0.08em] text-muted"
        >
          {label}
          {!required && (
            <span className="ml-2 font-normal normal-case tracking-normal text-muted/70">
              optional
            </span>
          )}
        </label>
        {labelAction}
      </div>

      {children ?? (
        <div className="relative mt-2">
          <input
            id={id}
            type={type}
            value={value ?? ''}
            onChange={(event) => onChange?.(event.target.value)}
            autoComplete={autoComplete}
            placeholder={placeholder}
            aria-invalid={error ? 'true' : undefined}
            aria-describedby={error ? `${id}-error` : undefined}
            className={`h-11 w-full rounded-field border bg-raised text-sm text-ink transition-colors duration-200 ease-out-cubic placeholder:text-muted/60 ${
              trailing ? 'pl-4 pr-12' : 'px-4'
            } ${
              error
                ? 'border-crimson'
                : 'border-hairline hover:border-card-edge focus:border-clay'
            }`}
            {...rest}
          />
          {trailing && (
            <div className="absolute inset-y-0 right-0 flex items-center pr-1.5">
              {trailing}
            </div>
          )}
        </div>
      )}

      {hint && !error && (
        <p className="mt-1.5 text-xs text-muted">{hint}</p>
      )}
      {error && (
        <p id={`${id}-error`} className="mt-1.5 text-xs font-medium text-crimson">
          {error}
        </p>
      )}
    </div>
  )
}
