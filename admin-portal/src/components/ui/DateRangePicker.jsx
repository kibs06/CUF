import { useEffect, useRef, useState } from 'react'
import { CalendarDays, ChevronDown, ChevronLeft, ChevronRight } from 'lucide-react'

const DAYS = ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa']

const PRESETS = [
  { label: 'Today', days: 0 },
  { label: 'Last 7 days', days: 7 },
  { label: 'Last 30 days', days: 30 },
  { label: 'All time', days: null },
]

/** `YYYY-MM-DD` (what the admin filters keep in state) → local Date at midnight. */
export function parseISODate(value) {
  if (!value) return null
  const [year, month, day] = value.split('-').map(Number)
  return new Date(year, month - 1, day)
}

/** local Date → `YYYY-MM-DD`, or '' for no bound. */
export function toISODate(date) {
  if (!date) return ''
  const month = String(date.getMonth() + 1).padStart(2, '0')
  const day = String(date.getDate()).padStart(2, '0')
  return `${date.getFullYear()}-${month}-${day}`
}

function startOfDay(d) {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate())
}

function formatDay(d) {
  return d.toLocaleDateString('en-PH', { month: 'short', day: 'numeric' })
}

function formatRangeLabel(from, to) {
  if (!from || !to) return 'All time'
  if (from.getTime() === to.getTime()) {
    return from.toLocaleDateString('en-PH', { month: 'short', day: 'numeric', year: 'numeric' })
  }
  if (from.getFullYear() === to.getFullYear() && from.getMonth() === to.getMonth()) {
    return `${from.toLocaleDateString('en-PH', { month: 'short', day: 'numeric' })} – ${to.toLocaleDateString('en-PH', { month: 'short', day: 'numeric', year: 'numeric' })}`
  }
  if (from.getFullYear() === to.getFullYear()) {
    return `${formatDay(from)} – ${formatDay(to)}, ${to.getFullYear()}`
  }
  return `${formatDay(from)}, ${from.getFullYear()} – ${formatDay(to)}, ${to.getFullYear()}`
}

function getMonthGrid(monthDate) {
  const year = monthDate.getFullYear()
  const month = monthDate.getMonth()
  const startOffset = new Date(year, month, 1).getDay()
  const daysInMonth = new Date(year, month + 1, 0).getDate()
  const cells = []
  for (let i = 0; i < startOffset; i++) cells.push(null)
  for (let d = 1; d <= daysInMonth; d++) cells.push(new Date(year, month, d))
  return cells
}

