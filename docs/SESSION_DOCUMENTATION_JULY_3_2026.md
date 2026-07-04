# SoleVision — Session Documentation: Checkout / "Complete Order" Investigation

**Date:** July 3, 2026
**Purpose:** Full record of a debugging session that traced and resolved the "Complete Order fails / no longer available" bug family in the SoleVision checkout flow. Written for another AI (or engineer) to pick up context quickly without re-doing the investigation.
**Companion files:** This session produced five incremental fix specs (`FIX_complete_order_stock_mismatch.md`, `_v2.md`, `FIX_checkout_validation_stock_source_v3.md`, `FIX_ar_fitting_variant_id_v4.md`, `FIX_false_error_and_cart_clear_v5.md`). This document is the narrative summary tying them together — read this first, then reference the specific spec file for implementation detail on whichever piece you're working on.

---

## 1. Starting Point

The session began from a prior handoff (`SESSION_LOG_JULY_2_3_2026.md`), which documented a checkout flow overhaul completed July 2–3 and left one known critical bug open:

> "Complete Order" fails for `demo_2` with *"demo_2 (size EU40) is no longer available"* despite the seller dashboard showing 100+ units in stock.

The prior session's working theory was a size-format mismatch between `inventory` (bare numbers like `"40"`) and `product_variants`/cart data (prefixed strings like `"EU40"`). That theory turned out to be correct for **one** of two distinct bugs found today — but the investigation uncovered a second, unrelated bug hiding behind the same symptom, and then a third finding that reframed the whole problem. All three are documented below in the order they were found.

---

## 2. Investigation Method

Rather than editing code blind, this session worked by:
1. Reading the actual live database schema (`schema.sql`) and comparing it against what the app code claimed to do.
2. Pulling live data from Supabase via targeted SQL queries at each step, rather than assuming table contents.
3. Getting the actual current source of the relevant functions (`createOrder()`, `_addToCart()` in two different screens, the DB trigger itself) rather than relying on the prior session log's description of what those functions were supposed to do.
4. Tracing one specific real failing case (a product called "Classic Derby Oxford," later also referenced by its seed name `demo_2`) end-to-end through every layer — cart → validation → order creation → DB trigger — until the exact break point was found.

This mattered because the prior session log's own fixes (July 3 entries) were *assumed* to be working; this session found that some of them didn't fully resolve the problem, and that there was a completely separate bug the prior session never touched.

---

## 3. Finding #1 — DB Trigger Exact-Match Bug (Confirmed, Fixed, Deployed)

### What we found
Two Postgres trigger functions, `decrement_inventory_on_order` (fires on `order_items` insert) and `decrement_inventory_on_sale` (fires on `sales_transaction_items` insert, the POS/in-store equivalent), both did a plain string equality check:

```sql
where product_id = new.product_id
  and size = new.size          -- exact match only
  and stock >= new.quantity;
```

Live data confirmed `inventory.size` always stores bare numbers (`"38"`, `"40"`, `"41"`), while other parts of the system (`product_variants`, cart display) can use prefixed sizes (`"EU40"`). Any exact-match comparison between the two formats fails, and the trigger raises `P0001: Insufficient stock`, which the app was mostly (but not universally) translating into a customer-facing message.

### What we did
Rewrote both trigger functions in the live database to normalize both sides of the comparison by stripping non-digit characters before comparing:

```sql
CREATE OR REPLACE FUNCTION public.decrement_inventory_on_order()
RETURNS trigger AS $$
begin
  update public.inventory
  set stock = stock - new.quantity
  where product_id = new.product_id
    and regexp_replace(size, '\D', '', 'g') = regexp_replace(new.size, '\D', '', 'g')
    and stock >= new.quantity;

  if not found then
    raise exception 'Insufficient stock for product % size %',
      new.product_id, new.size;
  end if;

  return new;
end;
$$ LANGUAGE plpgsql;
```
(Identical change applied to `decrement_inventory_on_sale`.)

### Status
✅ **Deployed and confirmed running** (`CREATE OR REPLACE FUNCTION` executed successfully in the live DB). This closes the specific failure mode described in the original session log for size-format mismatches at the trigger level.

### Still open from this finding
- Not yet verified: whether any product in the catalog uses non-numeric sizes (`"S"`, `"M"`, `"One Size"`) that would break under digit-stripping normalization. Verification query provided in the fix specs, not yet run.
- Not yet verified: whether `order_items`/`sales_transaction_items` rows written before this fix left any inventory in a bad state that needs backfilling.

Full detail: `FIX_complete_order_stock_mismatch.md` (v1, original investigation) and `_v2.md` (confirms deployment, lays out remaining verification steps).

---

## 4. Finding #2 — Checkout Blocked by Validation, Not by the Trigger (Root-Caused, Not Yet Fixed in Code)

