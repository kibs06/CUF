import assert from 'node:assert/strict'
import { describe, it } from 'node:test'

import {
  AVATAR_BUCKET,
  AVATAR_MAX_BYTES,
  avatarFileError,
  avatarStoragePath,
  birthdayError,
  emptyProfileDraft,
  genderDraftFrom,
  isProfileComplete,
  parseDateInput,
  profileDraftFromRow,
  profileError,
  profileErrors,
  profileIsDirty,
  profilePhoneError,
  profileUpdatePayload,
  sameProfilePayload,
  withAvatarCacheBust,
} from './profileRules.js'
import { validateBirthday } from './signupRules.js'

/** A `profiles` row as PostgREST returns it, with the fields read here. */
const row = (overrides = {}) => ({
  id: '061eae13-4309-44bd-81c5-96dfcd23c46a',
  full_name: 'Ana Reyes',
  email: 'ana@example.com',
  phone: '0917 123 4567',
  birthday: '1998-04-17',
  gender: 'Woman',
  bio: null,
  avatar_url: null,
  role: 'customer',
  seller_status: 'none',
  ...overrides,
})

const draft = (overrides = {}) => ({
  ...profileDraftFromRow(row()),
  ...overrides,
})

describe('genderDraftFrom', () => {
  it('maps a preset option straight back', () => {
    assert.deepEqual(genderDraftFrom('Woman'), {
      option: 'Woman',
      selfDescribe: '',
    })
    assert.deepEqual(genderDraftFrom('Prefer not to say'), {
      option: 'Prefer not to say',
      selfDescribe: '',
    })
  })

  it('recognises a self-described value as free text, not as an option', () => {
    // Sign-up persists the free text ITSELF into profiles.gender, so anything
    // that is not one of the four options is a self-description. Getting this
    // wrong rewrites somebody's gender the moment they edit their name.
    assert.deepEqual(genderDraftFrom('Nonbinary, they/them'), {
      option: 'Self-describe',
      selfDescribe: 'Nonbinary, they/them',
    })
  })

  it('is blank for null, empty and whitespace', () => {
    for (const value of [null, undefined, '', '   ']) {
      assert.deepEqual(genderDraftFrom(value), { option: '', selfDescribe: '' })
    }
  })
})

describe('profileDraftFromRow', () => {
  it('reads every editable field off the row', () => {
    assert.deepEqual(profileDraftFromRow(row()), {
      fullName: 'Ana Reyes',
      phone: '0917 123 4567',
      birthday: '1998-04-17',
      genderOption: 'Woman',
      genderSelfDescribe: '',
      bio: '',
    })
  })

  it('trims a timestamp-shaped DATE to the input’s own format', () => {
    assert.equal(
      profileDraftFromRow(row({ birthday: '1998-04-17T00:00:00+00:00' })).birthday,
      '1998-04-17',
    )
  })

  it('is an empty draft for a missing row rather than throwing', () => {
    assert.deepEqual(profileDraftFromRow(null), emptyProfileDraft())
    assert.deepEqual(profileDraftFromRow({}), emptyProfileDraft())
  })

  it('survives a birthday it cannot parse without inventing one', () => {
    assert.equal(profileDraftFromRow(row({ birthday: 'not a date' })).birthday, '')
  })
})

describe('parseDateInput', () => {
  it('parses a local date at midnight', () => {
    const date = parseDateInput('1998-04-17')
    assert.equal(date.getFullYear(), 1998)
    assert.equal(date.getMonth(), 3)
    assert.equal(date.getDate(), 17)
  })

  it('rejects a day that does not exist rather than rolling it over', () => {
    // `new Date(2026, 1, 31)` silently becomes 3 March.
    assert.equal(parseDateInput('2026-02-31'), null)
    assert.equal(parseDateInput('2026-13-01'), null)
  })

  it('rejects anything that is not a full date', () => {
    for (const value of [null, '', '17/04/1998', '1998-04']) {
      assert.equal(parseDateInput(value), null)
    }
  })
})

