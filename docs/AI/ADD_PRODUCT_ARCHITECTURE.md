# Add Product Architecture

> **Purpose:** Detailed reference for AI agents working on the `AddEditProductScreen` — the full product creation/editing form for sellers. Covers UI structure, data models, service layer, variant system, customization system, and image management.

---

## 1. Overview

The Add/Edit Product screen is a **single, dual-purpose StatefulWidget** that handles both creating new products and editing existing ones. All data is persisted to Supabase via `ProductService`.

**File:** `lib/screens/seller/add_edit_product_screen.dart` (4,369 lines)

**Key behaviors:**
- Pass `product: null` → **Add mode** (clean form)
- Pass a product map → **Edit mode** (prefilled form)
- All data reads/writes go through `ProductService.instance` (singleton)
- Variants are managed via a bottom sheet with sizing system + multi-size + per-size color/stock
- Customizations are managed via a bottom sheet with name, type, choices, price
- Images are picked via `image_picker`, stored in Supabase Storage, and linked via `product_images` table

---

## 2. Form Structure (7 Sections)

```
┌─────────────────────────────────────────────────────┐
│  AppBar: "Add Product" / "Edit Product"             │
├─────────────────────────────────────────────────────┤
│                                                     │
│  SECTION 1: Product Images                          │
│  ├─ Horizontal scrollable row (max 6 images)       │
│  ├─ First image = "Main" (primary)                 │
│  ├─ Each image: preview + remove button             │
│  └─ "Add Photo" tile (opens image_picker)          │
│                                                     │
│  SECTION 2: Basic Info                              │
│  ├─ Product Name * (text field, 3-100 chars)       │
│  ├─ Category * (preset chip selector + custom)     │
│  ├─ Base Price (₱) * (number field)                │
│  └─ Description (multiline, max 500 chars)         │
│                                                     │
│  SECTION 3: Sale (Optional)                         │
│  ├─ Discounted price (₱)                           │
│  ├─ Start date (optional date picker)              │
│  └─ End date (optional date picker)                │
│                                                     │
│  SECTION 4: Barcode                                 │
│  └─ Barcode value (optional, max 50 chars)         │
│                                                     │
│  SECTION 5: Tags                                    │
│  └─ Grouped multi-select chips (Product type /     │
│     Material / Sustainability + Other per group)   │
│                                                     │
│  SECTION 6: Sizes & Variants                        │
│  ├─ List of existing variants (size · color)       │
│  ├─ Edit/Delete per variant                        │
│  └─ "Add Variant" button → opens variant sheet     │
│                                                     │
│  SECTION 7: Customization Options                   │
│  ├─ List of existing customizations                │
│  ├─ Edit/Delete per customization                  │
│  └─ "Add Customization" button → opens sheet       │
│                                                     │
│  SECTION 8: Visibility                              │
│  ├─ Active toggle (visible to customers)           │
│  └─ Featured toggle (appears in featured section)  │
│                                                     │
│  [Upload progress indicator]                        │
│  [Save/Update Product button]                       │
│                                                     │
└─────────────────────────────────────────────────────┘
```

---

## 3. Data Models

### `ProductVariant` (`lib/models/product_models.dart`)

Represents a single (size, color) combination with its stock and pricing.

```dart
class ProductVariant {
  final String? id;           // DB id (null for new variants)
  final String size;          // e.g. "EU 40", "US 8", "Kids 12"
  final String? color;        // e.g. "Black", "Burnished Clay" (nullable)
  final int stock;            // Quantity in stock (≥ 0)
  final double additionalPrice; // Extra cost on top of base price (₱)
  final String? sku;          // Stock Keeping Unit (nullable)

  // Serializes for DB insert
  Map<String, dynamic> toInsertMap(String productId);
  // Deserializes from DB row
  factory ProductVariant.fromMap(Map<String, dynamic> map);
}
```

**Size naming convention:** Sizes are stored as `"{SYSTEM} {VALUE}"` — e.g. `"EU 40"`, `"US 8"`, `"UK 3.5"`. Custom systems like `"JP 25"` follow the same pattern.

### `ProductCustomization` (`lib/models/product_models.dart`)

