# Audit — notification and email recipients (NULL / missing)

**Date:** September 16, 2026
**Trigger:** "audit every place a notification or email is sent from SQL for a NULL
or missing recipient, since one bad row can abort a whole batch."
**Scope:** every SQL write into `public.notifications` / `public.seller_notifications`
(40 sites across 13 migration files), plus every edge function that sends an email
or a push. **Result: 8 sites were vulnerable — one of them reproduced as a
total batch failure. All 8 are fixed, and two new guards make the next one fail a
test instead of production.**

---

## 1. The rule, and why a NULL recipient is not a "skipped notification"

`public.notifications` is declared:

```sql
user_id  UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE
```

So a recipient that resolves to NULL is **`23502`, nothing more and nothing
less** — and in Postgres a failed statement is not a skipped row, it is a
rolled-back transaction. Where the insert sits inside a loop, the rollback takes
every row the loop had already processed with it.

This is not a hypothesis. The GCash expiry sweep was reproduced end to end with a
batch of two overdue orders, the second of which has no customer:

```
── calling the sweep ──
ERROR:  null value in column "user_id" of relation "notifications"
        violates not-null constraint
DETAIL: Failing row contains (d5c3113c-…, null, d0000000-0000-0000-0000-000000000002,
        returns, Payment window expired, …)
CONTEXT: SQL statement "INSERT INTO public.notifications (user_id, order_id, …)…"
PL/pgSQL function cancel_awaiting_gcash_order(…) line 51 at SQL statement
PL/pgSQL function expire_overdue_gcash_orders() line 11 at IF

── after the sweep ──
 d0000000-…-0001 | awaiting_payment_confirmation | no_customer = f   ← HEALTHY order
 d0000000-…-0002 | awaiting_payment_confirmation | no_customer = t   ← the bad row
 notifications written: 0
```

**Both** orders are still awaiting confirmation — including the healthy one the
sweep had already cancelled before it reached the bad row, whose work was rolled
back. While such a row exists the sweep resolves **nothing at all, on every run**,
and every order in the batch keeps its stock reserved. With the guard in place the
same batch reports `{"expired": 2}` and both orders are cancelled.

The failure mode to keep in mind, in one line: **a missing recipient is not a
skipped notification, it is a failed transaction.**

## 2. The two sinks

| Sink | Recipient column | Constraint |
|---|---|---|
| `public.notifications` | `user_id` | `NOT NULL REFERENCES profiles(id) ON DELETE CASCADE` |
| `public.seller_notifications` | `store_id` | `NOT NULL REFERENCES stores(id) ON DELETE CASCADE` |

`notifications` is keyed by **user**, `seller_notifications` by **store**. Both
are `NOT NULL`, so both have the same failure shape.

## 3. Which columns can be NULL (the list that matters)

Queried against the live schema, not assumed — every column that is ever used as
a recipient:

```sql
select table_name||'.'||column_name from information_schema.columns
 where table_schema='public'
   and column_name in ('customer_id','owner_id','seller_id','user_id')
   and is_nullable='YES' order by 1;
```

```
cart_items.user_id            customization_requests.customer_id
gcash_payment_decision_audit.seller_id    orders.customer_id
orders.store_id               products.seller_id
sales_transactions.seller_id  stores.owner_id
```

Of these, exactly **three** are used as a notification recipient:
`orders.customer_id`, `orders.store_id` and `stores.owner_id`. The other five are
never a recipient (checked by reading every site), so they are not this audit's
problem — though `products.seller_id` being nullable is worth its own look, since
it is the legacy twin of `stores.owner_id`.

Columns that are **NOT NULL** and therefore safe as recipients:
`bulk_reservations.customer_id`, `pickup_reservations.customer_id`,
`conversations.customer_id`, `profiles.id`.

## 4. The inventory — all 40 sites

| Recipient source | Sites | Verdict |
|---|---|---|
| `v_reservation.customer_id` (bulk) — `bulk_reservations.customer_id` is NOT NULL | 12 | ✅ safe by construction |
| `v_row.customer_id` (pickup expire + reminders) | 3 | ✅ safe by construction |
| `conv.customer_id` — `conversations.customer_id` is NOT NULL | 3 (one live revision) | ✅ safe by construction |
| `new.id` on `profiles` (`notify_on_seller_approved`) | 1 | ✅ PK of the row being updated |
| `SELECT s.owner_id … AND s.owner_id IS NOT NULL` (pickup) | 3 | ✅ already guarded |
| `IF v_store_owner IS NOT NULL THEN` (bulk) | 3 | ✅ already guarded |
| `IF v_owner IS NOT NULL` / `IF v_row.owner_id IS NOT NULL` then `v_owners[v_at]` (pickup) | 2 | ✅ already guarded |
| `v_row.customer_id` (store goodwill grant) | 1 | ✅ NOT NULL column |
| `submit_gcash_proof` → `seller_notifications` with `v_store_id` | 1 | ❌ **fixed** |
| `SELECT s.owner_id` with **no** owner filter — `request_bulk_reservation` | 2 (live + superseded copy) | ❌ **fixed** |
| `v_customer_id` from `orders.customer_id`, unguarded — `cancel_awaiting_gcash_order` | 2 (live + superseded copy) | ❌ **fixed** (batch abort, reproduced) |
| `v_customer_id`, unguarded — `confirm_gcash_payment` | 2 (live + superseded copy) | ❌ **fixed** |
| `new.customer_id`, unguarded — the two order triggers | 2 | ❌ **fixed** |
| `SELECT o.customer_id` unguarded — the pg_cron expiry body | 1 | ❌ **fixed** |
| `CASE … ELSE v_owner_id` unguarded — `cancel_pickup_reservation` | 1 | ❌ **fixed** |