describe('birthdayError', () => {
  it('requires a birthday', () => {
    assert.match(birthdayError(''), /select your birthday/)
    assert.match(birthdayError(null), /select your birthday/)
  })

  it('rejects a malformed date', () => {
    assert.match(birthdayError('2026-02-31'), /valid birthday/)
  })

  it('rejects the future', () => {
    const future = new Date(Date.now() + 3 * 24 * 60 * 60 * 1000)
    const value = `${future.getFullYear()}-${String(future.getMonth() + 1).padStart(2, '0')}-${String(future.getDate()).padStart(2, '0')}`
    assert.match(birthdayError(value), /future/)
  })

  it('accepts a plausible adult birthday', () => {
    assert.equal(birthdayError('1998-04-17'), null)
  })

  it('uses the account’s wording, not sign-up’s', () => {
    // The threshold is shared; the sentence is not — "to sign up" is wrong for
    // somebody who signed up years ago and is fixing a typo in their year.
    const tooYoung = `${new Date().getFullYear() - 4}-01-01`
    assert.match(birthdayError(tooYoung), /A CUFMAI account needs a birthday/)
    assert.ok(!/sign up/.test(birthdayError(tooYoung)))
  })

  it('agrees with the sign-up rule on every boundary that matters', () => {
    // Two different sentences, ONE accept/reject decision. This is the test
    // that stops the two drifting into disagreeing about a 13-year-old.
    const thisYear = new Date().getFullYear()
    const cases = [
      '',
      null,
      '2026-02-31',
      `${thisYear}-01-01`,
      `${thisYear - 12}-06-15`,
      `${thisYear - 13}-01-01`,
      `${thisYear - 13}-12-31`,
      `${thisYear - 40}-07-04`,
    ]

    for (const value of cases) {
      const ours = birthdayError(value) === null
      const signup = validateBirthday(parseDateInput(value)) === null
      assert.equal(ours, signup, `disagreement on ${String(value)}`)
    }
  })
})

describe('profilePhoneError', () => {
  it('accepts an empty phone — the field is optional', () => {
    assert.equal(profilePhoneError(''), null)
    assert.equal(profilePhoneError(null), null)
    assert.equal(profilePhoneError('   '), null)
  })

  it('accepts the forms people actually type', () => {
    assert.equal(profilePhoneError('0917 123 4567'), null)
    assert.equal(profilePhoneError('+63 917 123 4567'), null)
    assert.equal(profilePhoneError('0917-123-4567'), null)
  })

  it('rejects an incomplete one, using the checkout’s own rule', () => {
    assert.match(profilePhoneError('0917'), /complete mobile number/)
  })
})

describe('profileErrors', () => {
  it('passes a complete draft', () => {
    assert.deepEqual(profileErrors(draft()), {})
    assert.equal(isProfileComplete(draft()), true)
  })

  it('requires a name', () => {
    assert.match(profileErrors(draft({ fullName: '   ' })).fullName, /enter a name/)
  })

  it('requires the self-describe text only when that option is chosen', () => {
    assert.ok(profileErrors(draft({ genderOption: 'Self-describe' })).gender)
    assert.deepEqual(
      profileErrors(
        draft({ genderOption: 'Self-describe', genderSelfDescribe: 'They/them' }),
      ),
      {},
    )
    assert.deepEqual(profileErrors(draft({ genderOption: 'Man' })), {})
    assert.deepEqual(profileErrors(draft({ genderOption: '' })), {})
  })
})

