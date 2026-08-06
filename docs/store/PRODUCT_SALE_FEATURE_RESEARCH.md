# Product "On Sale" Feature — Deep Research & File Map

**Goal:** Let a seller mark a product as *on sale* (discounted price, optionally
with start/end dates). The sale is visible in the **customer home** (badge +
strikethrough price + optional "On Sale" filter/section), and the **discounted
price flows all the way through cart → checkout → order**, including POS.

**Status:** Research complete — implementation-ready. No sale/discount fields
exist in the schema today (only a manual `Discount:` row in the POS UI, which
is unrelated). This is greenfield.

---

## 1. Feature shape (recommended data model)

Add **3 nullable columns** to the existing `products` table (keep `price` as the
*regular/original* price — never overwrite it):

| Column | Type | Meaning |
|---|---|---|
| `sale_price` | `NUMERIC` NULL | The discounted price while the sale is active |
| `sale_starts_at` | `TIMESTAMPTZ` NULL | Optional — sale goes live at this time (defaults to now) |
| `sale_ends_at` | `TIMESTAMPTZ` NULL | Optional — sale expires at this time (NULL = no end) |

**Convention (critical):** `price` is ALWAYS the original price. A product is
"on sale" only when `sale_price IS NOT NULL AND sale_price < price AND
(sale_starts_at IS NULL OR sale_starts_at <= now()) AND (sale_ends_at IS NULL
OR sale_ends_at >= now())`. Define this once in a shared helper (see §7) so
every screen computes the **effective price** identically.

No RLS changes needed — the existing `products` policies already cover the new
columns (SELECT public, UPDATE seller/admin).

---

## 2. Database layer

| File | Role | Touchpoint |
|---|---|---|
| `supabase/schema.sql` | Source-of-truth schema doc | `public.products` table starts at **line 164** (`price NUMERIC NOT NULL CHECK (price >= 0)` at line ~168, then `is_active`, `is_featured`, `is_published`). New columns go after `is_published`. |
| `supabase/migrations/` | Versioned DDL | **New file** `20260804000000_add_product_sale_fields.sql` following the existing naming convention. Add the 3 columns with `ADD COLUMN IF NOT EXISTS`. **Do not** add a CHECK that `sale_price < price` (sellers may want to clear a sale later by setting it above/equal) — enforce in the app layer instead. |

Suggested migration:

```sql
-- 20260804000000_add_product_sale_fields.sql
ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS sale_price     NUMERIC,          -- NULL = not on sale
  ADD COLUMN IF NOT EXISTS sale_starts_at TIMESTAMPTZ,      -- NULL = active immediately
  ADD COLUMN IF NOT EXISTS sale_ends_at   TIMESTAMPTZ;      -- NULL = never expires

CREATE INDEX IF NOT EXISTS idx_products_active_sale
  ON public.products (sale_price)
  WHERE sale_price IS NOT NULL;
```

---

## 3. Service layer (write path + read path)

| File | Role | Touchpoint |
|---|---|---|
| `lib/services/supabase_service.dart` | Customer-side data access (fetch + legacy add/update) | • `fetchProducts()` **line 138** — selects `*, stores(name), product_images(...), inventory(...), product_variants(...)`. New columns ride along automatically via `*`. <br>• `addProduct()` **line 158** — insert whitelist at **lines 167–180** (`name`, `category`, `price`, …, `is_featured`, `is_published`). **Add** `sale_price`, `sale_starts_at`, `sale_ends_at`. <br>• `updateProduct()` **line 191** — key whitelist at **lines 198–207**. **Add** the 3 sale keys. <br>• `_mapProduct()` **line 866** — maps rows to app maps; spreads `...row` (line 890) so sale fields flow through, but **coerce** `sale_price` to `double` next to the `'price'` coercion at **line 892**. |
| `lib/services/product_service.dart` | Seller-facing CRUD (create/update/delete with images, variants, customizations) | • `createProduct()` — add optional `salePrice`, `saleStartsAt`, `saleEndsAt` params; insert them in the `products` insert map alongside `'is_featured'`. <br>• `updateProduct()` **line 110** — same 3 params, add to the `update({...})` map. <br>• `toggleFeatured()` exists as the pattern for a future `toggleSale()`. |
| `lib/services/cart_service.dart` | Server-side cart restore | **Line 33** — queries product row (`id, size, color, stock, additional_price`). When a cart is restored from the DB, the effective price must be recomputed from `products.price`/`sale_price`, **not** from stale client-stored price. Verify this query joins `products` and add `sale_price` to the projection + effective-price logic. |

---

## 4. Provider / state layer

| File | Role | Touchpoint |
|---|---|---|
| `lib/providers/product_provider.dart` | Catalog state, filter, sort | • `_extractPrice()` (mid-file) — currently reads `product['price']` only. **Change to return the effective price** (sale-aware). This single change makes `priceLowToHigh` / `priceHighToLow` sorts correct under sales. <br>• `getFilteredProducts()` — add an **"On Sale" pseudo-category** filter (like the existing category filter) so the customer home can show only discounted items. <br>• Add a small public getter, e.g. `bool isOnSale(map)` or `double effectivePrice(map)`, delegating to the shared helper (§7) — screens should never inline the active-sale check. |

---

## 5. Customer UI layer (where the sale "shows")