Represents a customization option (e.g. embroidery text, sole color choice).

```dart
class ProductCustomization {
  final String? id;           // DB id (null for new)
  final String optionName;    // e.g. "Embroidery Text", "Sole Color"
  final String optionType;    // 'text' | 'select' | 'color'
  final List<String> options; // Choice values (for 'select'/'color' types)
  final bool isRequired;      // Must customer provide this?
  final double additionalPrice; // Extra cost (₱)

  Map<String, dynamic> toInsertMap(String productId);
  factory ProductCustomization.fromMap(Map<String, dynamic> map);
}
```

### `_ImageItem` (private helper class)

```dart
class _ImageItem {
  final String? id;     // DB id for existing images
  final String? url;    // Remote URL for existing images
  final XFile? file;    // Local file for new picks
  // Assert: url != null || file != null (one must exist)
}
```

### `_ColorStockEntry` (private helper class)

Used inside the variant bottom sheet — represents one color+stock row per size.

```dart
class _ColorStockEntry {
  String color;
  final TextEditingController stockCtrl;  // default '0'
  final TextEditingController priceCtrl;  // default '0'
  final TextEditingController skuCtrl;    // default '10'
}
```

---

## 4. Variant System (Deep Dive)

The variant system is the most complex part of the form. It lives in `_showVariantSheet()` and manages:

### 4.1 Sizing Systems

Predefined sizing systems with their size lists:

```dart
static const Map<String, List<String>> _sizingSystems = {
  'US': ['3', '3.5', '4', '4.5', '5', ..., '15'],
  'EU': ['35', '35.5', '36', ..., '47'],
  'UK': ['2', '2.5', '3', ..., '15'],
};
```

**Custom systems** (e.g. JP, CHN, AUS) are supported via the "+ Other" chip — they have no preset sizes, so a free-text field appears instead.

### 4.2 Variant Sheet Flow

```
┌─────────────────────────────────────────────────┐
│  Add/Edit Variant  [?] (guide overlay)          │
├─────────────────────────────────────────────────┤
│                                                 │
│  Step 1: Sizing System *                         │
│  [US (American)] [EU (European)] [UK (British)] │
│  [+ Other]                                      │
│                                                 │
│  Step 2: Size * (select multiple)                │
│  [7] [7.5] [8] [8.5] [9] [9.5] [10] ...        │
│  [+ Other]                                      │
│                                                 │
│  Step 3: Colors & Stock per Size                 │
│  ┌─ Size 8 ─────────────────────────────────┐  │
│  │  ● ● ● ● ● ● ● ●  [+ Other]             │  │
│  │  [−][  3 ][+]  ₱___  SKU___              │  │
│  │  [+ Add Color]                            │  │
│  ├─ Size 9 ─────────────────────────────────┤  │
│  │  ● ● ● ● ● ● ● ●  [+ Other]             │  │
│  │  [−][  5 ][+]  ₱___  SKU___              │  │
│  │  [+ Add Color]                            │  │
│  └───────────────────────────────────────────┘  │
│  Total stock: 8                                 │
│                                                 │
│  [Add 2 Variants]                               │
│                                                 │
└─────────────────────────────────────────────────┘
```

### 4.3 Per-Size Color/Stock Architecture

Each selected size gets its own **list of `_ColorStockEntry`** objects stored in `perSizeColorStocks`:

```dart
Map<String, List<_ColorStockEntry>> perSizeColorStocks = {
  '8': [_ColorStockEntry(color: 'Black', stock: '3', price: '0', sku: 'ABC')],
  '9': [_ColorStockEntry(color: '', stock: '5', price: '0', sku: 'DEF')],
};
```

**On save**, this map is flattened into `ProductVariant` objects — one per (size, color) pair:

```
perSizeColorStocks['8'] = [Black(3), Brown(2)]
→ Variant(size: 'EU 8', color: 'Black', stock: 3)
→ Variant(size: 'EU 8', color: 'Brown', stock: 2)
```

### 4.4 Size Detection (Edit Mode)

When editing an existing variant, the system detects the sizing system from the stored size string:

