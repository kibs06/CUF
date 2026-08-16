# SoleVision — Seller Application UI Architecture

> Condensed, UI-focused reference for AI agents working on the seller
> application screens. Derived from the live codebase:
> `lib/screens/auth/seller_application_flow.dart` (the flow),
> `lib/providers/seller_application_controller.dart` (state),
> and the shared auth widgets in `lib/widgets/auth/`
> (`SignupScaffold`, `AuthTextField`, `StepProgressIndicator`,
> `TermsPolicyTile`, `PasswordStrengthMeter`, `DocumentUploadTile`),
> plus the design tokens in `lib/constants/app_constants.dart`.
>
> **This doc is about the UI only.** For the full-stack flow (auth creation
> timing, storage uploads, RLS, admin approval) see
> `docs/AI/SIGNUP_ARCHITECTURE.md`.

---

## Entry point — AccountEntryScreen (merged video front door)

`lib/screens/auth/account_entry_screen.dart` is the merged front door
(replaced the old role-choice screen AND the old `LoginScreen`): one screen
with two in-place modes — `AuthEntryMode.create` (the role picker below) and
`AuthEntryMode.signin` (email/password) — sharing a single **full-bleed
video hero**: `video/locals.mp4` (2160×3840 portrait, 143s) loops muted
behind everything, composed by the `VideoHeroBackground` widget
(`lib/widgets/auth/full_bleed_video_background.dart` — autoplay, `cover` fit,
no controls, dark base while loading so there's never a cream flash, plus the
tuned global dim + scrims). Switching modes is an **in-place state change**
(slide/fade swap via one shared `AnimationController` — header and content
slide in opposite directions, direction reverses per switch, reduced-motion
honored), so the video never restarts.

In **create** mode the hierarchy is weighted by usage: the **customer** path
is the single primary CTA (`SolePrimaryAuthButton`, clay, radius 14, subtle
drop shadow) while the **seller** path is one compact **link-style row** —
"A shoemaker or artisan? Apply to sell", centered, "Apply to sell"
underlined in warm cream. No border, no fill, no separate card: the whole
row is the tap target (≥44px, `Semantics` `button`) and pushes straight into
`SellerApplicationFlow` (all 4 steps — never shortcut). "Already have an
account? Sign in" switches to `signin` mode in place.

**Layout** — header block (eyebrow `CUFMAI` / serif 28px white title /
14px white@85% subtitle) pinned top, content block pinned bottom (inside a
bottom-anchored scroll view so short screens / large text scroll instead of
clipping), empty middle where the video is unobstructed.

**Contrast is tuned to the actual asset** (ffmpeg `signalstats` over the
full clip: full-frame mean luma ≈ 89/255, worst-case ≈ 146 top band / 118
bottom band / 130 in the 25–55% band where the sign-in fields sit). The
`VideoHeroBackground` composes: a global `surfaceDark` dim (0.20), a top
scrim `0.95 → 0.70 → 0` over `0 → 32% → 75%` height, and a bottom scrim
`0.22 → 0.98` over `18% → 100%` height — the scrims overlap so no band is
unprotected. Result: every chrome element clears ≥ 4.5:1 even on the single
brightest frame (≥ 4.8:1 subtitle, ≥ 4.9:1 cream seller link). See
`docs/AI/SIGN_IN_ARCHITECTURE.md` for the full merged-screen design and the
sign-in mode's contracts (no self-navigation on login, error toast,
biometric handling).

The app has no dark theme; this screen is inherently dark, so it is
light-theme-only like the rest of auth. The shared `SolePrimaryAuthButton`
lives in `lib/widgets/auth/sole_primary_auth_button.dart` (used by this
screen and the seller flow steps). The seller flow itself still renders
through `SignupScaffold` in its `lightContent` mode.

## What this is

`SellerApplicationFlow` is a **4-step, single-screen** form wizard (not 4
routes — one route whose body swaps between steps with an
`AnimatedSwitcher`). The screen in the mockup is **Step 1 · Account**:

