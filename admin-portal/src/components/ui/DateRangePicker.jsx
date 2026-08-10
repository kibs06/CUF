import { useEffect, useRef, useState } from 'react'
import { CalendarDays, ChevronDown, ChevronLeft, ChevronRight } from 'lucide-react'

const DAYS = ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa']

const PRESETS = [
  { label: 'Today', days: 0 },
  { label: 'Last 7 days', days: 7 },
  { label: 'Last 30 days', days: 30 },
  { label: 'All time', days: null },
]

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

export default function DateRangePicker({ from = null, to = null, onChange }) {
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
        className="flex items-center gap-2 rounded-full border border-[#D9D0C7] bg-white py-2 pl-3 pr-3 text-sm font-medium text-[#3B2314] transition-colors hover:border-primary/40 hover:bg-[#FBF8F5]"
      >
        <CalendarDays size={15} className="text-primary" />
        <span className="whitespace-nowrap">{formatRangeLabel(from, to)}</span>
        <ChevronDown size={14} className={`text-[#6B5C4E] transition-transform ${open ? 'rotate-180' : ''}`} />
      </button>

      {open && (
        <div className="absolute right-0 z-30 mt-2 w-72 rounded-2xl border border-[#D9D0C7] bg-white p-4 shadow-xl">
          {/* Presets */}
          <div className="mb-3 flex flex-wrap gap-1.5">
            {PRESETS.map((p) => (
              <button
                key={p.label}
                type="button"
                onClick={() => pickPreset(p)}
                className={`rounded-full px-2.5 py-1 text-xs font-semibold transition-colors ${
                  (!from && !to && p.days === null) || (from && to && p.days !== null && daysAgo(p.days, from))
                    ? 'bg-primary/10 text-primary'
                    : 'bg-[#F5F0EB] text-[#6B5C4E] hover:bg-[#E9E0D6]'
                }`}
              >
                {p.label}
              </button>
            ))}
          </div>

          {/* Month navigation */}
          <div className="mb-2 flex items-center justify-between">
            <button
              type="button"
              onClick={() => setView(new Date(view.getFullYear(), view.getMonth() - 1, 1))}
              className="rounded-lg p-1.5 text-[#6B5C4E] transition-colors hover:bg-[#F5F0EB] hover:text-[#3B2314]"
            >
              <ChevronLeft size={16} />
            </button>
            <p className="text-sm font-semibold text-[#3B2314]">
              {view.toLocaleDateString('en-PH', { month: 'long', year: 'numeric' })}
            </p>
            <button
              type="button"
              onClick={() => setView(new Date(view.getFullYear(), view.getMonth() + 1, 1))}
              className="rounded-lg p-1.5 text-[#6B5C4E] transition-colors hover:bg-[#F5F0EB] hover:text-[#3B2314]"
            >
              <ChevronRight size={16} />
            </button>
          </div>

          {/* Calendar grid */}
          <div className="grid grid-cols-7 gap-0.5 text-center">
            {DAYS.map((d) => (
              <span key={d} className="py-1 text-[10px] font-semibold uppercase text-[#6B5C4E]">
                {d}
              </span>
            ))}
            {getMonthGrid(view).map((day, i) => {
              if (!day) return <span key={`empty-${i}`} />
              const today = startOfDay(new Date()).getTime() === day.getTime()
              const selected = isEndpoint(day)
              const ranged = inRange(day)
              return (
                <button
                  key={day.getTime()}
                  type="button"
                  onClick={() => handleDayClick(day)}
                  className={`relative rounded-lg py-1.5 text-xs transition-colors ${
                    selected
                      ? 'bg-primary font-bold text-white'
                      : ranged
                        ? 'bg-primary/10 text-primary'
                        : 'text-[#3B2314] hover:bg-[#F5F0EB]'
                  }`}
                >
                  {day.getDate()}
                  {today && (
                    <span className={`absolute inset-x-1.5 bottom-0.5 h-0.5 rounded-full ${selected ? 'bg-white' : 'bg-primary'}`} />
                  )}
                </button>
              )
            })}
          </div>

          {/* Footer */}
          <div className="mt-3 flex items-center justify-between border-t border-[#E9E0D6] pt-3">
            <button
              type="button"
              onClick={clear}
              className="text-xs font-semibold text-[#6B5C4E] transition-colors hover:text-error"
            >
              Clear
            </button>
            <button
              type="button"
              onClick={apply}
              disabled={!draftFrom || !draftTo}
              className="rounded-full bg-primary px-4 py-1.5 text-xs font-semibold text-white transition-colors hover:bg-secondary disabled:cursor-not-allowed disabled:opacity-40"
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
