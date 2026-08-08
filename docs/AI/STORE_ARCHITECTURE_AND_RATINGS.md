# Store Architecture & Ratings — Reference

**Date:** August 8, 2026
**Scope:** How a *store* works end-to-end in SoleVision — the `stores` table, store lifecycle (one store per seller), store RLS, the customer/seller store screens, store follows — followed by a **deep dive on ratings & reviews** (the two independent rating systems and how they interact).
**Related:** `docs/AI/FOLLOWING_FEATURE_ARCHITECTURE.md` (follow feature), `docs/AI/PRODUCT_REVIEWS_ROADMAP_v2.md` (original reviews plan — superseded by the live per-order-item design), `docs/AI/SELLER_ARCHITECTURE_GRAPH.md`, `docs/AI/CUSTOMER_HOME_ARCHITECTURE.md`.

---

## 0. TL;DR — the one thing to remember about ratings

There are **TWO completely separate rating systems** in this codebase, and they are **NOT connected**:

| Rating | Where it lives | Maintained automatically? | Shown in |
|---|---|---|---|
| **Product rating** | `products.avg_rating` + `products.review_count` | ✅ Yes — `refresh_product_rating()` trigger recomputes on every review insert/update/delete | Product cards, product detail page |
| **Store rating** | `stores.rating` (`NUMERIC(2,1)`, nullable) | ✅ **Yes — trigger-maintained since migration `20260807000000` (Aug 7) and extended to 3 sources by `20260808000000` (Aug 8).** `refresh_store_rating()` recomputes from `reviews` + legacy `product_reviews` + `store_reviews` (weighted by count) on every insert/update/delete. `NULL` = no reviews yet (badge hidden). | Customer store screens, seller dashboard, seller store profile |

Before that migration, store ratings were static `5.0` defaults — see §5.10 for how the live mechanism works now.

---

## 1. Store data model (Supabase)

**Table:** `public.stores` — master definition in `supabase/schema.sql` (§2), mutated incrementally by the migrations listed below.

| Column | Type | Notes |
|---|---|---|
| `id` | `UUID PK DEFAULT gen_random_uuid()` | |
| `name` | `TEXT NOT NULL` | |
| `tagline` | `TEXT` | |
| `location` | `TEXT NOT NULL` | e.g. `'Valladolid, Carcar City'` |
| `brand_color` | `TEXT DEFAULT '#8B5A2B'` | Hex; parsed by `AppConstants.parseBrandColor` |
| `banner_url` | `TEXT` | `store-assets` bucket |
| `logo_url` | `TEXT` | `store-assets` bucket |
| `rating` | `NUMERIC(2,1)`, nullable, no default | ⚠️ **Trigger-maintained** — see §5.10; `NULL` = no reviews yet |
| `review_count` | `INTEGER NOT NULL DEFAULT 0` | Added `20260807000000_add_store_rating_aggregation.sql` |
| `is_open` | `BOOLEAN DEFAULT true` | Store open/closed toggle |
| `is_active` | `BOOLEAN DEFAULT true` | Soft-deactivate; customer queries filter `is_active = true` |
| `owner_id` | `UUID REFERENCES profiles(id)` | The seller; **UNIQUE** — one store per seller (§2) |
| `created_at` | `TIMESTAMPTZ` | |
| `auto_schedule_enabled` | `BOOLEAN DEFAULT false` | Added `20260729000000_add_store_auto_schedule.sql` |
| `open_time` / `close_time` | `TEXT` (`'HH:MM:SS'` wall clock, Asia/Manila) | Same migration |
| `manual_override` | `BOOLEAN DEFAULT false` | Seller manually closed against schedule; cron clears at next transition |
| `gcash_qr_url` | `TEXT` | Static GCash QR for POS checkout — added `20260806000000_add_static_gcash_qr.sql` (re-added after `20260730000000` dropped the manual-GCash flow) |
| `gcash_number` | `TEXT` | Same migration |
| `gcash_account_name` | `TEXT` | Same migration |

