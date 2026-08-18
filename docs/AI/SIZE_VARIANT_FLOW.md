# Size & Variant Flow

> **Purpose:** End-to-end reference for how sizes, variants, and colors work — from the seller's "Add Color" sheet through the database to the customer's product page.

---

## 1. Overview

The variant system has two layers:

1. **Color** (`ProductColor`) — the top-level entity the seller creates. Each color owns its own photo gallery and a list of size/stock variants.
2. **Variant** (`ProductVariant`) — a single (size, color, stock) row stored in `product_variants`. Multiple variants belong to one color.

A seller never adds a "variant" directly. They add a **color**, then add **sizes** under that color.

```
ProductColor "Black"
  ├── images: [img1.jpg, img2.jpg]
  └── variants:
        ├── ProductVariant(size: "EU 40", stock: 3)
        ├── ProductVariant(size: "EU 41", stock: 5)
        └── ProductVariant(size: "EU 42", stock: 0)

ProductColor "Brown"
  ├── images: [img3.jpg]
  └── variants:
        ├── ProductVariant(size: "EU 40", stock: 2)
        └── ProductVariant(size: "EU 41", stock: 4)
```

---

## 2. Sizing Systems

Defined in `add_edit_product_screen.dart` as `_sizingSystems`:

```dart
static const Map<String, List<String>> _sizingSystems = {
  'US': ['3', '3.5', '4', '4.5', '5', '5.5', '6', '6.5', '7', '7.5', '8', '8.5', '9', '9.5', '10', '10.5', '11', '11.5', '12', '13', '14', '15'],
  'EU': ['35', '35.5', '36', '36.5', '37', '37.5', '38', '38.5', '39', '39.5', '40', '40.5', '41', '41.5', '42', '42.5', '43', '43.5', '44', '44.5', '45', '45.5', '46', '47'],
  'UK': ['2', '2.5', '3', '3.5', '4', '4.5', '5', '5.5', '6', '6.5', '7', '7.5', '8', '8.5', '9', '9.5', '10', '10.5', '11', '12', '13', '14', '15'],
};
```

Custom systems (JP, CHN, AUS, etc.) are supported via the "+ Other" chip — they have no preset sizes, so a free-text field appears.

**Size naming convention:** Sizes are stored as `"{SYSTEM} {VALUE}"` — e.g. `"EU 40"`, `"US 8"`, `"UK 3.5"`. Custom systems like `"JP 25"` follow the same pattern.

---

## 3. Seller UI Flow

### 3.1 Adding a Color

```
Add Color sheet
├── Step 1: Color Name
│   └── _PresetChipSelector (Black, Brown, ..., + Other)
│       └── allowDeselect: true (tap again to unselect)
│
├── Step 2: Photos for this color
│   └── Horizontal scrollable grid (max 6 images)
│       ├── Each image: preview + remove button
│       └── "Add" tile → opens image_picker
│
├── Step 3: Sizes & Stock
│   └── "Add Sizes" button → opens _showVariantSheetForColor()
│       └── Returns List<ProductVariant> with color set
│   └── Shows list of added sizes with stock/price
│
└── "Add Color" button (disabled until name + photo)
```

### 3.2 Adding Sizes (Variant Sheet)

The variant sheet is opened by `_showVariantSheetForColor()`, which:
1. Temporarily swaps `_variants` with the color's existing variants
2. Opens `_showVariantSheet(colorOverride: colorName)`
3. On save: the sheet writes variants to `_variants` with the color name set
4. `_showVariantSheetForColor()` reads the result and returns it

```
Variant Sheet (scoped to a color)
├── Step 1: Sizing System
│   └── _PresetChipSelector: US (American) / EU (European) / UK (British) / + Other
│       └── Changing system clears selected sizes
│
├── Step 2: Size (select multiple)
│   └── _SizeMultiSelector: checkbox-style multi-select chips
│       ├── Preset sizes from _sizingSystems[selectedSystem]
│       └── "+ Other" for custom sizes (free-text)
│       └── Changing selected sizes updates perSizeColorStocks map
│
├── Step 3: Stock per Size
│   └── For each selected size:
│       ├── Size badge (brown circle with size value)
│       ├── Stock stepper: [−] [count] [+]
│       ├── Extra Price field (₱)
│       └── SKU field
│   └── "Add Color" per size (legacy mode only — not used in color-scoped mode)
│   └── Total stock summary
│
└── Save button: "Add N Variants"
```

### 3.3 Size String Format

