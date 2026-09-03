# Seller Application & Account Creation Architecture

> **Purpose:** Documents the full seller onboarding flow — the multi-step application, document upload pipeline, account creation (deferred to final submit), admin review, and post-approval routing. Written for AI agents that need to understand or modify this subsystem.

---

## 1. Entry Points

| Entry | Trigger | Notes |
|---|---|---|
| `AccountEntryScreen` → role choice | New user selects "Sell on SoleVision" | Fresh application, draft-eligible |
| `EditProfileScreen` → "Re-apply" | Rejected seller taps re-apply | Prefills from existing profile (`prefillProfile`), no password collected, `isReapply = true` |
| Dev mode bypass | `DevMode.instance.isEnabled` | Skips validation at each step, creates a real PENDING account with null documents on submit |

**Key file:** `lib/screens/auth/seller_application_flow.dart`

---

## 2. The 5-Step Flow

```
Step 0 ─ Account        Step 1 ─ Identity      Step 2 ─ Community
Step 3 ─ Business       Step 4 ─ Storefront
```

### Step 0 · Account
- **Fields:** full name, email, phone, birthday (required), gender (optional), password, confirm password, terms acceptance
- **Validation:** form validation + duplicate-email check via `AuthService.emailExists()` (queries `profiles` table, lightweight pre-check before any document work)
- **Password:** collected here but NOT used until final submit. Stored in draft via `FlutterSecureStorage`, never plaintext on disk.
- **Re-apply:** password fields hidden; `ensureUser` reuses existing session.

### Step 1 · Identity
- **Documents:** government ID photo + liveness selfie (both required)
- **ID type picker:** must select before photo upload is shown (AnimatedSwitcher reveals the upload tile). Options from `AppConstants.govIdTypes` (Philippine government IDs).
- **Validation:** ID type selected + both photos picked before Continue is enabled.

### Step 2 · Community
- **Toggle:** CUFMAI member vs. non-member (SegmentedButton)
  - **Member:** optional CUFMAI member ID text field
  - **Non-member:** required barangay proof document upload
- **Personal details:** birthday + gender (carried from Step 0, displayed for confirmation)
- **Store location:** map picker (`StoreLocationPickerScreen` — MapTiler + Geolocator). Required. Stores formatted address + lat/lng coordinates.
- **Validation:** store location set + (if non-member) barangay proof picked.

### Step 3 · Business Verification (all required)
- **Documents:** DTI certificate + BIR COR + mayor's/barangay permit
- **All three are mandatory** — admins verify the applicant runs a registered business.
- **Storage:** uploaded to private `seller-verification-docs` bucket, written to `seller_business_docs` table (one row per profile, upsert on `profile_id`).

### Step 4 · Storefront
- **Fields:** store name (required), store description (optional), store tags (at least one required from preset vocabulary)
- **Documents:**
  - Store front photo (1 required) — uploaded to **PUBLIC** `store-assets` bucket, doubles as store banner (`profiles.store_front_url`)
  - Product photos (5 required) — uploaded to private `seller-verification-docs` bucket, stored as `profiles.product_photo_urls` (TEXT[])
- **Submit button** triggers the full submission sequence.

---

## 3. State Management

### `SellerApplicationController` (ChangeNotifier)
**File:** `lib/providers/seller_application_controller.dart`

Scoped via `ChangeNotifierProvider.value` in the flow widget. Owns:
- Step navigation (`step`, `nextStep()`, `backStep()`, `jumpToStep()`)
- All form fields (text, toggles, date pickers)
- All `SellerDocState` instances (one per document slot)
- Submission state (`isSubmitting`, `accountCreated`, `applicationSaved`, `showSubmission`, `submitError`)
- Re-apply detection (`_isReapply`)
- Document picking/removal (`pickDocument`, `removeDocument`)
- Upload orchestration (`_uploadIfNeeded`)
- Full submission sequence (`submit()`)

### `SellerDocState`
Holds per-document lifecycle:
```
localPath  → storagePath  → status (empty → picked → uploading → uploaded → error)
```

### `SellerApplicationData` (immutable model)
**File:** `lib/models/seller_application_data.dart`

Snapshot of all form + upload data, passed from controller to `AuthProvider.signUpSeller` → `AuthService.completeSellerApplication`. Fields map 1:1 to `profiles` and `seller_business_docs` columns.

---

## 4. Draft Resume (30-minute window)

**File:** `lib/services/seller_application_draft_store.dart`

- **SharedPreferences** stores form fields + local file paths (non-sensitive)
- **FlutterSecureStorage** stores password separately
- Draft auto-saves debounced at 300ms on every controller change
- **30-minute expiry:** `load()` checks `savedAt` age; expired drafts are deleted
- **Cleared on:** successful submission, or re-apply flow (never persists/restores for `prefillProfile`)
- **Best-effort:** if storage unavailable, the flow still works — just no resume

---

## 5. Submission Sequence

