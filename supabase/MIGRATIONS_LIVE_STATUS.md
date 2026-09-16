# Live Database Migration Status

**Project:** `psczvbfoybqhjeqssimw` (Supabase)
**Last verified:** September 17, 2026 — every row re-checked against the live
project with `supabase db query --linked` (the read-only Management-API query
path the SQL Editor uses — **not** `supabase db push`, see the warning below).

**✅ 2026-09-17 — the three pickup migrations are APPLIED (verified live by object, not by trust).** `pickup_reservations` has **18 columns**; `pickup_code` and `store_extension_count` are both present; `pickup_reservations_pickup_code_check`, `pickup_reservations_within_store_extension_cap` and the unique index `uq_pickup_reservations_pickup_code` are present; `pickup_reservation_extension_grants` exists; and all nine new functions exist (`pickup_code_alphabet`, `pickup_code_length`, `generate_pickup_code`, `assign_pickup_code`, `normalize_pickup_code`, `find_pickup_reservation_by_code`, `fulfill_pickup_reservation_by_code`, `grant_pickup_extension`, `pickup_reservation_max_store_extensions`). So `20260915170000` is at its 18-column / 72 h revision — the re-apply called for below is DONE.

**⚠️ 2026-09-17 — amended-file re-apply: 7 of 8 verified live, ONE still behind.** Asserted against `pg_proc.prosrc`: `notify_on_order_status_change` (null guard) ✅, `notify_on_order_insert` (pending guard) ✅, **`cancel_my_pending_payment_intent` ❌**, `cancel_pickup_reservation` (`v_recipient IS NOT NULL`) ✅, the T5 confirm (`Guarded on the RECIPIENT`) ✅, both bulk files (`s.owner_id IS NOT NULL`, ×4) ✅, and their policies ✅. **The exception is `20260809000000_revive_paymongo_online_gcash.sql`** — its `WHERE o.customer_id IS NOT NULL` guard is NOT in the live `cancel_my_pending_payment_intent`, so one customer-less order still rolls the whole set back with 23502, taking the intent-expiry and its audit row with it. Apply that one file.

**🔧 2026-09-17 — CLI migration-history repair.** The remote `supabase_migrations.schema_migrations` table had stopped at `20260907000000`, leaving **69 versions untracked**, so `supabase db push` listed ~71 already-applied files as pending and began replaying them onto production. It aborted on `20260601000000_base_schema.sql` statement 6 (`CREATE POLICY` with no `IF NOT EXISTS`) — each file runs in ONE transaction, so it rolled back cleanly: **nothing was applied and no history row was written**. The 69 versions are now marked applied (`supabase migration repair --status applied`).

**⚠️ 2026-09-17 — do NOT follow the CLI's own `db push` repair advice.** `db push` now stops with *"Remote migration versions not found in local migrations directory"*, naming `20260714 20260715 20260721 20260723`, and suggests marking them `--status reverted`. **Do not run that.** Those four are exactly the dates where an 8-digit file shares a prefix with 14-digit siblings (`20260714_push_notifications.sql` beside `20260714000000_messaging_attachments_schema.sql`, and the same for 20260715 / 20260721 / 20260723), which defeats the CLI's version pairing. Reverting them would make `db push` try to APPLY those four files to production. The stopped push is the safe end state — it applies nothing. Keep hand-applying through the SQL Editor, which is what this table documents.

**ℹ️ 2026-09-17 — `20260817150000` is marked applied although it is outstanding.** `20260817150000_add_store_auto_schedule_cron.sql` is a guarded `DO $$ … IF EXISTS (pg_cron) … $$` block that degrades to a NOTICE, and `pg_cron` is still not installed (verified: extension count 0, no auto-schedule function live), so it did nothing. It is marked applied only so the history table stops replaying it. **Hand-run it when `pg_cron` is enabled** — until then `stores.is_open` never follows the posted schedule.
**All ⏳ rows up to `20260915170000` were stale: the ANQUI migrations had already
been applied.** They were verified by object, not by trust: `pickup_reservations`
with 16 columns and both window CHECKs, the duplicate-hold unique index, all four
extension functions, `vouchers`/`voucher_redemptions`, the `orders` voucher
triggers (`trg_orders_apply_voucher`, `trg_orders_record_voucher_redemption`),
`trusted_devices`/`device_secrets`/`device_enforcement_policy`, and the
`'reservations'` enum value. Only two things remain outstanding: the pg_cron
migration (blocked — the extension is not installed) and the device-gate switch,
which is deliberately left `false` (`enforcement_enabled = false`) until the
1.0.26 build is in testers' hands.

