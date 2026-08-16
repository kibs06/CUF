# ⚠️⛔ DEV MODE (UI-ONLY SKIP) — REMOVE BEFORE RELEASE ⛔⚠️

> **THIS IS TEST SCAFFOLDING. It must be deleted before the app ships to
> real users.** A tester can enable it with a hidden swipe code, and while
> enabled every signup form is bypassed (nothing is actually created — but
> the flow is fully skippable and a "DEV MODE" chip is shown).
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
- **No backend writes, ever:** no Supabase account, profile, upload or
  application is created. The customer "submit" jumps straight to
  `FootProfileOnboardingScreen`; the seller final "Submit" pops back with a
  fake "Application submitted!" SnackBar. This is the **UI-only contract**
  chosen by the developer — do not turn it into a real-account mode without
  asking.

## How it works

| Piece | File | Role |
|-------|------|------|
| Controller + code | `lib/utils/dev_mode.dart` | `DevMode` singleton (`ValueNotifier<bool>`), `devModeUnlockCode` (`↑↑↓↓→→←←`), `classifySwipe()` (delta → direction), `DevModeSwipeTracker` (sliding window over the last 8 swipes) |
| Unlock gesture | `lib/widgets/auth/dev_mode_swipe_detector.dart` | Raw `Listener` wrapping the entry screen body — observes pointer deltas, never competes with scrollables in the gesture arena |
| Indicator + toggle | `lib/widgets/auth/dev_mode_badge.dart` | `DevModeBadge` chip, renders inline and collapses to nothing when off; **tapping it toggles dev mode OFF** from any screen with a confirmation SnackBar |
| Entry screen | `lib/screens/auth/account_entry_screen.dart` | Body wrapped in `DevModeSwipeDetector`; badge in the header row |
| Shared auth chrome | `lib/widgets/auth/signup_scaffold.dart` | Badge in the top bar (covers customer + seller + foot-profile screens) |
| Customer skip | `lib/screens/auth/customer_register_screen.dart` | `_submit()` → `DevMode.instance.isEnabled` → pushReplacement `FootProfileOnboardingScreen` |
| Seller skips | `lib/screens/auth/seller_application_flow.dart` | 4 guards: `_continueFromAccount`, identity Continue, community Continue, `_submit` (fake submitted SnackBar + **pushes `PendingApprovalScreen` as a DEV PREVIEW** — no account exists, so AuthGate can't route there) |
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
   `dev_mode` + `pending_approval_screen` imports + all four
   `DevMode.instance.isEnabled` guards (including the dev-mode `navigator.push`
   of `PendingApprovalScreen` in `_submit`).
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
