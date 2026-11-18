import { AlertTriangle, CheckCircle2 } from 'lucide-react'

/**
 * Shared visual primitives for the manual-GCash flow.
 *
 * The four screens in this flow (platform account, verification queue,
 * payouts) are one workflow, so they share one surface language: a cream
 * extruded tray around a machined inner face, mono eyebrow labels, Playfair
 * panel titles, pill CTAs with a nested icon circle, and a staggered
 * fade-up on entry. Anything that needs to look like this flow should import
 * from here rather than copy the class strings.
 */
export const EASE = 'ease-[cubic-bezier(0.32,0.72,0,1)]'

export const FIELD_CLASS =
  'h-11 w-full rounded-xl border border-border bg-canvas px-3.5 text-sm text-ink outline-none ' +
  `transition-[border-color,box-shadow,background-color] duration-300 ${EASE} ` +
  'placeholder:text-muted/50 focus:border-primary focus:bg-white ' +
  'focus:shadow-[0_0_0_3px_rgba(139,90,43,0.12)]'

/** Staggered entry wrapper. Motion lives in `.gcash-rise` in index.css. */
export function Rise({ delay = 0, className = '', children, ...rest }) {
  return (
    <div
      {...rest}
      className={`gcash-rise ${className}`}
      style={{ animationDelay: `${delay}ms` }}
    >
      {children}
    </div>
  )
}

/** Mono eyebrow + display title + one specific line. */
export function PageHeader({ eyebrow = 'Operations', title, description, actions }) {
  return (
    <Rise>
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div className="min-w-0">
          <p className="font-mono text-[10px] uppercase tracking-[0.24em] text-muted">
            {eyebrow}
          </p>
          <h1 className="mt-2 font-display text-3xl leading-[1.05] tracking-tight text-ink sm:text-[38px]">
            {title}
          </h1>
          {description ? (
            <p className="mt-3 max-w-2xl text-[13px] leading-relaxed text-muted">
              {description}
            </p>
          ) : null}
        </div>
        {actions ? <div className="flex flex-wrap items-center gap-3">{actions}</div> : null}
      </div>
    </Rise>
  )
}

/** Double-bezel card: outer tray, then the inner face that holds content. */
export function Panel({
  eyebrow,
  title,
  description,
  children,
  aside,
  delay = 0,
  dark = false,
  innerClassName = '',
  className = '',
}) {
  return (
    <Rise
      delay={delay}
      className={`rounded-[28px] bg-white/55 p-1.5 ring-1 ring-secondary/[0.07] shadow-[0_20px_44px_-34px_rgba(59,35,20,0.55)] ${className}`}
    >
      <section
        className={
          dark
            ? `rounded-[22px] border border-secondary/20 bg-[linear-gradient(170deg,#2E1C10_0%,#3B2314_100%)] p-6 text-[#F5F0EB] shadow-[inset_0_1px_0_rgba(255,255,255,0.12)] ${innerClassName}`
            : `rounded-[22px] border border-border/70 bg-[linear-gradient(155deg,#ffffff_0%,#fffdfa_58%,#f8f2ea_100%)] p-6 shadow-[inset_0_1px_0_rgba(255,255,255,0.95),inset_0_-1px_0_rgba(59,35,20,0.05)] ${innerClassName}`
        }
      >
        {title || eyebrow ? (
          <div className="flex flex-wrap items-start justify-between gap-3">
            <div className="min-w-0">
              {eyebrow ? (
                <p
                  className={`font-mono text-[10px] uppercase tracking-[0.2em] ${
                    dark ? 'text-[#C4A882]' : 'text-muted'
                  }`}
                >
                  {eyebrow}
                </p>
              ) : null}
              {title ? (
                <h2 className="mt-1.5 font-display text-[19px] leading-tight">
                  {title}
                </h2>
              ) : null}
              {description ? (
                <p
                  className={`mt-1.5 max-w-xl text-[12px] leading-relaxed ${
                    dark ? 'text-[#C4A882]' : 'text-muted'
                  }`}
                >
                  {description}
                </p>
              ) : null}
            </div>
            {aside}
          </div>
        ) : null}
        <div className={title || eyebrow ? 'mt-6' : ''}>{children}</div>
      </section>
    </Rise>
  )
}

/** Mono label, control, then a hint that doubles as the error slot. */
export function Field({ label, hint, error, htmlFor, children, className = '' }) {
  return (
    <div className={className}>
      <label
        htmlFor={htmlFor}
        className="block font-mono text-[10px] uppercase tracking-[0.16em] text-muted"
      >
        {label}
      </label>
      <div className="mt-2">{children}</div>
      <p
        className={`mt-1.5 text-[11px] leading-snug ${
          error ? 'text-error' : 'text-muted'
        }`}
      >
        {error || hint}
      </p>
    </div>
  )
}

