import assert from 'node:assert/strict'
import { describe, it } from 'node:test'

import {
  OTHER_SELLER_NOTIFICATION_TYPE,
  SELLER_NOTIFICATION_TYPES,
  filterSellerNotifications,
  isBatchedSellerNotification,
  sellerNotificationConversationId,
  sellerNotificationDestination,
  sellerNotificationReferenceId,
  sellerNotificationType,
  sellerNotificationTypeLabel,
  sellerNotificationTypesPresent,
  unreadCountsBySellerType,
  unreadSellerNotificationCount,
} from './sellerNotificationRules.js'

/** A row the way the table returns one. */
const row = (over = {}) => ({
  id: 's1',
  store_id: 'store-1',
  type: 'new_order',
  title: 'New order #a1b2c3d4',
  body: '₱1,250 — tap to view',
  reference_id: 'order-1',
  is_read: false,
  created_at: '2026-09-25T10:00:00Z',
  metadata: null,
  ...over,
})

describe('sellerNotificationType', () => {
  it('knows the five types the app creates', () => {
    assert.deepEqual(SELLER_NOTIFICATION_TYPES, [
      'new_order',
      'stale_order',
      'low_stock',
      'custom_order_request',
      'new_message',
    ])

    for (const type of SELLER_NOTIFICATION_TYPES) {
      assert.equal(sellerNotificationType(type), type)
    }
  })

  it('accepts the raw value the way the column stores it', () => {
    assert.equal(sellerNotificationType('  NEW_ORDER '), 'new_order')
  })

  it('does not guess at a type it has never seen', () => {
    // The customer side defaults an unknown category to `unpaid`, which is a
    // category a row could honestly have. Here every type is a claim about the
    // work, so guessing would put an icon and a colour on something untrue.
    assert.equal(sellerNotificationType('payment_confirmed'), OTHER_SELLER_NOTIFICATION_TYPE)
    assert.equal(sellerNotificationType(null), OTHER_SELLER_NOTIFICATION_TYPE)
    assert.notEqual(sellerNotificationType('low_stock'), OTHER_SELLER_NOTIFICATION_TYPE)
  })

  it('labels all five the way the app does', () => {
    assert.equal(sellerNotificationTypeLabel('new_order'), 'New order')
    assert.equal(sellerNotificationTypeLabel('stale_order'), 'Needs attention')
    assert.equal(sellerNotificationTypeLabel('low_stock'), 'Low stock')
    assert.equal(sellerNotificationTypeLabel('custom_order_request'), 'Custom order')
    assert.equal(sellerNotificationTypeLabel('new_message'), 'Message')
  })

  it('makes a label out of an unknown type rather than shrugging', () => {
    // The raw value is the only true thing anyone can say about a row like
    // this, and it is what a seller would quote when asking about it.
    assert.equal(sellerNotificationTypeLabel('payment_confirmed'), 'Payment confirmed')
    assert.equal(sellerNotificationTypeLabel('gcash.proof-submitted'), 'Gcash proof submitted')
    assert.equal(sellerNotificationTypeLabel(''), 'Update')
    assert.equal(sellerNotificationTypeLabel(null), 'Update')
  })
})

describe('sellerNotificationReferenceId', () => {
  it('reads the column, and treats blank as absent', () => {
    assert.equal(sellerNotificationReferenceId(row()), 'order-1')
    assert.equal(sellerNotificationReferenceId(row({ reference_id: '' })), null)
    assert.equal(sellerNotificationReferenceId(row({ reference_id: null })), null)
    assert.equal(sellerNotificationReferenceId(row({ reference_id: 42 })), '42')
  })
})

