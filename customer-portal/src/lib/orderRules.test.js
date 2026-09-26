import assert from 'node:assert/strict'
import { describe, it } from 'node:test'

import {
  CANCEL_WINDOW_HOURS,
  CANCELLATION_REASONS,
  ORDER_FILTERS,
  ORDER_PROGRESS_STEPS,
  availableOrderFilters,
  cancelError,
  cancelPlan,
  filterOrders,
  fulfilmentLabel,
  isOpenOrder,
  isUnpaidOrder,
  orderLines,
  orderPieces,
  orderTimeline,
  orderTotals,
  preparingAt,
  progressIndex,
  shippingAddressLines,
  shortOrderRef,
  sortOrders,
  statusLabel,
  statusMeta,
  statusTone,
} from './orderRules.js'

/**
 * An order as `mapOrder` produces it, carrying only the fields read here.
 *
 * The two fixtures below are the real shapes, read from the deployed database
 * on 2026-09-25: an order cancelled before payment (which has NO `order_items`,
 * because the webhook never ran) and a paid one (which does).
 */
const order = (overrides = {}) => ({
  id: 'f91a8201-a633-4b24-84d1-ca63a54f8d03',
  status: 'pending',
  payment_status: 'paid',
  fulfillment: 'pickup',
  total_amount: 400,
  created_at: '2026-09-25T11:13:05.177353+00:00',
  items_snapshot: [
    {
      size: 'US 8',
      quantity: 1,
      product_id: 'fd44ad66-6c33-4540-9666-7960d47f4cdf',
      unit_price: 300,
      product_name: 'JBC Crown Leather Sandals',
    },
  ],
  order_items: [],
  order_status_history: [],
  ...overrides,
})

describe('statusMeta', () => {
  it('uses the app’s own labels for every status it knows', () => {
    // Copied from MyOrdersScreen._getStatusData so the two clients cannot
    // describe one database value two ways.
    assert.equal(statusLabel('pending'), 'Pending')
    assert.equal(statusLabel('preparing'), 'Processing')
    assert.equal(statusLabel('ready'), 'Ready')
    assert.equal(statusLabel('cancelled'), 'Cancelled')
  })

  it('maps the legacy aliases onto their modern names', () => {
    // 'placed' and 'received' exist on rows older than the current CHECK.
    assert.equal(statusLabel('placed'), 'Pending')
    assert.equal(statusLabel('received'), 'Delivered')
    assert.equal(statusLabel('delivered'), 'Delivered')
  })

  it('has a label for the PayMongo statuses', () => {
    assert.equal(statusLabel('awaiting_payment'), 'Awaiting payment')
    assert.equal(statusLabel('payment_conflict'), 'Needs review')
  })

  it('shows an unknown status rather than hiding the order', () => {
    // The CHECK constraint has grown four times. An order that vanishes from
    // the list is worse than one with a label this file has not heard of.
    const meta = statusMeta('being_polished')
    assert.equal(meta.label, 'Being polished')
    assert.equal(meta.tone, 'muted')
    assert.equal(statusMeta('').status, '')
  })

  it('gives every status a tone from the site palette', () => {
    const tones = new Set()
    for (const status of [
      'pending',
      'placed',
      'preparing',
      'ready',
      'delivered',
      'received',
      'cancelled',
      'cancellation_requested',
      'awaiting_payment',
      'awaiting_payment_confirmation',
      'payment_conflict',
    ]) {
      tones.add(statusTone(status))
    }
    for (const tone of tones) {
      assert.ok(
        ['amber', 'clay', 'olive', 'crimson', 'muted'].includes(tone),
        `unexpected tone ${tone}`,
      )
    }
  })
})

describe('progressIndex', () => {
  it('matches the app’s step mapping', () => {
    assert.equal(progressIndex('pending'), 0)
    assert.equal(progressIndex('placed'), 0)
    assert.equal(progressIndex('preparing'), 1)
    assert.equal(progressIndex('ready'), 2)
    assert.equal(progressIndex('delivered'), 3)
    assert.equal(progressIndex('received'), 3)
  })

  it('is -1 when the progress line does not apply', () => {
    // The app hides the stepper for these rather than showing a wrong position.
    assert.equal(progressIndex('cancelled'), -1)
    assert.equal(progressIndex('cancellation_requested'), -1)
    assert.equal(progressIndex('awaiting_payment'), -1)
  })

  it('has four steps', () => {
    assert.equal(ORDER_PROGRESS_STEPS.length, 4)
  })
})