**Relevant migrations (chronological):**
- `20260709_one_store_per_seller.sql` — dedupe + `UNIQUE` on `owner_id` (constraint `unique_owner_store`)
- `20260729000000_add_store_auto_schedule.sql` — auto open/close scheduling
- `20260730000000_add_paymongo_gcash_columns.sql` — dropped manual GCash columns
- `20260806000000_add_static_gcash_qr.sql` — re-added static GCash QR columns

### 1.1 Entity relationships

```
profiles (owner_id) 1 ── 1 stores 1 ── N products
                        │ 1 ── N order_items/orders, customization_requests, sales_transactions
                        │ 1 ── N story_entries (workshop stories)
                        │ 1 ── N seller_notifications
                        │ 1 ── N conversations (messaging)
                        │ 1 ── N reviews (store_id)   ← product-review ratings root
                        │ 1 ── N store_reviews (store_id, customer_id)  ← direct store ratings
                        └ 1 ── N store_follows (user_id, store_id) PK
```

- `store_follows` has `PRIMARY KEY (user_id, store_id)`; unique constraint enforced again by migration `20260720120000_add_store_follows_unique_constraint.sql`.
- ⚠️ `products.store_id` FK is plain `REFERENCES public.stores(id)` — **NO `ON DELETE CASCADE`** (defaults to NO ACTION; same for `orders.store_id` and `customization_requests.store_id`). Only `sales_transactions`, `story_entries`, `store_follows`, `seller_notifications`, `conversations`, `reviews`, and `store_reviews` cascade. Deleting a store therefore requires reassigning child rows first — exactly what `20260709_one_store_per_seller.sql` does when deduping duplicate stores.
- **Type note:** `schema.sql` declares `products.id TEXT`, `orders.id BIGINT`, `order_items.id BIGINT`. Migration `20260718_order_item_reviews.sql` warns the **live DB actually uses UUID** for `products.id`, `orders.id`, and `order_items.id`. The Dart layer treats every id as a `String` everywhere, which is why this never surfaces at runtime. See §10.

---

## 2. Store lifecycle — one store per seller

**Rule enforced in two layers:**

1. **DB:** `20260709_one_store_per_seller.sql` adds `UNIQUE` constraint `unique_owner_store` on `stores.owner_id` (after deduping duplicates and reassigning child rows to the keeper store).
2. **App:** `StoreService.createStore()` calls `getMyStore()` first and throws `'You already have a store. Each seller can only manage one store.'`

**Store creation** (`lib/screens/seller/create_store_screen.dart` → `StoreService.createStore`): inserts `{owner_id, name, tagline, location, brand_color, is_open: true, is_active: true}`, then uploads optional logo/banner to `store-assets/{sellerId}/{storeId}/logo.jpg` and `banner.jpg` and patches `logo_url`/`banner_url`.

**Store editing** (`edit_store_screen.dart` → `updateStoreSeller`): name/tagline/location/brand_color/is_open; logo/banner replaced with timestamped paths (`logo_{ts}.jpg`) or nulled with `removeLogo`/`removeBanner`.

**Open/close + auto-schedule** (`StoreService.toggleStoreOpen` / `updateStoreSchedule` / `clearManualOverride`):
- Manual toggle with auto-schedule ON: closing sets `manual_override = true`; reopening clears it.
- Enabling schedule clears `manual_override` so the cron takes over.

**GCash QR** (`StoreService.updateGcashSettings`): uploads to stable path `{sellerId}/{storeId}/gcash_qr.png` with `upsert: true` (replacing the QR never orphans files), and best-effort removes the object when `removeQr` is passed.

---

## 3. Store RLS policies

From `schema.sql` §2 — all `public.stores` rows:

| Policy | Command | Rule |
|---|---|---|
| `"Stores are viewable by everyone"` | SELECT | `USING (true)` |
| `"Store owners can insert their store"` | INSERT | `auth.uid() = owner_id` |
| `"Store owners can update their store"` | UPDATE | `auth.uid() = owner_id` |
| `"Admins can manage all stores"` | ALL | `profiles.role = 'admin'` |

