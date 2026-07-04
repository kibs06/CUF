# SoleVision — Auth Debug Reference

This folder contains **snapshots** of the core authentication files as of **June 29, 2026**, after the account-switching freeze bug was fixed.

These files are kept here for reference only — they are **not** the source of truth. The actual source files live in `lib/`.

---

## Why These Files Were Copied

During the debugging session, we identified and fixed **5 root causes** of a high-severity bug: the app freezing when a seller or customer logs out and logs in with a different account.

The fixes touched every file in the auth flow, so these copies serve as a documented checkpoint of the corrected state.

---

## Files

| File | Responsibility | Key Fixes Applied |
|------|---------------|-------------------|
| `auth_provider.dart` | Auth state: `_currentUser`, `_profile`, `_isLoading`, `_errorMessage` | State fully cleared on `login()` and `logout()`; `try/catch/finally` guarantees `_isLoading` resets |
| `auth_service.dart` | Supabase Auth calls: `signIn`, `signOut`, `getProfile` with retry logic | Force signs out existing session before new `signIn`; retry counter uses local variable (no stale state) |
| `auth_gate.dart` | `StreamBuilder` routing by role after auth state changes | Explicit `signedOut`/`signedIn` handling; profile cache reset on sign-out; 12-second profile fetch timeout; offline detection via `InternetAddress.lookup` |
| `login_screen.dart` | Login form UI, button state, error display | Button only disabled on `isLoading`; error shown via SnackBar; no manual `Navigator.push` after login |
| `biometric_service.dart` | Biometric auth, credential storage via `FlutterSecureStorage` | `clearCredentials()` called on logout to prevent Account A's credentials from interfering with Account B |

---

## Bug Summary

| Cause | Fix |
|-------|-----|
| Stale `AuthProvider` state between sessions | Reset all state at top of `login()` and `logout()` |
| Lingering Supabase session blocking new sign-in | `AuthService.signIn()` calls `signOut()` if session exists |
| Profile fetch retry counter not resetting | Uses local `attempt` variable in for loop (no instance state) |
| Biometric credentials from previous account interfering | `BiometricService.clearCredentials()` called in `AuthProvider.logout()` |
| `_isLoading` stuck `true` after failed login | `try/catch/finally` in `login()` guarantees reset |

---

## Additional Improvements

- **Profile fetch timeout** (12s) — prevents users from being stuck on loading screen forever
- **Offline detection** — `InternetAddress.lookup('google.com')` check shows "No Internet Connection" screen with retry button instead of spinning indefinitely

---

## How to Use

These files are **read-only reference copies**. If you need to make changes, edit the actual source files in `lib/`. After making changes, you can update these copies by running the copy commands again.

> **Note:** These snapshots will drift from the live codebase over time. They are intended as a debugging reference, not a sync mechanism.
