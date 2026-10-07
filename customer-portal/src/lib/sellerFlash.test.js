import assert from 'node:assert/strict'
import { test } from 'node:test'

import { productSavedFlash } from './sellerFlash.js'

test('a created product with no photos names the ones it still needs', () => {
  const { title, message } = productSavedFlash({
    created: true,
    name: 'Barong slip-on',
  })
  assert.equal(title, 'Product added')
  assert.equal(
    message,
    'Barong slip-on is saved. Open it to add its photos.',
  )
})

test('a created product with photos says they went up with it', () => {
  /*
    The photos a create carries are uploaded by that same save (the row, then its
    images), so a card that still asked for them would send the seller back to a
    product that is already complete — and would be the wording drifting from the
    form rather than from the data.
  */
  const one = productSavedFlash({ created: true, name: 'A pair', photos: 1 })
  assert.equal(one.title, 'Product added')
  assert.equal(one.message, 'A pair is saved with its photo.')

  const many = productSavedFlash({ created: true, name: 'A pair', photos: 6 })
  assert.equal(many.message, 'A pair is saved with its 6 photos.')
})

test('an updated product never claims photos were uploaded', () => {
  // An edit writes the row and nothing else about photos: the Photos card uploads
  // on its own, so a photo count reaching this card must not become a claim about
  // an edit's photos.
  for (const photos of [0, 1, 4, undefined, null, 'nonsense', -3]) {
    const { message } = productSavedFlash({
      created: false,
      name: 'A pair',
      photos,
    })
    assert.equal(message, 'A pair is saved.')
  }
})

test('no card points at the page the seller is already on', () => {
  /*
    A save navigates to `/seller/products`, so the card is read with the
    products list behind it. A sentence or a button sending the seller there
    would spend itself saying nothing — and a card that said it would be the
    tell that the navigation and the copy had drifted apart.
  */
  for (const created of [true, false]) {
    const { message } = productSavedFlash({ created, name: 'A pair' })
    const said = message.toLowerCase()
    assert.ok(!said.includes('view your products'), said)
    assert.ok(!said.includes('back to'), said)
  }
})

test('an updated product says so and stops', () => {
  const { title, message } = productSavedFlash({
    created: false,
    name: 'Barong slip-on',
  })
  assert.equal(title, 'Product updated')
  assert.equal(message, 'Barong slip-on is saved.')
})

test('a blank name does not leave a sentence starting with "is saved"', () => {
  // The form trims before it writes, so a name of only whitespace can reach the
  // card from a product whose name was blanked — and "  is saved." is worse than
  // no name at all.
  for (const name of ['', '   ', null, undefined]) {
    const { message } = productSavedFlash({ created: false, name })
    assert.equal(message, 'Your product is saved.')
    assert.ok(!message.startsWith(' '), 'the message must not start with a space')
  }
})

test('a nonsense photo count is not written into the sentence', () => {
  /*
    The count is arithmetic on a save that may have failed part-way, and a card is
    the wrong place to discover that it is `NaN`: anything that is not a positive
    number is the created-without-photos sentence, verbatim.
  */
  for (const photos of [undefined, null, 'nonsense', NaN, -3, 0]) {
    const { message } = productSavedFlash({ created: true, name: 'A pair', photos })
    assert.equal(message, 'A pair is saved. Open it to add its photos.')
  }
})

test('no card claims the product is visible to customers', () => {
  /*
    The one thing this copy must not do. The storefront hides any product whose
    total stock is zero (`purchasableProducts`), and a product with sizes but no
    stock saves fine — so "your changes are live on the storefront" would be a
    promise the catalog breaks, made in the same breath as the form's own note
    that the product is at zero.
  */
  for (const [created, photos] of [
    [true, 0],
    [true, 3],
    [false, 0],
    [false, 3],
  ]) {
    const { title, message } = productSavedFlash({ created, name: 'A pair', photos })
    const said = `${title} ${message}`.toLowerCase()
    assert.ok(!said.includes('live'), `${said} must not say the write is live`)
    assert.ok(
      !said.includes('storefront'),
      `${said} must not promise the storefront`,
    )
  }
})
