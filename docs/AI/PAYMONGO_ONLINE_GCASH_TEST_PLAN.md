# Online GCash (PayMongo) — Isolated Test Plan (attempt #6)

> Companion to `docs/AI/CHECKOUT_AND_GCASH_ARCHITECTURE.md` (attempt #6 section).
> This covers the **PayMongo Checkout Sessions** flow: order created in
> `awaiting_payment` (no stock touched) → customer authorizes in GCash via the
> hosted page → signature-verified webhook finalizes the order (order_items
> materialized → stock decremented by the existing trigger) → `pending`/paid.
> Model B GCash fee (surcharge to the customer, rate from `payment_fee_config`),
> 15-minute intent expiry, customer self-cancel RPC.
>
> Status: functions written + typechecked (deno check passes). **Not yet run
> against PayMongo sandbox — requires sandbox keys from the human.**

---

## 0. Pre-requisites (apply once)

```bash
supabase db push                      # applies …20260809000000_revive_paymongo_online_gcash.sql
supabase functions deploy create-gcash-payment-intent --no-verify-jwt  # JWT checked inside
supabase functions deploy get-payment-status --no-verify-jwt
supabase functions deploy gcash-webhook --no-verify-jwt                 # PUBLIC — signature-checked inside
```

Function env (sandbox):

```bash
PAYMONGO_SECRET_KEY=sk_test_…        # sandbox secret — NEVER in the app
PAYMONGO_WEBHOOK_SECRET=whsk_test_…  # from the PayMongo dashboard webhook config
SUPABASE_URL=…  SUPABASE_ANON_KEY=…  SUPABASE_SERVICE_ROLE_KEY=…   (set by Supabase by default)
PAYMONGO_SUCCESS_URL=solvision://checkout/gcash/success   # must match the app's registered deep link
PAYMONGO_CANCEL_URL=solvision://checkout/gcash/cancel
GCASH_PAYMENT_EXPIRY_MINUTES=15      # confirmed decision
PAYMONGO_LIVEMODE=false
```

PayMongo dashboard → Developers → Webhooks → add endpoint `…/functions/v1/gcash-webhook`
with events **`payment.paid`, `payment.failed`, `checkout_session.payment.paid`**
(and, if offered, `checkout_session.expired`). Copy the `whsk_…` webhook secret.

Verify objects landed:

```sql
SELECT * FROM public.payment_fee_config;                 -- seed row (223 bps / 1200 vat)
SELECT public.get_gcash_fee(250);                        -- fee_amount ≈ 6.41, total_charged ≈ 256.41
SELECT proname FROM pg_proc WHERE proname IN
  ('get_gcash_fee','set_payment_fee_config','cancel_my_pending_payment_intent');
SELECT jobname FROM cron.job WHERE jobname = 'expire-online-gcash-payments';
```

### Signing sample webhook payloads (for local tests)

```bash
PAYMONGO_WEBHOOK_SECRET=whsk_test_… FUNCTION_URL=https://<project>.functions.supabase.co/gcash-webhook
ts=$(date +%s)
body='{"data":{"id":"evt_test_123","type":"event","attributes":{"type":"payment.paid","livemode":false,"data":{"id":"pay_test_1","type":"payment","attributes":{"amount":25641,"payment_intent_id":"pi_test_1"}}}}}'
sig=$(printf '%s.%s' "$ts" "$body" | openssl dgst -sha256 -hmac "$PAYMONGO_WEBHOOK_SECRET" -hex | awk '{print $2}')
curl -sS -X POST "$FUNCTION_URL" -H "Content-Type: application/json" \
  -H "Paymongo-Signature: t=$ts,te=$sig" -d "$body"
```

AUTH_HEADER for the authenticated functions: `-H "Authorization: Bearer $SUPABASE_JWT"`.

---

## 1. `create-gcash-payment-intent` (isolated, sandbox keys)

| # | Case | Expect |
|---|---|---|
| 1.1 | No / bad JWT | `401 Unauthorized` |
| 1.2 | Seller (role != customer) | `403` — "Only customers can place online orders" |
| 1.3 | `idempotency_key` not a UUID | `400` |
| 1.4 | Empty / malformed items | `400` |
| 1.5 | Unknown product_id | `409` "no longer available" |
| 1.6 | Size out of stock | `409` "no longer available for …" |
| 1.7 | Items from two different stores | `409` "items from different stores" |
| 1.8 | **Happy path** | `200` with `{order_id, checkout_url, client_key, amount, fee_amount, expires_at}`; `orders` row `status='awaiting_payment'`, `payment_status='pending'`, `total_amount` = server-recomputed products+delivery, `gcash_fee_amount` = amount − total; **no `order_items` rows; stock unchanged**; `payment_intents` row `status='pending'`, `checkout_session_id` starts `cs_`, `expires_at` ≈ now+15 min |
| 1.9 | Client lies about prices (sends a fake total) | Total is server-recomputed; the fake number is ignored (verify against DB) |
| 1.10 | Double-tap same cart (same idempotency_key or same fingerprint) | `200` with `already_exists: true` and the SAME `checkout_url`/`order_id` — only ONE PayMongo session created |
| 1.11 | Pending intent for a DIFFERENT cart | `409` "unfinished checkout for a different cart" |
| 1.12 | Fee math parity | `get_gcash_fee(<server total>)` returns the same `fee_amount`/`total_charged` the intent stored |
| 1.13 | PayMongo down / bad secret key | `502` "Payment provider unavailable"; order cancelled + `payment_webhook_events` row `checkout_session.create_failed`; no stock touched |

## 2. `gcash-webhook` (isolated — do these before wiring the app)

| # | Case | Expect |
|---|---|---|
| 2.1 | **No signature header** | `401`; `payment_webhook_events` gets a `rejected_signature` row (`rej-…`) |
| 2.2 | **Forge/tamper**: sign body A, deliver body B (same timestamp) | `401`; rejection logged |
| 2.3 | **Wrong secret** | `401` |
| 2.4 | **Stale timestamp** (t > 10 min old) | `401` |
| 2.5 | Valid `payment.paid` for a created intent (signed as above) | Order → `pending`/`paid`; `order_items` materialized from `items_snapshot`; stock decremented exactly once; `gcash_transaction_id` = pay_xxx, `payment_verified_at` set; `payment_intents` → `succeeded`; `payment_webhook_events` → `processed`; seller + customer notifications inserted |
| 2.6 | **Replay the same event id** | `200 {duplicate:true}`; no second decrement, no duplicate notifications |
| 2.7 | Valid `checkout_session.payment.paid` (real event from PayMongo test checkout) | Same as 2.5 (cs_ lookup path; pi_ backfilled) |
| 2.8 | `payment.paid` where charged amount ≠ intent amount | `payment_conflict` + `payment_status='paid'` + amount-mismatch detail; NOT silently accepted |
| 2.9 | `payment.failed` for an awaiting order | Order `cancelled`/`failed`; intent `failed`; customer notified; no stock touched (none was held) |
| 2.10 | `payment.paid` for an order already cancelled/expired | `payment_conflict` + `paid` — late-payment flag for manual refund review |
| 2.11 | Unknown event type (e.g. `payment.refunded`) | `200`; `ignored_unknown` logged — never silently dropped |
| 2.12 | Intent that matches no order / unknown session | `200`; `ignored_unknown` logged |
| 2.13 | Webhook while sweep is running concurrently | Exactly one terminal state (state guards) — see §6 |

## 3. `get-payment-status` (isolated)

| # | Case | Expect |
|---|---|---|
| 3.1 | No JWT | `401` |
| 3.2 | Customer A queries customer B's order | `403` |
| 3.3 | Happy path (awaiting) | `{status:'awaiting_payment', paid:false, payment:{status:'pending', amount, fee_amount, expires_at, checkout_url}}` |
| 3.4 | After webhook | `{status:'pending', paid:true}` |

## 4. RLS / security checks

| # | Check | Expect |
|---|---|---|
| 4.1 | Customer A reads customer B's `payment_intents` | 0 rows (SELECT own-only) |
| 4.2 | Client tries `UPDATE payment_intents SET status='succeeded'` | Denied (no write policies) |
| 4.3 | Client tries `UPDATE orders SET payment_status='paid'` (non-admin) | Denied (tightened store-scoped policy; only the webhook/service role sets `paid`) |
| 4.4 | Client tries `INSERT/UPDATE payment_fee_config` | Denied (read-only policy; only `set_payment_fee_config` writes, admin role) |
| 4.5 | `payment_webhook_events` is append-only | No client write possible |
| 4.6 | Unauthenticated `get_gcash_fee` | Denied (grant is `authenticated` only) |

## 5. `cancel_my_pending_payment_intent` + expiry

| # | Case | Expect |
|---|---|---|
| 5.1 | Non-owner tries to cancel | `P0001` "Order not found" |
| 5.2 | Happy path (still pending) | Returns `true`; order `cancelled`/`failed` ("Cancelled by customer"); intent `cancelled`; audit row `cancel-…`; **no stock held → nothing to release**; one-pending cap freed |
| 5.3 | Cancel after webhook already paid | Returns `false` — no-op, order stays `pending`/`paid` |
| 5.4 | Cancel after expiry | Returns `false` |
| 5.5 | Set `expires_at` in the past → run the sweep SQL (or wait for cron) | Intent `expired`; order `cancelled`/`failed`; audit row `exp-…`; customer notification "Payment session expired"; no stock released (none held) |
| 5.6 | Run the sweep twice | Second run inserts nothing (NOT EXISTS guards), no double notification |

## 6. Edge-case coverage map (§8 of the brief)

| Brief case | Covered by |
|---|---|
| 7.1 Duplicate webhook | 2.6 |
| 7.2 Stock reservation vs decrement | Defer-until-paid: stock only moves on `payment.paid` materialization (1.8 asserts untouched pre-payment; 2.5 asserts exactly-once) |
| 7.3 Abandoned redirect | 5.5 (15-min expiry resolves; app polls get-payment-status) |
| 7.4 Double checkout / two devices | 1.10/1.11 + DB one-pending-per-customer index |
| 7.5 Webhook vs redirect/poll race | 2.13, 5.3; state guards in webhook + sweep |
| 7.6 Partial insert after capture | Webhook: diff-based materialization; never deletes a paid order — `payment_conflict` instead (2.8, 2.10) |
| 7.7 Amount mismatch | 2.8 |
| 7.8 Network/webview failures | Flutter: poll `get-payment-status` on resume — never trust the redirect (manual E2E) |

## 7. Manual Flutter E2E (after the app wiring lands)

1. **Happy path**: checkout with GCash → system browser opens PayMongo hosted page → complete test GCash authorization → return to app → "confirming payment…" → order shows `pending`/paid once the webhook lands; seller sees "New paid order".
2. **Abandon**: close the browser mid-payment → back in app → polling shows still `awaiting_payment` with countdown; after 15 min the sweep cancels it and the customer can re-checkout.
3. **Failure**: use a failing test payment → app shows the failure state with "no charge was made".
4. **Self-cancel**: create checkout, then cancel from My Orders → freed to re-checkout immediately.
5. **Cash on Pickup regression**: unchanged flow.
6. **POS regression**: `pos_screen.dart` untouched, static-QR flow still works.

## 8. Rollout notes

- Keep `PAYMONGO_LIVEMODE=false` and `sk_test_`/`whsk_test_` keys until the whole
  suite above passes and the code has been reviewed; switch to live keys via
  function env only, never code. Verify the live `payment_fee_config` rate
  against the PayMongo pricing page before the first live order.
- Suggest a soft rollout (one internal/test store) before enabling everywhere.
- PayMongo retries webhooks up to 12× but does **not** re-send missed events —
  `get-payment-status` polling is the documented rollback; keep the app polling
  until the order leaves `awaiting_payment`.
