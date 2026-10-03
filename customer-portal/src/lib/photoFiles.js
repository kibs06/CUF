/**
 * What a seller picked, and the one kind of file the storefront cannot show.
 *
 * ## Why HEIC, and why here
 *
 * An iPhone saves photos as HEIC by default, and a browser's file picker hands the
 * file over untouched. Nothing downstream can draw it: Chrome, Edge and Firefox
 * cannot decode HEIC in an `<img>`, and the app's gallery is the same image widget
 * over the same URLs. So a HEIC that gets uploaded is a photo the seller watched
 * appear in their form and no customer will ever see — a silent failure, which is
 * the worst kind to leave in a picker.
 *
 * The app has no such hole: `add_edit_product_screen.dart` picks with
 * `imageQuality: 85`, which makes `image_picker` re-encode a HEIC to JPEG before
 * `product_service.dart` ever uploads it. Only this portal takes the raw file, so
 * only this portal has to say no. Saying it *here*, in a helper both pickers call,
 * is what keeps the product gallery and a colour's gallery from disagreeing about
 * what they accept.
 *
 * ## Extension **or** MIME type
 *
 * Both signals are checked, because neither alone is dependable in a browser.
 * `file.type` is guessed by the operating system: a Windows machine with the HEIF
 * codec installed reports `image/heic`, a machine without it can report `''` or
 * even `image/octet-stream`; Safari sometimes reports `image/heic` for a `.jpg`
 * that merely contains HEIC data, and iOS exports named `.HEIC` uppercase. The
 * extension covers the empty-type case, the MIME type covers a renamed file, and a
 * file refused by either is refused.
 *
 * ## What the seller is told
 *
 * `heicRejectionNotice` names the files, says what is wrong with them and what to
 * do about it, in the terms a phone gives them — Settings → Camera → Formats →
 * Most Compatible, or export/share as JPEG. A picker that quietly drops a photo is
 * indistinguishable from one that never received it, so the message is not
 * optional; both callers render it next to the button they picked from.
 */

/** The extensions an iPhone writes. Lower-case; matching folds the case. */
export const HEIC_EXTENSIONS = ['heic', 'heif']

/** The MIME types browsers and phones report for the same files. */
export const HEIC_MIME_TYPES = ['image/heic', 'image/heif']

/** The end of a file name, lower-cased, or `''` when there is none. */
export function photoExtension(name) {
  const match = /\.([a-z0-9]+)$/i.exec(String(name ?? '').trim())
  return match ? match[1].toLowerCase() : ''
}

/**
 * Is this a HEIC/HEIF file — by its type, its name, or both?
 *
 * `startsWith` rather than an equality check for the MIME half, so the variants
 * phones actually report (`image/heic-sequence`, `image/heif-sequence`, and
 * Safari's occasional `image/heic; charset=…`) are refused too. A false positive
 * costs the seller one unusable file and a message that explains itself; a false
 * negative costs them a photo no customer will ever see.
 */
export function isHeicPhoto(file) {
  const type = String(file?.type ?? '').trim().toLowerCase()
  if (HEIC_MIME_TYPES.some((mime) => type === mime || type.startsWith(`${mime};`))) {
    return true
  }
  if (type.startsWith('image/heic') || type.startsWith('image/heif')) return true
  return HEIC_EXTENSIONS.includes(photoExtension(file?.name))
}

/**
 * A pick, split into the photos to keep and the HEIC files to explain.
 *
 * Order is preserved on both sides — the storefront's cover is the first photo of
 * the pick, so a filter that reordered would silently change which photo leads.
 */
export function splitPickedPhotos(files) {
  const accepted = []
  const rejected = []
  for (const file of files ?? []) {
    if (isHeicPhoto(file)) rejected.push(file)
    else accepted.push(file)
  }
  return { accepted, rejected }
}

/**
 * What to tell a seller about the HEIC files that were left out, or `null` when
 * there were none.
 *
 * Up to three names are listed and the rest counted, because the message has to
 * fit next to a button — but the number is always the true one, so a seller who
 * picked twelve knows twelve came back. The advice is the phone's own fix rather
 * than "convert it somewhere", because the phone that took the photo is where the
 * setting lives: new photos become JPEGs from then on, and an existing one can be
 * exported from Photos as JPEG.
 */
export function heicRejectionNotice(rejected) {
  const files = [...(rejected ?? [])]
  if (files.length === 0) return null

  const names = files
    .map((file) => String(file?.name ?? '').trim())
    .filter(Boolean)
  const listed =
    names.length > 3
      ? `${names.slice(0, 3).join(', ')} and ${names.length - 3} more`
      : names.join(', ')

  const one = files.length === 1
  const subject = listed
    ? one
      ? `${listed} is a HEIC photo`
      : `${listed} are HEIC photos`
    : one
      ? 'That photo is HEIC'
      : `Those ${files.length} photos are HEIC`

  const advice =
    'iPhones save photos that way, but browsers and the storefront cannot show ' +
    'them. Export as JPEG (on iPhone: Settings → Camera → Formats → Most ' +
    'Compatible), then add again.'

  return `${subject} — ${advice}`
}

/**
 * The files a pick should upload, with the notice to show or `null`.
 *
 * The two halves a caller always wants together, so neither picker can wire the
 * filter without the message — the mistake that would make this helper useless.
 */
export function screenPickedPhotos(files) {
  const { accepted, rejected } = splitPickedPhotos(files)
  return { accepted, notice: heicRejectionNotice(rejected) }
}