**✅ 2026-09-17: resolved — all three of these files are applied; see the 2026-09-17 block above.**

**⚠️ 2026-09-16 (counter code): `20260915170000` gains a THIRD thing the live
revision lacks — `pickup_code` (plus its CHECK and unique index) — and a new
migration, `20260916140000_add_pickup_codes.sql`, depends on it. The order to
apply is: the base file AGAIN → the store grant → the counter code.** All three
are re-runnable (verified by re-applying each over the existing tables), and the
counter-code file adds no table of its own, so it does not move the device-gate
count. Nothing calls the new RPCs until a build ships the seller's **Collect by
code** action and the customer's code band, so this stays additive.

**✅ 2026-09-17: resolved — live `pickup_reservations` is at the 18-column revision (see the 2026-09-17 block above).**

**⚠️ 2026-09-16 (later the same day): the store-grant work makes ONE of those
"applied" rows a REVISION behind.** The live `pickup_reservations` is at the
16-column revision — no `store_extension_count`, no `pickup_code`, and
`pickup_reservation_max_store_extensions()` does not exist — while the base file
in the repo now declares 18 columns and a 72 h ceiling. So
`20260915170000` must be **re-applied** (it converges: 18 × `ADD COLUMN IF NOT
EXISTS`, then the widened ceiling CHECK) **before** `20260916120000`, whose RPC
spends that column and that budget. Re-applying the base file is otherwise safe:
the only existing rows are live holds with ≤48 h deadlines, which satisfy the
widened CHECK.
**⚠️ 2026-09-17: 7 of the 8 are verified live; `20260809000000_revive_paymongo_online_gcash.sql` is still behind — see the 2026-09-17 block above.**

**⚠️ 2026-09-16 (notification-recipient audit): EIGHT already-applied files were
amended, and each must be RE-APPLIED to reach the live database.** They gained a
recipient guard against a NULL notification recipient — see
`docs/AI/NOTIFICATION_RECIPIENT_AUDIT.md`. None of them changes a schema or an
API; each is a one-to-three-line guard inside a function or trigger body, and all
eight were verified to apply cleanly a second time:

```
20260702_notifications.sql                          (both order triggers)
20260808210000_add_direct_gcash_rpcs.sql            (cancel + confirm + proof notice)
20260808230000_add_customer_cancel_pending_gcash.sql (the LIVE cancel — the batch bug)
20260809000000_revive_paymongo_online_gcash.sql     (cron body)
20260905000000_fix_t5_manual_gcash_dedupe_audit.sql (the LIVE confirm)
20260913120000_add_bulk_reservations.sql            (request notice + 4 policies made re-runnable)
20260913140000_add_bulk_reservation_deposits.sql    (request notice + 3 policies made re-runnable)
20260915170000_add_pickup_reservations.sql          (cancel recipient resolved first)
```

Ordering does not matter among them, **except** that `20260808230000` and
`20260905000000` must come *after* the older files they supersede (the order they
are listed in above). Apply them in the same hand-apply way as everything else —
**not** `db push`. The two bulk files previously failed a second apply on a
`CREATE POLICY` with no `DROP POLICY IF EXISTS`; that is fixed, and it was the
reason the fix inside them could not otherwise be deployed.

**Source of truth:** this table — **not** `supabase migration list`, whose remote
tracking table is out of sync (old records use pre-rename filenames, so the CLI
shows ~50 migrations as "pending" even though they are applied).