```dart
String _detectSizingSystem(String size) {
  // 1. Check for prefix: "EU 40" → system "EU"
  // 2. Check numeric match against known systems
  // 3. Fallback: "Other"
}
```

Custom systems like `"JP 25"` are split on the first space → system `"JP"`, size `"25"`.

### 4.5 Variant Guide Overlay

A coach-mark spotlight overlay (`_VariantGuideOverlay`) walks sellers through the 4 steps:
1. **Sizing System** — Choose US/EU/UK or type custom
2. **Select Sizes** — Multi-select chips
3. **Colors & Stock** — Color swatches + stock stepper per size
4. **Save** — Tap to save all variants

Accessed via the `?` icon in the variant sheet header.

---

## 5. Customization System

### 5.1 Customization Sheet Flow

```
┌─────────────────────────────────────────────┐
│  Add/Edit Customization                     │
├─────────────────────────────────────────────┤
│                                             │
│  Option Name *                              │
│  [e.g. Embroidery Text, Sole Color]        │
│                                             │
│  Type *                                     │
│  [Text] [Select] [Color] [+ Other]         │
│                                             │
│  Choices (shown for 'select'/'color')       │
│  [Add a choice...] [+]                     │
│  [Choice1 ×] [Choice2 ×] [Choice3 ×]       │
│                                             │
│  Extra Price (₱) [0]                        │
│  Required [toggle]                          │
│                                             │
│  [Add/Update Customization]                 │
│                                             │
└─────────────────────────────────────────────┘
```

### 5.2 Customization Types

| Type | Behavior | Choices UI |
|------|----------|------------|
| `text` | Free-text input for customer | Hidden |
| `select` | Dropdown with predefined choices | Choice chips with add/remove |
| `color` | Color swatch picker with predefined colors | Choice chips with add/remove |
| *(custom)* | Any user-defined type via "+ Other" | Depends on usage |

---

## 6. Tag System

### 6.1 Tag Storage Format

Tags are stored in `products.tags` as a `TEXT[]` array with two formats:

- **Preset tags:** Plain snake_case id — e.g. `"handmade"`, `"genuine_leather"`, `"sustainable"`
- **Custom tags:** Prefixed with `custom:<group>:<text>` — e.g. `"custom:material:Vegan Suede"`

### 6.2 Tag Groups

Three preset groups plus a catch-all "Other" bucket:

```
┌─ Product Type ─────────────────────────────┐
│ [Oxford] [Loafer] [Sneaker] [Boot] ...     │
│ [+ Other]                                  │
├─ Material ─────────────────────────────────┤
│ [Genuine Leather] [Suede] [Canvas] ...     │
│ [+ Other]                                  │
├─ Sustainability ───────────────────────────┤
│ [Handmade] [Eco-Friendly] [Fair Trade] ... │
│ [+ Other]                                  │
└────────────────────────────────────────────┘
```

### 6.3 Tag Widget

`_ProductTagSelector` is a private widget that:
- Owns its selection state and animation scope
- Parses stored tags via `_parseStoredTag()` (handles presets, `custom:` format, legacy free text)
- Serializes via `_push()` and reports via `onChanged`
- Each group has its own "+ Other" input with validation (no duplicates, max 30 chars)

---

## 7. Image Management

### 7.1 Image States

Images can be in one of two states:
1. **Existing remote:** Has `id` and `url` (from DB) — displayed via `CachedNetworkImage`
2. **New local pick:** Has `file` (XFile) — displayed via `Image.memory()`

### 7.2 Image Operations

| Action | Method | Behavior |
|--------|--------|----------|
| Pick images | `_pickImages()` | Opens `ImagePicker.pickMultiImage()`, max 1200×1200, quality 85% |
| Remove image | `_removeImage(index)` | If existing: calls `ProductService.removeImage()` (DB + Storage). Removes from local list. |

### 7.3 Upload Flow (on save)

```
_imageItems
  ├─ Existing: filter by url != null → keep as existingImageUrls
  └─ New: filter by file != null → collect XFile list

ProductService.createProduct/updateProduct
  → _uploadImages()
    → For each XFile:
      → Read bytes
      → Upload to Storage: {sellerId}/{productId}/{timestamp}_{index}.{ext}
      → getPublicUrl()
      → Insert into product_images table
```