- **Eyebrow:** `SELLER APPLICATION` (small-caps, brand color, letter-spaced)
- **Title:** `Create your seller account` (serif display, 30px)
- **Subtitle:** `Step 1 of 4 — your login details for SoleVision.`
- **Stepper:** 4 numbered circles (Account → Identity → Community → Storefront)
- **Fields:** Full Name, Email Address, Phone Number, Password, Confirm
  Password — each a label above a white rounded box with a left icon
- **Checkbox row:** `I agree to the Terms & Privacy Policy of CUFMAI.`
- **CTA:** full-width `Continue` button

---

## Screen anatomy (top → bottom)

```
Scaffold (surfaceLight #F5F0EB)
└── Stack
    ├── noiseOverlay(opacity: 0.04)      ← fine organic texture, CustomPainter
    └── SafeArea
        └── Column
            ├── TopBar                    ← back IconButton (44×44) + optional actions
            ├── Expanded
            │   └── SingleChildScrollView (horizontal padding 24)
            │       ├── Eyebrow           ← 12px, w600, letterSpacing 1.6, primary, UPPERCASE
            │       ├── Title             ← headlineStyle(30) serif, secondary
            │       ├── Subtitle          ← 15px, secondary @ 65% alpha, height 1.45
            │       └── Flow body         ← stepper + AnimatedSwitcher(step content)
            └── (optional pinned footer, not used by this flow)
```

Everything is hosted by the shared **`SignupScaffold`** — the same page
chrome used by the customer register and role-choice screens, so typography
and spacing rhythm are identical across the whole auth module.

---

## Step content — how the 4 steps swap

`SellerApplicationFlow` is a `StatefulWidget` that owns:

- One `TextEditingController` per field (name, email, phone, password,
  confirm, member ID, store name, store desc)
- **One `GlobalKey<FormState>` per step that has a Form**
  (`_accountFormKey`, `_storefrontFormKey`). This is deliberate: the
  `AnimatedSwitcher` briefly keeps the outgoing step mounted, and sharing a
  key between steps would crash with `"Duplicate GlobalKey"`.
- The scoped `SellerApplicationController` (created in `initState`, disposed
  with the screen)

The body is:

```
StepProgressIndicator(currentStep: ctrl.step, totalSteps: 4,
                      labels: ['Account','Identity','Community','Storefront'])
AnimatedSwitcher(250ms, fade in/out)
├── submitting || showSubmission  →  _SubmissionView (key 'submission')
└── else                          →  KeyedSubtree('step-${ctrl.step}')
                                     └── _AccountStep / _IdentityStep /
                                         _CommunityStep / _StorefrontStep
```

**Rebuild plumbing:** the step widgets read controller state directly in
their `build` (step index, termsAccepted, doc statuses…), so the flow adds a
controller listener (`_onControllerChanged → setState`) to repaint whenever
the controller notifies. Without this, a value like `termsAccepted` set
inside the read-and-agree flow would be stored but never repainted.

### Step navigation

- `ctrl.nextStep() / backStep() / jumpToStep(i)` mutate `_step` and
  `notifyListeners()`. Step is zero-based (`0..3`).
- Titles/subtitles are derived per step:
  - 0 · `Create your seller account` / `Step 1 of 4 — your login details for SoleVision.`
  - 1 · `Verify your identity` / `Step 2 of 4 — a government ID and a selfie help admins confirm it's really you.`
  - 2 · `Prove your community link` / `Step 3 of 4 — CUFMAI membership, or a barangay proof if you're not a member.`
  - 3 · `Set up your storefront` / `Step 4 of 4 — how customers will find you, and where your earnings go.`
