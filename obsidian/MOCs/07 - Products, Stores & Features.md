# 🛍️ Products, Stores & Features

> Product listings, store profiles, follows, ratings/reviews, sharing, and cross-cutting features. **#moc**

---

## 📌 Overview

Products are the heart of the marketplace — `products.id` is **TEXT** (`gen_random_uuid()::text`), stock lives in **two tables that must never drift**: `product_variants` (per size+color) and `inventory` (per size, **authoritative**). Stores are CUFMAI artisan storefronts with branding, schedules, stories, and a **trigger-maintained rating**. Follows, reviews, and sharing are layered on top.

---

## 🛍️ Products — stock system (the most important rule)

> **`inventory` and `product_variants` must always agree on per-size totals.**

Two write paths keep them in sync, in opposite directions:

| Writer | Writes first | Then syncs | Direction |
|--------|-------------|-----------|-----------|
| Seller Add/Edit form (`ProductService`) | `product_variants` (delete + re-insert) | `_syncInventoryFromVariants()` — regenerates `inventory` FROM variants | variants → inventory |
| **Adjust Stock** (`SupabaseService`) | `inventory` (upsert) | `_syncVariantStock()` — distributes totals ONTO variant rows | inventory → variants |

**Why it matters**: if Adjust Stock wrote only `inventory`, the next product edit would regenerate inventory from stale variants and **silently wipe every adjustment**.

**Read paths**: customer browse/product detail/checkout read `inventory` (higher-wins merge with variants) · POS/seller screens read both · edit form reads `product_variants`. `purchasableProducts()` (`lib/utils/product_stock.dart`) hides products exactly when unpurchasable — restock makes them reappear on next fetch.

**Per-color photo galleries**: each `ProductColor` owns its own photo gallery and size/stock variants. Sellers add colors, then sizes under each color — see [[docs/AI/SIZE_VARIANT_FLOW|Size/variant flow]].

**products columns** (key): `id TEXT PK`, `store_id`, `seller_id` (**nullable!**), `price` (always original), `category`, `tags TEXT[]`, `collection`, `sku`, `is_active` (auto-synced to stock), `is_featured`, `is_published`, `sale_price` + `sale_starts_at`/`sale_ends_at` (on-sale). Storage bucket `product-images` (public read).

**RLS**: anyone SELECT; only `role IN ('seller','admin')` INSERT/UPDATE/DELETE with `store_id` ownership verification (`20260712_tighten_products_rls.sql`).

---

## 🏪 Stores — profiles, ratings, follows

- `stores` — branding (name, tagline, location, brand color, logo, banner), `is_open` toggle, GCash QR + number + name, `rating NUMERIC(2,1)` (nullable — NULL = no reviews yet, badge hidden), `review_count`.
- **Rating is trigger-maintained**: `refresh_store_rating()` (SECURITY DEFINER) fires on every insert/update/delete of `reviews` + `product_reviews` + `store_reviews`, recomputing from all three (weighted by count), resolving legacy `product_reviews` via `products.store_id`. Migrations: `20260807000000_add_store_rating_aggregation.sql` + `20260808000000_add_store_reviews.sql`.
- **`store_reviews`** — direct "Rate this store": `UNIQUE(store_id, customer_id)`, rating 1–5, comment; `getStoreLevelReviews(storeId)` + `submitStoreReview({storeId, rating, comment})` in `ReviewProvider`.
- **Follows** — `store_follows` (composite PK); async `isFollowingAsync()` is the real check (**`isFollowing()` sync is a stub returning false**).
- Screens: `lib/screens/store/store_screen.dart`, `store_profile_screen.dart` (stories, reviews, masonry→standard grid fix), `collection_screen.dart`, `rate_store_screen.dart` (submit/edit store review), `seller/store_reviews_screen.dart` (list + seller replies + in-page display avg), `seller/store_schedule_screen.dart`.
- ⚠️ **FKs**: `products.store_id` / `orders.store_id` have NO cascade — deleting a store requires reassigning children first (`20260709_one_store_per_seller.sql` dedupes duplicates).

---

## ⭐ Reviews & ratings roadmap

- `reviews` (order-linked) + legacy `product_reviews` + `store_reviews` feed `stores.rating`.
- Roadmaps: [[docs/AI/PRODUCT_REVIEWS_ROADMAP|v1]] · [[docs/AI/PRODUCT_REVIEWS_ROADMAP_v2|v2]].
- ⚠️ Do **not** recreate `product_reviews` if missing — `20260717_product_reviews.sql` would overwrite `refresh_product_rating()` and break ratings.

## 🔗 Sharing & other features

- **Share product previews**: `lib/screens/customer/product_detail_screen.dart` share button; `supabase/functions/product-preview/index.ts` generates OG-image HTML (escaping, "View in the CUFMAI app" CTA). See [[docs/AI/SHARE_PRODUCT_ARCHITECTURE|Share product architecture]].
- **Feature file lookup guide** maps 8 features to files: secure checkout badge, quantity limit, size guide modal, return/refund policy screen, social sharing, recently viewed, delivery estimate, search filters/sort.

## ⚠️ Gotchas

1. Never let `inventory`/`product_variants` drift — break the dual sync and adjustments get silently wiped.
2. `seller_id` nullable on products — legacy/unassigned rows exist.
3. Store deletion is awkward (NO ACTION FKs) — reassign children first.
4. `is_active` is auto-managed by stock — don't fight it manually.
5. `sale_price` ≠ `price` — `price` always holds the original.

## 📚 Deep-dive docs

- [[docs/AI/PRODUCT_ARCHITECTURE|Product architecture]] — stock system + Adjust Stock deep dive (supersedes `PRODUCT_ARCHITECTURE_CONTEXT.md` for stock)
- [[docs/AI/PRODUCT_ARCHITECTURE_CONTEXT|Product architecture context]]
- [[docs/AI/STORE_ARCHITECTURE_AND_RATINGS|Store architecture & ratings]] — the canonical stores/ratings reference
- [[docs/AI/SHARE_PRODUCT_ARCHITECTURE|Share product architecture]]
- [[docs/AI/FOLLOWING_FEATURE_ARCHITECTURE|Following feature architecture]]
- [[docs/needs/PROFILE_AND_STORE_FOLLOW_ARCHITECTURE|Profile & store follow architecture]]
- [[docs/store/PRODUCT_SALE_FEATURE_RESEARCH|Product sale feature research]]
- [[docs/product_delete_and_auto_deactivation|Product delete & auto-deactivation]]
- [[docs/AI/PRODUCT_REVIEWS_ROADMAP|Product reviews roadmap]] · [[docs/AI/PRODUCT_REVIEWS_ROADMAP_v2|v2]]
- [[docs/AI/feature_file_lookup_guide|🔍 Feature file lookup guide]]

## 🔗 Related

- [[obsidian/MOCs/03 - Seller Module|👞 Seller Module]] — product CRUD, inventory sync, POS
- [[obsidian/MOCs/02 - Customer App|📱 Customer App]] — product detail, store browsing
- [[obsidian/MOCs/05 - Database & Supabase|🗄️ Database & Supabase]] — tables, triggers
