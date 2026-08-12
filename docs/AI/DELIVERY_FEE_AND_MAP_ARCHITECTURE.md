# Delivery Fee & Map Architecture

> **Purpose:** Full documentation of (1) how the **delivery fee** is computed, charged, and persisted across the client, edge functions, and database, and (2) the **map stack** (flutter_map + MapTiler + geolocator + geocoding) used for address capture, so AI agents can work on either feature without re-reading the whole codebase.
> **Last updated:** August 10, 2026

---

# PART A — DELIVERY FEE

## A1. Overview

The delivery fee is a **flat ₱100** for any online order. It is **not** stored as its own column — it is folded into `orders.total_amount` at order creation and re-computed independently by the PayMongo edge function.

- Cart shows a fee whenever there is at least one item: `fee = subtotal > 0 ? ₱100 : ₱0`.
- Checkout adds it to `orderTotal` before calling `placeOrder`.
- The PayMongo path re-computes it **server-side** (`DELIVERY_FEE = 100` in the edge function) and surfaces it as its own line item in the PayMongo hosted checkout.
- There is **no distance-based, weight-based, or zone-based calculation** anywhere — a single hardcoded constant (duplicated client-side and server-side).

```
CartProvider (client)                    Edge function (server)
  subtotal > 0 ? 100 : 0                 const DELIVERY_FEE = 100
        │                                        │
        └───────────┬────────────────────────────┘
                    ▼
        orders.total_amount  (fee baked in, no column)
```

**Key facts:**

- **Two sources of truth that must stay in sync:** `CartProvider.deliveryFee` (`lib/providers/cart_provider.dart:48`) and `const DELIVERY_FEE = 100` (`supabase/functions/create-gcash-payment-intent/index.ts:53`). If you change the fee, change BOTH — otherwise GCash (PayMongo) orders and cash/other orders will disagree.
- **No `delivery_fee` column exists** in the `orders` table (verified: no delivery_fee in schema, SQL migrations, or SCHEMA_REFERENCE). The fee lives inside `total_amount`.
- **Delivery estimate is a separate, display-only feature** (`lib/utils/delivery_date.dart`) — it does not affect the fee.

## A2. File Map

| Layer | File | Role |
|-------|------|------|
| Provider | `lib/providers/cart_provider.dart` | `deliveryFee` :48, `total` :49, `selectedDeliveryFee` :67, `selectedTotal` :68 |
| Screen | `lib/screens/customer/checkout_screen.dart` | Adds fee to order total :253; price breakdown `_priceRow('Delivery Fee', …)` :800; estimate row :831 |
| Screen | `lib/screens/customer/cart_screen.dart` | `'Delivery: ₱${selectedDeliveryFee}'` :696 |
| Provider | `lib/providers/order_provider.dart` | `placeOrder` :70-87 (passes `total_amount`, `delivery_address`) |
| Service | `lib/services/supabase_service.dart` | `createOrder` :312 (persists `total_amount`, `notes` = address text, `shipping_address` JSONB) |
| Edge fn | `supabase/functions/create-gcash-payment-intent/index.ts` | `DELIVERY_FEE = 100` :53, order total recompute :248, "Delivery Fee" line item :317 |
| Service | `lib/services/gcash_payment_service.dart` | Legacy attempt-#5 direct GCash path (fee already inside `total_amount`) |
| Service | `lib/services/direct_gcash_service.dart` | SQL-callable payment intent path :190-196 |
| Util | `lib/utils/delivery_date.dart` | Business-day estimate (`deliveryBusinessDays = 4`), pure Dart, no `intl` |
| Model | `lib/models/address_model.dart` | `toSnapshot()` :116 — JSONB for `orders.shipping_address` |

## A3. Data Flow

### A3.1 In the cart (CartProvider, cart_provider.dart:42-68)

```
subtotal        = Σ (price × quantity) over ALL items
deliveryFee     = subtotal > 0 ? 100.0 : 0.0        // ₱100 flat
total           = subtotal + deliveryFee

selectedSubtotal     = Σ over CHECKED items only
selectedDeliveryFee  = selectedSubtotal > 0 ? 100.0 : 0.0
selectedTotal        = selectedSubtotal + selectedDeliveryFee
```

The UI (cart screen, checkout bar) uses the **selected** getters so unselected items (e.g. from another store) are not charged.

### A3.2 At checkout (checkout_screen.dart:248-282)