describe('sellerNotificationConversationId', () => {
  it('reads `reference_id`, which is where the app puts a thread', () => {
    assert.equal(
      sellerNotificationConversationId(row({ type: 'new_message', reference_id: 'convo-1' })),
      'convo-1',
    )
  })

  it('also reads `metadata.conversation_id`, which is where SQL puts it', () => {
    // Both writers exist, and a card that read only one of them links to the
    // inbox while the thread it is about sits one line further down.
    assert.equal(
      sellerNotificationConversationId(
        row({
          type: 'new_message',
          reference_id: null,
          metadata: { conversation_id: 'convo-2', message_count: 3 },
        }),
      ),
      'convo-2',
    )
  })

  it('is null for a type that is not about a thread', () => {
    assert.equal(sellerNotificationConversationId(row({ type: 'new_order' })), null)
  })
})

describe('sellerNotificationDestination', () => {
  it('sends an order notification to the order', () => {
    assert.deepEqual(sellerNotificationDestination(row({ type: 'new_order' })), {
      kind: 'order',
      orderId: 'order-1',
    })
    assert.deepEqual(
      sellerNotificationDestination(row({ type: 'stale_order', reference_id: 'order-9' })),
      { kind: 'order', orderId: 'order-9' },
    )
  })

  it('falls back to the orders list when there is no reference to follow', () => {
    // Better than an inert card: "which order?" is answerable on the list.
    assert.deepEqual(
      sellerNotificationDestination(row({ type: 'new_order', reference_id: null })),
      { kind: 'orders' },
    )
  })

  it('sends a low-stock notification to the product it names', () => {
    // The app opens the catalogue with a Low Stock filter; the portal points at
    // the product itself, which is the screen stock is actually edited on.
    assert.deepEqual(
      sellerNotificationDestination(row({ type: 'low_stock', reference_id: 'product-3' })),
      { kind: 'product', productId: 'product-3' },
    )
    assert.deepEqual(
      sellerNotificationDestination(row({ type: 'low_stock', reference_id: null })),
      { kind: 'products' },
    )
  })

  it('sends a message notification to the thread, and to the inbox without one', () => {
    assert.deepEqual(
      sellerNotificationDestination(row({ type: 'new_message', reference_id: 'convo-1' })),
      { kind: 'conversation', conversationId: 'convo-1' },
    )
    assert.deepEqual(
      sellerNotificationDestination(row({ type: 'new_message', reference_id: null })),
      { kind: 'messages' },
    )
  })

  it('admits when there is nowhere to go', () => {
    // A custom order request opens the app's `CustomOrdersScreen`, which this
    // portal does not have. An inert card beats a link to a page that does not
    // exist — and it matches the app's own `switch`, which has no default.
    assert.deepEqual(sellerNotificationDestination(row({ type: 'custom_order_request' })), {
      kind: 'none',
    })
    assert.deepEqual(
      sellerNotificationDestination(row({ type: 'payment_confirmed', reference_id: 'order-1' })),
      { kind: 'none' },
    )
  })
})

describe('filterSellerNotifications', () => {
  const rows = [
    row({ id: 'a', type: 'new_order', created_at: '2026-09-25T10:00:00Z' }),
    row({ id: 'b', type: 'low_stock', created_at: '2026-09-25T12:00:00Z' }),
    row({ id: 'c', type: 'low_stock', created_at: '2026-09-24T09:00:00Z', is_read: true }),
    row({ id: 'd', type: 'payment_confirmed', created_at: '2026-09-26T09:00:00Z' }),
  ]

  it('is newest first', () => {
    assert.deepEqual(
      filterSellerNotifications(rows).map((entry) => entry.id),
      ['d', 'b', 'a', 'c'],
    )
  })

  it('filters on one type', () => {
    assert.deepEqual(
      filterSellerNotifications(rows, { type: 'low_stock' }).map((entry) => entry.id),
      ['b', 'c'],
    )
  })

  it('can isolate the types it does not know', () => {
    assert.deepEqual(
      filterSellerNotifications(rows, { type: OTHER_SELLER_NOTIFICATION_TYPE }).map((e) => e.id),
      ['d'],
    )
  })

  it('survives nothing at all', () => {
    assert.deepEqual(filterSellerNotifications(undefined), [])
    assert.deepEqual(filterSellerNotifications(null, { type: 'new_order' }), [])
  })
})