The size string stored in `product_variants.size` combines the system and value:

```
System: EU, Value: 40  →  Stored as: "EU 40"
System: US, Value: 8   →  Stored as: "US 8"
System: JP, Value: 25  →  Stored as: "JP 25" (custom system)
```

**Why this matters:** The customer product detail screen uses `_detectSizingSystem()` to parse the stored size and determine which sizing system to display. The unit switcher (US/EU/UK) converts between systems for display while keeping the canonical string untouched.

### 3.4 Color-Scoped vs Standalone Mode

The variant sheet operates in two modes:

| Mode | Trigger | Color handling |
|------|---------|---------------|
| **Color-scoped** | `_showVariantSheet(colorOverride: "Black")` | All variants get `color: "Black"` — color picker section skipped |
| **Standalone** | `_showVariantSheet()` (no colorOverride) | Each size can have multiple color entries via per-size color picker (legacy) |

The color sheet always uses color-scoped mode.

---

## 4. Data Model

### `ProductVariant` (`lib/models/product_models.dart`)

```dart
class ProductVariant {
  final String? id;           // DB id (null for new)
  final String size;          // e.g. "EU 40", "US 8"
  final String? color;        // e.g. "Black" (matches ProductColor.name)
  final int stock;            // Quantity (≥ 0)
  final double additionalPrice; // Extra cost on top of base price (₱)
  final String? sku;          // Stock Keeping Unit
}
```

### `ProductColor` (`lib/models/product_models.dart`)

```dart
class ProductColor {
  final String? id;                     // DB id (null for new)
  final String name;                    // e.g. "Black"
  final List<ProductColorImage> images; // must have length >= 1
  final List<ProductVariant> variants;  // sizes/stock for this color

  bool get hasImages => images.isNotEmpty;
  bool get hasVariants => variants.isNotEmpty;
  int get totalStock => variants.fold(0, (sum, v) => sum + v.stock);
  int get sizeCount => variants.map((v) => v.size).toSet().length;
}
```

### `ProductColorImage` (`lib/models/product_models.dart`)

```dart
class ProductColorImage {
  final String? id;       // DB id (null for new)
  final String? url;      // Remote URL (existing)
  final XFile? file;      // Local file (new pick)
  final int displayOrder; // 0 = primary thumbnail
}
```

---

## 5. Database Schema

### `product_variants` (existing)

```sql
CREATE TABLE product_variants (
    id              BIGINT PRIMARY KEY,
    product_id      UUID REFERENCES products(id) ON DELETE CASCADE,
    size            TEXT NOT NULL,          -- "EU 40", "US 8", etc.
    color           TEXT,                   -- matches ProductColor.name
    stock           INTEGER NOT NULL DEFAULT 0 CHECK (stock >= 0),
    additional_price NUMERIC NOT NULL DEFAULT 0,
    sku             TEXT
);
```

### `product_color_images` (new)

```sql
CREATE TABLE product_color_images (
    id              BIGINT PRIMARY KEY,
    product_id      UUID REFERENCES products(id) ON DELETE CASCADE,
    color_name      TEXT NOT NULL,          -- matches product_variants.color
    url             TEXT NOT NULL,
    display_order   INTEGER NOT NULL DEFAULT 0,
    created_at      TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_product_color_images_product_color
    ON product_color_images (product_id, color_name);
```

**Design decision:** We use `color_name` (TEXT) as the join key rather than a separate `product_colors` table. This keeps `product_variants.color` as the single source of truth for color identity, so `_syncInventoryFromVariants()` (which groups by size, ignoring color) continues to work unchanged.

### `inventory` (unchanged)

```sql
-- One row per unique (product_id, size), sums stock across colors
CREATE TABLE inventory (
    product_id  UUID REFERENCES products(id) ON DELETE CASCADE,
    size        TEXT NOT NULL,
    stock       INTEGER NOT NULL DEFAULT 0,
    updated_at  TIMESTAMPTZ DEFAULT now(),
    PRIMARY KEY (product_id, size)
);
```

---

## 6. Save Flow

### 6.1 Validation

```
_saveProduct()
  ├── Form valid? (name, price, category, description)
  ├── At least 1 product image?
  ├── At least 1 color? (_colors.isNotEmpty)
  ├── Every color has at least 1 photo? (_colors.where(!hasImages))
  ├── Store ID exists?
  └── Sale price < base price?
```

### 6.2 Create Flow

