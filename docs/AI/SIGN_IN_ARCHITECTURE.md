# SoleVision — Sign In / Account Entry Architecture & UI Design

> Condensed reference for AI agents working on authentication / the merged
> front-door screen. Derived from the live codebase:
> `lib/screens/auth/account_entry_screen.dart`,
> `lib/providers/auth_provider.dart`, `lib/services/auth_service.dart`,
> `lib/services/biometric_service.dart`, `lib/screens/auth_gate.dart`,
> `lib/widgets/auth/dark_auth_text_field.dart`,
> `lib/widgets/auth/full_bleed_video_background.dart`,
> `lib/widgets/auth/sole_primary_auth_button.dart`,
> `lib/widgets/app_error_toast.dart`, `lib/utils/auth_error_messages.dart`,
> and `lib/constants/app_constants.dart`.
>
> **Where do I start?** `account_entry_screen.dart` for the UI + mode-switch
> animation + sign-in interactions, `auth_provider.dart` →
> `AuthProvider.login()` for the state layer, `auth_service.dart` →
> `AuthService.signIn()` for the Supabase call, and `auth_gate.dart` for
> post-login routing.

---

## Quick Facts

- **Screen:** `AccountEntryScreen` (`lib/screens/auth/account_entry_screen.dart`)
  — the merged front door that replaced the old `LoginScreen` + separate
  role-choice screen. Reached from `AuthGate` (returning logged-out user) or
  the OnboardingScreen's final fade.
- **Two in-place modes** (`AuthEntryMode.create` / `.signin`) share **one
  full-bleed video background** (`video/locals.mp4`, looping/muted/autoplay).
  Switching modes is a **state change inside the widget — never a route push** —
  so the video never restarts or cuts.
- **Stack:** Flutter + Supabase Auth (email/password) + `local_auth`
  (fingerprint/face) + `flutter_secure_storage` (encrypted credential vault).
- **State management:** ChangeNotifier + Provider (`AuthProvider`).
- **On successful login:** `AuthProvider` caches `currentUser` + `profile`,
  fires `onLoginHook` (loads `FollowProvider`), and **AuthGate's
  StreamBuilder reacts to the Supabase auth state change** to swap the root
  widget — `AccountEntryScreen` never navigates itself.
- **Two login paths:** email/password (`_submit`) and biometric
  (`_loginWithBiometrics`, shown only when the device supports it AND the
  user has previously enrolled).
- **Biometric enrollment offer:** after the FIRST successful email/password
  login (if available, not enrolled, and not previously declined), a modal
  bottom sheet asks "Enable Biometric Login?".
- **"Forgot password?" is currently SIMULATED** — it shows a green SnackBar
  ("Password reset link sent (simulated)"), it does NOT call
  `AuthService.resetPassword` (the real RPC exists but is not wired here).

---

## The mode-switch animation (the part that's easy to get wrong)

One `AnimationController` (280ms) drives BOTH blocks; the shared
`_SlideSwap` widget applies the slide to a header block and a content block
whose offsets have **opposite signs**, so they always move in opposite
directions in the same transition. Direction reverses per switch:

| Switch | Header | Content |
|--------|--------|---------|
| create → signin ("forward") | slides left | slides right |
| signin → create ("backward") | slides right | slides left |

- The content block's offset is the header's with the sign flipped — one
  distance value, one sign flip per block. Do NOT hand-tune four animations.
- `AnimatedSwitcher` was deliberately NOT used — it can't move two children
  in different directions in one transition.
- **Reduced motion:** `MediaQuery.of(context).disableAnimations` → the
  switch snaps instantly (no slide/fade).
- The eyebrow ("CUFMAI") stays static; only title/subtitle swap inside the
  slide. The outgoing copy is `ExcludeSemantics` while both are mounted, so
  screen readers never hear duplicate labels during the transition.

## Layout & content