describe('isOpenOrder / isUnpaidOrder', () => {
  it('treats delivered and cancelled as finished', () => {
    assert.equal(isOpenOrder('delivered'), false)
    assert.equal(isOpenOrder('received'), false)
    assert.equal(isOpenOrder('cancelled'), false)
    assert.equal(isOpenOrder('preparing'), true)
    assert.equal(isOpenOrder('ready'), true)
  })

  it('flags both unpaid shapes, including the gateway-free legacy one', () => {
    assert.equal(isUnpaidOrder('awaiting_payment'), true)
    assert.equal(isUnpaidOrder('awaiting_payment_confirmation'), true)
    assert.equal(isUnpaidOrder('pending'), false)
  })
})

describe('cancelPlan', () => {
  const now = new Date('2026-09-25T12:00:00.000Z')

  it('cancels a pending order outright', () => {
    const plan = cancelPlan(order({ status: 'pending' }), { now })
    assert.equal(plan.allowed, true)
    assert.equal(plan.kind, 'cancel')
    assert.equal(plan.reason, null)
  })

  it('cancels the legacy placed alias outright too', () => {
    assert.equal(cancelPlan(order({ status: 'placed' }), { now }).kind, 'cancel')
  })

  it('makes a processing order a request, not an outright cancel', () => {
    const plan = cancelPlan(
      order({
        status: 'preparing',
        order_status_history: [
          { id: 1, status: 'preparing', changed_at: '2026-09-25T11:31:00.000Z' },
        ],
      }),
      { now },
    )
    assert.equal(plan.allowed, true)
    assert.equal(plan.kind, 'request')
    // 11:31 + 2h — the window closes at 13:31.
    assert.equal(plan.closesAt.toISOString(), '2026-09-25T13:31:00.000Z')
  })

  it('closes the window at the deadline itself, not after it', () => {
    const at = (changedAt) =>
      cancelPlan(
        order({
          status: 'preparing',
          order_status_history: [
            { id: 1, status: 'preparing', changed_at: changedAt },
          ],
        }),
        { now },
      )

    assert.equal(at('2026-09-25T10:00:00.000Z').allowed, true) // exactly 2h
    assert.equal(at('2026-09-25T09:59:59.000Z').allowed, false)
    assert.match(at('2026-09-25T09:59:59.000Z').reason, /2-hour cancellation window/)
  })

  it('lets an unageable order through', () => {
    // No 'preparing' history row means the order predates the history trigger.
    // Unknown age is allowed because this transition is a request, not a
    // unilateral cancel — the maker still decides.
    const plan = cancelPlan(
      order({ status: 'preparing', order_status_history: [] }),
      { now },
    )
    assert.equal(plan.allowed, true)
    assert.equal(plan.kind, 'request')
    assert.equal(plan.closesAt, null)
  })

  it('refuses the statuses that cannot be cancelled, each in its own words', () => {
    const refusals = {
      ready: /bagged and waiting/,
      delivered: /has been delivered/,
      received: /has been delivered/,
      cancelled: /already cancelled/,
      cancellation_requested: /already asked to cancel/,
      awaiting_payment: /payment screen/,
      awaiting_payment_confirmation: /payment screen/,
      payment_conflict: /contact the store/,
    }

    for (const [status, pattern] of Object.entries(refusals)) {
      const plan = cancelPlan(order({ status }), { now })
      assert.equal(plan.allowed, false, `${status} should not be cancellable`)
      assert.equal(plan.kind, null)
      assert.match(plan.reason, pattern, `wrong message for ${status}`)
    }
  })

  it('never leaves a refusal without an explanation', () => {
    for (const status of ['ready', 'cancelled', 'whatever_next']) {
      const plan = cancelPlan(order({ status }), { now })
      assert.equal(plan.allowed, false)
      assert.ok(plan.reason && plan.reason.length > 0)
    }
  })
})

describe('preparingAt', () => {
  it('is null without history', () => {
    assert.equal(preparingAt(order()), null)
    assert.equal(preparingAt({ order_status_history: null }), null)
    assert.equal(preparingAt(null), null)
  })

  it('takes the latest preparing row, not the first', () => {
    // A seller can send an order back through preparing after a correction, and
    // the window should restart with the work.
    const at = preparingAt(
      order({
        order_status_history: [
          { id: 1, status: 'preparing', changed_at: '2026-09-20T10:00:00.000Z' },
          { id: 2, status: 'ready', changed_at: '2026-09-21T10:00:00.000Z' },
          { id: 3, status: 'preparing', changed_at: '2026-09-25T11:00:00.000Z' },
        ],
      }),
    )
    assert.equal(at.toISOString(), '2026-09-25T11:00:00.000Z')
  })

  it('ignores an unparseable timestamp instead of returning Invalid Date', () => {
    assert.equal(
      preparingAt(
        order({
          order_status_history: [
            { id: 1, status: 'preparing', changed_at: 'garbage' },
          ],
        }),
      ),
      null,
    )
  })
})