### Why we kept digging after Finding #1
After the trigger fix, checkout was tested again on a real product ("Classic Derby Oxford," product id `aaaaaaaa-0001-0001-0001-000000000001`, size 41) and **still failed** with the same-looking "no longer available" message. This ruled out Finding #1 as the sole cause and prompted a full trace of the actual data flow instead of further guessing.

### What we found, step by step
1. Confirmed `aaaaaaaa-0001-0001-0001-000000000001` really is Classic Derby Oxford (only one product with that name).
2. Confirmed `inventory` for this product is completely healthy — size `"41"` has `stock = 46`, correct format, no mismatch at all. This ruled out Finding #1 as relevant to this specific case.
3. Confirmed `order_items` had **zero rows** for this product — meaning `createOrder()` was never even called. The block was happening *before* order submission, not at the DB trigger.
4. Traced backward to the `orders` table (since `createOrder()` creates the order row before inserting line items) and then to `cart_items` for the specific cart row involved.
5. Found the cart row had **`variant_id = NULL`**.
6. Reviewed the actual code (`createOrder_function_reference.md`, `addToCart_and_fetchCart_reference.md`) and confirmed: when `variant_id` is null, `fetchCart()` falls back to picking the **first size found** in `inventory` for that product (no `ORDER BY`, effectively arbitrary) rather than the size the customer actually selected. `validateCartForCheckout()` then validates stock for whatever size got arbitrarily substituted — which may not be the size the UI displays or the size with real stock.
7. Separately confirmed a second, related bug: `validateCartForCheckout()`'s normal (non-null-variant) path reads stock from `product_variants.stock`, not from `inventory.stock` — meaning even a correctly-linked cart item could be blocked if `product_variants.stock` is stale or zero while real stock lives in `inventory`.

### Fix identified (not yet implemented in code as of this writing)
`validateCartForCheckout()` needs to treat `inventory` as the authoritative stock source — the same source `createOrder()` already correctly uses — rather than trusting `product_variants.stock`, and rather than silently substituting an arbitrary fallback size when `variant_id` is null.

### Status
🟡 **Root cause identified and documented; code fix not yet written.** This finding also motivated Finding #3 below, which traces *why* `variant_id` was null in the first place.

Full detail: `FIX_checkout_validation_stock_source_v3.md`.

---

## 5. Finding #3 — The Actual Source of the Null `variant_id`: a Second, Incomplete "Add to Cart" Implementation

### Why we kept digging after Finding #2
Finding #2 explained *what* breaks when `variant_id` is null, but not *why* it was null for a product that has perfectly good `product_variants` data. We queried `product_variants` directly for this product and confirmed it has a clean row for size 41 (12 units, Tan; 11 units, Black) — so the null wasn't caused by missing data. That ruled out one of the two hypotheses from Finding #2 and left only one explanation: the code path that adds items to this cart never attempted the variant lookup in the first place.

### What we found
There are **two separate "Add to Cart" implementations** in the app:
- `lib/screens/customer/product_detail_screen.dart` — the normal product page. Its `_addToCart()` correctly loops through `product_variants` to resolve `variantId` by matching size + color before adding to cart.
- `lib/screens/customer/ar_fitting_screen.dart` — the AR "try it on" screen. Its `_addToCart()` **never performs this lookup at all** — it calls `cart.addToCart(...)` without a `variantId`, unconditionally, for every item added through this screen.

This was confirmed by pulling the actual current source of `ar_fitting_screen.dart`'s `_addToCart()` and comparing it side-by-side with the working version in `product_detail_screen.dart`.

### Fix identified (not yet implemented in code as of this writing)
Add the same variant-lookup loop to `ar_fitting_screen.dart`'s `_addToCart()`, mirroring `product_detail_screen.dart`. Also flagged as worth doing in the same pass: extracting this duplicated logic into one shared helper function so a third screen can't reintroduce the same gap later.

### Secondary finding (data hygiene, not related to this bug's cause)
While querying `product_variants` for this product, noticed the 10 real size/color combinations are each represented by **two** rows (20 total rows, all with matching stock values per duplicate pair) — likely a seeding or product-edit duplication issue. Flagged for separate follow-up; did not affect this bug since both duplicate rows agree on stock.

### Status
🟡 **Root cause fully confirmed, exact code diff written, not yet applied.**

Full detail: `FIX_ar_fitting_variant_id_v4.md`.

---

## 6. Finding #4 — The Symptom Was Reframed: the Order Actually Succeeds

### What changed
After Finding #3 was documented, new information came in directly from the user: checking the seller/admin portal showed that the order for the affected product **was actually present and correct** — meaning the order had, in fact, gone through successfully on the backend, despite the checkout screen displaying a "no longer available" failure banner.