Child tables follow the same "owner via `stores.owner_id`" pattern: `story_entries`, `products` (plus admin), `inventory`, `product_images`, `product_variants`, `product_customizations`, `orders` (SELECT for store owner), `sales_transactions`, `seller_notifications`, `conversations`.

---

## 4. App layer

### 4.1 Model — `lib/models/store.dart`

`Store` maps 1:1 to the `stores` table (incl. auto-schedule fields). Notable derived getters:
- `color` → `AppConstants.parseBrandColor(brandColor)`
- `initials` → first letters of first two words (avatar fallback)
- `cardGradient` → brand color lerped toward `0xFF1A1208`
- `hoursLabel` → `'9:00 AM – 5:00 PM'` from `open_time`/`close_time`

`Store.fromMap` maps `rating` (nullable — no fake `5.0` default) and `reviewCount` (`stores.review_count`).

### 4.2 Service — `lib/services/store_service.dart` (`StoreService.instance` singleton)

**Seller side:** `getMyStore()`, `createStore(...)`, `updateStoreSeller(...)`, `updateGcashSettings(...)`, `toggleStoreOpen(...)`, `clearManualOverride(...)`, `updateStoreSchedule(...)`, `uploadStoreAsset(...)`, `updateStore(storeId, data)`.

**Customer side:** `fetchAllStores()` (only `is_active = true`, newest first), `fetchStoreById(id)`, `getProductCountForStore(...)` (pure helper), `getStoryEntriesForStore(id)`.

**Follow side:** `followStore` / `unfollowStore` / `isFollowingAsync` / `toggleFollow` / `getFollowedStores(userId)` (join query with **fallback** to two queries when the FK relationship is missing) / `getFollowerCounts(storeIds)` / `getFollowingCount(userId)` / `getFollowerCount(storeId)`.

> `followStore` uses **upsert on conflict `(user_id, store_id)`** so rapid double-taps are idempotent.

### 4.3 Provider — `lib/providers/follow_provider.dart`

Owns all follow state app-wide (`ProfileScreen`, Following dialog, `StoreProfileScreen` share it). Key behaviors:
- `_followedStoreIds` set + `_pendingStoreIds` per-store in-flight guard (prevents concurrent toggles).
- `_followerCountCache` per-store follower counts; `followerCountFor(storeId, {fallback})`.
- `toggle()` is **optimistic with rollback** on failure; re-fetches the followed list and reconciles `followingCount` against DB (`getFollowingCount`) after success.
- `reconcileCount(userId)` re-syncs on dialog open to catch drift.
- Careful not to call `notifyListeners()` in `finally` (avoids "setState during build").

### 4.4 UI map

**Customer side:**
- `lib/screens/store/store_screen.dart` — "market walk" discovery tab: hero carousel → focused store info → cross-store product rows
- `lib/screens/store/store_profile_screen.dart` — full store profile (banner, stats incl. `★ {store.rating}`, products, stories, follow button)
- `lib/screens/store/widgets/store_hero_card.dart`, `store_focused_info.dart`, `cross_store_product_row.dart`
- `lib/screens/store/collection_screen.dart` — store-filtered product grid
- `lib/screens/shared/following_list_dialog.dart` — list of followed stores

**Seller side:**
- `lib/screens/seller/create_store_screen.dart` / `edit_store_screen.dart` — create/manage
- `lib/screens/seller/store_profile_screen.dart` — seller's own store view (shows `Rating` metric from `_store?['rating']`)
- `lib/screens/seller/store_reviews_screen.dart` — all reviews for the store, with seller replies (§9.7)
- `lib/screens/seller/seller_dashboard_screen.dart` — reads `data.store?['rating']` and renders `'{rating} ★'`

---

## 5. Ratings & reviews — deep dive

### 5.1 Three review sources, two trigger targets

