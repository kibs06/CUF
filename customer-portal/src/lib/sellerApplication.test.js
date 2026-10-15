import assert from 'node:assert/strict'
import { describe, it } from 'node:test'

import {
  GOV_ID_TYPES,
  REQUIRED_PRODUCT_PHOTOS,
  validateAccountStep,
  validateBusinessStep,
  validateCommunityStep,
  validateDocFile,
  validateIdentityStep,
  validateStorefrontStep,
} from './sellerApplicationRules.js'

function yearsAgo(years) {
  const now = new Date()
  const date = new Date(now.getFullYear() - years, now.getMonth(), now.getDate())
  const month = String(date.getMonth() + 1).padStart(2, '0')
  const day = String(date.getDate()).padStart(2, '0')
  return `${date.getFullYear()}-${month}-${day}`
}

function file(name = 'id.jpg', type = 'image/jpeg', size = 1024) {
  return { name, type, size }
}

const goodAccount = {
  fullName: 'Juan dela Cruz',
  email: 'juan@example.com',
  phone: '09171234567',
  birthday: yearsAgo(20),
  gender: 'Man',
  genderText: '',
  password: 'supersecret',
  confirm: 'supersecret',
  termsAccepted: true,
}

describe('GOV_ID_TYPES', () => {
  it('covers the twelve Philippine IDs the app accepts', () => {
    assert.equal(GOV_ID_TYPES.length, 12)
    const values = GOV_ID_TYPES.map((entry) => entry.value)
    for (const expected of ['philid', 'passport', 'drivers_license', 'tin', 'nbi']) {
      assert.ok(values.includes(expected), `missing ${expected}`)
    }
  })
})

describe('validateAccountStep', () => {
  it('accepts a complete account', () => {
    assert.deepEqual(validateAccountStep(goodAccount), {})
  })

  it('requires every field the app requires', () => {
    const errors = validateAccountStep({
      ...goodAccount,
      fullName: '',
      email: 'not-an-email',
      phone: '',
      password: 'short',
      confirm: 'different',
      termsAccepted: false,
    })
    assert.ok(errors.fullName)
    assert.ok(errors.email)
    assert.ok(errors.phone)
    assert.ok(errors.password)
    assert.ok(errors.confirm)
    assert.ok(errors.terms)
  })

  it('enforces the 13-year age gate', () => {
    const errors = validateAccountStep({ ...goodAccount, birthday: yearsAgo(10) })
    assert.ok(errors.birthday)
  })
})

describe('validateIdentityStep', () => {
  it('requires an ID type and both photos', () => {
    const errors = validateIdentityStep({ idType: null, idFile: null, selfieFile: null })
    assert.ok(errors.idType)
    assert.ok(errors.idFile)
    assert.ok(errors.selfieFile)
  })

  it('accepts a complete identity step', () => {
    assert.deepEqual(
      validateIdentityStep({ idType: 'philid', idFile: file(), selfieFile: file('me.png', 'image/png') }),
      {},
    )
  })
})

describe('validateCommunityStep', () => {
  it('asks a member for their member ID', () => {
    assert.ok(validateCommunityStep({ isMember: true, memberId: '', storeLocation: 'Carcar' }).memberId)
    assert.deepEqual(
      validateCommunityStep({ isMember: true, memberId: 'CUF-123', storeLocation: 'Carcar' }),
      {},
    )
  })

  it('asks a non-member for a barangay proof instead', () => {
    const errors = validateCommunityStep({ isMember: false, barangayFile: null, storeLocation: 'Carcar' })
    assert.ok(errors.barangayFile)
    assert.ok(!errors.memberId)
  })

  it('always requires the store location', () => {
    assert.ok(validateCommunityStep({ isMember: true, memberId: 'CUF-123', storeLocation: '' }).storeLocation)
  })
})

describe('validateBusinessStep', () => {
  it('requires all three business documents', () => {
    const errors = validateBusinessStep({ dtiFile: null, birFile: null, permitFile: null })
    assert.ok(errors.dtiFile)
    assert.ok(errors.birFile)
    assert.ok(errors.permitFile)
  })
})

describe('validateStorefrontStep', () => {
  it('requires name, description, a tag, a storefront photo and five product photos', () => {
    const errors = validateStorefrontStep({
      storeName: '',
      storeDescription: '',
      tagCount: 0,
      storefrontFile: null,
      productFiles: [file()],
    })
    assert.ok(errors.storeName)
    assert.ok(errors.storeDescription)
    assert.ok(errors.tags)
    assert.ok(errors.storefrontFile)
    assert.ok(errors.productFiles, `needs ${REQUIRED_PRODUCT_PHOTOS} product photos`)
  })

  it('accepts a complete storefront', () => {
    assert.deepEqual(
      validateStorefrontStep({
        storeName: 'Shoe Story',
        storeDescription: 'Handmade leather sandals',
        tagCount: 2,
        storefrontFile: file(),
        productFiles: [file(), file(), file(), file(), file()],
      }),
      {},
    )
  })
})

describe('validateDocFile', () => {
  it('refuses non-photos and oversized files', () => {
    assert.ok(validateDocFile(file('doc.pdf', 'application/pdf')))
    assert.ok(validateDocFile(file('big.jpg', 'image/jpeg', 11 * 1024 * 1024)))
    assert.equal(validateDocFile(file()), null)
  })
})
