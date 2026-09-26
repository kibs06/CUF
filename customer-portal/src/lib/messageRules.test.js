import assert from 'node:assert/strict'
import { describe, it } from 'node:test'

import {
  MESSAGE_PREVIEW_LENGTH,
  buildConversation,
  buildOutgoingMessage,
  conversationPreview,
  isMine,
  mergeMessage,
  messageAttachment,
  messageBody,
  messageDayKey,
  messageDayLabel,
  messagePreviewText,
  messageRelativeTime,
  messageText,
  needsMarkRead,
  quickOrderMessages,
  threadHistoryState,
  readReceiptFor,
  sortConversations,
  unreadBadgeLabel,
  unreadThreadCount,
  sortMessages,
  unreadFromOther,
} from './messageRules.js'

const conversation = (over = {}) => ({
  id: 'c1',
  store_id: 's1',
  customer_id: 'u1',
  last_message_at: '2026-09-25T10:00:00Z',
  last_message_preview: 'Your pair is ready.',
  created_at: '2026-09-20T10:00:00Z',
  ...over,
})

const message = (over = {}) => ({
  id: 'm1',
  conversation_id: 'c1',
  sender_id: 'u1',
  sender_type: 'customer',
  body: 'Hello',
  is_read: false,
  created_at: '2026-09-25T10:00:00Z',
  ...over,
})

describe('quickOrderMessages', () => {
  it('offers the app’s four questions on a live order', () => {
    assert.deepEqual(quickOrderMessages('preparing'), [
      'When will my order ship?',
      'Can I still change the size/color?',
      'Can I update my delivery address?',
      'Is my order still on track?',
    ])
  })

  it('swaps to the after-the-fact pair once the order is over', () => {
    // The app's `_isCompletedOrder`: cancelled, delivered or received.
    for (const status of ['cancelled', 'delivered', 'received', 'RECEIVED']) {
      assert.deepEqual(quickOrderMessages(status), [
        'I have an issue with my order',
        "I'd like to leave feedback",
      ])
    }
  })

  it('treats an unknown status as live rather than as finished', () => {
    // "When will my order ship?" is a silly question about a cancelled order,
    // and "I have an issue" is a strange opener on one still being made.
    for (const status of ['pending', 'placed', '', null, 'nonsense']) {
      assert.equal(quickOrderMessages(status)[0], 'When will my order ship?')
    }
  })
})

describe('sortConversations', () => {
  it('puts the most recent activity first', () => {
    const sorted = sortConversations([
      conversation({ id: 'old', last_message_at: '2026-09-20T10:00:00Z' }),
      conversation({ id: 'new', last_message_at: '2026-09-25T10:00:00Z' }),
    ])
    assert.deepEqual(sorted.map((row) => row.id), ['new', 'old'])
  })

  it('puts a thread with NO messages at the very top — the app’s nullsFirst', () => {
    // A conversation just opened from a store page has no messages yet, and it
    // has to be where the customer who just opened it is looking.
    const sorted = sortConversations([
      conversation({ id: 'talked', last_message_at: '2026-09-25T10:00:00Z' }),
      conversation({ id: 'fresh', last_message_at: null }),
    ])
    assert.deepEqual(sorted.map((row) => row.id), ['fresh', 'talked'])
  })

  it('breaks ties by when the thread was opened', () => {
    const sorted = sortConversations([
      conversation({ id: 'a', last_message_at: null, created_at: '2026-09-01T00:00:00Z' }),
      conversation({ id: 'b', last_message_at: null, created_at: '2026-09-10T00:00:00Z' }),
    ])
    assert.deepEqual(sorted.map((row) => row.id), ['b', 'a'])
  })

  it('does not mutate the list it was given', () => {
    const list = [conversation({ id: 'a' }), conversation({ id: 'b', last_message_at: null })]
    sortConversations(list)
    assert.equal(list[0].id, 'a')
  })

  it('survives nothing at all', () => {
    assert.deepEqual(sortConversations(null), [])
    assert.deepEqual(sortConversations(undefined), [])
  })
})

describe('conversationPreview', () => {
  it('says so when nothing has been said', () => {
    assert.equal(conversationPreview(conversation({ last_message_preview: null })), 'No messages yet')
    assert.equal(conversationPreview(conversation({ last_message_preview: '   ' })), 'No messages yet')
    assert.equal(conversationPreview(null), 'No messages yet')
  })

  it('passes a normal preview through untouched', () => {
    assert.equal(conversationPreview(conversation()), 'Your pair is ready.')
  })

  it('truncates at the trigger’s own width, with an ellipsis', () => {
    const long = 'x'.repeat(400)
    const preview = conversationPreview(conversation({ last_message_preview: long }))
    assert.equal(preview.length, MESSAGE_PREVIEW_LENGTH)
    assert.equal(preview.endsWith('…'), true)
  })
})

