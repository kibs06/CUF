# Customer Sign-Up Flow — Quick Reference Graph

> **Purpose:** One diagram for the whole customer path — from app launch / sign-up to landing inside `CustomerShell` (Home · Store · Notifications · Profile).
> **Audience:** AI agents and developers tracing or changing the customer auth entry point.
> **Last updated:** October 17, 2026 — polished to the actual journey: splash shortcut, confirm-OFF branch, give-up path, foot-scan returns, full sign-in gates
> **Verified against:** `lib/screens/auth_gate.dart`, `lib/screens/auth/customer_register_screen.dart`, `lib/screens/auth/account_entry_screen.dart`, `lib/screens/auth/foot_profile_onboarding_screen.dart`, `lib/providers/auth_provider.dart`, `lib/services/auth_service.dart`, `lib/screens/customer/customer_shell.dart`
>
> **Editable copy (Dia):** `docs/AI/diagrams/customer-signup-flow.dia` — the same flow as an editable [Dia](https://gitlab.gnome.org/GNOME/dia) diagram. It has two layers, "1 - Signup to CustomerShell" and "2 - CustomerShell tabs", which can be toggled independently in the Layers dialog. Rendered exports sit beside it (`.png`, `.svg`).
>
> **Client-facing copy (draw.io):** `docs/diagrams/customer-signup-flow.drawio` — the same journey written in plain English for the customer, with no screen, class or table names. The `customer-signup-flow-preview.png` and `.svg` beside it are previews drawn from the same coordinates. The whole customer journey (sign-up, shopping, try-on, custom pairs, orders, messages, profile) is the 13-page `docs/diagrams/customer-journey-flowchart.drawio`, with page previews in `docs/diagrams/previews/` — see `docs/diagrams/README.md`.

## Table of Contents
1. [The one-line version](#1-the-one-line-version)
2. [Stage 1 — Launch to the registration form](#2-stage-1--launch-to-the-registration-form)
3. [Stage 2 — Account creation and e-mail confirmation](#3-stage-2--account-creation-and-e-mail-confirmation)
4. [Stage 3 — Foot-profile step, then AuthGate routing into the shell](#4-stage-3--foot-profile-step-then-authgate-routing-into-the-shell)
5. [Returning-user sign-in — the gates a new customer skips](#5-returning-user-sign-in--the-gates-a-new-customer-skips)
6. [Stage 4 — CustomerShell: the four tabs](#6-stage-4--customershell-the-four-tabs)
7. [Decision points worth knowing](#7-decision-points-worth-knowing)
8. [File map](#8-file-map)
9. [Not covered here](#9-not-covered-here)

---

## 1. The one-line version

```mermaid
flowchart LR
    A(["SplashScreen<br/>2 s + silent update check"]) --> B{"Existing session?"}
    B -- "Yes" --> H(["CustomerShell<br/>straight in, no form"])
    B -- "No" --> C("Onboarding<br/>(first launch only)")
    C --> D("AccountEntryScreen<br/>(create / signin switch in place)")
    D --> E("CustomerRegisterScreen")
    E --> F{"Confirm email ON?<br/>usual is yes"}
    F -- "Yes" --> G("E-mail code / link<br/>(profiles row written here)")
    F -- "No" --> K("Signed in right away")
    G --> K
    K --> L("FootProfileOnboarding<br/>(always skippable)")
    L --> M("AuthGate._routeByRole + gates")
    M --> H

    style H fill:transparent,color:#000000,stroke:#000000
```

> ⚠️ The customer has **no navigation of its own** on success. Every screen in the
> sign-up path stops at "account created" and `AuthGate`'s `StreamBuilder` swaps
> the root widget. Pushing a route from inside the gate's subtree replaces the
> gate's own route and kills the auth listener — see the comment in
> `lib/screens/auth/onboarding_screen.dart`.

---

## 2. Stage 1 — Launch to the registration form

```mermaid
flowchart TD
    A(["App launch — <code>SplashScreen</code><br/>2 s · silent UpdateProvider check"]) --> B{"AuthGate<br/>existing session?"}

    B -- "No session" --> C{"has_seen_onboarding<br/>SharedPreferences?"}
    C -- "false — very first launch" --> D["OnboardingScreen<br/>3 slides · Skip / Get Started<br/>writes has_seen_onboarding = true"]
    C -- "true" --> E["AccountEntryScreen<br/>in-place mode = create"]
    D --> E

    E -- "\"Shop as customer?\"" --> F["CustomerRegisterScreen<br/>(this flow)"]
    E -- "\"Apply to sell\"" --> X1["SellerApplicationFlow<br/>→ seller side, out of scope"]
    E -- "\"Already have an account? Sign in\"" --> X2["Mode switches to signin IN PLACE<br/>video never restarts — see §5<br/>AuthProvider.login() + forgot link<br/>new-device code · biometrics · lockout"]

    style F fill:transparent,color:#000000,stroke:#000000
    style X1 fill:transparent,color:#000000,stroke:#000000
    style X2 fill:transparent,color:#000000,stroke:#000000
```

> `AccountEntryScreen` is **one screen with two modes**, not two routes. `create`
> (default) is the customer / seller choice; `signin` is the same widget with the
> form. Both buttons in create mode DO push routes; the sign-in switch does not.

---

## 3. Stage 2 — Account creation and e-mail confirmation

```mermaid
flowchart TD
    F["CustomerRegisterScreen"] --> F1["Form fields<br/>Full name · Email · Phone (optional)<br/>Birthday (required, 13+) · Gender (optional)<br/>Password + strength meter · Confirm password<br/>Terms & Privacy checkbox"]
    F1 --> F2{"Form valid AND<br/>terms accepted?"}
    F2 -- "No" --> F1
    F2 -- "Yes" --> F3{"AuthService.emailExists()<br/>address already registered?"}
    F3 -- "Yes" --> F4["Inline error on the email field<br/>(authErrorEmailExists)"] --> F1
    F3 -- "No" --> G["AuthProvider.signUpCustomer()<br/>metadata: role=customer · seller_status=none"]
    G --> G1{"Call threw?"}
    G1 -- "Yes" --> G2["AppErrorToast with mapped message<br/>stay on the form"] --> F1
    G1 -- "No" --> H["AuthService.signUp()<br/>supabase.auth.signUp + emailRedirectTo deep link<br/>(profile fields stashed in user metadata)"]
    H --> I{"Response carries a session?<br/>— i.e. is 'Confirm email' ON?<br/><b>ON by default</b>"}

    I -- "Session present<br/>(confirmation OFF — legacy path)" --> P["writeProfileFromMetadata()<br/>profiles row upserted immediately"]
    I -- "No session<br/>(confirmation ON)" --> J["pendingSignupVerification = email<br/>_currentUser / _profile = null<br/>NO profiles row yet (RLS needs a session)"]

    style P fill:transparent,color:#000000,stroke:#000000
    style J fill:transparent,color:#000000,stroke:#000000
```

### 3.1 The confirmation gate (only reached when there is no session yet)

```mermaid
flowchart TD
    J["pendingSignupVerification set<br/>AuthGate renders this screen<br/>BEFORE any session logic"] --> K["EmailOtpScreen<br/>purpose = signupVerification<br/>6-digit code already e-mailed by signUp"]

    K --> K1{"How does the user confirm?"}
    K1 -- "Types the 6-digit code" --> K2["AuthProvider.verifySignupEmail(code)<br/>otp.verifySignupCode → session established"]
    K1 -- "Taps the e-mail button<br/>solvision://auth/confirm" --> K3["Deep-link observer signs them in<br/>completeSignupFromEmailLink()<br/>(writes the row only if missing)"]
    K1 -- "Wrong / expired code" --> K4["Mapped code-specific copy<br/>Resend (60 s cooldown, rate limits surfaced)"] --> K
    K1 -- "\"Back to sign in\"" --> K5["cancelSignupVerification()<br/>auth user stays unconfirmed"] --> E["AccountEntryScreen"]

    K2 --> L["writeProfileFromMetadata()<br/>profiles row INSERT<br/>RLS policy: auth.uid() = id"]
    K3 --> L
    L --> M["_finishSignupSession(user, profile)<br/>clear pending · set _currentUser + _profile<br/>fire onLoginHook (FollowProvider)<br/>record this device as trusted<br/>save session in AccountManager"]

    M --> N(["✅ Account fully created<br/>customer can shop — no activation step"])

    style N fill:transparent,color:#000000,stroke:#000000
```

> The `profiles` row is **not** written by an `on auth.users` trigger — that is
> exactly why confirmation is deferred to this point. Either the code or the
> e-mail link supplies the session the row's INSERT policy requires.

---

## 4. Stage 3 — Foot-profile step, then AuthGate routing into the shell

```mermaid
flowchart TD
    M["Session established"] --> N["Navigator.pushReplacement →<br/>FootProfileOnboardingScreen<br/>(replaces the register/verify screen)"]
    P["Session established<br/>(confirmation OFF path)"] --> N
    N --> O{"Which path?<br/>all three are non-blocking"}

    O -- "Scan your feet with AR<br/>(primary · RECOMMENDED)" --> O1["FootInstructionsScreen → AR capture → FootResultsScreen<br/>saves foot_measurements + foot_profile_source = 'ar_scan'<br/>pushed ON TOP — fail/deny lands back here, never a dead end"]
    O -- "Enter size manually<br/>(secondary)" --> O2["EU size + width picker<br/>must pick a size first ('pick your size')<br/>save failure retries — foot_profile_source = 'manual'"]
    O -- "Skip for now<br/>(tertiary, plain text)" --> O3["foot_profile_source = 'skipped'<br/>fire-and-forget, instant — never blocks<br/>reminder banner invites them back"]

    O1 --> P2["_finish() → Navigator.popUntil(isFirst)"]
    O2 --> P2
    O3 --> P2

    P2 --> Q["AuthGate StreamBuilder<br/>receives the signedIn event"]
    Q --> R["AuthService.getProfile(user.id)<br/>12 s timeout · cached per user id"]
    R -- "error / null" --> R1["_ProfileErrorView<br/>Retry · Sign out<br/>(a late provider profile can still rescue it)"] --> Q
    R -- "profile loaded" --> S{"_routeByRole(profile)"}

    S -- "suspended == true" --> S1["SuspendedAccountScreen<br/>(session only cleared on tap)"]
    S -- "role == admin" --> S2["AdminShell — admin side"]
    S -- "role == seller AND approved" --> S3["SellerApprovedCelebrationScreen<br/>then SellerShell"]
    S -- "seller_status == pending" --> S4["PendingApprovalScreen"]
    S -- "else → role == customer" --> T{"MFA step-up needed?<br/>session AAL1 AND a verified TOTP factor"}

    T -- "Yes" --> T1["MfaVerifyScreen<br/>on success the session upgrades to AAL2<br/>+ ensureDeviceTrusted()"] --> T
    T -- "No — the normal customer case" --> U(["✅ CustomerShell<br/>PageView + SoleBottomNav"])

    style U fill:transparent,color:#000000,stroke:#000000
    style S1 fill:transparent,color:#000000,stroke:#000000
    style S3 fill:transparent,color:#000000,stroke:#000000
    style S4 fill:transparent,color:#000000,stroke:#000000
```

> A **brand-new** customer signup normally skips every gate here: no MFA factor is
> enrolled yet, the device was recorded as trusted during `_finishSignupSession`,
> and `role = 'customer'` falls through to the final `else`.

---

## 5. Returning-user sign-in — the gates a new customer skips

```mermaid
flowchart TD
    S0["AccountEntryScreen signin mode<br/>email + password, empty/short flagged first"] --> S1{"Forgot password?"}
    S1 -- "Yes" --> S2["resetPasswordForEmail redirect solvision://auth/recovery<br/>link opens app with short-lived recovery session<br/>AuthGate renders ResetPasswordScreen ahead of all routes<br/>applyRecoveredPassword clears it — stays signed in"]
    S1 -- "No" --> S3{"login() success?"}
    S3 -- "No" --> S4["SAME message for bad email or password<br/>AppErrorToast, fields NOT cleared<br/>too many tries → LockoutOverlay"]
    S3 -- "Yes — force-signout first, then signInWithPassword" --> S5{"New device?"}
    S5 -- "No" --> S6["Session live"]
    S5 -- "Yes" --> S7["AAL1 withdrawn → EmailOtpScreen newDeviceChallenge<br/>sendError shown on first frame if mail failed<br/>Resend or cancel — verify records device trusted"]
    S7 --> S6
    S6 --> S8["First success offers biometric enrol (once, modal)<br/>later: OR-divider pill only if supported + enrolled"]
    S8 --> S9["Same AuthGate tail as §4: profile retry → suspended → role → MFA"]

    style S4 fill:transparent,color:#000000,stroke:#000000
```

> Password login never reveals whether the e-mail exists (`invalid_credentials`
> and `user_not_found` share one message). `login()` resets
> `_currentUser`/`_profile` first so a retry never flashes the old account.

---

## 6. Stage 4 — CustomerShell: the four tabs

```mermaid
flowchart TB
    Shell["CustomerShell<br/>PageView + KeepAlivePage + HideOnScrollBottomBar<br/>ActiveTab publishes the visible index"]

    Shell --> T0["Tab 0 — Home<br/>CustomerHomeScreen (hideAppBar: true)<br/>no AppBar · full-bleed hero"]
    Shell --> T1["Tab 1 — Store<br/>StoreScreen (hideAppBar: true)<br/>AppBar 'Stores' + CartIconButton"]
    Shell --> T2["Tab 2 — Notifications<br/>NotificationsScreen (hideAppBar: true)<br/>AppBar 'Notifications' + 'Mark all read'<br/>unread badge from NotificationProvider"]
    Shell --> T3["Tab 3 — Profile<br/>ProfileScreen (hideAppBar: true, tabIndex: 3)<br/>AppBar 'My Profile' + Settings action"]

    T0 --> T0a["Product detail · search · on-sale / size listings<br/>cart · foot-size flows · AR try-on"]
    T1 --> T1a["Store profile · collection · rate store"]
    T2 --> T2a["Order / message notifications<br/>tap → the relevant screen"]
    T3 --> T3a["My orders · addresses · reviews<br/>reservations · inbox · SettingsScreen"]

    style Shell fill:transparent,color:#000000,stroke:#000000
```

> Labels are `Home`, `Store`, `Notifications`, `Profile` for `roleCustomer` in
> `lib/widgets/sole_bottom_nav.dart`. Each visited tab stays mounted
> (`KeepAlivePage`) — `initState` does not re-run when switching back.

---

## 7. Decision points worth knowing

| # | Decision | Where | What happens |
|---|---|---|---|
| 0 | Existing session? | `AuthGate` + `SplashScreen` update check | Session present → profile fetch → shell directly, no form |
| 1 | Onboarding seen? | `_FirstTimeOrLoginRouter` (auth_gate.dart) | 3-slide intro once per install; written to `has_seen_onboarding` |
| 2 | Create vs. sign in | `AccountEntryScreen._switchMode` | In-place state change, **not** a route push (the video hero never restarts) |
| 3 | Email already registered? | `AuthService.emailExists()` before signUp | Inline field error, no account created, no e-mail sent |
| 4 | Terms accepted? | `CustomerRegisterScreen._submit` | Blocks submit with a toast (independent of form validation) |
| 5 | "Confirm email" ON? | `AuthService.signUp` → `response.session == null` | Yes (default) → OTP screen owns the hand-off; No → immediate profile write + auto-login |
| 6 | Code vs. e-mail link | `EmailOtpScreen` / `DeepLinkService.isAuthConfirmLink` | Both end at `writeProfileFromMetadata()`; the link path is the cold-start race the provider profile watcher exists for |
| 7 | Foot profile path | `FootProfileOnboardingScreen` | AR scan (fail returns here) / manual (must pick size) / skip (instant) — all land in the shell |
| 7b | Give up on the code? | `cancelSignupVerification()` | Back to sign in; auth user stays unconfirmed, asked again next time |
| 7c | Forgot password? | `resetPasswordForEmail` → `ResetPasswordScreen` | Recovery session first, shell only after new password |
| 7d | Same-error rule? | `friendlyAuthErrorMessage` | Bad email and bad password read identically; fields kept |
| 7e | Lockout? | `pendingLockout` → `LockoutOverlay` | Too many tries locks the screen for a while |
| 7f | New device? | `pendingDeviceChallenge` | Code mailed; sendError shown on the OTP first frame, not silent |
| 7g | Biometrics? | `BiometricService` + secure vault | Pill only if supported + enrolled; offered once after first success; logout clears vault, keeps declined flag |
| 8 | Profile fetch failed? | `AuthGate` `FutureBuilder` | Retry screen with a Sign-out escape hatch; a late profile from `AuthProvider` short-circuits it |
| 9 | Role / status routing | `AuthGate._routeByRole` | admin → AdminShell · approved seller → SellerShell · pending → PendingApprovalScreen · **else → CustomerShell** |
| 10 | MFA step-up | `_MfaGate` | Only for AAL1 + verified TOTP factor; a new customer has neither |

---

## 8. File map

| Stage | File |
|---|---|
| Splash + silent update check | `lib/screens/auth/splash_screen.dart` |
| Auth decision tree, OTP gates, role routing, error view | `lib/screens/auth_gate.dart` |
| First-launch onboarding | `lib/screens/auth/onboarding_screen.dart` |
| Merged create / sign-in front door | `lib/screens/auth/account_entry_screen.dart` |
| Customer registration form | `lib/screens/auth/customer_register_screen.dart` |
| 6-digit e-mail code screen (signup + new device) | `lib/screens/shared/email_otp_screen.dart` |
| Post-signup foot-profile step | `lib/screens/auth/foot_profile_onboarding_screen.dart` |
| State: signUpCustomer / verifySignupEmail / _finishSignupSession | `lib/providers/auth_provider.dart` |
| State: routing, device trust, lockout, MFA | `lib/providers/auth_provider.dart`, `lib/services/mfa_service.dart` |
| Supabase signUp + profiles write | `lib/services/auth_service.dart` |
| The 4-tab shell | `lib/screens/customer/customer_shell.dart` |
| Tab bar labels/icons | `lib/widgets/sole_bottom_nav.dart` |

---

## 9. Not covered here

- **Returning-user sign-in internals** — see §5 above plus
  `docs/AI/EMAIL_OTP_AND_DEVICE_TRUST_ARCHITECTURE.md` and
  `docs/AI/SIGN_IN_ARCHITECTURE.md` (biometric vault, DismissOnSignIn, AnimatedSwitcher fade).
- **Seller application** — `lib/screens/auth/seller_application_flow.dart` and
  `docs/AI/SELLER_ARCHITECTURE_GRAPH.md`.
- **Admin side**, and everything past the four tabs (cart → checkout → order).

> ⚠️ `docs/SIGNUP_ARCHITECTURE.md` predates the split registration screens: it
> still describes a single `AuthProvider.signUp(..., applyAsSeller:)` form and a
> success SnackBar. The current code is `signUpCustomer` + the separate seller
> flow, and the register screen hands off to `FootProfileOnboardingScreen`
> instead of showing a SnackBar.