describe('profileUpdatePayload', () => {
  it('sends exactly the five columns the form owns', () => {
    // role / seller_status / suspended* / the seller application columns are
    // guarded by a trigger and are never sent from here.
    assert.deepEqual(Object.keys(profileUpdatePayload(draft())).sort(), [
      'bio',
      'birthday',
      'full_name',
      'gender',
      'phone',
    ])
  })

  it('trims the name and sends the date in the column’s own format', () => {
    const payload = profileUpdatePayload(draft({ fullName: '  Ana Reyes  ' }))
    assert.equal(payload.full_name, 'Ana Reyes')
    assert.equal(payload.birthday, '1998-04-17')
  })

  it('turns an emptied field into NULL rather than leaving the old value', () => {
    // Deliberate divergence from the app, which cannot clear birthday/gender.
    const payload = profileUpdatePayload(
      draft({ phone: '', birthday: '', genderOption: '', bio: '   ' }),
    )
    assert.equal(payload.phone, null)
    assert.equal(payload.birthday, null)
    assert.equal(payload.gender, null)
    assert.equal(payload.bio, null)
  })

  it('stores the self-described text, not the literal option', () => {
    // Copying sign-up: the COLUMN holds the free text.
    const payload = profileUpdatePayload(
      draft({ genderOption: 'Self-describe', genderSelfDescribe: ' Nonbinary ' }),
    )
    assert.equal(payload.gender, 'Nonbinary')
  })

  it('round-trips a saved draft through the payload unchanged', () => {
    const current = profileDraftFromRow(row())
    const reread = profileDraftFromRow(profileUpdatePayload(current))
    assert.deepEqual(profileUpdatePayload(reread), profileUpdatePayload(current))
  })

  it('round-trips a self-described gender', () => {
    const current = profileDraftFromRow(row({ gender: 'Nonbinary' }))
    assert.equal(profileUpdatePayload(current).gender, 'Nonbinary')
  })
})

describe('profileIsDirty', () => {
  it('is false for an untouched draft', () => {
    assert.equal(profileIsDirty(profileDraftFromRow(row()), row()), false)
  })

  it('is false when only whitespace changed', () => {
    const next = draft({ fullName: '  Ana Reyes  ' })
    assert.equal(profileIsDirty(next, row()), false)
  })

  it('is true for a real change', () => {
    assert.equal(profileIsDirty(draft({ fullName: 'Ana R.' }), row()), true)
    assert.equal(profileIsDirty(draft({ phone: '' }), row()), true)
    assert.equal(profileIsDirty(draft({ bio: 'From Carcar' }), row()), true)
  })

  it('counts a cleared birthday as a change', () => {
    assert.equal(profileIsDirty(draft({ birthday: '' }), row()), true)
  })
})

describe('sameProfilePayload', () => {
  it('is true for the same write', () => {
    const payload = profileUpdatePayload(draft())
    assert.equal(sameProfilePayload(payload, { ...payload }), true)
  })

  it('is false when any field differs', () => {
    const payload = profileUpdatePayload(draft())
    assert.equal(
      sameProfilePayload(payload, { ...payload, full_name: 'Someone Else' }),
      false,
    )
  })

  it('treats a missing key and an explicit null as the same', () => {
    // `undefined` and `null` both mean "no value" in a column, and a payload
    // that went through JSON and back will have one where the other was.
    assert.equal(sameProfilePayload({ bio: null }, {}), true)
  })

  it('is false between null and a real value', () => {
    assert.equal(sameProfilePayload({ bio: null }, { bio: 'x' }), false)
  })
})

describe('avatarStoragePath / AVATAR_BUCKET', () => {
  it('is the path the Storage policies and the app both expect', () => {
    // `(storage.foldername(name))[1] = auth.uid()` — the folder has to be the
    // user id, and the filename is fixed so uploads overwrite instead of piling
    // up unreferenced files.
    assert.equal(AVATAR_BUCKET, 'avatars')
    assert.equal(
      avatarStoragePath('061eae13-4309-44bd-81c5-96dfcd23c46a'),
      '061eae13-4309-44bd-81c5-96dfcd23c46a/avatar.jpg',
    )
  })

  it('does not throw on a missing id', () => {
    assert.equal(avatarStoragePath(null), '/avatar.jpg')
  })
})

