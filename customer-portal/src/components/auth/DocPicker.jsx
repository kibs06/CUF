import { useEffect, useRef, useState } from 'react'
import { ImagePlus, X } from 'lucide-react'

import { validateDocFile } from '../../lib/sellerApplicationRules.js'

function formatSize(bytes) {
  if (!bytes && bytes !== 0) return ''
  if (bytes < 1024) return `${bytes} B`
  if (bytes < 1024 * 1024) return `${Math.round(bytes / 1024)} KB`
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`
}

/**
 * One required photo, as a dropzone rather than a bare file row.
 *
 * A naked `<input type="file">` tells the applicant nothing about what happens
 * next; this shows the photo the moment it is picked (proof it landed), names
 * the file and its size, and offers removal. Drag-and-drop is a second way in,
 * never the only one — the input stays a real, keyboard-reachable control, and
 * the dropzone's ring follows `focus-within` so keyboard users see where they
 * are. Rejected files explain themselves instead of silently doing nothing.
 */
export default function DocPicker({
  id,
  label,
  hint,
  file,
  error,
  onChange,
  required = false,
}) {
  const [dragging, setDragging] = useState(false)
  const [localError, setLocalError] = useState(null)
  const [preview, setPreview] = useState(null)
  const dragCount = useRef(0)
  const shown = error ?? localError

  useEffect(() => {
    if (!file) {
      setPreview(null)
      return undefined
    }
    const url = URL.createObjectURL(file)
    setPreview(url)
    return () => URL.revokeObjectURL(url)
  }, [file])

  const accept = (picked) => {
    if (!picked) return
    const problem = validateDocFile(picked)
    if (problem) {
      setLocalError(problem)
      return
    }
    setLocalError(null)
    onChange(picked)
  }

  return (
    <div>
      <p className="block text-xs font-semibold uppercase tracking-[0.08em] text-muted">
        {label}
        {!required && (
          <span className="ml-2 font-normal normal-case tracking-normal text-muted/70">
            optional
          </span>
        )}
      </p>

      <div
        onDragEnter={(event) => {
          event.preventDefault()
          dragCount.current += 1
          setDragging(true)
        }}
        onDragLeave={(event) => {
          event.preventDefault()
          dragCount.current = Math.max(0, dragCount.current - 1)
          if (dragCount.current === 0) setDragging(false)
        }}
        onDragOver={(event) => event.preventDefault()}
        onDrop={(event) => {
          event.preventDefault()
          dragCount.current = 0
          setDragging(false)
          accept(event.dataTransfer.files?.[0] ?? null)
        }}
        className={`mt-2 flex items-center gap-4 rounded-field border border-dashed p-3 transition-colors duration-200 ease-out-cubic focus-within:border-clay focus-within:ring-2 focus-within:ring-clay/30 ${
          dragging
            ? 'border-clay bg-clay/10'
            : shown
              ? 'border-crimson/50'
              : 'border-card-edge hover:border-clay/60'
        }`}
      >
        {preview ? (
          <img
            src={preview}
            alt={`${label} preview`}
            className="h-16 w-16 shrink-0 rounded-field border border-hairline object-cover"
          />
        ) : (
          <span
            aria-hidden="true"
            className="flex h-16 w-16 shrink-0 items-center justify-center rounded-field bg-subtle text-muted"
          >
            <ImagePlus className="h-6 w-6" />
          </span>
        )}

        <div className="min-w-0 flex-1">
          {file ? (
            <>
              <p className="truncate text-sm font-semibold text-ink">{file.name}</p>
              <p className="mt-0.5 text-xs text-muted">{formatSize(file.size)} · JPG or PNG</p>
              <button
                type="button"
                onClick={() => {
                  setLocalError(null)
                  onChange(null)
                }}
                className="mt-1.5 inline-flex cursor-pointer items-center gap-1 text-xs font-semibold text-crimson underline-offset-4 hover:underline"
              >
                <X className="h-3.5 w-3.5" aria-hidden="true" />
                Remove and choose another
              </button>
            </>
          ) : (
            <>
              <label
                htmlFor={id}
                className="cursor-pointer text-sm font-semibold text-clay-ink underline-offset-4 hover:underline"
              >
                Choose a photo
              </label>
              <p className="mt-0.5 text-xs text-muted">or drag it here · JPG or PNG, under 10 MB</p>
            </>
          )}
          <input
            id={id}
            type="file"
            accept="image/jpeg,image/png"
            onChange={(event) => {
              accept(event.target.files?.[0] ?? null)
              event.target.value = ''
            }}
            aria-invalid={shown ? 'true' : undefined}
            aria-describedby={shown ? `${id}-error` : undefined}
            className="sr-only"
          />
        </div>
      </div>

      {hint && !shown && <p className="mt-1.5 text-xs text-muted">{hint}</p>}
      {shown && (
        <p id={`${id}-error`} className="mt-1.5 text-xs font-medium text-crimson">
          {shown}
        </p>
      )}
    </div>
  )
}