describe('orderLines', () => {
  it('falls back to the snapshot when order_items has not been written yet', () => {
    // defer-until-paid: the webhook inserts the line rows only after the money
    // moves, so a cancelled or still-pending order legitimately has none.
    const lines = orderLines(order())
    assert.equal(lines.length, 1)
    assert.equal(lines[0].name, 'JBC Crown Leather Sandals')
    assert.equal(lines[0].unitPrice, 300)
    assert.equal(lines[0].lineTotal, 300)
  })

  it('prefers the real rows once they exist', () => {
    const lines = orderLines(
      order({
        order_items: [
          {
            id: 'item-1',
            product_id: 'p1',
            size: 'EU 40',
            quantity: 2,
            unit_price: 799,
            products: {
              name: 'Cebuano Dress Brogue',
              product_images: [{ image_url: 'brogue.jpg', display_order: 0 }],
            },
          },
        ],
      }),
    )

    assert.equal(lines.length, 1)
    assert.equal(lines[0].name, 'Cebuano Dress Brogue')
    assert.equal(lines[0].imageUrl, 'brogue.jpg')
    assert.equal(lines[0].lineTotal, 1598)
  })

  it('picks the primary image, then the lowest display order', () => {
    const [line] = orderLines(
      order({
        order_items: [
          {
            id: 'i',
            quantity: 1,
            unit_price: 1,
            products: {
              name: 'X',
              product_images: [
                { image_url: 'second.jpg', display_order: 1, is_primary: false },
                { image_url: 'primary.jpg', display_order: 9, is_primary: true },
              ],
            },
          },
        ],
      }),
    )
    assert.equal(line.imageUrl, 'primary.jpg')
  })

  it('gives the card a name even when the product row is gone', () => {
    const [line] = orderLines(
      order({ order_items: [{ id: 'i', quantity: 1, unit_price: 5 }] }),
    )
    assert.equal(line.name, 'Product')
    assert.equal(line.imageUrl, null)
  })

  it('is empty rather than throwing for a malformed order', () => {
    assert.deepEqual(orderLines(null), [])
    assert.deepEqual(orderLines({}), [])
  })
})

describe('orderTotals', () => {
  it('reads the server’s total and derives delivery as the difference', () => {
    // ₱300 of goods + the fixed ₱100 = the ₱400 the server recorded. Deriving
    // it (rather than printing the ₱100 constant) is what keeps a legacy or
    // vouchered order's breakdown adding up to its own total.
    const totals = orderTotals(order())
    assert.deepEqual(totals, { subtotal: 300, deliveryFee: 100, total: 400 })
  })

  it('never reports a negative delivery fee', () => {
    const totals = orderTotals(
      order({ total_amount: 100, items_snapshot: [{ unit_price: 300, quantity: 1 }] }),
    )
    assert.equal(totals.subtotal, 300)
    assert.equal(totals.deliveryFee, 0)
    assert.equal(totals.total, 100)
  })

  it('handles an order whose lines are unavailable entirely', () => {
    const totals = orderTotals({ total_amount: 250 })
    assert.deepEqual(totals, { subtotal: 0, deliveryFee: 250, total: 250 })
  })
})

describe('orderPieces', () => {
  it('counts pieces across lines, not lines', () => {
    assert.equal(
      orderPieces(
        order({
          items_snapshot: [
            { unit_price: 300, quantity: 2 },
            { unit_price: 100, quantity: 1 },
          ],
        }),
      ),
      3,
    )
  })
})

describe('shippingAddressLines', () => {
  it('reads the snake_case snapshot the app writes', () => {
    // Real shape, read from the deployed database.
    const lines = shippingAddressLines({
      label: 'Home',
      region: 'Region VII (Central Visayas)',
      barangay: 'Poblacion I',
      province: 'Cebu',
      recipient_name: 'Portal Verify',
      street_address: '12 Osmena St.',
      recipient_phone: '09171234567',
      city_municipality: 'Carcar City',
    })

    assert.deepEqual(lines, [
      'Portal Verify',
      '09171234567',
      '12 Osmena St.',
      'Poblacion I',
      'Carcar City',
      'Cebu',
      'Region VII (Central Visayas)',
    ])
  })

  it('labels a landmark so it does not read as a street', () => {
    const lines = shippingAddressLines({
      street_address: '12 Osmena St.',
      landmark: 'Blue gate beside the bakery',
    })
    assert.deepEqual(lines, [
      '12 Osmena St.',
      'Landmark: Blue gate beside the bakery',
    ])
  })

  it('is empty for a pickup order with no address at all', () => {
    assert.deepEqual(shippingAddressLines(null), [])
    assert.deepEqual(shippingAddressLines({}), [])
    assert.deepEqual(shippingAddressLines('an address'), [])
  })
})

