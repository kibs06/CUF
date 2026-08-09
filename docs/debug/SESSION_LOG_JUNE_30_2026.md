# SoleVision — Session Log: June 30, 2026

## Overview

This document details all bug fixes, improvements, and code changes made during the
June 30, 2026 development session. Three critical bugs were resolved across the
authentication flow and product catalog, along with several UX improvements.

---

## Table of Contents

1. [Bug #1: Login Freeze When Switching Accounts](#bug-1-login-freeze-when-switching-accounts)
2. [Bug #2: Navigator Stack Conflict on Account Switch](#bug-2-navigator-stack-conflict-on-account-switch)
3. [Bug #3: Product Size Selector Empty — Inventory Never Written](#bug-3-product-size-selector-empty--inventory-never-written)
4. [Improvement #1: Profile Fetch Timeout](#improvement-1-profile-fetch-timeout)
5. [Improvement #2: Offline Detection](#improvement-2-offline-detection)
6. [Improvement #3: Size Selector Loading Skeleton](#improvement-3-size-selector-loading-skeleton)
7. [Reference Copies](#reference-copies)
8. [SQL Migration](#sql-migration)
9. [Files Modified](#files-modified)
10. [Testing Checklist](#testing-checklist)

---

## Bug #1: Login Freeze When Switching Accounts

### Severity: Critical

### Symptom

When a seller or customer logs out and attempts to log in with a different account,
the app freezes on the login screen:

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

```dart
Future<void> clearCredentials() async {
  await _secureStorage.delete(key: _keyEmail);
  await _secureStorage.delete(key: _keyPassword);
  await _secureStorage.delete(key: _keyDeclined);
}
```

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
/// Sync the inventory table from a variants list.
///
/// Groups variants by size and sums their stock across all colors,
/// then replaces all inventory rows for this product with one row
/// per unique size.
Future<void> _syncInventoryFromVariants(
  String productId,
  List<ProductVariant> variants,
) async {
  // Group stock by size — sum across all colors
  final Map<String, int> stockBySize = {};
  for (final v in variants) {
    final size = v.size.trim();
    if (size.isEmpty) continue;
    stockBySize[size] = (stockBySize[size] ?? 0) + v.stock;
  }

  // Delete existing inventory rows (BEFORE early return to clear stale data)
  await _client
      .from('inventory')
      .delete()
      .eq('product_id', productId);

  if (stockBySize.isEmpty) return;

  // Insert one row per unique size
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

**Called in `createProduct()` after variants insert:**

```dart
// 4. Insert variants
if (variants.isNotEmpty) {
  await _client.from('product_variants').insert(
        variants.map((v) => v.toInsertMap(productId)).toList(),
      );
}

// 5. Sync inventory from variants — one row per unique size
await _syncInventoryFromVariants(productId, variants);

// 6. Insert customizations
```

**Called in `updateProduct()` after variants replace:**

```dart
// 3. Replace variants (delete + re-insert)
await _client.from('product_variants').delete().eq('product_id', productId);
if (variants.isNotEmpty) {
  await _client.from('product_variants').insert(
        variants.map((v) => v.toInsertMap(productId)).toList(),
      );
}

// 4. Sync inventory after variants are replaced
await _syncInventoryFromVariants(productId, variants);

// 5. Replace customizations
```

### Fix 2: `lib/services/product_service.dart` — Read Path

**`getProduct()`** — Added `inventory(*)` to select:

```dart
Future<Map<String, dynamic>> getProduct(String productId) async {
  return await _client
      .from('products')
      .select(
          '*, product_images(*), product_variants(*), product_customizations(*), inventory(*)')
      .eq('id', productId)
      .single();
}
```

**`getSellerProducts()`** — Added `inventory(*)` to select:

```dart
Future<List<Map<String, dynamic>>> getSellerProducts() async {
  final sellerId = _client.auth.currentUser!.id;
  final data = await _client
      .from('products')
      .select(
          '*, product_images(*), product_variants(*), product_customizations(*), inventory(*)')
      .eq('seller_id', sellerId)
      .order('created_at', ascending: false);
  return List<Map<String, dynamic>>.from(data);
}
```

### Fix 3: `lib/screens/customer/product_detail_screen.dart`

**Added `_buildSizesMap()` helper:**

```dart
Map<String, int> _buildSizesMap() {
  final Map<String, int> sizes = {};

  // From inventory table (primary source)
  final inventory = widget.product['inventory'] as List<dynamic>? ?? [];
  for (final row in inventory) {
    final size = row['size']?.toString();
    final stock = row['stock'] as int? ?? 0;
    if (size != null && size.isNotEmpty) {
      sizes[size] = (sizes[size] ?? 0) + stock;
    }
  }

  // From product_variants table (fallback / supplementary)
  final variants = widget.product['product_variants'] as List<dynamic>? ?? [];
  for (final row in variants) {
    final size = row['size']?.toString();
    final stock = row['stock'] as int? ?? 0;
    if (size != null && size.isNotEmpty) {
      sizes[size] = ((sizes[size] ?? 0) < stock) ? stock : (sizes[size] ?? 0);
    }
  }

  // Sort numerically by EU size
  return Map.fromEntries(
    sizes.entries.toList()
      ..sort((a, b) =>
          (int.tryParse(a.key) ?? 0).compareTo(int.tryParse(b.key) ?? 0)),
  );
}
```

**Fixed `initState()` and `build()`** to use `_buildSizesMap()` instead of
the non-existent `widget.product['sizes']` key.

### Database Schema

**`inventory` table** — one row per product per size:

```sql
CREATE TABLE public.inventory (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id  UUID REFERENCES public.products(id) ON DELETE CASCADE NOT NULL,
    size        TEXT NOT NULL,
    stock       INTEGER NOT NULL DEFAULT 0,
    updated_at  TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL
);
```

**`product_variants` table** — one row per product per size+color:

```sql
CREATE TABLE public.product_variants (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id       UUID REFERENCES public.products(id) ON DELETE CASCADE NOT NULL,
    size             TEXT NOT NULL,
    color            TEXT,
    stock            INTEGER DEFAULT 0,
    additional_price NUMERIC DEFAULT 0,
    sku              TEXT,
    created_at       TIMESTAMP WITH TIME ZONE DEFAULT now()
);
```

**Relationship:** `product_variants` holds granular stock per size+color.
`inventory` holds aggregated stock per size (summed across all colors).

---

## Improvement #1: Profile Fetch Timeout

### Problem

If the network is slow, the profile fetch in `AuthGate` could take indefinitely,
leaving the user stuck on the loading spinner.

### Solution: `lib/screens/auth_gate.dart`

Added a **12-second timeout** on the profile fetch:

```dart
static const _profileTimeout = Duration(seconds: 12);

Future<Map<String, dynamic>?> _profileFor(User user) {
  if (_profileFuture == null || _profileUserId != user.id) {
    _profileUserId = user.id;
    _profileFuture = _authService
        .getProfile(user.id)
        .timeout(_profileTimeout);
  }
  return _profileFuture!;
}
```

Added `import 'dart:async';` for `TimeoutException` support.

When the timeout fires, the `FutureBuilder` catches the error and shows the
`ErrorRetryWidget` with a retry button.

---

## Improvement #2: Offline Detection

### Problem

When the device has no internet connection, the loading screen spins forever
with no feedback.

### Solution: `lib/screens/auth_gate.dart`

**Added `_hasConnection()` method:**

```dart
Future<bool> _hasConnection() async {
  try {
    final result = await InternetAddress.lookup('google.com')
        .timeout(const Duration(seconds: 5));
    return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
  } catch (_) {
    return false;
  }
}
```

**Added `_ProfileErrorView` widget** that checks connectivity on init:

- Shows a brief loading spinner while checking
- If **offline**: displays a "No Internet Connection" screen with wifi-off icon,
  message, and retry button
- If **online** but profile fetch failed: shows the existing `ErrorRetryWidget`
  with a friendly timeout message

Applied to **both paths** in `AuthGate`:
1. The `ConnectionState.waiting` path (existing session)
2. The stream-connected path (new login)

Added `import 'dart:io';` for `InternetAddress`.

---

## Improvement #3: Size Selector Loading Skeleton

### Problem

When inventory data is missing from the product map (e.g., parent screen didn't
include `inventory(*)` in its query), the size selector area is blank with no
indication that data is loading.

### Solution: `lib/screens/customer/product_detail_screen.dart`

**Added `_isLoadingSizes` state flag** and **`_fetchInventory()` fallback:**

```dart
Future<void> _fetchInventory() async {
  if (!mounted) return;
  setState(() => _isLoadingSizes = true);

  try {
    final productId = widget.product['id'].toString();
    final data = await Supabase.instance.client
        .from('products')
        .select('inventory(*), product_variants(*)')
        .eq('id', productId)
        .single();

    if (!mounted) return;

    setState(() {
      widget.product['inventory'] = data['inventory'];
      widget.product['product_variants'] = data['product_variants'];
      _isLoadingSizes = false;
    });

    // Auto-select first available size after data loads
    final sizesMap = _buildSizesMap();
    for (final entry in sizesMap.entries) {
      if (entry.value > 0) {
        _selectedSize = entry.key;
        break;
      }
    }
  } catch (_) {
    if (mounted) setState(() => _isLoadingSizes = false);
  }
}
```

**Added `_buildSizeSkeleton()` shimmer widget:**

```dart
Widget _buildSizeSkeleton() {
  return Shimmer.fromColors(
    baseColor: AppConstants.borderGray.withOpacity(0.3),
    highlightColor: AppConstants.borderGray.withOpacity(0.1),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List.generate(5, (_) => Container(
          width: 48, height: 48,
          margin: const EdgeInsets.only(right: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
          ),
        )),
      ),
    ),
  );
}
```

In `initState()`, if `_buildSizesMap()` returns empty, `_fetchInventory()` is
called and the skeleton is shown while loading.

---

## Reference Copies

All modified source files were copied to `docs/debug/` for reference:

| File | Source | Purpose |
|------|--------|---------|
| `auth_provider.dart` | `lib/providers/auth_provider.dart` | Auth state management with login/logout fixes |
| `auth_service.dart` | `lib/services/auth_service.dart` | Supabase auth calls with session-clear fix |
| `auth_gate.dart` | `lib/screens/auth_gate.dart` | Stream-based routing, timeout, offline detection |
| `login_screen.dart` | `lib/screens/auth/login_screen.dart` | Login form UI |
| `biometric_service.dart` | `lib/services/biometric_service.dart` | Biometric auth + credential storage |
| `product_detail_screen.dart` | `lib/screens/customer/product_detail_screen.dart` | Customer product detail with size selector fix |
| `product_service.dart` | `lib/services/product_service.dart` | Product CRUD with inventory sync |
| `inventory_backfill.sql` | *(new file)* | SQL script to populate inventory for existing products |
| `README.md` | *(new file)* | Overview of the debug folder |

---

## SQL Migration

### Backfill Script: `docs/debug/inventory_backfill.sql`

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

## Files Modified

| # | File | Changes |
|---|------|---------|
| 1 | `lib/providers/auth_provider.dart` | State reset in `login()` and `signOut()` |
| 2 | `lib/services/auth_service.dart` | Session-clear before `signIn()` |
| 3 | `lib/screens/auth_gate.dart` | Direct widget returns, profile timeout, offline detection, `PendingApprovalScreen` logout fix |
| 4 | `lib/services/product_service.dart` | `_syncInventoryFromVariants()` helper, inventory sync in `createProduct()`/`updateProduct()`, `inventory(*)` in read queries |
| 5 | `lib/screens/customer/product_detail_screen.dart` | `_buildSizesMap()` helper, `_fetchInventory()` fallback, loading skeleton |
| 6 | `docs/debug/inventory_backfill.sql` | SQL backfill script for existing products |
| 7 | `docs/debug/README.md` | Debug folder overview |
| 8 | ~~`docs/debug/*.dart`~~ | Reference copies of all modified source files — **removed 2026-08-09** (recoverable via git history) |

---

## Testing Checklist

### Auth Flow — Account Switching

- [ ] Log in as customer → Logout → Log in as seller → Navigates to SellerShell
- [ ] Log in as seller → Logout → Log in as admin → Navigates to AdminShell
- [ ] Log in as Account A → Logout → Log in as Account A again → Works correctly
- [ ] Rapid switch: Log in → Logout → Log in immediately → No freeze
- [ ] Log in as pending seller → Tap Log Out on PendingApprovalScreen → Returns to login with state cleared
- [ ] Fresh install → Onboarding shows → Complete onboarding → Login → Works

### Auth Flow — Error Handling

- [ ] Log in with wrong password → Error shown → Correct password → Login succeeds
- [ ] Slow network → 12s timeout → Retry screen with friendly message
- [ ] No internet → "No Internet Connection" screen with retry button

### Product Flow — Size Selector

- [ ] Open product with inventory rows only → Sizes appear, first available pre-selected
- [ ] Open product with product_variants rows only → Sizes appear correctly
- [ ] Open product with both tables → Sizes deduplicated, stock correct
- [ ] Open product with all stock = 0 → All chips strikethrough, no auto-selection
- [ ] Navigate from customer home → Product detail → Sizes load correctly
- [ ] Create new product with variants → Inventory table populated
- [ ] Update product stock → Inventory table updated
- [ ] Remove all variants from product → Inventory rows cleared

### SQL Backfill

- [ ] Run `inventory_backfill.sql` in Supabase SQL Editor
- [ ] Verify existing products now have inventory rows
- [ ] Verify customer size selector works for pre-existing products

---

## Design System Reference

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

*SoleVision v1.1.0 — Session documented June 30, 2026*
