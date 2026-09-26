import { PRODUCT_AUDIENCES } from './constants.js'

/**
 * Sign-up field rules — a port of `lib/utils/customer_profile_fields.dart`.
 *
 * Kept pure and separate from the form so the age gate is provable without
 * rendering anything. These are policy, not cosmetics: the 13-year minimum is
 * enforced on both clients and would be silently wrong if a re-implementation
 * drifted a year.
 */

/** The gender options offered at signup (`AppConstants.customerGenderOptions`). */
export const GENDER_OPTIONS = [
  'Woman',
  'Man',
  'Prefer not to say',
  'Self-describe',
]

/** Minimum age for a customer account (`AppConstants.minimumSignupAgeYears`). */
export const MINIMUM_SIGNUP_AGE = 13

/** Today, at local midnight. */
function todayAtMidnight() {
  const now = new Date()
  return new Date(now.getFullYear(), now.getMonth(), now.getDate())
}

/**
 * Validates a birthday. Returns `null` when acceptable, or a reason.
 *
 * The comparison is **by calendar year**, deliberately — it is copied from the
 * app. A day-accurate check would reject someone on the morning of their 13th
 * birthday, and an off-by-one rejection on the exact day is worse than
 * admitting them a few hours early.
 */
export function validateBirthday(value) {
  if (!value) return 'Please select your birthday'

  const picked = new Date(value)
  if (Number.isNaN(picked.getTime())) return 'Please enter a valid birthday'

  const pickedDay = new Date(
    picked.getFullYear(),
    picked.getMonth(),
    picked.getDate(),
  )
  if (pickedDay.getTime() > todayAtMidnight().getTime()) {
    return "Birthday can't be in the future"
  }

  const years =
    todayAtMidnight().getFullYear() - pickedDay.getFullYear()
  if (years < MINIMUM_SIGNUP_AGE) {
    return `You must be at least ${MINIMUM_SIGNUP_AGE} years old to sign up`
  }

  return null
}

/**
 * Guards the 'Self-describe' free-text field: it applies only when that option
 * is selected, and must not be blank when it is. Any other selection — or none
 * at all, since the field is optional — is fine.
 */
export function validateGenderSelfDescribe(selectedOption, text) {
  if (selectedOption !== 'Self-describe') return null
  if (!text || !text.trim()) {
    return 'Please tell us how you describe yourself'
  }
  return null
}

/**
 * The value to persist: the preset option, or the free text when
 * 'Self-describe' was chosen. Null when nothing was selected.
 */
export function resolveGenderValue(selectedOption, selfDescribeText) {
  if (!selectedOption) return null
  if (selectedOption === 'Self-describe') {
    const text = selfDescribeText?.trim()
    return text ? text : null
  }
  return selectedOption
}

/**
 * A birthday as a local `YYYY-MM-DD` string for the `DATE` column.
 *
 * Built by hand rather than via `toISOString()`: that converts to UTC, so a
 * birthday typed after 4pm in Cebu (UTC+8) would be sent as the *previous* day.
 */
export function formatBirthdayForDb(value) {
  if (!value) return null
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return null

  const month = String(date.getMonth() + 1).padStart(2, '0')
  const day = String(date.getDate()).padStart(2, '0')
  return `${date.getFullYear()}-${month}-${day}`
}

/** A product audience's label, or null. Re-exported so forms can offer it. */
export const AUDIENCES = PRODUCT_AUDIENCES