| Table | Purpose | Status |
|---|---|---|
| `reviews` | **Per-order-item** reviews (Shopee/Lazada-style, one per purchased line item), `UNIQUE(order_item_id)`, `store_id` FK — this is **the primary, going-forward table** | ✅ Active |
| `product_reviews` | **Legacy per-product** reviews (one per product per customer, `UNIQUE(product_id, customer_id)`) | ⚠️ Legacy — kept, still counted |
| `store_reviews` | **Direct store reviews** ("Rate this store", one per customer per store, `UNIQUE(store_id, customer_id)`), added `20260808000000_add_store_reviews.sql` | ✅ Active |

`reviews` + `product_reviews` feed the **product** summary (`refresh_product_rating()`). All **three** feed the **store** summary (`refresh_store_rating()`), weighted by count.

### 5.2 `reviews` (primary table)

Columns: `id`, `order_id`, `order_item_id`, `product_id`, `customer_id`, `store_id`, `rating SMALLINT CHECK (1–5)`, `comment`, `seller_reply`, `seller_reply_at`, `created_at`, `updated_at`, `UNIQUE(order_item_id)`.

Indexes: `order_id`, `product_id`, `customer_id`, `store_id`, `order_item_id`.

`review_images`: `id`, `review_id (FK CASCADE)`, `image_url`, `display_order`. Uploaded to the **`review-images`** storage bucket under `{customerId}/{reviewId}/{timestamp}_{index}.{ext}`.

### 5.3 `product_reviews` (legacy)

Columns: `id`, `product_id`, `customer_id`, `order_id`, `rating`, `title`, `body`, `is_verified BOOLEAN`, `created_at`, `updated_at`, `UNIQUE(product_id, customer_id)`.

Compared to `reviews` it differs on more than just `store_id` — it has **no** `order_item_id`, `comment`, `seller_reply`, or `seller_reply_at` (it uses `title` + `body` instead of `comment`, and carries an `is_verified` flag). Images in `product_review_images`. **It has no `store_id`** — one reason there is no store-level aggregate.

### 5.4 The refresh trigger — `refresh_product_rating()`

Defined in `20260718_order_item_reviews.sql` (replaces the older `20260717` version). Attached to **both** tables:

```sql
AFTER INSERT OR UPDATE OF rating OR DELETE ON public.reviews
AFTER INSERT OR UPDATE OF rating OR DELETE ON public.product_reviews
```

Logic (`SECURITY DEFINER`):
1. Resolves `target_product_id = COALESCE(NEW.product_id, OLD.product_id)`.
2. Computes `AVG(rating)` rounded to 1 decimal + count from `reviews`.
3. If `product_reviews` exists, computes its own avg/count and **merges weighted by count**: `v_avg = (v_avg*v_count + pr_avg*pr_count) / (v_count + pr_count)`.
4. Writes `products.avg_rating = COALESCE(v_avg, 0)` and `products.review_count = COALESCE(v_count, 0)`.

So `products.avg_rating`/`review_count` are always live. **This trigger ONLY touches `products` — never `stores.rating`.**

### 5.5 RLS on reviews

| Policy | Command | Rule |
|---|---|---|
| `"Reviews are viewable by everyone"` | SELECT | `true` |
| `"Customers can insert reviews for delivered orders"` | INSERT | `auth.uid() = customer_id` **AND** the `order_item_id` belongs to an order of that customer with `o.status = 'received'` |
| `"Customers can update own reviews"` | UPDATE | `auth.uid() = customer_id` |
| `"Customers can delete own reviews"` | DELETE | `auth.uid() = customer_id` |
| `"Sellers can reply to store reviews"` | UPDATE | `stores.owner_id = auth.uid()` for the review's `store_id` |
| Review images | SELECT `true` / ALL for review owner | |

⚠️ **Gotcha:** the seller UPDATE policy is whole-row — the **app** limits sellers to `seller_reply`/`seller_reply_at` (via `ReviewService.sellerReply`), but a direct API caller could edit any column of a review belonging to their store. If that matters, split the reply into a separate table or add a trigger.

