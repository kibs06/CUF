import assert from 'node:assert/strict'
import { test } from 'node:test'

import {
  CUSTOMIZATION_TYPES,
  DEFAULT_CUSTOMIZATION_TYPE,
  MAX_CUSTOM_TYPE_LENGTH,
  addChoice,
  customizationFromRow,
  customizationProblems,
  customizationRowsForInsert,
  customizationTotals,
  customizationTypeLabel,
  customizationsFromProduct,
  emptyCustomization,
  removeChoice,
  typeHasChoices,
} from './productCustomizations.js'

const STORED = [
  {
    id: 1,
    option_name: 'Engraving text',
    option_type: 'text',
    options: [],
    is_required: false,
    additional_price: 0,
  },
  {
    id: 2,
    option_name: 'Sole colour',
    option_type: 'color',
    options: ['Tan', 'Black'],
    is_required: true,
    additional_price: 75,
  },
]

test('the three built-in types are the app’s, with the app’s labels', () => {
  assert.deepEqual(CUSTOMIZATION_TYPES, [
    { value: 'text', label: 'Text' },
    { value: 'select', label: 'Select' },
    { value: 'color', label: 'Color' },
  ])
  assert.equal(DEFAULT_CUSTOMIZATION_TYPE, 'text')
})

test('customizationTypeLabel shows a preset’s label, or the type as typed', () => {
  assert.equal(customizationTypeLabel('text'), 'Text')
  assert.equal(customizationTypeLabel('color'), 'Color')
  // The column's CHECK was relaxed to allow invented types on purpose, so an
  // unrecognised one is shown as it was typed rather than relabelled 'Text' —
  // which would silently change what a customer is asked for.
  assert.equal(customizationTypeLabel('file upload'), 'file upload')
  assert.equal(customizationTypeLabel('  Number  '), 'Number')
  assert.equal(customizationTypeLabel(''), '')
  assert.equal(customizationTypeLabel(null), '')
})

test('typeHasChoices is the two types the app shows a choice list for', () => {
  assert.equal(typeHasChoices('select'), true)
  assert.equal(typeHasChoices('color'), true)
  assert.equal(typeHasChoices('text'), false)
  assert.equal(typeHasChoices('number'), false)
  assert.equal(typeHasChoices(undefined), false)
})

test('customizationFromRow coerces what Postgres returns', () => {
  assert.deepEqual(
    customizationFromRow({
      option_name: '  Engraving ',
      option_type: '',
      options: [' Red ', '', null],
      is_required: 'yes',
      additional_price: '25.5',
    }),
    {
      option_name: 'Engraving',
      option_type: 'text',
      options: ['Red'],
      // Strictly `true`: `'yes'` is not a boolean, and defaulting a truthy
      // string to a required option would make an option compulsory that the
      // database says is optional.
      is_required: false,
      additional_price: 25.5,
    },
  )

  assert.deepEqual(customizationFromRow({}), {
    option_name: '',
    option_type: 'text',
    options: [],
    is_required: false,
    additional_price: 0,
  })
})

test('customizationsFromProduct keeps the order the rows come back in', () => {
  const list = customizationsFromProduct(STORED)
  assert.deepEqual(
    list.map((customization) => customization.option_name),
    ['Engraving text', 'Sole colour'],
  )
  assert.deepEqual(list[1].options, ['Tan', 'Black'])
  assert.deepEqual(customizationsFromProduct(null), [])
})

test('emptyCustomization starts on a type, so a save never lacks one', () => {
  assert.deepEqual(emptyCustomization(), {
    option_name: '',
    option_type: 'text',
    options: [],
    is_required: false,
    additional_price: 0,
  })
  assert.equal(emptyCustomization({ is_required: true }).is_required, true)
})

