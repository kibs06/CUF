import assert from 'node:assert/strict'
import { test } from 'node:test'

import {
  ALL_TAG_GROUPS,
  MAX_CUSTOM_TAG_LENGTH,
  OTHER_TAG_GROUP,
  PRODUCT_TAG_GROUPS,
  addCustomTag,
  customTagValue,
  groupEntries,
  hasPreset,
  parseStoredTag,
  parseTags,
  removeCustomTag,
  serializeTags,
  togglePreset,
} from './productTags.js'

const TYPE = 'type'
const MATERIAL = 'material'

test('the vocabulary matches the app: three groups, ids unique across all of them', () => {
  assert.deepEqual(
    PRODUCT_TAG_GROUPS.map((group) => group.id),
    ['type', 'material', 'sustainability'],
  )

  const ids = PRODUCT_TAG_GROUPS.flatMap((group) =>
    group.presets.map((preset) => preset.id),
  )
  assert.equal(new Set(ids).size, ids.length, 'a preset id must be unique')

  // The whole point of a global id space: no group prefix is needed on the
  // stored value, so `serializeTags` can write a bare id and `parseStoredTag`
  // can find its group by looking in every group.
  for (const id of ids) {
    assert.match(id, /^[a-z_]+$/, `${id} is not snake_case`)
  }
})

test('parseStoredTag: presets are matched case-insensitively and canonicalised', () => {
  assert.deepEqual(parseStoredTag('handmade'), {
    group: TYPE,
    value: 'handmade',
    custom: false,
  })
  // The app lowercases before comparing and reports the PRESET's spelling, so a
  // tag written by another client in caps converges rather than duplicating.
  assert.deepEqual(parseStoredTag('HANDMADE'), {
    group: TYPE,
    value: 'handmade',
    custom: false,
  })
  assert.deepEqual(parseStoredTag('  Leather '), {
    group: MATERIAL,
    value: 'leather',
    custom: false,
  })
})

test('parseStoredTag: custom entries carry their group and their text', () => {
  assert.deepEqual(parseStoredTag('custom:material:Teal'), {
    group: MATERIAL,
    value: 'Teal',
    custom: true,
  })
  // A colon inside the text is kept — the group is one split, the rest is text.
  assert.deepEqual(parseStoredTag('custom:type:A:B'), {
    group: TYPE,
    value: 'A:B',
    custom: true,
  })
})

test('parseStoredTag: malformed customs and unknown vocabulary become free text', () => {
  // No text after the group: the literal `custom:type:` must never be drawn as
  // a chip. `parseStoredTag` reports an empty value and `parseTags` drops it.
  assert.deepEqual(parseStoredTag('custom:type:'), {
    group: OTHER_TAG_GROUP.id,
    value: '',
    custom: true,
  })
  assert.deepEqual(parseStoredTag('custom:nonsense:value'), {
    group: OTHER_TAG_GROUP.id,
    value: '',
    custom: true,
  })
  // Free text from before the grouped selector — kept, in the other bucket.
  assert.deepEqual(parseStoredTag('Winter'), {
    group: OTHER_TAG_GROUP.id,
    value: 'Winter',
    custom: true,
  })
})

test('parseTags drops the entries that produced nothing', () => {
  const entries = parseTags(['handmade', 'custom:type:', 'custom:material:Teal', ''])
  assert.deepEqual(entries, [
    { group: TYPE, value: 'handmade', custom: false },
    { group: MATERIAL, value: 'Teal', custom: true },
  ])
  assert.deepEqual(parseTags(null), [])
  assert.deepEqual(parseTags(undefined), [])
  assert.deepEqual(parseTags('handmade'), [], 'a bare string is not a tag array')
})

test('groupEntries keeps the other bucket separate from the real groups', () => {
  const entries = parseTags(['handmade', 'Winter'])
  assert.deepEqual(groupEntries(entries, TYPE), [
    { group: TYPE, value: 'handmade', custom: false },
  ])
  assert.deepEqual(groupEntries(entries, OTHER_TAG_GROUP.id), [
    { group: OTHER_TAG_GROUP.id, value: 'Winter', custom: true },
  ])
  assert.deepEqual(groupEntries(entries, 'sustainability'), [])
})

test('togglePreset adds, removes, and never mutates the input', () => {
  const start = []
  const added = togglePreset(start, TYPE, 'handmade')
  assert.deepEqual(start, [], 'the input array is untouched')
  assert.equal(hasPreset(added, TYPE, 'handmade'), true)

  const removed = togglePreset(added, TYPE, 'handmade')
  assert.deepEqual(removed, [])
  assert.equal(hasPreset(removed, TYPE, 'handmade'), false)
})

test('togglePreset targets one group: the same id in another group is not it', () => {
  const entries = togglePreset([], MATERIAL, 'rubber')
  assert.equal(hasPreset(entries, MATERIAL, 'rubber'), true)
  assert.equal(hasPreset(entries, TYPE, 'rubber'), false)
  // Toggling "rubber" in `type` must ADD, not remove the material one.
  assert.equal(togglePreset(entries, TYPE, 'rubber').length, 2)
})

