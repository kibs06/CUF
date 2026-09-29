import { test } from 'node:test'
import assert from 'node:assert/strict'

import {
  ASK_AGAIN_TAIL,
  ASK_BODY,
  ASK_ENDING,
  ASK_NAME_FALLBACK,
  ASK_PUSH_FUNCTION,
  ASK_PUSH_SCREEN,
  CLOSING_NOTICE,
  DECLINE_QUOTE,
  NOTHING_TO_DECLINE_SENTENCE,
  NOTICE_CATEGORY,
  NOTICE_CHANNELS,
  NOTICE_NOT_READABLE_SENTENCE,
  SELLER_NOTICE_TYPE,
  TEAM_QUOTE,
  askEndingPush,
  declineDeliverySentence,
  deliveryHeadline,
  deliverySentence,
  noteReachesSeller,
  sellerWasTold,
} from './askDelivery.js'
import { MODELLING_ENDING } from './modelPublish.js'

// ─── Did this ending tell the seller? ──────────────────────────────

test('exactly one ending told the seller, and it is the one that closed the ask', () => {
  assert.equal(sellerWasTold(MODELLING_ENDING.CLOSED), true)
  assert.equal(sellerWasTold(MODELLING_ENDING.NOT_LIVE), false)
  assert.equal(sellerWasTold(MODELLING_ENDING.LIVE_BUT_OPEN), false)

  // An ending this module has never heard of must not be rounded to "told":
  // the claim is about the seller's inbox, so the safe default is silence.
  assert.equal(sellerWasTold('something_new'), false)
  assert.match(deliverySentence('something_new'), /unknown/)
})

test('the headline says which of the two happened, in one line', () => {
  assert.equal(deliveryHeadline(MODELLING_ENDING.CLOSED), 'The seller has been told.')
  assert.equal(deliveryHeadline(MODELLING_ENDING.NOT_LIVE), 'The seller has not been told.')
  assert.equal(deliveryHeadline(MODELLING_ENDING.LIVE_BUT_OPEN), 'The seller has not been told.')
})

test('the closed sentence quotes the sentence the seller reads, on both channels', () => {
  const sentence = deliverySentence(MODELLING_ENDING.CLOSED)

  assert.match(sentence, /The seller has been told/)
  // The title, quoted verbatim — a paraphrase is how "your model is ready"
  // becomes "the team finished your model" in an admin's head.
  assert.ok(sentence.includes(`"${CLOSING_NOTICE.FULFILLED}"`))
  // ⚠️ The V2.14 fact: one row was correct and unreadable at the same time.
  for (const channel of NOTICE_CHANNELS) {
    assert.ok(
      sentence.includes(channel.label),
      `${channel.table} is one of the two rows the RPCs write and must be named`,
    )
  }
  assert.equal(NOTICE_CHANNELS.length, 2)
  // The claim the SQL has to keep: same transaction, so "closed" implies "told".
  assert.match(sentence, /same transaction/)
})

test('the two silent endings say why nothing was sent', () => {
  const liveButOpen = deliverySentence(MODELLING_ENDING.LIVE_BUT_OPEN)
  assert.match(liveButOpen, /not been told anything/)
  assert.match(liveButOpen, /ask is still open, so no notice was written/)
  // The green-tick hazard this whole phase is about, named.
  assert.match(liveButOpen, /a green tick would have hidden/)

  const notLive = deliverySentence(MODELLING_ENDING.NOT_LIVE)
  assert.match(notLive, /not been told anything, and needs nothing/)
  assert.match(notLive, /nothing went live/)
})

test('the two endings file under one subject, so the words have to carry the polarity', () => {
  assert.notEqual(CLOSING_NOTICE.FULFILLED, CLOSING_NOTICE.DECLINED)
  assert.match(CLOSING_NOTICE.FULFILLED, /ready/)
  assert.match(CLOSING_NOTICE.DECLINED, /declined/)
  // One feed, one category: the seller's "3D models" filter holds both, which is
  // exactly why a decline cannot reuse the fulfilled words.
  assert.equal(NOTICE_CATEGORY, 'models')
  assert.equal(SELLER_NOTICE_TYPE, 'model_request')
})

// ─── The decline, and the reason it carries ────────────────────────

test('the decline tells the seller in the admin’s own words', () => {
  const sentence = declineDeliverySentence({ reason: 'Mesh came out too dense to fit the budget.' })

  assert.match(sentence, /The seller has been told/)
  assert.ok(sentence.includes(`"${CLOSING_NOTICE.DECLINED}"`))
  assert.ok(sentence.includes(`${DECLINE_QUOTE}Mesh came out too dense to fit the budget.`))
  // A decline is not a dead end: the partial index exists so they can retry.
  assert.match(sentence, /ask again/)
})

test('a blank reason degrades to a notice that stands on its own, never a dangling quote', () => {
  for (const blank of [{}, { reason: '' }, { reason: '   ' }, { reason: null }, undefined]) {
    const sentence = declineDeliverySentence(blank)

    assert.match(sentence, /The seller has been told/)
    assert.match(sentence, /with no reason in it/)
    // No colon left hanging over an empty quote, and no empty quote either.
    assert.ok(!sentence.includes(DECLINE_QUOTE))
    assert.ok(!sentence.includes('""'))
    assert.ok(!/:\s*$/.test(sentence))
  }
})

