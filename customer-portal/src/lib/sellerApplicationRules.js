import {
  validateBirthday,
  validateGenderSelfDescribe,
} from './signupRules.js'

/**
 * Seller application rules — the pure half of the portal's seller signup.
 *
 * Kept free of the Supabase client for the same reason `sellerRules.js` is:
 * every step's requirements are policy, and policy must be provable without a
 * network. Each rule is copied from the piece it has to agree with — the
 * Flutter app's `seller_application_flow.dart` /
 * `seller_application_controller.dart` — because the portal and the phone
 * write to the SAME profile rows, and a web application the admin reads
 * differently from a phone one is worse than no web application.
 *
 * The Supabase writes live next door in `sellerApplication.js`.
 */

/** Storage buckets — the same two the app writes (`auth_service.dart`). */
export const VERIFICATION_BUCKET = 'seller-verification-docs'
export const STORE_ASSET_BUCKET = 'store-assets'

/** Product photos the storefront step requires (the app's `requiredUploadCount`). */
export const REQUIRED_PRODUCT_PHOTOS = 5

/** Document keys — the `{userId}/{docKey}.{ext}` layout, upsert per key. */
export const SELLER_DOC_KEYS = {
  ID_DOCUMENT: 'id_document',
  SELFIE: 'selfie',
  BARANGAY_PROOF: 'barangay_proof',
  DTI_CERT: 'dti_cert',
  BIR_COR: 'bir_cor',
  PERMIT: 'permit',
  STOREFRONT: 'storefront',
}

/**
 * Valid Philippine government IDs (`AppConstants.govIdTypes` — `value` is what
 * is stored in `profiles.id_type`, `label` is what the applicant reads).
 */
export const GOV_ID_TYPES = [
  { value: 'philid', label: 'PhilSys National ID (PhilID / ePhilID)' },
  { value: 'passport', label: 'Philippine Passport' },
  { value: 'drivers_license', label: "Driver's License (LTO)" },
  { value: 'umid', label: 'UMID / SSS Digitized ID' },
  { value: 'gsis', label: 'GSIS eCard' },
  { value: 'prc', label: 'PRC ID' },
  { value: 'postal', label: 'Postal ID (PhilPost)' },
  { value: 'voters', label: "Voter's ID (COMELEC)" },
  { value: 'senior', label: 'Senior Citizen ID (OSCA)' },
  { value: 'pwd', label: 'PWD ID' },
  { value: 'tin', label: 'TIN ID (BIR)' },
  { value: 'nbi', label: 'NBI Clearance' },
]

export const MINIMUM_PASSWORD_LENGTH = 8

/** Client-side document guard — the app's 10 MB JPEG/PNG rule. */
export const MAX_DOC_BYTES = 10 * 1024 * 1024
const ACCEPTED_DOC_TYPES = ['image/jpeg', 'image/png']
const ACCEPTED_DOC_EXTS = ['jpg', 'jpeg', 'png']

function extensionOf(name) {
  const parts = String(name ?? '').split('.')
  return parts.length > 1 ? parts.pop().toLowerCase() : ''
}

/**
 * A picked file's problem, or null when it may be uploaded.
 *
 * Client-side validation is UX, not security — it catches an accidental PDF
 * early. The bucket's own MIME allowlist is the real boundary.
 */
export function validateDocFile(file) {
  if (!file) return 'Please choose a file.'
  const ext = extensionOf(file.name)
  const typeOk = ACCEPTED_DOC_TYPES.includes(file.type)
  const extOk = ACCEPTED_DOC_EXTS.includes(ext)
  if (!typeOk && !extOk) {
    return 'Only JPG and PNG photos are accepted.'
  }
  if (file.size > MAX_DOC_BYTES) {
    return 'That photo is too large — please use one under 10 MB.'
  }
  return null
}

function isEmail(value) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(String(value ?? '').trim())
}

/**
 * Step 1 — Account. Returns an errors object; empty means the step may continue.
 * Mirrors the app's account-step validators plus the portal's own age gate.
 */
