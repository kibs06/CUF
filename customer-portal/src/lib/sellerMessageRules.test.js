import assert from 'node:assert/strict'
import { describe, it } from 'node:test'

import {
  SELLER_CONVERSATION_FALLBACK_NAME,
  sellerConversationName,
  sellerConversationStarted,
} from './sellerMessageRules.js'
import { conversationPreview, sortConversations, unreadThreadCount } from './messageRules.js'

/** A conversation row the way the seller's query returns one. */
const conversation = (over = {}) => ({
  id: 'convo-1',
  store_id: 'store-1',
  customer_id: 'customer-1',
  customer_name: 'Ana Cruz',
  last_message_at: '2026-09-25T10:00:00Z',
  last_message_preview: 'Can you do a 38?',
  created_at: '2026-09-24T10:00:00Z',
  unread_count: 0,
  ...over,
})

describe('sellerConversationName', () => {
  it('reads the denormalised column', () => {
    assert.equal(sellerConversationName(conversation()), 'Ana Cruz')
  })

  it('falls back for a thread that predates the backfill', () => {
    // `customer_name` was added to a table that already had rows, so a NULL is
    // a real case rather than a broken one — and a blank row is indistinguishable
    // from a page that failed to load.
    assert.equal(sellerConversationName(conversation({ customer_name: null })), 'Customer')
    assert.equal(sellerConversationName(conversation({ customer_name: '   ' })), 'Customer')
    assert.equal(sellerConversationName(null), SELLER_CONVERSATION_FALLBACK_NAME)
  })

  it('does not invent a second source for the name', () => {
    // There is no e-mail fallback on purpose: this path never selects one, and
    // two sources would disagree the moment the customer changed either.
    assert.equal(
      sellerConversationName(conversation({ customer_name: null, customer_email: 'a@b.c' })),
      SELLER_CONVERSATION_FALLBACK_NAME,
    )
  })
})

describe('sellerConversationStarted', () => {
  it('is false for a thread nobody has written in', () => {
    assert.equal(sellerConversationStarted(conversation({ last_message_at: null })), false)
    assert.equal(sellerConversationStarted(conversation()), true)
  })
})

describe('the shared rules the seller inbox reuses', () => {
  it('puts an empty thread at the top, exactly as the customer inbox does', () => {
    // `sortConversations` is shared rather than reimplemented: the seller who
    // just opened a thread from an order is looking for it for the same reason
    // a customer is.
    const sorted = sortConversations([
      conversation({ id: 'written', last_message_at: '2026-09-25T10:00:00Z' }),
      conversation({ id: 'empty', last_message_at: null }),
    ])

    assert.deepEqual(sorted.map((row) => row.id), ['empty', 'written'])
  })

  it('counts threads needing a reply, not messages', () => {
    assert.equal(
      unreadThreadCount([
        conversation({ unread_count: 3 }),
        conversation({ unread_count: 0 }),
      ]),
      1,
    )
  })

  it('says so when a thread has no messages yet', () => {
    assert.equal(conversationPreview(conversation({ last_message_preview: null })), 'No messages yet')
  })
})