### 5.6 Service — `lib/services/review_service.dart` (`ReviewService.instance`)

All Supabase access for reviews goes through here; screens never touch Supabase directly.

| Method | Purpose |
|---|---|
| `getReviews(productId)` | All reviews for a product, joined `profiles!customer_id(full_name, avatar_url)` + `review_images`, newest first |
| `getMyReview(productId)` | Current user's review for a product |
| `canReview(productId)` | UI gate: no existing review **and** a completed order (`ready`/`received`/`delivered`) contains the product |
| `getRatingSummary(productId)` | **Client-side aggregation** — fetches *all* reviews and computes `{avg_rating, review_count, breakdown{1..5}}` in Dart (§5.8) |
| `getStoreReviews(storeId)` | Seller side: all reviews for a store, joined reviewer profile, images, and `order_items(products(name))` |
| `getOrderItemsWithReviewStatus(orderId)` | Order items + attached `review` (null if unreviewed) |
| `submitOrderItemReview({orderId, orderItemId, productId, storeId, rating, comment, images})` | Insert (validates all 5 UUIDs non-empty, rating 1–5) + uploads images |
| `updateOrderItemReview(...)` / `updateReview(...)` | Ownership check client-side, update rating/comment, remove deleted images (and their storage files), upload new ones |
| `submitReview({productId, rating, title?, body?, images})` | Legacy-ish path: **auto-discovers** the best `order_id`/`order_item_id`/`store_id` from the customer's completed orders |
| `deleteOrderItemReview(id)` / `deleteReview(id)` | Removes images + storage files, then deletes row (cascade cleans image rows) |
| `sellerReply({reviewId, reply})` | Sets `seller_reply` + `seller_reply_at` |
| `getStoreLevelReviews(storeId)` | All **direct store reviews** (`store_reviews`), joined reviewer profiles, newest first |
| `getMyStoreReview(storeId)` | Current user's direct store review (or null) |
| `canReviewStore(storeId)` | Verified-buyer gate for store reviews: a `received` order from this store **and** no existing review (matches RLS exactly) |
| `submitStoreReview({storeId, rating, comment})` | Insert into `store_reviews` (rating 1–5) |
| `updateStoreReview({reviewId, rating, comment})` / `deleteStoreReview(reviewId)` | Ownership-checked edit/delete of a direct store review |

Normalization: `_normalizeOrderItemReview` flattens the joined `profiles` into `reviewer_name`/`reviewer_avatar`, sorts images by `display_order`, aliases `body` ⇄ `comment`, and extracts `product_name`/`item_size`/`item_quantity` from the nested `order_items` join.

### 5.7 Provider — `lib/providers/review_provider.dart`

Registered in `main.dart` as a top-level `ChangeNotifierProvider`. State:

- **Per-product:** `reviews`, `myReview`, `ratingSummary`, `canReview`, `isLoading`
- **Per-order-item:** `orderItems`, `isLoadingOrderItems`
- **Seller:** `storeReviews`, `isLoadingStoreReviews`
- **Store-level:** `storeLevelReviews`, `myStoreReview`, `canReviewStore`, `isLoadingStoreLevelReviews`

Derived getters: `avgRating` / `reviewCount` / `breakdown` (parsed from `ratingSummary`), `unreviwedItemCount`, `allItemsReviewed`.

Key methods: `loadReviews(productId)` fires **4 queries in parallel** (`getReviews`, `getMyReview`, `canReview`, `getRatingSummary`); `loadOrderItems(orderId)`; `loadStoreReviews(storeId)`; `loadStoreLevelReviews(storeId)` fires **3 in parallel** (reviews list, my review, can-review gate); submit/update/delete wrappers that reload state on success; `sellerReply` (reloads store reviews); `reset()` / `resetOrderItems()`.

### 5.8 Where the numbers come from — **two different sources!**

This is subtle and easy to break:

