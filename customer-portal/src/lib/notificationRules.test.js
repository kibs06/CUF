import assert from 'node:assert/strict'
import { describe, it } from 'node:test'

import {
  NOTIFICATION_CATEGORIES,
  filterNotifications,
  isBatchedNotification,
  notificationCategory,
  notificationCategoryLabel,
  notificationConversationId,
  notificationDestination,
  notificationMessageCount,
  notificationMetadata,
  notificationOrderType,
  notificationPreviews,
  notificationRelativeTime,
  notificationStoreName,
  unreadCountsByCategory,
  unreadNotificationCount,
} from './notificationRules.js'

/** A row the way the table returns one. */
const row = (over = {}) => ({
  id: 'n1',
  category: 'processing',
  title: 'Order is processing',
  message: 'Order #12345678 is being prepared.',
  order_type: 'catalog',
  order_id: 'order-1',
  is_read: false,
  created_at: '2026-09-25T10:00:00Z',
  metadata: null,
  ...over,
})

describe('notificationCategory', () => {
  it('knows all nine the database can send', () => {
    // The first migration created five; message, support, approval and
    // reservations arrived later. A feed that only knew five would show four
    // kinds of notification as "Unpaid".
    assert.deepEqual(NOTIFICATION_CATEGORIES, [
      'unpaid',
      'processing',
      'shipped',
      'review',
      'returns',
      'message',
      'support',
      'approval',
      'reservations',
    ])
    for (const name of NOTIFICATION_CATEGORIES) {
      assert.equal(notificationCategory(name), name)
      assert.notEqual(notificationCategoryLabel(name), undefined)
    }
  })

  it('labels them the way the app does', () => {
    assert.equal(notificationCategoryLabel('reservations'), 'Reservation')
    assert.equal(notificationCategoryLabel('message'), 'Message')
  })

  it('falls back to unpaid — the app’s own default — never to nothing', () => {
    // A category drives an icon and a chip; an unknown one has to render as
    // something rather than disappear from the feed.
    for (const value of [null, undefined, '', 'nonsense', 42, {}]) {
      assert.equal(notificationCategory(value), 'unpaid')
    }
  })

  it('is case- and whitespace-insensitive', () => {
    assert.equal(notificationCategory('  ShIpped '), 'shipped')
  })
})

describe('the feed’s tabs', () => {
  it('buckets by order_type, defaulting to catalog', () => {
    assert.equal(notificationOrderType(row({ order_type: 'custom' })), 'custom')
    assert.equal(notificationOrderType(row({ order_type: 'catalog' })), 'catalog')
    assert.equal(notificationOrderType(row({ order_type: null })), 'catalog')
    assert.equal(notificationOrderType(row({})), 'catalog')
  })

  it('filters and sorts newest first', () => {
    const feed = [
      row({ id: 'old', created_at: '2026-09-20T10:00:00Z' }),
      row({ id: 'custom', order_type: 'custom', created_at: '2026-09-24T10:00:00Z' }),
      row({ id: 'new', created_at: '2026-09-25T10:00:00Z' }),
    ]

    assert.deepEqual(
      filterNotifications(feed).map((item) => item.id),
      ['new', 'custom', 'old'],
    )
    assert.deepEqual(
      filterNotifications(feed, { tab: 'custom' }).map((item) => item.id),
      ['custom'],
    )
    assert.deepEqual(
      filterNotifications(feed, { tab: 'catalog' }).map((item) => item.id),
      ['new', 'old'],
    )
  })

  it('filters by category on top of the tab', () => {
    const feed = [
      row({ id: 'a', category: 'message', created_at: '2026-09-25T10:00:00Z' }),
      row({ id: 'b', category: 'processing', created_at: '2026-09-24T10:00:00Z' }),
    ]

    assert.deepEqual(
      filterNotifications(feed, { category: 'message' }).map((item) => item.id),
      ['a'],
    )
    assert.deepEqual(filterNotifications(feed, { category: 'returns' }), [])
  })

  it('survives nothing at all', () => {
    assert.deepEqual(filterNotifications(null), [])
    assert.deepEqual(filterNotifications(undefined, { tab: 'custom' }), [])
  })
})

describe('unread counts', () => {
  const feed = [
    row({ id: 'a', is_read: false, category: 'message' }),
    row({ id: 'b', is_read: false, category: 'message' }),
    row({ id: 'c', is_read: false, category: 'shipped' }),
    row({ id: 'd', is_read: true, category: 'shipped' }),
  ]

  it('counts everything unread, and one category', () => {
    assert.equal(unreadNotificationCount(feed), 3)
    assert.equal(unreadNotificationCount(feed, { category: 'message' }), 2)
    assert.equal(unreadNotificationCount(feed, { category: 'returns' }), 0)
  })

  it('returns every category, zeroed, for the chip row', () => {
    const counts = unreadCountsByCategory(feed)
    assert.equal(counts.message, 2)
    assert.equal(counts.shipped, 1)
    assert.equal(counts.returns, 0)
    assert.equal(Object.keys(counts).length, NOTIFICATION_CATEGORIES.length)
  })
})