```
_saveProduct()
  ├── Flatten colors → allVariants
  │     for each ProductColor in _colors:
  │       allVariants.addAll(color.variants)
  │
  └── ProductService.createProduct(colors: _colors, variants: allVariants)
        ├── 1. INSERT products row → productId
        ├── 2. Upload general images → INSERT product_images
        ├── 3. INSERT product_variants (all colors' variants flattened)
        ├── 4. _syncInventoryFromVariants(productId, allVariants)
        │     ├── DELETE old inventory
        │     ├── Group by size, sum stock across colors
        │     └── INSERT aggregated inventory rows
        ├── 5. INSERT product_customizations
        └── 6. For each ProductColor:
              └── _syncColorImages(productId, color.name, color.images)
                    ├── Upload new files to Storage: {sellerId}/{productId}/colors/{colorName}/{timestamp}_{i}.{ext}
                    └── INSERT product_color_images rows
```

### 6.3 Update Flow

```
_saveProduct()
  ├── Flatten colors → allVariants
  └── ProductService.updateProduct(colors: _colors, variants: allVariants)
        ├── 1. UPDATE products row
        ├── 2. Upload new general images → INSERT product_images
        ├── 3. DELETE product_variants WHERE product_id = ? → INSERT new
        ├── 4. _syncInventoryFromVariants (same as create)
        ├── 5. DELETE product_customizations → INSERT new
        └── 6. DELETE product_color_images WHERE product_id = ?
              For each ProductColor:
                └── _syncColorImages (upload + insert)
```

---

## 7. Inventory Sync

`_syncInventoryFromVariants()` groups variants by **size** (ignoring color) and sums stock:

```
Variants:
  Black · EU 40 · stock 3
  Black · EU 41 · stock 5
  Brown · EU 40 · stock 2

→ inventory:
  EU 40: 5  (3 + 2)
  EU 41: 5
```

**Key behavior:** Inventory is the authoritative stock source for the customer size selector and the Adjust Stock editor. Low-stock notifications fire when any size has stock ≤ 5.

---

## 8. Customer UI

### 8.1 Color Selector

The product detail screen shows color swatches with thumbnails:

```
Select Color / Leather
┌──────┐ ┌──────┐ ┌──────┐
│ 📷   │ │ 📷   │ │ 📷   │
│Black │ │Brown │ │Cream │
└──────┘ └──────┘ └──────┘
```

- If `product_color_images` has images for a color → shows the first image as a thumbnail
- If no color images → falls back to a colored dot (deterministic from name)
- Tapping a color:
  1. Sets `_selectedColor`
  2. Swaps the image gallery to that color's photos (`_sortedImageUrls` checks `product_color_images` first)
  3. Filters the size picker to that color's variants only (`_buildSizesMap()` filters by color)

### 8.2 Image Gallery

`_sortedImageUrls` priority:
1. `product_color_images` filtered by `_effectiveColor` → sorted by `display_order`
2. `product_images` (general product photos) → sorted by `display_order`
3. `images` flat list (legacy fallback)

### 8.3 Size Picker

`_buildSizesMap()` behavior:
- When a color is selected → reads only variants matching that color
- When no color selected → reads all variants + inventory table
- Sorts numerically by EU size

### 8.4 Variant Lookup (Add to Cart)

```dart
resolveVariant(
  variants: product['product_variants'],
  size: _selectedSize!,
  color: _effectiveColor,
)
```

Returns `variantId` and `additionalPrice` for the matching (size, color) pair.

---

## 9. Edit Mode Prefill

When editing a product, `_prefillFromProduct()` rebuilds `_colors` from the DB data:

```
product_variants: [{size: "EU 40", color: "Black", stock: 3}, ...]
product_color_images: [{color_name: "Black", url: "...", display_order: 0}, ...]

→ _colors:
  ProductColor(
    name: "Black",
    images: [ProductColorImage(url: "...")],
    variants: [ProductVariant(size: "EU 40", stock: 3)],
  )
```

Grouping logic:
1. Group `product_variants` by `color` field → `Map<String, List<ProductVariant>>`
2. Group `product_color_images` by `color_name` → `Map<String, List<ProductColorImage>>`
3. Merge into `ProductColor` objects

---

