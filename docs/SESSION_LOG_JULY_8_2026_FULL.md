# Session Log — July 8, 2026 (Full Session)

**Date:** July 8, 2026
**Duration:** ~3 hours
**Focus:** Address search bar (MapTiler geocoding), MapTiler 403 fix, customer_addresses RLS fix, orders.shipping_address column fix

---

## Executive Summary

This session tackled four interconnected issues in the customer address/checkout flow:

1. **Implemented a search bar with live predictions** on the Delivery Location map screen using MapTiler's Geocoding API
2. **Fixed a MapTiler 403 "Key usage restricted" error** caused by missing `User-Agent` header on geocoding requests
3. **Fixed customer_addresses RLS policies** — INSERT/SELECT/UPDATE/DELETE policies from the July 5 migration were never applied to the live database
4. **Fixed orders.shipping_address column** — the ALTER TABLE from the July 5 migration was also never applied

The recurring root cause across issues #3 and #4 is the same pattern seen on July 4: **SQL migrations are written to disk but never executed against the live Supabase database.** This is now the third time this has caused production bugs.

---

## Timeline

### 1. Address Search Bar Implementation (~10:00 AM)

**User Request:** Add a search bar with live MapTiler geocoding predictions to the Delivery Location map screen.

**Investigation:**
- Read `docs/SoleVision_Complete_Documentation.md` and `AI_PROJECT_SUMMARY.md` for architecture context
- Found existing implementation in `lib/screens/customer/add_edit_address_screen.dart` — already has GPS auto-locate, manual pin-dragging, reverse geocoding
- MapTiler already integrated for tile rendering via `flutter_map`
- No `http` or `dio` packages in the project — uses `dart:io`'s `HttpClient` elsewhere

**MapTiler Geocoding API Research:**
- Endpoint: `https://api.maptiler.com/geocoding/{query}.json?key=<API_KEY>`
- Response: GeoJSON with `features` array, each containing `place_name`, `center` [lng, lat]
- Supports `bbox` parameter for region biasing (Philippines: `116.927,4.587,126.603,21.119`)
- Supports `limit` parameter to cap results

**Implementation (single file: `lib/screens/customer/add_edit_address_screen.dart`):**

| Component | Details |
|-----------|---------|
| **State variables** | `_searchController`, `_searchPredictions`, `_isSearchLoading`, `_searchError`, `_searchDebounce`, `_showPredictions` |
| **Search method** | `_searchAddress(query)` — debounced at 350ms, minimum 2 chars |
| **API call** | `_fetchPredictions(query)` — `HttpClient` to MapTiler Geocoding API, Philippines bbox bias, 5-result limit, 8s timeout |
| **Selection** | `_onPredictionSelected(prediction)` — animates map to location, dismisses keyboard, reverse-geocodes to fill form |
| **Search bar UI** | `_buildSearchBar()` — rounded overlay input, magnifying glass icon, clear button, in-bar loading spinner |
| **Prediction dropdown** | `_buildPredictionDropdown()` — location pin + address text, tappable rows, empty/error states, max 5 results |
| **Error handling** | Network errors → "Search unavailable right now"; empty results → "No results found"; 401/403 → "Invalid API key" |
| **Async safety** | All async callbacks check `mounted` before `setState()`, `HttpClient` closed in `finally` block, debounce timer cancelled in `dispose()` |

**Design tokens used:** Primary `#8B5A2B`, Surface `#F5F0EB`, Error `#D64545`, rounded corners (16px), soft shadow

**Code review:** Passed — reviewer confirmed correctness, async safety, and that existing features (GPS auto-locate, current location button, pin-dragging) remain intact.

**Flutter analyze:** Clean — no errors, warnings, or info messages.

---

### 2. MapTiler 403 "Key usage restricted" Fix (~11:00 AM)

**User Report:** Search bar shows "Search unavailable right now" when typing.