describe('sortMessages', () => {
  it('reads oldest first, whatever order it was given', () => {
    const sorted = sortMessages([
      message({ id: 'b', created_at: '2026-09-25T10:05:00Z' }),
      message({ id: 'a', created_at: '2026-09-25T10:00:00Z' }),
      message({ id: 'c', created_at: '2026-09-25T10:10:00Z' }),
    ])
    assert.deepEqual(sorted.map((row) => row.id), ['a', 'b', 'c'])
  })

  it('survives nothing at all', () => {
    assert.deepEqual(sortMessages(null), [])
  })
})

describe('unreadFromOther', () => {
  it('counts the other party’s unread messages, never your own', () => {
    // A customer's own message stays `is_read = false` until the SELLER reads
    // it. Counting those would badge a thread the moment the customer replies.
    const thread = [
      message({ id: 'a', sender_type: 'seller', is_read: false }),
      message({ id: 'b', sender_type: 'seller', is_read: true }),
      message({ id: 'c', sender_type: 'customer', is_read: false }),
      message({ id: 'd', sender_type: 'customer', is_read: false }),
    ]
    assert.equal(unreadFromOther(thread, 'customer'), 1)
    assert.equal(unreadFromOther(thread, 'seller'), 2)
  })

  it('is zero for an empty thread', () => {
    assert.equal(unreadFromOther([], 'customer'), 0)
    assert.equal(unreadFromOther(null), 0)
  })
})

describe('isMine', () => {
  it('reads the TYPE, because a deleted account nulls the id', () => {
    // `messages.sender_id` is `ON DELETE SET NULL`, so a message from a deleted
    // seller keeps its type and loses its id. Judging the bubble's side by id
    // would move an old message to the customer's own side.
    assert.equal(isMine(message({ sender_type: 'customer', sender_id: null }), 'customer'), true)
    assert.equal(isMine(message({ sender_type: 'seller', sender_id: null }), 'customer'), false)
  })
})

describe('buildOutgoingMessage', () => {
  it('builds the row the RLS policy will accept', () => {
    assert.deepEqual(
      buildOutgoingMessage({ conversationId: 'c1', customerId: 'u1', body: '  Hello  ' }),
      {
        conversation_id: 'c1',
        sender_id: 'u1',
        sender_type: 'customer',
        body: 'Hello',
        order_reference_id: null,
      },
    )
  })

  it('carries the order a thread is about', () => {
    assert.equal(
      buildOutgoingMessage({
        conversationId: 'c1',
        customerId: 'u1',
        body: 'Is my order on track?',
        orderReferenceId: 'o9',
      }).order_reference_id,
      'o9',
    )
  })

  it('refuses to build a message with nothing to say', () => {
    // Whitespace is not a message, and an insert with an empty body would sit
    // in the thread as a blank bubble for both parties.
    for (const body of ['', '   ', null, undefined]) {
      assert.equal(buildOutgoingMessage({ conversationId: 'c1', customerId: 'u1', body }), null)
    }
  })

  it('refuses to build one that cannot be addressed', () => {
    assert.equal(buildOutgoingMessage({ conversationId: null, customerId: 'u1', body: 'hi' }), null)
    assert.equal(buildOutgoingMessage({ conversationId: 'c1', customerId: null, body: 'hi' }), null)
  })
})

describe('buildConversation', () => {
  it('needs both sides', () => {
    assert.deepEqual(buildConversation({ storeId: 's1', customerId: 'u1' }), {
      store_id: 's1',
      customer_id: 'u1',
    })
    assert.equal(buildConversation({ storeId: null, customerId: 'u1' }), null)
    assert.equal(buildConversation({ storeId: 's1', customerId: null }), null)
  })
})

describe('messageBody', () => {
  it('trims, and treats empty as nothing', () => {
    assert.equal(messageBody(' hi '), 'hi')
    assert.equal(messageBody(''), null)
    assert.equal(messageBody(null), null)
  })
})

