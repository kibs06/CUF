# SoleVision — AR Virtual Try-On System Architecture

> **Generated:** July 30, 2026  
> **Purpose:** Complete reference for AI agents and developers working on the AR/virtual try-on feature.

---

## 1. Overview

The AR (Augmented Reality) Virtual Try-On system is a **simulated AR experience** that lets customers preview how shoes look on their feet before purchasing. It uses a placeholder camera feed with animated overlays to simulate an AR environment, combined with a fully functional product selection and add-to-cart workflow.

**Key distinction:** This is **not** a real AR system (no 3D model rendering, no actual camera feed, no foot tracking). It is a polished UI mockup that simulates the AR concept with:
- Animated scan lines and corner brackets (simulated camera feed)
- Pulsing tracking status indicators
- Product switching and size selection
- Direct add-to-cart integration

---

## 2. File Map

### Core AR Files

| File | Purpose |
|------|---------|
| `lib/screens/customer/ar_fitting_screen.dart` | **Main AR screen** — full-screen simulated AR experience with product selection, size chips, tracking indicators, tutorial overlay, and add-to-cart |
| `lib/widgets/ar_view_placeholder.dart` | **Camera feed placeholder** — animated scan line, corner brackets, "Place Foot Inside Box" guidance overlay. Accepts an optional `arView` widget for future real AR integration |
| `lib/widgets/sole_ar_pill.dart` | **CTA button widget** — pill-shaped "Try On in AR" button used on product detail screens to launch the AR experience |
| `lib/utils/cart_helpers.dart` | **Shared helpers** — `resolveVariant()`, `normalizeSize()`, `resolveInventoryStock()` used by both AR screen and product detail screen |

### Entry Points (Screens that launch AR)

| File | How AR is accessed |
|------|-------------------|
| `lib/screens/customer/customer_home_screen.dart` | `SoleProductCard.onTryOnTap` → `ARVirtualFitScreen(preselectedProduct: prod)` |
| `lib/screens/customer/product_detail_screen.dart` | `SoleARPill.onPressed` → `ARVirtualFitScreen(preselectedProduct: widget.product)` |
| `lib/screens/store/store_profile_screen.dart` | `SoleProductCard.onTryOnTap` → `ARVirtualFitScreen(preselectedProduct: prod)` |
| `lib/screens/store/collection_screen.dart` | `SoleProductCard.onTryOnTap` → `ARVirtualFitScreen(preselectedProduct: prod)` |
| `lib/screens/store/widgets/cross_store_product_row.dart` | `SoleProductCard.onTryOnTap` → `ARVirtualFitScreen(preselectedProduct: prod)` |

### Supporting Files