### What this means
This reframes the entire remaining problem. It is **not** (or at least not only) a case of checkout being genuinely blocked — it's a **false-positive UI/state bug**: the order succeeds, but the customer-facing screen still shows an error as if it failed. Two most likely explanations, not yet distinguished:
- Something re-validates cart/stock *after* a successful order and incorrectly flags it, or
- The ordered item is never removed from the cart after a successful order, so it gets re-validated later (e.g. on returning to the cart) using stale or now-decremented numbers, and throws the same-looking banner again.

### New, narrower scope agreed with the user
Two concrete, explicit asks going forward:
1. Stop the false "no longer available" banner from appearing for orders that actually succeed.
2. After a successful "Complete Order," automatically remove that item from the cart (it's now a placed order awaiting seller processing, not a cart item).

**Explicitly out of scope for now** (per direct user instruction): anything about seller-side order processing, fulfillment status, or notifying the seller — that will be handled separately later.

### Status
🟡 **Scoped and speced; requires pulling the actual current `_submitCheckout()` code (not yet in hand) before writing the fix.** This is the immediate next piece of work.

Full detail: `FIX_false_error_and_cart_clear_v5.md`.

---

## 7. Overall Status Summary

| # | Finding | Root cause confirmed? | Fix written? | Deployed/Applied? |
|---|---|---|---|---|
| 1 | DB trigger exact-match on size | ✅ Yes | ✅ Yes | ✅ **Yes — live in production DB** |
| 2 | `validateCartForCheckout()` trusts wrong stock source | ✅ Yes | ✅ Yes (spec'd) | ❌ Not yet applied |
| 3 | AR Fitting screen missing variant lookup | ✅ Yes | ✅ Yes (exact diff provided) | ❌ Not yet applied |
| 4 | False "unavailable" banner after successful order + cart not cleared | 🟡 Scoped, not fully isolated between two hypotheses yet | 🟡 Partial — cart-removal fix is clear; banner-suppression fix depends on pulling `_submitCheckout()` code | ❌ Not yet applied |

---

## 8. Recommended Order of Work From Here

1. **Pull the actual current `_submitCheckout()` code** in `checkout_screen.dart` — this is the single missing piece blocking Finding #4 from being fully diagnosed and fixed. Everything else has enough detail to implement directly.
2. **Implement Finding #3's fix** (AR fitting variant lookup) — small, well-isolated, exact code provided, low risk.
3. **Implement Finding #2's fix** (`validateCartForCheckout()` reading from `inventory`) — also well-scoped, and will likely eliminate a whole class of future false negatives regardless of which "add to cart" path was used.
4. **Implement Finding #4's cart-clearing fix**, then re-test whether the false banner disappears on its own as a side effect before writing any additional banner-specific logic.
5. Re-run the full regression/test checklist from `FIX_ar_fitting_variant_id_v4.md` Section 4 and `FIX_false_error_and_cart_clear_v5.md` Section 5 together, since fixes 2–4 all touch overlapping parts of the checkout flow and should be verified as a set, not just individually.
6. Circle back (separately, lower priority) to the two data-hygiene items noted along the way: duplicate `product_variants` rows, and confirming no non-numeric sizes exist that would break the trigger's normalization from Finding #1.

---

## 9. Reference Index

| File | Contents |
|---|---|
| `SESSION_LOG_JULY_2_3_2026.md` | Prior session's own log — starting context for this session, includes the originally-reported bug |
| `schema.sql` | Live-ish DB schema, used to understand table relationships (`inventory`, `product_variants`, `cart_items`, `order_items`, etc.) — note: found to be slightly out of date vs. live DB in at least one place (`product_variants.product_id` type) |
| `createOrder_function_reference.md` | Full annotated source of `createOrder()`, confirmed correct/working size-resolution logic |
| `addToCart_and_fetchCart_reference.md` | Full annotated source of the *normal* `_addToCart()` (product detail screen) and `fetchCart()`'s inventory fallback logic |
| `ar_fitting_addToCart_reference.md` | Full annotated source of the *broken* `_addToCart()` (AR fitting screen) — this is where Finding #3's bug lives |
| `FIX_complete_order_stock_mismatch.md` | v1 — original trigger investigation |
| `FIX_complete_order_stock_mismatch_v2.md` | v2 — confirms trigger fix deployed, lays out remaining verification |
| `FIX_checkout_validation_stock_source_v3.md` | v3 — Finding #2 in full detail |
| `FIX_ar_fitting_variant_id_v4.md` | v4 — Finding #3 in full detail, exact fix code included |
| `FIX_false_error_and_cart_clear_v5.md` | v5 — Finding #4 in full detail, current active scope |

---

*This document is a narrative summary of a single investigation session. It intentionally repeats key facts already present in the individual fix specs so it can be read standalone, but implementation detail (exact code diffs, full SQL, full test checklists) lives in the linked spec files above — refer to those when actually writing code.*