The `submit()` method in `SellerApplicationController` runs this exact sequence:

```
1. AuthService.ensureUser(email, password, fullName)
   ├─ Case A: Already signed in with same email → reuse (re-apply)
   ├─ Case B: Signed in with different email → sign out first
   └─ Case C: No session → auth.signUp
       └─ If account exists but no session (legacy) → signInWithPassword fallback

2. Upload documents (sequential, each individually retryable):
   ├─ id_document  → private bucket  (upsert: {userId}/id_document.{ext})
   ├─ selfie       → private bucket  (upsert: {userId}/selfie.{ext})
   ├─ dti_cert     → private bucket  (upsert: {userId}/dti_cert.{ext})
   ├─ bir_cor      → private bucket  (upsert: {userId}/bir_cor.{ext})
   ├─ permit       → private bucket  (upsert: {userId}/permit.{ext})
   ├─ storefront   → PUBLIC store-assets bucket (upsert: {userId}/storefront.{ext})
   ├─ product_photo_1..5 → private bucket (upsert: {userId}/product_photo_N.{ext})
   └─ barangay_proof → private bucket (only if NOT CUFMAI member)

3. AuthProvider.signUpSeller(data)
   ├─ AuthService.completeSellerApplication(user, data)
   │   ├─ profiles upsert: all Tier 1 fields + seller_status = 'pending'
   │   │   (role stays 'customer' — flipped to 'seller' ONLY on admin approval)
   │   └─ seller_business_docs upsert: DTI/BIR/permit paths + verification_status = 'pending'
   └─ Session adopted → AuthGate routes to PendingApprovalScreen
```

### Idempotency guarantees
- Already-uploaded docs are skipped on retry (status check)
- `ensureUser` reuses existing session
- Profile upsert overwrites cleanly
- Business docs upsert on `profile_id` (single row)

---

## 6. Storage Architecture

| Bucket | Access | Contents |
|---|---|---|
| `seller-verification-docs` | Private (owner + admin read via RLS) | ID photos, selfies, barangay proofs, business docs (DTI/BIR/permit), product photos |
| `store-assets` | Public | Store front photos (doubles as store banner post-approval) |

**File layout:** `{userId}/{docKey}.{ext}` (ext = jpg or png, determined by picker output)

**Upload:** `VerificationDocumentService.uploadDocument()` — upserts (overwrites previous), maxWidth 1600px, imageQuality 85, orientation baked in by picker.

**Signed URLs:** Private docs accessed via `VerificationDocumentService.signedUrl()` (1-hour expiry, enforced by storage RLS).

---

## 7. Database Schema (relevant columns)

### `profiles` table
```
id, full_name, email, role, seller_status, phone, birthday, gender,
id_type, id_document_url, selfie_url,
cufmai_member_id, barangay_proof_url,
store_name, store_description, store_location, store_lat, store_lng,
store_tags (TEXT[]), store_front_url, product_photo_urls (TEXT[]),
rejection_reason
```

### `seller_business_docs` table
```
profile_id (FK → profiles.id, unique),
dti_cert_url, bir_cor_url, permit_url,
verification_status ('none' | 'pending' | 'verified' | 'rejected'),
submitted_at, verified_at
```

### Key status values (`AppConstants`)
- `seller_status`: `'none'` → `'pending'` → `'approved'` | `'rejected'`
- `role`: `'customer'` → `'seller'` (only on admin approval)
- `verification_status`: `'none'` | `'pending'` | `'verified'` | `'rejected'`

---

## 8. Admin Review

### Tier 1: Seller Applications
**File:** `lib/screens/admin/seller_approval_screen.dart`

- Tab 0 of `SellerApprovalScreen` — lists all `seller_status == 'pending'` profiles
- Expandable document review: government ID, selfie, barangay proof, store info, product photos, business docs (via FK join to `seller_business_docs`)
- **Approve:** sets `role = 'seller'`, `seller_status = 'approved'`
- **Reject:** collects optional reason → sets `seller_status = 'rejected'`, `rejection_reason` stored. Reason included in rejection email via `send-approval-email` edge function.

### Tier 2: Business Documents (optional, decoupled)
**File:** `lib/screens/admin/seller_business_docs_review_screen.dart`

- Tab 1 of `SellerApprovalScreen` — reviews DTI/BIR/permit submissions separately
- Uses `set_business_verification_status` RPC (SECURITY DEFINER, server-side `is_admin()` check)
- **Never blocks selling** — a seller with `verification_status = 'none'` or `'pending'` can still sell normally

---

## 9. Post-Submission Routing

After successful submit → session adopted → `AuthGate` sees `seller_status == 'pending'` → routes to `PendingApprovalScreen`.

**File:** `lib/screens/auth/pending_approval_screen.dart`