---

## 8. Save Flow

### 8.1 Validation

Before saving, the form validates:
1. **Form fields** — Name (3-100 chars), Price (> 0), Category (required), Description (≤ 500 chars)
2. **Images** — At least 1 image required
3. **Variants** — At least 1 variant required
4. **Store ID** — Must exist (loaded via `getSellerStoreId()`)
5. **Sale price** — If set, must be < base price

### 8.2 Create Flow

```
_saveProduct()
  → Validate form + images + variants + storeId + sale price
  → setState(_isSaving: true, _isUploading: true)
  → ProductService.createProduct(storeId, name, price, ..., images, variants, customizations)
    → 1. INSERT products row (returns productId)
    → 2. Upload images to Storage → get URLs
    → 3. INSERT product_images rows
    → 4. INSERT product_variants rows
    → 5. _syncInventoryFromVariants(productId, variants)
         → DELETE old inventory WHERE product_id = ?
         → INSERT aggregated inventory (one row per unique size, summing stock across colors)
         → Fire low_stock notifications if stock ≤ 5
    → 6. INSERT product_customizations rows
  → syncProductActiveStatus(productId) [fire-and-forget]
  → Pop with result=true
```

### 8.3 Update Flow

```
_saveProduct()
  → Validate form + images + variants + storeId + sale price
  → ProductService.updateProduct(productId, name, price, ..., newImages, existingUrls, variants, customizations)
    → 1. UPDATE products row (always sends sale fields — null clears sale)
    → 2. Upload new images → INSERT product_images rows
    → 3. DELETE product_variants WHERE product_id = ? → INSERT new variants
    → 4. _syncInventoryFromVariants() (same as create)
    → 5. DELETE product_customizations WHERE product_id = ? → INSERT new customizations
  → syncProductActiveStatus(productId) [fire-and-forget]
  → Pop with result=true
```

### 8.4 Inventory Sync Detail

`_syncInventoryFromVariants()` in `ProductService`:
- **Purpose:** Keep `inventory` table in sync with `product_variants`
- **Logic:** Groups variants by `size` (ignoring color), sums `stock` across colors per size
- **Result:** One inventory row per unique size with aggregated stock
- **Side effects:** Fires low-stock notifications if any size has stock ≤ 5

---

## 9. Private Widget Helpers

### Chip Selectors (reusable patterns)

| Widget | Purpose | Selection Mode |
|--------|---------|---------------|
| `_PresetChipSelector` | Single-select chips + custom "Other" | Radio-style (one active) |
| `_SizeMultiSelector` | Multi-select size chips + custom "Other" | Checkbox-style (many active) |
| `_SizeColorSelector` | Color swatch dots + custom "Other" | Single-select (toggle to deselect) |
| `_ColorSwatchPicker` | Color swatch chips + custom "Other" | Single-select (toggle to deselect) |
| `_ProductTagSelector` | Grouped multi-select tags | Checkbox-style per group |

### Chip Visual Widgets

| Widget | Purpose |
|--------|---------|
| `_TagChip` | Animated chip with pop-on-tap scale effect |
| `_CustomTagChip` | Filled chip with remove button (× + label) |
| `_OtherTagChip` | Dashed-border "Other" chip (toggle input) |
| `_SmallColorDot` | 30px circular color dot with selection ring |
| `_ColorSwatchChip` | 60px color swatch with name + check icon |
| `_AddCustomButton` | Filled "Add" button for custom input |
| `_CustomChipSwitcher` | AnimatedSwitcher for fade/scale chip transitions |

### Other Helpers

| Widget/Class | Purpose |
|--------------|---------|
| `_CompactSheetField` | Dense borderless text field (for ₱ / SKU in variant rows) |
| `_VariantGuideOverlay` | Coach-mark spotlight overlay with step navigation |
| `_SpotlightPainter` | CustomPainter for dark overlay + transparent cutout |
| `_DashedBorderPainter` | CustomPainter for dashed chip borders |
| `_ColorStockEntry` | Per-size color/stock/price/sku data holder |
| `_ImageItem` | Existing-URL or new-file image wrapper |
| `_GuideStep` | Step data for the variant guide overlay |

