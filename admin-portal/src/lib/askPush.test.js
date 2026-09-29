import { test } from 'node:test'
import assert from 'node:assert/strict'

import { ASK_ENDING, ASK_PUSH_FUNCTION, CLOSING_NOTICE, SELLER_NOTICE_TYPE } from './askDelivery.js'
import { sendAskEndingPush } from './askPush.js'

// ─── The push, driven by a fake client ─────────────────────────────
//
// This is the portal's half of a notification loop whose other half is SQL, and
// the thing that made it necessary was a real report: "the request was closed and
// the seller's phone stayed quiet". Two properties matter, and the fake client is
// how both are checked without a network:
//
//   1. the payload it asks the Edge Function to send, and
//   2. that **nothing it can do makes the close look failed** — every failure is
//      a returned `{sent:false}`, never a thrown error.
//
// The client is injected rather than imported (`askPush.js` takes it as an
// argument) for exactly this reason: the same seam the app's own services use for
// their data sources, so a test can prove the sequence without a live Supabase.

const REQUEST = {
  store_id: 'store-1',
  product_id: 'product-1',
  products: { name: 'JBC Crown Leather Sandals' },
}

/** A stand-in for `SupabaseClient` with only what this function calls. */
function fakeClient({ request = REQUEST, store = { owner_id: 'owner-1' }, requestError = null, storeError = null, invokeError = null } = {}) {
  const calls = []
  return {
    calls,
    from(table) {
      const result = table === 'shoe_model_requests' ? { data: request, error: requestError } : { data: store, error: storeError }
      const chain = {
        eq(column, value) {
          calls.push({ kind: 'read', table, column, value })
          return chain
        },
        maybeSingle: async () => result,
      }
      return { select: () => chain }
    },
    functions: {
      async invoke(name, options) {
        calls.push({ kind: 'invoke', name, body: options?.body })
        return { data: invokeError ? null : { message: 'Sent 1 notifications' }, error: invokeError }
      },
    },
  }
}

test('a fulfilled ask asks for exactly one push, addressed to the store owner', async () => {
  const client = fakeClient()
  const result = await sendAskEndingPush({
    client,
    requestId: 'request-1',
    kind: ASK_ENDING.FULFILLED,
    note: 'Signed by the artisan.',
  })

  assert.deepEqual(result, { sent: true })

  // Which row was read, so a push cannot be addressed to the wrong ask.
  assert.deepEqual(client.calls[0], {
    kind: 'read',
    table: 'shoe_model_requests',
    column: 'id',
    value: 'request-1',
  })

  const invokes = client.calls.filter((c) => c.kind === 'invoke')
  assert.equal(invokes.length, 1, 'one close is one push')
  assert.equal(invokes[0].name, ASK_PUSH_FUNCTION)

  // The Edge Function's own contract: a user id, a title, a body, and the type
  // whose channel the app already renders. The product name reaches the sentence
  // from the request row rather than from the caller, so the caller cannot pass a
  // stale one.
  assert.equal(invokes[0].body.recipientUserId, 'owner-1')
  assert.equal(invokes[0].body.title, CLOSING_NOTICE.FULFILLED)
  assert.equal(invokes[0].body.type, SELLER_NOTICE_TYPE)
  assert.equal(
    invokes[0].body.body,
    'JBC Crown Leather Sandals — it is live on the product page. From the team: Signed by the artisan.',
  )
  assert.equal(invokes[0].body.referenceId, 'product-1')
})

test('a decline sends the other sentence, quoting the reason the seller will read', async () => {
  const client = fakeClient()
  const result = await sendAskEndingPush({
    client,
    requestId: 'request-2',
    kind: ASK_ENDING.DECLINED,
    reason: 'No usable capture of the straps.',
  })

  assert.equal(result.sent, true)
  const sent = client.calls.find((c) => c.kind === 'invoke').body
  assert.equal(sent.title, CLOSING_NOTICE.DECLINED)
  assert.match(sent.body, /They said: No usable capture of the straps\./)
})

test('nothing here can throw: every dead end reports itself and invokes nothing', async () => {
  // ⚠️ This is the property the whole file exists to keep. The ask is already
  // closed by the time this runs and the seller already has the notice, so a
  // failure here must never surface as a failed close.
  // `reachesTheService` is the one distinction worth drawing: every dead end but
  // the last is discovered *before* the invoke, and the last is the service's own
  // refusal (a missing FCM secret, a bad token), which is a failure this function
  // reports rather than prevents.
  const cases = [
    ['no client', { client: null, requestId: 'r', kind: ASK_ENDING.FULFILLED }, false],
    ['no request id', { client: fakeClient(), kind: ASK_ENDING.FULFILLED }, false],
    [
      'the request is gone',
      { client: fakeClient({ request: null }), requestId: 'r', kind: ASK_ENDING.FULFILLED },
      false,
    ],
    [
      'the request row refused',
      {
        client: fakeClient({ requestError: { message: 'permission denied' } }),
        requestId: 'r',
        kind: ASK_ENDING.FULFILLED,
      },
      false,
    ],
    [
      'the store row refused',
      {
        client: fakeClient({ storeError: { message: 'permission denied' } }),
        requestId: 'r',
        kind: ASK_ENDING.FULFILLED,
      },
      false,
    ],
    [
      'a store with no owner',
      { client: fakeClient({ store: null }), requestId: 'r', kind: ASK_ENDING.FULFILLED },
      false,
    ],
    ['an unknown ending', { client: fakeClient(), requestId: 'r', kind: 'something_new' }, false],
    [
      'the push service refused it',
      {
        client: fakeClient({ invokeError: { message: 'FCM credentials missing' } }),
        requestId: 'r',
        kind: ASK_ENDING.FULFILLED,
      },
      true,
    ],
  ]

  const warnings = []
  const realWarn = console.warn
  console.warn = (line) => warnings.push(line)
  try {
    for (const [label, args, reachesTheService] of cases) {
      const result = await sendAskEndingPush(args)
      assert.equal(result.sent, false, `${label} must not report a push was sent`)
      assert.ok(result.why, `${label} must say why`)
      assert.equal(
        (args.client?.calls ?? []).filter((c) => c.kind === 'invoke').length,
        reachesTheService ? 1 : 0,
        `${label}: unexpected number of calls to the push service`,
      )
    }

    // …and a client that throws outright is the same non-event.
    const exploding = {
      from() {
        throw new Error('the network is gone')
      },
    }
    const result = await sendAskEndingPush({ client: exploding, requestId: 'r', kind: ASK_ENDING.FULFILLED })
    assert.equal(result.sent, false)
    assert.match(result.why, /the network is gone/)
  } finally {
    console.warn = realWarn
  }

  // Every dead end writes one line, and none of them is silent: an admin asking
  // "did the seller's phone buzz?" needs the console to answer.
  assert.equal(warnings.length, cases.length + 1)
  assert.ok(warnings.every((line) => line.startsWith('[askPush] no push for request')))
})