- **Back moves between steps — it never leaves the flow mid-form.** Both
  the top-bar back button (`SignupScaffold.onBack`, added for this) and
  the system back gesture (`PopScope.canPop` + `onPopInvokedWithResult`)
  route through one `_handleBack()`: step > 0 → `ctrl.backStep()`;
  submission/error view visible → `dismissSubmission()` (back to the
  form); only step 1 pops the route back to the landing screen. The route
  may only pop from step 1 while idle (`canPop: !submitting &&
  !showSubmission && step == 0`).
- **30-minute draft resume.** For the fresh "Apply to sell" entry (no
  `prefillProfile`), the flow autosaves the form to disk debounced (300ms
  after each controller change — `SellerApplicationDraftStore` in
  `lib/services/seller_application_draft_store.dart`): fields, current
  step, toggles, and any still-existing picked image paths. Reopening the
  flow within 30 minutes restores everything (`ctrl.restoreDraft` +
  `TextEditingController` re-seed). Expired drafts are discarded on load;
  the draft is cleared on successful submit. Re-apply (`prefillProfile`)
  never persists or restores. The password half is written to
  `FlutterSecureStorage`, never plaintext in SharedPreferences.

---

## Step 1 · Account (`_AccountStep`)

A `Form` containing, in order:

1. **Re-apply banner** (only when `ctrl.isReapply` — rejected seller
   re-applying with an existing session): `_InfoBanner` with a refresh icon
   saying no new password is needed.
2. **Full Name** — `AuthTextField`, hint `e.g. Josefa Reyes`,
   `Icons.person_outline`, `AutofillHints.name`, required.
3. **Email Address** — hint `e.g. josefa@gmail.com`, `Icons.email_outlined`,
   `AutofillHints.email`, format check (`@` + `.`), and surfaces
   `ctrl.emailExistsError` inline. The error is cleared on change.
4. **Phone Number** — hint `e.g. 09XX-XXX-XXXX`, `Icons.phone_outlined`,
   `AutofillHints.telephoneNumber`, min 10 chars.
5. **Password** (hidden when re-applying) — `obscureText`, lock icon,
   `AutofillHints.newPassword`, min 6 chars, followed by
   `PasswordStrengthMeter`.
6. **Confirm Password** — `Icons.lock_clock_outlined`, must equal password
   field ("Passwords do not match").
7. **TermsPolicyTile** — bound to `ctrl.termsAccepted`.
8. **Continue** — `SolePrimaryAuthButton`; on press validates the form,
   requires terms accepted, then runs the **duplicate-email check** (spinner
   on the button while checking, `_checkingEmail`), then `ctrl.nextStep()`.

### AuthTextField — the shared field widget

Used by every text field in the flow (and the customer register screen).
Extends the app's `SoleTextField` visual language with auth-specific
behavior:

- **Label** — 14px bold, secondary color, above the field.
- **Input box** — white fill, 12px radius, 1px `borderGray @ 60%` border;
  content padding 16/14; 15px input text.
- **Prefix icon** — 20px, primary color.
- **Live inline validation** — a controller listener re-runs the `validator`
  on every keystroke; the suffix shows a green
  `check_circle` (valid) or red `error_outline` (invalid), swapped with an
  `AnimatedSwitcher` scale transition. This is in addition to submit-time
  `Form.validate()` error text (12px red, `errorMaxLines: 2`).
- **Password fields** (`passwordField: true`) — show/hide eye toggle
  (`visibility` / `visibility_off`), 44×44 tap target, screen-reader
  tooltip. The eye starts hidden (`_obscure = true`).
- **Borders** — focused: primary 1.5px; error: `error` 1.5px.
- **Autocorrect/suggestions OFF by default** — auth fields collect
  structured data (names, emails, passwords, IDs); the per-word spell-check
  underline would read as a stray yellow underline. Opt back in explicitly
  for genuinely prose fields.

### PasswordStrengthMeter

- 4 animated segments (`AnimatedContainer`, 220ms) + live label
  (`AnimatedDefaultTextStyle`), appearing only when the password is
  non-empty (`AnimatedOpacity`/`AnimatedSize`).