| File | Role |
|------|------|
| `lib/widgets/sole_product_card.dart` | Product card with "Try On" sticker badge (top-right corner) that triggers AR |
| `lib/providers/product_provider.dart` | Provides product list data to AR screen (used as fallback when no product preselected) |
| `lib/providers/cart_provider.dart` | Receives add-to-cart calls from AR screen |
| `lib/models/product_models.dart` | `ProductVariant` model (used for variant resolution in AR) |
| `lib/constants/app_constants.dart` | Design tokens: `accent` color (#4ECDC4, teal for AR mode), `surfaceDark` (#1A1208), typography, etc. |
| `lib/screens/auth/onboarding_screen.dart` | Slide 3: "Try It On with AR" introduction with custom SVG illustration |

---

## 3. Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                        USER ENTRY POINTS                        │
│                                                                 │
│  Home Screen ──┐    Product Detail ──┐    Store Profile ──┐     │
│  Collection ───┤    (SoleARPill)     │    (Product Card)  │     │
│  CrossStore ───┘                     └────────────────────┘     │
│         │                          │               │             │
│         └──────────────────────────┼───────────────┘             │
│                                    ▼                             │
│                     ┌──────────────────────┐                     │
│                     │  SoleProductCard      │                    │
│                     │  .onTryOnTap()        │                    │
│                     │  (or SoleARPill)      │                    │
│                     └──────────┬───────────┘                     │
│                                │                                 │
│                    Navigator.push(ARVirtualFitScreen)            │
│                                │                                 │
├────────────────────────────────┼─────────────────────────────────┤
│                                ▼                                 │
│              ┌─────────────────────────────────┐                 │
│              │     ARVirtualFitScreen           │                │
│              │  (ar_fitting_screen.dart)        │                │
│              │                                  │                │
│              │  Props: preselectedProduct?      │                │
│              │                                  │                │
│              │  ┌────────────────────────────┐  │                │
│              │  │   ARViewPlaceholder         │  │               │
│              │  │  • Animated scan line       │  │               │
│              │  │  • Corner brackets          │  │               │
│              │  │  • "Place Foot Inside Box"  │  │               │
│              │  └────────────────────────────┘  │                │
│              │                                  │                │
│              │  ┌────────────────────────────┐  │                │
│              │  │   Particle Overlay          │  │               │
│              │  │  (_ARParticlePainter)       │  │               │
│              │  └────────────────────────────┘  │                │
│              │                                  │                │
│              │  ┌────────────────────────────┐  │                │
│              │  │   Top Glassmorphism Bar     │  │               │
│              │  │  • Close button             │  │               │
│              │  │  • Product name + color     │  │               │
│              │  └────────────────────────────┘  │                │
│              │                                  │                │
│              │  ┌────────────────────────────┐  │                │
│              │  │   Bottom Glassmorphism Box  │  │               │
│              │  │  • Tracking status pulse    │  │               │
│              │  │  • Availability button      │  │               │
│              │  │  • Product carousel (52px)  │  │               │
│              │  │  • Size selector chips      │  │               │
│              │  │  • Add to Cart button       │  │               │
│              │  └────────────────────────────┘  │                │
│              │                                  │                │
│              │  ┌────────────────────────────┐  │                │
│              │  │   Tutorial Overlay          │  │               │
│              │  │  (first-time only)          │  │               │
│              │  │  3-step guide + "Got It"    │  │               │
│              │  └────────────────────────────┘  │                │
│              └──────────────────────────────────┘                │
│                         │                                        │
│              _addToCart() │                                       │
│                         ▼                                        │
│              ┌──────────────────────┐                            │
│              │   CartProvider       │                             │
│              │   .addToCart()       │                             │
│              └──────────────────────┘                            │
└─────────────────────────────────────────────────────────────────┘
```

---

## 4. Component Deep Dive

### 4.1 `ARVirtualFitScreen` — The Main AR Screen

**File:** `lib/screens/customer/ar_fitting_screen.dart`

```dart
class ARVirtualFitScreen extends StatefulWidget {
  final Map<String, dynamic>? preselectedProduct;
  const ARVirtualFitScreen({super.key, this.preselectedProduct});
}
```

**State class:** `_ARVirtualFitScreenState with TickerProviderStateMixin`

#### Key State Variables

| Variable | Type | Purpose |
|----------|------|---------|
| `_activeProduct` | `Map<String, dynamic>` | Currently displayed product |
| `_activeSize` | `String` | Selected EU size (e.g. `"40"`) |
| `_activeColor` | `String` | Selected color name (default: `"Burnished Clay"`) |
| `_isTracking` | `ValueNotifier<bool>` | Simulated foot-tracking status |
| `_showTutorial` | `bool` | First-time tutorial overlay visibility |
| `_pulseController` | `AnimationController` | Pulse animation for tracking dot (1s, repeat) |
| `_particleController` | `AnimationController` | Particle scatter animation (8s, repeat) |

#### Initialization Flow (`initState`)

1. **Resolve product:** Uses `preselectedProduct` if provided, otherwise falls back to first product from `ProductProvider`, or hardcoded demo data
2. **Initialize size:** First available size with stock > 0 from `product['sizes']` map
3. **Initialize color:** Defaults to `'Burnished Clay'`
4. **Start tracking simulation:** After 2500ms delay, `_isTracking` becomes `true`
5. **Start animations:** `_pulseController` (1s repeat) and `_particleController` (8s repeat)

#### Product Data Structure Expected

```dart
{
  'id': 1,
  'name': 'Carcar Classic Oxford',
  'price': 2499.00,         // int or double
  'images': ['https://...'], // List<String>, first image used
  'sizes': {                 // Map<String, int> — EU size → stock qty
    '38': 5,
    '39': 8,
    '40': 12,
    '41': 6,
    '42': 0,                 // 0 = out of stock
  },
  'product_variants': [      // List<Map> — optional, for variant resolution
    {'id': 'v1', 'size': '40', 'color': 'Burnished Clay', 'additional_price': 0}
  ],
  'store_id': 'uuid',
  'store_name': 'Carcar Leatherworks',
  'category': 'Classic',
  'description': 'Handcrafted...',
}
```

#### Key Methods

| Method | Purpose |
|--------|---------|
| `_switchProduct(product)` | Changes active product, resets tracking (1800ms relock delay) |
| `_checkSizeAvailability()` | Shows bottom sheet with stock levels per size |
| `_addToCart()` | Resolves variant via `resolveVariant()`, calls `CartProvider.addToCart()`, shows SnackBar |

#### UI Layer Stack (bottom to top)

1. `ARViewPlaceholder` — full-screen simulated camera feed
2. `_ARParticlePainter` — animated glowing dots near borders
3. Top glassmorphism bar — back button, product name, color
4. Bottom glassmorphism box — tracking status, product carousel, size chips, add-to-cart
5. Tutorial overlay (dismissible, shows first time only)

---

### 4.2 `ARViewPlaceholder` — Simulated Camera Feed

**File:** `lib/widgets/ar_view_placeholder.dart`

```dart
class ARViewPlaceholder extends StatefulWidget {
  final Widget? arView;  // Optional: if provided, renders this instead
  const ARViewPlaceholder({super.key, this.arView});
}
```

**State class:** `_ARViewPlaceholderState with SingleTickerProviderStateMixin`

#### Behavior

- If `arView` widget is provided → renders it directly (extension point for real AR)
- If `arView` is null → renders the simulated placeholder:
  - Dark background (`AppConstants.surfaceDark`)
  - Centered 220×320 rounded-rect target box with corner brackets
  - "Place Foot Inside Box" text with fit icon
  - Animated horizontal scan line (3s cycle, sweeping top→bottom)
  - "Simulating AR Foundation Camera Feed..." label

#### Corner Bracket System

The `_buildCorner(Alignment)` method draws 20×20px corner brackets using `Border` on a `Container`. Corners are positioned at `Alignment.topLeft`, `topRight`, `bottomLeft`, `bottomRight`.

---

### 4.3 `SoleARPill` — CTA Button

**File:** `lib/widgets/sole_ar_pill.dart`

```dart
class SoleARPill extends StatelessWidget {
  final VoidCallback onPressed;
  final String label;  // default: 'Try On in AR'
}
```

- Renders a pill-shaped `FilledButton` with `AppConstants.accent` (teal) background
- Eye icon + label text
- Box shadow with accent glow effect
- Used exclusively in `ProductDetailScreen` as a pinned floating button at bottom

---

### 4.4 `cart_helpers.dart` — Shared Utilities

**File:** `lib/utils/cart_helpers.dart`

#### `resolveVariant()`

```dart
({String? variantId, double additionalPrice}) resolveVariant({
  required List<dynamic> variants,
  required String size,
  String? color,
})
```

Iterates product variants, matches by size and optionally by color. Returns the best-matching variant ID and its additional price. Used by both `ar_fitting_screen.dart` and `product_detail_screen.dart`.

#### `normalizeSize()`

```dart
String normalizeSize(String size)  // "EU40" → "40", "US9" → "9"
```

#### `resolveInventoryStock()`

```dart
int resolveInventoryStock({...})  // Returns stock count or -1 if no match
```

---

## 5. Navigation Flow

### 5.1 From Product Card (Home / Store / Collection screens)

```
SoleProductCard.onTryOnTap
  └─ Navigator.push → ARVirtualFitScreen(preselectedProduct: prod)
```

The `SoleProductCard` widget renders a **"Try On" sticker badge** (top-right of the product image). Tapping it triggers `onTryOnTap` (not the main card `onTap` which goes to product detail).

### 5.2 From Product Detail Screen

```
ProductDetailScreen
  └─ SoleARPill (pinned floating button, bottom area)
       └─ onPressed → Navigator.push → ARVirtualFitScreen(preselectedProduct: widget.product)
```

The `SoleARPill` is positioned above the Add to Cart / Buy Now bar using `Positioned(bottom: 84)`.

### 5.3 Navigation Pattern

All AR navigation uses `MaterialPageRoute` push. The AR screen is a full-screen dark scaffold with no AppBar (custom close button in glassmorphism overlay).

---

## 6. Animations & Visual Effects

### 6.1 Tracking Pulse (`_pulseController`)

- **Duration:** 1 second, `repeat(reverse: true)`
- **Visual:** 10×10px circle that pulses with a shadow glow
- **Color:** `AppConstants.success` (green) when tracking locked, `AppConstants.accent` (teal) when searching
- **State:** `_isTracking` ValueNotifier — `false` initially, becomes `true` after 2500ms delay (or 1800ms after product switch)

### 6.2 Particle Scatter (`_particleController`)

- **Duration:** 8 seconds, `repeat()`
- **Visual:** 4 glowing circles (3-6px radius) animated along left/right edges
- **Color:** `AppConstants.accent` with 0.2 opacity
- **Implementation:** `_ARParticlePainter` (CustomPainter) calculates positions based on progress value

### 6.3 Scan Line (ARViewPlaceholder)

- **Duration:** 3 seconds, `repeat(reverse: true)`
- **Visual:** 3px horizontal line with accent glow shadow, sweeping vertically
- **Range:** From 20% to 70% of screen height

### 6.4 Tutorial Overlay

- Full-screen `Colors.black87` overlay
- Dismissible by tapping anywhere or the "Got It" button
- Sets `_showTutorial = false` (not persisted — shows every time the screen is opened)

---

## 7. Design Tokens Used

From `lib/constants/app_constants.dart`:

| Token | Value | Usage in AR |
|-------|-------|-------------|
| `AppConstants.accent` | `#4ECDC4` (Celadon Teal) | AR mode color — buttons, scan line, tracking, particles, badges |
| `AppConstants.surfaceDark` | `#1A1208` (Midnight Canvas) | AR screen background, glassmorphism overlays |
| `AppConstants.success` | `#6B8F47` (Olive Stitch) | Tracking locked indicator |
| `AppConstants.error` | `#D64545` (Crimson Welt) | Out-of-stock indicators |
| `AppConstants.secondary` | `#3B2314` (Carob Dark) | Text on accent backgrounds |
| `AppConstants.surfaceLight` | `#F5F0EB` (Off-White Suede) | Text on dark backgrounds |
| `AppConstants.cardRadius` | `BorderRadius.circular(16)` | Glassmorphism panels |
| `AppConstants.buttonRadius` | `BorderRadius.circular(12)` | Add to Cart button |

Typography:
- `AppConstants.headlineStyle()` → Playfair Display
- `AppConstants.bodyStyle()` → DM Sans
- `AppConstants.monoStyle()` → JetBrains Mono (size chips)

---

## 8. Data Flow

### 8.1 Product Data

```
Supabase DB → SupabaseService.fetchProducts() → ProductProvider.products
                                                        │
                                                        ▼
                                          ARVirtualFitScreen
                                          (reads productProvider.products
                                           as fallback when no preselectedProduct)
```

### 8.2 Add to Cart

```
ARVirtualFitScreen._addToCart()
  ├─ resolveVariant(variants, size, color)  → variantId, additionalPrice
  ├─ CartProvider.addToCart(
  │     productId, productName, imageUrl, price,
  │     size, color, variantId, additionalPrice
  │   )
  └─ ScaffoldMessenger.showSnackBar(...)
```

### 8.3 Product Data Shape

Products are `Map<String, dynamic>` objects fetched from Supabase. The AR screen specifically reads:
- `product['id']` — unique identifier
- `product['name']` — display name
- `product['price']` — price (int or double)
- `product['images']` — `List<String>` of image URLs
- `product['sizes']` — `Map<String, dynamic>` where keys are EU sizes and values are stock quantities (0 = out of stock)
- `product['product_variants']` — `List<Map>` for variant resolution (optional, used by `resolveVariant()`)

> **Note:** `store_id` is present in the product data but is **not used** by the AR screen — it is only relevant for the cart/order flow.

---

## 9. Integration with Onboarding

**File:** `lib/screens/auth/onboarding_screen.dart`

The third onboarding slide (Slide 3) introduces the AR feature:
- **Headline:** "Try It On with AR"
- **Body:** "Use our augmented reality feature to see how shoes look on your feet before you buy."
- **SVG:** Custom illustration showing a phone with a foot outline and dashed shoe overlay, corner brackets, and AR sparkle dots

This is purely informational — it does not deep-link to the AR screen.

---

## 10. Current Limitations & Future Work

### Current State
- **No real AR:** The camera feed is a simulated placeholder with animated overlays
- **No 3D rendering:** No shoe models are rendered in 3D space
- **No foot tracking:** The tracking status is a timer-based simulation
- **No persistence (by design):** Tutorial overlay re-shows every session — no `SharedPreferences` usage. This is intentional for demo/prototype purposes.
- **Hardcoded color:** `_activeColor` always defaults to `'Burnished Clay'` — color swatches are not displayed in AR
- **Size fallback:** When initializing `_activeSize`, if no size has stock > 0, it falls back to `'39'` via `orElse: () => '39'`. This avoids crashes but may show an unavailable size.
- **`store_id` not used by AR:** While product data contains `store_id`, the AR screen does not reference it (only the cart/order flow uses it).
- **Sizes from `product['sizes']` map:** Uses a simple `{size: stock}` map rather than the full `product_variants`/`inventory` tables used by product detail screen

### Extension Points for Real AR
1. **`ARViewPlaceholder(arView: ...)`** — The `arView` parameter accepts a widget to render instead of the placeholder. A real AR camera feed (e.g., from `ar_flutter_plugin` or a WebAR WebView) can be passed here.
2. **Product data is passed in** — `ARVirtualFitScreen` accepts `preselectedProduct` and reads from `ProductProvider`, making it easy to swap data sources.
3. **Variant resolution** — Uses the same `resolveVariant()` helper as product detail, ensuring consistency if real 3D models need variant-specific rendering.

### Potential Improvements
- Persist tutorial seen state in `SharedPreferences`
- Add a real AR library (e.g., `model_viewer_plus` for 3D shoe models, or `arkit_plugin`/`arcore_flutter_plugin` for foot tracking)
- Add color swatches to AR screen (currently hardcoded)
- Use `product_variants` + `inventory` tables for stock display (matching product detail screen)
- Add screenshot/share functionality from AR view
- Add "Buy Now" shortcut from AR screen (currently only Add to Cart)

---

## 11. Testing Notes

- The AR screen depends on `ProductProvider` being initialized in the widget tree (via `ChangeNotifierProvider`)
- `CartProvider` must be available for the add-to-cart flow
- The screen uses `TickerProviderStateMixin` — requires a `vsync` provider (handled by Flutter's `State`)
- No unit tests exist specifically for the AR screen — manual testing recommended

---

## 12. Quick Reference — Key Classes & Widgets

```
ARVirtualFitScreen          ← Main AR screen (StatefulWidget)
  _ARVirtualFitScreenState  ← State with animations, tracking, product logic
  _ARParticlePainter        ← CustomPainter for ambient particle effect

ARViewPlaceholder           ← Simulated camera feed (StatefulWidget)
  _ARViewPlaceholderState   ← Manages scan line animation

SoleARPill                  ← CTA button widget (StatelessWidget)

resolveVariant()            ← Shared variant resolution helper
normalizeSize()             ← Size string normalization
resolveInventoryStock()     ← Inventory stock lookup

SoleProductCard             ← Product card with "Try On" badge (entry point)
```

---

*This document is intended for AI agents and developers. For UI/UX questions, refer to the visual design assets or run the app.*
