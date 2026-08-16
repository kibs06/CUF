# ⚠️⛔ DEV MODE (UI-ONLY SKIP) — REMOVE BEFORE RELEASE ⛔⚠️

> **THIS IS TEST SCAFFOLDING. It must be deleted before the app ships to
> real users.** A tester can enable it with a hidden swipe code, and while
> enabled every signup form is bypassed and a "DEV MODE" chip is shown.
>
> **Updated Aug 2026 — the seller flow's final Submit now creates a REAL
> seller application** (a real Supabase account with `seller_status =
> pending`) so the dev lands on PendingApprovalScreen and can test the FULL
> admin loop — approve in the console → in-app notification + **Gmail via
> the send-approval-email edge function**. Everything else stays UI-only.
> See "Real-account dev submit" below.
>
> **Also tracked on the task board:** `obsidian/Tasks.md` → 🔜 Backlog.

---

## What it is

A **UI-only developer shortcut** for walking the customer + seller signup
flows without filling forms or touching the backend:

- **Unlock:** on the "Create your account" screen (`AccountEntryScreen`),
  swipe **2 up, 2 down, 2 right, 2 left** (`↑ ↑ ↓ ↓ → → ← ←`). A SnackBar
  confirms "Developer mode ON". Swiping the same code again turns it off.
- **While ON:** every Continue / Create-account / Submit button in the
  customer + seller flows **skips validation and advances**, and a small
  **"DEV MODE"** chip is pinned in the top-right of every auth screen.
- **Quick toggle OFF from anywhere:** the "DEV MODE" chip itself is
  tappable — tap it in any flow (customer register, any seller step, foot
  onboarding, or the entry screen) to turn dev mode off immediately
  (SnackBar confirms). It can only be visible while dev mode is on, so a
  tap always means off; re-enabling still requires the swipe code on the
  entry screen.
- **Almost no backend writes:** the customer "submit" jumps straight to
  `FootProfileOnboardingScreen` with no account created. The ONE exception
  is the seller final "Submit" — see **Real-account dev submit** below.
  Everything else (all Continues, all other steps) is UI-only.

## Real-account dev submit (seller Submit only)

When dev mode is ON, the seller flow's final **Submit application** button
creates a **real Supabase account with a normal PENDING application** — the
same `AuthProvider.signUpSeller` → `AuthService.completeSellerApplication`
path the real flow uses, so `seller_status = pending` and `role` stays
`customer`. `AuthGate` then routes the dev to the real
`PendingApprovalScreen`, and the **entire admin loop is exercised**: the
admin approves in the console (Flutter `SellerApprovalScreen` or the
admin-portal), the DB trigger writes the in-app `approval` notification, and
the `send-approval-email` edge function emails the applicant's Gmail
straight through Gmail SMTP (the app's own Gmail account + App Password —
no third-party provider, no domain).

- Implemented by `_submit()` in `seller_application_flow.dart` (dev-mode
  branch): builds a `SellerApplicationData` with dev defaults (email
  `dev.seller@test.com` / password `devpass123` when the fields were left
  empty, store `Dev Store`, tag `local`, location `Carcar City, Cebu`) and
  calls `AuthProvider.signUpSeller(data)` — exactly like the real submit,
  minus the document uploads (all doc paths are null, so the admin review
  shows them as missing, which is fine for testing the approval + email).
- Repeated runs reuse the same account: `ensureUser` signs back in when the
  dev email already exists, so the dev lands on the same pending account
  each time.
- **To test the Gmail notification:** sign in to the admin console with an
  admin account, approve the dev application, and the applicant's email
  address receives the approval email (requires the Gmail setup —
  `GMAIL_SENDER` + `GMAIL_APP_PASSWORD` secrets + the edge function
  deployed).

## How it works

