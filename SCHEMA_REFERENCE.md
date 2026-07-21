# Schema Reference — ID Types for Review Submission Path

> **Source of truth**: Inferred from code usage patterns and Supabase error messages.
> Run the SQL query in `REVIEW_SUBMISSION_SCHEMA_AUDIT_PLAN.md` Step 1 to confirm.

## ID Column Types

| Table | Column | Inferred Type | Notes |
|-------|--------|---------------|-------|
| `orders` | `id` | **UUID** | Confirmed by `FormatException: Invalid radix-10 number` on `3593cde2-...` |
| `orders` | `customer_id` | UUID | FK to `profiles.id` |
| `orders` | `store_id` | UUID | FK to `stores.id` — may be NULL for some orders |
| `orders` | `status` | TEXT | Values: `pending`, `preparing`, `ready`, `received`, `delivered` |
| `order_items` | `id` | UUID | |
| `order_items` | `order_id` | UUID | FK to `orders.id` |
| `order_items` | `product_id` | TEXT | FK to `products.id` (products.id is TEXT, not UUID) |
| `products` | `id` | **TEXT** | Confirmed by earlier task — not UUID, not numeric |
| `reviews` | `id` | UUID | Auto-generated |
| `reviews` | `order_id` | UUID | FK to `orders.id` |
| `reviews` | `order_item_id` | UUID | FK to `order_items.id` |
| `reviews` | `product_id` | TEXT | FK to `products.id` |
| `reviews` | `customer_id` | UUID | FK to `profiles.id` |
| `reviews` | `store_id` | UUID | FK to `stores.id` — **must not be empty string** |
| `reviews` | `rating` | INT | 1-5 |
| `review_images` | `id` | UUID | |
| `review_images` | `review_id` | UUID | FK to `reviews.id` |
| `profiles` | `id` | UUID | Supabase auth user ID |
| `stores` | `id` | UUID | |

## Key Findings

1. **`orders.id` is UUID, not BIGINT** — earlier assumptions in `CUSTOMER_ORDER_PROCESS.md` were wrong.
2. **`products.id` is TEXT** — can contain any string (e.g., `"abc123"`), not necessarily UUID format.
3. **`order_status_history.order_id` is BIGINT** — this is a DIFFERENT table with a different type than `orders.id`. The `supabase_service.dart:483` code that does `int.tryParse(orderId.toString())` is correct for that specific table.
4. **Empty strings are NOT valid UUIDs** — PostgreSQL rejects `""` for UUID columns. Always validate non-empty before inserting.

## Dart-Side Type Mapping

| DB Type | Dart Type | Safe Conversion |
|---------|-----------|-----------------|
| UUID | `String` | Use `.toString()` directly, never `int.parse()` |
| TEXT | `String` | Use `.toString()` directly |
| INT | `int` | Use `_asInt()` helper for Supabase responses |
| BIGINT | `int` | Use `_asInt()` helper (PostgREST may return as String) |