describe('fulfilmentLabel', () => {
  it('defaults to pickup, the only fulfilment the schema’s default allows', () => {
    assert.equal(fulfilmentLabel(order()), 'Pickup')
    assert.equal(fulfilmentLabel(order({ fulfillment: 'delivery' })), 'Delivery')
    assert.equal(fulfilmentLabel(null), 'Pickup')
  })
})

describe('orderTimeline', () => {
  it('adds the creation moment when history does not already start there', () => {
    // order_status_history only begins when the trigger shipped (2026-07-18),
    // and orders older than that were backfilled with a single row.
    const timeline = orderTimeline(
      order({
        created_at: '2026-09-25T11:13:05.000Z',
        order_status_history: [
          {
            id: 7,
            status: 'preparing',
            changed_at: '2026-09-25T12:00:00.000Z',
          },
        ],
      }),
    )

    assert.equal(timeline.length, 2)
    assert.equal(timeline[0].label, 'Order placed')
    assert.equal(timeline[0].source, 'created')
    assert.equal(timeline[1].label, 'Processing')
  })

  it('does not duplicate a history row that already records creation', () => {
    const timeline = orderTimeline(
      order({
        created_at: '2026-09-25T11:13:05.000Z',
        order_status_history: [
          { id: 1, status: 'pending', changed_at: '2026-09-25T11:13:05.000Z' },
        ],
      }),
    )
    assert.equal(timeline.length, 1)
    assert.equal(timeline[0].source, 'history')
  })

  it('keeps creation when the first transition is NOT creation', () => {
    // Measured on a live order: created 11:13:05, cancelled 11:13:11. Deduping
    // on the timestamp alone (both are seconds apart) dropped 'Order placed'
    // and left a one-entry timeline that never said the order was placed.
    const timeline = orderTimeline(
      order({
        created_at: '2026-09-25T11:13:05.177353+00:00',
        order_status_history: [
          {
            id: 120,
            status: 'cancelled',
            changed_at: '2026-09-25T11:13:11.403536+00:00',
          },
        ],
      }),
    )

    assert.deepEqual(
      timeline.map((entry) => entry.label),
      ['Order placed', 'Cancelled'],
    )
  })

  it('sorts oldest first, so the story reads downwards', () => {
    const timeline = orderTimeline(
      order({
        created_at: '2026-09-25T11:13:05.000Z',
        order_status_history: [
          { id: 3, status: 'received', changed_at: '2026-09-27T09:00:00.000Z' },
          { id: 1, status: 'preparing', changed_at: '2026-09-25T12:00:00.000Z' },
          { id: 2, status: 'ready', changed_at: '2026-09-26T09:00:00.000Z' },
        ],
      }),
    )

    assert.deepEqual(
      timeline.map((entry) => entry.label),
      ['Order placed', 'Processing', 'Ready', 'Delivered'],
    )
  })

  it('stands on created_at alone when there is no history at all', () => {
    // The insert trigger only records an UPDATE, so a brand-new order has no
    // history rows at all and creation is the only thing that can be said.
    const timeline = orderTimeline(order({ order_status_history: [] }))
    assert.equal(timeline.length, 1)
    assert.equal(timeline[0].status, 'placed')
    assert.equal(timeline[0].at.toISOString(), '2026-09-25T11:13:05.177Z')
  })

  it('is empty for an order with no dates it can trust', () => {
    assert.deepEqual(orderTimeline({}), [])
    assert.deepEqual(orderTimeline(null), [])
  })
})