- **Product cards / catalog** (`sole_product_card.dart`) read `product['avg_rating']` and `product['review_count']` — i.e. the **denormalized trigger-maintained columns** on the product row.
- **Product detail page** (`product_detail_screen.dart` → `_buildRatingSummary`) reads `provider.avgRating` / `provider.breakdown` — i.e. the **client-side aggregation from `getRatingSummary()`**, which re-fetches every review and recomputes in Dart.

Both usually agree, but they're computed independently. `getRatingSummary` also includes the 5★→1★ `breakdown` used for the distribution bars (which the denormalized columns don't carry).

### 5.9 Rating UI surfaces

| Widget/Screen | What it shows | Data source |
|---|---|---|
| `lib/widgets/sole_star_rating.dart` | Reusable 1–5 star row (display or interactive tap-to-set) | any rating int |
| `lib/widgets/sole_review_card.dart` | One review: stars, comment, photos, reviewer name/avatar, `is_verified` badge, `seller_reply` block | normalized review map |
| `sole_product_card.dart` | Stars + `(n)` **only if** `review_count > 0` | `product['avg_rating']` / `product['review_count']` |
| `product_detail_screen.dart` `_buildRatingSummary` | Big avg number, stars, count, distribution bars | `ReviewProvider.avgRating` / `breakdown` (client-side) |
| `order_review_screen.dart` | Per-item "Rate & Review" buttons + existing review summaries per delivered order item | `ReviewProvider.orderItems` |
| `write_review_screen.dart` | Star picker (`SoleStarRating` interactive) + comment + images | → `ReviewService` |
| `store_profile_screen.dart` Store Reviews section / `rate_store_screen.dart` | Direct store rating: rate/edit/delete CTA + store review list | `ReviewProvider.storeLevelReviews` / `myStoreReview` / `canReviewStore` |
| `seller/store_reviews_screen.dart` | Store review list; seller computes a display avg in-page (`total/len`); reply posting | `ReviewProvider.storeReviews` |
| Customer store screens (`store_hero_card`, `store_focused_info`, `store_profile_screen`) | `⭐ {store.rating}` stat pill (hidden until `review_count > 0`) | `stores.rating` (trigger-maintained) |
| Seller dashboard / seller store profile | `{rating} ★` / "No reviews" placeholder | `stores.rating` (trigger-maintained) |

### 5.10 Store rating — trigger-maintained from 3 sources (since 2026-08-07, extended 2026-08-08)

Migration `20260807000000_add_store_rating_aggregation.sql` made store ratings real; `20260808000000_add_store_reviews.sql` extended the aggregate to include direct store reviews:

- `stores.rating` is **nullable** with the `DEFAULT 5.0` **dropped** — `NULL` means "no reviews yet" and the app hides the badge (see §5.9). `stores.review_count INTEGER NOT NULL DEFAULT 0` was added.
- `refresh_store_rating()` (SECURITY DEFINER) fires on `AFTER INSERT OR UPDATE OF rating OR DELETE` on **all three** tables (`reviews`, `product_reviews`, `store_reviews`):
  - From `reviews`/`store_reviews` it uses `store_id` directly; from legacy `product_reviews` (which has no `store_id`) it resolves via `products.store_id`.
  - Aggregates `AVG(rating)` (1 decimal) + `COUNT(*)` from each source and merges **weighted by count** — identical math to `refresh_product_rating()`. Shared helper `refresh_store_rating_stats(store_id)` is the single aggregation implementation.
  - Writes `stores.rating = v_avg` (or `NULL` when the total count is 0) and `stores.review_count = total`.
  - If the store can't be resolved (e.g. a legacy review whose product was deleted), it exits early without erroring.
- Both migrations **backfill every existing store** through the shared helper, so ratings are correct immediately rather than after the next review event.
- RLS: unchanged for `stores` (SELECT already public; trigger runs `SECURITY DEFINER`). `store_reviews` gets its own policies (§5.11).