1. `orderTotal = Σ (price × quantity)` over selected items.
2. `orderTotal += cart.selectedDeliveryFee; // ₱100 delivery` (:253).
3. **Cash / other methods:** `orderProvider.placeOrder(totalAmount: orderTotal, …)` → `SupabaseService.createOrder` inserts:
   - `total_amount` = orderTotal (fee included)
   - `fulfillment: 'pickup'` (hardcoded, `supabase_service.dart:353`)
   - `notes` = `orderData['delivery_address']` (address text — legacy column, still used)
   - `shipping_address` = `Address.toSnapshot()` (JSONB snapshot so later address edits don't retro-change placed orders)
4. **GCash (PayMongo):** `_startGcashCheckout` (checkout_screen.dart:359) calls the edge function instead; order is created server-side in `awaiting_payment` with NO stock held, cart cleared, webhook confirms payment.

### A3.3 Server-side recompute (create-gcash-payment-intent/index.ts)

```
const DELIVERY_FEE = 100;                    // :53  ← must match CartProvider
subtotalCents = Σ (unit_price × qty) × 100   // :239
orderTotalCents = subtotalCents > 0 ? subtotalCents + DELIVERY_FEE * 100 : 0   // :248
→ orders.total_amount = orderTotalCents / 100                                 // :284
→ PayMongo line items: […, { name: "Delivery Fee", amount: 10000, quantity: 1 }]  // :317
```

The webhook (`gcash-webhook/index.ts`) verifies the charged amount against the intent amount (`expectedCentavos`, :319) — the fee is inherently protected because it's inside `total_amount`.

### A3.4 Persistence

| Where | What's stored |
|---|---|
| `orders.total_amount` | Products + ₱100 fee (online orders); POS orders carry no fee |
| `orders.shipping_address` | JSONB snapshot: recipient, region/province/city/barangay/street, lat/lng, label (from `Address.toSnapshot()`) |
| `orders.notes` | Legacy: the delivery address **text** (also used as `delivery_address` when reading back) |
| `orders.fulfillment` | Hardcoded `'pickup'` on insert; `'delivery'` only appears in tracking UI logic |

## A4. Known Pitfalls

1. **Fee constant duplicated in 2 places** (cart_provider.dart:48, index.ts:53) — no shared config. Always update both.
2. **No `delivery_fee` column** — analytics/reporting can't separate fee from products; if you ever need to, you'll have to add a column + backfill, and keep the two constants in sync.
3. **POS orders pay no delivery fee** — the fee only applies when `CartProvider` computes it; POS inserts raw `total_amount` from the POS screen.
4. **`fulfillment` is always `'pickup'` at insert** even though delivery addresses are collected — the tracking screen branches on `fulfillment == 'delivery'` (tracking_screen.dart:1014) but that branch is effectively unreachable from the online flow today.
5. **Estimate ≠ fee:** the "Estimated delivery" row (`delivery_date.dart`, 4 business days, weekends skipped, no holiday calendar) is display-only and independent of the fee.
6. **Legacy path:** `gcash_payment_service.dart` (attempt-#5) is superseded by `create-gcash-payment-intent`; the fee there is whatever the client passed in `total_amount`.

---

# PART B — MAP STACK

## B1. Overview

The app uses **flutter_map** (OpenStreetMap-based, no API key for tiles) with **MapTiler** raster tiles and **MapTiler Geocoding** (requires API key), plus **geolocator** for GPS and the **geocoding** package for reverse geocoding. Maps are used in exactly **one place**: the address pin-drop screen (`AddEditAddressScreen`), which is the delivery-address capture flow.

```
AddEditAddressScreen
├── FlutterMap + MapTiler streets-v2 raster tiles (AppConstants.maptilerKey)
├── Center pin-drop (map moves under a fixed pin) → lat/lng
├── Forward geocoding search (MapTiler /geocoding/{q}.json, PH bbox, 350ms debounce)
├── Reverse geocoding (geocoding package: placemarkFromCoordinates)
├── GPS auto-locate on open + manual "use my location" (geolocator)
└── Save → Address → AddressProvider → customer_addresses table
```

**Key facts:**

- **Packages (pubspec.yaml:54-57):** `geolocator ^14.0.3`, `geocoding ^5.0.0`, `flutter_map ^8.3.1`, `latlong2 ^0.10.1`.
- **Tile provider:** MapTiler `streets-v2` raster (`https://api.maptiler.com/maps/streets-v2/{z}/{x}/{y}.png?key=…`). The API key lives in `AppConstants.maptilerKey` (`lib/constants/app_constants.dart:13`) — **hardcoded in source, not dart_defines**.
- **Attribution required:** `RichAttributionWidget` with `© MapTiler © OpenStreetMap contributors` is rendered (usage policy); `showFlutterMapAttribution: false`.
- **Philippines-scoped search:** the geocoding call pins a bbox `116.927,4.587,126.603,21.119` (PH bounds) and `limit=5`.
- **Coordinates always saved:** every address row persists `latitude`/`longitude` even when the user typed everything manually (they come from the map center).

## B2. File Map

| Layer | File | Role |
|-------|------|------|
| Screen | `lib/screens/customer/add_edit_address_screen.dart` | The only map screen: pin-drop + search + GPS + reverse geocode + form |
| Screen | `lib/screens/customer/address_book_screen.dart` | Address list; entry point for Add/Edit |
| Model | `lib/models/address_model.dart` | `Address` with lat/lng :14-15; `toSnapshot()` :116 for orders |
| Provider | `lib/providers/address_provider.dart` | Add/update/delete/default via `AddressService` |
| Service | `lib/services/address_service.dart` | CRUD on `customer_addresses` (note `user_id`, NOT `customer_id`) |
| Constants | `lib/constants/app_constants.dart` | `maptilerKey` :13 |

## B3. Map Screen Flow (add_edit_address_screen.dart)

### B3.1 Two-step structure

- **Step A — map pin-drop** (`_showMap == true`, `_buildMapStep` :509): full-screen `FlutterMap` with a fixed center pin; panning the map moves `_currentCenter` (`onPositionChanged`, only when `hasGesture`).
- **Step B — address form** (`_buildFormStep` :959): recipient + Region/Province/City/Barangay/Street + landmark + label chips (Home/Work/Other) + default toggle.

Edit mode skips the map (`_showMap = false` immediately, form pre-filled from the existing `Address`).

### B3.2 Initialization

| Mode | Behavior |
|---|---|
| Add (new) | `_autoLocateOnOpen` (:249): check service → request permission → `Geolocator.getCurrentPosition(high accuracy, 10s timeLimit)` → move map → reverse geocode |
| Edit | Center = existing address lat/lng, straight to form |

Default center when GPS fails/denied: **Cebu** `LatLng(10.3157, 123.8854)`.

Permission-denied states produce friendly `_locationMessage` banners ("drag the pin to your address") instead of hard errors.

### B3.3 Forward geocoding (search)

- Debounced 350ms (`_searchDebounce`), min 2 chars.
- `GET https://api.maptiler.com/geocoding/{query}.json?key=…&bbox=PH&limit=5` via raw `HttpClient` (8s timeout, `User-Agent: com.solevision.app`).
- Guards: empty/placeholder key → "Search is not configured" error; 401/403 → "Invalid API key".
- Selecting a prediction: `_mapController.move(target, 17)` + reverse geocode to pre-fill the form.

### B3.4 Reverse geocoding

- `Geocoding().placemarkFromCoordinates(lat, lng)` (geocoding package → MapTiler under the hood).
- Maps placemark → Region (`administrativeArea`), Province (`subAdministrativeArea`), City (`locality ?? subLocality`), Barangay (`thoroughfare`), Street (`subThoroughfare + thoroughfare`).
- Errors are non-fatal: "fields remain editable" (:421).

### B3.5 Manual recenter

The "use my current location" button (`_useCurrentLocation` :309) re-runs the permission ladder with SnackBars and a Settings deep-link (`Geolocator.openAppSettings`) for `deniedForever`.

### B3.6 Save

`_saveAddress` (:433) builds an `Address` with the **map center as lat/lng**, then `AddressProvider.addAddress/updateAddress` → `AddressService` → `customer_addresses` (`user_id` column). Returns the saved `Address` via `Navigator.pop(result)` so checkout can select it immediately.

## B4. Data Model (customer_addresses + orders.shipping_address)

```
customer_addresses (user_id scoped — note: orders uses customer_id, don't conflate)
  id, user_id, label, recipient_name, recipient_phone,
  region, province, city_municipality, barangay, street_address, landmark,
  latitude, longitude, is_default, created_at

orders.shipping_address (JSONB snapshot taken at order time)
  → Address.toSnapshot(): recipientName, recipientPhone, region, province,
    cityMunicipality, barangay, streetAddress, landmark, latitude, longitude, label
```

Defaults are managed by a DB trigger (unset others) plus a belt-and-suspenders update in `AddressService.setDefaultAddress` (:63).

## B5. Known Pitfalls

1. **API key is committed in source** (`app_constants.dart:13`) — it is a runtime constant with no `dart_defines` indirection. Rotating it means a release. Do NOT add a second key in git; if the key leaks, rotate and update this constant.
2. **MapTiler tile URL embeds the key directly** — every tile request carries it; rate limits apply per key, so heavy testing can trip MapTiler quotas (then tiles go blank while search still works).
3. **Search/geocode bbox is hardcoded to the Philippines** — addresses outside the PH bbox won't be searchable (but manual pin-drop still works).
4. **`onPositionChanged` fires only on gestures** — programmatic moves (`_mapController.move`) don't update `_currentCenter`, which is why selection/GPS handlers explicitly `setState` the center.
5. **First-frame map move is deferred** via `addPostFrameCallback` (:289) because the `MapController` isn't attached until the first frame.
6. **No map anywhere else** — order tracking has no map; delivery addresses are text + coordinates only. If you add distance-based fees later, `orders.shipping_address` lat/lng is the data source, but the store's own location is not persisted for delivery (only `stores` basic profile).

---

## Related Docs

- `docs/AI/CHECKOUT_AND_GCASH_ARCHITECTURE.md` — GCash/PayMongo path where the server recomputes the fee
- `docs/AI/PAYMONGO_ONLINE_GCASH_TEST_PLAN.md` — `total_amount` = products + delivery assertions
- `docs/AI/CUSTOMER_MODULE_CONTEXT.md` / `docs/AI/checkout_screen_and_app_constants.md` — customer checkout context
- `docs/CUSTOMER_MODULE_DOCUMENTATION.md` — address book + map pin-drop feature docs
- `docs/SESSION_LOG_CUSTOMER_ADDRESSES_RLS_FIX.md` — RLS on `customer_addresses` INSERT
