import { test } from 'node:test'
import assert from 'node:assert/strict'

import {
  activityAuditCsv,
  mapActivityRow,
  mapFailedLoginRow,
  mapPaymentAuditRow,
  mapSellerAuditRow,
  mapSessionRow,
  paymentAuditCsv,
  securityAuditCsv,
  sellerAuditCsv,
  sessionAuditCsv,
  shortId,
  toneFor,
} from './audit.js'

// Run with `npm test` (Node's own runner — no framework, no new dependency).

test('seller rows carry actor, applicant and the status transition', () => {
  const row = {
    id: 'a1',
    profile_id: 'p1',
    actor_id: 'admin1',
    action: 'rejected',
    previous_status: 'pending',
    new_status: 'rejected',
    notes: 'Fake ID',
    created_at: '2026-09-04T10:00:00Z',
  }
  const names = {
    admin1: { full_name: 'Rosa Admin', email: 'rosa@cufmai.ph' },
    p1: { full_name: 'Juan Applicant', email: 'juan@example.com' },
  }
  const mapped = mapSellerAuditRow(row, names)
  assert.equal(mapped.actor, 'Rosa Admin')
  assert.equal(mapped.subject, 'Juan Applicant')
  assert.equal(mapped.previousStatus, 'pending')
  assert.equal(mapped.newStatus, 'rejected')
  assert.equal(mapped.notes, 'Fake ID')
})

test('missing names never render blank — the row still reads', () => {
  const mapped = mapSellerAuditRow(
    { id: 'a2', profile_id: 'gone', actor_id: 'gone', action: 'approved', previous_status: 'pending', new_status: 'approved', created_at: '2026-09-04T10:00:00Z' },
    {},
  )
  assert.equal(mapped.actor, 'Unknown account')
  assert.equal(mapped.subject, 'Unknown account')
})

test('tones reuse existing badge variants only', () => {
  assert.equal(toneFor('submitted'), 'pending')
  assert.equal(toneFor('approved'), 'approved')
  assert.equal(toneFor('rejected'), 'rejected')
  assert.equal(toneFor('status_changed'), 'under_review')
  assert.equal(toneFor('confirmed'), 'confirmed')
  assert.equal(toneFor('locked'), 'failed')
})

test('payment rows name the seller and shorten the order', () => {
  const mapped = mapPaymentAuditRow(
    { id: 7, order_id: 'abcdef1234567890', seller_id: 's1', reference_number: 'REF1', amount_shown_to_seller: 1500, decision: 'confirmed', source: 'pos', created_at: '2026-09-05T10:00:00Z' },
    { s1: { full_name: 'Ana Seller', email: 'ana@example.com' } },
  )
  assert.equal(mapped.actor, 'Ana Seller')
  assert.equal(mapped.subject, `Order ${shortId('abcdef1234567890')}`)
  assert.equal(mapped.amount, 1500)
})

test('security rows qualify the location as approximate', () => {
  const mapped = mapFailedLoginRow(
    { id: 'f1', user_id: 'u1', attempt_count: 5, status: 'locked', locked_until: '2026-09-06T10:00:00Z', failed_at: '2026-09-06T09:00:00Z', ip_address: '1.2.3.4', user_agent: 'Android', location: 'Cebu City, Central Visayas, Philippines' },
    { u1: { full_name: 'Juan', email: 'juan@example.com' } },
  )
  assert.match(mapped.place, /approximate/)
  assert.match(mapped.place, /Cebu City/)
  assert.equal(mapped.subject, '5 attempts')
})

test('session rows name the seller and the reporting client', () => {
  const mapped = mapSessionRow(
    { id: 's1', user_id: 'u9', event: 'sign_in', role: 'seller', source: 'app', user_agent: 'Pixel 4', created_at: '2026-10-15T08:00:00Z' },
    { u9: { full_name: 'Ana Seller', email: 'ana@example.com' } },
  )
  assert.equal(mapped.actor, 'Ana Seller')
  assert.equal(mapped.action, 'sign_in')
  assert.equal(mapped.subject, 'app')
  assert.equal(mapped.role, 'seller')
  assert.equal(mapped.device, 'Pixel 4')
})

test('session rows survive a deleted account', () => {
  const mapped = mapSessionRow(
    { id: 's2', user_id: 'gone', event: 'sign_out', role: 'seller', source: 'customer-portal', created_at: '2026-10-15T09:00:00Z' },
    {},
  )
  assert.equal(mapped.actor, 'Unknown account')
})

test('activity rows name products and shorten orders', () => {
  const names = { a1: { full_name: 'Ana Seller', email: 'ana@example.com' } }
  const product = mapActivityRow(
    { id: 'x1', actor_id: 'a1', action: 'product_created', entity: 'product', entity_id: 'p1', store_id: 'st1', detail: 'Carcar Sandals', created_at: '2026-10-15T08:00:00Z' },
    names,
  )
  assert.equal(product.actor, 'Ana Seller')
  assert.equal(product.subject, 'Carcar Sandals')

  const order = mapActivityRow(
    { id: 'x2', actor_id: 'a1', action: 'order_status_changed', entity: 'order', entity_id: 'abcdef1234567890', detail: 'placed → preparing', previous_status: 'placed', new_status: 'preparing', created_at: '2026-10-15T08:05:00Z' },
    names,
  )
  assert.equal(order.subject, `Order ${shortId('abcdef1234567890')}`)
  assert.equal(order.previousStatus, 'placed')
  assert.equal(order.newStatus, 'preparing')
})

test('new actions reuse existing badge tones', () => {
  assert.equal(toneFor('sign_in'), 'active')
  assert.equal(toneFor('sign_out'), 'expired')
  assert.equal(toneFor('product_created'), 'confirmed')
  assert.equal(toneFor('product_updated'), 'under_review')
  assert.equal(toneFor('product_removed'), 'cancelled')
  assert.equal(toneFor('store_created'), 'confirmed')
  assert.equal(toneFor('store_updated'), 'under_review')
  // Order transitions borrow the destination status tone.
  assert.equal(toneFor('order_status_changed', { newStatus: 'preparing' }), 'preparing')
  assert.equal(toneFor('order_status_changed', { newStatus: 'cancelled' }), 'cancelled')
})

test('session and activity CSV exporters keep the BOM contract', () => {
  const sessions = sessionAuditCsv([
    { at: '2026-10-15', action: 'sign_in', actor: 'Ana', actorEmail: 'ana@example.com', role: 'seller', subject: 'app', device: 'Pixel 4' },
  ])
  assert.ok(sessions.startsWith('\uFEFF'))
  assert.match(sessions, /Account,Email,Role,Source,Device/)

  const activity = activityAuditCsv([
    { at: '2026-10-15', action: 'product_created', actor: 'Ana', actorEmail: '', entity: 'product', detail: 'Carcar, Sandals', previousStatus: '—', newStatus: '—' },
  ])
  assert.ok(activity.startsWith('\uFEFF'))
  assert.match(activity, /"Carcar, Sandals"/)
})

test('CSV exporters quote commas and keep the BOM', () => {
  const csv = sellerAuditCsv([
    { at: '2026-09-04', action: 'rejected', actor: 'Rosa', actorEmail: '', subject: 'Juan', subjectEmail: '', previousStatus: 'pending', newStatus: 'rejected', notes: 'Bad "ID", retry' },
  ])
  assert.ok(csv.startsWith('\uFEFF'))
  assert.match(csv, /"Bad ""ID"", retry"/)
  assert.equal(paymentAuditCsv([]).split('\n').length, 1)
  assert.equal(securityAuditCsv([]).split('\n').length, 1)
})