**Diagnosis:**
- Debug logs showed: `[SEARCH] Response status: 403` / `Error body: Key usage restricted`
- User's MapTiler key (`ZsHghTkRWCoZDpjMxUir`) was valid and stored correctly in `dart_defines.json`
- Map tiles rendered fine — only geocoding failed
- Key had `Allowed user-agent header: com.solevision.app` set in MapTiler dashboard
- Flutter's `HttpClient` sends a generic Dart/VM user-agent by default — not `com.solevision.app`
- `flutter_map`'s `TileLayer` already sets `userAgentPackageName: 'com.solevision.app'` for tile requests — that's why tiles worked

**Fix applied:**
```dart
// Added after final request = await client.getUrl(url);
request.headers.set('User-Agent', 'com.solevision.app');
```

**Additional improvements (from code review feedback):**
- Added guard for empty/placeholder API key: `if (_maptilerKey.isEmpty || _maptilerKey.contains('YOUR_'))`
- Added specific 401/403 error detection with clear message: "Invalid API key — check your MapTiler configuration"
- Added diagnostic `debugPrint` logging (query only, not full URL with key)
- Changed `activeColor` → `activeThumbColor` on Switch (deprecation fix)

**Code review:** Passed — reviewer confirmed the one-line User-Agent fix is correct and consistent with `flutter_map`'s existing behavior.

**Flutter analyze:** Clean.

---

### 3. customer_addresses RLS Fix (~11:30 AM)

**User Report:** Saving an address fails with:
```
PostgrestException(message: new row violates row-level security
policy for table "customer_addresses", code: 42501, details: Forbidden)
```

