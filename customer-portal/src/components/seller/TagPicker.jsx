import { useState } from 'react'
import { Plus } from 'lucide-react'

import Chip from '../ui/Chip.jsx'
import {
  MAX_CUSTOM_TAG_LENGTH,
  OTHER_TAG_GROUP,
  PRODUCT_TAG_GROUPS,
  addCustomTag,
  groupEntries,
  removeCustomTag,
  togglePreset,
} from '../../lib/productTags.js'

/**
 * Tags, grouped — a port of the app's `TagSelector`.
 *
 * ## What a seller is choosing
 *
 * Three closed groups (product type, material, sustainability) plus one hand-typed
 * value per group, because the vocabulary is a starting point rather than a limit:
 * a seller whose leather is vegetable-tanned needs to say so. The "other" group
 * is not editable — it is where free text saved before the grouped selector
 * existed is drawn, so those tags are visible and removable rather than invisible
 * and permanent.
 *
 * ## Why the entries are the state, not the strings
 *
 * `products.tags` is a `TEXT[]` of preset ids and `custom:<group>:<text>`
 * encodings, which is not something a chip can be drawn from — the label lives in
 * the vocabulary, and a custom entry's group is what puts it back in the right
 * row. So this holds parsed entries and hands the caller entries; the encoding
 * happens once, in `productColumnsFromDraft`. Keeping the strings here would mean
 * every render decoded them.
 */
export default function TagPicker({ entries, onChange, disabled = false }) {
  const [typing, setTyping] = useState(null) // the group whose input is open
  const [drafts, setDrafts] = useState({})
  const [error, setError] = useState(null)

  const apply = (next) => {
    setError(null)
    onChange(next)
  }

  const addCustom = (group) => {
    const { entries: next, error: problem } = addCustomTag(
      entries,
      group,
      drafts[group] ?? '',
    )
    if (problem) {
      setError(problem)
      return
    }
    setDrafts((current) => ({ ...current, [group]: '' }))
    setTyping(null)
    apply(next)
  }

  const otherEntries = groupEntries(entries, OTHER_TAG_GROUP.id)

  return (
    <div className="space-y-5">
      {PRODUCT_TAG_GROUPS.map((group) => {
        const inGroup = groupEntries(entries, group.id)
        const customs = inGroup.filter((entry) => entry.custom)
        const isOpen = typing === group.id

        return (
          <div key={group.id}>
            <p className="text-xs font-semibold uppercase tracking-[0.08em] text-muted">
              {group.label}
            </p>

            <div className="mt-2.5 flex flex-wrap gap-2">
              {group.presets.map((preset) => (
                <Chip
                  key={preset.id}
                  label={preset.label}
                  selected={inGroup.some(
                    (entry) => !entry.custom && entry.value === preset.id,
                  )}
                  disabled={disabled}
                  onClick={() =>
                    apply(togglePreset(entries, group.id, preset.id))
                  }
                />
              ))}

              {/*
                The "+ Other" toggle. `aria-expanded` rather than a pressed state:
                it opens an input, it does not select anything — and a chip that
                claimed to be selected while nothing had been typed yet would be
                lying about the product's tags.
              */}
              <button
                type="button"
                onClick={() => {
                  setError(null)
                  setTyping(isOpen ? null : group.id)
                }}
                disabled={disabled}
                aria-expanded={isOpen}
                aria-controls={`tag-input-${group.id}`}
                className={`inline-flex items-center gap-1.5 rounded-full border border-dashed px-3 py-1.5 text-xs font-semibold transition-colors duration-200 ease-out-cubic ${
                  isOpen
                    ? 'border-clay text-clay-ink'
                    : 'border-hairline text-muted hover:border-card-edge hover:text-ink'
                }`}
              >
                <Plus className="h-3.5 w-3.5" aria-hidden="true" />
                {isOpen ? 'Close' : 'Other'}
              </button>
            </div>

            {customs.length > 0 && (
              <div className="mt-2.5 flex flex-wrap gap-2">
                {customs.map((entry) => (
                  <Chip
                    key={`${group.id}-${entry.value}`}
                    label={entry.value}
                    disabled={disabled}
                    onRemove={() =>
                      apply(removeCustomTag(entries, group.id, entry.value))
                    }
                  />
                ))}
              </div>
            )}

            {isOpen && (
              <div id={`tag-input-${group.id}`} className="mt-3 flex gap-2">
                <input
                  value={drafts[group.id] ?? ''}
                  onChange={(event) =>
                    setDrafts((current) => ({
                      ...current,
                      [group.id]: event.target.value,
                    }))
                  }
                  onKeyDown={(event) => {
                    if (event.key === 'Enter') {
                      event.preventDefault()
                      addCustom(group.id)
                    }
                  }}
                  maxLength={MAX_CUSTOM_TAG_LENGTH}
                  disabled={disabled}
                  autoFocus
                  placeholder={`Add your own ${group.label.toLowerCase()}…`}
                  aria-label={`Your own ${group.label.toLowerCase()} tag`}
                  className="h-10 flex-1 rounded-field border border-hairline bg-raised px-3 text-sm text-ink placeholder:text-muted/60"
                />
                <button
                  type="button"
                  onClick={() => addCustom(group.id)}
                  disabled={disabled || !(drafts[group.id] ?? '').trim()}
                  className="btn btn-outline h-10 py-0"
                >
                  Add
                </button>
              </div>
            )}
          </div>
        )
      })}

      {otherEntries.length > 0 && (
        <div>
          <p className="text-xs font-semibold uppercase tracking-[0.08em] text-muted">
            {OTHER_TAG_GROUP.label}
          </p>
          <p className="mt-1 text-xs text-muted">
            Tags saved before this vocabulary existed. They still work, and they
            can be removed.
          </p>
          <div className="mt-2.5 flex flex-wrap gap-2">
            {otherEntries.map((entry) => (
              <Chip
                key={`other-${entry.value}`}
                label={entry.value}
                disabled={disabled}
                onRemove={() =>
                  apply(removeCustomTag(entries, OTHER_TAG_GROUP.id, entry.value))
                }
              />
            ))}
          </div>
        </div>
      )}

      {error && (
        <p role="alert" className="text-xs font-medium text-crimson">
          {error}
        </p>
      )}
    </div>
  )
}