describe('metadata', () => {
  it('accepts an object or a JSON string, and refuses the rest', () => {
    assert.deepEqual(notificationMetadata(row({ metadata: { a: 1 } })), { a: 1 })
    assert.deepEqual(notificationMetadata(row({ metadata: '{"a":1}' })), { a: 1 })
    assert.equal(notificationMetadata(row({ metadata: 'not json' })), null)
    assert.equal(notificationMetadata(row({ metadata: '[1,2]' })), null)
    assert.equal(notificationMetadata(row({ metadata: null })), null)
  })

  it('reads the batching trigger’s own fields', () => {
    const batched = row({
      category: 'message',
      metadata: {
        conversation_id: 'conv-1',
        store_name: 'Janella',
        message_count: 3,
        previews: [
          { sender: 'Janella', text: 'Your pair is ready.', timestamp: '2026-09-25T10:00:00Z' },
          { sender: 'Janella', text: 'We can ship today.', timestamp: '2026-09-25T09:00:00Z' },
        ],
      },
    })

    assert.equal(notificationMessageCount(batched), 3)
    assert.equal(isBatchedNotification(batched), true)
    assert.equal(notificationConversationId(batched), 'conv-1')
    assert.equal(notificationStoreName(batched), 'Janella')
    assert.deepEqual(
      notificationPreviews(batched).map((preview) => preview.text),
      ['Your pair is ready.', 'We can ship today.'],
    )
  })

  it('is a single message when the row predates batching', () => {
    const legacy = row({ category: 'message', metadata: { conversation_id: 'conv-1' } })
    assert.equal(notificationMessageCount(legacy), 1)
    assert.equal(isBatchedNotification(legacy), false)
    assert.deepEqual(notificationPreviews(legacy), [])
  })

  it('drops a preview with no text rather than adding an empty line', () => {
    const messy = row({
      metadata: { previews: [{ sender: 'x' }, { text: 'real' }, 'nonsense', null] },
    })
    assert.deepEqual(notificationPreviews(messy).map((preview) => preview.text), ['real'])
  })

  it('is null-safe about a count that is not a number', () => {
    assert.equal(notificationMessageCount(row({ metadata: { message_count: 'many' } })), 1)
    assert.equal(notificationMessageCount(row({ metadata: { message_count: 0 } })), 1)
    assert.equal(notificationMessageCount(row({ metadata: { message_count: '4' } })), 4)
  })
})

describe('notificationDestination', () => {
  it('sends a message to its thread', () => {
    assert.deepEqual(
      notificationDestination(
        row({ category: 'message', metadata: { conversation_id: 'conv-9' } }),
      ),
      { kind: 'conversation', conversationId: 'conv-9' },
    )
  })

  it('reports a support reply as “reports”, which the portal does not have', () => {
    // The app opens MyReportsScreen; the portal has no equivalent, so the page
    // leaves the card inert instead of linking to a 404.
    assert.deepEqual(notificationDestination(row({ category: 'support' })), { kind: 'reports' })
  })

  it('sends an order notification to its order', () => {
    assert.deepEqual(notificationDestination(row({ order_id: 'order-7' })), {
      kind: 'order',
      orderId: 'order-7',
    })
  })

  it('is inert when there is nowhere to go', () => {
    // An `approval` card with no order, or a message card whose metadata lost
    // its conversation and has no order either: an untappable card beats a
    // wrong one.
    assert.deepEqual(notificationDestination(row({ order_id: null })), { kind: 'none' })
    assert.deepEqual(
      notificationDestination(row({ category: 'message', metadata: null, order_id: null })),
      { kind: 'none' },
    )
    assert.deepEqual(notificationDestination(null), { kind: 'none' })
  })

  it('falls back to the ORDER when a message card has lost its conversation', () => {
    // The app's `onTap` order, kept exactly: message-with-conversation, then
    // support, then any order. A message card that can still point at the order
    // it is about should point at it rather than going inert.
    assert.deepEqual(
      notificationDestination(row({ category: 'message', metadata: null, order_id: 'order-3' })),
      { kind: 'order', orderId: 'order-3' },
    )
  })
})

describe('notificationRelativeTime', () => {
  const at = '2026-09-25T12:00:00Z'
  const now = Date.parse(at)

  it('matches the app’s wording, at every boundary', () => {
    const ago = (seconds) => notificationRelativeTime(new Date(now - seconds * 1000).toISOString(), now)
    assert.equal(ago(0), 'Just now')
    assert.equal(ago(59), 'Just now')
    assert.equal(ago(60), '1m ago')
    assert.equal(ago(59 * 60), '59m ago')
    assert.equal(ago(60 * 60), '1h ago')
    assert.equal(ago(23 * 3600), '23h ago')
    assert.equal(ago(24 * 3600), '1d ago')
    assert.equal(ago(6 * 86400), '6d ago')
    assert.equal(ago(7 * 86400), '1w ago')
    assert.equal(ago(29 * 86400), '4w ago')
    assert.equal(ago(30 * 86400), '1mo ago')
    assert.equal(ago(400 * 86400), '13mo ago')
  })

  it('is empty rather than “NaN ago” for a timestamp it cannot read', () => {
    assert.equal(notificationRelativeTime(null, now), '')
    assert.equal(notificationRelativeTime('not a date', now), '')
  })
})