test('a reason that was already closed tells nobody, and the page says so instead of "done"', () => {
  assert.match(NOTHING_TO_DECLINE_SENTENCE, /changes nothing and tells nobody/)
  assert.match(NOTHING_TO_DECLINE_SENTENCE, /not found or already closed/)
})

// ─── The note, and the limit of what the portal can know ───────────

test('an admin’s note is known to reach the seller, quoted under a fixed prefix', () => {
  const sentence = noteReachesSeller()
  assert.ok(sentence.includes(`"${TEAM_QUOTE}…"`))
  assert.match(sentence, /both channels/)
})

test('the portal says what it cannot show rather than showing a blank', () => {
  // Both notice tables grant SELECT to the recipient only, so a timestamp here
  // would have to be invented — this is the sentence that says so.
  assert.match(NOTICE_NOT_READABLE_SENTENCE, /grant SELECT to the recipient/)
  assert.match(NOTICE_NOT_READABLE_SENTENCE, /no admin policy exists/)
  assert.match(NOTICE_NOT_READABLE_SENTENCE, /no timestamp it cannot read/)
})

// ─── The push: the same words, onto a lock screen ──────────────────

test('the fulfilled push says what the bell says, and the note is the argument', () => {
  const plain = askEndingPush({
    kind: ASK_ENDING.FULFILLED,
    productName: 'JBC Crown Leather Sandals',
    productId: 'e3b0c442-0000-0000-0000-000000000000',
  })

  assert.equal(plain.title, CLOSING_NOTICE.FULFILLED)
  assert.equal(plain.body, 'JBC Crown Leather Sandals — it is live on the product page.')
  // The tap has to land somewhere the app can open, and the key is the one the
  // app already navigates for — an invented screen key swallows the tap.
  assert.equal(plain.screen, ASK_PUSH_SCREEN)
  assert.equal(plain.type, SELLER_NOTICE_TYPE)
  assert.equal(plain.referenceId, 'e3b0c442-0000-0000-0000-000000000000')

  const withNote = askEndingPush({
    kind: ASK_ENDING.FULFILLED,
    productName: 'JBC Crown Leather Sandals',
    note: '  Signed by the artisan.  ',
  })
  // Verbatim, trimmed, under the same prefix the RPC uses — a note the admin
  // typed is the seller's only written explanation.
  assert.equal(
    withNote.body,
    'JBC Crown Leather Sandals — it is live on the product page. ' +
      'From the team: Signed by the artisan.',
  )
  // A blank note adds nothing: no dangling prefix, no double space.
  const blank = askEndingPush({ kind: ASK_ENDING.FULFILLED, productName: 'X', note: '   ' })
  assert.equal(blank.body, 'X — it is live on the product page.')
})

test('the declined push carries the reason and the way back', () => {
  const push = askEndingPush({
    kind: ASK_ENDING.DECLINED,
    productName: 'JBC Crown Leather Sandals',
    reason: 'No usable capture of the straps.',
  })

  assert.equal(push.title, CLOSING_NOTICE.DECLINED)
  assert.equal(
    push.body,
    'JBC Crown Leather Sandals' +
      ASK_BODY.DECLINED +
      ' They said: No usable capture of the straps.' +
      ASK_AGAIN_TAIL,
  )

  // The degradation for a client that sends no reason (older app, direct RPC
  // call): the sentence stands on its own rather than ending in a colon.
  const bare = askEndingPush({ kind: ASK_ENDING.DECLINED, productName: 'X' })
  assert.equal(bare.body, `X${ASK_BODY.DECLINED}${ASK_AGAIN_TAIL}`)
  assert.ok(!bare.body.includes('They said:'))
})

test('an ending this module does not know pushes nothing, and a nameless product reads as the RPC writes it', () => {
  // Same rule as `sellerWasTold`: the claim is about somebody's phone, so the
  // safe default is silence rather than a guess.
  assert.equal(askEndingPush({ kind: 'something_new' }), null)
  assert.equal(askEndingPush(), null)

  const nameless = askEndingPush({ kind: ASK_ENDING.FULFILLED })
  assert.equal(nameless.body, `${ASK_NAME_FALLBACK}${ASK_BODY.FULFILLED}`)
  assert.equal(nameless.referenceId, null)

  // ⚠️ A string, always. FCM's data map is string-to-string and the edge
  // function copies this value into it verbatim — a bigint arriving as a number
  // would fail the send at FCM instead of here, where the reason is legible.
  const numeric = askEndingPush({ kind: ASK_ENDING.FULFILLED, productName: 'X', productId: 42 })
  assert.equal(numeric.referenceId, '42')
  assert.equal(typeof numeric.referenceId, 'string')

  // The function name is the app's, not an invention of this module's.
  assert.equal(ASK_PUSH_FUNCTION, 'send-notification-push')
})
