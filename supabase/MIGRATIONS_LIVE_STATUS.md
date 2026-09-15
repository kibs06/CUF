# Live Database Migration Status

**Project:** `psczvbfoybqhjeqssimw` (Supabase)
**Last verified:** September 3, 2026 (T3 hardening migrations applied via SQL Editor + verified live via PostgREST probes)
**Source of truth:** this table — **not** `supabase migration list`, whose remote
tracking table is out of sync (old records use pre-rename filenames, so the CLI
shows ~50 migrations as "pending" even though they are applied).

**pgTAP suite — verified locally, September 15, 2026:** `supabase db reset`
(91 migrations, from scratch) then `supabase test db` → **`Result: PASS`**,
7 files / 229 tests (`vouchers` 37, `trusted_devices` 30,
`trusted_device_enforcement` 43, `admin_account_security` 31,
RLS recursion canary 7, `bulk_reservation_deposits` 51,
manual-GCash dedupe 30). Flutter side: `flutter analyze` clean,
`flutter test` 750 PASS. The *rows below* track
the **live** project, which is a separate question from whether the migrations
apply and pass on a clean database — the local stack is green, the live
database still needs the pending ones applied.

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
| `20260817130000_add_stores_description.sql` | ✅ | **Applied Aug 17, 2026** — `stores.description`. Fixes PGRST204 "Could not find the 'description' column of 'stores'" on store create/edit. Verified live: `stores.description` select → HTTP 200 |
| `20260817140000_add_seller_application_v2_fields.sql` | ✅ | **Applied Aug 17, 2026** — `profiles.store_location`/`store_lat`/`store_lng`/`store_tags` + `stores.tags` (application v2: personal details, required business docs, location, store tags). Verified live: `stores.tags`/`profiles.store_tags`/`profiles.store_lat` selects → HTTP 200 |
| `20260817150000_add_store_auto_schedule_cron.sql` | ⏳ **Not yet applied** | Schedules the `apply-store-schedules` pg_cron job (every 5 min) so `stores.is_open` auto-flips per `open_time`/`close_time`. Fixes stores stuck showing "Open Now" after their posted close time. Apply via Dashboard → SQL Editor |
| `20260903000000_lock_seller_application_after_submit.sql` | ✅ | **Applied Sep 3, 2026** — T3: extends `guard_profiles_sensitive_columns` so applicants cannot edit application-content columns (store details, verification-doc URLs, `rejection_reason`) once `seller_status` is `pending`/`approved`; `rejected`/`none` stay editable (re-apply/draft). Verified live: content PATCH on pending row → 400; on `none`/`rejected` → 204 |
| `20260903010000_add_seller_application_audit_log.sql` | ✅ | **Applied Sep 3, 2026** — T3: `seller_application_audit_log` table + `AFTER UPDATE OF seller_status` trigger (only writer; SECURITY DEFINER). RLS admin-SELECT-only; direct INSERT/UPDATE/DELETE revoked from every role incl. service_role. Verified live: admin approve/reject wrote rows with correct actor + notes; direct INSERT blocked (403) for admin & non-admin |
| `20260903020000_audit_initial_application_submission.sql` | ✅ | **Applied Sep 3, 2026** — T3 follow-up: `AFTER INSERT` trigger logs the initial `submitted` event (project has no signup trigger creating profiles, so first-time submissions take the INSERT branch and the UPDATE trigger never saw them). Verified live: fresh submit wrote `submitted` row with applicant as actor |
| `20260905000000_fix_t5_manual_gcash_dedupe_audit.sql` | ⏳ **Not yet applied** | **T5 (2026-09-05)** — POS GCash reference dedupe (partial unique index `uq_orders_gcash_reference_number_paid` on paid orders, pre-cleaning existing duplicate refs to NULL); new admin-only `gcash_payment_decision_audit` table (RLS `is_admin()` SELECT-only, all write grants revoked incl. service_role); POS confirm audit trigger `trg_log_pos_gcash_confirm_audit`; confirm/reject RPCs now append audit rows (source='queue'); `create_gcash_checkout` EXECUTE revoked from authenticated (closes the remote route into the manual flow). Companion pgTAP suite: `supabase/tests/t5_manual_gcash_dedupe_audit.test.sql` (runs in CI's supabase-migrations job). Apply via SQL Editor. |
| `20260907000000_fix_stale_pending_gcash_intents.sql` | ⏳ **Not yet applied** | **Incident 2026-09-07** — one-time global cleanup for the "Checkout cancelled on every GCash order" bug: expires all `payment_intents` stuck `status='pending'` past `expires_at` (pg_cron is NOT installed on this DB, so the sweep from 20260809000000 never ran; a stale Aug-19 test-mode intent bricked checkout for customer 3ee96df2-… via the `uq_payment_intents_one_pending_per_customer` index); cancels orders still `awaiting_payment` behind expired intents (no stock held — defer-until-paid); appends `exp-…` audit rows to `payment_webhook_events` (NOT EXISTS-guarded, idempotent); RAISEs a WARNING when pg_cron is absent. Companion code fix: per-customer mini-sweep in `create-gcash-payment-intent` (deploy the function alongside). Idempotent — safe to re-run. Apply via SQL Editor or `supabase db push`. |
| `20260913110000_add_reservations_notification_category.sql` | ⏳ **Not yet applied** | Bulk Reservations step 1 — `notification_category` enum gains `'reservations'` (own migration because `ALTER TYPE ... ADD VALUE` cannot be USED in the same transaction that adds it). **Apply BEFORE `20260913120000` and `20260913140000`** (their RPCs insert 'reservations' notifications). Idempotent — safe to re-run. Apply via SQL Editor. |
| `20260913120000_add_bulk_reservations.sql` | ⏳ **Not yet applied** | Bulk Reservations (reseller holds) base feature — `bulk_reservations` table + RLS + `request`/`decide`/`cancel`/`fulfill`/`expire` RPCs + `reserved_stock_for_product` helper. Requires `20260913110000` first. Idempotent — safe to re-run. Apply via SQL Editor. See `docs/AI/BULK_RESERVATION_ARCHITECTURE.md`. |
| `20260913130000_add_bulk_reservation_awaiting_deposit_status.sql` | ⏳ **Not yet applied** | Bulk Reservation Deposits step 1 — `bulk_reservation_status` enum gains `'awaiting_deposit'` (own migration, same ALTER TYPE constraint). **Apply AFTER `20260913120000`, BEFORE `20260913140000`.** Idempotent — safe to re-run. Apply via SQL Editor. |
| `20260913140000_add_bulk_reservation_deposits.sql` | ⏳ **Not yet applied** | **Bulk Reservation Deposits (deposit gate)** — inserts `pending → awaiting_deposit → approved(reserved) → fulfilled` between seller approval and the stock draw: `deposit_amount` (resolved 20% of estimated value, ceil to whole peso) / `deposit_status` / `deposit_deadline` (24h) / `deposit_paid_at` / `deposit_proof_id` columns; `bulk_reservation_deposits` proofs table (platform-unique 12–13 digit GCash ref, screenshot in the private `payment-proofs` bucket under `{reservation_id}/…`, + 4 storage policies); RPCs: approve now only opens the deposit window (NO stock moves), new `submit_bulk_reservation_deposit_proof` (customer), `confirm_bulk_reservation_deposit` (seller — THIS draws stock, relocated verbatim from the old approve branch), `reject_bulk_reservation_deposit` (seller), cancel/fulfill/sweep extended (`awaiting_deposit` expiry releases nothing; `approved` expiry forfeits the paid deposit). No new UPDATE policies — all writes via SECURITY DEFINER RPCs. Requires `20260913130000` first. Idempotent — safe to re-run. Apply via SQL Editor. |

| `20260915120000_add_vouchers.sql` | ⏳ **Not yet applied** | **Vouchers step 1 (ANQUI item #5)** — `vouchers` + `voucher_redemptions` tables (case-insensitive codes, store scope vs platform-wide, fixed/percent + peso cap, min order, max uses, per-user limit, window, `funded_by`), RLS (customers have **no** read access — codes are only readable through the preview RPC), `orders.subtotal_amount`/`discount_amount`/`voucher_code`/`voucher_id`, the money-term freeze guard, and the shared pricing helpers `product_effective_price` (mirrors `lib/utils/sale_price.dart`) + `checkout_cart_summary`. Idempotent — safe to re-run. Apply via SQL Editor. |
| `20260915140000_add_trusted_devices.sql` | ⏳ **Not yet applied** | **Email OTP step-up (ANQUI item #16)** — `trusted_devices` (per `(user_id, device_id)` pair, so one phone with two accounts stays two independent trusts) + RLS (read/revoke own rows, admin read, **no INSERT/UPDATE policy at all**) + the `SECURITY DEFINER` `trust_device(p_device_id, p_device_label)` RPC, which is the only write path and takes the user from `auth.uid()` so a client can never trust a device for another account. Re-trusting refreshes `last_seen_at` and preserves `first_seen_at`/`trusted_at`/`device_label`. pgTAP suite: `supabase/tests/trusted_devices.test.sql`. Idempotent — safe to re-run. Apply via SQL Editor. ⚠️ The feature ALSO needs two dashboard toggles (Confirm email ON; `{{ .Token }}` added to the Confirm-signup and Magic-link templates) — see `docs/AI/EMAIL_OTP_AND_DEVICE_TRUST_ARCHITECTURE.md` §5.1. |
| `20260915150000_enforce_trusted_devices.sql` | ⏳ **Not yet applied** | **Email OTP step-up, SERVER-SIDE ENFORCEMENT (ANQUI item #16)** — makes the step-up unskippable by a hand-crafted client. `device_secrets` (SHA-256 of a 32-byte secret per `(user_id, device_id)`, composite FK to `trusted_devices` **ON DELETE CASCADE** so revoking a device destroys its credential; RLS on with **no policies and no grants** — invisible to every client role) + `device_enforcement_policy` (single-row rollout switch) + `device_is_trusted()` (reads `x-cufmai-device` out of `request.headers`, hashes and compares) + `session_proves_possession()` (the mint gate: `amr` otp/magiclink or `aal2`) + `device_gate_open()` (read-only probe so the app can tell "empty" from "gated") + `set_device_enforcement(boolean)` (admin-only flip) + **RESTRICTIVE `Require a trusted device` policies (`USING` + `WITH CHECK`) on the private tables** (26 when it runs standalone; every later migration that adds an RLS table calls the re-runnable `install_device_gate_policies()` and pushes the count up — `20260915170000` takes it to 27) — `orders`, `order_items`, `cart_items`, `customer_addresses`, `messages`, `conversations`, `notifications`, `payment_intents`, `gcash_payment_proofs`, `vouchers`, `voucher_redemptions`, `sales_transactions`, `reports`, `seller_business_docs`, … (`profiles`, `trusted_devices`, `failed_logins` and the public catalogue are exempt on purpose — gating them would lock users out or add friction with no protection). `trust_device()` is rewritten to require a stepped-up session and to return a freshly minted secret (so a stolen password cannot mint one), and rotates on re-trust. Requires `20260915140000` first. Idempotent — safe to re-run. pgTAP suite: `supabase/tests/trusted_device_enforcement.test.sql` (44 assertions — it asserts the named high-value tables are still gated plus a floor on the total, rather than an exact count that every new gated table used to break). **⚠️ Enforcement ships OFF** (`enforcement_enabled = false`) so applying this cannot break the installed client, which sends no device header. After the updating build is in users' hands, run `select public.set_device_enforcement(true);` — that single row is the whole rollout (and the rollback: set it back to `false`). See `docs/AI/EMAIL_OTP_AND_DEVICE_TRUST_ARCHITECTURE.md` Part C. Apply via SQL Editor. |
| `20260915160000_add_admin_account_security.sql` | ⏳ **Not yet applied** | **Email OTP step-up, ADMIN DIAGNOSTICS (ANQUI item #16 support tooling)** — `admin_account_security_overview(p_user_id uuid) → jsonb`, the admin-side answer to "I got a new phone and I can't get in". Returns the account (email confirmation, role), **every trusted device with whether it still holds a credential** (`has_secret` — a device listed as trusted while the gate refuses it is the state this exists to expose), GoTrue's own event timeline, password lockouts, and the enforcement switch — plus a `cannot_answer` block stating what it CANNOT know (a wrong code leaves no trace server-side, and a refused device is never recorded), so an empty timeline cannot be misread as "nobody tried". `SECURITY DEFINER`, gate-kept by `is_admin()` (42501 otherwise), granted to `authenticated` only (`anon` has no EXECUTE, so accounts cannot be enumerated without a session); takes the subject as an ARGUMENT because an admin investigating someone else's account is the point; reads `device_secrets` (which has no grants) but selects only the mint time, **never the hash**. The timeline matches all three identification shapes GoTrue uses — `user_recovery_requested` carries the user in `actor_id`, while `user_signedup` puts the SERVICE ROLE there and the user in `traits.user_id` — because an `actor_id`-only filter silently drops every signup. Also exposes `device_gate_exempt_tables()` (hoisted out of the sweep so the installer, the pgTAP guard and the Dart contract test read ONE list) and makes the sweep re-runnable. Requires `20260915150000` first. Idempotent — safe to re-run. pgTAP suite: `supabase/tests/admin_account_security.test.sql` (31 assertions). UI: Manage Users → ⋮ → Account Security. See `docs/AI/EMAIL_OTP_AND_DEVICE_TRUST_ARCHITECTURE.md` Part D. Apply via SQL Editor. |
| `20260915170000_add_pickup_reservations.sql` | ⏳ **Not yet applied** | **Pickup reservations (ANQUI item #14) — free 24 h holds, extendable once (48 h max)** — a **separate, simpler system from the deposit-gated bulk flow** (they share only `inventory.stock` and the `reservations` notification category). `pickup_reservations` (customer/store/product/`size`/`quantity`/`reserved_stock`/`status`/`pickup_deadline` + exactly-once audit stamps + `fulfilled_order_id` + `reminder_sent_at`), statuses `active → fulfilled/cancelled/expired`; `pickup_reservation_max_quantity()` = **2** (one number, pinned to the Dart constant by a contract test); `pickup_reservation_hold_hours()` = 24, `pickup_reservation_max_extensions()` = 1 and `pickup_reservation_extension_hours()` = 24, again one number each — so a hold runs at most **48 h from reservation**, and that ceiling is a **table CHECK** (`pickup_reservations_within_max_window`, plus `pickup_reservations_within_extension_cap` on the count), not merely a branch inside the RPC; `extend_pickup_reservation(p_reservation_id)` (+24 h, returns the new deadline) is **customer-only**, refused once the deadline has passed (`HOLD_LAPSED`) and beyond the cap (`EXTENSION_LIMIT_REACHED`), moves no stock, charges nothing, clears `reminder_sent_at` so the NEW deadline gets its own T-2 h warning, and notifies both sides; RLS **SELECT-only** for customer/store-owner/admin (no write policies — every row represents stock already taken, so the RPCs are the only write path); RPCs `request_pickup_reservation` (cap + `stock >= quantity` compare-and-set hold, deadline +24 h), `cancel_pickup_reservation` (customer **or** seller), `fulfill_pickup_reservation` (seller — writes a real **POS order**: `source='pos'`, `status='received'`, `payment_status='paid'`, inventory **not** touched again because the hold IS the draw), `expire_pickup_reservations()` (opportunistic sweep, no pg_cron here) and `send_pickup_reservation_reminders()` (T-2 h, exactly-once via `reminder_sent_at`; the customer is reminded **per hold**, while the **store owner gets ONE aggregated summary per run** — "2 pickup holds expire in the next 2 hours — 2 pairs return to stock" — with a NULL-owner guard so an ownerless store cannot abort the whole sweep). Cancel and the sweep share one release core that re-reads the row `FOR UPDATE` and no-ops if the status moved on, so a concurrent cancel/sweep can never double-release; the sweep uses `FOR UPDATE SKIP LOCKED`. A fulfilled pickup **counts toward `units_sold`** (it is the same paid POS order `fetchUnitsSold()` already sums — Best Sellers included); bulk reservations still do not. A partial unique index `(customer_id, product_id, size) WHERE status = 'active'` makes a duplicate hold impossible rather than merely unlikely — the RPC's own duplicate check is serial, so two simultaneous submits would both pass it (the stock compare-and-set stops them overselling, which is what would have hidden it). Ends by calling `install_device_gate_policies()`: `pickup_reservations` is customer-private and is therefore device-gated like `orders`. Idempotent — safe to re-run. pgTAP suite: `supabase/tests/pickup_reservations.test.sql` (128 assertions). See `docs/AI/PICKUP_RESERVATION_ARCHITECTURE.md`. Apply via SQL Editor. |
| `20260915130000_add_voucher_enforcement.sql` | ⏳ **Not yet applied** | **Vouchers step 2** — `voucher_evaluate` (the single validation/discount source of truth, `FOR UPDATE`-capable so use caps cannot be raced), the customer preview RPC `validate_voucher`, the **orders BEFORE INSERT trigger** that reprices and overwrites the totals from the server (forged client totals are impossible), the AFTER INSERT redemption trigger (`uses_count` + `voucher_redemptions`, same transaction), and `deactivate_voucher`. Requires `20260915120000` first. pgTAP suite: `supabase/tests/vouchers.test.sql`. Idempotent — safe to re-run. Apply via SQL Editor. |

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