Every "superseded copy" is a file that a later migration overrides. They were
fixed too, on purpose: these files are hand-applied and re-runnable, so a repair
re-apply of the older file would otherwise silently reintroduce the bug.

## 5. The eight holes, and what each would have done

1. **`expire_overdue_gcash_orders()` → `cancel_awaiting_gcash_order()`** — the
   `IF p_notify_customer THEN` guard tests the *caller's intent*, not the
   recipient. One customer-less order aborts the loop and rolls back the healthy
   orders' cancellations (§1). **The most severe finding: permanent, silent,
   batch-wide.**
2. **`confirm_gcash_payment()`** — runs in one transaction with the state change
   and the T5 audit row, so a customer-less order rolled the seller's
   confirmation back: a payment that was really made could not be confirmed.
3. **`notify_on_order_insert()`** — fires `AFTER INSERT`, so a raise rejects the
   **order itself**. An order without a customer could not be created.
4. **`notify_on_order_status_change()`** — fires `AFTER UPDATE OF status`, so a
   seller could not move such an order's status.
5. **`request_bulk_reservation()`** — the seller notice is a row-select on
   `stores.owner_id`; unguarded, an ownerless store failed the **customer's**
   request outright (same transaction as the reservation row).
6. **`submit_gcash_proof()`** — `seller_notifications` is keyed by a nullable
   `orders.store_id`; unguarded, a proof submission failed, i.e. the customer
   could not submit the payment they had already made.
7. **`cancel_pickup_reservation()`** — the recipient is a `CASE`, and the `ELSE`
   branch is the store owner. On an ownerless store the CUSTOMER could not cancel
   their own hold. (This one was introduced by the pickup work and missed because
   the other four sites in that file were guarded — the shape was different.)
8. **The `cron.schedule()` expiry body** in `20260809000000` — a set-based
   `SELECT o.customer_id` insert; unguarded it rolls back the intent-expiry and
   audit work above it. See §7: this path cannot be tested.

All eight are now guarded, and each guard names the reason at the site.

**One adjacent fix, required to deploy the above.** The two bulk-reservation
files were not actually re-runnable: 7 `CREATE POLICY` statements had no
`DROP POLICY IF EXISTS`, so a second apply died at the first of them — *before*
reaching the functions further down. That meant the fix in #5 could never be
applied by re-running the file, the documented procedure. Those 7 policies are now
dropped first, like the storage policies in the same file already were, and both
files apply twice cleanly.

## 6. Emails and pushes — what actually sends them

**No SQL sends email.** Verified: no `pg_net`, `net.http_post`, SMTP, or
mail-provider reference exists in any migration. Emails come from three places,
and each resolves its recipient in code:

| Path | Recipient resolved from | Verdict |
|---|---|---|
| `send-approval-email` | server-side lookup of `profiles.email` by `payload.userId`; `404` when the profile or its email is missing | ✅ a clean, explicit failure |
| `send-lockout-email` | **the caller's request body** (`400` if absent) | ✅ no NULL hazard — but see below |
| Supabase Auth (signup confirmation, OTP, magic link, reset) | `auth.users.email` — always present | ✅ |
| `sendPushToUser` (shared by both push functions) | `device_tokens` rows for the user; no user id or no tokens → `{0,0}` and a log line | ✅ gracefully does nothing |
| `request-account-deletion` | admins read from `profiles where role='admin'`; `admin.id` is a PK | ✅ |
| `gcash-webhook` (2 in-app inserts) | `order.customer_id` — one is inside a `try/catch` that logs it non-fatal, the other has an explicit `if (!order.customer_id) return;` | ✅ already handled |

The push path deserves the credit it gets here: "no tokens" and "no user id" are
both explicit early returns, so a user who has never installed the app is a
no-op rather than an error. That is the shape every notification site should have.

**Not a recipient bug, but found next to it and already on record:**
`send-approval-email` and `send-lockout-email` are deployed with
`verify_jwt = false` and **take the recipient and the message from the caller's
body**, so an anonymous caller can trigger a real "your account has been locked"
email to any address. This is exactly the "no internal authorization — an
anonymous caller can invoke them with forged bodies" note already in
`supabase/config.toml`; this audit adds only the recipient half of the picture,
and does not change it. That belongs to a security task, not this one.