describe('order filters', () => {
  const list = [
    order({ id: 'a', status: 'awaiting_payment' }),
    order({ id: 'b', status: 'pending' }),
    order({ id: 'c', status: 'ready' }),
    order({ id: 'd', status: 'cancelled' }),
    order({ id: 'e', status: 'delivered' }),
  ]

  it('groups them the way the app’s tabs do', () => {
    const ids = (filter) =>
      filterOrders(list, filter).map((entry) => entry.id)

    assert.deepEqual(ids('all'), ['a', 'b', 'c', 'd', 'e'])
    assert.deepEqual(ids('unpaid'), ['a'])
    assert.deepEqual(ids('processing'), ['b'])
    assert.deepEqual(ids('ready'), ['c'])
    assert.deepEqual(ids('completed'), ['d', 'e'])
  })

  it('falls back to the full list for an unknown filter', () => {
    assert.equal(filterOrders(list, 'nonsense').length, list.length)
    assert.equal(filterOrders(list).length, list.length)
  })

  it('hides tabs with nothing behind them', () => {
    const filters = availableOrderFilters([order({ status: 'pending' })])
    assert.deepEqual(
      filters.map((filter) => filter.id),
      ['all', 'processing'],
    )
  })

  it('always keeps the list’s own name', () => {
    assert.deepEqual(
      availableOrderFilters([]).map((filter) => filter.id),
      ['all'],
    )
    assert.equal(ORDER_FILTERS[0].id, 'all')
  })

  it('never returns null for a missing list', () => {
    for (const filter of ORDER_FILTERS) {
      assert.deepEqual(filterOrders(null, filter.id), [])
    }
  })
})

describe('sortOrders', () => {
  it('puts the newest order first and does not mutate the input', () => {
    const input = [
      order({ id: 'old', created_at: '2026-09-20T10:00:00.000Z' }),
      order({ id: 'new', created_at: '2026-09-25T10:00:00.000Z' }),
    ]
    const sorted = sortOrders(input)
    assert.deepEqual(
      sorted.map((entry) => entry.id),
      ['new', 'old'],
    )
    assert.equal(input[0].id, 'old')
  })

  it('survives a missing timestamp', () => {
    const sorted = sortOrders([
      order({ id: 'a', created_at: null }),
      order({ id: 'b', created_at: '2026-09-25T10:00:00.000Z' }),
    ])
    assert.equal(sorted[0].id, 'b')
  })
})

describe('shortOrderRef', () => {
  it('prints the same reference the payment pages do', () => {
    // Consistency here is the whole point: one order, one reference, whichever
    // page the customer is reading.
    assert.equal(shortOrderRef('f91a8201-a633-4b24-84d1-ca63a54f8d03'), '#f91a8201')
  })

  it('has a placeholder for a missing id', () => {
    assert.equal(shortOrderRef(null), '—')
    assert.equal(shortOrderRef(''), '—')
  })
})

describe('cancelError', () => {
  it('shows the server’s own sentence for a refusal', () => {
    // "The maker has already started this order and the 2-hour cancellation
    // window has closed." is written for a customer; a generic apology would
    // throw away the only useful thing in the response.
    const mapped = cancelError({
      code: 'P0001',
      message:
        'The maker has already started this order and the 2-hour cancellation window has closed. Message the store to arrange a return.',
    })
    assert.match(mapped.message, /2-hour cancellation window/)
    assert.equal(mapped.notAvailable, false)
  })

  it('recognises the migration not being applied yet', () => {
    // PostgREST answers 404/PGRST202 when the function does not exist. Telling
    // somebody "please try again" when trying again can never work is the worst
    // available answer, so this gets its own message and its own flag.
    const mapped = cancelError({
      code: 'PGRST202',
      message:
        'Could not find the function public.cancel_my_order(p_order_id, p_reason, p_details) in the schema cache',
    })
    assert.equal(mapped.notAvailable, true)
    assert.match(mapped.message, /not switched on yet/)
    assert.match(mapped.message, /CUFMAI app/)
  })

  it('does not print Postgres at a customer for a closed route', () => {
    const mapped = cancelError({
      code: '42501',
      message: 'permission denied for function cancel_my_order',
    })
    assert.match(mapped.message, /not allowed to cancel/)
    assert.ok(!/permission denied/.test(mapped.message))
  })

  it('passes our own ’Order not found’ through', () => {
    assert.equal(cancelError({ code: '42501', message: 'Order not found' }).message, 'Order not found')
  })

  it('falls back for anything unrecognisable', () => {
    assert.equal(
      cancelError({}, 'We could not cancel this order.').message,
      'We could not cancel this order.',
    )
    assert.match(cancelError(null).message, /try again/)
  })
})

describe('CANCELLATION_REASONS', () => {
  it('is the app’s list, ending in Other', () => {
    // Ported from AppConstants.cancellationReasons. A reason that exists in one
    // client and not the other splits one report field into two vocabularies.
    assert.equal(CANCELLATION_REASONS.length, 9)
    assert.equal(CANCELLATION_REASONS[0], 'Changed my mind')
    assert.equal(CANCELLATION_REASONS.at(-1), 'Other')
  })

  it('agrees with the server’s two-hour window', () => {
    assert.equal(CANCEL_WINDOW_HOURS, 2)
  })
})