test('addCustomTag refuses the three things the app refuses, in its words', () => {
  const empty = addCustomTag([], TYPE, '   ')
  assert.equal(empty.error, 'Type a tag first.')
  assert.deepEqual(empty.entries, [])

  const long = addCustomTag([], TYPE, 'x'.repeat(MAX_CUSTOM_TAG_LENGTH + 1))
  assert.equal(long.error, 'Keep it under 30 characters.')
  assert.deepEqual(long.entries, [])

  // A preset SOMEWHERE, not just in this group: an entry that duplicates a chip
  // the grouped selector would also draw is the one case a custom tag cannot
  // represent.
  const preset = addCustomTag([], MATERIAL, 'handmade')
  assert.equal(preset.error, 'That is already a preset option — tap it above instead.')
  assert.deepEqual(preset.entries, [])
  const crossGroup = addCustomTag([], TYPE, 'leather')
  assert.equal(crossGroup.error, 'That is already a preset option — tap it above instead.')
})

test('a preset LABEL is refused too — the portal is stricter than the app here', () => {
  // The Dart selector compares only against preset ids, so typing the label its
  // own chip is showing ('Eco-friendly' vs the id 'eco_friendly') slips through
  // and is stored as a custom entry, leaving two chips with one reading. See the
  // note in `addCustomTag`.
  const byLabel = addCustomTag([], MATERIAL, 'Eco-friendly')
  assert.equal(byLabel.error, 'That is already a preset option — tap it above instead.')
  assert.deepEqual(byLabel.entries, [])

  // But it is checked at entry time only: a product created by the app carrying
  // the label as a custom already parses, renders and round-trips untouched.
  const stored = ['custom:material:Eco-friendly']
  assert.deepEqual(serializeTags(parseTags(stored)), stored)
})

test('addCustomTag refuses a duplicate within its own group only', () => {
  const first = addCustomTag([], MATERIAL, 'Teal')
  assert.equal(first.error, null)

  const again = addCustomTag(first.entries, MATERIAL, 'teal')
  assert.equal(again.error, 'That tag is already added.')
  assert.equal(again.entries.length, 1)

  // The same text in a different group is a different tag.
  const other = addCustomTag(first.entries, TYPE, 'teal')
  assert.equal(other.error, null)
  assert.equal(other.entries.length, 2)
})

test('removeCustomTag removes by group and text, leaving presets alone', () => {
  let entries = togglePreset([], MATERIAL, 'leather')
  entries = addCustomTag(entries, MATERIAL, 'Teal').entries
  entries = addCustomTag(entries, TYPE, 'Teal').entries

  const removed = removeCustomTag(entries, MATERIAL, 'Teal')
  assert.equal(removed.length, 2)
  assert.equal(
    removed.some((entry) => entry.custom && entry.group === MATERIAL),
    false,
  )
  // The material preset survives, and the `type` custom is a different entry.
  assert.equal(hasPreset(removed, MATERIAL, 'leather'), true)
  assert.equal(removed.some((entry) => entry.custom && entry.group === TYPE), true)
})

test('serializeTags writes presets before customs, group by group, other last', () => {
  // Added out of order on purpose: a custom in `type` first, then a preset, then
  // a legacy tag. Save must normalise, because this array is what every future
  // read of the product sees.
  let entries = addCustomTag([], TYPE, 'Bespoke fit').entries
  entries = togglePreset(entries, TYPE, 'handmade')
  entries = togglePreset(entries, 'sustainability', 'eco_friendly')
  entries = addCustomTag(entries, OTHER_TAG_GROUP.id, 'Winter').entries

  assert.deepEqual(serializeTags(entries), [
    'handmade',
    'custom:type:Bespoke fit',
    'eco_friendly',
    'custom:other:Winter',
  ])
})

test('serializeTags is the inverse of parseTags for everything it can hold', () => {
  const stored = [
    'handmade',
    'custom:material:Teal',
    'eco_friendly',
    'custom:other:Winter',
  ]
  assert.deepEqual(serializeTags(parseTags(stored)), stored)
})

test('a legacy free-text tag is re-encoded on its first save, as the app does', () => {
  // Not a bug and not an improvement: the Dart selector serialises every custom
  // entry through `custom:<group>:<text>`, so `Winter` becomes
  // `custom:other:Winter` the first time the form saves. The portal matching
  // that keeps one product's tags from growing a second spelling depending on
  // which surface edited it last.
  assert.deepEqual(serializeTags(parseTags(['Winter'])), ['custom:other:Winter'])
})

test('customTagValue is the encoding parseStoredTag expects', () => {
  const value = customTagValue(MATERIAL, ' Teal ')
  assert.equal(value, 'custom:material:Teal')
  assert.deepEqual(parseStoredTag(value), {
    group: MATERIAL,
    value: 'Teal',
    custom: true,
  })
})

test('ALL_TAG_GROUPS is the serialisation order, and ends with the other bucket', () => {
  assert.deepEqual(
    ALL_TAG_GROUPS.map((group) => group.id),
    ['type', 'material', 'sustainability', 'other'],
  )
})