export function validateAccountStep({
  fullName,
  email,
  phone,
  birthday,
  gender,
  genderText,
  password,
  confirm,
  termsAccepted,
}) {
  const errors = {}
  if (!String(fullName ?? '').trim()) errors.fullName = 'Enter your full name'
  if (!String(email ?? '').trim()) errors.email = 'Enter your email address'
  else if (!isEmail(email)) errors.email = 'Enter a valid email address'
  if (!String(phone ?? '').trim()) errors.phone = 'Enter your mobile number'

  const birthdayError = validateBirthday(birthday)
  if (birthdayError) errors.birthday = birthdayError

  const genderError = validateGenderSelfDescribe(gender, genderText)
  if (genderError) errors.gender = genderError

  if (!password) errors.password = 'Choose a password'
  else if (password.length < MINIMUM_PASSWORD_LENGTH) {
    errors.password = `Use at least ${MINIMUM_PASSWORD_LENGTH} characters`
  }
  if (confirm !== password) errors.confirm = 'The two passwords do not match'
  if (!termsAccepted) {
    errors.terms = 'Please accept the Terms & Privacy Policy to continue.'
  }
  return errors
}

/** Step 2 — Identity: an ID type plus both photos picked. */
export function validateIdentityStep({ idType, idFile, selfieFile }) {
  const errors = {}
  if (!idType) errors.idType = 'Choose the ID you are showing us'
  const idProblem = validateDocFile(idFile)
  if (idProblem) errors.idFile = 'Add a photo of your government ID.'
  const selfieProblem = validateDocFile(selfieFile)
  if (selfieProblem) errors.selfieFile = 'Add a selfie holding that ID.'
  return errors
}

/**
 * Step 3 — Community: a CUFMAI member gives their member ID, anyone else gives
 * a barangay proof — at least one of the two must be present (the app's rule).
 * The store location is required; on the web it is a typed address rather than
 * the app's map pin (lat/lng stay optional).
 */
export function validateCommunityStep({
  isMember,
  memberId,
  barangayFile,
  storeLocation,
}) {
  const errors = {}
  if (isMember) {
    if (!String(memberId ?? '').trim()) {
      errors.memberId = 'Enter your CUFMAI member ID'
    }
  } else {
    const proofProblem = validateDocFile(barangayFile)
    if (proofProblem) errors.barangayFile = 'Add your barangay proof.'
  }
  if (!String(storeLocation ?? '').trim()) {
    errors.storeLocation = 'Tell us where your store is'
  }
  return errors
}

/** Step 4 — Business: DTI, BIR COR and permit are ALL required. */
export function validateBusinessStep({ dtiFile, birFile, permitFile }) {
  const errors = {}
  if (validateDocFile(dtiFile)) errors.dtiFile = 'Add your DTI certificate.'
  if (validateDocFile(birFile)) errors.birFile = 'Add your BIR COR.'
  if (validateDocFile(permitFile)) {
    errors.permitFile = "Add your mayor's or barangay permit."
  }
  return errors
}

/**
 * Step 5 — Storefront: name, description, at least one tag (application v2),
 * a store-front photo (it doubles as the store banner post-approval) and five
 * product photos.
 */
export function validateStorefrontStep({
  storeName,
  storeDescription,
  tagCount,
  storefrontFile,
  productFiles,
}) {
  const errors = {}
  if (!String(storeName ?? '').trim()) errors.storeName = 'Name your store'
  if (!String(storeDescription ?? '').trim()) {
    errors.storeDescription = 'Describe what your store makes and sells'
  }
  if (!tagCount) errors.tags = 'Please choose at least one store tag.'
  if (validateDocFile(storefrontFile)) {
    errors.storefrontFile = 'Please add a photo of your store front.'
  }
  const count = Array.isArray(productFiles) ? productFiles.length : 0
  if (count < REQUIRED_PRODUCT_PHOTOS) {
    errors.productFiles =
      `Add ${REQUIRED_PRODUCT_PHOTOS} product photos (${count} of ${REQUIRED_PRODUCT_PHOTOS} so far).`
  }
  return errors
}