### 5.11 `store_reviews` — direct "Rate this store"

Added `20260808000000_add_store_reviews.sql`. Columns: `id`, `store_id (FK CASCADE)`, `customer_id (FK CASCADE)`, `rating SMALLINT CHECK (1–5)`, `comment TEXT`, `created_at`, `updated_at`, `UNIQUE(store_id, customer_id)`.

**RLS** (verified-buyer-only, mirrors the `reviews` INSERT gate and avoids the §7.3 `canReview` mismatch — app and DB both require `status = 'received'`):

| Policy | Command | Rule |
|---|---|---|
| `"Store reviews are viewable by everyone"` | SELECT | `true` |
| `"Customers can rate stores after receiving an order"` | INSERT | `auth.uid() = customer_id` **AND** a `received` order from that store exists (`orders.store_id = store_reviews.store_id`); `UNIQUE(store_id, customer_id)` enforces one per customer |
| `"Customers can update own store reviews"` | UPDATE | `auth.uid() = customer_id` |
| `"Customers can delete own store reviews"` | DELETE | `auth.uid() = customer_id` |

**Customer flow:** `store_profile_screen.dart` Store Reviews section → `RateStoreScreen` (new/edit) → `ReviewProvider.submitStoreReview` → `ReviewService.submitStoreReview` → `INSERT store_reviews` → trigger recomputes `stores.rating`/`review_count`. `ReviewService.canReviewStore` mirrors the RLS gate (has `received` order + no existing review).

---

## 6. Review flow walkthrough (customer)

```
Order delivered → My Orders tab "Review" → OrderReviewScreen
        │  loads items via ReviewProvider.loadOrderItems(orderId)
        │  each item: "Rate & Review" (or existing summary)
        ▼
WriteReviewScreen (order-item mode: orderId/orderItemId/storeId/productId)
        │  star picker + comment + up to N photos
        ▼
ReviewService.submitOrderItemReview → INSERT reviews (RLS: must own a 'received' order with that item)
        │  → review_images rows in bucket 'review-images'
        ▼
trigger refresh_product_rating() → products.avg_rating/review_count updated
        ▼
product cards / detail page reflect the new average
```

Seller reply flow: `seller/store_reviews_screen.dart` → `ReviewProvider.sellerReply` → `ReviewService.sellerReply` (updates `seller_reply` + `seller_reply_at`) → reloads store reviews.

---

## 7. Known gaps & gotchas

1. **Store ratings are now live** (migrations `20260807000000` + `20260808000000`, §5.10–§5.11) — don't reintroduce a static `5.0` default when creating stores; the trigger owns `stores.rating`/`review_count` exclusively.
2. **`getRatingSummary()` is client-side and unpaginated** — it fetches every review for the product to compute the average + breakdown. Fine for small review sets; a top seller's product with thousands of reviews will pull a large payload. Prefer `products.avg_rating` for the headline number; the breakdown genuinely needs per-star counts (could be a SQL `GROUP BY rating`).
3. **`canReview` vs RLS mismatch:** the app's `canReview` accepts orders with status `ready`/`received`/`delivered`, while the RLS INSERT policy requires `status = 'received'`. A customer whose order is `ready`/`delivered` will see the "Write Review" button, and the insert will then be **silently blocked by RLS**. Keep them aligned (either loosen RLS or tighten `canReview`).
4. **ID type discrepancy:** `schema.sql` documents `products.id TEXT`, `orders.id BIGINT`, `order_items.id BIGINT`, but `20260718_order_item_reviews.sql` says the live DB uses **UUID** for all three. All Dart code treats ids as strings, which hides it — but any future raw-SQL join must be written for UUID.
5. **Seller UPDATE policy is whole-row** (§5.5) — app-layer-only enforcement of "reply only".
6. **Two review tables, one average** — the product average silently merges `reviews` + legacy `product_reviews`. If you ever delete legacy rows, the trigger self-corrects; if you ever add a third review source, update `refresh_product_rating()` in one place only.
7. **Delete flows clean up storage** (`_removeStorageFile` parses the URL, removes from `review-images`) — keep that pairing if you add new delete paths.