describe('messageText and messageAttachment', () => {
  it('reads a text-only message', () => {
    assert.equal(messageText(message({ body: '  Hello  ' })), 'Hello')
    assert.equal(messageAttachment(message()), null)
  })

  it('reads an attachment-only message — body is NULL, not empty', () => {
    // The constraint is `body IS NOT NULL OR attachment_url IS NOT NULL`, and
    // the app stores a SIGNED url, so it goes straight into an img.
    const row = message({
      body: null,
      attachment_url: 'https://example.test/signed/pair.jpg?token=abc',
      attachment_type: 'image',
    })
    assert.equal(messageText(row), null)
    assert.deepEqual(messageAttachment(row), {
      url: 'https://example.test/signed/pair.jpg?token=abc',
      type: 'image',
      thumbnailUrl: null,
    })
  })

  it('defaults an unknown attachment type to image, never to nothing', () => {
    assert.equal(messageAttachment(message({ attachment_url: 'u', attachment_type: 'gif' })).type, 'image')
    assert.equal(messageAttachment(message({ attachment_url: 'u', attachment_type: null })).type, 'image')
    assert.equal(messageAttachment(message({ attachment_url: 'u', attachment_type: 'video' })).type, 'video')
  })

  it('ignores a blank attachment url', () => {
    assert.equal(messageAttachment(message({ attachment_url: '   ' })), null)
    assert.equal(messageAttachment(null), null)
  })
})

describe('messagePreviewText', () => {
  it('uses the trigger’s own words for an attachment-only message', () => {
    // `update_conversation_on_message` writes exactly these strings into the
    // inbox preview, so the list and the bubble cannot disagree.
    assert.equal(messagePreviewText(message({ body: '', attachment_url: 'u', attachment_type: 'image' })), '📷 Photo')
    assert.equal(messagePreviewText(message({ body: null, attachment_url: 'u', attachment_type: 'video' })), '🎥 Video')
  })

  it('prefers the caption when a message has both', () => {
    assert.equal(messagePreviewText(message({ body: 'Here it is', attachment_url: 'u', attachment_type: 'image' })), 'Here it is')
  })

  it('is empty when there is nothing to say', () => {
    assert.equal(messagePreviewText(message({ body: null })), '')
  })
})

describe('mergeMessage — the realtime fold', () => {
  const first = message({ id: 'a', created_at: '2026-09-25T10:00:00Z' })
  const second = message({ id: 'b', created_at: '2026-09-25T10:05:00Z' })

  it('appends an insert and keeps the thread oldest-first', () => {
    const merged = mergeMessage([second], { eventType: 'INSERT', row: first })
    assert.deepEqual(merged.map((row) => row.id), ['a', 'b'])
  })

  it('does not duplicate a row the channel delivers twice', () => {
    // Supabase Realtime echoes a sender's OWN insert back to them, so the
    // optimistic bubble and the realtime row are the same message.
    const once = mergeMessage([first], { eventType: 'INSERT', row: first })
    const twice = mergeMessage(once, { eventType: 'INSERT', row: first })
    assert.equal(twice.length, 1)
  })

  it('patches an update in place', () => {
    const merged = mergeMessage([first], { eventType: 'UPDATE', row: { id: 'a', is_read: true } })
    assert.equal(merged[0].is_read, true)
    assert.equal(merged[0].body, 'Hello')
  })

  it('ignores an update for a row that is not loaded', () => {
    // Guessing a position for a message we have never fetched would put it in
    // the wrong place in the thread.
    const merged = mergeMessage([first], { eventType: 'UPDATE', row: { id: 'zz', is_read: true } })
    assert.deepEqual(merged.map((row) => row.id), ['a'])
  })

  it('removes on delete', () => {
    const merged = mergeMessage([first, second], { eventType: 'DELETE', row: { id: 'a' } })
    assert.deepEqual(merged.map((row) => row.id), ['b'])
  })

  it('survives an event with no row, and no list at all', () => {
    assert.deepEqual(mergeMessage([first], { eventType: 'INSERT', row: null }).map((r) => r.id), ['a'])
    assert.deepEqual(mergeMessage(null, { eventType: 'INSERT', row: first }).map((r) => r.id), ['a'])
  })
})

describe('messageRelativeTime', () => {
  const now = new Date('2026-09-25T12:00:00Z').getTime()
  const ago = (ms) => new Date(now - ms).toISOString()

  it('walks the app’s ladder', () => {
    assert.equal(messageRelativeTime(ago(30 * 1000), now), 'Just now')
    assert.equal(messageRelativeTime(ago(5 * 60 * 1000), now), '5m ago')
    assert.equal(messageRelativeTime(ago(3 * 60 * 60 * 1000), now), '3h ago')
    assert.equal(messageRelativeTime(ago(6 * 24 * 60 * 60 * 1000), now), '6d ago')
    assert.equal(messageRelativeTime(ago(61 * 24 * 60 * 60 * 1000), now), '2mo ago')
  })

  it('has no week rung, unlike the notification feed', () => {
    // The app has two ladders and they disagree here on purpose.
    assert.equal(messageRelativeTime(ago(9 * 24 * 60 * 60 * 1000), now), '9d ago')
  })

  it('is empty — not "20658d ago" — for a thread with no messages', () => {
    for (const value of [null, undefined, '', 'not a date']) {
      assert.equal(messageRelativeTime(value, now), '')
    }
  })
})

