import assert from 'node:assert/strict'
import { describe, it } from 'node:test'

import {
  MESSAGE_PUSH_FUNCTION,
  MESSAGE_PUSH_SENDER_TYPES,
  messagePushPayload,
} from './messagePushRules.js'

/** The stored row a seller's reply comes back as. */
const SELLER_ROW = {
  id: 'm1',
  conversation_id: 'convo-1',
  sender_id: 'seller-1',
  sender_type: 'seller',
  body: 'Your pair ships tomorrow morning.',
  order_reference_id: null,
  is_read: false,
  created_at: '2026-09-26T02:00:00Z',
}

describe('messagePushPayload', () => {
  it('names the function by the name the app calls', () => {
    // `send-message-push` is deployed; a typo here is a 404 nobody sees, because
    // the call is fire and forget.
    assert.equal(MESSAGE_PUSH_FUNCTION, 'send-message-push')
    assert.deepEqual(MESSAGE_PUSH_SENDER_TYPES, ['customer', 'seller'])
  })

  it('sends the four fields a seller→customer push needs', () => {
    assert.deepEqual(messagePushPayload(SELLER_ROW), {
      conversation_id: 'convo-1',
      sender_id: 'seller-1',
      sender_type: 'seller',
      body: 'Your pair ships tomorrow morning.',
    })
  })

  it('does the same for the other direction, from the customer row', () => {
    assert.deepEqual(
      messagePushPayload({ conversation_id: 'convo-1', sender_id: 'c1', sender_type: 'customer', body: 'Hi' }),
      { conversation_id: 'convo-1', sender_id: 'c1', sender_type: 'customer', body: 'Hi' },
    )
  })

  it('carries nothing the function would have to ignore', () => {
    // The title is the database's (the store's name, or the customer's), and the
    // recipient is resolved from the conversation. A payload that also shipped a
    // `store_name` would be a second source for a name the server already has.
    const payload = messagePushPayload(SELLER_ROW)
    assert.deepEqual(Object.keys(payload).sort(), [
      'body',
      'conversation_id',
      'sender_id',
      'sender_type',
    ])
  })

  it('leaves an empty body out rather than sending an empty string', () => {
    // The function has its own fallback for a message with no text, and an
    // attachment-only row is the case it exists for.
    const payload = messagePushPayload({ ...SELLER_ROW, body: '   ' })
    assert.equal('body' in payload, false)
    assert.deepEqual(messagePushPayload({ ...SELLER_ROW, body: null }), {
      conversation_id: 'convo-1',
      sender_id: 'seller-1',
      sender_type: 'seller',
    })
  })

  it('trims the text it does send', () => {
    assert.equal(messagePushPayload({ ...SELLER_ROW, body: '  hello  ' }).body, 'hello')
  })

  it('refuses to make a request that could not work', () => {
    assert.equal(messagePushPayload({ ...SELLER_ROW, conversation_id: null }), null)
    assert.equal(messagePushPayload({ ...SELLER_ROW, conversation_id: '  ' }), null)
    assert.equal(messagePushPayload({ ...SELLER_ROW, sender_id: undefined }), null)
    assert.equal(messagePushPayload({ ...SELLER_ROW, sender_type: 'admin' }), null)
    assert.equal(messagePushPayload({ ...SELLER_ROW, sender_type: '' }), null)
    assert.equal(messagePushPayload({ ...SELLER_ROW, sender_type: null }), null)
  })

  it('reads either spelling of the fields, because a caller may hold a draft', () => {
    // `buildOutgoingMessage` returns the snake_case row, but an optimistic copy
    // is assembled in the browser and a caller should not have to know which one
    // it is holding.
    assert.deepEqual(messagePushPayload({ conversationId: 'c1', senderId: 'u1', senderType: 'Seller' }), {
      conversation_id: 'c1',
      sender_id: 'u1',
      sender_type: 'seller',
    })
  })

  it('survives being handed nothing at all', () => {
    assert.equal(messagePushPayload(), null)
    assert.equal(messagePushPayload(null), null)
    assert.equal(messagePushPayload('a string'), null)
    assert.equal(messagePushPayload(42), null)
  })
})