```
Stack
├── VideoHeroBackground   (video + global dim 0.20 + top/bottom scrims)
└── SafeArea
    └── Column
        ├── Header block (pinned top) — eyebrow CUFMAI + animated title/subtitle
        └── Expanded (middle video, bottom-anchored scroll view)
              └── Content block (pinned bottom; scrolls when it overflows)
```

**Header** — create: "Create your account" / "Join the home of Carcar
footwear craftsmanship."; signin: "Welcome back" / "Sign in to your CUFMAI
account." (28px Playfair white title, 14px white@85% subtitle, same as the
old video hero).

**Create mode content** (bottom-up):
- **Shop as customer?** — `SolePrimaryAuthButton` (clay, radius 14, drop
  shadow) → pushes `CustomerRegisterScreen`.
- **A shoemaker or artisan? Apply to sell** — centered link row (underline
  on "Apply to sell"), whole row the tap target (≥44px, `Semantics`
  `button`) → pushes `SellerApplicationFlow` (all 4 steps, unshortcut).
- Hairline divider, then **Already have an account? Sign in** — switches to
  `signin` mode. **This is a mode switch, not navigation.**

**Signin mode content** (bottom-up):
- **Email / Password** — `DarkAuthTextField` (`lib/widgets/auth/
  dark_auth_text_field.dart`): a NEW dark-over-video field style, NOT
  `SoleTextField` as-is (that widget assumes a white card). Semi-opaque
  black fill (0.35), light white@0.22 border, cream icons, white text,
  `fieldRadius` 14. Same validators / `autofillHints` /
  autocorrect-off as the old login fields.
- **Forgot password?** — right-aligned, unchanged simulated stub.
- **Log In** — `SolePrimaryAuthButton`, same clay + shadow as "Shop as
  customer?" (one button language for both modes), spinner while
  `auth.isLoading`.
- **Biometric** (only when `_biometricAvailable && _biometricEnabled`) — OR
  divider + white pill "Sign in with Biometrics", restyled for the dark
  video (light dividers, black-based shadow).
- Hairline divider, then **New here? Create an account** — switches back to
  `create` mode.

**No glassmorphism anywhere** — `backdrop-filter` blur over a *playing*
video is expensive and drops frames on weaker GPUs; the gradient scrims do
the legibility work.

## Contrast — measured, not eyeballed

Scrims are tuned to ffmpeg `signalstats` measurements of the real asset
(`video/locals.mp4`, 2160×3840 portrait, 143s). The sign-in fields sit
higher than the old create-mode actions (≈33–70% of screen height on short
devices), and the 25–55% band reaches luma ≈ 130 on its brightest frames —
so the scrims were strengthened to close the 40–60% gap:

- **Global dim** `surfaceDark @ 0.20`.
- **Top scrim** `0.95 → 0.70 → 0` over `0 → 32% → 75%` (tail extended from
  55% so fields never fall into a scrim gap).
- **Bottom scrim** `0.22 → 0.98` over `18% → 100%` (floor raised / start
  moved up from 25% to overlap the top tail).
- **Fields** add black @ 0.35 on top (the brief's "0.28-ish" deepened to
  close the measured gap).

Worst-frame ratios (AA target 4.5:1): header eyebrow 6.6:1 / title 6.3:1 /
subtitle 4.8:1; field white text 5.1–6.3:1, cream labels 4.8–6.0:1; bottom
link rows 4.9–6.3:1 (4.5:1 on the single brightest bottom frame). The empty
middle stays ≈52% of the video's original brightness, so the footage reads
clearly.

## Architecture Layers

```
PRESENTATION  AccountEntryScreen (account_entry_screen.dart)
              ├─ VideoHeroBackground / DarkAuthTextField /
              │  SolePrimaryAuthButton / AppErrorToast
STATE         AuthProvider (login / logout / errorMessage / isLoading)
SERVICE       AuthService.signIn()  +  BiometricService
              └─ friendlyAuthErrorMessage()  (error → user copy)
BACKEND       Supabase Auth (signInWithPassword) + profiles row (RLS)
ROUTING       AuthGate StreamBuilder → _routeByRole() → shell
```

