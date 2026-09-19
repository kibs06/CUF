# Product Audience Plan — Who a Product Is For (Men's / Women's / Kids')

**Date:** September 18, 2026
**Status:** **All phases complete — P0–P4 shipped, P5 verified and documented (2026-09-19) · the switch is on · the audience chip row + per-audience listing page built on request (see the note below the P5 section).** The column is live, the vocabulary exists, sellers can set, change and clear a product's audience on Add / Edit Product, and the three home rails (Men's / Women's / Kids') and audience-aware size-chart labels are all **live** — `AppConstants.productAudienceEnabled` is `true` (and remains the whole rollback).

The one thing P5 could **not** complete here is the on-device pass: real fonts, real banner images, a real phone. Everything that a widget test and a seeded regression catalog can settle is settled and recorded under P5 below; the device sweep on a tagged catalog is the remaining step, and it is listed there as open rather than claimed.

**Turning it on changed nothing on screen, and that is the point of the rollout order:** every audience surface is data-derived, so with all 15 live products still `audience = null` (P4 has since run and measured exactly that: 15 of 15 unset) the rails render nothing, the new audience chips render nothing, and `productSizeChart()` returns the shopper's own scale verbatim. Home, search and every size label are byte-for-byte what they were with the switch off. What has *not* been verified is the surfaces **with data** — that is what P4 + the P5 QA table below are for, and the flip does not stand in for them. See the "Shipped"/"Landed" notes under P0–P3 for what landed and where it deviated from this doc's sketch.
**Scope:** Give products an *audience* dimension, so browse can offer Men's / Women's / Kids' sections and so US/UK size labels come from the product's own chart instead of the shopper's saved scale.
**Schema change:** one nullable column on `public.products` (+ a `CHECK`). **The migration must be applied before the client build that writes it** — a missing column fails the write and the client reports it as a generic error (see §5 R5, the exact failure `20260917130000_add_foot_size_category.sql` produced).
**Related:** `docs/AI/SIZE_AWARE_SHOPPING_PLAN.md` (the size surfaces this sits beside) · `docs/AI/SIZE_VARIANT_FLOW.md` (**the size contract this must not break**) · `docs/AI/PRODUCT_ARCHITECTURE.md` · `docs/AI/CUSTOMER_HOME_ARCHITECTURE.md` · `docs/AI/seller_products_architecture.md` · `docs/AI/SELLER_APPLICATION_UI_ARCHITECTURE.md`

---

## How to work this doc

Six phases. P0–P4 are independently shippable and independently revertable; **P2 (the visible part) ships behind `AppConstants.productAudienceEnabled`**, so landing the phase is not the same as showing it.

```bash
# After EVERY phase — the gate before moving on:
flutter analyze lib test && flutter test
```

---

## Phase overview

| Phase | Deliverable | Visible to customers? | Est. | Depends on |
|---|---|---|---|---|
| **P0** ✅ | The column, the vocabulary, the pure helpers | No | 0.5 day | migration applied |
| **P1** ✅ | Seller input on Add / Edit Product | Sellers only | 0.5–1 day | P0 |
| **P2** ✅ *(dark)* | Men's / Women's / Kids' home rails | Yes, behind the switch | 0.5 day | P1 (data), P0 |
| **P3** ✅ *(dark)* | US/UK labels from the product's own chart | Yes, behind the switch | 0.5 day | P0 |
| **P4** | Unset-audience backfill + admin visibility | Sellers / admins | 0.5–1 day | P1 |
| **P5** | QA, docs, switch-on, delete dead code | — | 0.5 day | P2–P4 |

**Rollback is per phase:** `productAudienceEnabled = false` removes P2; P0/P1/P3 are additive and inert without data (P3 changes a label — see its rollback note). P1's rollback is to remove the chip group from the form — the column simply stays null, and nothing else reads it.

---

## 1. The gap, measured

The app can tell a customer *"this product stocks EU 42"* (that is `InYourSizeSection`). It **cannot** tell them *"this is a men's shoe"*, because the catalog has no such field.

| Fact | Evidence |
|---|---|
| `public.products` has no audience/gender column | `supabase/migrations/20260601000000_base_schema.sql:182` — `store_id, seller_id, name, description, price, category, tags, collection, sku, is_active, is_featured, is_published` |
| No later migration adds one | the only `ALTER TABLE public.products` statements add reviews' rating columns, `barcode`, and the sale fields |
| `category` is **style**, not audience | `AppConstants.productCategories` (`app_constants.dart:320`) — Casual, Formal, Sports, Sandals, Boots, Sneakers, Slip-ons, Custom |
| The tag vocabulary has no audience preset | `tagGroups` (Product type / Material / Sustainability) and `storeTagGroups` in `lib/widgets/seller/tag_selector.dart` |
| `gender` exists only on **people**, never on products | `profiles.gender` (customer + seller accounts, signup and edit-profile); no product surface reads it |
| The one audience-ish signal describes the *shopper* | `profiles.foot_size_category` + `foot_measurements.shoe_category` (`'men' \| 'women' \| 'kids'`), vocabulary in `customerFootSizeCategories` (`lib/utils/customer_profile_fields.dart:53`) |

### 1.1 Why the size band cannot stand in for audience

`customerEuSizes` (35→48) and `customerKidsEuSizes` (22→35) are the app's own bands
(`lib/utils/customer_profile_fields.dart`). Two consequences:

