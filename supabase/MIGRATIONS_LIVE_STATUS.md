# Live Database Migration Status

**Project:** `psczvbfoybqhjeqssimw` (Supabase)
**Last verified:** August 16, 2026 (object-level audit via `supabase db query --linked`)
**Source of truth:** this table — **not** `supabase migration list`, whose remote
tracking table is out of sync (old records use pre-rename filenames, so the CLI
shows ~50 migrations as "pending" even though they are applied).

## Status

| Migration | Status | Notes |
|---|---|---|
| `20260601000000_base_schema.sql` | ✅ | All base tables present |
| `20260702_notifications.sql` | ✅ | notifications + triggers |
| `20260703_add_cart_items_size.sql` | ✅ | `cart_items.size` |
| `20260704_add_orders_delete_policy.sql` | ✅ | orders delete-pending policy |
| `20260705_add_customer_addresses.sql` | ✅ | table + `orders.shipping_address` |
| `20260708_fix_customer_addresses_rls.sql` | ✅ | address policies |
| `20260709_one_store_per_seller.sql` | ✅ | `unique_owner_store` |
| `20260711_fix_trigger_security_definer.sql` | ✅ | stock-decrement functions |
| `20260712_tighten_products_rls.sql` | ✅ | product policies |
| `20260713_messaging.sql` | ✅ | conversations/messages RLS |
| `20260714000000_messaging_attachments_schema.sql` | ✅ | message attachment columns |
| `20260714_push_notifications.sql` | ✅ | `device_tokens`, `notify_on_new_message` |
| `20260715090100_fix_fk_join_syntax.sql` | ✅ | documentation only — no schema |
| `20260715090200_fix_profiles_rls_for_conversations.sql` | ✅ | conversation-partner profile policy |
| `20260715090300_add_customer_name_to_conversations.sql` | ✅ | `conversations.customer_name` |
| `20260715_seller_notifications.sql` | ✅ | `seller_notifications` + policies |
| `20260717_product_reviews.sql` | ⚠️ **NOT applied — intentional** | legacy table, superseded by `reviews` (20260718). Do **not** apply: it would overwrite `refresh_product_rating()` and break ratings |
| `20260718_order_item_reviews.sql` | ✅ | `reviews` table (current design) |
| `20260719_add_is_deleted_to_notifications.sql` | ✅ | `notifications.is_deleted` |
| `20260720120000_add_store_follows_unique_constraint.sql` | ✅ | per remote tracking |
| `20260720130000_add_delivered_status.sql` | ✅ | per remote tracking |
| `20260720140000_order_status_history.sql` | ✅ | table + trigger |
| `20260721120000_add_order_cancellation_fields.sql` | ✅ | per remote tracking |
| `20260721_fix_order_status_history_fk.sql` | ✅ | minor FK fix, history works |
| `20260722_fix_orders_status_check_constraint.sql` | ✅ | per remote tracking |
| `20260723120000_add_reports_table.sql` | ✅ | per remote tracking |
| `20260723130000_add_custom_details_to_reports.sql` | ✅ | per remote tracking |
| `20260723140000_add_support_notification_category.sql` | ✅ | per remote tracking |
| `20260723_notification_soft_delete.sql` | ✅ | `is_deleted` + notification policies |
| `20260724000000_add_metadata_and_bulk_ops.sql` | ✅ | per remote tracking |
| `20260725000000_batch_message_notifications.sql` | ✅ | per remote tracking |
| `20260725020000_add_avatar_storage_rls.sql` | ✅ | storage.objects avatar policy |
| `20260726000000_add_order_source_column.sql` | ✅ | `orders.source` |
| `20260726100000_add_tendered_change_to_orders.sql` | ✅ | `amount_tendered` / `change_amount` |
| `20260727000000_add_barcode_to_products.sql` | ✅ | `products.barcode` |
| `20260728000000_relax_customization_type_constraint.sql` | ✅ | constraint relaxed |
| `20260729000000_add_store_auto_schedule.sql` | ✅ | `open_time` / auto-schedule |
| `20260729110000_add_gcash_manual_verification.sql` | ✅ | `orders.gcash_reference_number` |
| `20260730000000_add_paymongo_gcash_columns.sql` | ✅ | `gcash_transaction_id` etc. |
| `20260730100000_add_foot_measurements.sql` | ✅ | `foot_measurements` + policies |
| `20260802000000_allow_sellers_create_conversations.sql` | ✅ | `seller_insert_conversations` |
| `20260802030000_fix_notify_on_new_message_jsonb_slice.sql` | ✅ | trigger fixed |
| `20260804000000_add_product_sale_fields.sql` | ✅ | `sale_price` / sale window |
| `20260805000000_add_delete_own_messages_policy.sql` | ✅ | message delete policies |
| `20260805000001_allow_customers_delete_cancelled_orders.sql` | ✅ | orders delete-cancelled policy |
| `20260806000000_add_static_gcash_qr.sql` | ✅ | `stores.gcash_qr_url` |
| `20260807000000_add_store_rating_aggregation.sql` | ✅ | `refresh_store_rating` |
| `20260808000000_add_store_reviews.sql` | ✅ | `store_reviews` + policies |
| `20260808120000_add_online_gcash_payments.sql` | ✅ | `payment_intents` + policies |
| `20260808200000_add_direct_gcash_online_checkout.sql` | ✅ | proof-submission policies |
| `20260808210000_add_direct_gcash_rpcs.sql` | ✅ | GCash RPC functions |
| `20260808230000_add_customer_cancel_pending_gcash.sql` | ✅ | cancel RPCs |
| `20260809000000_revive_paymongo_online_gcash.sql` | ✅ | fee config + PayMongo columns |
| `20260809120000_fix_profiles_rls_recursion.sql` | ✅ | `is_admin`/`is_seller_or_admin` (SECURITY DEFINER) |
| `20260810000000_admin_transactions_view.sql` | ✅ | admin payment-intent policies |
| `20260812000000_add_seller_tiered_verification.sql` | ✅ | `seller_business_docs` + profile columns |
| `20260812130000_add_customer_profile_fields.sql` | ✅ | `birthday`/`gender`/foot fields |
| `20260813000000_admin_suspension_enforcement.sql` | ✅ | **Applied Aug 12, 2026** — `suspended_reason`/`suspended_at`, `is_suspended()`, guard triggers. (Patched to skip legacy `product_reviews`) |
| `20260816000000_add_seller_id_type.sql` | ✅ | **Applied Aug 16, 2026** — `profiles.id_type` (gov ID selection) |
| `20260816120000_add_seller_store_photos.sql` | ✅ | **Applied Aug 16, 2026** — `store_front_url` + `product_photo_urls`. ⚠️ Was **partially applied** (only `store_front_url` landed; `product_photo_urls` was missing → seller submissions failed with "We could not save your application"). Fixed by re-running the `ALTER TABLE ... ADD COLUMN IF NOT EXISTS product_photo_urls TEXT[]` on Aug 16 |
| `20260816150000_add_seller_approval_notification.sql` | ✅ | **Applied Aug 16, 2026** — `notification_category` enum + `'approval'` value, `notify_on_seller_approved()` + `trg_notify_on_seller_approved` trigger |
| `20260817120000_admin_delete_user.sql` | ✅ | **Applied Aug 17, 2026** — `admin_delete_user(uuid)` SECURITY DEFINER RPC (admin-only permanent account delete, FK-safe) |
| `20260817130000_add_stores_description.sql` | ⏳ | **Ready Aug 17, 2026** — `stores.description`. Fixes PGRST204 "Could not find the 'description' column of 'stores'" on store create/edit. Run in SQL editor, then mark ✅ |
| `20260817140000_add_seller_application_v2_fields.sql` | ⏳ | **Ready Aug 17, 2026** — `profiles.store_location`/`store_lat`/`store_lng`/`store_tags` + `stores.tags` (application v2: personal details, required business docs, location, store tags). Run in SQL editor, then mark ✅ |

## Deploying a new migration

1. Create `supabase/migrations/<timestamp>_<name>.sql`.
2. Open the file → copy the contents → **Supabase Dashboard → SQL Editor → New query → Run**.
3. Add a row to the table above (mark ✅ after it succeeds).

> ⚠️ **Do not run `supabase db push`.** Because the remote tracking table is out of
> sync, it would try to re-apply ~50 already-applied migrations. If you ever want to
> repair the tracking instead, use `supabase migration repair --status applied <version>`
> (repeat per migration) — do this only after confirming the schema object already exists.

## Quick self-check after any deploy

```sql
-- Example: confirm the suspension columns landed
SELECT column_name FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'profiles'
  AND column_name IN ('suspended', 'suspended_reason', 'suspended_at');
```

If you see a new "column/relation does not exist" error, search this table for the
migration that adds it — it either wasn't applied or (rare) was intentionally skipped.