- Score from length (6+, 10+) and character-class coverage (lower/upper/
  digit/symbol) → `tooShort | weak | fair | good | strong`:
  `borderGray` → `error` red → amber → blue → `success` green.

### TermsPolicyTile — read-and-agree consent

Shared by customer registration AND the seller flow (used to be duplicated).
The tile is **role-aware**: it takes a `CUFMAITermsPolicy` (`customer` /
`seller` / `all`) and opens the matching document in `TermsPrivacyScreen` —
the customer register consents to the Customer policy, the seller flow to
the Seller policy (Profile → Settings picks by the signed-in role: sellers
see the Seller document, **admins see both stacked** via
`CUFMAITermsPolicy.all`, everyone else the Customer document). The checkbox
label and link text mirror the role ("…Customer/Seller Terms & Privacy
Policy…").

- **Custom-drawn checkbox** — a 22×22 rounded box (`AnimatedContainer`,
  180ms) that fills primary with a white check when checked; no stock
  `Checkbox` widget.
- **Tap behavior** — tapping the row when unchecked opens
  `TermsPrivacyScreen` in **readAndAgree** mode (agree button disabled until
  the user scrolls to the very bottom); agreeing pops `true` and checks the
  box. Already checked → tapping unchecks directly (no re-read).
- The `Terms & Privacy Policy` span has its own `TapGestureRecognizer`
  (owned + disposed in state) so tapping the link opens the policy WITHOUT
  toggling the checkbox.
- Wrapped in `Semantics(container, checked, label)` so screen readers see
  the whole row as a checkbox.

---

## Step 2 · Identity (`_IdentityStep`)

- Two upload slots, each `_DocTileLabel` (uppercase 12px section header) +
  `DocumentUploadTile`:
  - **Government-issued ID** — "Government ID photo", any valid ID with
    name + photo.
  - **Liveness selfie** — "Selfie", clear face photo.
- Privacy `_InfoBanner` (lock icon): photos are private and only seen by
  SoleVision admins.
- **Continue** is gated on both docs being non-empty; if missing, a red
  SnackBar names what's required (no form validation, just doc presence).

### DocumentUploadTile + status lifecycle

`DocumentUploadStatus` = `empty → picked → uploading → uploaded | error`.
The tile renders whatever state the controller gives it:

| State | Visual |
|-------|--------|
| `empty` | Dashed-look drop target: 52px icon circle (`add_a_photo`), title, description, pill "Add photo" |
| `picked` | 64×64 thumbnail + status line "Ready to submit with your application" + replace/remove icon actions |
| `uploading` | Thumbnail + "Uploading securely…" + 3px `LinearProgressIndicator` |
| `uploaded` | Thumbnail + green verified icon + "Uploaded securely" |
| `error` | Red border, "Upload failed" + message + retry action (re-runs the idempotent submit) |

- Border color tracks status: `error` red / `uploaded` success green /
  otherwise `borderGray`.
- Picking a photo opens `showVerificationImageSourceSheet` — a white bottom
  sheet with **Gallery** / **Camera** cards (`_SourceOption`, 92px tall,
  icon + label).
- Actions are 36×36 icon buttons with `Tooltip` + `Semantics` labels
  (Replace photo / Remove photo / Retry upload).

---

## Step 3 · Community (`_CommunityStep`)

- Explainer `_InfoBanner` (people icon) on why SoleVision asks (Carcar City
  shoe artisans marketplace).
- **`SegmentedButton<bool>`** toggle: `CUFMAI member` (badge icon) vs
  `Not a member` (home icon). Style: selected bg `primary @ 12%`,
  selected fg primary, 1px `borderGray @ 60%` side.
- **Conditional body** (`AnimatedSwitcher`, 220ms) swaps between:
  - Member → optional **CUFMAI Member ID** text field (badge icon, hint
    `e.g. CUF-2021-0184`) + a "speeds up approval" note.
  - Non-member → **Barangay certificate / proof** upload tile (required to
    continue).
- Switching to "member" clears any picked barangay proof
  (`ctrl.removeDocument`).
- **Continue** requires the barangay proof when non-member (red SnackBar
  otherwise).

---

## Step 4 · Storefront (`_StorefrontStep`)

- **Store Name** — storefront icon, required.
- **Store Description** — 4-line multiline field, min 20 chars.
- **Store photos** — a **Store front photo** `DocumentUploadTile` plus a
  **Product photos** section rendered as a compact **horizontal carousel**
  of five 96px square slots (`_ProductPhotoSlot`, keys
  `product-slot-1…5`): empty slots show a `+`/number affordance, filled
  slots show the image with a number chip and a small remove (X) button.
  The store-front photo uploads to the PUBLIC `store-assets` bucket
  (`{userId}/storefront.jpg`) so `StoreService.createStore` can reuse it
  as `banner_url`; the 5 product photos go to the private verification
  bucket (`product_photo_1…5`, stored as `profiles.product_photo_urls
  TEXT[]`). `_submit()` gates on the store-front photo first, then all 5
  product photos ("Please add N more product photos (5 required).").
- **Submit application** — `SolePrimaryAuthButton`, shows the button spinner
  while `ctrl.isSubmitting`.
- **Inline terms footnote** — a `Text.rich` with a `WidgetSpan` +
  `GestureDetector` (leak-free: no recognizer lifecycle to manage in a
  stateless step) linking to `TermsPrivacyScreen`.

---

## Submission view — animated checklist + designed error

When submit starts, the body swaps to `_SubmissionView` (white card, 16px
radius, 1px border):

- Header: "Submitting your application" (serif 18) + "This usually takes a
  few seconds. Please keep the app open."
- **Checklist** of `_CheckRow`s driven by controller flags:
  - Create your account — `ctrl.accountCreated`
  - Upload government ID — `idDocument.status`
  - Upload selfie — `selfie.status`
  - Upload barangay proof — only when not a CUFMAI member
  - Save your application — `ctrl.applicationSaved`
- Per-row trailing icon (`AnimatedSwitcher`, 200ms): green `check_circle`
  (done) / red `cancel` (error) / 18px `CircularProgressIndicator`
  (active) / outlined radio (pending).
- **On failure** the view STAYS on screen (never snaps back to the form):
  an error card (error @ 8% bg, 14px radius, error @ 40% border) shows the
  message with a full-width **Try again** button (re-runs the idempotent
  submit) and a **Back to my application** TextButton
  (`dismissSubmission()` + `jumpToStep(0)`).

---

## Shared small widgets

| Widget | Look |
|--------|------|
| `SolePrimaryAuthButton` | Full-width 52px `FilledButton`, primary bg, 12px radius, white 16px bold label, inline 24px spinner when loading, disabled = primary @ 60% |
| `_InfoBanner` | primary @ 6% bg, primary @ 20% border, 12px radius, 18px icon + 12px secondary text |
| `_DocTileLabel` | 12px UPPERCASE, w600, letterSpacing 1.2, secondary @ 60% |
| `_CheckRow` | label + animated status icon (submission checklist rows) |

---

## Design tokens (the espresso/cream visual language)

All from `AppConstants` (`lib/constants/app_constants.dart`):

- **Colors:** `surfaceLight` #F5F0EB (warm cream page bg) · `primary`
  #8B5A2B (burnished clay — buttons, accents, icons) · `secondary`
  #3B2314 (carob dark — text/icons) · `success` #6B8F47 · `error` #D64545 ·
  `borderGray` #D2C7BC.
- **Typography:** headlines = **Playfair Display** serif
  (`headlineStyle`), body/labels = **DM Sans** (`bodyStyle`), numerics =
  **Sora** tabular (`monoStyle`). Type scale used on auth screens:
  30 / 24 / 18 / 15 / 13 / 12.
- **Spacing:** `AuthSpacing` 4px scale (s4..s56) — every auth screen uses
  these instead of ad-hoc EdgeInsets so the rhythm is identical.
- **Radii:** card 16, button 12, stadium 999.
- **Texture:** `AppConstants.noiseOverlay(opacity: 0.04)` layered over the
  cream background — a `CustomPainter` that renders fine pseudo-random
  speckles (6px step grid, seeded RNG) for an organic paper feel.

---

## State ↔ UI binding rules

1. **All form/upload state lives in the controller** (scoped
   `ChangeNotifierProvider.value`), never in the step widgets — navigating
   steps or leaving/re-entering the flow mid-session keeps entered data.
2. **Notifying setters where the UI must repaint immediately** — e.g.
   `termsAccepted` is a getter/setter that calls `notifyListeners()`, not a
   plain field, so the checkbox repaints the moment the read-and-agree flow
   returns.
3. **`TextEditingController`s stay in the flow widget** and are seeded from
   controller state in `initState`; field `onChanged` writes back into the
   controller.
4. **One Form GlobalKey per step** — required by the AnimatedSwitcher's
   overlapping lifecycle.
5. **Per-step `ValueKey`s** (`'step-N'`, `'submission'`) force the switcher
   to treat each step as a distinct child.
6. **Document lifecycle** lives in `SellerDocState` (localPath, storagePath,
   status, errorMessage) — the tile is purely presentational.

---

## Key file map

| File | UI responsibility |
|------|-------------------|
| `lib/screens/auth/seller_application_flow.dart` | The 4-step flow screen: chrome wiring, step build/switch, step widgets, submission view, shared small widgets |
| `lib/providers/seller_application_controller.dart` | All form + upload + submission state (UI reads/writes this) |
| `lib/widgets/auth/signup_scaffold.dart` | Page chrome: cream bg, noise, eyebrow/title/subtitle, top bar, footer; also `AuthSpacing` |
| `lib/widgets/auth/auth_text_field.dart` | Premium field: label, prefix icon, live validation suffix, password toggle |
| `lib/widgets/auth/step_progress_indicator.dart` | 4-step stepper: circles + animated connector lines + labels |
| `lib/widgets/auth/terms_policy_tile.dart` | Role-aware read-and-agree terms checkbox row (opens the customer or seller policy) |
| `lib/widgets/auth/password_strength_meter.dart` | 4-segment live strength meter |
| `lib/widgets/auth/document_upload_tile.dart` | Doc upload slot + status lifecycle + gallery/camera sheet |
| `lib/screens/shared/terms_privacy_screen.dart` | Policy screen (`readAndAgree` mode) |
| `lib/constants/app_constants.dart` | Color/typography/spacing tokens, noise overlay |

---

## Edge cases & gotchas (UI-relevant)

1. **`AnimatedSwitcher` + GlobalKeys** — never share a Form GlobalKey
   between steps; each form-hosting step needs its own.
2. **Controller repaint dependency** — the flow must listen to the
   controller and `setState`; step widgets reading controller fields without
   that listener would render stale UI (the classic terms-checkbox bug).
3. **Re-apply mode** hides the password + confirm fields and swaps in an
   info banner — the flow detects `seller_status == 'rejected'` via the
   prefilled profile.
4. **Terms footnote vs checkbox** — on Step 4 the footnote link is a
   `WidgetSpan` + `GestureDetector` (stateless-safe); on Step 1 the link
   uses a disposed `TapGestureRecognizer` in a stateful tile. Both open the
   policy without toggling consent.
5. **Back navigation** — back goes to the **previous step** (button and
   system gesture both), only step 1 exits the flow; the submission view
   is dismissed first if it's on screen. Back is ignored while the final
   submit is running.
6. **Success path** — after submit the messenger is captured BEFORE
   `popUntil(route.isFirst)` because the flow's context is disposed as the
   role-choice screen unwinds; the snackbar is then shown from the captured
   messenger.