---

## 10. Category System

Categories are shared between the seller form and customer home filter:

```dart
static const List<String> _categories = AppConstants.productCategories;
```

The `_PresetChipSelector` renders them as chips with a "+ Other" option for custom categories.

---

## 11. Key Constants & Configuration

| Constant | Location | Value |
|----------|----------|-------|
| Max images | `_AddEditProductScreenState` | 6 |
| Max description length | Validator | 500 chars |
| Max product name length | Validator | 100 chars |
| Max barcode length | Validator | 50 chars |
| Max custom tag length | `_maxCustomTagLength` | 30 chars |
| Image picker max dimensions | `_pickImages()` | 1200×1200 |
| Image quality | `_pickImages()` | 85% |
| Preset colors | `_presetColors` | Black, Brown, Carob, Cream, Burgundy, Gold, Olive, Navy, Grey |
| Storage bucket | `ProductService._uploadImages()` | `'product-images'` |
| Sale validation | `_saveProduct()` | sale_price must be < base price |

---

## 12. File Map

| File | Role |
|------|------|
| `lib/screens/seller/add_edit_product_screen.dart` | Main add/edit form (4,369 lines) |
| `lib/models/product_models.dart` | ProductVariant + ProductCustomization models |
| `lib/services/product_service.dart` | Singleton CRUD service for products |
| `lib/widgets/seller/tag_selector.dart` | Shared tag presets (TagPreset, TagGroup, tagGroups) |
| `lib/constants/app_constants.dart` | Shared constants (categories, colors, styles) |
| `lib/constants/seller_theme_constants.dart` | Seller-specific theme (SellerTheme) |
| `lib/widgets/sole_card.dart` | Reusable card widget |
| `lib/widgets/sole_text_field.dart` | Reusable text field widget |
| `lib/widgets/sole_primary_button.dart` | Primary action button |
| `lib/widgets/sole_switch.dart` | Toggle switch widget |

---

## 13. Common Modification Patterns

### Adding a new variant field (e.g. weight)

1. Add field to `ProductVariant` model + `toInsertMap()` + `fromMap()`
2. Add UI field in `_showVariantSheet()` (inside the per-size row)
3. Add field to `_ColorStockEntry` if it's per-color
4. Add DB column + migration
5. Update `ProductService.createProduct()` and `updateProduct()` to pass the field

### Adding a new customization type

1. Add type string to the `_PresetChipSelector` presets in `_showCustomizationSheet()`
2. If the type needs special UI (like 'color' shows swatches), add conditional UI
3. The type is stored as `option_type` on `product_customizations`

### Modifying variant storage format

1. Update `ProductVariant.toInsertMap()` and `fromMap()`
2. Update `ProductService` CRUD methods
3. Update any existing variants display (e.g. `ManageProductsScreen`, `POSScreen`)
4. Consider a migration for existing data

---

## 14. Edge Cases & Gotchas

1. **Variant replacement strategy:** On update, ALL variants are deleted and re-inserted (not patched). This is simpler but means every edit touches all variants.

2. **Inventory sync timing:** `_syncInventoryFromVariants()` runs AFTER variants are inserted, so old inventory rows are replaced with fresh aggregated data.

3. **Active status auto-sync:** After save, `syncProductActiveStatus()` runs as fire-and-forget — if all stock is 0, the product is auto-deactivated.

4. **Sale price clearing:** Sale fields are ALWAYS sent on update (even as null) — this allows clearing a sale by emptying the sale price field.

5. **Image ordering:** The first image is always `is_primary: true` and `display_order: 0`. Reordering is not currently supported in the form.

6. **Size string format:** Sizes MUST be stored as `"{SYSTEM} {VALUE}"` — the edit-mode prefill logic depends on this format to detect the sizing system.

7. **Custom tags persistence:** Custom tags use the `custom:<group>:<text>` format so they survive round-trips through the tag selector and can be re-rendered in the correct group during edit mode.

8. **Variant count display:** The save button label dynamically shows "Add N Variants" based on the total (sizes × colors per size).
