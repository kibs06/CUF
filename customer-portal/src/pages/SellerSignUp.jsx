import { useEffect, useState } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import { Check, Clock3 } from 'lucide-react'

import AuthErrorSummary from '../components/auth/AuthErrorSummary'
import AuthShell from '../components/auth/AuthShell'
import DocPicker from '../components/auth/DocPicker'
import StepIndicator from '../components/auth/StepIndicator'
import TagPicker from '../components/seller/TagPicker'
import Field from '../components/ui/Field'
import PasswordField from '../components/ui/PasswordField'
import { serializeTags } from '../lib/productTags.js'
import { GENDER_OPTIONS } from '../lib/signupRules.js'
import {
  GOV_ID_TYPES,
  MINIMUM_PASSWORD_LENGTH,
  REQUIRED_PRODUCT_PHOTOS,
  clearPendingSellerApplication,
  clearSellerDraft,
  completeSellerApplication,
  loadPendingSellerApplication,
  loadSellerDraft,
  savePendingSellerApplication,
  saveSellerDraft,
  sellerEmailExists,
  signUpSellerAccount,
  uploadSellerDocuments,
  uploadStorefrontPhoto,
  validateAccountStep,
  validateBusinessStep,
  validateCommunityStep,
  validateDocFile,
  validateIdentityStep,
  validateStorefrontStep,
} from '../lib/sellerApplication.js'
import { supabase } from '../lib/supabase'

const STEPS = ['Account', 'Identity', 'Community', 'Business', 'Storefront']

/** Error key → element id, per step, for the summary's field links. */
const STEP_LINKS = [
  {
    fullName: 'seller-fullName',
    email: 'seller-email',
    phone: 'seller-phone',
    birthday: 'seller-birthday',
    gender: 'seller-gender',
    password: 'seller-password',
    confirm: 'seller-confirm',
    terms: 'seller-terms',
  },
  { idType: 'seller-idType', idFile: 'seller-idFile', selfieFile: 'seller-selfie' },
  {
    memberId: 'seller-memberId',
    barangayFile: 'seller-barangay',
    storeLocation: 'seller-location',
  },
  { dtiFile: 'seller-dti', birFile: 'seller-bir', permitFile: 'seller-permit' },
  {
    storeName: 'seller-storeName',
    storeDescription: 'seller-storeDesc',
    tags: 'seller-tags',
    storefrontFile: 'seller-storefront',
    productFiles: 'seller-products',
  },
]

const SELLER_STORY = {
  eyebrow: 'Sell on CUFMAI · Carcar City, Cebu',
  heading: 'Your craft, in front of every shopper.',
  body: 'One application, reviewed by an admin — the same review whether you apply here or in the CUFMAI app. Approval usually takes a few days, and the store-front photo you add below becomes your banner.',
  points: [
    'The same application and review as the CUFMAI app',
    'Every document verified before approval',
    'Sell here and in the app with one account',
  ],
  browseTo: '/',
  browseLabel: 'Back to the storefront',
}

const SUBMIT_PROGRESS = {
  account: 'Creating your account…',
  documents: 'Uploading your documents…',
  application: 'Saving your application…',
}

/**
 * Seller signup — the portal twin of the app's `SellerApplicationFlow`.
 *
 * The same 5 steps, the same required documents and the same database writes
 * (auth user at final submit only, private-bucket uploads, then a
 * `seller_status = 'pending'` profile with `role` left as `customer` — the
 * flip to `seller` happens ONLY on admin approval). Two web adaptations, both
 * honest about what changed:
 *
 *  - The store location is a typed address, not the app's map pin (lat/lng are
 *    not collected on the web).
 *  - With "Confirm email" ON there is no session after signup, and files
 *    cannot be stashed — so the text half is saved to `localStorage`, the
 *    applicant confirms the link, and `AuthConfirm` sends them back here to
 *    re-attach the documents and finish. The awaiting-email copy says exactly
 *    that.
 */