**pgTAP suite — verified locally, September 16, 2026:** `supabase db reset`
(93 migrations, from scratch) then `supabase test db` → **`Result: PASS`**,
10 files / 445 tests (`pickup_reservations` 129, `store_pickup_extensions` 59,
`bulk_reservation_deposits` 51, `trusted_device_enforcement` 44, `vouchers` 37,
`admin_account_security` 31, `trusted_devices` 30, manual-GCash dedupe 30,
`notification_recipients` 27, RLS recursion canary 7).
Flutter side: `flutter analyze` clean,
`flutter test` 890 PASS. The *rows below* track
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
| `20260817150000_add_store_auto_schedule_cron.sql` | ⏳ **Still not applied — blocked** (verified Sep 16, 2026; **marked applied in the CLI history on Sep 17 so it stops replaying — see the ℹ️ note at the top, and hand-run it when `pg_cron` is enabled**) | Schedules the `apply-store-schedules` pg_cron job (every 5 min) so `stores.is_open` auto-flips per `open_time`/`close_time`. Fixes stores stuck showing "Open Now" after their posted close time. Apply via Dashboard → SQL Editor |
| `20260903000000_lock_seller_application_after_submit.sql` | ✅ | **Applied Sep 3, 2026** — T3: extends `guard_profiles_sensitive_columns` so applicants cannot edit application-content columns (store details, verification-doc URLs, `rejection_reason`) once `seller_status` is `pending`/`approved`; `rejected`/`none` stay editable (re-apply/draft). Verified live: content PATCH on pending row → 400; on `none`/`rejected` → 204 |
| `20260903010000_add_seller_application_audit_log.sql` | ✅ | **Applied Sep 3, 2026** — T3: `seller_application_audit_log` table + `AFTER UPDATE OF seller_status` trigger (only writer; SECURITY DEFINER). RLS admin-SELECT-only; direct INSERT/UPDATE/DELETE revoked from every role incl. service_role. Verified live: admin approve/reject wrote rows with correct actor + notes; direct INSERT blocked (403) for admin & non-admin |
| `20260903020000_audit_initial_application_submission.sql` | ✅ | **Applied Sep 3, 2026** — T3 follow-up: `AFTER INSERT` trigger logs the initial `submitted` event (project has no signup trigger creating profiles, so first-time submissions take the INSERT branch and the UPDATE trigger never saw them). Verified live: fresh submit wrote `submitted` row with applicant as actor |
| `20260905000000_fix_t5_manual_gcash_dedupe_audit.sql` | ✅ **Applied** (verified live Sep 16) | **T5 (2026-09-05)** — POS GCash reference dedupe (partial unique index `uq_orders_gcash_reference_number_paid` on paid orders, pre-cleaning existing duplicate refs to NULL); new admin-only `gcash_payment_decision_audit` table (RLS `is_admin()` SELECT-only, all write grants revoked incl. service_role); POS confirm audit trigger `trg_log_pos_gcash_confirm_audit`; confirm/reject RPCs now append audit rows (source='queue'); `create_gcash_checkout` EXECUTE revoked from authenticated (closes the remote route into the manual flow). Companion pgTAP suite: `supabase/tests/t5_manual_gcash_dedupe_audit.test.sql` (runs in CI's supabase-migrations job). Apply via SQL Editor. |
| `20260907000000_fix_stale_pending_gcash_intents.sql` | ✅ **Effectively applied** (verified live Sep 16) | **Incident 2026-09-07** — one-time global cleanup for the "Checkout cancelled on every GCash order" bug: expires all `payment_intents` stuck `status='pending'` past `expires_at` (pg_cron is NOT installed on this DB, so the sweep from 20260809000000 never ran; a stale Aug-19 test-mode intent bricked checkout for customer 3ee96df2-… via the `uq_payment_intents_one_pending_per_customer` index); cancels orders still `awaiting_payment` behind expired intents (no stock held — defer-until-paid); appends `exp-…` audit rows to `payment_webhook_events` (NOT EXISTS-guarded, idempotent); RAISEs a WARNING when pg_cron is absent. Companion code fix: per-customer mini-sweep in `create-gcash-payment-intent` (deploy the function alongside). Idempotent — safe to re-run. Apply via SQL Editor or `supabase db push`. |
| `20260916140000_add_pickup_codes.sql` | ✅ **Applied** (verified live Sep 17, 2026, by object) | **Pickup counter code (ANQUI item #14 follow-up)** — the customer shows a short code, the seller types it and the hold is collected in one action. The COLUMN (`pickup_code`, nullable), its UNIQUE index and its CHECK live in `20260915170000` §3/§3b (a re-apply has to converge an existing table); this file owns everything else: `pickup_code_alphabet()` = `23456789ABCDEFGHJKMNPQRSTVWXYZ` (30 symbols — **no I, L, O, U, 0 or 1**, because a code is read off a screen across a counter and often spoken aloud), `pickup_code_length()` = 6, `generate_pickup_code()` (loops until free rather than letting a collision surface as a failed *customer* request; randomness from `gen_random_uuid()` hashed, not the session-seeded `random()`), `assign_pickup_code()` (BEFORE INSERT trigger, so EVERY insert path gets one and the format is decided in exactly one place), `normalize_pickup_code()` (upper-cases and strips separators, and **deliberately does no look-alike substitution** so a mistyped code cannot normalise into somebody else's hold), `find_pickup_reservation_by_code(p_code)` (resolves **only** for a store the caller owns — scoped by joining `stores.owner_id = auth.uid()`, so a seller cannot enumerate another store's holds; another store's code gets the SAME `NOT_FOUND` as a code that does not exist, so the error cannot be probed for real ones; a resolved hold still resolves, because a dispute — "this is the pair the customer showed me" — is exactly when a seller needs the trail) and `fulfill_pickup_reservation_by_code(p_code, p_payment_method)` (**resolve + collect in ONE call**, delegating to `fulfill_pickup_reservation` so the ownership check, the `ALREADY_RESOLVED` guard, the POS order and the single stock draw all stay in one place). Adds **no table**, so the device-gate count is unchanged. **⚠️ Apply `20260915170000` again FIRST** — without the re-apply the table has no `pickup_code` column, its CHECK or its unique index, and every code path fails. Additive otherwise: nothing calls these RPCs until the build that ships the seller's *Collect by code* action and the customer's code band. pgTAP suite: `supabase/tests/pickup_codes.test.sql` (45 assertions). Every rule here was **mutation-tested** (8 SQL + 8 Dart mutations, each failing a named assertion); the one first-pass survivor — a by-code fulfil that resolved the code and collected nothing, which a bare `lives_ok` could not tell from the real thing — is why assertion 37 now checks the returned id against `orders`. See `docs/AI/PICKUP_RESERVATION_ARCHITECTURE.md` §5. Apply via SQL Editor. |
| `20260913110000_add_reservations_notification_category.sql` | ✅ **Applied** | Bulk Reservations step 1 — `notification_category` enum gains `'reservations'` (own migration because `ALTER TYPE ... ADD VALUE` cannot be USED in the same transaction that adds it). **Apply BEFORE `20260913120000` and `20260913140000`** (their RPCs insert 'reservations' notifications). Idempotent — safe to re-run. Apply via SQL Editor. |
| `20260913120000_add_bulk_reservations.sql` | ✅ **Applied** | Bulk Reservations (reseller holds) base feature — `bulk_reservations` table + RLS + `request`/`decide`/`cancel`/`fulfill`/`expire` RPCs + `reserved_stock_for_product` helper. Requires `20260913110000` first. Idempotent — safe to re-run. Apply via SQL Editor. See `docs/AI/BULK_RESERVATION_ARCHITECTURE.md`. |
| `20260913130000_add_bulk_reservation_awaiting_deposit_status.sql` | ✅ **Applied** | Bulk Reservation Deposits step 1 — `bulk_reservation_status` enum gains `'awaiting_deposit'` (own migration, same ALTER TYPE constraint). **Apply AFTER `20260913120000`, BEFORE `20260913140000`.** Idempotent — safe to re-run. Apply via SQL Editor. |
| `20260913140000_add_bulk_reservation_deposits.sql` | ✅ **Applied** | **Bulk Reservation Deposits (deposit gate)** — inserts `pending → awaiting_deposit → approved(reserved) → fulfilled` between seller approval and the stock draw: `deposit_amount` (resolved 20% of estimated value, ceil to whole peso) / `deposit_status` / `deposit_deadline` (24h) / `deposit_paid_at` / `deposit_proof_id` columns; `bulk_reservation_deposits` proofs table (platform-unique 12–13 digit GCash ref, screenshot in the private `payment-proofs` bucket under `{reservation_id}/…`, + 4 storage policies); RPCs: approve now only opens the deposit window (NO stock moves), new `submit_bulk_reservation_deposit_proof` (customer), `confirm_bulk_reservation_deposit` (seller — THIS draws stock, relocated verbatim from the old approve branch), `reject_bulk_reservation_deposit` (seller), cancel/fulfill/sweep extended (`awaiting_deposit` expiry releases nothing; `approved` expiry forfeits the paid deposit). No new UPDATE policies — all writes via SECURITY DEFINER RPCs. Requires `20260913130000` first. Idempotent — safe to re-run. Apply via SQL Editor. |

| `20260915120000_add_vouchers.sql` | ✅ **Applied** | **Vouchers step 1 (ANQUI item #5)** — `vouchers` + `voucher_redemptions` tables (case-insensitive codes, store scope vs platform-wide, fixed/percent + peso cap, min order, max uses, per-user limit, window, `funded_by`), RLS (customers have **no** read access — codes are only readable through the preview RPC), `orders.subtotal_amount`/`discount_amount`/`voucher_code`/`voucher_id`, the money-term freeze guard, and the shared pricing helpers `product_effective_price` (mirrors `lib/utils/sale_price.dart`) + `checkout_cart_summary`. Idempotent — safe to re-run. Apply via SQL Editor. |
| `20260915140000_add_trusted_devices.sql` | ✅ **Applied** | **Email OTP step-up (ANQUI item #16)** — `trusted_devices` (per `(user_id, device_id)` pair, so one phone with two accounts stays two independent trusts) + RLS (read/revoke own rows, admin read, **no INSERT/UPDATE policy at all**) + the `SECURITY DEFINER` `trust_device(p_device_id, p_device_label)` RPC, which is the only write path and takes the user from `auth.uid()` so a client can never trust a device for another account. Re-trusting refreshes `last_seen_at` and preserves `first_seen_at`/`trusted_at`/`device_label`. pgTAP suite: `supabase/tests/trusted_devices.test.sql`. Idempotent — safe to re-run. Apply via SQL Editor. ⚠️ The feature ALSO needs two dashboard toggles (Confirm email ON; `{{ .Token }}` added to the Confirm-signup and Magic-link templates) — see `docs/AI/EMAIL_OTP_AND_DEVICE_TRUST_ARCHITECTURE.md` §5.1. |
| `20260915150000_enforce_trusted_devices.sql` | ✅ **Applied** (enforcement OFF) | **Email OTP step-up, SERVER-SIDE ENFORCEMENT (ANQUI item #16)** — makes the step-up unskippable by a hand-crafted client. `device_secrets` (SHA-256 of a 32-byte secret per `(user_id, device_id)`, composite FK to `trusted_devices` **ON DELETE CASCADE** so revoking a device destroys its credential; RLS on with **no policies and no grants** — invisible to every client role) + `device_enforcement_policy` (single-row rollout switch) + `device_is_trusted()` (reads `x-cufmai-device` out of `request.headers`, hashes and compares) + `session_proves_possession()` (the mint gate: `amr` otp/magiclink or `aal2`) + `device_gate_open()` (read-only probe so the app can tell "empty" from "gated") + `set_device_enforcement(boolean)` (admin-only flip) + **RESTRICTIVE `Require a trusted device` policies (`USING` + `WITH CHECK`) on the private tables** (26 when it runs standalone; every later migration that adds an RLS table calls the re-runnable `install_device_gate_policies()` and pushes the count up — `20260915170000` took it to 27, and the **live project reports 29** as of Sep 16, 2026, because the sweep is re-runnable and covers tables added after it first ran. That drift is precisely why the pgTAP guard asserts the named high-value tables plus a *floor* on the total rather than an exact count.) — `orders`, `order_items`, `cart_items`, `customer_addresses`, `messages`, `conversations`, `notifications`, `payment_intents`, `gcash_payment_proofs`, `vouchers`, `voucher_redemptions`, `sales_transactions`, `reports`, `seller_business_docs`, … (`profiles`, `trusted_devices`, `failed_logins` and the public catalogue are exempt on purpose — gating them would lock users out or add friction with no protection). `trust_device()` is rewritten to require a stepped-up session and to return a freshly minted secret (so a stolen password cannot mint one), and rotates on re-trust. Requires `20260915140000` first. Idempotent — safe to re-run. pgTAP suite: `supabase/tests/trusted_device_enforcement.test.sql` (44 assertions — it asserts the named high-value tables are still gated plus a floor on the total, rather than an exact count that every new gated table used to break). **⚠️ Enforcement ships OFF** (`enforcement_enabled = false`) so applying this cannot break the installed client, which sends no device header. After the updating build is in users' hands, run `select public.set_device_enforcement(true);` — that single row is the whole rollout (and the rollback: set it back to `false`). See `docs/AI/EMAIL_OTP_AND_DEVICE_TRUST_ARCHITECTURE.md` Part C. Apply via SQL Editor. |
| `20260915160000_add_admin_account_security.sql` | ✅ **Applied** | **Email OTP step-up, ADMIN DIAGNOSTICS (ANQUI item #16 support tooling)** — `admin_account_security_overview(p_user_id uuid) → jsonb`, the admin-side answer to "I got a new phone and I can't get in". Returns the account (email confirmation, role), **every trusted device with whether it still holds a credential** (`has_secret` — a device listed as trusted while the gate refuses it is the state this exists to expose), GoTrue's own event timeline, password lockouts, and the enforcement switch — plus a `cannot_answer` block stating what it CANNOT know (a wrong code leaves no trace server-side, and a refused device is never recorded), so an empty timeline cannot be misread as "nobody tried". `SECURITY DEFINER`, gate-kept by `is_admin()` (42501 otherwise), granted to `authenticated` only (`anon` has no EXECUTE, so accounts cannot be enumerated without a session); takes the subject as an ARGUMENT because an admin investigating someone else's account is the point; reads `device_secrets` (which has no grants) but selects only the mint time, **never the hash**. The timeline matches all three identification shapes GoTrue uses — `user_recovery_requested` carries the user in `actor_id`, while `user_signedup` puts the SERVICE ROLE there and the user in `traits.user_id` — because an `actor_id`-only filter silently drops every signup. Also exposes `device_gate_exempt_tables()` (hoisted out of the sweep so the installer, the pgTAP guard and the Dart contract test read ONE list) and makes the sweep re-runnable. Requires `20260915150000` first. Idempotent — safe to re-run. pgTAP suite: `supabase/tests/admin_account_security.test.sql` (31 assertions). UI: Manage Users → ⋮ → Account Security. See `docs/AI/EMAIL_OTP_AND_DEVICE_TRUST_ARCHITECTURE.md` Part D. Apply via SQL Editor. |
| `20260915170000_add_pickup_reservations.sql` | ✅ **Applied at the 18-column / 72 h revision** (verified live Sep 17, 2026 by object: `pickup_code` + `store_extension_count` present, both window CHECKs present) | **Pickup reservations (ANQUI item #14) — free 24 h holds, extendable once by the customer and once by the store (72 h max)** — a **separate, simpler system from the deposit-gated bulk flow** (they share only `inventory.stock` and the `reservations` notification category). `pickup_reservations` (customer/store/product/`size`/`quantity`/`reserved_stock`/`status`/`pickup_deadline` + exactly-once audit stamps + `fulfilled_order_id` + `reminder_sent_at`), statuses `active → fulfilled/cancelled/expired`; `pickup_reservation_max_quantity()` = **2** (one number, pinned to the Dart constant by a contract test); `pickup_reservation_hold_hours()` = 24, `pickup_reservation_max_extensions()` = 1, `pickup_reservation_extension_hours()` = 24 and — **added 2026-09-16** — `pickup_reservation_max_store_extensions()` = 1, `pickup_reservation_store_extension_hours()` = 24 and `pickup_reservation_max_window_hours()` (the SUM of every budget: 24 × 3), again one number each. There are therefore **two independent budgets**: the customer's own ask takes a hold to **48 h**, and a store's goodwill grant takes it to the **72 h absolute ceiling**, which is a **table CHECK** (`pickup_reservations_within_max_window`, reading the summed function, plus `pickup_reservations_within_extension_cap` bounding EACH counter against its own budget), not merely a branch inside the RPC; `store_extension_count` is the store's own counter, stored beside `extension_count` so neither can be confused for the other; `extend_pickup_reservation(p_reservation_id)` (+24 h, returns the new deadline) is **customer-only**, refused once the deadline has passed (`HOLD_LAPSED`) and beyond the cap (`EXTENSION_LIMIT_REACHED`), moves no stock, charges nothing, clears `reminder_sent_at` so the NEW deadline gets its own T-2 h warning, and notifies both sides; RLS **SELECT-only** for customer/store-owner/admin (no write policies — every row represents stock already taken, so the RPCs are the only write path); RPCs `request_pickup_reservation` (cap + `stock >= quantity` compare-and-set hold, deadline +24 h), `cancel_pickup_reservation` (customer **or** seller), `fulfill_pickup_reservation` (seller — writes a real **POS order**: `source='pos'`, `status='received'`, `payment_status='paid'`, inventory **not** touched again because the hold IS the draw), `expire_pickup_reservations()` (opportunistic sweep, no pg_cron here) and `send_pickup_reservation_reminders()` (T-2 h, exactly-once via `reminder_sent_at`; the customer is reminded **per hold**, while the **store owner gets ONE aggregated summary per run** — "2 pickup holds expire in the next 2 hours — 2 pairs return to stock" — with a NULL-owner guard so an ownerless store cannot abort the whole sweep). Cancel and the sweep share one release core that re-reads the row `FOR UPDATE` and no-ops if the status moved on, so a concurrent cancel/sweep can never double-release; the sweep uses `FOR UPDATE SKIP LOCKED`. A fulfilled pickup **counts toward `units_sold`** (it is the same paid POS order `fetchUnitsSold()` already sums — Best Sellers included); bulk reservations still do not. A partial unique index `(customer_id, product_id, size) WHERE status = 'active'` makes a duplicate hold impossible rather than merely unlikely — the RPC's own duplicate check is serial, so two simultaneous submits would both pass it (the stock compare-and-set stops them overselling, which is what would have hidden it). Ends by calling `install_device_gate_policies()`: `pickup_reservations` is customer-private and is therefore device-gated like `orders`. **§3b makes the file CONVERGE the table** (`ALTER TABLE … ADD COLUMN IF NOT EXISTS` for all 18 columns) instead of only no-op'ing on a database that already has it at this revision — a live re-apply without it died on `42703: column "extension_count" does not exist`, raised by a CHECK constraint whose own text is correct (2026-09-16; see §3b and the deploying rules below). pgTAP suite: `supabase/tests/pickup_reservations.test.sql` (129 assertions, one of which pins the 18-column shape). See `docs/AI/PICKUP_RESERVATION_ARCHITECTURE.md`. Apply via SQL Editor. |
| `20260916120000_add_store_pickup_extensions.sql` | ✅ **Applied** (verified live Sep 17, 2026, by object) | **Store goodwill extensions (ANQUI item #14 follow-up)** — lets a store be lenient without loosening the customer-only rule, as an explicit, auditable act. `grant_pickup_extension(p_reservation_id, p_reason)` (store owner **only**; **reason REQUIRED**, 3–280 chars after trimming; only while the hold is live; only once per hold; +24 h; returns the new deadline; moves no stock; charges nothing; clears `reminder_sent_at` so the granted deadline gets its own T-2 h warning; notifies the customer **with the reason**) and its trail table `pickup_reservation_extension_grants` (who granted, for which hold, `previous_deadline` → `new_deadline`, `hours_granted`, `reason` — with `granted_by ON DELETE SET NULL` so deleting a seller cannot delete the record that a favour happened, and a `CHECK (length(btrim(reason)) BETWEEN 3 AND 280)` so an unexplained grant cannot be inserted by any path). RLS **SELECT-only** (customer / store owner / admin) — the RPC is the only write path, so a client cannot fabricate a trail — and the file ends by calling `install_device_gate_policies()` (28 gated tables in a clean database). **⚠️ Apply `20260915170000` again FIRST** (see the note above): this RPC reads `store_extension_count` and `pickup_reservation_max_store_extensions()`, which the live database does not have yet. Additive otherwise — it can be applied without a new build, and nothing calls it until the build that ships the seller action. pgTAP suite: `supabase/tests/store_pickup_extensions.test.sql` (60 assertions — 60 was added 2026-09-16 when the customer's Goodwill history started embedding the hold through this table's `reservation_id` FK; the customer history itself needs **no migration**). Every rule here was **mutation-tested** (eleven mutations, one per rule); the first pass found two rules with no assertion at all — a lapsed hold and a resolved one — now assertions 56–59. See `docs/AI/PICKUP_RESERVATION_ARCHITECTURE.md` §5. Apply via SQL Editor. |
| `20260915130000_add_voucher_enforcement.sql` | ✅ **Applied** | **Vouchers step 2** — `voucher_evaluate` (the single validation/discount source of truth, `FOR UPDATE`-capable so use caps cannot be raced), the customer preview RPC `validate_voucher`, the **orders BEFORE INSERT trigger** that reprices and overwrites the totals from the server (forged client totals are impossible), the AFTER INSERT redemption trigger (`uses_count` + `voucher_redemptions`, same transaction), and `deactivate_voucher`. Requires `20260915120000` first. pgTAP suite: `supabase/tests/vouchers.test.sql`. Idempotent — safe to re-run. Apply via SQL Editor. |

## Deploying a new migration

1. Create `supabase/migrations/<timestamp>_<name>.sql`.
2. Open the file → copy the contents → **Supabase Dashboard → SQL Editor → New query → Run**.
3. Add a row to the table above (mark ✅ after it succeeds).
4. If it creates a table, prove the table actually has what the file says (see
   the self-check below). A statement that "succeeded" is not evidence that
   every column exists.

### ⚠️ A table is not re-created by re-running — it must CONVERGE

These files are applied by hand, so "idempotent — safe to re-run" has to mean
more than "does not error where it already ran at this revision".
`CREATE TABLE IF NOT EXISTS` is a **no-op** when the table already exists: it does
not reconcile the table with the definition in the file. A column that is declared
only inside that `CREATE TABLE` is therefore invisible on any database that
already holds the table — and the error that follows names a different statement.

That has now cost us twice:

- `20260816120000_add_seller_store_photos.sql` — `product_photo_urls` missing from
  a partially applied table → seller applications failed to save with "We could
  not save your application".
- `20260915170000_add_pickup_reservations.sql` — a live `pickup_reservations`
  predating the hold-extension work had no `extension_count`, so the re-apply died
  on `ERROR: 42703: column "extension_count" does not exist`, raised by a CHECK
  constraint whose own text is correct.

**The rule: after `CREATE TABLE IF NOT EXISTS`, list every column again as
`ALTER TABLE … ADD COLUMN IF NOT EXISTS`, before anything reads it** (§3b of
`20260915170000` is the pattern). `IF NOT EXISTS` makes each line a no-op on a
current table, so the cost is a handful of lines and the benefit is that
re-applying the file converges a table created by *any* earlier revision of
itself. The block then doubles as a readable column manifest — and its drift from
the `CREATE TABLE` is caught for you, by
`test/services/pickup_reservation_contract_test.dart` (same columns, and still
before the constraints that read them).

**…and the same is true of the CHECKs that arrive WITH those columns.** An inline
`CHECK` is created only alongside its column, so `ADD COLUMN IF NOT EXISTS` is a
no-op on a table that already has the column — a missing constraint stays missing,
and re-running silently reports success. Any CHECK that encodes a rule the app or
the tests depend on is therefore written **twice on purpose**: inline (for a table
created fresh) and again as an explicit `DROP CONSTRAINT IF EXISTS` +
`ADD CONSTRAINT`, so a re-apply converges the constraints too. Both pickup files
end their convergence block that way, naming every constraint on the two tables. If
you add a CHECK to a table that already ships, add its explicit `DROP`/`ADD` pair in
the same commit — otherwise the first partial apply is permanent.

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

```sql
-- After any table-creating migration: list what the table ACTUALLY has and
-- compare it against the file, line by line. A column missing here is the
-- 42703 waiting to happen on the next re-run.
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'pickup_reservations'
ORDER BY ordinal_position;
```

If you see a new "column/relation does not exist" error, search this table for the
migration that adds it — it either wasn't applied or (rare) was intentionally skipped.