describe('unreadSellerNotificationCount', () => {
  const rows = [
    row({ id: 'a', is_read: false }),
    row({ id: 'b', type: 'low_stock', is_read: false }),
    row({ id: 'c', type: 'low_stock', is_read: true }),
    row({ id: 'd', type: 'payment_confirmed', is_read: false }),
  ]

  it('counts the unread ones', () => {
    assert.equal(unreadSellerNotificationCount(rows), 3)
  })

  it('is scoped to a type when asked', () => {
    assert.equal(unreadSellerNotificationCount(rows, { type: 'low_stock' }), 1)
    assert.equal(unreadSellerNotificationCount(rows, { type: 'new_message' }), 0)
  })

  it('counts an unknown type too, so the badge can always be cleared', () => {
    // A chip row built from the five known types alone would show a badge of 1
    // with nothing on screen to explain or clear it.
    assert.equal(unreadSellerNotificationCount(rows, { type: OTHER_SELLER_NOTIFICATION_TYPE }), 1)
  })
})

describe('unreadCountsBySellerType', () => {
  it('has a key for every type, including the unknown one', () => {
    const counts = unreadCountsBySellerType([
      row({ is_read: false }),
      row({ type: 'low_stock', is_read: false }),
      row({ type: 'low_stock', is_read: false }),
      row({ type: 'low_stock', is_read: true }),
      row({ type: 'mystery_type', is_read: false }),
    ])

    assert.deepEqual(counts, {
      new_order: 1,
      stale_order: 0,
      low_stock: 2,
      custom_order_request: 0,
      new_message: 0,
      other: 1,
    })
  })

  it('adds up to the unread total', () => {
    const rows = [
      row({ is_read: false }),
      row({ type: 'new_message', is_read: false }),
      row({ type: 'payment_confirmed', is_read: false }),
      row({ type: 'new_order', is_read: true }),
    ]
    const counts = unreadCountsBySellerType(rows)
    const sum = Object.values(counts).reduce((total, count) => total + count, 0)

    assert.equal(sum, unreadSellerNotificationCount(rows))
  })
})

describe('sellerNotificationTypesPresent', () => {
  it('lists only the types in the feed, in the app order', () => {
    assert.deepEqual(
      sellerNotificationTypesPresent([
        row({ type: 'new_message' }),
        row({ type: 'new_order' }),
        row({ type: 'new_message' }),
      ]),
      ['new_order', 'new_message'],
    )
  })

  it('puts an unknown type last', () => {
    assert.deepEqual(
      sellerNotificationTypesPresent([row({ type: 'payment_confirmed' }), row({ type: 'low_stock' })]),
      ['low_stock', OTHER_SELLER_NOTIFICATION_TYPE],
    )
  })

  it('is empty for an empty feed', () => {
    assert.deepEqual(sellerNotificationTypesPresent(null), [])
  })
})

describe('batched message cards', () => {
  it('passes the trigger\u2019s own previews straight through', () => {
    const batched = row({
      type: 'new_message',
      metadata: {
        conversation_id: 'convo-1',
        message_count: 3,
        previews: [
          { sender: 'Ana Cruz', text: 'Can you do a 38?', timestamp: '2026-09-25T11:00:00Z' },
          { sender: 'Ana Cruz', text: 'Or a 39?', timestamp: '2026-09-25T10:59:00Z' },
        ],
      },
    })

    assert.equal(isBatchedSellerNotification(batched), true)
    assert.equal(isBatchedSellerNotification(row()), false)
  })

  it('treats a single message as unbatched', () => {
    assert.equal(
      isBatchedSellerNotification(row({ type: 'new_message', metadata: { message_count: 1 } })),
      false,
    )
  })
})
