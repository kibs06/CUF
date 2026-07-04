# Fix Spec v6: False "No Longer Available" Error + Cart Not Cleared from DB

**Date:** July 3, 2026  
**Status:** ✅ Implemented  
**Predecessor:** `FIX_false_error_and_cart_clear_v5.md` (v5 — claimed "already implemented" but bugs still occurring)

---

## 1. Summary

Both bugs from the v5 spec were still occurring in production despite v5 being marked as "✅ Already implemented." Independent re-verification confirmed the actual root causes were different from what v5 identified.

---

## 2. Bug 1: False "is no longer available" error

### Root Cause

**`_itemValidations` in `checkout_screen.dart` was never cleared** — not at the start of a new validation pass, not when items were removed from the cart, and not on successful order placement.

The failure chain:
1. User adds Item A to cart → goes to checkout → `_validateCart()` runs → `_itemValidations` gets an entry for Item A
2. User goes back, removes Item A from cart, adds Item B
3. User returns to checkout → `_validateCart()` runs → new entry for Item B is **appended** to `_itemValidations`, but the **stale entry for Item A persists**
4. `_canSubmitOrder()` iterates ALL entries in `_itemValidations` — if Item A's stale entry has `isAvailable: false`, the order button is permanently disabled
5. Even if Item A's entry has `isAvailable: true`, duplicate/stale entries can cause incorrect `insufficientStock` calculations

The v5 spec assumed the root cause was either:
- The validation reading from `product_variants.stock` instead of `inventory.stock` (already fixed in v3), or
- A stale error state from a previous validation pass

Neither was the actual cause. The validation code itself (`validateCartForCheckout()`) was correct — it properly reads from `inventory` as the authoritative source. The bug was purely in the **UI state management** of `_itemValidations`.

### Fix

1. **Clear `_itemValidations` at the start of `_validateCart()`** — prevents stale entries from accumulating
2. **Filter validation results** to only include items still present in the cart after validation completes
3. **Clear `_itemValidations` on empty cart** — handles the case where all items were removed

### Files Changed

- `lib/screens/customer/checkout_screen.dart` — `_validateCart()` method

---

## 3. Bug 2: Cart items not deleted from DB after order

### Root Cause

`_submitCheckout()` called `cart.removeFromCart(key)` for each ordered item. `CartProvider.removeFromCart()` removes the item locally, then fires a background server delete via `_syncRemoveFromServer(serverId)` — but **only if `server_id` is not null**.

The problem: `server_id` is set asynchronously by `_syncAddToServer()` after the local add. If the user proceeds to checkout quickly (before the background sync completes), `server_id` is still `null`, and the server-side DELETE is silently skipped. The local UI clears, but the Supabase `cart_items` rows remain.

On next login, device switch, or app restart, `_syncFromServer()` fetches from Supabase and the "ordered" items reappear in the cart.

The v5 spec identified this as "low probability in normal usage" but it was the actual production bug. The `removeFromCart()` pattern is fundamentally unreliable for post-order cleanup because it depends on an async field (`server_id`) that may not be set.

### Fix

1. **Added `CartService.removeItems(userId, cartItemIds)`** — a new method that deletes specific cart items by their Supabase row IDs, scoped to user. This is called directly from the checkout screen, bypassing the provider's `server_id` dependency.
2. **`_submitCheckout()` now awaits the server-side delete** before navigating to the confirmation screen — same pattern that fixed the product deletion bug (missing `await`).
3. **Scoped to only ordered items** — only the selected items' `server_id` values are passed to `removeItems()`, so unselected items (e.g., from other stores) are preserved.

### Files Changed

- `lib/services/cart_service.dart` — new `removeItems()` method
- `lib/screens/customer/checkout_screen.dart` — `_submitCheckout()` method

---

## 4. Why v5 Was Incorrect

The v5 spec (`FIX_false_error_and_cart_clear_v5.md`) concluded:

> **Both asks from the v5 spec are already implemented.** No code changes are needed for the core functionality.

This was wrong because:

1. **v5's analysis of `_submitCheckout()` was based on reading the code, not testing it.** The analysis correctly identified that `cart.removeFromCart(key)` is called after order success, but incorrectly assumed this would reliably delete from Supabase. It didn't account for the `server_id` race condition.

2. **v5's analysis of the false banner was based on a hypothesis about stale navigation state** (user returning to checkout after a previous order). The actual bug was simpler — `_itemValidations` never being cleared during a single checkout session.

3. **v5 recommended "rebuild and retest"** instead of implementing fixes. The bugs were real and reproducible; they just hadn't been properly traced to their actual root causes.

---

## 5. Verification

### Bug 1 — False error
1. Add an in-stock item to cart
2. Go to checkout → should show no error banners
3. Go back, remove the item, add a different in-stock item
4. Return to checkout → should show no error banners (old item's stale validation is gone)
5. Place order → should succeed with no false error

### Bug 2 — Cart clearing
1. Add items to cart
2. Go to checkout, place order → order succeeds
3. Kill the app completely
4. Reopen app, go to cart → cart should be empty (ordered items were deleted from Supabase)
5. Alternatively: query Supabase directly:
   ```sql
   SELECT * FROM cart_items WHERE user_id = 'YOUR_USER_ID';
   ```
   Should return 0 rows after a successful order.

### Regression — Out-of-stock items still blocked
1. Add an item that has 0 stock in `inventory`
2. Go to checkout → should show "is no longer available" banner
3. "Complete Order" button should be disabled
4. The error banner should NOT appear for items that genuinely have stock

---

## 6. Data Verification Queries

See `docs/VERIFY_CHECKOUT_FIX_QUERIES.sql` for the full set of SQL queries to run against the live database, including:
- Step 2: Non-numeric sizes that break trigger normalization
- Step 3: Orphaned inventory rows
- Step 5: Duplicate product_variants rows
- Step 7: Cart clearing verification
- Step 8: Order items size format audit

---

*Fix spec v6 — July 3, 2026. Supersedes v5 which was incorrectly marked as "already implemented."*
