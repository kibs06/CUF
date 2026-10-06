import assert from 'node:assert/strict'
import { test } from 'node:test'

import { productSavedFlash } from './sellerFlash.js'

test('a created product names the photos it still needs', () => {
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

test('no card claims the product is visible to customers', () => {
  /*
    The one thing this copy must not do. The storefront hides any product whose
    total stock is zero (`purchasableProducts`), and a product with sizes but no
    stock saves fine — so "your changes are live on the storefront" would be a
    promise the catalog breaks, made in the same breath as the form's own note
    that the product is at zero.
  */
  for (const created of [true, false]) {
    const { title, message } = productSavedFlash({ created, name: 'A pair' })
    const said = `${title} ${message}`.toLowerCase()
    assert.ok(!said.includes('live'), `${said} must not say the write is live`)
    assert.ok(
      !said.includes('storefront'),
      `${said} must not promise the storefront`,
    )
  }
})
