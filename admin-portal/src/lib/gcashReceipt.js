// admin-portal/src/lib/gcashReceipt.js
//
// Reading the GCash reference number out of a transfer screenshot, with the
// SAME rules the customer app uses when it reads its own proof of payment
// (lib/utils/gcash_ref_extractor.dart). Ported rather than reinvented so an
// admin and a customer looking at the same receipt always land on the same
// digits:
//
//   1. **Label-first** — a line carrying a reference label ("Ref No.",
//      "Reference Number", "Ref #") is the strongest signal. Its digits win;
//      when the layout splits the label from the value, the next line is read.
//   2. **Scored fallback** — otherwise every line is scored: 13 digits (what
//      GCash prints) beats other plausible lengths, a line that is mostly
//      digits beats prose, and GCash's grouped style ("4043 676 687260")
//      beats an ungrouped run. Money lines, dates/times and Philippine mobile
//      numbers are excluded outright — a phone number on a receipt is contact
//      info, never a reference.
//
// The stored value is digits only, exactly like the app; the grouped form is
// for display so the admin can eyeball it against the screenshot. This module
// is pure (no DOM, no OCR) so it is unit-testable and so the OCR step can be
// swapped without touching the rules.

export const MIN_DIGITS = 10
export const MAX_DIGITS = 16
export const IDEAL_DIGITS = 13

const REF_LABEL = /ref(?:erence)?\s*(?:no|num|number|#)/i
const DECIMAL_AMOUNT = /[0-9]{1,3}(?:,[0-9]{3})+\.[0-9]{2}/
const PLAIN_DECIMAL = /\d+\.\d{2}/
const GROUPED_RUN = /^\d{3,6}(?: \d{3,6})+$/
const PH_MOBILE = /^09\d{9}$/

/** Words that mark a line as an amount or other context, never a reference. */
const MONEY_WORDS = [
  '₱',
  'php',
  'peso',
  'amount',
  'total',
  'balance',
  'change',
  'due',
  'paid',
  'fee',
  'vat',
  'discount',
  'charge',
  'cash',
]

/** Digits only — spaces, dots and dashes are formatting, not data. */
export function digitsOf(line) {
  return String(line ?? '').replace(/[^0-9]/g, '')
}

function isPlausible(digits) {
  return digits.length >= MIN_DIGITS && digits.length <= MAX_DIGITS
}

function looksLikeMoneyOrDate(line) {
  const lower = String(line).toLowerCase()
  if (MONEY_WORDS.some((word) => lower.includes(word))) return true
  if (DECIMAL_AMOUNT.test(line)) return true
  if (PLAIN_DECIMAL.test(line)) return true
  // "07/15/2026 10:30" is a timestamp, not a reference number.
  if (line.includes('/') || line.includes(':')) return true
  return false
}

function scoreLine(line, digits) {
  let score = 0
  if (digits.length === IDEAL_DIGITS) score += 100
  else if (digits.length >= MIN_DIGITS) score += 20

  // A lone PH mobile number is contact info on a receipt, never a reference.
  if (PH_MOBILE.test(digits)) return -50

  // A line that is essentially just digits is far more likely the reference
  // than prose that happens to contain a long number.
  const nonSpace = String(line).replace(/ /g, '')
  if (nonSpace.length > 0) {
    const ratio = digits.length / nonSpace.length
    if (ratio > 0.85) score += 30
    else if (ratio > 0.5) score += 10
  }

  // GCash prints the reference in groups (4-3-6).
  if (GROUPED_RUN.test(String(line).trim())) score += 40
  return score
}

/**
 * Format digits the way a GCash receipt prints them, for the read-back under
 * the field: 13 digits use GCash's 4-3-6 grouping (`4043676687260` →
 * `4043 676 687260`); any other length falls back to 4-digit chunks.
 */
export function formatGrouped(digits) {
  const value = digitsOf(digits)
  if (value.length === IDEAL_DIGITS) {
    return `${value.slice(0, 4)} ${value.slice(4, 7)} ${value.slice(7)}`
  }
  return value.replace(/(.{4})/g, '$1 ').trim()
}

/**
 * Extract the reference number from OCR lines.
 *
 * @param {string[]} lines OCR text, one line per entry.
 * @returns {{reference: string|null, candidates: string[], matchedLabel: boolean, displayGrouped: string}}
 *   `reference` is digits only (null when nothing plausible was found),
 *   `matchedLabel` says it came from a "Ref No." line (highest confidence),
 *   and `candidates` carries up to three scored alternatives for an ambiguous
 *   screenshot so the UI can offer them instead of guessing silently.
 */
export function extractReference(lines) {
  const rows = (Array.isArray(lines) ? lines : []).map((line) => String(line ?? ''))

  // ── 1. Label-first ────────────────────────────────────────────────
  for (let i = 0; i < rows.length; i += 1) {
    const line = rows[i].trim()
    if (!REF_LABEL.test(line)) continue

    const digits = digitsOf(line)
    if (isPlausible(digits)) {
      return {
        reference: digits,
        candidates: [digits],
        matchedLabel: true,
        displayGrouped: formatGrouped(digits),
      }
    }

    // Label on its own line, value on the next one.
    if (i + 1 < rows.length) {
      const next = digitsOf(rows[i + 1])
      if (isPlausible(next)) {
        return {
          reference: next,
          candidates: [next],
          matchedLabel: true,
          displayGrouped: formatGrouped(next),
        }
      }
    }
  }

  // ── 2. Scored fallback ────────────────────────────────────────────
  const scored = []
  for (const raw of rows) {
    const line = raw.trim()
    const digits = digitsOf(line)
    if (!isPlausible(digits)) continue
    if (looksLikeMoneyOrDate(line)) continue
    const score = scoreLine(line, digits)
    // Only positive scores qualify — a stray long number in prose must never
    // be surfaced as the reference.
    if (score > 0) scored.push({ digits, score })
  }

  if (scored.length === 0) {
    return { reference: null, candidates: [], matchedLabel: false, displayGrouped: '' }
  }

  scored.sort((a, b) => b.score - a.score)
  const candidates = [...new Set(scored.slice(0, 3).map((row) => row.digits))]
  return {
    reference: scored[0].digits,
    candidates,
    matchedLabel: false,
    displayGrouped: formatGrouped(scored[0].digits),
  }
}

/** Convenience: OCR text blob → the same result as [extractReference]. */
export function parseReceiptText(text) {
  return extractReference(String(text ?? '').split(/\r?\n/))
}