## Flow diagram

```
                     ┌──────────────────────────────┐
                     │        AuthGate              │
                     │  StreamBuilder(authState)     │
                     │   user == null                │
                     │   has_seen_onboarding?        │
                     │   └─ true → AccountEntryScreen◄┤
                     └──────────────────────────────┘
                                     │  create mode: "Shop as customer?"
                                     │  → push CustomerRegisterScreen
                                     │  create mode: "Apply to sell"
                                     │  → push SellerApplicationFlow
                                     │  "Sign in" → in-place mode switch
                                     ▼
                     ┌──────────────────────────────┐
                     │  signin mode _submit()        │
                     │  AuthProvider.login(email,    │
                     │               password)       │
                     │  • resets _currentUser/_profile│
                     │  • _isLoading = true          │
                     │  • AuthService.signIn(...)    │
                     └──────────────────────────────┘
                                     │
              ┌──────────────────────┴───────────────────────┐
              ▼                                              ▼
  ┌─────────────────────────┐                  ┌──────────────────────────┐
  │ AuthService.signIn()     │                  │ FAILURE                  │
  │ 1. force signOut existing│                  │ friendlyAuthErrorMessage│
  │    session (account      │                  │ → AppErrorToast          │
  │    switching safety)     │                  │   (floating, auto-dismiss)│
  │ 2. signInWithPassword    │                  └──────────────────────────┘
  │ 3. getProfile(user.id)   │
  │ 4. return user+profile   │
  └────────────┬────────────┘
               ▼
  ┌──────────────────────────────┐
  │ SUCCESS                       │
  │ AuthProvider caches user+     │
  │ profile, onLoginHook →        │
  │ FollowProvider.loadForUser    │
  │ (then) _offerBiometricEnroll- │
  │ ment if first-time + possible │
  └────────────┬──────────────────┘
               ▼
  Supabase auth state emits signedIn
               ▼
  AuthGate StreamBuilder rebuilds → _routeByRole(profile)
  ├─ suspended == true  → _SuspendedAccountScreen
  ├─ role == admin      → AdminShell
  ├─ role == seller + approved → SellerShell
  ├─ seller_status == pending  → PendingApprovalScreen
  └─ else               → CustomerShell (AnimatedSwitcher fade, 500ms)
```

## Error handling

- `AuthProvider.login` catches everything and stores
  `friendlyAuthErrorMessage(e)` (which maps `AuthException.code` → human
  copy; non-auth errors reduce to a generic message). Raw exceptions never
  reach the UI.
- **Security note:** `invalid_credentials` and `user_not_found` share one
  message so login can never reveal whether an email exists.
- `AccountEntryScreen._submit` shows `auth.errorMessage` via `AppErrorToast`
  (root overlay — floats above the video/content AND the keyboard) and stays
  on the screen (credentials are NOT cleared — the user can correct and
  resubmit).
- Form validation runs first via `_signinFormKey.currentState!.validate()` —
  email non-empty, password ≥ 6 chars — before any network call.

## Biometric login path