## 10. Data Flow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│  SELLER UI                                                      │
│                                                                 │
│  Add Color Sheet                                                │
│  ├── Color Name (chip selector)                                 │
│  ├── Photos (image_picker → XFile list)                         │
│  └── Add Sizes → Variant Sheet                                  │
│       ├── Sizing System (US/EU/UK/custom)                       │
│       ├── Size Multi-select (chip list)                         │
│       └── Stock/Price/SKU per size                              │
│                                                                 │
│  On "Add Color" save:                                           │
│  → ProductColor(name, images, variants) added to _colors        │
│                                                                 │
│  On "Save Product":                                             │
│  → _colors flattened → allVariants                              │
│  → ProductService.createProduct/updateProduct(colors, variants) │
└─────────────────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────────┐
│  SERVICE LAYER (ProductService)                                 │
│                                                                 │
│  createProduct:                                                 │
│  1. INSERT products row                                         │
│  2. Upload general images → product_images                      │
│  3. INSERT product_variants (flattened, color on each row)      │
│  4. _syncInventoryFromVariants (group by size, sum stock)       │
│  5. INSERT product_customizations                               │
│  6. For each color: upload images → product_color_images        │
│                                                                 │
│  updateProduct:                                                 │
│  Same as create, but DELETE + re-insert for variants,           │
│  customizations, and color images                               │
└─────────────────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────────┐
│  DATABASE                                                       │
│                                                                 │
│  products           product_variants        product_color_images │
│  ┌──────────┐      ┌──────────────┐       ┌──────────────────┐ │
│  │ id (UUID)│─────→│ product_id   │──────→│ product_id       │ │
│  │ name     │      │ size ("EU 40")│      │ color_name       │ │
│  │ price    │      │ color ("Black")│     │ url              │ │
│  │ ...      │      │ stock        │       │ display_order    │ │
│  └──────────┘      │ sku          │       └──────────────────┘ │
│                     └──────────────┘                            │
│                                                                 │
│  inventory                                                     │
│  ┌──────────────────┐                                          │
│  │ product_id       │  ← synced from product_variants          │
│  │ size             │    groups by size, sums stock            │
│  │ stock            │                                          │
│  └──────────────────┘                                          │
└─────────────────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────────┐
│  CUSTOMER UI (ProductDetailScreen)                              │
│                                                                 │
│  Color selector → thumbnail grid from product_color_images      │
│  Image gallery → swaps to color's photos when color selected    │
│  Size picker → filtered to selected color's variants            │
│  Add to cart → resolveVariant(size, color) → variant_id + price │
└─────────────────────────────────────────────────────────────────┘
```

---

## 11. Key Methods Reference

| Method | File | Purpose |
|--------|------|---------|
| `_showColorSheet()` | add_edit_product_screen.dart | Add/edit a color: name, photos, sizes |
| `_showVariantSheet()` | add_edit_product_screen.dart | Add sizes with stock (sizing system → sizes → stock per size) |
| `_showVariantSheetForColor()` | add_edit_product_screen.dart | Wraps `_showVariantSheet` scoped to a specific color |
| `_prefillFromProduct()` | add_edit_product_screen.dart | Rebuilds `_colors` from DB data for edit mode |
| `_saveProduct()` | add_edit_product_screen.dart | Validates + flattens colors → calls service |
| `createProduct()` | product_service.dart | DB write: products → images → variants → inventory → color images |
| `updateProduct()` | product_service.dart | DB write: same as create, delete+re-insert for variants/color images |
| `_syncInventoryFromVariants()` | product_service.dart | Aggregates stock by size across all colors |
| `_syncColorImages()` | product_service.dart | Uploads color images to Storage + inserts DB rows |
| `_buildSizesMap()` | product_detail_screen.dart | Builds {size: stock} map, filtered by selected color |
| `_sortedImageUrls` | product_detail_screen.dart | Image gallery: color images first, then general, then legacy |
| `resolveVariant()` | cart_helpers.dart | Finds variant_id + additional_price for (size, color) pair |

---

## 12. Edge Cases

1. **Legacy products without color images:** Products created before this feature have `product_variants.color` but no `product_color_images` rows. The customer UI falls back to general `product_images`. The seller UI shows a warning badge on the color card.

2. **Inventory sync is color-agnostic:** `_syncInventoryFromVariants()` groups by size only, summing stock across colors. This is intentional — the customer size selector shows total stock per size regardless of color.

3. **Size string format is load-bearing:** The `"SYSTEM VALUE"` format is parsed by `_detectSizingSystem()` on the customer side. Changing this format would break the unit switcher.

4. **Variant replacement strategy:** On update, ALL variants are deleted and re-inserted (not patched). Same for color images. This is simpler but means every edit touches all rows.

5. **Color name is the join key:** `product_variants.color` and `product_color_images.color_name` must match exactly. There's no foreign key between them — the app ensures consistency.