## 7. The one path no test can reach

The guard in `20260809000000` is inside a **string handed to
`cron.schedule('expire-online-gcash-payments', …, $cron$ … $cron$)`** — not a
function. Nothing can call it: not pgTAP, not the app, not pg_cron here (the
extension is not installed in this project, so the job was never even scheduled).

Two consequences, both worth knowing:

- its correctness can only be established **by reading it**, which is why the
  source-level guard in §8 exists;
- it **duplicates** logic that also lives in `cancel_my_pending_payment_intent`
  (a callable function, and the tested path). Two copies of an expiry rule that
  must agree, one of which is invisible to tests, is a drift seam. Extracting the
  body into a function that the cron job then *calls* would make it testable and
  remove the copy. Not done here — it changes a payment path — but it is the
  single highest-value follow-up from this audit.

## 8. The two guards

**Behavioural — `supabase/tests/notification_recipients.test.sql` (27 assertions).**
Every case is a pair: a NULL recipient must not raise, **and** a real recipient
must still be notified. The pair is the evidence — the tolerant half alone would
pass if a guard simply switched the notification off (proved: three
"over-aggressive" mutations that always skip are caught by the positive
assertions). The headline case is §1's batch, asserted as three separate claims:
the sweep does not raise, it reports both orders expired, and both are
`cancelled`.

**Structural — `test/services/notification_recipient_contract_test.dart` (7
tests).** Scans every notification insert in the migrations and ratchets the
known hazardous shapes: a `SELECT <alias>.owner_id` / `.customer_id` recipient
must filter on `IS NOT NULL` in the same statement; the order triggers must check
`new.customer_id`; a `VALUES` insert whose recipient is a local variable must have
a guard **naming that variable** in the enclosing function; and the cron body must
keep its guard, since no behavioural test can reach it. A floor assertion keeps
the scanner itself honest.

The first version of this file was wrong in an instructive way, and the mutation
pass is what caught it: it searched raw text, and the **comment** explaining the
rule (`` `owner_id IS NOT NULL` everywhere a store is notified ``) satisfied the
search for the rule — deleting the real `AND s.owner_id IS NOT NULL` still passed.
A guard that reads comments reports success while the code is broken. Comments are
stripped before matching now.

**Mutation-tested, both guards.** Fifteen mutations, one per rule, each reverted
in isolation and restored from the file between runs:

| Guard reverted | Caught by |
|---|---|
| sweep's customer guard | pgTAP 1 (the sweep raises) |
| `confirm_gcash_payment` recipient guard | pgTAP 7 |
| order INSERT trigger guard | pgTAP 11 |
| order STATUS trigger guard | pgTAP 12 |
| `request_bulk_reservation` owner guard | pgTAP 18 |
| `cancel_pickup_reservation` CASE guard | pgTAP 23 |
| insert trigger notifies nobody *(over-aggressive)* | pgTAP 15, 17 |
| bulk owner notice always skipped *(over-aggressive)* | pgTAP 21 |
| pickup cancel never notifies *(over-aggressive)* | pgTAP 27 |
| bulk request owner guard | contract test (store-owner rule) |
| pickup request owner guard | contract test (store-owner rule) |
| paymongo cron customer guard | contract test (order-customer rule) |
| order insert trigger guard | contract test (`new.customer_id`) |
| `confirm_gcash_payment` recipient guard | contract test (variable rule) |
| cron body's recipient guard | contract test (untestable-path rule) |

## 9. What was NOT changed, and the residual risk

- **The columns are still nullable.** `orders.customer_id`, `orders.store_id` and
  `stores.owner_id` still permit NULL. A `NOT NULL` would remove the whole class
  structurally — and is the *right* long-term fix — but it is a data-affecting
  change to live tables with writers this audit did not enumerate (POS, the
  dashboard, imports). Guards in the notifying code fail safe today; promoting
  them to constraints should be its own change, with a backfill check first.
- **`auth.uid()`-derived recipients rely on the FK, not on a check.** A valid
  session whose profile row is gone would make those inserts fail — but every such
  site writes a row keyed by that same FK first, so it fails there with a clearer
  error. Left as is; noted so it is not mistaken for an oversight.
- **Two paths can only be read, not run:** the cron body (§7), and the
  `sync`-time guard inside a function only reachable through pg_cron.
- **Live data check.** All the states these guards defend against are currently
  **zero** in the live project: 0 orders without a customer, 0 orders without a
  store, 0 stores without an owner, 0 notifications whose profile is missing. The
  holes found here are latent, not incidents — but nothing enforced that.

**The standing rule for new code:** when a notification's recipient comes from a
column rather than from `auth.uid()` or a PK, check it — and prefer the shape
`INSERT … SELECT … WHERE recipient IS NOT NULL`, which sends nothing rather than
failing, over an `IF` that has to be remembered at the call site.