- **Men's and Women's share the exact same EU band.** EU is unisex — that is not an
  oversight, it is what `size_key.dart`'s own doc comment says. The scale only changes
  the **chart a US/UK label is drawn on**: `kEuToUsChartOffset` makes EU 42 read
  `US 9` on the men's chart and `US 10.5` on the women's.
- **Kids' is separable in principle** (EU 22→35) but not in practice: a small adult
  style sits at EU 39 and a kids' band overlap exists through 35. Deriving audience
  from sizes would be a guess, and a wrong guess puts a child's rail on an adult shoe.

So audience is **metadata that only a seller can supply**, and the whole point of the
column is that it is *stated*, never inferred.

---

## 2. What already exists to build on

| Precedent | Where | Why it is the template |
|---|---|---|
| A parameterised, absent-safe home rail | `lib/widgets/in_your_size_section.dart` | The three audience rails are the same widget with a different filter: header + size-less `HorizontalProductCard` strip, hides itself when empty, owns its trailing spacing, reads the kill switch first |
| The one-const kill switch | `AppConstants.sizeAwareShoppingEnabled`; `kBestSellersRailEnabled` in `customer_home_screen.dart` | Flip a surface off without a revert |
| The derived-filter precedent | `'On Sale'` / `'Best Sellers'` pseudo-categories in `product_provider.dart` (`categories`, `getFilteredProducts`) | Its rule — *a chip that hides itself when it would be a dead end* — is what the audience chips reuse via `audiencesInCatalog`; the chips are not pseudo-categories, because they navigate to a shelf instead of filtering this feed |
| A catalog lookup the provider already owns | `ProductProvider.productsInSize()` | `productsForAudience()` should be its sibling: filter + rank (units sold → rating → name) + cap, so a per-load shuffle cannot reorder a rail |
| The audience VOCABULARY, already shared | `customerFootSizeCategories` / `footSizeCategoryLabel` / `savedFootSizeCategory` (`customer_profile_fields.dart`) | `('men', "Men's")`, `('women', "Women's")`, `('kids', "Kids'")` — reuse it rather than inventing a second spelling of the same three words |
| A chip group in the product form | `add_edit_product_screen.dart` — `_category` state (`:39`), prefill (`:97`), the `_PresetChipSelector` `FormField` (`:1952`) | The audience input is this shape. Note `_PresetChipSelector` has a free-text "Other" affordance, which audience must NOT get — a closed set is the whole value |
| The product write path | `ProductService.createProduct()` (`:22`) / `updateProduct()` (`:129`), called from `add_edit_product_screen.dart:1373` and `:1403` | One extra named parameter each, plus a key in the insert map |
| The catalog query | `supabase_service.dart:203` — `select('*, stores(name), … inventory(size, stock), product_variants(…)')` | `*` already carries a new column to the client with **no query change** |

---

## 3. Decisions to lock before P0