| Piece | File | Role |
|-------|------|------|
| Controller + code | `lib/utils/dev_mode.dart` | `DevMode` singleton (`ValueNotifier<bool>`), `devModeUnlockCode` (`↑↑↓↓→→←←`), `classifySwipe()` (delta → direction), `DevModeSwipeTracker` (sliding window over the last 8 swipes) |
| Unlock gesture | `lib/widgets/auth/dev_mode_swipe_detector.dart` | Raw `Listener` wrapping the entry screen body — observes pointer deltas, never competes with scrollables in the gesture arena |
| Indicator + toggle | `lib/widgets/auth/dev_mode_badge.dart` | `DevModeBadge` chip, renders inline and collapses to nothing when off; **tapping it toggles dev mode OFF** from any screen with a confirmation SnackBar |
| Entry screen | `lib/screens/auth/account_entry_screen.dart` | Body wrapped in `DevModeSwipeDetector`; badge in the header row |
| Shared auth chrome | `lib/widgets/auth/signup_scaffold.dart` | Badge in the top bar (covers customer + seller + foot-profile screens) |
| Customer skip | `lib/screens/auth/customer_register_screen.dart` | `_submit()` → `DevMode.instance.isEnabled` → pushReplacement `FootProfileOnboardingScreen` |
| Seller skips | `lib/screens/auth/seller_application_flow.dart` | 4 guards: `_continueFromAccount`, identity Continue, community Continue, `_submit` (**real-account dev submit** — creates a real PENDING seller application via `signUpSeller` so AuthGate routes to PendingApprovalScreen and the admin approval → Gmail loop runs) |
| Pending-screen preview | `lib/screens/auth/pending_approval_screen.dart` | `devPreview` flag: shows a "DEV PREVIEW — no account was created" banner and defaults every "What we received" row to checked so the dev sees the real-appearance state |

**Detection notes:** the tracker keeps the last 8 swipes (sliding window), so
an accidental scroll swipe mid-sequence doesn't reset progress. Swipes shorter
than 48 logical px (or diagonal) don't count. Only one finger is tracked.
Dev mode is a session-global singleton — once enabled it stays on across
screens until the app is restarted, the code is swiped again on the entry
screen, or the "DEV MODE" chip is tapped in any flow.

## 🧹 Removal checklist (do all of these before release)

1. **Delete** `lib/utils/dev_mode.dart`
2. **Delete** `lib/widgets/auth/dev_mode_swipe_detector.dart`
3. **Delete** `lib/widgets/auth/dev_mode_badge.dart`
4. **Delete** `docs/AI/DEV_MODE_ARCHITECTURE.md`
5. **Revert** `lib/screens/auth/account_entry_screen.dart`:
   - remove the `dev_mode_badge` / `dev_mode_swipe_detector` imports
   - unwrap the body `Stack` from `DevModeSwipeDetector`
   - restore the header's `Text('CUFMAI')` (remove the `Row` + `Spacer` +
     `DevModeBadge()`)
6. **Revert** `lib/widgets/auth/signup_scaffold.dart`:
   - remove the `dev_mode_badge` import
   - remove `const DevModeBadge(),` from `_buildTopBar`
7. **Revert** `lib/screens/auth/customer_register_screen.dart`: remove the
   `dev_mode` import + the `DevMode.instance.isEnabled` block in `_submit`.
8. **Revert** `lib/screens/auth/seller_application_flow.dart`: remove the
   `dev_mode` + `seller_application_data` imports + all four
   `DevMode.instance.isEnabled` guards (the `_submit` dev branch creates a
   real pending account — restoring the branch to the pre-dev form also
   restores the real submit validation + `_controller.submit(...)` call).
9. **Revert** `lib/screens/auth/pending_approval_screen.dart`: remove the
   `dev_mode` import, the `devPreview` flag + its checked-by-default rows,
   and the "DEV PREVIEW" banner.
10. **Clear the task-board entry** in `obsidian/Tasks.md` and the one-line
   note in `obsidian/MOCs/00 - Auth & Accounts.md` / `docs/AI/SIGNUP_ARCHITECTURE.md`.

A grep to confirm zero references afterwards:

```
rg -n "DevMode|dev_mode|DEV MODE" lib/ docs/AI/ obsidian/
```

---

*Written for the team: this file intentionally lives in the docs the AI
agents read, so the removal is impossible to miss.*