- Shows timeline: Application received ✓ → Verification (in progress) → Certified CUFMAI member
- Lists what was received (ID, selfie, community proof, store info, store photos)
- Mentions Tier 2 business verification as optional/secondary
- Email notice: "We'll email you the decision" (check spam folder)
- "Back to home" button: pops if navigable, otherwise signs out (AuthGate then shows login screen)

**Re-apply flow:** rejected seller → profile has `seller_status = 'rejected'` → `SellerApplicationFlow(prefillProfile: profile)` → pre-fills account/community/store fields → `isReapply = true` → no password collected → `ensureUser` reuses existing session → clears `rejection_reason` on submit.

---

## 10. Navigation & Back Behavior

- **Back on Step 0:** exits the flow (pops to previous route)
- **Back on Steps 1–4:** moves to previous step (does NOT exit the flow)
- **Back during submission:** ignored
- **Back on submission/error view:** dismisses the view, returns to form
- **System back gesture:** handled via `PopScope` — same behavior as the top-bar back button

---

## 11. Error Handling

- **Duplicate email:** caught at Step 1 via `AuthService.emailExists()`, shown inline on the email field. Skipped during re-apply with same email.
- **Auth errors:** mapped through `friendlyAuthError()` (shared mapper with login/customer signup — consistent wording)
- **Upload failures:** per-document error state with retry. The submission view shows a checklist with ✅/❌/⏳ per item. "Try again" retries the full sequence (idempotent — already-uploaded docs skipped).
- **Network errors:** generic "Something went wrong. Check your connection and try again."

---

## 12. Key File Map

```
lib/
├── models/
│   └── seller_application_data.dart      # Immutable snapshot passed to auth layer
├── providers/
│   ├── auth_provider.dart                # signUpSeller() — creates account + persists application
│   └── seller_application_controller.dart # Form state, doc lifecycle, submission sequence
├── screens/
│   ├── auth/
│   │   ├── seller_application_flow.dart   # The 5-step UI (Entry → all step widgets)
│   │   ├── pending_approval_screen.dart   # Post-submit locked screen
│   │   └── seller_approved_celebration_screen.dart # Shown on approval
│   └── admin/
│       ├── seller_approval_screen.dart    # Tier 1: approve/reject seller applications
│       └── seller_business_docs_review_screen.dart # Tier 2: business doc verification
├── services/
│   ├── auth_service.dart                  # ensureUser, completeSellerApplication, approveSeller, rejectSeller
│   ├── verification_document_service.dart # Pick, upload, delete, signed URL for private docs
│   └── seller_application_draft_store.dart # 30-min draft resume (SharedPreferences + SecureStorage)
├── widgets/
│   ├── auth/
│   │   ├── document_upload_tile.dart      # Reusable doc upload card (status, pick, remove, retry)
│   │   ├── terms_policy_tile.dart         # Terms & privacy checkbox with read-and-agree flow
│   │   ├── step_progress_indicator.dart   # Segmented step indicator
│   │   └── password_strength_meter.dart   # Password strength visualization
│   ├── seller/
│   │   └── tag_selector.dart              # Preset tag picker (store tags + product tags)
│   └── admin/
│       └── verification_doc_viewer.dart   # Thumbnail + full-size viewer for private docs
└── constants/
    └── app_constants.dart                 # govIdTypes, statusPending/Approved/Rejected, roleSeller, etc.
```

---

## 13. Dev Mode Bypass

**⚠️ REMOVE BEFORE RELEASE**

When `DevMode.instance.isEnabled`:
- Step validation skipped at every Continue button
- Submit creates a real Supabase account with `seller_status = 'pending'` but **null document paths** (no uploads)
- Landed on `PendingApprovalScreen` → full admin approval loop runs
- Credentials default to `dev.seller@test.com` / `devpass123` if fields are empty
- Reuses existing account on repeated dev runs (`ensureUser` signs back in)

---

## 14. Data Flow Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    SellerApplicationFlow                     │
│  (StatefulWidget — owns TextEditingControllers + draft timer)│
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │       SellerApplicationController (ChangeNotifier)    │   │
│  │  - step, form fields, SellerDocState per doc slot    │   │
│  │  - pickDocument() / removeDocument()                 │   │
│  │  - submit() → ensureUser → upload → persist          │   │
│  └──────────────────────────────────────────────────────┘   │
│         │                                    │                │
│         ▼                                    ▼                │
│  VerificationDocumentService          AuthProvider            │
│  (pick, upload to Supabase            .signUpSeller(data)    │
│   storage, signed URL, delete)         │                     │
│                                        ▼                     │
│                                 AuthService                  │
│                                 .ensureUser()                │
│                                 .completeSellerApplication() │
│                                        │                     │
│                                        ▼                     │
│                              Supabase PostgREST              │
│                              profiles (upsert)               │
│                              seller_business_docs (upsert)   │
│                              Storage (private + public)      │
│                                        │                     │
│                                        ▼                     │
│                              AuthGate routes to              │
│                              PendingApprovalScreen           │
└─────────────────────────────────────────────────────────────┘
```
