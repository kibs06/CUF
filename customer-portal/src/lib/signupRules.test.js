import assert from 'node:assert/strict'
import { describe, it } from 'node:test'

import {
  MINIMUM_SIGNUP_AGE,
  formatBirthdayForDb,
  resolveGenderValue,
  validateBirthday,
  validateGenderSelfDescribe,
} from './signupRules.js'

/** A `YYYY-MM-DD` string exactly N years before today. */
function yearsAgo(years) {
  const now = new Date()
  const date = new Date(now.getFullYear() - years, now.getMonth(), now.getDate())
  const month = String(date.getMonth() + 1).padStart(2, '0')
  const day = String(date.getDate()).padStart(2, '0')
  return `${date.getFullYear()}-${month}-${day}`
}

function daysFromNow(days) {
  const date = new Date()
  date.setDate(date.getDate() + days)
  const month = String(date.getMonth() + 1).padStart(2, '0')
  const day = String(date.getDate()).padStart(2, '0')
  return `${date.getFullYear()}-${month}-${day}`
}

describe('validateBirthday', () => {
  it('requires a birthday', () => {
    assert.equal(validateBirthday(null), 'Please select your birthday')
    assert.equal(validateBirthday(''), 'Please select your birthday')
  })

  it('rejects an unparseable value', () => {
    assert.equal(validateBirthday('not-a-date'), 'Please enter a valid birthday')
  })

  it('rejects a future birthday', () => {
    assert.equal(
      validateBirthday(daysFromNow(1)),
      "Birthday can't be in the future",
    )
  })

  it('accepts today (age 0 is not the point — the year rule decides)', () => {
    // Same calendar year as today, so `years` is 0 and the age rule rejects it
    // with the age message rather than the future message.
    assert.equal(
      validateBirthday(daysFromNow(0)),
      `You must be at least ${MINIMUM_SIGNUP_AGE} years old to sign up`,
    )
  })

  it('rejects anyone under the minimum age by calendar year', () => {
    const tooYoung = new Date()
    tooYoung.setFullYear(tooYoung.getFullYear() - (MINIMUM_SIGNUP_AGE - 1))
    const month = String(tooYoung.getMonth() + 1).padStart(2, '0')
    const day = String(tooYoung.getDate()).padStart(2, '0')

    assert.equal(
      validateBirthday(`${tooYoung.getFullYear()}-${month}-${day}`),
      `You must be at least ${MINIMUM_SIGNUP_AGE} years old to sign up`,
    )
  })

  it('accepts exactly the minimum age', () => {
    assert.equal(validateBirthday(yearsAgo(MINIMUM_SIGNUP_AGE)), null)
  })

  it('accepts a comfortably adult birthday', () => {
    assert.equal(validateBirthday(yearsAgo(30)), null)
  })
})

describe('validateGenderSelfDescribe', () => {
  it('only applies to the Self-describe option', () => {
    assert.equal(validateGenderSelfDescribe('Woman', ''), null)
    assert.equal(validateGenderSelfDescribe(null, ''), null)
  })

  it('requires text when Self-describe is chosen', () => {
    assert.equal(
      validateGenderSelfDescribe('Self-describe', '   '),
      'Please tell us how you describe yourself',
    )
    assert.equal(validateGenderSelfDescribe('Self-describe', 'Non-binary'), null)
  })
})

describe('resolveGenderValue', () => {
  it('is null when nothing was chosen', () => {
    assert.equal(resolveGenderValue(null, null), null)
    assert.equal(resolveGenderValue('', 'ignored'), null)
  })

  it('passes a preset through', () => {
    assert.equal(resolveGenderValue('Man', 'ignored'), 'Man')
  })

  it('substitutes the free text for Self-describe', () => {
    assert.equal(resolveGenderValue('Self-describe', '  Non-binary  '), 'Non-binary')
    // A blank self-description resolves to nothing rather than to the literal
    // string "Self-describe", which would be stored as a gender.
    assert.equal(resolveGenderValue('Self-describe', '   '), null)
  })
})

describe('formatBirthdayForDb', () => {
  it('formats a local YYYY-MM-DD', () => {
    assert.equal(formatBirthdayForDb('2000-03-07'), '2000-03-07')
  })

  it('does NOT shift the day through UTC', () => {
    // The reason this function exists rather than `toISOString()`: a date built
    // from local parts must come back as the same local day, whatever the
    // machine's offset.
    const local = new Date(2000, 2, 7)
    assert.equal(formatBirthdayForDb(local), '2000-03-07')
  })

  it('is null for nothing or garbage', () => {
    assert.equal(formatBirthdayForDb(null), null)
    assert.equal(formatBirthdayForDb('nonsense'), null)
  })
})
