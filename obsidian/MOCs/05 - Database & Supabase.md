# 🗄️ Database & Supabase

> Schema, RLS, migrations, triggers, and backup for the PostgreSQL/Supabase backend. **#moc**

---

## 📌 Overview

Supabase (PostgreSQL + RLS + Auth + Storage) on project `psczvbfoybqhjeqssimw.supabase.co`. **RLS is the security boundary** — every role's access is enforced at the DB layer, never just in app code. Migrations live in `supabase/migrations/` (numeric filenames, replayable, idempotent where possible). ⚠️ **`supabase/schema.sql` is OUTDATED — never use it as a source of truth.**

---

## 🗄️ Tables (essentials)

| Table | Purpose | Key relationships |
|-------|---------|-------------------|
| `profiles` | Users + roles + seller_status + suspension fields + foot profile + Tier 1 verification | FK → `auth.users` |
| `stores` | Artisan stores, branding, GCash QR, `rating` | `owner_id → profiles` |
| `products` | Listings — **`id` TEXT PK**, `is_active`, `is_published`, `sale_price` | `store_id → stores`, `seller_id → profiles` (nullable) |
| `product_variants` | Per size+color stock (`BIGINT` identity PK) | `product_id → products` CASCADE |
| `inventory` | **Aggregated stock per size — AUTHORITATIVE** (UNIQUE `(product_id, size)` in live DB) | `product_id → products` CASCADE |
| `product_images` | Photos (`is_primary`, `display_order`) | CASCADE |
| `product_customizations` | Customization options per product | CASCADE |
| `orders` | **`id` UUID PK** (live DB; schema.sql says BIGINT — stale) | `store_id → stores`, `customer_id → profiles` |
| `order_items` | Line items | `order_id` CASCADE, `product_id` **SET NULL** |
| `sales_transactions` / `_items` | POS | `store_id`; `product_id` SET NULL |
| `cart_items` | Server cart (**has `size` column**) | `user_id → profiles`, `product_id` CASCADE |
| `customization_requests` | Bespoke shoe requests | `customer_id`, `store_id`, `base_product_id` SET NULL |
| `store_follows` | `(user_id, store_id)` composite PK | — |
| `reviews` / `product_reviews` / `store_reviews` | Ratings | see [[obsidian/MOCs/07 - Products, Stores & Features|🛍️ Products MOC]] |
| `notifications` / `seller_notifications` | In-app feeds | see [[obsidian/MOCs/06 - Notifications & Messaging|🔔 Notifications MOC]] |
| `conversations` / `messages` | Chat | see Messaging |
| `payment_intents` / `payment_webhook_events` / `payment_fee_config` | Online GCash (attempt #6) | see [[obsidian/MOCs/01 - Checkout, Orders & Payments|💳 Checkout MOC]] |
| `seller_business_docs` | Tier 2 verification docs | `profile_id` unique |
| `device_tokens` | FCM push tokens | — |
| `banners` | Home screen banner carousel (image, link, display order) | — |
| `deletion_requests` | Account deletion requests (customer-initiated) | `user_id → profiles` |
| `product_color_images` | Per-color photo galleries (one gallery per product color) | `product_id → products` CASCADE |
| `order_status_history` | Order status change audit trail | `order_id` (BIGINT, different table!) |
| `reports` | User-submitted reports (product/user/order) | `reporter_id → profiles` |

### FK delete rules (do not change)
`order_items`/`sales_transaction_items`/`customization_requests.base_product_id` → **SET NULL** (preserve history) · `inventory`/`product_variants`/`product_images`/`product_customizations`/`cart_items` → **CASCADE**. ⚠️ `products.store_id` / `orders.store_id` / `customization_requests.store_id` have **NO cascade** (NO ACTION) — deleting a store requires reassigning children first.

### ID types (confirmed — see SCHEMA_REFERENCE)
- `orders.id` **UUID** (not BIGINT) · `order_status_history.order_id` **BIGINT** (different table!) · `products.id` **TEXT** · `reviews.*` UUID, `product_id` TEXT.
- Dart rule: UUID/TEXT → `String` via `.toString()`; never `int.parse()` on UUIDs; BIGINT may come back as String → `_asInt()`.

---

## ⚡ Triggers

| Trigger | Fires on | Purpose |
|---------|----------|---------|
| `decrement_inventory_on_order()` | `order_items` INSERT | Decrements `inventory.stock`; raises `Insufficient stock` (P0001) on oversell |
| `decrement_inventory_on_sale()` | `sales_transaction_items` INSERT | Same for POS |
| `refresh_store_rating()` | INSERT/UPDATE OF rating/DELETE on `reviews` + `product_reviews` + `store_reviews` | Recomputes `stores.rating` (SECURITY DEFINER) |
| `guard_seller_business_docs_status` | `seller_business_docs` | Blocks owner self-certification (verified/rejected) |
| `prevent_admin_self_lockout` / `protect_last_admin` | `profiles` UPDATE | Refuse demote/suspend of yourself or the last active admin |
| Profile auto-create | `auth.users` INSERT (handle_new_user) | Creates the `profiles` row after signup |
| `trg_record_order_status_change` | `orders` UPDATE OF status | Records status changes in `order_status_history` |
| `trg_compute_report_priority` | `reports` INSERT/UPDATE | Auto-computes priority based on report type + severity |
| `trg_check_duplicate_report` | `reports` INSERT | Prevents duplicate reports from same reporter |
| `trg_notify_on_seller_approved` | `profiles` UPDATE OF seller_status | Sends notification when seller is approved |
| `trg_set_customer_name` / `trg_sync_customer_name` | `conversations` / `profiles` | Syncs customer name to conversation records |
| `trg_update_conversation_on_message_delete` | `messages` DELETE | Updates conversation last message on delete |

Both inventory triggers are `SECURITY DEFINER` (July 4 2026 fix — RLS was blocking the trigger's UPDATE) and normalize size via `regexp_replace(size, '\D', '', 'g')`.

---

## 🔐 RLS policy matrix

| Table | Customer | Seller | Admin |
|-------|----------|--------|-------|
| `profiles` | Read all, update own | Read all, update own | Read all, update any |
| `products` | Read all | CRUD own store | CRUD any |
| `orders` | CRUD own | Read all, update own store | Read all, update any |
| `inventory` | Read all | CRUD own store | CRUD any |
| `cart_items` | CRUD own | — | — |
| `customer_addresses` | CRUD own | — | — |
| `stores` | Read all | Update own | Update any |

**Suspension enforcement (migration `20260813000000`):** `is_suspended()` SECURITY DEFINER helper; `is_admin()`/`is_seller_or_admin()` redefined with `AND NOT COALESCE(suspended, false)`; explicit `AND NOT is_suspended()` on customer-write policies (`orders`, `cart_items`, `reviews`, `product_reviews`, `customization_requests`, `conversations`, `messages`, `store_follows`, `sales_transactions`). Guard triggers prevent self-lockout + last-admin loss. **A suspended account loses all elevated access the instant the flag flips.**

---

## 🗺️ Migrations & deployment

- Migration files: `supabase/migrations/` — numeric names (`20260702_…`, `20260813…`), applied to the live DB. ⚠️ **CLI migration tracking is unreliable** — verify via `supabase/MIGRATIONS_LIVE_STATUS.md`, not `supabase migration list`.
- **The #1 cause of past failed fixes**: SQL written but never applied to the live DB. Always verify a migration landed.
- Realtime: `ALTER PUBLICATION supabase_realtime ADD TABLE public.profiles` (and others) must be enabled in the dashboard for live features.
- Storage buckets: `avatars`, `product-images`, `store-assets`, `banners` (public) · `seller-verification-docs`, `payment-proofs`, `chat-attachments` (private, signed URLs).
- Edge Functions: `create-gcash-payment-intent`, `gcash-webhook`, `get-payment-status`, `send-message-push`, `send-notification-push`, `product-preview` (share OG images), `apply-store-schedules`, `create-gcash-payment`, `request-account-deletion`, `send-approval-email`.

## ⚠️ Gotchas

1. **NEVER trust `supabase/schema.sql`** — docs + live DB are truth.
2. `inventory` is authoritative for stock; `product_variants` may be stale — they must stay in sync (two-directional sync, see [[obsidian/MOCs/03 - Seller Module|👞 Seller MOC]]).
3. `product_reviews` may not exist in some environments — the suspension migration guards it with `to_regclass(...) IS NOT NULL`. **Do not create it "for completeness"** — `20260717_product_reviews.sql` would overwrite `refresh_product_rating()` and break ratings.
4. `story_entries` has **no `title` column** in the live DB.
5. Empty strings are invalid UUIDs — validate non-empty before inserting into UUID columns.
6. Revenue queries: `status != 'cancelled'` AND `payment_status = 'paid'`, combining `orders` + `sales_transactions`.

## 📚 Deep-dive docs

- [[docs/SoleVision_Complete_Documentation|📘 Master documentation]] — 22 sections; the schema reference (Section 4)
- [[SCHEMA_REFERENCE|SCHEMA_REFERENCE.md]] — ID types for review submission (repo root)
- [[docs/AI_PROJECT_SUMMARY|⚡ AI Project Summary — "Database Schema"]] — tables, FK rules, triggers, RLS matrix
- [[docs/HARDENING_SQL_QUERIES|Hardening SQL queries]]
- [[docs/BACKUP_AND_RESTORE|Backup & restore]]
- [[docs/VERIFICATION_AUDIT_JULY_4_2026|Verification audit July 4]] — proof fixes were never deployed
- [[docs/PROJECT_HANDOFF|📄 Project Handoff — schema & RLS sections]]
- [[docs/project_doc|Project doc (v1.2.0)]] — earlier master reference

## 🔗 Related

- [[obsidian/MOCs/04 - Admin Portal|🛡️ Admin Portal]] — `admin_policies.sql`, suspension enforcement
- [[obsidian/MOCs/00 - Auth & Accounts|🔐 Auth & Accounts]] — `profiles`, RLS
- [[obsidian/MOCs/01 - Checkout, Orders & Payments|💳 Checkout, Orders & Payments]] — payment tables, triggers
- [[obsidian/MOCs/03 - Seller Module|👞 Seller Module]] — inventory sync, POS
