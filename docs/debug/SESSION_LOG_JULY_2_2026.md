# SoleVision — Session Log: June 30 – July 2, 2026

## Overview

This document details all bug fixes, improvements, and code changes made across
the June 30 and July 2, 2026 development sessions. Six bugs were resolved
(authentication, product inventory, cart rendering, and layout), along with
several UX improvements.

---

## Table of Contents

1. [Session 1 — June 30, 2026](#session-1--june-30-2026)
   - [Bug #1: Login Freeze When Switching Accounts](#bug-1-login-freeze-when-switching-accounts)
   - [Bug #2: Navigator Stack Conflict on Account Switch](#bug-2-navigator-stack-conflict-on-account-switch)
   - [Bug #3: Product Size Selector Empty — Inventory Never Written](#bug-3-product-size-selector-empty--inventory-never-written)
   - [Improvement #1: Profile Fetch Timeout](#improvement-1-profile-fetch-timeout)
   - [Improvement #2: Offline Detection](#improvement-2-offline-detection)
   - [Improvement #3: Size Selector Loading Skeleton](#improvement-3-size-selector-loading-skeleton)
2. [Session 2 — July 2, 2026](#session-2--july-2-2026)
   - [Bug #4: Product Variants Missing from Main Query](#bug-4-product-variants-missing-from-main-query)
   - [Bug #5: Poor Error Messages on Size Selector](#bug-5-poor-error-messages-on-size-selector)
   - [Bug #6: Blank White Cart Screen (RenderBox Layout Error)](#bug-6-blank-white-cart-screen-renderbox-layout-error)
3. [SQL Migrations](#sql-migrations)
4. [All Files Modified](#all-files-modified)
5. [Testing Checklist](#testing-checklist)
6. [Design System Reference](#design-system-reference)

---

# Session 1 — June 30, 2026

## Bug #1: Login Freeze When Switching Accounts

### Severity: Critical

### Symptom

When a seller or customer logs out and attempts to log in with a different
account, the app freezes on the login screen:

- No error message is shown
- No navigation occurs
- The login button appears disabled or unresponsive
- The only recovery is to fully close and reopen the app

This does **not** happen on a fresh app launch — only when switching from one
account to another within the same session.

### Root Causes (5 total)

| # | Cause | File |
|---|-------|------|
| 1 | Stale `AuthProvider` state — `_currentUser` and `_profile` not cleared before next `signIn()` | `auth_provider.dart` |
| 2 | Supabase Auth stream not re-emitting correctly for `signedOut → signedIn` transition | `auth_gate.dart` |
| 3 | Profile fetch retry counter not resetting between sessions | `auth_service.dart` |
| 4 | Biometric credentials from Account A interfering with Account B's login | `biometric_service.dart` |
| 5 | `_isLoading` flag stuck `true` — login button permanently disabled | `auth_provider.dart` |

### Fixes Applied

#### Fix 1: `lib/providers/auth_provider.dart`

**`signOut()`** — Clears all state before calling Supabase:

```dart
Future<void> signOut() async {
  // Clear all local state FIRST
  _currentUser = null;
  _profile = null;
  _errorMessage = null;
  _isLoading = false;
  notifyListeners();

  // Clear biometric credentials so they don't bleed into the next session
  await BiometricService.instance.clearCredentials();
  await AuthService.instance.signOut();
}
```

**`login()`** — Resets everything at the very top, uses `try/catch/finally`:

```dart
Future<bool> login(String email, String password) async {
  // Reset ALL state at the very start
  _currentUser = null;
  _profile = null;
  _errorMessage = null;
  _isLoading = true;
  notifyListeners();

  try {
    final res = await _auth.signIn(email: email, password: password);
    _currentUser = res['user'];
    _profile = res['profile'];
    return true;
  } catch (e) {
    _errorMessage = e.toString().replaceAll('Exception: ', '');
    return false;
  } finally {
    // ALWAYS reset _isLoading — even if an exception is thrown mid-flow
    _isLoading = false;
    notifyListeners();
  }
}
```

#### Fix 2: `lib/services/auth_service.dart`

**`signIn()`** — Forces sign-out of any existing session before signing in:

```dart
Future<Map<String, dynamic>> signIn({
  required String email,
  required String password,
}) async {
  // Force sign-out any existing session — critical when switching accounts.
  final existing = _client.auth.currentSession;
  if (existing != null) {
    await _client.auth.signOut();
  }

  final response = await _client.auth.signInWithPassword(
    email: email.trim(),
    password: password,
  );
  // ...
}
```

**Why this is the primary fix:** Without clearing the lingering session, Supabase
rejects the new sign-in silently, leaving the app stuck with `_isLoading = true`.

#### Fix 3: `lib/screens/auth_gate.dart`

**`_FirstTimeOrLoginRouter`** — Returns widgets directly instead of using
`Navigator.pushReplacement` (see Bug #2 below for full details).

**`PendingApprovalScreen`** — Uses `context.read<AuthProvider>().logout()` instead
of `AuthService.instance.signOut()` for full state cleanup.

#### Fix 4: `lib/services/biometric_service.dart`

**`clearCredentials()`** — Already existed and was already called inside
`AuthProvider.signOut()`. No additional changes needed.

#### Fix 5: Login button state

Already correctly implemented — button `onPressed` is `null` only when
`auth.isLoading == true`. `auth.errorMessage` is displayed via SnackBar.

### Interaction Map

| If you skip... | What still breaks |
|---|---|
| Fix 1 (AuthProvider reset) | `_isLoading` stays `true`, button stays disabled |
| Fix 2 (AuthService session clear) | Supabase rejects the new sign-in silently |
| Fix 3 (AuthGate routing) | Stream emits but UI doesn't re-route |
| Fix 4 (biometric clear) | Secure storage credentials from Account A corrupt flow |
| Fix 5 (button state) | No feedback, button appears stuck |

**All 5 fixes must be applied together.**

---

## Bug #2: Navigator Stack Conflict on Account Switch

### Severity: Critical

### Symptom

After logging out and logging in with a different account, the app stays on the
login screen even though the auth stream has emitted `signedIn` and the correct
shell has been rendered underneath.

### Root Cause

`_FirstTimeOrLoginRouter` used `Navigator.pushReplacement` to push `LoginScreen`
onto the navigator stack. This placed `LoginScreen` on a **separate stack layer**
on top of `AuthGate`, disconnected from the `StreamBuilder`. When the stream
emitted `signedIn`, `AuthGate` rebuilt with the correct shell underneath, but
`LoginScreen` was never popped — it remained on top, blocking the shell.

```
Step 1: User logs out → Stream emits signedOut → AuthGate rebuilds
Step 2: _FirstTimeOrLoginRouter pushes LoginScreen via Navigator.pushReplacement
Step 3: LoginScreen is now ON TOP of AuthGate — disconnected from StreamBuilder
Step 4: User logs in → Stream emits signedIn → AuthGate rebuilds correctly
Step 5: BUT LoginScreen is still on top → App appears frozen
```

### Fix: `lib/screens/auth_gate.dart`

Replaced `_FirstTimeOrLoginRouter` to return widgets directly from `build()`:

```dart
class _FirstTimeOrLoginRouterState extends State<_FirstTimeOrLoginRouter> {
  bool? _hasSeenOnboarding;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _hasSeenOnboarding = prefs.getBool('has_seen_onboarding') ?? false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hasSeenOnboarding == null) return const _LoadingScreen();

    // Return directly — do NOT use Navigator.pushReplacement
    if (!_hasSeenOnboarding!) return const OnboardingScreen();
    return const LoginScreen();
  }
}
```

**Why this works:** When `LoginScreen` is returned directly from `build()`, it is
part of `AuthGate`'s widget subtree. When the stream emits `signedIn`, `AuthGate`
rebuilds and naturally replaces `LoginScreen` with the correct shell — no manual
`Navigator.pop()` needed.

### Secondary Fix: `PendingApprovalScreen` Logout

Changed from `AuthService.instance.signOut()` (bypasses `AuthProvider`) to
`context.read<AuthProvider>().logout()` for full state cleanup:

```dart
// Before:
Future<void> _logout() => AuthService.instance.signOut();

// After:
onPressed: () => context.read<AuthProvider>().logout(),
```

---

## Bug #3: Product Size Selector Empty — Inventory Never Written

### Severity: Critical

### Symptom

Customer product detail screen shows the "Select Size (EU)" label but no size
chips underneath. "Add to Cart" always shows "Please select an available size."

### Root Causes (2 total)

| # | Cause | File |
|---|-------|------|
| 1 | `product_detail_screen.dart` reads non-existent `widget.product['sizes']` key | `product_detail_screen.dart` |
| 2 | `product_service.dart` `createProduct()` and `updateProduct()` never write to the `inventory` table | `product_service.dart` |

### Fix 1: `lib/services/product_service.dart` — Write Path

**Added `_syncInventoryFromVariants()` helper:**

```dart
Future<void> _syncInventoryFromVariants(
  String productId,
  List<ProductVariant> variants,
) async {
  final Map<String, int> stockBySize = {};
  for (final v in variants) {
    final size = v.size.trim();
    if (size.isEmpty) continue;
    stockBySize[size] = (stockBySize[size] ?? 0) + v.stock;
  }

  await _client.from('inventory').delete().eq('product_id', productId);
  if (stockBySize.isEmpty) return;

  await _client.from('inventory').insert(
    stockBySize.entries.map((e) => {
      'product_id': productId,
      'size': e.key,
      'stock': e.value,
      'updated_at': DateTime.now().toIso8601String(),
    }).toList(),
  );
}
```

**Called in `createProduct()` after variants insert** and in `updateProduct()`
after variants replace.

### Fix 2: `lib/services/product_service.dart` — Read Path

Added `inventory(*)` to `getProduct()` and `getSellerProducts()` select queries.

### Fix 3: `lib/screens/customer/product_detail_screen.dart`

**Added `_buildSizesMap()` helper** that reads from both `inventory` and
`product_variants` tables, deduplicates sizes, and sorts numerically.

**Added `_fetchInventory()` fallback** with shimmer loading skeleton for when
the parent screen doesn't include inventory data in its query.

---

## Improvement #1: Profile Fetch Timeout

**File:** `lib/screens/auth_gate.dart`

Added a **12-second timeout** on the profile fetch so users aren't stuck on the
loading spinner when the network is slow.

---

## Improvement #2: Offline Detection

**File:** `lib/screens/auth_gate.dart`

Added `_hasConnection()` method and `_ProfileErrorView` widget that checks
connectivity on init. Shows a "No Internet Connection" screen with wifi-off icon,
message, and retry button when offline.

---

## Improvement #3: Size Selector Loading Skeleton

**File:** `lib/screens/customer/product_detail_screen.dart`

Added `_isLoadingSizes` state flag, `_fetchInventory()` fallback, and
`_buildSizeSkeleton()` shimmer widget for when inventory data is missing from
the product map.

---

# Session 2 — July 2, 2026

## Bug #4: Product Variants Missing from Main Query

### Severity: Medium

### Symptom

The main product fetch query in `SupabaseService.fetchProducts()` included
`inventory(size, stock)` but **not** `product_variants(size, stock)`. This meant
`_buildSizesMap()` in `product_detail_screen.dart` could only read from the
`inventory` table on the initial load, and had to fall back to a separate
`_fetchInventory()` query when inventory was empty.

### Fix: `lib/services/supabase_service.dart`

**Added `product_variants(size, stock)` to the main product query:**

```dart
// Before:
'*, stores(name), product_images(image_url, display_order), inventory(size, stock)',

// After:
'*, stores(name), product_images(image_url, display_order), inventory(size, stock), product_variants(size, stock)',
```

**Impact:** Sizes are now available immediately from the main product query,
eliminating the need for the `_fetchInventory()` fallback in most cases. This
reduces unnecessary Supabase queries and improves perceived load time.

---

## Bug #5: Poor Error Messages on Size Selector

### Severity: Low

### Symptom

When no sizes were available, the user saw a generic "Please select an available
size" snackbar. This didn't distinguish between "sizes are still loading" and
"no sizes exist for this product."

### Fix: `lib/screens/customer/product_detail_screen.dart`

**Improved `_addToCart()` error message:**

```dart
// Before:
SnackBar(
  content: Text('Please select an available size.'),
  backgroundColor: AppConstants.error,
)

// After:
SnackBar(
  content: Text(
    _isLoadingSizes
        ? 'Sizes are still loading. Please wait.'
        : 'No sizes available. Please check back later.',
  ),
  backgroundColor: AppConstants.error,
)
```

**Added "No sizes available" visual state** in the size selector area when
`sizesMap` is empty and not loading:

```dart
else if (sizesMap.isEmpty)
  Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      color: AppConstants.borderGray.withOpacity(0.15),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      children: [
        Icon(Icons.info_outline, size: 16, color: AppConstants.secondary.withOpacity(0.5)),
        const SizedBox(width: 8),
        Text(
          'No sizes available for this product.',
          style: AppConstants.bodyStyle(fontSize: 13, color: AppConstants.secondary.withOpacity(0.5)),
        ),
      ],
    ),
  )
```

---

## Bug #6: Blank White Cart Screen (RenderBox Layout Error)

### Severity: Critical

### Symptom

The cart screen (`lib/screens/customer/cart_screen.dart`) showed a completely
blank white screen. This started after a Shopee-inspired cart redesign. The
following were confirmed as **NOT** the cause:

- ✅ `EmptyStateWidget` — constructor matches exactly
- ✅ `AppConstants` — all referenced properties exist
- ✅ `CartProvider` — all new methods exist
- ✅ `SoleCard` — accepts `color`, `padding`, `margin` params
- ✅ Supabase data — seed data exists (4 stores, 11 products, 48 inventory rows)
- ✅ `CartProvider` is in the widget tree (provided in `main.dart`'s `MultiProvider`)
- ✅ Navigation — `CartScreen` is correctly referenced in `CartIconButton`

### Diagnostic Process

#### Step 1: Surgical Isolation Test

Replaced the entire `body:` of the Scaffold with hardcoded debug text:

```dart
body: const Center(
  child: Text(
    'CART SCREEN IS RENDERING',
    style: TextStyle(fontSize: 24, color: Colors.red),
  ),
),
```

**Result:** Still blank white. This proved the bug was **not** in the body
content — it was at a higher level or in the rendering phase.

#### Step 2: Debug Print Tracing + Try-Catch

Added `debugPrint` statements at every decision point in `build()` and wrapped
the entire method in a `try/catch` that would render a bright red error screen
if an exception was caught.

**Result:** Still blank white. The try-catch didn't catch anything because the
error was a **layout/rendering error**, not a build-time exception. Flutter's
rendering errors happen **after** `build()` returns, during the layout phase.

#### Step 3: Provider/Routing Verification

- ✅ `CartProvider` is provided in `main.dart`'s `MultiProvider`
- ✅ `CustomerShell` uses `IndexedStack` — cart screen is always in the tree
- ✅ `CartIconButton` pushes `CartScreen` via `MaterialPageRoute`
- ✅ No duplicate `CartScreen` class definitions
- ✅ `flutter analyze` — 0 errors in app code

#### Step 4: Console Error Capture

After `flutter clean` and a fresh build, the user captured these errors:

```
RenderBox was not laid out: RenderConstrainedBox#9ff39 relayoutBoundary=up5
RenderBox was not laid out: RenderFlex#e7e4a relayoutBoundary=up4
RenderBox was not laid out: RenderPadding#64ec5 relayoutBoundary=up3
RenderBox was not laid out: RenderDecoratedBox#70aa3 relayoutBoundary=up2
RenderBox was not laid out: RenderFlex#246a9 relayoutBoundary=up1
```

**This was the smoking gun.** A cascade of `RenderBox was not laid out` errors
originating from deep in the widget tree and propagating up.

### Root Cause

`SolePrimaryButton` used `SizedBox(width: double.infinity, height: 52)` to make
the button fill its parent's width. This works correctly when the button is
inside an `Expanded` or `Column` — but in `_CartCheckoutBar`, the button was
placed **directly inside a `Row`** without an `Expanded` wrapper:

```dart
// _CartCheckoutBar
Row(
  children: [
    // ... checkbox, "All" label, delivery info ...
    Expanded(child: Column(...)),
    SolePrimaryButton(  // ← SizedBox(width: double.infinity) inside Row!
      label: 'Check Out ($selectedCount)',
      onPressed: canCheckout ? () { ... } : null,
    ),
  ],
)
```

**Why this breaks:** In Flutter's `Row` layout algorithm, non-flex children
(requesting a specific width) are laid out **first** before flex children get
their allocation. A `SizedBox(width: double.infinity)` requests unbounded width.
The `Row` gives it `0 to maxWidth`, the `SizedBox` tries to be `double.infinity`
wide, and the layout engine fails — cascading `RenderBox was not laid out`
errors up through the render tree. Flutter's `ErrorWidget` catches these and
renders a blank white surface, which is why the cart screen appeared empty.

### Error Cascade Explanation

```
RenderConstrainedBox (up5) — the SizedBox(width: double.infinity) inside SolePrimaryButton
  ↓ fails
RenderFlex (up4) — the Row inside _CartCheckoutBar
  ↓ cascades
RenderPadding (up3) — the Container's padding
  ↓ cascades
RenderDecoratedBox (up2) — the Container decoration
  ↓ cascades
RenderFlex (up1) — the Column in Scaffold body
  ↓ cascades
RenderDecoratedBox (up2) — the Scaffold body container
```

### Fix: `lib/widgets/sole_primary_button.dart`

**Added `expandToFill` parameter** (default `true` for backward compatibility):

```dart
class SolePrimaryButton extends StatelessWidget {
  // ... existing fields ...

  /// When [expandToFill] is true (default), the button fills its parent's width.
  /// Set to false when placing inside a Row to avoid unbounded width errors.
  final bool expandToFill;

  const SolePrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.backgroundColor = AppConstants.primary,
    this.textColor = AppConstants.surfaceLight,
    this.isLoading = false,
    this.icon,
    this.expandToFill = true,  // ← NEW PARAMETER
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: expandToFill ? double.infinity : null,  // ← KEY FIX
      height: 52,
      child: FilledButton(
        onPressed: isLoading ? null : onPressed,
        // ...
      ),
    );
  }
}
```

### Fix: `lib/screens/customer/cart_screen.dart`

**Set `expandToFill: false` on the checkout bar's `SolePrimaryButton`:**

```dart
// _CartCheckoutBar
SolePrimaryButton(
  label: canCheckout ? 'Check Out ($selectedCount)' : 'Check Out',
  expandToFill: false,  // ← NEW — avoids unbounded width inside Row
  onPressed: canCheckout ? () { ... } : null,
),
```

**Also removed:**
- All `debugPrint` statements added during diagnosis
- The `try/catch` wrapper around the build method
- The error fallback Scaffold

### Fix: `lib/widgets/cart_icon_button.dart`

**Removed debug prints** from the `onPressed` handler that were added during
diagnosis.

### Why the Other SolePrimaryButton Call Sites Are Safe

The delete confirmation modal in `cart_screen.dart` also uses `SolePrimaryButton`,
but it's inside a `Row` wrapped in `Expanded`:

```dart
Row(
  children: [
    Expanded(child: OutlinedButton(...)),  // ← Expanded wraps it
    const SizedBox(width: 12),
    Expanded(child: SolePrimaryButton(...)),  // ← Also wrapped in Expanded
  ],
)
```

Since `Expanded` constrains the child to the flex allocation (not unbounded),
`SizedBox(width: double.infinity)` works fine here. No change needed.

---

# SQL Migrations

## Backfill Script: `docs/debug/inventory_backfill.sql`

Run this **once** in the Supabase SQL Editor after deploying the code fix:

```sql
-- Step 1: Add unique constraint (skip if already exists)
ALTER TABLE public.inventory
  ADD CONSTRAINT inventory_product_size_unique UNIQUE (product_id, size);

-- Step 2: Backfill inventory from product_variants
INSERT INTO public.inventory (product_id, size, stock, updated_at)
SELECT
  product_id,
  size,
  SUM(stock) AS stock,
  now() AS updated_at
FROM public.product_variants
WHERE size IS NOT NULL AND size <> ''
GROUP BY product_id, size
ON CONFLICT (product_id, size) DO UPDATE
  SET stock = EXCLUDED.stock,
      updated_at = now();
```

**What this does:** Aggregates stock by size from `product_variants` (summing
across all colors) and inserts one row per unique size into `inventory`. Uses
`ON CONFLICT` to update rows that already exist.

---

# All Files Modified

## Session 1 — June 30, 2026

| # | File | Changes |
|---|------|---------|
| 1 | `lib/providers/auth_provider.dart` | State reset in `login()` and `signOut()` |
| 2 | `lib/services/auth_service.dart` | Session-clear before `signIn()` |
| 3 | `lib/screens/auth_gate.dart` | Direct widget returns, profile timeout, offline detection, `PendingApprovalScreen` logout fix |
| 4 | `lib/services/product_service.dart` | `_syncInventoryFromVariants()` helper, inventory sync in `createProduct()`/`updateProduct()`, `inventory(*)` in read queries |
| 5 | `lib/screens/customer/product_detail_screen.dart` | `_buildSizesMap()` helper, `_fetchInventory()` fallback, loading skeleton |
| 6 | `docs/debug/inventory_backfill.sql` | SQL backfill script for existing products |

## Session 2 — July 2, 2026

| # | File | Changes |
|---|------|---------|
| 7 | `lib/services/supabase_service.dart` | Added `product_variants(size, stock)` to `fetchProducts()` select query |
| 8 | `lib/screens/customer/product_detail_screen.dart` | Improved `_addToCart()` error message (loading vs empty), added "No sizes available" visual state |
| 9 | `lib/widgets/sole_primary_button.dart` | Added `expandToFill` parameter (default `true`). When `false`, `SizedBox` width is `null` instead of `double.infinity`, avoiding unbounded width inside Rows |
| 10 | `lib/screens/customer/cart_screen.dart` | Set `expandToFill: false` on checkout bar's `SolePrimaryButton`. Removed all debug prints and try-catch wrapper |
| 11 | `lib/widgets/cart_icon_button.dart` | Removed debug prints from `onPressed` handler |

---

# Testing Checklist

## Auth Flow — Account Switching

- [ ] Log in as customer → Logout → Log in as seller → Navigates to SellerShell
- [ ] Log in as seller → Logout → Log in as admin → Navigates to AdminShell
- [ ] Log in as Account A → Logout → Log in as Account A again → Works correctly
- [ ] Rapid switch: Log in → Logout → Log in immediately → No freeze
- [ ] Log in as pending seller → Tap Log Out on PendingApprovalScreen → Returns to login with state cleared
- [ ] Fresh install → Onboarding shows → Complete onboarding → Login → Works

## Auth Flow — Error Handling

- [ ] Log in with wrong password → Error shown → Correct password → Login succeeds
- [ ] Slow network → 12s timeout → Retry screen with friendly message
- [ ] No internet → "No Internet Connection" screen with retry button

## Product Flow — Size Selector

- [ ] Open product with inventory rows only → Sizes appear, first available pre-selected
- [ ] Open product with product_variants rows only → Sizes appear correctly
- [ ] Open product with both tables → Sizes deduplicated, stock correct
- [ ] Open product with all stock = 0 → All chips strikethrough, no auto-selection
- [ ] Open product with no sizes at all → "No sizes available" info message shown
- [ ] Navigate from customer home → Product detail → Sizes load correctly

## Cart Flow — Rendering

- [ ] Navigate to cart tab with empty cart → "Your cart is empty" icon and message are **visibly** shown (not blank white)
- [ ] Browse home screen → products appear (Classic Derby Oxford, Artisan Penny Loafer, etc.)
- [ ] Open a product → sizes appear (EU 38–42)
- [ ] Select a size → tap Add to Cart → no "select a size" snackbar
- [ ] Navigate to cart → item appears grouped under store name (NOT blank white, NOT "Unknown Store")
- [ ] Quantity stepper works, checkout bar total updates
- [ ] No overflow warnings anywhere on cart screen
- [ ] Multi-store grouping works (items from different stores in separate cards)

## SQL Backfill

- [ ] Run `inventory_backfill.sql` in Supabase SQL Editor
- [ ] Verify existing products now have inventory rows
- [ ] Verify customer size selector works for pre-existing products

---

# Design System Reference

| Token | Value | Usage |
|-------|-------|-------|
| Primary (Burnished Clay) | `AppConstants.primary` / `#8B5A2B` | Buttons, active states, selected chips |
| Surface Light (Off-White Suede) | `AppConstants.surfaceLight` / `#F5F0EB` | Backgrounds, selected chip text |
| Error (Crimson Welt) | `AppConstants.error` / `#D64545` | Error messages, out-of-stock strikethrough |
| Success | `AppConstants.success` | "Added to Cart" SnackBar |
| Border Gray | `AppConstants.borderGray` / `#D2C7BC` | Unselected chip borders |
| Secondary (Carob Dark) | `AppConstants.secondary` / `#3B2314` | Unselected chip text |
| Monospace font | JetBrains Mono via `AppConstants.monoStyle()` | Size chip labels, prices |
| Body font | DM Sans via `AppConstants.bodyStyle()` | All body text and labels |
| Headline font | Playfair Display via `AppConstants.headlineStyle()` | Screen titles |
| Button radius | `AppConstants.buttonRadius` (12px) | All buttons and chips |

---

*SoleVision v1.1.0 — Session documented July 2, 2026*
*Covers development sessions: June 30 – July 2, 2026*
