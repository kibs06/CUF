# SoleVision — docs/debug (Debug Reference)

This folder contains **historical debugging documentation and setup SQL scripts**
from past sessions. Nothing here is the source of truth — the actual source files
live in `lib/`.

> **Note (2026-08-09):** The snapshot `.dart` copies of source files that used to
> live here were **removed** — they drifted from the live codebase, broke
> `flutter analyze` (733 errors from broken relative imports), and confused
> contributors. If you need the old snapshots, they are fully recoverable from
> git history (`git log -- docs/debug`).

---

## What's still here

| File | Purpose |
|------|---------|
| `inventory_backfill.sql` | Backfill `inventory` from `product_variants` (referenced by setup docs) |
| `cart_items_migration.sql` | Legacy cart-items table setup |
| `CUSTOMER_ORDER_PROCESS.md` | Customer order flow reference |
| `REVIEW_INSERT_PAYLOAD_AND_ORDER_STATUSES.md` | Order status + review payload reference |
| `SELLER_ORDER_CONFIRMATION_ARCHITECTURE.md` | Seller order confirmation architecture |
| `SESSION_LOG_JUNE_30_2026.md` | Session log (historical) |
| `SESSION_LOG_JULY_2_2026.md` | Session log (historical) |
| `SoleVision_Project_Documentation2.md` | Older project documentation (historical) |

---

## Historical: Auth Debug Reference (June 29, 2026)

The snapshot files this section once documented were removed on 2026-08-09; the
record of what was fixed is preserved here.

During the debugging session, we identified and fixed **5 root causes** of a
high-severity bug: the app freezing when a seller or customer logs out and logs
in with a different account.

| Cause | Fix |
|-------|-----|
| Stale `AuthProvider` state between sessions | Reset all state at top of `login()` and `logout()` |
| Lingering Supabase session blocking new sign-in | `AuthService.signIn()` calls `signOut()` if session exists |
| Profile fetch retry counter not resetting | Uses local `attempt` variable in for loop (no instance state) |
| Biometric credentials from previous account interfering | `BiometricService.clearCredentials()` called in `AuthProvider.logout()` |
| `_isLoading` stuck `true` after failed login | `try/catch/finally` in `login()` guarantees reset |

**Additional improvements:** 12-second profile fetch timeout (prevents stuck
loading), and offline detection (`InternetAddress.lookup`) with a "No Internet
Connection" retry screen.