| File | Role | Touchpoint |
|---|---|---|
| `lib/widgets/sole_product_card.dart` | Product card used in EVERY grid (home, store profile, collection) | • Price row: `'₱${price.toStringAsFixed(2)}'` (currently reads `product['price']`). **Show effective price + strikethrough original** when on sale. <br>• Add a **sale badge** — mirror the existing "Try On" badge (`Positioned` top-right in `_buildImageSection`); place a `SALE` / `-XX%` ribbon at top-left. <br>• ⚠️ Masonry contract: the card must stay **self-sizing** — the badge is a `Positioned` overlay, so aspect-ratio/id-hash stability is unaffected. **Do not change** `imageAspectRatio` behavior. |
| `lib/screens/customer/customer_home_screen.dart` | Customer landing page | • Category chips row — optionally append an **"On Sale"** chip (highlight-only, no checkmark — matches the recent chip styling). <br>• The masonry grid automatically shows sale badges once the card is updated. <br>• Recently-viewed strip price at **line 465** uses `item['price']` — switch to effective price if recently-viewed entries include it. <br>• (Future/optional) a dedicated "On Sale" sliver between Recently Viewed and the banner — reuse `SoleProductCard` + `SliverMasonryGrid`, **never** a fixed grid. |
| `lib/screens/customer/product_detail_screen.dart` | Product detail | • Price display block near **line 783** (`monoStyle` price) — show strikethrough original + sale price + "You save ₱X" / ends-on date. <br>• `_addToCart()` **lines 426–441** — `price` is read from `product['price']` and passed to `cart.addToCart(...)`. **Must pass the effective (sale) price** — this is the price that gets persisted in the cart. |
| `lib/screens/store/store_profile_screen.dart` | Store profile grid | Uses `SoleProductCard` masonry — sale badge/price come free. Its own `'Newest'` string-based sort (line 40) sorts by id/price — make its price sort effective-price-aware. |
| `lib/screens/store/collection_screen.dart` | Collection grid | Same — card-level changes apply automatically. |

---

## 6. Cart → checkout → order → POS (price integrity)

The sale price must survive the entire purchase pipeline. **Trace:**

1. `product_detail_screen._addToCart()` passes **effective price** → `cart_provider.addToCart(...)`.
2. `lib/providers/cart_provider.dart` **line 296**: `effectivePrice = price + additionalPrice;` → stored as `item['price']` (**line 309**). No change needed here **if** the detail screen passes the sale price — but the cart never re-validates against the DB, so an **expired sale** could still be charged at sale price if the customer sits on the cart screen. Decide (see §8): revalidate price on checkout, or accept the snapshot.
3. `lib/screens/customer/checkout_screen.dart` **line 218**: `'unit_price': item['price'] as double` → flows into `order_items.unit_price` and `orders.total_amount`. This is the **snapshot that the seller gets paid on** — correct automatically.
4. `lib/screens/seller/pos_screen.dart` — POS sells products at `product['price']` today. **Must use effective price** for in-store sales so POS doesn't undercut/ignore the sale. (Line 1101 has an unrelated manual `Discount:` row — leave it.) The seller product row widget `lib/widgets/seller/seller_product_row.dart` also displays price — show sale price there too.

---

## 7. Shared helper (recommended new file)

Create `lib/utils/sale_price.dart` (pure, unit-testable, no Flutter imports):

```dart
/// True only while the sale is active (not started / expired).
bool isOnSale(Map<String, dynamic> product, {DateTime? now});

/// The price the customer actually pays, or [product.price] when not on sale.
double effectivePrice(Map<String, dynamic> product, {DateTime? now});

/// Discount percent for badges: ((price - salePrice) / price * 100).round().
int? salePercent(Map<String, dynamic> product, {DateTime? now});
```

This is the **single source of truth** — the provider, cards, detail screen,
cart restore, and POS all call it, so the active-sale rule can never drift
between screens.

---

## 8. Open decisions to confirm before implementing

1. **Data model:** `sale_price` absolute value (recommended) vs `discount_percent` stored on the product. Absolute price is simpler for POS/cart math and survives price changes predictably.
2. **Expiry handling:** if a sale expires while an item is in the cart, should checkout (a) revalidate against the DB and charge the regular price, or (b) honor the snapshot the customer saw? (b) is simpler and matches current cart behavior; (a) needs a price-revalidation step in checkout.
3. **Does the discount apply in POS?** Almost certainly yes for consistency, but confirm — some sellers run POS at full price during storefront sales.
4. **Variant/customization extras:** apply the discount to the base price only, then add `additional_price` extras on top (recommended), or discount everything?
5. **"On Sale" surface on the customer home:** filter chip only, or a dedicated sliver section too?

---

## 9. Implementation order (suggested)

1. Migration (`20260804000000_add_product_sale_fields.sql`) + update `schema.sql`.
2. `lib/utils/sale_price.dart` + unit tests (active/not-started/expired/equal-price edge cases).
3. `SupabaseService` (fetch/add/update/`_mapProduct`) + `ProductService` (create/update) — pass sale fields through.
4. `ProductProvider` — effective price in `_extractPrice` + "On Sale" filter.
5. `SoleProductCard` — badge + strikethrough. (Customer home + store grids light up immediately.)
6. `product_detail_screen` — sale display + `_addToCart` uses effective price.
7. Seller UI — `add_edit_product_screen` (sale inputs) + `manage_products_screen` ("Set Sale" action, mirroring `_toggleFeatured` at line 294, plus an "On Sale" filter tab alongside the existing tabs at line 727).
8. POS + `cart_service` restore — effective price.
9. Verify: `flutter analyze`, full `flutter test`, and a manual walk of home → detail → cart → checkout → order.

---

## 10. Files that need NO changes (verified)

- `supabase/schema.sql` RLS policies for `products` (new columns covered).
- `SoleProductCard` masonry contract / `_imageAspectRatioFor` (id-hash based — sale badges are overlays).
- `lib/constants/app_constants.dart` (no pricing constants today; optionally add a `SALE` badge color here).
- `lib/models/product_models.dart` (variants/customizations models — sale lives on the product row, not variants).