1. `_loginWithBiometrics()` → `BiometricService.authenticate()` — native
   prompt (`biometricOnly: true`, localized reason "Verify your identity to
   sign in to CUFMAI").
2. On success → `getSavedCredentials()` (returns `null` if not enabled or
   keys missing).
3. `AuthProvider.login(savedEmail, savedPassword)` — same path as manual
   login, so RLS, profile fetch and routing are identical.
4. Failures surface friendly toasts ("Biometric authentication cancelled.",
   "No saved credentials found…", "Biometric login failed…").
5. `logout()` clears the saved credentials (`clearCredentials`, keeps the
   `_declined` flag) so a different account can sign in.

## Key file map

| Layer | File | Responsibility |
|-------|------|----------------|
| UI | `lib/screens/auth/account_entry_screen.dart` | Merged front door: mode state + `_SlideSwap` animation, create content, signin form, biometric section, enrollment modal |
| UI | `lib/widgets/auth/dark_auth_text_field.dart` | Dark-over-video field variant (semi-opaque black fill, light border, cream icons) |
| UI | `lib/widgets/auth/full_bleed_video_background.dart` | `FullBleedVideoBackground` (looping video) + `VideoHeroBackground` (video + tuned scrims) |
| UI | `lib/widgets/auth/sole_primary_auth_button.dart` | Clay CTA with optional radius + drop shadow (both modes use it) |
| State | `lib/providers/auth_provider.dart` | `login()`, `logout()`, session/profile cache, `onLoginHook`/`onLogoutHook`, error mapping |
| Service | `lib/services/auth_service.dart` | `signIn()` — force sign-out → `signInWithPassword` → `getProfile` |
| Service | `lib/services/biometric_service.dart` | Native auth prompt + secure credential vault (local_auth + flutter_secure_storage) |
| Routing | `lib/screens/auth_gate.dart` | AuthState stream → `_routeByRole` → shells; suspended gate; first-time/login router |
| Shared UI | `lib/widgets/app_error_toast.dart` | Floating root-overlay error toast |
| Utils | `lib/utils/auth_error_messages.dart` | `AuthException.code` → friendly copy (shared with signup) |
| Constants | `lib/constants/app_constants.dart` | Palette, typography, radii, shadows |
| Tests | `test/utils/auth_error_messages_test.dart` | Error-mapping coverage (no widget test for the screen yet) |

## Edge cases & gotchas

1. **No self-navigation on success.** `AccountEntryScreen` never pushes a
   route after login — AuthGate's StreamBuilder detects the new session and
   swaps the root. Adding a manual `Navigator.push` here would fight the
   gate. (The create-mode buttons DO push — `CustomerRegisterScreen` /
   `SellerApplicationFlow` own their post-signup navigation.)
2. **Account switching.** `AuthService.signIn` force-signs-out any existing
   session first; a lingering session would otherwise block the new login
   silently.
3. **`AuthProvider.login` resets `_currentUser`/`_profile` to `null` before
   the attempt** so stale data from a previous session can't leak into the
   new one (e.g. wrong-password retry showing the old user's shell).
4. **Credentials fields disable autocorrect/suggestions** to prevent the
   keyboard's per-word yellow underlines and mangling of the address.
5. **Forgot password is a stub** — a SnackBar, not `resetPassword`. Wiring
   the real RPC (already available on `AuthService`/`SupabaseService`) is
   the natural next step.
6. **Biometric modal timing:** offered only after a SUCCESSFUL manual
   login, and only once per device (`declined` flag). `clearCredentials` on
   logout keeps the declined flag so we never re-pester.
7. **Biometric button is doubly gated:** device support AND previous
   enrollment — so most fresh installs never see the `OR` divider at all.
8. **`AnimatedSwitcher` (500ms fade)** wraps `_routeByRole` — the shell swap
   after login is animated, not a hard cut.
9. **Suspended accounts never reach a shell:** AuthGate checks
   `profile['suspended']` before role routing and shows
   `_SuspendedAccountScreen` (RLS also blocks their writes server-side).
10. **Toast vs SnackBar:** the error toast is deliberately NOT a SnackBar —
    it renders on the root overlay so it floats above the form (and the
    keyboard) without pushing layout around.
11. **Mode switch keeps the video alive:** header + content swap via one
    `AnimationController`; the video background is outside the swapped
    subtree so it never re-initializes on a mode toggle.
12. **Form GlobalKeys:** only the signin mode renders a `Form`, and only one
    mode's content is mounted at a time (the outgoing is dropped when the
    transition completes), so `_signinFormKey` can never be duplicated —
    the "duplicate GlobalKey" trap documented elsewhere doesn't apply here.
13. **Responsiveness:** header is pinned; the content block is bottom-anchored
    inside a scroll view (`ConstrainedBox(minHeight)` + `IntrinsicHeight` +
    `Column(end)`), so on short devices / large text / open keyboard it
    scrolls instead of clipping. Safe areas respected in both modes.
