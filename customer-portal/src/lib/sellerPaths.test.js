import assert from 'node:assert/strict'
import { test } from 'node:test'

import { sellerProductPreviewPath } from './sellerPaths.js'

test('the preview is a seller route, never a customer one', () => {
  const path = sellerProductPreviewPath({ id: 'p1' })
  assert.equal(path, '/seller/products/p1/preview')

  /*
    The half that matters: a preview that pointed at `/product/:id` would be the
    bug this route exists to fix — `AppLayout` redirects an approved seller out
    of every customer route, so the page would show for a moment and then be
    replaced by the dashboard.
  */
  assert.ok(path.startsWith('/seller/'), path)
  assert.ok(!path.startsWith('/product/'), path)
})

test('the id is carried through verbatim, the way the editor routes carry it', () => {
  // A real id from the products table, because this is a pass-through rather
  // than a slug: the router resolves it, and an id that does not exist is the
  // preview's own "not found" rather than a different path.
  assert.equal(
    sellerProductPreviewPath({ id: '203e770b-9a96-448c-a784-db26b11914ad' }),
    '/seller/products/203e770b-9a96-448c-a784-db26b11914ad/preview',
  )
})