export default function DateRangePicker({ from = null, to = null, onChange, align = 'right' }) {
  const [open, setOpen] = useState(false)
  const [draftFrom, setDraftFrom] = useState(from)
  const [draftTo, setDraftTo] = useState(to)
  const [view, setView] = useState(() => startOfDay(from ?? new Date()))
  const rootRef = useRef(null)

  useEffect(() => {
    if (!open) return undefined
    function onPointerDown(e) {
      if (rootRef.current && !rootRef.current.contains(e.target)) setOpen(false)
    }
    function onKeyDown(e) {
      if (e.key === 'Escape') setOpen(false)
    }
    document.addEventListener('mousedown', onPointerDown)
    document.addEventListener('keydown', onKeyDown)
    return () => {
      document.removeEventListener('mousedown', onPointerDown)
      document.removeEventListener('keydown', onKeyDown)
    }
  }, [open])

  function openPicker() {
    setDraftFrom(from)
    setDraftTo(to)
    setView(startOfDay(from ?? new Date()))
    setOpen(true)
  }

  function pickPreset(p) {
    if (p.days === null) {
      onChange(null, null)
    } else {
      const end = startOfDay(new Date())
      const start = new Date(end)
      start.setDate(start.getDate() - p.days)
      onChange(start, end)
    }
    setOpen(false)
  }

  function handleDayClick(day) {
    if (!draftFrom || (draftFrom && draftTo)) {
      setDraftFrom(day)
      setDraftTo(null)
    } else if (day < draftFrom) {
      setDraftTo(draftFrom)
      setDraftFrom(day)
    } else {
      setDraftTo(day)
    }
  }

  function apply() {
    if (draftFrom && draftTo) onChange(draftFrom, draftTo)
    setOpen(false)
  }

  function clear() {
    onChange(null, null)
    setOpen(false)
  }

  function inRange(day) {
    if (!draftFrom || !draftTo) return false
    return day >= draftFrom && day <= draftTo
  }

  function isEndpoint(day) {
    return (draftFrom && day.getTime() === draftFrom.getTime()) || (draftTo && day.getTime() === draftTo.getTime())
  }

  return (
    <div ref={rootRef} className="relative">
      <button
        type="button"
        onClick={openPicker}
        aria-haspopup="dialog"
        aria-expanded={open}
        className="flex h-9 w-full items-center justify-between gap-2 rounded-lg border border-border bg-card px-3 text-[12.5px] font-medium text-ink outline-none transition-colors duration-200 ease-[cubic-bezier(0.32,0.72,0,1)] hover:border-primary/40 hover:bg-canvas focus-visible:border-primary focus-visible:ring-2 focus-visible:ring-primary/15"
      >
        <CalendarDays size={14} strokeWidth={1.7} className="shrink-0 text-primary" aria-hidden="true" />
        <span className="min-w-0 flex-1 truncate text-center">{formatRangeLabel(from, to)}</span>
        <ChevronDown
          size={14}
          strokeWidth={1.7}
          aria-hidden="true"
          className={`shrink-0 text-muted transition-transform duration-200 ease-[cubic-bezier(0.32,0.72,0,1)] ${
            open ? 'rotate-180' : ''
          }`}
        />
      </button>

      {open && (
        <div
          role="dialog"
          aria-label="Choose a date range"
          className={`absolute z-30 mt-2 w-[336px] max-w-[calc(100vw-2rem)] rounded-2xl border border-border bg-card p-4 shadow-pop ${
            align === 'left' ? 'left-0' : 'right-0'
          }`}
        >
          <div className="mb-3 flex flex-wrap gap-1.5">
            {PRESETS.map((preset) => {
              const active =
                (!from && !to && preset.days === null) ||
                (from && to && preset.days !== null && daysAgo(preset.days, from))
              return (
                <button
                  key={preset.label}
                  type="button"
                  onClick={() => pickPreset(preset)}
                  aria-pressed={active}
                  className={`rounded-full px-3 py-1.5 text-[12px] font-semibold transition-colors ${
                    active
                      ? 'bg-[#E5D7C6] text-secondary'
                      : 'bg-[#F4EEE7] text-muted hover:bg-[#EBE1D6] hover:text-secondary'
                  }`}
                >
                  {preset.label}
                </button>
              )
            })}
          </div>

          <div className="mb-2 flex items-center justify-between">
            <button
              type="button"
              onClick={() => setView(new Date(view.getFullYear(), view.getMonth() - 1, 1))}
              aria-label="Previous month"
              className="inline-flex h-7 w-7 items-center justify-center rounded-lg text-muted transition-colors hover:bg-canvas hover:text-ink"
            >
              <ChevronLeft size={16} strokeWidth={1.7} />
            </button>
            <p className="text-sm font-semibold text-ink">
              {view.toLocaleDateString('en-PH', { month: 'long', year: 'numeric' })}
            </p>
            <button
              type="button"
              onClick={() => setView(new Date(view.getFullYear(), view.getMonth() + 1, 1))}
              aria-label="Next month"
              className="inline-flex h-7 w-7 items-center justify-center rounded-lg text-muted transition-colors hover:bg-canvas hover:text-ink"
            >
              <ChevronRight size={16} strokeWidth={1.7} />
            </button>
          </div>

          <div className="grid grid-cols-7 gap-0.5 text-center">
            {DAYS.map((day) => (
              <span
                key={day}
                className="py-1 text-[10px] font-medium uppercase tracking-[0.08em] text-muted"
              >
                {day}
              </span>
            ))}
            {getMonthGrid(view).map((day, index) => {
              if (!day) return <span key={`empty-${index}`} />
              const today = startOfDay(new Date()).getTime() === day.getTime()
              const selected = isEndpoint(day)
              const ranged = inRange(day)
              return (
                <button
                  key={day.getTime()}
                  type="button"
                  onClick={() => handleDayClick(day)}
                  aria-label={day.toLocaleDateString('en-PH', {
                    weekday: 'long',
                    month: 'long',
                    day: 'numeric',
                    year: 'numeric',
                  })}
                  aria-pressed={selected}
                  className={`relative flex h-8 items-center justify-center rounded-lg text-[12px] transition-colors ${
                    selected
                      ? 'bg-primary font-semibold text-white'
                      : ranged
                        ? 'bg-[#F1E9E0] text-secondary'
                        : 'text-ink hover:bg-canvas'
                  }`}
                >
                  {day.getDate()}
                  {today && (
                    <span
                      aria-hidden="true"
                      className={`absolute inset-x-2 bottom-0.5 h-[2px] rounded-full ${
                        selected ? 'bg-card' : 'bg-primary'
                      }`}
                    />
                  )}
                </button>
              )
            })}
          </div>

          <div className="mt-3 flex items-center justify-between border-t border-border/70 pt-3">
            <button
              type="button"
              onClick={clear}
              className="text-[12px] font-semibold text-muted transition-colors hover:text-error"
            >
              Clear
            </button>
            <button
              type="button"
              onClick={apply}
              disabled={!draftFrom || !draftTo}
              className="rounded-full bg-primary px-4 py-1.5 text-[12px] font-semibold text-white transition-colors hover:bg-secondary disabled:cursor-not-allowed disabled:opacity-40"
            >
              Apply
            </button>
          </div>
        </div>
      )}
    </div>
  )
}

function daysAgo(days, from) {
  const target = startOfDay(new Date())
  target.setDate(target.getDate() - days)
  return from.getTime() === target.getTime()
}