/** Full pill CTA with the icon living in its own circle inside the pill. */
export function PrimaryButton({ children, icon: Icon, className = '', ...props }) {
  return (
    <button
      {...props}
      className={`group inline-flex h-11 items-center gap-2 rounded-full bg-primary pl-5 pr-1.5 text-[12px] font-semibold text-white shadow-[0_12px_26px_-16px_rgba(111,69,32,0.9)] transition-[background-color,transform,box-shadow] duration-300 ${EASE} hover:bg-primaryDeep active:scale-[0.98] disabled:cursor-not-allowed disabled:opacity-45 ${className}`}
    >
      {children}
      <span
        className={`flex h-8 w-8 items-center justify-center rounded-full bg-white/15 transition-transform duration-300 ${EASE} group-hover:translate-x-0.5 group-hover:-translate-y-px`}
      >
        {Icon ? <Icon size={14} strokeWidth={1.6} /> : null}
      </span>
    </button>
  )
}

const ACTION_TONES = {
  primary:
    'bg-primary text-white hover:bg-primaryDeep shadow-[0_10px_22px_-16px_rgba(111,69,32,0.9)]',
  accent: 'bg-accent text-white hover:bg-accent/90',
  success: 'bg-[#4F6B35] text-white hover:bg-[#445C2D]',
  ghost: 'border border-border bg-white/60 text-ink hover:border-primary/40 hover:bg-surface',
  danger: 'border border-error/35 bg-white/60 text-error hover:bg-errorSoft',
}

/**
 * Row-level action. Same pill geometry as [PrimaryButton] at a smaller size,
 * so a dense queue still reads as the same product.
 */
export function ActionPill({
  children,
  icon: Icon,
  tone = 'ghost',
  className = '',
  ...props
}) {
  return (
    <button
      {...props}
      className={`inline-flex h-9 items-center gap-2 rounded-full pl-3.5 pr-1 text-[11px] font-semibold transition-[background-color,border-color,transform] duration-300 ${EASE} active:scale-[0.98] disabled:cursor-not-allowed disabled:opacity-45 ${ACTION_TONES[tone] ?? ACTION_TONES.ghost} ${className}`}
    >
      {children}
      <span
        className={`flex h-6 w-6 items-center justify-center rounded-full ${
          tone === 'ghost' || tone === 'danger' ? 'bg-canvas' : 'bg-white/15'
        }`}
      >
        {Icon ? <Icon size={12} strokeWidth={1.7} /> : null}
      </span>
    </button>
  )
}

const PILL_TONES = {
  ok: 'bg-accentSoft text-accent',
  warn: 'bg-[#F6E7C6] text-[#8A5D14]',
  danger: 'bg-errorSoft text-error',
  muted: 'bg-canvas text-muted',
}

export function StatusPill({ tone = 'muted', icon: Icon, children }) {
  return (
    <span
      className={`inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 font-mono text-[10px] uppercase tracking-[0.12em] ${
        PILL_TONES[tone] ?? PILL_TONES.muted
      }`}
    >
      {Icon ? <Icon size={11} strokeWidth={1.8} /> : <span className="h-1.5 w-1.5 rounded-full bg-current" />}
      {children}
    </span>
  )
}

/** Inset well for grouped facts (proof details, money breakdowns). */
export function InsetTile({ children, className = '' }) {
  return (
    <div
      className={`rounded-2xl border border-border/70 bg-canvas/70 px-4 py-3.5 ${className}`}
    >
      {children}
    </div>
  )
}

/** One label/value fact, mono value, safe to wrap at narrow widths. */
export function Fact({ label, children, tone }) {
  return (
    <div className="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-0.5">
      <span className="font-mono text-[9.5px] uppercase tracking-[0.14em] text-muted">
        {label}
      </span>
      <span
        className={`font-mono text-[12px] tabular-nums ${
          tone === 'danger' ? 'text-error' : tone === 'ok' ? 'text-accent' : 'text-ink'
        }`}
      >
        {children}
      </span>
    </div>
  )
}

export function InlineMessage({ tone = 'ok', children }) {
  if (!children) return null
  return (
    <Rise
      role="status"
      className={`rounded-2xl border px-4 py-3 text-xs ${
        tone === 'ok'
          ? 'border-accent/25 bg-accentSoft/70 text-ink'
          : 'border-error/25 bg-errorSoft text-error'
      }`}
    >
      {children}
    </Rise>
  )
}

export function EmptyPanel({ icon: Icon = CheckCircle2, title, hint }) {
  return (
    <div className="rounded-2xl border border-dashed border-border bg-canvas/70 px-5 py-8 text-center">
      <Icon size={22} strokeWidth={1.4} className="mx-auto text-muted/70" />
      <p className="mt-2 text-[12px] font-medium text-ink">{title}</p>
      {hint ? <p className="mx-auto mt-1 max-w-sm text-[11px] text-muted">{hint}</p> : null}
    </div>
  )
}

/** Flag glyph used in the verification queue. */
export const FlagIcon = AlertTriangle
