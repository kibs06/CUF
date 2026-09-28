import assert from 'node:assert/strict'
import { describe, it } from 'node:test'

import { customerNotificationPath, sellerNotificationPath } from './notificationPaths.js'

/** A customer row the way the table returns one. */
const row = (over = {}) => ({
  id: 'n1',
  category: 'processing',
  order_id: 'order-1',
  metadata: null,
  ...over,
})

/** A seller row the way the table returns one. */
const sellerRow = (over = {}) => ({
  id: 's1',
  type: 'new_order',
  reference_id: 'order-1',
  metadata: null,
  ...over,
})

describe('customerNotificationPath', () => {
  it('sends a message to its thread', () => {
    assert.equal(
      customerNotificationPath(row({ category: 'message', metadata: { conversation_id: 'c9' } })),
      '/messages/c9',
    )
  })

  it('sends an order notification to its order', () => {
    assert.equal(customerNotificationPath(row()), '/orders/order-1')
  })

  it('is null where the portal has no screen', () => {
    // A support reply belongs to the app's reports screen, which the portal
    // does not have; an inert card beats a link to a 404.
    assert.equal(customerNotificationPath(row({ category: 'support' })), null)
    assert.equal(customerNotificationPath(row({ order_id: null })), null)
    assert.equal(customerNotificationPath(null), null)
  })
})

describe('sellerNotificationPath', () => {
  it('sends an order row to the order, or the list without a reference', () => {
    assert.equal(sellerNotificationPath(sellerRow()), '/seller/orders/order-1')
    assert.equal(
      sellerNotificationPath(sellerRow({ type: 'stale_order', reference_id: null })),
      '/seller/orders',
    )
  })

  it('sends a low-stock row to the product that needs restocking', () => {
    assert.equal(
      sellerNotificationPath(sellerRow({ type: 'low_stock', reference_id: 'product-4' })),
      '/seller/products/product-4',
    )
    assert.equal(
      sellerNotificationPath(sellerRow({ type: 'low_stock', reference_id: null })),
      '/seller/products',
    )
  })

  it('reads a message row’s conversation from either column', () => {
    // The app writes `reference_id`, the batching triggers write
    // `metadata.conversation_id` — a path resolver that read only one of them
    // would drop the seller at the inbox instead of in the thread.
    assert.equal(
      sellerNotificationPath(sellerRow({ type: 'new_message', reference_id: 'conv-3' })),
      '/seller/messages/conv-3',
    )
    assert.equal(
      sellerNotificationPath(
        sellerRow({
          type: 'new_message',
          reference_id: null,
          metadata: { conversation_id: 'conv-8' },
        }),
      ),
      '/seller/messages/conv-8',
    )
    assert.equal(
      sellerNotificationPath(sellerRow({ type: 'new_message', reference_id: null })),
      '/seller/messages',
    )
  })

  it('is null for a custom order request and for a type it does not know', () => {
    assert.equal(
      sellerNotificationPath(sellerRow({ type: 'custom_order_request' })),
      null,
    )
    assert.equal(sellerNotificationPath(sellerRow({ type: 'payment_confirmed' })), null)
    assert.equal(sellerNotificationPath(null), null)
  })
})