**Investigation:**
- Found `supabase/migrations/20260705_add_customer_addresses.sql` — contains table creation + all 4 RLS policies (SELECT/INSERT/UPDATE/DELETE)
- Migration uses `user_id` column (NOT `customer_id` — that column doesn't exist on this table)
- **Policies were never applied to the live database** — same pattern as July 4 checkout bug
- `pg_policies` query confirmed: no INSERT policy existed on `customer_addresses`

**Fix (manual SQL in Supabase SQL Editor):**
```sql
CREATE POLICY "Customers can insert own addresses"
ON customer_addresses
FOR INSERT
TO authenticated
WITH CHECK (user_id = auth.uid());

CREATE POLICY "Customers can view own addresses"
ON customer_addresses FOR SELECT
USING (user_id = auth.uid());

CREATE POLICY "Customers can update own addresses"
ON customer_addresses FOR UPDATE
USING (user_id = auth.uid());

CREATE POLICY "Customers can delete own addresses"
ON customer_addresses FOR DELETE
USING (user_id = auth.uid());
```

**Also created:** `supabase/migrations/20260708_fix_customer_addresses_rls.sql` — DROP IF EXISTS + CREATE all 4 policies (idempotent, safe to re-run).

**Verification:** User confirmed INSERT policy applied and address saving works.

---

### 4. orders.shipping_address Column Fix (~12:00 PM)

**User Report:** After address fix, order placement fails with:
```
PostgrestException(message: Could not find the 'shipping_address' column
of 'orders' in the schema cache, code: PGRST204)
```

**Diagnosis:**
- The `20260705_add_customer_addresses.sql` migration includes `ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS shipping_address JSONB;`
- This ALTER TABLE was **also never applied** to the live database
- The checkout screen passes `shippingAddress: _selectedAddress!.toSnapshot()` to `OrderProvider.placeOrder()`
- PostgREST can't find the column → PGRST204 error

**Fix (manual SQL in Supabase SQL Editor):**
```sql
ALTER TABLE public.orders
    ADD COLUMN IF NOT EXISTS shipping_address JSONB;
```

**Verification:** User confirmed order placement works end-to-end.

---

## Files Modified/Created This Session

| File | Action | Purpose |
|------|--------|---------|
| `lib/screens/customer/add_edit_address_screen.dart` | Modified | Added search bar, geocoding predictions, User-Agent fix, error handling |
| `supabase/migrations/20260708_fix_customer_addresses_rls.sql` | Created | RLS policies for customer_addresses (idempotent) |
| `docs/SESSION_LOG_JULY_8_2026.md` | Created | Earlier session log (map setup, dart-define config) |
| `docs/SESSION_LOG_CUSTOMER_ADDRESSES_RLS_FIX.md` | Created | RLS fix session log |
| `docs/AI_PROJECT_SUMMARY.md` | Modified | Updated RLS matrix, migrations table, bug history, known issues |

---

## SQL Applied to Live Database

| SQL | Status | Applied By |
|-----|--------|------------|
| `CREATE POLICY "Customers can insert own addresses"` (and SELECT/UPDATE/DELETE) | ✅ Applied | User in Supabase SQL Editor |
| `ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS shipping_address JSONB` | ✅ Applied | User in Supabase SQL Editor |

---

## Bug Fix History (Updated)

| Date | Fix | Root Cause |
|------|-----|------------|
| June 28 | Product hard delete + auto-deactivation | Missing RLS DELETE policy + FK constraints |
| June 30 | Login freeze on account switch | 5 root causes: stale state, race condition, biometric bleed |
| June 30 | Empty size selector | inventory table never written to |
| July 2 | Checkout flow overhaul | Multi-item orders broken, wrong pricing, fake IDs |
| July 3 | Stock validation + friendly errors | Raw PostgrestException shown to users |
| July 3 | DB trigger exact-match fix | Size format mismatch ("EU40" vs "40") |
| July 3 | validateCartForCheckout reads inventory | Was reading stale product_variants |
| July 4 | Order creation atomicity | Orphaned 0-item orders on failure |
| July 4 | **SECURITY DEFINER on triggers** | **True root cause: RLS blocked trigger UPDATE** |
| July 4 | cart_items.size column | Migration existed but never applied |
| July 8 | Permanent dart-define config for MAPTILER_API_KEY | Created dart_defines.json + helper scripts |
| July 8 | Updated .gitignore for secrets | Added dart_defines.json and *.env patterns |
| July 8 | **Address search bar + MapTiler geocoding** | **New feature: live prediction search on map screen** |
| July 8 | **MapTiler 403 fix (User-Agent header)** | **Key had user-agent restriction; Flutter HttpClient didn't set it** |
| July 8 | **customer_addresses RLS fix** | **Policies from 20260705 migration never applied to live DB** |
| July 8 | **orders.shipping_address column** | **ALTER TABLE from 20260705 migration never applied to live DB** |

---

## Key Lessons

1. **SQL migrations must be applied to the live database.** This is now the third time (July 4, July 8 ×2) that migration files existed on disk but were never executed. Every migration should be followed by a verification query against the live DB.

2. **MapTiler key restrictions affect more than tiles.** A key with `Allowed user-agent header` restrictions works for `flutter_map` tiles (which set `userAgentPackageName`) but fails for raw `HttpClient` calls (which don't). Always set the User-Agent header on custom HTTP requests to MapTiler.

3. **`customer_addresses` uses `user_id`, not `customer_id`.** The `orders` table uses `customer_id`, but `customer_addresses` uses `user_id`. Don't assume consistent naming across tables.

4. **The `shipping_address` column is a JSONB snapshot.** It stores the delivery address at order time so future address edits don't retrochange placed orders. This is an intentional design choice.

5. **ListTile background color warnings.** The checkout screen throws repeated "ListTile background color or ink splashes may be invisible" warnings. This is a cosmetic issue (ListTiles inside DecoratedBox without Material wrapper) — not blocking functionality but should be fixed for clean logs.

---

## Remaining Issues

| Issue | Status | Priority |
|-------|--------|----------|
| No git repository | ⚠️ No version control | Critical |
| Non-numeric sizes may break triggers | ⚠️ Unverified (query ready) | High |
| Duplicate product_variants rows | ⚠️ Cleanup script ready | High |
| ListTile background color warnings | Cosmetic — many repeated in logs | Medium |
| `supabase/schema.sql` is outdated | Known | Medium |
| No unit tests | Default template only | Medium |
| AR fitting is a placeholder | No real AR | Low |
| CSV export is a stub | Shows SnackBar only | Low |
| No push notifications | Not started | Future |
| No real-time updates | Not integrated | Future |

---

*Session documented by Buffy (Codebuff AI Assistant)*
*July 8, 2026*
