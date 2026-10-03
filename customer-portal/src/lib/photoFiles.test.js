import assert from 'node:assert/strict'
import { test } from 'node:test'

import {
  HEIC_EXTENSIONS,
  HEIC_MIME_TYPES,
  heicRejectionNotice,
  isHeicPhoto,
  photoExtension,
  screenPickedPhotos,
  splitPickedPhotos,
} from './photoFiles.js'

/** A picked file, as the browser hands it over — only the two fields matter. */
function picked(name, type = '') {
  return { name, type }
}

test('photoExtension reads the tail, case folded, or nothing at all', () => {
  assert.equal(photoExtension('IMG_0001.HEIC'), 'heic')
  assert.equal(photoExtension('shot.JPEG'), 'jpeg')
  assert.equal(photoExtension('no-extension'), '')
  assert.equal(photoExtension('trailing.'), '')
  assert.equal(photoExtension(''), '')
  assert.equal(photoExtension(null), '')
})

test('isHeicPhoto answers on the extension when the type says nothing', () => {
  // The case the OS is least helpful about: a machine without the HEIF codec
  // reports `''`, and the name is the only signal left.
  assert.equal(isHeicPhoto(picked('IMG_0001.HEIC', '')), true)
  assert.equal(isHeicPhoto(picked('IMG_0001.heic', 'application/octet-stream')), true)
  assert.equal(isHeicPhoto(picked('IMG_0001.heif')), true)
  assert.equal(isHeicPhoto(picked('IMG_0001.HeIf')), true)

  assert.equal(isHeicPhoto(picked('IMG_0001.jpg', 'image/jpeg')), false)
  assert.equal(isHeicPhoto(picked('IMG_0001.png', 'image/png')), false)
  assert.equal(isHeicPhoto(picked('photo.webp', 'image/webp')), false)
  // A file that is not a photo at all is not this helper's business to refuse —
  // the picker's `accept` is what keeps documents out.
  assert.equal(isHeicPhoto(picked('notes.pdf', 'application/pdf')), false)
  assert.equal(isHeicPhoto(picked('', '')), false)
  assert.equal(isHeicPhoto(null), false)
})

test('isHeicPhoto answers on the MIME type when the name says nothing', () => {
  // A renamed file: iOS exports and sharing flows hand these over under a name
  // the extension check cannot see.
  assert.equal(isHeicPhoto(picked('IMG_0001.jpg', 'image/heic')), true)
  assert.equal(isHeicPhoto(picked('IMG_0001.jpg', 'image/heif')), true)
  // Every suffix a phone actually reports.
  for (const type of HEIC_MIME_TYPES) {
    assert.equal(isHeicPhoto(picked('photo', type)), true, type)
    assert.equal(isHeicPhoto(picked('photo', `${type}-sequence`)), true, `${type}-sequence`)
    assert.equal(isHeicPhoto(picked('photo', `${type}; charset=utf-8`)), true)
    assert.equal(isHeicPhoto(picked('photo', type.toUpperCase())), true)
  }
  // Case and whitespace must not let one through.
  assert.equal(isHeicPhoto({ name: ' IMG_0001.HEIC ', type: ' IMAGE/HEIC ' }), true)
})

test('every extension the helper refuses is the pair an iPhone writes', () => {
  assert.deepEqual(HEIC_EXTENSIONS, ['heic', 'heif'])
  assert.deepEqual(HEIC_MIME_TYPES, ['image/heic', 'image/heif'])
})

test('splitPickedPhotos keeps the order on both sides', () => {
  const first = picked('a.jpg', 'image/jpeg')
  const second = picked('b.heic', 'image/heic')
  const third = picked('c.png', 'image/png')
  const fourth = picked('d.heif')

  const { accepted, rejected } = splitPickedPhotos([first, second, third, fourth])

  // The first photo of a pick is the cover, so a filter that reordered would
  // silently change which photo leads the gallery.
  assert.deepEqual(accepted, [first, third])
  assert.deepEqual(rejected, [second, fourth])
})

test('splitPickedPhotos takes an empty pick, and no pick at all', () => {
  assert.deepEqual(splitPickedPhotos([]), { accepted: [], rejected: [] })
  assert.deepEqual(splitPickedPhotos(null), { accepted: [], rejected: [] })
})

test('the notice names the file, the problem and the way out', () => {
  const notice = heicRejectionNotice([picked('IMG_0421.HEIC', 'image/heic')])

  assert.match(notice, /IMG_0421\.HEIC/)
  // What is wrong — not a codec lecture, the words a seller can act on.
  assert.match(notice, /HEIC/)
  assert.match(notice, /cannot show/)
  // And the fix, which lives on the phone that took the photo.
  assert.match(notice, /JPEG/)
  assert.match(notice, /Most Compatible/)
})

test('the notice counts the files it does not name', () => {
  const files = [
    picked('one.heic'),
    picked('two.heic'),
    picked('three.heic'),
    picked('four.heic'),
    picked('five.heif'),
  ]
  const notice = heicRejectionNotice(files)

  assert.match(notice, /one\.heic/)
  assert.match(notice, /three\.heic/)
  // The tail is counted, not silently dropped — a seller who picked five must
  // not read "three" and wonder about the rest.
  assert.match(notice, /and 2 more/)
  assert.doesNotMatch(notice, /four\.heic/)
})

test('a pick with no names is still explained, in the plural it deserves', () => {
  assert.match(heicRejectionNotice([picked('', 'image/heic')]), /That photo is HEIC/)
  assert.match(
    heicRejectionNotice([picked('', 'image/heic'), picked('', 'image/heic')]),
    /Those 2 photos are HEIC/,
  )
})

test('no rejected files means no notice at all', () => {
  assert.equal(heicRejectionNotice([]), null)
  assert.equal(heicRejectionNotice(null), null)
})

test('screenPickedPhotos hands back the files to upload and the notice to show', () => {
  const keep = picked('a.jpg', 'image/jpeg')
  const drop = picked('b.heic', 'image/heic')
  const { accepted, notice } = screenPickedPhotos([keep, drop])

  assert.deepEqual(accepted, [keep])
  assert.match(notice, /b\.heic/)
  // Nothing refused: the notice is null rather than an empty string, so a caller
  // can render it behind a truthiness check.
  assert.deepEqual(screenPickedPhotos([keep]), { accepted: [keep], notice: null })
})