export default function SellerSignUp() {
  const [searchParams] = useSearchParams()
  const [step, setStep] = useState(0)

  // Step 1 — Account (same fields as the app's account step).
  const [fullName, setFullName] = useState('')
  const [email, setEmail] = useState('')
  const [phone, setPhone] = useState('')
  const [birthday, setBirthday] = useState('')
  const [gender, setGender] = useState('')
  const [genderText, setGenderText] = useState('')
  const [password, setPassword] = useState('')
  const [confirm, setConfirm] = useState('')
  const [termsAccepted, setTermsAccepted] = useState(false)

  // Step 2 — Identity.
  const [idType, setIdType] = useState('')
  const [idFile, setIdFile] = useState(null)
  const [selfieFile, setSelfieFile] = useState(null)

  // Step 3 — Community.
  const [isMember, setIsMember] = useState(true)
  const [memberId, setMemberId] = useState('')
  const [barangayFile, setBarangayFile] = useState(null)
  const [storeLocation, setStoreLocation] = useState('')

  // Step 4 — Business (all three required, like the app).
  const [dtiFile, setDtiFile] = useState(null)
  const [birFile, setBirFile] = useState(null)
  const [permitFile, setPermitFile] = useState(null)

  // Step 5 — Storefront.
  const [storeName, setStoreName] = useState('')
  const [storeDescription, setStoreDescription] = useState('')
  const [tagEntries, setTagEntries] = useState([])
  const [storefrontFile, setStorefrontFile] = useState(null)
  const [productFiles, setProductFiles] = useState([])

  const [errors, setErrors] = useState({})
  const [attempt, setAttempt] = useState(0)
  const [formError, setFormError] = useState(null)
  const [checkingEmail, setCheckingEmail] = useState(false)
  const [submitting, setSubmitting] = useState(false)
  const [progress, setProgress] = useState(null)
  const [awaitingEmail, setAwaitingEmail] = useState(false)
  const [submitted, setSubmitted] = useState(false)
  const [resumed, setResumed] = useState(false)
  const [started, setStarted] = useState(false)
  const [draftAvailable, setDraftAvailable] = useState(false)
  const [draftNotice, setDraftNotice] = useState(false)

  // Resume after an email confirmation: AuthConfirm routes the fresh session
  // back here (`?resume=1`) and the text half is restored from localStorage.
  // Files cannot be restored — the notice says to re-attach them.
  useEffect(() => {
    if (searchParams.get('resume') !== '1') return
    let cancelled = false
    async function resume() {
      const draft = loadPendingSellerApplication()
      if (!draft) return
      const { data } = await supabase.auth.getSession()
      if (cancelled) return
      const sessionEmail = data?.session?.user?.email ?? ''
      if (
        sessionEmail &&
        draft.email &&
        sessionEmail.toLowerCase() !== String(draft.email).toLowerCase()
      ) {
        return
      }
      const account = draft.account ?? {}
      const community = draft.community ?? {}
      const storefront = draft.storefront ?? {}
      setFullName(account.fullName ?? '')
      setEmail(draft.email ?? sessionEmail ?? '')
      setPhone(account.phone ?? '')
      setBirthday(account.birthday ?? '')
      setGender(account.gender ?? '')
      setGenderText(account.genderText ?? '')
      setIsMember(community.isMember ?? true)
      setMemberId(community.memberId ?? '')
      setStoreLocation(community.storeLocation ?? '')
      setIdType(draft.identity?.idType ?? '')
      setStoreName(storefront.storeName ?? '')
      setStoreDescription(storefront.storeDescription ?? '')
      setResumed(true)
      setStarted(true)
      setDraftAvailable(false)
      // Files are gone with the old page — start where they are re-attached.
      setStep(sessionEmail ? 1 : 0)
    }
    resume()
    return () => {
      cancelled = true
    }
  }, [searchParams])

  // A draft the applicant left behind (a closed tab, a dead battery) is
  // offered back — typed answers only, never the password, and photos must
  // be re-attached. The post-confirmation resume above takes precedence.
  useEffect(() => {
    if (searchParams.get('resume') === '1') return
    if (loadSellerDraft()) setDraftAvailable(true)
  }, [searchParams])

  // Autosave typed answers as they go (Etsy/Stripe-style save-and-continue).
  // Files are deliberately excluded — a photo has nowhere to live before the
  // account exists — and so is the password.
  useEffect(() => {
    if (!started || submitted || awaitingEmail) return
    saveSellerDraft({
      step,
      email,
      account: { fullName, phone, birthday, gender, genderText },
      identity: { idType },
      community: { isMember, memberId, storeLocation },
      storefront: { storeName, storeDescription },
      savedAt: new Date().toISOString(),
    })
  }, [started, submitted, awaitingEmail, step, email, fullName, phone, birthday, gender, genderText, idType, isMember, memberId, storeLocation, storeName, storeDescription])

  const restoreDraft = (draft) => {
    const account = draft.account ?? {}
    const community = draft.community ?? {}
    const storefront = draft.storefront ?? {}
    setFullName(account.fullName ?? '')
    setEmail(draft.email ?? '')
    setPhone(account.phone ?? '')
    setBirthday(account.birthday ?? '')
    setGender(account.gender ?? '')
    setGenderText(account.genderText ?? '')
    setIsMember(community.isMember ?? true)
    setMemberId(community.memberId ?? '')
    setStoreLocation(community.storeLocation ?? '')
    setIdType(draft.identity?.idType ?? '')
    setStoreName(storefront.storeName ?? '')
    setStoreDescription(storefront.storeDescription ?? '')
    // Photos cannot be restored — resume where they are re-attached.
    setStep(Math.min(draft.step ?? 0, 1))
    setDraftAvailable(false)
    setDraftNotice(true)
    setStarted(true)
  }

  const fail = (next) => {
    const ok = Object.keys(next).length === 0
    setErrors(next)
    // Re-mount the summary so it takes focus on every failed attempt.
    if (!ok) setAttempt((count) => count + 1)
    return ok
  }

  const goNext = async () => {
    if (step === 0) {
      if (
        !fail(
          validateAccountStep({
            fullName,
            email,
            phone,
            birthday,
            gender,
            genderText,
            password,
            confirm,
            termsAccepted,
          }),
        )
      ) {
        return
      }
      // Duplicate-email check at Step 1 — before any document work, like the app.
      setCheckingEmail(true)
      try {
        const { data } = await supabase.auth.getSession()
        const ownEmail = (data?.session?.user?.email ?? '').toLowerCase()
        if (email.trim().toLowerCase() !== ownEmail) {
          const exists = await sellerEmailExists(email)
          if (exists) {
            fail({ email: 'This email is already registered. Try signing in instead.' })
            return
          }
        }
      } catch {
        // The probe is best-effort (RLS may hide other rows): the final submit
        // surfaces a real conflict, so a failed check never blocks the form.
      } finally {
        setCheckingEmail(false)
      }
      setErrors({})
      setStep(1)
      return
    }
    if (step === 1) {
      if (!fail(validateIdentityStep({ idType, idFile, selfieFile }))) return
      setErrors({})
      setStep(2)
      return
    }
    if (step === 2) {
      if (
        !fail(
          validateCommunityStep({ isMember, memberId, barangayFile, storeLocation }),
        )
      ) {
        return
      }
      setErrors({})
      setStep(3)
      return
    }
    if (step === 3) {
      if (!fail(validateBusinessStep({ dtiFile, birFile, permitFile }))) return
      setErrors({})
      setStep(4)
    }
  }

  const goBack = (target) => {
    setErrors({})
    setFormError(null)
    setStep(typeof target === 'number' ? target : (current) => Math.max(0, current - 1))
  }

  const onSubmit = async (event) => {
    event.preventDefault()
    setFormError(null)
    if (
      !fail(
        validateStorefrontStep({
          storeName,
          storeDescription,
          tagCount: tagEntries.length,
          storefrontFile,
          productFiles,
        }),
      )
    ) {
      return
    }

    const account = {
      fullName,
      phone,
      birthday,
      gender,
      genderText,
    }
    const identity = { idType }
    const community = { isMember, memberId, storeLocation }
    const storefront = {
      storeName,
      storeDescription,
      storeTags: serializeTags(tagEntries),
    }

    setSubmitting(true)
    try {
      // 1. Account — created ONLY now, never mid-flow (no orphaned accounts).
      setProgress('account')
      const { user, emailVerificationRequired } = await signUpSellerAccount({
        email,
        password,
        fullName,
      })

      // 1b. Email confirmation first when required: uploads and the profile
      // write both need a session (private-bucket RLS keys off auth.uid()).
      if (emailVerificationRequired) {
        savePendingSellerApplication({
          email: email.trim(),
          account: { ...account, password: undefined },
          identity,
          community,
          storefront,
          savedAt: new Date().toISOString(),
        })
        setAwaitingEmail(true)
        clearSellerDraft()
        return
      }

      // 2. Upload documents into the private bucket (+ storefront public).
      setProgress('documents')
      const paths = await uploadSellerDocuments(user.id, {
        idFile,
        selfieFile,
        dtiFile,
        birFile,
        permitFile,
        barangayFile,
        isMember,
        productFiles,
      })
      paths.storefront = await uploadStorefrontPhoto(user.id, storefrontFile)

      // 3. Persist the application (role stays customer, status pending).
      setProgress('application')
      await completeSellerApplication({
        userId: user.id,
        email,
        account,
        identity,
        community,
        business: {},
        storefront,
        paths: {
          id_document: paths.id_document,
          selfie: paths.selfie,
          barangay_proof: paths.barangay_proof,
          dti_cert: paths.dti_cert,
          bir_cor: paths.bir_cor,
          permit: paths.permit,
          storefront: paths.storefront,
          productPhotos: paths.productPhotos,
        },
      })
      clearPendingSellerApplication()
      clearSellerDraft()
      setSubmitted(true)
    } catch (error) {
      setFormError(
        error?.message ?? 'We could not submit your application. Please try again.',
      )
    } finally {
      setSubmitting(false)
      setProgress(null)
    }
  }

  // The whole job, stated upfront (the Amazon pattern): what to prepare,
  // how long it takes, and what happens after — so step 1 never feels like
  // the first page of a surprise novel.
  if (!started) {
    return (
      <AuthShell
        title="Apply to sell"
        subtitle="Five short steps, about 10 minutes, one review."
        story={SELLER_STORY}
        footer={
          <>
            Already have an account?{' '}
            <Link
              to="/signin"
              className="font-semibold text-clay-ink underline-offset-4 hover:underline"
            >
              Sign in
            </Link>
          </>
        }
      >
        <p className="flex items-center gap-2 text-sm font-semibold text-ink">
          <Clock3 className="h-4 w-4 text-clay-ink" aria-hidden="true" />
          What you will need
        </p>
        <ul className="mt-3 space-y-2.5 text-sm text-muted-strong">
          {[
            'Your details — name, birthday, store address',
            'A government ID photo plus a selfie holding it',
            'Business papers — DTI certificate, BIR COR, permit',
            'A store-front photo plus 5 product photos',
          ].map((line) => (
            <li key={line} className="flex items-start gap-2.5">
              <span
                aria-hidden="true"
                className="mt-0.5 flex h-[18px] w-[18px] shrink-0 items-center justify-center rounded-full bg-olive/15 text-olive"
              >
                <Check className="h-3 w-3" strokeWidth={3} />
              </span>
              <span className="leading-snug">{line}</span>
            </li>
          ))}
        </ul>
        <p className="mt-4 text-xs leading-relaxed text-muted">
          Your typed answers save on this device as you go. An admin reviews
          everything after you submit — approval usually takes a few days.
        </p>
        <button
          type="button"
          onClick={() => setStarted(true)}
          className="btn btn-primary mt-5 w-full"
        >
          Start my application
        </button>
        {draftAvailable && (
          <button
            type="button"
            onClick={() => {
              const draft = loadSellerDraft()
              if (draft) restoreDraft(draft)
              else setStarted(true)
            }}
            className="mt-2.5 w-full cursor-pointer text-xs font-semibold text-muted underline-offset-4 transition-colors duration-200 ease-out-cubic hover:text-clay-ink hover:underline"
          >
            Pick up where you left off
          </button>
        )}
      </AuthShell>
    )
  }

  if (submitted) {
    return (
      <AuthShell
        title="Application received"
        subtitle="An admin is looking at it now."
        story={SELLER_STORY}
        footer={
          <>
            Back to{' '}
            <Link
              to="/"
              className="font-semibold text-clay-ink underline-offset-4 hover:underline"
            >
              the storefront
            </Link>
          </>
        }
      >
        <div
          role="status"
          className="rounded-field border border-olive/30 bg-olive/[0.07] px-4 py-3"
        >
          <p className="text-sm font-semibold text-ink">
            {storeName.trim()} is in the review queue
          </p>
          <p className="mt-1 text-sm leading-relaxed text-muted">
            Your application is now{' '}
            <span className="font-semibold text-ink">pending review</span>. You
            will be able to list products and take orders here as soon as it is
            approved — the CUFMAI app will let you know when that happens.
          </p>
        </div>
        <p className="mt-4 text-xs text-muted">
          Your account can already shop the storefront while you wait.
        </p>
      </AuthShell>
    )
  }

  if (awaitingEmail) {
    return (
      <AuthShell
        title="Check your email"
        subtitle="Confirm your address to finish your application."
        story={SELLER_STORY}
        footer={
          <>
            Wrong address?{' '}
            <button
              type="button"
              onClick={() => setAwaitingEmail(false)}
              className="font-semibold text-clay-ink underline-offset-4 hover:underline"
            >
              Go back and change it
            </button>
          </>
        }
      >
        <p className="text-sm leading-relaxed text-muted">
          We sent a confirmation link to{' '}
          <span className="font-semibold text-ink">{email.trim()}</span>. Open it
          in this browser — you will come straight back here to finish.
        </p>
        <p className="mt-4 text-sm leading-relaxed text-muted">
          Your details are saved on this device. Photos cannot be kept while you
          confirm, so you will re-attach them after — everything you typed stays.
        </p>
      </AuthShell>
    )
  }

  return (
    <AuthShell
      title="Apply to sell"
      subtitle={`Step ${step + 1} of ${STEPS.length} · ${STEPS[step]} · ${Math.round(((step + 1) / STEPS.length) * 100)}%`}
      story={SELLER_STORY}
      footer={
        <>
          Already have an account?{' '}
          <Link
            to="/signin"
            className="font-semibold text-clay-ink underline-offset-4 hover:underline"
          >
            Sign in
          </Link>
        </>
      }
    >
      <StepIndicator steps={STEPS} current={step} onSelect={goBack} />

      {resumed && (
        <div
          role="status"
          className="mb-5 rounded-field border border-olive/30 bg-olive/[0.07] px-4 py-3 text-sm leading-relaxed text-ink"
        >
          Email confirmed — welcome back. Your details are restored; re-attach
          your photos below to finish.
        </div>
      )}
      {draftNotice && !resumed && (
        <div
          role="status"
          className="mb-5 rounded-field border border-olive/30 bg-olive/[0.07] px-4 py-3 text-sm leading-relaxed text-ink"
        >
          Welcome back — your typed answers are restored. Re-attach your photos
          to continue (photos cannot be saved until your account exists).
        </div>
      )}

      {Object.keys(errors).length > 0 && (
        <div className="mb-5">
          <AuthErrorSummary
            key={`${step}-${attempt}`}
            errors={errors}
            links={STEP_LINKS[step]}
          />
        </div>
      )}

      {step === 0 && (
        <div className="space-y-5">
          <Field
            id="seller-fullName"
            label="Full name"
            value={fullName}
            onChange={setFullName}
            error={errors.fullName}
            autoComplete="name"
            required
            placeholder="Juan dela Cruz"
          />
          <Field
            id="seller-email"
            label="Email"
            type="email"
            value={email}
            onChange={setEmail}
            error={errors.email}
            autoComplete="email"
            required
            placeholder="you@example.com"
          />
          <Field
            id="seller-phone"
            label="Mobile number"
            type="tel"
            value={phone}
            onChange={setPhone}
            error={errors.phone}
            autoComplete="tel"
            required
            placeholder="09XX XXX XXXX"
          />
          <Field
            id="seller-birthday"
            label="Birthday"
            type="date"
            value={birthday}
            onChange={setBirthday}
            error={errors.birthday}
            autoComplete="bday"
            required
          />
          <Field id="seller-gender" label="Gender" error={errors.gender}>
            <select
              id="seller-gender"
              value={gender}
              onChange={(event) => setGender(event.target.value)}
              className="mt-2 h-11 w-full rounded-field border border-hairline bg-raised px-4 text-sm text-ink transition-colors duration-200 ease-out-cubic hover:border-card-edge focus:border-clay"
            >
              <option value="">Prefer not to say</option>
              {GENDER_OPTIONS.filter((option) => option !== 'Prefer not to say').map(
                (option) => (
                  <option key={option} value={option}>
                    {option}
                  </option>
                ),
              )}
            </select>
          </Field>
          {gender === 'Self-describe' && (
            <Field
              id="seller-genderText"
              label="How you describe yourself"
              value={genderText}
              onChange={setGenderText}
              required
              placeholder="Your words"
            />
          )}
          <PasswordField
            id="seller-password"
            label="Password"
            value={password}
            onChange={setPassword}
            error={errors.password}
            autoComplete="new-password"
            required
            hint={`At least ${MINIMUM_PASSWORD_LENGTH} characters.`}
          />
          <PasswordField
            id="seller-confirm"
            label="Confirm password"
            value={confirm}
            onChange={setConfirm}
            error={errors.confirm}
            autoComplete="new-password"
            required
          />
          <div>
            <label
              htmlFor="seller-terms"
              className="flex cursor-pointer items-start gap-3 text-sm text-muted"
            >
              <input
                id="seller-terms"
                type="checkbox"
                checked={termsAccepted}
                onChange={(event) => setTermsAccepted(event.target.checked)}
                aria-invalid={errors.terms ? 'true' : undefined}
                aria-describedby={errors.terms ? 'seller-terms-error' : undefined}
                className="mt-1 h-4 w-4 shrink-0 cursor-pointer accent-clay-ink"
              />
              <span>
                I agree to the CUFMAI Terms &amp; Privacy Policy and to an admin
                reviewing my documents.
              </span>
            </label>
            {errors.terms && (
              <p id="seller-terms-error" className="mt-1.5 text-xs font-medium text-crimson">
                {errors.terms}
              </p>
            )}
          </div>
        </div>
      )}

      {step === 1 && (
        <div className="space-y-5">
          <Field id="seller-idType" label="Government ID" error={errors.idType} required>
            <select
              id="seller-idType"
              value={idType}
              onChange={(event) => setIdType(event.target.value)}
              className="mt-2 h-11 w-full rounded-field border border-hairline bg-raised px-4 text-sm text-ink transition-colors duration-200 ease-out-cubic hover:border-card-edge focus:border-clay"
            >
              <option value="">Choose your ID type</option>
              {GOV_ID_TYPES.map((option) => (
                <option key={option.value} value={option.value}>
                  {option.label}
                </option>
              ))}
            </select>
          </Field>
          <DocPicker
            id="seller-idFile"
            label="ID photo"
            hint="Show all four corners, in color — no screenshots."
            file={idFile}
            error={errors.idFile}
            onChange={setIdFile}
            required
          />
          <DocPicker
            id="seller-selfie"
            label="Selfie holding that ID"
            hint="Your face and the ID must both be visible."
            file={selfieFile}
            error={errors.selfieFile}
            onChange={setSelfieFile}
            required
          />
        </div>
      )}

      {step === 2 && (
        <div className="space-y-5">
          <div>
            <p
              id="seller-membership-label"
              className="block text-xs font-semibold uppercase tracking-[0.08em] text-muted"
            >
              CUFMAI membership
            </p>
            <div className="mt-2 grid grid-cols-2 gap-2" role="group" aria-labelledby="seller-membership-label">
              <button
                type="button"
                onClick={() => setIsMember(true)}
                aria-pressed={isMember}
                className={`h-11 cursor-pointer rounded-field border text-sm font-semibold transition-colors duration-200 ease-out-cubic focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-clay/60 ${
                  isMember
                    ? 'border-clay bg-clay/10 text-clay-ink'
                    : 'border-hairline bg-raised text-muted hover:border-card-edge'
                }`}
              >
                I am a member
              </button>
              <button
                type="button"
                onClick={() => setIsMember(false)}
                aria-pressed={!isMember}
                className={`h-11 cursor-pointer rounded-field border text-sm font-semibold transition-colors duration-200 ease-out-cubic focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-clay/60 ${
                  !isMember
                    ? 'border-clay bg-clay/10 text-clay-ink'
                    : 'border-hairline bg-raised text-muted hover:border-card-edge'
                }`}
              >
                Not yet a member
              </button>
            </div>
          </div>
          {isMember ? (
            <Field
              id="seller-memberId"
              label="CUFMAI member ID"
              value={memberId}
              onChange={setMemberId}
              error={errors.memberId}
              required
              placeholder="CUF-0000"
            />
          ) : (
            <DocPicker
              id="seller-barangay"
              label="Barangay proof"
              hint="A certificate or clearance showing you live or work here."
              file={barangayFile}
              error={errors.barangayFile}
              onChange={setBarangayFile}
              required
            />
          )}
          <Field
            id="seller-location"
            label="Store location"
            value={storeLocation}
            onChange={setStoreLocation}
            error={errors.storeLocation}
            required
            placeholder="Poblacion, Carcar City, Cebu"
            hint="Street / barangay / city — where customers find you."
          />
        </div>
      )}

      {step === 3 && (
        <div className="space-y-5">
          <p className="text-sm leading-relaxed text-muted">
            Business documents prove the store is real. All three are required —
            an admin reviews them with the rest of your application.
          </p>
          <DocPicker
            id="seller-dti"
            label="DTI certificate"
            hint="A clear photo or scan — every line readable."
            file={dtiFile}
            error={errors.dtiFile}
            onChange={setDtiFile}
            required
          />
          <DocPicker
            id="seller-bir"
            label="BIR certificate of registration"
            hint="A clear photo or scan — every line readable."
            file={birFile}
            error={errors.birFile}
            onChange={setBirFile}
            required
          />
          <DocPicker
            id="seller-permit"
            label="Mayor's or barangay permit"
            hint="A clear photo or scan — every line readable."
            file={permitFile}
            error={errors.permitFile}
            onChange={setPermitFile}
            required
          />
        </div>
      )}

      {step === 4 && (
        <form onSubmit={onSubmit} className="space-y-5" noValidate>
          <Field
            id="seller-storeName"
            label="Store name"
            value={storeName}
            onChange={setStoreName}
            error={errors.storeName}
            required
            placeholder="Ana's Handmade Footwear"
          />
          <Field
            id="seller-storeDesc"
            label="Store description"
            value={storeDescription}
            onChange={setStoreDescription}
            error={errors.storeDescription}
            required
            placeholder="What you make, and what makes it yours"
          >
            <textarea
              id="seller-storeDesc"
              value={storeDescription}
              onChange={(event) => setStoreDescription(event.target.value)}
              rows={3}
              placeholder="What you make, and what makes it yours"
              aria-invalid={errors.storeDescription ? 'true' : undefined}
              aria-describedby={errors.storeDescription ? 'seller-storeDesc-error' : undefined}
              className="mt-2 w-full rounded-field border border-hairline bg-raised px-4 py-3 text-sm text-ink transition-colors duration-200 ease-out-cubic placeholder:text-muted/60 hover:border-card-edge focus:border-clay"
            />
          </Field>
          <div id="seller-tags">
            <p className="block text-xs font-semibold uppercase tracking-[0.08em] text-muted">
              Store tags
            </p>
            <div className="mt-2">
              <TagPicker entries={tagEntries} onChange={setTagEntries} />
            </div>
            {errors.tags && (
              <p className="mt-1.5 text-xs font-medium text-crimson">{errors.tags}</p>
            )}
          </div>
          <DocPicker
            id="seller-storefront"
            label="Store-front photo"
            hint="Shows you really run a store — and becomes your store banner."
            file={storefrontFile}
            error={errors.storefrontFile}
            onChange={setStorefrontFile}
            required
          />
          <div>
            <p className="block text-xs font-semibold uppercase tracking-[0.08em] text-muted">
              Product photos{' '}
              <span className="font-normal normal-case tracking-normal text-muted/70">
                {productFiles.length} of {REQUIRED_PRODUCT_PHOTOS} — required
              </span>
            </p>
            <p className="mt-1.5 text-xs text-muted">Clear photos of what you actually sell — they are reviewed.</p>
            <input
              id="seller-products"
              type="file"
              accept="image/jpeg,image/png"
              multiple
              aria-describedby={errors.productFiles ? 'seller-products-error' : undefined}
              onChange={(event) => {
                const picked = Array.from(event.target.files ?? []).filter(
                  (file) => !validateDocFile(file),
                )
                setProductFiles((current) =>
                  [...current, ...picked].slice(0, REQUIRED_PRODUCT_PHOTOS),
                )
                event.target.value = ''
              }}
              className="mt-2 block w-full cursor-pointer text-sm text-muted file:mr-3 file:cursor-pointer file:rounded-field file:border file:border-hairline file:bg-raised file:px-4 file:py-2 file:text-sm file:font-semibold file:text-ink hover:file:border-card-edge"
            />
            {productFiles.length > 0 && (
              <ul className="mt-3 grid grid-cols-5 gap-2">
                {productFiles.map((file, index) => (
                  <li key={`${file.name}-${index}`} className="relative">
                    <img
                      src={URL.createObjectURL(file)}
                      alt={`Product photo ${index + 1}`}
                      className="h-16 w-full rounded-field border border-hairline object-cover"
                    />
                    <button
                      type="button"
                      aria-label={`Remove product photo ${index + 1}`}
                      onClick={() =>
                        setProductFiles((current) =>
                          current.filter((_, position) => position !== index),
                        )
                      }
                      className="absolute -right-1.5 -top-1.5 flex h-5 w-5 cursor-pointer items-center justify-center rounded-full bg-crimson text-[11px] font-bold text-white transition-transform duration-200 ease-out-cubic hover:scale-110"
                    >
                      <span aria-hidden="true">×</span>
                    </button>
                  </li>
                ))}
              </ul>
            )}
            {errors.productFiles && (
              <p id="seller-products-error" className="mt-1.5 text-xs font-medium text-crimson">
                {errors.productFiles}
              </p>
            )}
          </div>

          {formError && (
            <div
              role="alert"
              className="rounded-field border border-crimson/30 bg-crimson/[0.07] px-4 py-3 text-sm text-ink"
            >
              {formError}
            </div>
          )}

          <button
            type="submit"
            disabled={submitting}
            aria-busy={submitting}
            className="btn btn-primary w-full"
          >
            {submitting && progress
              ? SUBMIT_PROGRESS[progress]
              : submitting
                ? 'Submitting…'
                : 'Submit application'}
          </button>
          <button
            type="button"
            onClick={() => goBack(3)}
            disabled={submitting}
            className="w-full cursor-pointer text-xs font-semibold text-muted underline-offset-4 transition-colors duration-200 ease-out-cubic hover:text-clay-ink hover:underline disabled:cursor-default disabled:opacity-60"
          >
            Back to business documents
          </button>
        </form>
      )}

      {step < 4 && (
        <div className="mt-7 space-y-3">
          <button
            type="button"
            onClick={goNext}
            disabled={checkingEmail}
            className="btn btn-primary w-full"
          >
            {checkingEmail ? 'Checking…' : step === 3 ? 'Continue to storefront' : 'Continue'}
          </button>
          {step > 0 && (
            <button
              type="button"
              onClick={() => goBack()}
              className="w-full cursor-pointer text-xs font-semibold text-muted underline-offset-4 transition-colors duration-200 ease-out-cubic hover:text-clay-ink hover:underline"
            >
              Back
            </button>
          )}
        </div>
      )}
    </AuthShell>
  )
}
