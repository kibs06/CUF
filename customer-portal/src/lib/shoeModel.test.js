import assert from 'node:assert/strict'
import { test } from 'node:test'

import { MODEL_BUCKET, activeProductModel, modelFileUrl } from './shoeModel.js'

const ROW = {
  id: 7,
  product_id: 'product-1',
  storage_path: 'store-1/product-1/abc.glb',
  sha256: 'a'.repeat(64),
  version: 1,
  status: 'active',
}

test('activeProductModel: only an active row is a row a customer sees', () => {
  // ⚠️ The rule that matters most on this page. A draft is an upload nobody has
  // published — showing it would put an unreviewed mesh on a shop window, and
  // the seller's own form says "not served to customers" about exactly this
  // state.
  assert.equal(activeProductModel([{ ...ROW, status: 'draft' }]), null)
  assert.equal(activeProductModel([{ ...ROW, status: 'rejected' }]), null)
  assert.equal(activeProductModel([]), null)
  assert.equal(activeProductModel(undefined), null)

  assert.equal(activeProductModel([ROW]).id, 7)
  assert.equal(
    activeProductModel([{ ...ROW, id: 1, status: 'draft' }, ROW]).id,
    7,
    'a draft beside a live model is not a coin toss'
  )
})

test('activeProductModel: the higher version wins, whatever the row order', () => {
  const v1 = { ...ROW, id: 1, version: 1 }
  const v2 = { ...ROW, id: 2, version: 2 }

  assert.equal(activeProductModel([v1, v2]).id, 2)
  assert.equal(activeProductModel([v2, v1]).id, 2)
})

test('activeProductModel: a version tie is broken by the newer timestamp', () => {
  const older = { ...ROW, id: 1, version: 3, updated_at: '2026-09-01T00:00:00Z' }
  const newer = { ...ROW, id: 2, version: 3, updated_at: '2026-10-01T00:00:00Z' }

  assert.equal(activeProductModel([older, newer]).id, 2)
  assert.equal(activeProductModel([newer, older]).id, 2)
})

test('activeProductModel: a row with no path is not a model to draw', () => {
  assert.equal(activeProductModel([{ ...ROW, storage_path: '   ' }]), null)
  assert.equal(activeProductModel([{ ...ROW, storage_path: null }]), null)
  // …and it does not hide a sibling that can be drawn.
  assert.equal(
    activeProductModel([{ ...ROW, id: 1, storage_path: '' }, ROW]).id,
    7
  )
})

test('modelFileUrl: the public object URL, from the bucket the app names', () => {
  assert.equal(
    modelFileUrl(ROW.storage_path, 'https://psczvbfoybqhjeqssimw.supabase.co'),
    `https://psczvbfoybqhjeqssimw.supabase.co/storage/v1/object/public/${MODEL_BUCKET}/store-1/product-1/abc.glb`
  )
  // A trailing slash on the project URL must not become a double slash: the
  // path is stored verbatim and both halves have to survive concatenation.
  assert.equal(
    modelFileUrl('a/b.glb', 'https://example.supabase.co/'),
    `https://example.supabase.co/storage/v1/object/public/${MODEL_BUCKET}/a/b.glb`
  )
})

test('modelFileUrl: nothing to fetch is null, never a half-built URL', () => {
  assert.equal(modelFileUrl('', 'https://example.supabase.co'), null)
  assert.equal(modelFileUrl('  ', 'https://example.supabase.co'), null)
  assert.equal(modelFileUrl(null, 'https://example.supabase.co'), null)
  // A build with no project URL configured draws nothing rather than a relative
  // path that 404s into a blank canvas.
  assert.equal(modelFileUrl(ROW.storage_path, ''), null)
  assert.equal(modelFileUrl(ROW.storage_path, undefined), null)
})