---

## 8. Key files

| File | Role |
|---|---|
| `supabase/schema.sql` | Master schema — `stores` (§2), `reviews`/`product_reviews` (§16–17) + trigger |
| `supabase/migrations/20260717_product_reviews.sql` | Legacy per-product reviews + first trigger version |
| `supabase/migrations/20260718_order_item_reviews.sql` | **Primary** `reviews` table, dual-source trigger, RLS |
| `supabase/migrations/20260807000000_add_store_rating_aggregation.sql` | **Store-level ratings**: nullable `stores.rating`, `stores.review_count`, `refresh_store_rating()` trigger + backfill |
| `supabase/migrations/20260808000000_add_store_reviews.sql` | **Direct "Rate this store"**: `store_reviews` table + RLS, extends `refresh_store_rating()` to 3 sources, backfill |
| `supabase/migrations/20260709_one_store_per_seller.sql` | `UNIQUE(owner_id)` |
| `supabase/migrations/20260729000000_add_store_auto_schedule.sql`, `20260806000000_add_static_gcash_qr.sql` | Store columns |
| `lib/models/store.dart` | `Store` model (incl. `rating`) |
| `lib/models/followed_store.dart` | Followed-store overlay model |
| `lib/services/store_service.dart` | All store + follow DB access |
| `lib/providers/follow_provider.dart` | Optimistic follow state |
| `lib/services/review_service.dart` | All review DB access + image upload/cleanup |
| `lib/providers/review_provider.dart` | Review state (product / order-item / seller) |
| `lib/widgets/sole_star_rating.dart` | Star row (display + picker) |
| `lib/widgets/sole_review_card.dart` | Single review card (incl. seller reply) |
| `lib/widgets/sole_product_card.dart` | Stars + count from `product['avg_rating']`/`review_count` |
| `lib/screens/customer/product_detail_screen.dart` | `_buildRatingSummary` (avg + breakdown) |
| `lib/screens/customer/order_review_screen.dart` / `write_review_screen.dart` | Customer product-review flow |
| `lib/screens/store/rate_store_screen.dart` | Direct store rating (new/edit) |
| `lib/screens/seller/store_reviews_screen.dart` | Seller review list + replies |
| `lib/screens/store/…` , `lib/screens/seller/store_profile_screen.dart`, `seller_dashboard_screen.dart` | Store rating displays (`stores.rating`) |

---

## 9. Modification checklist

1. **`stores.rating`/`stores.review_count` are trigger-owned.** Never write them from app code (store create/edit screens must not touch them). The `refresh_store_rating()` trigger + shared helper `refresh_store_rating_stats()` (migrations `20260807000000` + `20260808000000`) are the single source of truth — it aggregates **three** sources (`reviews`, `product_reviews`, `store_reviews`) weighted by count.
2. **Keep both review tables feeding `refresh_product_rating()`.** The weighted merge is intentional. Change it in the trigger, not in app code.
3. **Product card stars come from `product['avg_rating']`/`review_count`; the detail-page summary comes from `ReviewProvider`.** Don't swap one for the other without checking both surfaces update after a review.
4. **New review write paths must** (a) pass all of `order_id`/`order_item_id`/`product_id`/`store_id`/`rating` as non-empty strings, (b) keep the `body`⇄`comment` aliasing in `_normalizeOrderItemReview` for downstream consumers, (c) upload to `review-images` and clean up storage on delete.
5. **RLS is the real gate** — `canReview` is a UI convenience. Align its status list with the RLS `status = 'received'` check (§7.3).
6. **Follow toggles must stay optimistic + idempotent** — upsert on conflict, per-store in-flight guard, rollback on failure, and no `notifyListeners()` in `finally`.
7. **If you add store columns**, mirror them in `Store` model (`fromMap`/`toMap`) and the create/edit screens — `toMap` is used for upserts.