test('addChoice trims, ignores a blank, and refuses a duplicate', () => {
  const first = addChoice(emptyCustomization(), '  Red ')
  assert.deepEqual(first.customization.options, ['Red'])
  assert.equal(first.error, null)

  // The app's add button silently ignores a blank; refusing to move is the same
  // outcome without a state change.
  const blank = addChoice(first.customization, '   ')
  assert.equal(blank.customization, first.customization)
  assert.equal(blank.error, null)

  const again = addChoice(first.customization, 'red')
  assert.equal(again.error, 'That choice is already added.')
  assert.deepEqual(again.customization.options, ['Red'])
})

test('removeChoice removes one, leaving the rest in order', () => {
  const customization = emptyCustomization({ options: ['Tan', 'Black', 'Olive'] })
  assert.deepEqual(removeChoice(customization, 'Black').options, ['Tan', 'Olive'])
  assert.deepEqual(removeChoice(customization, 'Navy').options, [
    'Tan',
    'Black',
    'Olive',
  ])
})

test('customizationProblems: a name and a type, in the app’s own two refusals', () => {
  assert.deepEqual(customizationProblems(emptyCustomization()).errors, [
    'Give the option a name.',
  ])
  assert.deepEqual(
    customizationProblems(
      emptyCustomization({ option_name: 'Engraving', option_type: '  ' }),
    ).errors,
    ['Choose a kind of option.'],
  )
  assert.deepEqual(
    customizationProblems(
      emptyCustomization({ option_name: '  ', option_type: '' }),
    ).errors,
    ['Give the option a name.', 'Choose a kind of option.'],
  )
})

test('customizationProblems: an empty choice list is a note, not a refusal', () => {
  const { errors, notes } = customizationProblems(
    emptyCustomization({ option_name: 'Sole colour', option_type: 'color' }),
  )
  assert.deepEqual(errors, [])
  assert.deepEqual(notes, [
    'Sole colour has no choices yet, so the list a customer picks from would be empty.',
  ])

  // A text option is asked for, not chosen from: no choices is the whole point.
  assert.deepEqual(
    customizationProblems(
      emptyCustomization({ option_name: 'Engraving', option_type: 'text' }),
    ),
    { errors: [], notes: [] },
  )
})

test('customizationRowsForInsert writes the column shape', () => {
  const rows = customizationRowsForInsert([
    {
      option_name: '  Sole colour ',
      option_type: 'color',
      options: [' Tan ', ''],
      is_required: true,
      additional_price: '75',
    },
    emptyCustomization({ option_name: '   ', option_type: 'text' }),
    emptyCustomization({ option_name: 'No type', option_type: '' }),
  ])
  assert.deepEqual(rows, [
    {
      option_name: 'Sole colour',
      option_type: 'color',
      options: ['Tan', ''],
      is_required: true,
      additional_price: 75,
    },
  ])
})

test('choices survive a type change, and are still written', () => {
  // A mis-tap on the type must not cost the seller the choices they typed, so
  // the list stays on the row and the row keeps it whatever the type is —
  // `text` included, because dropping it would make switching type destructive.
  const typed = addChoice(
    emptyCustomization({ option_name: 'Sole colour', option_type: 'color' }),
    'Red',
  ).customization
  const asText = { ...typed, option_type: 'text' }
  assert.deepEqual(asText.options, ['Red'])
  assert.deepEqual(customizationRowsForInsert([asText])[0].options, ['Red'])
})

test('customizationProblems leaves a well-formed option alone', () => {
  assert.deepEqual(
    customizationProblems(
      emptyCustomization({
        option_name: 'Sole colour',
        option_type: 'color',
        options: ['Tan'],
        additional_price: 75,
      }),
    ),
    { errors: [], notes: [] },
  )
})

test('customizationTotals counts what a seller would ask for', () => {
  assert.deepEqual(customizationTotals(customizationsFromProduct(STORED)), {
    count: 2,
    required: 1,
    withExtra: 1,
  })
  assert.deepEqual(customizationTotals([]), { count: 0, required: 0, withExtra: 0 })
})