describe('unreadBadgeLabel and unreadThreadCount', () => {
  it('caps the pill at 9+, like the app', () => {
    assert.equal(unreadBadgeLabel(1), '1')
    assert.equal(unreadBadgeLabel(9), '9')
    assert.equal(unreadBadgeLabel(10), '9+')
    assert.equal(unreadBadgeLabel(400), '9+')
  })

  it('has nothing to show at zero, and does not crash on junk', () => {
    assert.equal(unreadBadgeLabel(0), null)
    assert.equal(unreadBadgeLabel(-2), null)
    assert.equal(unreadBadgeLabel(null), null)
    assert.equal(unreadBadgeLabel('nonsense'), null)
    assert.equal(unreadBadgeLabel('3'), '3')
  })

  it('counts threads, not messages — the app’s own badge rule', () => {
    // `if (count > 0) total++`: a thread with twelve unread messages still
    // counts once, so the badge can never outgrow the inbox.
    assert.equal(
      unreadThreadCount([
        { id: 'a', unread_count: 12 },
        { id: 'b', unread_count: 1 },
        { id: 'c', unread_count: 0 },
      ]),
      2,
    )
    assert.equal(unreadThreadCount([]), 0)
    assert.equal(unreadThreadCount(null), 0)
  })
})

describe('needsMarkRead and readReceiptFor', () => {
  it('asks only when the other party is unread', () => {
    assert.equal(needsMarkRead([message({ sender_type: 'seller', is_read: false })]), true)
    assert.equal(needsMarkRead([message({ sender_type: 'seller', is_read: true })]), false)
    assert.equal(needsMarkRead([message({ sender_type: 'customer', is_read: false })]), false)
    assert.equal(needsMarkRead([]), false)
  })

  it('reports a receipt only under the customer’s own last message', () => {
    assert.equal(readReceiptFor([message({ sender_type: 'customer', is_read: true })]), true)
    assert.equal(readReceiptFor([message({ sender_type: 'customer', is_read: false })]), false)
    assert.equal(readReceiptFor([message({ sender_type: 'seller' })]), null)
    assert.equal(readReceiptFor([]), null)
  })
})

describe('the day separators a chat draws', () => {
  /* Local dates, built from components, so the test does not depend on the
     machine's timezone the way a `Z`-suffixed string would. */
  const at = (day, hour, minute = 0) => new Date(2026, 8, day, hour, minute)

  it('keys two messages on the same day together', () => {
    assert.equal(messageDayKey(at(26, 8)), messageDayKey(at(26, 23)))
    assert.notEqual(messageDayKey(at(26, 23)), messageDayKey(at(27, 0)))
  })

  it('has no key for a missing or unreadable timestamp', () => {
    assert.equal(messageDayKey(null), '')
    assert.equal(messageDayKey(undefined), '')
    assert.equal(messageDayKey('not a date'), '')
  })

  it('says Today and Yesterday in words', () => {
    const now = at(26, 20)
    assert.equal(messageDayLabel(at(26, 8), now), 'Today')
    assert.equal(messageDayLabel(at(25, 23), now), 'Yesterday')
  })

  it('falls back to a written date further back', () => {
    const label = messageDayLabel(at(1, 10), at(26, 20))
    assert.match(label, /Sep/)
    assert.match(label, /2026/)
    assert.notEqual(label, 'Today')
  })

  it('draws nothing rather than a wrong day', () => {
    assert.equal(messageDayLabel('not a date', at(26, 20)), '')
  })
})

describe('threadHistoryState', () => {
  it('separates an empty conversation from a read that did not happen', () => {
    // The distinction the thread's copy depends on: `empty` may say "say hello",
    // `failed` may not, because a months-long conversation is not a greeting
    // opportunity.
    assert.equal(threadHistoryState({ isError: false, count: 0 }), 'empty')
    assert.equal(threadHistoryState({ isError: true, count: 0 }), 'failed')
  })

  it('calls a live thread on a failed read what it is: partial', () => {
    // The bug this exists for — realtime delivers the new messages while the
    // history never loads, so a thread that is missing months looks complete.
    assert.equal(threadHistoryState({ isError: true, count: 3 }), 'partial')
    assert.equal(threadHistoryState({ isError: false, count: 3 }), 'ready')
  })

  it('treats a missing or nonsense count as nothing to show', () => {
    assert.equal(threadHistoryState({}), 'empty')
    assert.equal(threadHistoryState(), 'empty')
    assert.equal(threadHistoryState({ isError: true }), 'failed')
    assert.equal(threadHistoryState({ count: null }), 'empty')
    assert.equal(threadHistoryState({ count: 'not a number' }), 'empty')
    assert.equal(threadHistoryState({ count: 2 }), 'ready')
  })
})