describe('avatarFileError', () => {
  const file = (overrides = {}) => ({
    type: 'image/jpeg',
    size: 1024,
    name: 'me.jpg',
    ...overrides,
  })

  it('accepts the three formats the bucket serves', () => {
    assert.equal(avatarFileError(file()), null)
    assert.equal(avatarFileError(file({ type: 'image/png' })), null)
    assert.equal(avatarFileError(file({ type: 'image/webp' })), null)
  })

  it('rejects another kind of file', () => {
    assert.match(avatarFileError(file({ type: 'application/pdf' })), /JPG, PNG or WebP/)
    assert.match(avatarFileError(file({ type: 'image/gif' })), /JPG, PNG or WebP/)
  })

  it('falls back to the extension when the browser sends no type', () => {
    // Windows drag-and-drop very often arrives with `file.type` empty;
    // rejecting a good JPEG with "use a JPG" is undiagnosable for a customer.
    assert.equal(avatarFileError(file({ type: '' })), null)
    assert.equal(avatarFileError(file({ type: '', name: 'me.PNG' })), null)
    assert.match(
      avatarFileError(file({ type: '', name: 'notes.txt' })),
      /JPG, PNG or WebP/,
    )
  })

  it('rejects an oversized photo', () => {
    assert.match(
      avatarFileError(file({ size: AVATAR_MAX_BYTES + 1 })),
      /under 5 MB/,
    )
  })

  it('allows one exactly at the limit', () => {
    assert.equal(avatarFileError(file({ size: AVATAR_MAX_BYTES })), null)
  })

  it('asks for a photo when nothing was chosen', () => {
    assert.match(avatarFileError(null), /Choose a photo/)
  })
})

describe('withAvatarCacheBust', () => {
  it('stamps the URL so a replaced photo is not served from cache', () => {
    assert.equal(
      withAvatarCacheBust(
        'https://x.supabase.co/storage/v1/object/public/avatars/u/avatar.jpg',
        1730000000000,
      ),
      'https://x.supabase.co/storage/v1/object/public/avatars/u/avatar.jpg?t=1730000000000',
    )
  })

  it('replaces an earlier stamp rather than stacking them', () => {
    const once = withAvatarCacheBust('https://x/a.jpg?t=1', 2)
    assert.equal(once, 'https://x/a.jpg?t=2')
  })

  it('keeps any other query parameter', () => {
    assert.equal(
      withAvatarCacheBust('https://x/a.jpg?token=abc', 2),
      'https://x/a.jpg?token=abc&t=2',
    )
  })

  it('is empty for an empty url, so a caller cannot render "?t="', () => {
    assert.equal(withAvatarCacheBust(''), '')
    assert.equal(withAvatarCacheBust(null), '')
  })
})

describe('profileError', () => {
  it('translates the bucket’s own size rejection', () => {
    const mapped = profileError({ message: 'Payload too large' })
    assert.match(mapped.message, /under 5 MB/)
    assert.ok(!/Payload too large/.test(mapped.message))
  })

  it('translates a rejected content type', () => {
    assert.match(
      profileError({ message: 'mime type text/plain is not supported' }).message,
      /JPG, PNG or WebP/,
    )
  })

  it('asks an expired session to sign in rather than blaming the save', () => {
    assert.match(
      profileError({ code: '42501', message: 'Not authenticated' }).message,
      /session has expired/,
    )
  })

  it('passes a hand-written server sentence through', () => {
    // The guard trigger's wording is written for a human; it should be shown.
    assert.equal(
      profileError({ code: 'P0001', message: 'Cannot change your own role.' })
        .message,
      'Cannot change your own role.',
    )
  })

  it('falls back for anything unrecognisable', () => {
    assert.match(profileError({}).message, /could not save your details/i)
    assert.match(profileError(null, 'Nope.').message, /Nope\./)
  })
})