| # | Question | Recommendation | Gates |
|---|---|---|---|
| **1** | Vocabulary | `'men' \| 'women' \| 'kids' \| 'unisex'`, **plus NULL = "not set"**. `unisex` is a real answer (a plain sandal is neither) and must never be shown in an audience rail — otherwise it appears three times | **P0** |
| **2** | Required on the seller form? | **Optional, but visible.** A required field blocks every edit of an existing product, and forces a lie on genuinely unisex items | P1 |
| **3** | Legacy / unset products | **Excluded from the audience rails; untouched everywhere else.** Stated > inferred. Measure the count before shipping (P4) so nobody is surprised by thin rails | P2 |
| **4** | Multi-value (a style sold to both)? | **Single value + `unisex`.** Multi-value doubles every filter and re-opens the chart question per value. A future `TEXT[]` migration is possible without changing the UI contract | P0 |
| **5** | Does a Kids' product's band matter? | **Warn, don't block/derive.** If audience is `kids` and every stocked size is outside EU 22–35 (say 40–44), surface a soft warning at entry. The rail itself must NOT re-derive audience from sizes — a mistyped field should be visible, not silently reinterpreted | P1 / P2 |
| **6** | Rails or a chip? | **Rails** (Men's / Women's / Kids', each hiding itself), audience orthogonal to the existing style chip row. **Superseded in part (2026-09-18):** the rails shipped as decided, and an audience chip row was then added on the user's request — but it does **not** narrow the feed (the pseudo-category shape this line anticipated). Each chip opens that audience's own listing page, so a shelf can hold more than a 12-card rail, `unisex` has somewhere to live, and the feed's own filters stay about product categories | P2 + chip row |
| **7** | Which chart labels a product's US/UK sizes? | **The product's own audience wins** when set; otherwise today's rule (the shopper's `foot_size_category`, men's as the final fallback). `unisex` → men's chart, stated as the app's existing default | P3 |
| 8 | Rail order | Fixed: Men's, Women's, Kids'. Optional nicety — put the customer's own scale first — is an open question (§8) | P2 |

---

## 4. The phases

### P0 — The column and the vocabulary · *0.5 day · no behaviour change*

- [ ] **1. Confirm what "audience" means before writing the migration.** Read `docs/AI/PRODUCT_ARCHITECTURE.md` and the seller form once more; if the three rails are the only consumer, one column is enough — do not add `audience_tags`, `gender`, and `sex` "to be safe".
- [ ] **2. Migration** `supabase/migrations/<date>_add_product_audience.sql`:
  ```sql
  ALTER TABLE public.products
    ADD COLUMN IF NOT EXISTS audience TEXT
        CHECK (audience IN ('men', 'women', 'kids', 'unisex'));
  ```
  Nullable on purpose (§3 decision 3). No backfill here — see P4. **Apply it to the project before any build that writes the column reaches a device.**
- [ ] **3. Vocabulary in one place.** Extend `customer_profile_fields.dart` (or a small `lib/utils/product_audience.dart`) with the product-side list — `('men', "Men's")`, `('women', "Women's")`, `('kids', "Kids'")`, `('unisex', 'Unisex')` — a `productAudienceLabel(value)` and a `productAudienceFrom(value)` that returns null for anything unrecognised. Reuse the existing three-value vocabulary; do not fork the spelling.
- [ ] **4. Kill switch** `AppConstants.productAudienceEnabled` (default `false` until P5), doc-commented like `sizeAwareShoppingEnabled`. — *as shipped: `true`, flipped at P5; the default-`false` rollout is what the "while off" notes below describe.*
- [ ] **5. Tests first, pure:** label/parse round-trip for all four values, `null` and garbage → null (never a guessed audience), and that the three RAIL audiences exclude `unisex`.
- [ ] **6. Run the gate.**

**Done when:** the column exists, the vocabulary is one file, and nothing renders differently.

**Rollback:** drop the column (no data depends on it yet).

**Shipped (2026-09-18).** Three deviations from the sketch above, all deliberate:

- **The migration is `20260918193313_add_product_audience.sql`**, verified against the live project
  (`audience` = `text`, nullable, `products_audience_check`). The `CHECK` is written **twice** — once
  inline, once as an explicit `DROP CONSTRAINT IF EXISTS` + `ADD CONSTRAINT` — because
  `ADD COLUMN IF NOT EXISTS` is a no-op on a re-run, so an inline-only constraint could go permanently
  missing while every later run reported success (the rule `supabase/MIGRATIONS_LIVE_STATUS.md` states
  twice).
- **The vocabulary lives in its own `lib/utils/product_audience.dart`**, not in
  `customer_profile_fields.dart`: that file owns the *shopper's* sign-up and foot-profile fields, and
  product audience is a different question — extending it would make one file the owner of two
  vocabularies. It **imports** the shared three (`productAudienceOptions` spreads
  `customerFootSizeCategories` and adds only `('unisex', 'Unisex')`), so `'women'` and `"Women's"`
  cannot come to mean two different things; a test pins that the first three entries *are* the shopper
  list in order, and that `productRailAudiences` still equals the shopper-side scale keys.
- **`productAudienceFrom` exact-matches** — no trimming, no case folding — because the column's own
  `CHECK` compares exactly. `'Men'` and `'unisex '` are `null`, not silently repaired.

---

### P1 — Seller input · *0.5–1 day*

- [ ] **1. `add_edit_product_screen.dart`:** `String? _audience` beside `_category` (`:39`), prefill from `p['audience']` (`:97`), a chip group in the form (NOT `_PresetChipSelector`'s free-text variant — the set is closed), and pass it through both `updateProduct` (`:1373`) and `createProduct` (`:1403`).
- [ ] **2. `ProductService.createProduct` / `updateProduct`:** one nullable named parameter each, written as `'audience': ?audience` so "not set" clears rather than writes an empty string.
- [ ] **3. Kids' band warning** (§3 decision 5) — computed from the same size parser the rest of the app uses (`size_key.dart`), never a second regex.
- [ ] **4. Manage-products surface:** show the audience on the seller's product row so a seller can see what they set without opening the editor (`manage_products_screen.dart`).
- [ ] **5. Widget tests:** chip group round-trips all four values **and clearing back to "Not set"**; prefill on edit; the kids' warning fires on 40–44 and does not on 28.
- [ ] **6. Run the gate.**

**Done when:** a seller can set, change and clear the audience, and nothing customer-facing has moved.

**Rollback:** hide the chip group; the column simply stays null.

**Shipped (2026-09-18).** What landed, and where it differs from the sketch:

- **A dedicated closed chip group, not `_PresetChipSelector`.** That widget's contract is the opposite
  of what this field needs three ways over: it reports a non-nullable `String` (so "cleared" can only
  be `''`, which the column's `CHECK` rejects), it always offers a free-text "+ Other" chip (the one
  thing a controlled vocabulary must not allow), and it cannot express "no selection" as a deliberate
  act. `_AudienceChipSelector` reuses the shared `_TagChip` for the chips themselves, so the group
  looks and animates like the category and tag rows without re-implementing them.
- **"Not set" is a real chip**, last in the row, so clearing is intentional and visible — not an
  unselected state a seller has to discover.
- **The service normalises rather than passing `?audience` through.** Both calls write
  `'audience': productAudienceFrom(audience)`, so anything outside the vocabulary becomes SQL `NULL`
  instead of tripping the `CHECK` as a 400 — whose message the UI flattens into a generic "Something
  went wrong". On update the key is **always sent**, following the existing `barcode`/`sale_*`
  precedent, which is what lets "Not set" clear an existing value.
- **The kids' warning is one pure function**, `audienceSizeMismatch()` in `product_audience.dart`
  (not screen-local logic), reading sizes through `size_key.dart`'s `sizeNumberInEu` and the band from
  `customerKidsEuSizes` — so the rule, the band and the parser are all shared with the rest of the app.
  It returns false unless *every* size is readable and outside EU 22–35: with no sizes yet, or one
  custom size in the list, there is nothing solid enough to contradict, so nothing is claimed.
- **`manage_products_screen.dart` shows the audience on the muted metadata line** (`Casual · Women's`),
  joined with the category the row already printed, via the shared label helper. An unset product
  contributes nothing, so rows for products that predate the column look unchanged.
- **Tests:** 6 pure cases for the band rule in `test/utils/product_audience_test.dart` and 11 widget
  tests in `test/widgets/add_edit_product_audience_test.dart` (the closed-set chips, prefill for all
  four values plus the unrecognised-value fallback, round-trip through the service, "Not set" reaching
  the service as `null`, and the warning firing at EU 40–44 / staying quiet at EU 28).
  `AddEditProductScreen` gained a `productService` seam so a test can assert the exact payload.
- **Known gap:** the *create* path is not covered by a widget test — saving a new product requires at
  least one image, which a widget test cannot produce without mocking the image picker. Both call sites
  pass the same `_audience`, and the update path (same service code) is covered.

---

### P2 — The three home rails · *0.5 day · first visible phase*

- [x] **1. `ProductProvider.productsForAudience(String audience, {int limit})`** — sibling of `productsInSize()`: keep products whose `audience` equals the requested value (skip null and `unisex`), rank units sold → rating → name, cap at a new `kAudienceRailLimit`.
- [x] **2. `lib/widgets/audience_section.dart`** — parameterise `InYourSizeSection`'s body rather than copying it: title (`Men's`), the same 130x180 `HorizontalProductCard` strip, self-hiding, self-spacing, reading the kill switch. If the two rails end up sharing more than the header, extract the strip into one widget and have both call it.
- [x] **3. Home wiring:** the three rails in fixed order, gated exactly like the others (`_searchKeyword.isEmpty` and no category filter) — see §4 of `CUSTOMER_HOME_ARCHITECTURE.md`.
- [x] **4. Widget tests:** each rail renders only its own audience; a `unisex` product appears in none of them; an unset product appears in none but is still in the catalog grid; a rail with no matches renders nothing (no header, no gap); narrow screen + 1.3 text scale does not overflow.
- [x] **5. Dual-brightness check** on the rail header (the dark-mode guard convention).
- [x] **6. Run the gate.**

**Done when:** a customer sees Men's / Women's / Kids' rails that contain only products a seller explicitly put there — and a catalog with no audiences yet looks exactly as it does today.

**Rollback:** `productAudienceEnabled = false`.

**Landed, dark (2026-09-18) — the code exists, the surface does not.** `AppConstants.productAudienceEnabled`
was still `false` at the time of writing (it was flipped at P5), and turning it on changed nothing on screen for
exactly the reason recorded here: there is nothing for the rails to show, because **all 15 products in the live
catalog have `audience = null`** (measured, not assumed — P4 later re-measured it as 15 of 15). What landed and
where it differs from the sketch:

- **The strip was extracted, not copied.** Four rails (In your size + Men's/Women's/Kids') would have been four
  copies of one header row + `ListView.separated` + trailing gap, which is how one rail quietly gains a 14px gap
  or a different card size. `lib/widgets/product_rail_section.dart` is now the shared body; `InYourSizeSection`
  was refactored onto it, and it takes an optional muted `meta` line — that parameter is the only difference
  between "In your size, EU 42" and "Men's". Callers own just the two things that genuinely differ: which
  products, and what to say beside the title. It does **not** hide itself — hiding belongs to the section widget,
  which is the only thing that knows whether "nothing" means "not applicable" or "empty catalog".
- **`AudienceSection` takes the audience, not a title.** The plan said the caller passes `"Men's"`; it takes
  `audience: 'men'` and derives the label through `productAudienceLabel`, so `"Men's"` / `"Women's"` / `"Kids'"`
  stay spelled in exactly one file and a rail cannot be labelled with an audience it does not query. The home
  screen iterates `productRailAudiences` rather than listing three widgets by hand, so the fixed order and the
  `unisex` exclusion are decided by that one constant instead of by call-site discipline.
- **The kill switch is read first, before the provider is touched** — with it off the widget asks for no list at
  all. Because the constant is `const false` for the whole phase, the widget takes a documented `enabled`
  parameter that **defaults to** `AppConstants.productAudienceEnabled` (no production call site passes it), so
  the rail's own behaviour is testable while the feature ships dark.
- **`productsForAudience` normalises its argument** through `productAudienceFrom` and returns EMPTY for anything
  that is not a rail-eligible audience — including a direct call with `'unisex'` — rather than defaulting to a
  rail. Ranking moved into one shared `_compareSuggestions` (units sold → rating → name) that `productsInSize`
  now also uses, so the two rails cannot drift into disagreeing about order.
- **Tests:** 9 provider cases in `test/providers/product_provider_test.dart` (per-audience filtering, `unisex` out
  of every rail, unset out of the rails **and still in `getFilteredProducts`**, malformed input → empty, ranking,
  tie stability, cap and `limit: 0`) and 9 widget cases in `test/widgets/audience_section_test.dart` (isolation,
  label/order, `unisex`, unset-still-in-grid, hidden-rail-has-no-gap, switch off, non-rail audience, narrow +
  1.3× text scale, and the dark/light header-ink check through `AppBrightness.set`). `flutter test` passes (1213)
  and `flutter analyze lib test` is clean.
- **Still open in this phase's spirit:** nothing has been backfilled, so these rails render nothing until a
  seller sets an audience — P4 has now *measured* that (15 of 15 unset) and given sellers the prompt, but the
  answer is still a human's to give. *(The switch, then still off, is now `true` — see P5.)*

---

### P3 — Labels from the product's own chart · *0.5 day*

Today `product_detail_screen.dart:1328` labels US/UK from the **shopper's** saved scale
(`savedFootSizeCategory`). A woman shopping a men's-sized product therefore sees the
women's chart. With an audience on the product, the label can be right for the *item*.

- [x] **1. Precedence:** product `audience` (when `men`/`women` — `kids` offers EU only, per `sizeUnitsForCategory`) → shopper's scale → men's. Write the order down in one place; do not scatter `??`.
- [~] **2. Apply at:** the product page's unit switcher ~~, the cart/checkout size labels (via `formatSize`)~~ — **labels only**. The stored size string, the cart row, the RPC matching and `SIZE_VARIANT_FLOW.md`'s contract do not change. **The cart/checkout half was not applied — see the note below.**
- [x] **3. Tests:** a men's product reads `US 9` for EU 42 for every shopper, including one whose saved scale is women's; a kids' product keeps EU; an unset product falls back to today's behaviour (assert that explicitly — it is the regression risk).
- [x] **4. Run the gate.**

**Done when:** the label on a product matches the chart that product is sold on, and every unset product behaves exactly as before.

**Rollback:** `productAudienceEnabled = false` — the helper takes the switch as an argument, so with it off the product page is handed `savedFootSizeCategory(profile)` verbatim. (The plan expected a code revert; the switch is a strictly safer one-const version of it.)

**Landed, dark (2026-09-18).** `lib/utils/product_audience.dart` now owns `productSizeChart({product, profile,
required audienceEnabled})` — the whole precedence, in one place, as four rules:

| Audience on the product | Chart used |
|---|---|
| `men` / `women` | that product's own chart, for every shopper |
| `kids` | the kids' scale — which `sizeUnitsForCategory` already renders as **EU only** (no child US/UK chart exists) |
| `null` / unrecognised | the shopper's saved scale, **verbatim, null included** |
| `unisex` | the men's chart — the app's existing no-knowledge default |

The product page (`product_detail_screen.dart:1332`) resolves its chart once through that helper and passes it
to both `sizeUnitsForCategory` and the two `displaySizeInUnit(category:)` call sites (the grid label and the
tap-to-canonical lookup). Its now-unused `customer_profile_fields.dart` import was dropped, which is the visible
sign the screen no longer decides the chart itself.

- **The switch is composed as an argument, not a constant read.** `audienceEnabled` is passed from
  `AppConstants.productAudienceEnabled`, so (a) the util stays pure Dart — it imports no Flutter and no app
  constants — and (b) the gate is unit-testable: with `false`, the helper returns
  `savedFootSizeCategory(profile)` for *every* input, audience set or not. The constant's own doc already
  claimed it gates "audience-aware size-chart labels", so P3 composes with that switch rather than inventing a
  second one.
- **Tests:** 7 cases added to `test/utils/product_audience_test.dart`, going through the real pipeline
  (`productSizeChart` → `sizeUnitsForCategory` → `displaySizeInUnit`) rather than restating arithmetic: a men's
  product reads `US 9` for EU 42 for five different shoppers (including a women's one), a women's product reads
  `US 10.5` regardless of the shopper, a kids' product offers EU only, an unset product is asserted **equal to
  `savedFootSizeCategory(profile)` itself** for six profiles (so it cannot drift from today's behaviour), unisex
  resolves to men's, a mis-cased/padded/unknown audience is treated as unset, and the switch off never consults
  the audience. `flutter test` passes (1220), `flutter analyze lib test` clean.

**Not done, and reported rather than worked around — the cart/checkout half of step 2.** The plan says to thread
the effective chart into the cart/checkout labels "via `formatSize`". Those call sites are
`'${formatSize(item['size']?.toString() ?? '')} · ${item['color']}'` (`cart_screen.dart:332`,
`checkout_screen.dart:1478`, `pending_gcash_checkout_sheet.dart:448`): **no `unit:` argument**, so `formatSize`
returns the stored string unchanged and never reads `category` — the chart is not part of those labels at all.
Threading it would be a no-op, and making the cart render a *converted* unit would change what every customer
sees in the cart for every product (including the audience-less ones), which is a product decision this phase
was not given. The cart items also carry no `audience` (`cart_provider.dart` keys on `product_id` + `size`), so
it would need a catalog lookup per row. Left as-is on purpose; the plan line is marked `[~]`.

---

### P4 — Backfill and admin visibility · *0.5–1 day*

- [x] **1. Measure first:** how many products are unset, and which stores own them. Without this number, "the rails look thin" has no diagnosis.
- [x] **2. Backfill options, in order of honesty:**
  1. **Sellers set it** — the only source that is actually true. Surface the count in the seller's manage-products screen ("12 products have no audience").
  2. **Admin-assisted** — `lib/screens/admin/monitor_products_screen.dart` shows the column and (optionally) allows a bulk edit, mirroring how the admin catalogue is already inspected.
  3. **A guess** (from the size band) — **do not**. See §1.1; it would put adult shoes in a kids' rail.
- [x] **3. Admin screen:** display the audience; the admin catalogue is where "why is this not in any rail" gets answered.
- [x] **4. Run the gate.**

**Done when:** nobody has to guess why a product is missing from a rail.

**Measured, 2026-09-19 — the number R1 was waiting for.** Against the live project:

| | Products | Unset | Set |
|---|---|---|---|
| **Total** | 15 | **15** | 0 |
| Valladolid Leather Co. | 9 | 9 | 0 |
| demo_storeName | 5 | 5 | 0 |
| Janella | 1 | 1 | 0 |

Risk R1 ("every existing product is unset, so three rails ship empty") is therefore **confirmed, not mitigated** — the rails and the audience chips have nothing to show today, exactly as they did the day they were built. The whole catalog is also tiny, so the number is a statement about a demo catalog rather than about a production backfill: the point of this table is that it can be re-run in one command (`supabase db query --linked "select count(*) filter (where audience is null) from public.products;"`) whenever it matters.

**Landed, 2026-09-19 — how the two surfaces were built.**

- **Seller: the existing alert banner, not a new treatment.** `manage_products_screen.dart` already has the shape this phase needs — `_buildAlerts()` produces "N products low on stock" style entries that rotate every 4 seconds, each carrying a `filter` it deep-links to. The audience nudge is one more entry there ("3 products missing 'Who is it for?'"), plus a `Not Set` filter chip so the list stays reachable after the banner rotates away. Informational by construction: a rotating banner and a chip, no modal, nothing blocking.
- **Said in the seller's words, not ours.** The form calls the field **"Who is it for?"**; "audience" is our word for the column. The nudge quotes the form, so a seller is not being asked about a concept they have never seen.
- **One rule, three sites.** `missingAudience(product)` (a top-level function in that screen, next to the `_AlertData` it feeds) decides what counts as missing; the banner count, the grid filter and the chip count all call it. The banner therefore cannot claim a number the filter does not then show — and the test asserts that wiring rather than trusting review.
- **`unisex` is NOT missing.** It is a stated answer that the rails deliberately skip, so it must not appear in the nudge: prompting a seller to "fix" a product they already answered is how a nudge becomes noise.
- **Admin: disclosure only — bulk edit was skipped, deliberately.** `monitor_products_screen.dart` now prints `Audience: Men's` per product from the shared label helper (amber "Not set" when unset, so the unanswered ones are findable at a glance). The phase allows bulk-editing "mirroring however bulk edits already work elsewhere in the admin catalogue" — **there are none**: that console has no selection, no action and no filter pattern of any kind to extend (`grep -rn "bulk\|Checkbox\|selectedIds" lib/screens/admin` is empty), so building one would mean inventing a new admin interaction model to satisfy a checkbox that this plan explicitly marks optional. Per-product visibility is what an admin needs to answer "what is left to fill in?".
- **No inference, in any form.** The phase's hard "do not" is not implemented anywhere, and the test guards the property that keeps it that way: every read of the `audience` column in the seller screen goes through the shared parser, so nothing can treat a raw or unrecognised value as an answer, and no size-band heuristic can quietly appear.
- **Tests:** 14 — `test/widgets/seller_audience_nudge_test.dart` (the rule across every vocabulary value, `unisex`, null/absent/empty/unrecognised, a 15-product all-unset catalog, and the wiring that the count and the filter are one rule) and `test/widgets/monitor_products_audience_test.dart` (each value prints as the shared vocabulary calls it, unset reads "Not set" and stands out, a non-canonical value reads as unset, an all-unset catalog, an empty catalog). The seller screen cannot be built in a widget test — `Supabase.instance` is uninitialized there — which is why its wiring is asserted against the source, the same technique `offscreen_timer_pause_contract_test.dart` already uses for that file. `flutter test` passes (1310), `flutter analyze lib test` clean.

---

### P5 — QA, docs, switch-on · *0.5 day*

- [x] **1. Combined regression pass** *(2026-09-19)* — one seeded catalog carrying all four audience values plus several unset products, asserted **across every surface at once** rather than phase by phase (`test/widgets/audience_end_to_end_test.dart`). What that pass established:

  | Product | Rails (P2) | Size label (P3) | Everywhere else |
  |---|---|---|---|
  | Men's | Men's rail only | Men's chart, overriding a shopper saved as `women` | catalog, search, category |
  | Women's | Women's rail only | Women's chart, overriding a shopper saved as `men` | catalog, search, category |
  | Kids' | Kids' rail only | **EU only** — no US/UK offered | catalog, search, category |
  | `unisex` | **no** rail | men's chart (the app's answer when nothing else is known) | catalog, search, **the Unisex shelf** |
  | `NULL` (several) | **no** rail | **the shopper's own scale, verbatim** | catalog, search, every category, no shelf |

  The unset row is the P3 regression check re-run **in combination** rather than in isolation, and it is the one that matters most: an untagged product produces byte-for-byte the label it produced before any of this work. Asserted alongside it: the seller's unset count matches exactly the products left unset, and the admin monitor prints each product's audience through the shared vocabulary (`Not set` for the nulls).

  One harness bug surfaced here and was fixed: `ListView.builder` builds lazily, so an off-screen card was not being counted — which made the "appears in no rail" assertions pass for the wrong reason. The test viewport is now tall enough to hold the whole list.

- [x] **2. QA sweep — the part a widget test can settle** *(2026-09-19)* — `test/widgets/audience_qa_sweep_test.dart`, 38 cases across the rail headers and the size-label surfaces: a 320px phone and a wide/tablet width, light and dark, and 1.3× and the platform-maximum 2.0× text scale, with **computed WCAG contrast** on the ink rather than restated tokens. No overflow, no clipped text, no broken layout in any combination. **Landscape is not supported** — the app locks portrait (`SystemChrome.setPreferredOrientations` in `main.dart`), confirmed against the code rather than assumed, so there is no landscape layout to sweep. The earlier version of this sweep found three real defects in the new code and two app-wide ones in `SoleProductCard` (see the CHANGELOG).

- [x] **3. Rollback proven** *(2026-09-19)* — `productAudienceEnabled` was set back to `false` and the **entire** suite re-run: **1355 pass**. That is the check this phase exists for, and it is stronger than a code reading: flipping the flag still fully reverts customer-visible behaviour with no leftover artifacts, so it remains the feature's rollback rather than a flag that has quietly stopped covering something. The flag is `true` again and its code paths stay.

- [ ] **4. Manual QA on a real device — STILL OPEN.** The table below is what remains, and it is open **by capability, not by oversight**: it needs real fonts, real banner images and a real phone, none of which exist in this environment.

  | Scenario | Expected |
  |---|---|
  | Product set to Men's | Appears in the Men's rail only |
  | Product set to Unisex | In no audience rail; still in the catalog and search |
  | Product with no audience | In no audience rail; everything else unchanged |
  | Kids' product | Kids' rail; product page offers no US/UK label |
  | Catalog with no audiences at all | Home identical to today — no empty headers |
  | Search / category filter active | No audience rails (the browse gate) |
  | Dark mode, largest text scale, narrow phone | Header and rail legible, no overflow |
  | Audience changed by the seller | Rail follows on the next catalog load |

  Every row whose behaviour a widget test can pin is pinned above (rows 1–4 and 6–7). What the device pass adds is the two things a harness cannot supply — real font metrics, and the hero's real banner photography, where contrast is a judgement call rather than a measured ratio. Three rows additionally need **tagged products on the live catalog**, which P4's measurement blocks: all 15 live products are unset, so on today's catalog those rows are vacuously "nothing shown".

- [x] **5. Docs** *(2026-09-19)* — `PRODUCT_ARCHITECTURE.md` (the column, its vocabulary, its readers, as shipped), `CUSTOMER_HOME_ARCHITECTURE.md` (the rails' gating and self-hiding, corrected from the stale "gated off"), `SIZE_VARIANT_FLOW.md` (**§3.5** — the audience label precedence, stating explicitly that the §3.3 size contract is untouched) and this plan's status. The point of the last two is direction: a doc that still calls a shipped feature "planned" is worse than no doc, because it misleads the next reader before they touch the code.
- [x] **6. CHANGELOG** in the house voice — naming the migration explicitly, the way the foot-size entry does.
- [x] **7. Flip `productAudienceEnabled = true`** *(2026-09-18)*, final gate, delete any dead code. Flipped **before** the rest of P5, on the user's decision, because the surfaces are data-derived and therefore inert on an untagged catalog (see the status note at the top).
- [x] **8. Final gate, post-flip** *(2026-09-19)* — `flutter analyze lib test` → **No issues found!**; `flutter test` → **1355 passing**. The count is **identical with the flag on and off**, which is the most direct evidence available for the claim the whole rollout order rests on: on an untagged catalog, turning this on changes nothing a customer can see.

**Landed, on request (2026-09-18) — the chip row and the listing pages.** Beyond the plan's sketch, and deliberately not the shape decision #6 anticipated:

- `HomeCategoryRow` (`lib/screens/customer/widgets/home_category_row.dart`) — extracted out of `HomeHero` so the row is a widget that reads no providers (the hero cannot be built in a test: `BannerProvider` constructs a live Supabase client). Order is `All` → audiences → categories → pseudo-categories, so the shelf chips are on screen without a horizontal scroll.
- `ProductProvider.audiencesInCatalog` — the audiences the catalog actually holds, in vocabulary order. Empty for today's catalog, which is what made the flip invisible.
- `AudienceListingScreen` (`lib/screens/customer/audience_listing_screen.dart`) — the whole shelf, its own sort, its own count, a Back button, and an empty state. A page rather than an in-place filter because a customer tapping "Women's" is asking for a shelf, not a keyword — and it is the only surface where `unisex` can be seen as a group (the rails must skip it, §4 R4).
- `ProductProvider.productsInAudience()` — deliberately **not** `productsForAudience()`: the listing includes `unisex` and is uncapped; the rail excludes `unisex` and caps at 12. Both exclude unset products.

---

## 5. Risks

| # | Risk | Mitigation |
|---|---|---|
| R1 | **Every existing product is "not set", so three rails ship empty** and the feature reads as broken | Measure before shipping (P4 step 1); rails are absent-safe so nothing looks broken, only absent; seller-side prompt; consider not shipping P2 until a floor of products are set |
| R2 | **A mistyped audience mislabels a size** — a men's chart on a women's shoe is a whole size of wrong advice | Only claim when the audience is set; EU stays the primary label; the seller can see and fix it in the product row |
| R3 | **Kids' audience with adult sizes** → a child's rail listing EU 42 | Soft warning at entry (P1 step 3); the rail does NOT re-derive from sizes, so the mistake stays visible and fixable rather than silently hidden |
| R4 | **`unisex` in three rails** triples the same products down the feed | `unisex` is excluded from every audience rail by rule, and that rule is unit-tested (P0 step 5) |
| R5 | **Migration ordering** — a build that writes a column the project does not have fails the write, and the customer/seller sees a generic "Something went wrong" | Apply the migration first; call it out in the CHANGELOG and the release checklist; this is the exact failure `20260917130000_add_foot_size_category.sql` produced |
| R6 | **Seller friction** — a forced field on an existing product blocks the edit | Optional (decision 2); clearing back to "Not set" must be possible (P1 step 5) |
| R7 | **A fourth place that spells "Women's"** and drifts from the foot-profile vocabulary | One vocabulary helper; the guard test in §6 |

---

## 6. Test plan

**Pure (`test/utils/`)** *(P0)*
- All four values round-trip; `null`, `''`, `'Men'`, `'unisex '` and garbage parse without inventing an audience.
- The rail set excludes `unisex` (the rule, not just the UI).

**Provider (`test/providers/product_provider_test.dart`)** *(P2)*
- `productsForAudience('men')` returns exactly the men's products, ranked units sold → rating → name.
- `null` and `unisex` products are in no audience set but still in `products`.
- The cap is honoured and `limit: 0` means no cap.

**Widget** *(P1–P2)*
- `AudienceSection`: renders its own audience only; empty → renders nothing at all.
- Home: the three rails in order, each self-hiding, and none under a search or category filter.
- `add_edit_product_screen`: chip group round-trips, including clearing; kids' warning.
- `ProductDetailScreen`: audience drives the US/UK chart; unset falls back to today's behaviour.

**Guard** *(P5)*
- A test asserting no customer-facing file contains a hardcoded `"Men's"` / `"Women's"` / `"Kids'"` string outside the one vocabulary helper — the drift this plan invites.

---

## 7. Out of scope

1. **Inferring audience from sizes.** Explicitly rejected (§1.1) — it is the one shortcut that produces confidently wrong results.
2. **Customer `gender`-based recommendation.** Identity is not the shopping scale; the app already documents this distinction (`customer_profile_fields.dart:44-50`).
3. **Per-product fit feedback and width data** — see `SIZE_AWARE_SHOPPING_PLAN.md` §7.
4. **Re-labelling stored catalog sizes.** Stored strings and the RPC matching stay as they are (`SIZE_VARIANT_FLOW.md`).
5. **Audience in search relevance / the style chip row.** A chip row was later built on request (see P5's landed note) as **shelf navigation**, not as a feed filter and not as anything search ranks by — audience still plays no part in relevance.

---

## 8. Open questions

1. **Rail order personalised?** Put the customer's own `foot_size_category` first (a women's shopper sees Women's before Men's). Costs one read of the profile and is easy to get wrong-looking — worth deciding before P2.
2. **How many products must be set before the rails ship?** A rail with two products looks worse than no rail. A minimum count (or "at least one product per rail") is a product call.
3. **Is `unisex` worth it at all**, or is NULL enough? `unisex` lets a seller say "this really is for anyone", which NULL cannot distinguish from "nobody has got to this yet".
4. **Should the audience show on the product page** as a chip beside the style, so a shopper can see it?
5. **Admin bulk edit** — in scope for P4, or a separate slice?

---

## 9. Key files

| File | Phase | Change |
|---|---|---|
| `supabase/migrations/<date>_add_product_audience.sql` | P0 | **new** — the column + CHECK |
| `lib/utils/product_audience.dart` (or `customer_profile_fields.dart`) | P0 | **new/extended** — vocabulary, label, parse |
| `lib/constants/app_constants.dart` | P0 | `productAudienceEnabled` kill switch (gates P2's rails and P3's chart labels) |
| `lib/utils/product_audience.dart` | P3 | `productSizeChart()` — the one place the chart precedence lives |
| `lib/screens/seller/add_edit_product_screen.dart` | P1 | `_audience` state, prefill, chip group, kids' warning, pass through on save |
| `lib/services/product_service.dart` | P1 | `audience` on `createProduct` / `updateProduct` |
| `lib/screens/seller/manage_products_screen.dart` | P1, P4 | show the audience on the card (P1); `missingAudience` + the "missing 'Who is it for?'" alert + the `Not Set` filter (P4) |
| `lib/providers/product_provider.dart` | P2 | `productsForAudience()`, `kAudienceRailLimit`, `audiencesInCatalog`, `productsInAudience()` (the listing page's uncapped, unisex-inclusive sibling) |
| `lib/screens/customer/widgets/home_category_row.dart` | chip row | **new** — the hero's category chips + the audience chips, extracted so it is testable without a Supabase client |
| `lib/screens/customer/audience_listing_screen.dart` | chip row | **new** — one audience's whole shelf, reachable from its chip |
| `lib/screens/customer/widgets/home_hero.dart` | chip row | feeds the row its categories and `audiencesInCatalog`; opens the listing via the screen's callback |
| `lib/widgets/product_rail_section.dart` | P2 | the shared rail body (header + strip + trailing gap) all four curated rails render through |
| `lib/widgets/audience_section.dart` | P2 | **new** — the three rails |
| `lib/screens/customer/customer_home_screen.dart` | P2 | render them behind the switch + browse gate |
| `lib/screens/customer/product_detail_screen.dart` | P3 | chart precedence for US/UK labels |
| `lib/screens/admin/monitor_products_screen.dart` | P4 | display the audience per product (`Audience:` line, amber "Not set"); **bulk edit not built** — no admin bulk pattern exists to extend |
| `docs/AI/CUSTOMER_HOME_ARCHITECTURE.md`, `PRODUCT_ARCHITECTURE.md`, `CHANGELOG.md` | P5 | the record |
