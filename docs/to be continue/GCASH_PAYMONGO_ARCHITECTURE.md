# GCash PayMongo QR Ph Integration — Architecture & Documentation

> **Last updated:** July 30, 2026  
> **Status:** Implementation in progress — QR image scanning bug under investigation  
> **Payment gateway:** PayMongo (test mode)  
> **Standard:** QR Ph (BSP Philippine national QR standard)

---

## Table of Contents

1. [Overview](#1-overview)
2. [Architecture Diagram](#2-architecture-diagram)
3. [Payment Flow — Step by Step](#3-payment-flow--step-by-step)
4. [Database Schema](#4-database-schema)
5. [Edge Functions](#5-edge-functions)
6. [Flutter Client — Checkout Sheet](#6-flutter-client--checkout-sheet)
7. [PayMongo API Reference](#7-paymongo-api-reference)
8. [Webhook Handling](#8-webhook-handling)
9. [Security Considerations](#9-security-considerations)
10. [Known Issues & Debugging](#10-known-issues--debugging)
11. [Testing Checklist](#11-testing-checklist)
12. [Deployment Guide](#12-deployment-guide)
13. [File Reference](#13-file-reference)
14. [Historical Context — Why QR Ph Not Sources API](#14-historical-context--why-qr-ph-not-sources-api)
15. [Future Improvements](#15-future-improvements)

---

## 1. Overview

This document describes the architecture for real, auto-confirming GCash payments in the SoleVision POS (Point of Sale) Flutter app using **PayMongo's QR Ph** integration.

### What It Does

When a seller selects "GCash" in the POS checkout sheet:

1. The app creates a **Payment Intent** with PayMongo
2. PayMongo generates a **QR Ph code** — a genuine BSP-standard QR code
3. The QR Ph code is displayed on screen for the customer to scan with their GCash app
4. The customer approves the payment in GCash
5. PayMongo sends a **webhook** confirming payment
6. The order's `payment_status` flips from `'pending'` → `'paid'` **automatically**
7. The checkout sheet detects this (via polling) and completes the transaction

### Key Properties

| Property | Value |
|---|---|
| Payment gateway | PayMongo (test mode: `sk_test_*`, `pk_test_*`) |
| QR standard | QR Ph (BSP Philippine national standard) |
| Supported apps | GCash, Maya, BPI, BDO, UnionBank, 30+ banks/e-wallets |
| Payment confirmation | Automatic via webhook (no manual reference entry) |
| Order creation timing | Upfront with `payment_status: 'pending'` before QR generation |
| Inventory decrement | ⚠️ Currently happens at order creation (see [Known Issues](#10-known-issues--debugging)) |

---

## 2. Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                        POS Flutter App                          │
│                                                                 │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────────┐  │
│  │  _POSScreen   │───▶│ _CheckoutSheet│───▶│  _startGcashPayment()│ │
│  │              │    │              │    │                  │  │
│  │  Order Items │    │ GCash/ Cash  │    │ 1. _createPendingOrder()│ │
│  │  Total       │    │ Method Select│    │ 2. Edge Function call  │ │
│  │              │    │ QR Display   │    │ 3. Start polling       │ │
│  └──────────────┘    │ Poll Timer   │    └──────────────────┘  │
│                      └──────────────┘                           │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ Supabase Edge Function invoke
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                  Supabase Edge Function                         │
│              create-gcash-payment/index.ts                      │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │              _shared/paymongo.ts                          │  │
│  │                                                          │  │
│  │  Step 1: POST /v1/payment_intents                        │  │
│  │          → { id, clientKey, status }                     │  │
│  │                                                          │  │
│  │  Step 2: POST /v1/payment_methods                        │  │
│  │          → { paymentMethodId }                           │  │
│  │                                                          │  │
│  │  Step 3: POST /v1/payment_intents/{id}/attach            │  │
│  │          → { qrImageBase64 } (from next_action.code)     │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
│  Saves Payment Intent ID to orders.gcash_reference_number       │
│  Returns { paymentIntentId, qrImageBase64 } to Flutter client   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ HTTP POST
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      PayMongo API                               │
│                https://api.paymongo.com/v1                      │
│                                                                 │
│  Payment Intent → Payment Method → Attach → QR Ph Image        │
│                                                                 │
│  Customer scans QR with GCash app → Payment confirmed           │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ Webhook POST
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│              Supabase Edge Function                             │
│              gcash-webhook/index.ts                              │
│                                                                 │
│  Receives: payment.paid event                                   │
│  Extracts: payment_intent ID from event payload                 │
│  Updates:  orders SET payment_status='paid'                     │
│            WHERE gcash_reference_number = <payment_intent_id>   │
│                                                                 │
│  Also sets: gcash_transaction_id, payment_verified_at           │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ Supabase Realtime / Polling
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                  POS Flutter App (Polling)                       │
│                                                                 │
│  Every 3 seconds: SELECT payment_status FROM orders WHERE id=X  │
│                                                                 │
│  When payment_status == 'paid':                                 │
│    → Cancel poll timer                                          │
│    → Call onConfirm('GCash', 0, orderId: orderId)              │
│    → _completePOSTransaction() → Success overlay                │
└─────────────────────────────────────────────────────────────────┘
```

---

## 3. Payment Flow — Step by Step

### 3.1 Seller Initiates GCash Payment

1. Seller taps **"Generate GCash QR"** button in `_CheckoutSheet`
2. `_startGcashPayment()` is called

### 3.2 Order Created with Pending Status

```
_createPendingOrder():
  1. Look up store_id from first product
  2. INSERT INTO orders:
     - customer_id: auth.id
     - store_id: <from product>
     - status: 'received'
     - fulfillment: 'pickup'
     - total_amount: <order total>
     - payment_method: 'gcash'
     - payment_status: 'pending'     ← KEY: not 'paid' yet
     - notes: 'In-store POS'
     - source: 'pos'
  3. INSERT INTO order_items (for each item)
  4. INSERT INTO order_status_history
  5. Return order ID
```

### 3.3 Edge Function Creates QR Ph

```
create-gcash-payment Edge Function:
  1. Receive { orderId, amount }
  2. Call createQrPhPayment(amount, description)
     a. POST /v1/payment_intents
        → { id: 'pi_xxx', clientKey: 'xxx', status: 'awaiting_next_action' }
     b. POST /v1/payment_methods
        → { id: 'pm_xxx' }
     c. POST /v1/payment_intents/{id}/attach
        → { next_action.code.image_url: 'data:image/png;base64,...' }
  3. UPDATE orders SET gcash_reference_number = <payment_intent_id>
  4. Return { paymentIntentId, qrImageBase64 }
```

### 3.4 Flutter Displays QR Ph Image

```dart
_gcashQrImageBase64 = response.data['qrImageBase64'];
_gcashPaymentPending = true;

// Render in checkout sheet:
Widget _buildQrPhImage(String base64Data) {
  final raw = base64Data.contains(',')
      ? base64Data.split(',').last  // Strip data URI prefix
      : base64Data;
  final bytes = base64Decode(raw);
  return Image.memory(bytes, width: 280, height: 280);
}
```

### 3.5 Customer Scans and Pays

1. Customer opens GCash app → Scan QR
2. Customer confirms payment in GCash
3. GCash sends payment to PayMongo

### 3.6 PayMongo Sends Webhook

```
POST /functions/v1/gcash-webhook
Body: {
  "data": {
    "id": "pay_xxx",
    "attributes": {
      "type": "payment.paid",
      "payment_intent": { "id": "pi_xxx" }
    }
  }
}
```

### 3.7 Webhook Updates Order

```sql
UPDATE orders SET
  payment_status = 'paid',
  gcash_transaction_id = 'pay_xxx',
  payment_verified_at = now()
WHERE gcash_reference_number = 'pi_xxx'
  AND payment_status = 'pending';
```

### 3.8 Polling Detects Payment

```dart
// Every 3 seconds:
Timer.periodic(Duration(seconds: 3), (_) async {
  final order = await supabase
      .from('orders')
      .select('payment_status')
      .eq('id', orderId)
      .single();

  if (order['payment_status'] == 'paid') {
    _pollTimer?.cancel();
    widget.onConfirm('GCash', 0, orderId: orderId);
    // → Success overlay shown
  }
});
```

---

## 4. Database Schema

### 4.1 Orders Table — GCash Columns

```sql
-- From schema.sql (updated)
CREATE TABLE IF NOT EXISTS public.orders (
    id              BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    customer_id     UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    store_id        UUID REFERENCES public.stores(id),
    status          TEXT NOT NULL DEFAULT 'placed'
                        CHECK (status IN ('placed', 'preparing', 'ready', 'received', 'cancelled', 'pending')),
    total_amount    NUMERIC NOT NULL CHECK (total_amount >= 0),
    payment_method  TEXT NOT NULL DEFAULT 'cash',
    payment_status  TEXT NOT NULL DEFAULT 'unpaid'
                        CHECK (payment_status IN ('paid', 'unpaid', 'pending')),
    fulfillment     TEXT NOT NULL DEFAULT 'pickup'
                        CHECK (fulfillment IN ('pickup', 'delivery')),
    notes           TEXT,
    -- PayMongo GCash integration columns
    gcash_reference_number TEXT,          -- PayMongo Payment Intent ID (pi_xxx)
    gcash_transaction_id   TEXT,          -- PayMongo Payment ID (pay_xxx)
    payment_verified_at    TIMESTAMPTZ,   -- When webhook confirmed payment
    source          TEXT DEFAULT 'online',
    created_at      TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);
```

### 4.2 Column Descriptions

| Column | Type | Description |
|---|---|---|
| `gcash_reference_number` | `TEXT` | PayMongo Payment Intent ID (`pi_xxx`). Stored when QR is generated. Used by webhook to find the order. |
| `gcash_transaction_id` | `TEXT` | PayMongo Payment ID (`pay_xxx`). Set by webhook when payment is confirmed. |
| `payment_verified_at` | `TIMESTAMPTZ` | Timestamp when PayMongo webhook confirmed the payment. |
| `payment_status` | `TEXT` | `'pending'` (QR generated, waiting) → `'paid'` (webhook confirmed) or `'unpaid'` (Cash). |

### 4.3 Migration Files

| Migration | Purpose |
|---|---|
| `20260729110000_add_gcash_manual_verification.sql` | Added manual GCash flow columns (now superseded) |
| `20260730000000_add_paymongo_gcash_columns.sql` | Added `gcash_transaction_id`, `payment_verified_at`, updated CHECK constraint to allow `'pending'`, dropped manual GCash columns from stores |

---

## 5. Edge Functions

### 5.1 File Structure

```
supabase/functions/
├── _shared/
│   └── paymongo.ts              # Shared PayMongo API helpers
├── create-gcash-payment/
│   └── index.ts                 # Creates QR Ph payment
└── gcash-webhook/
    └── index.ts                 # Handles payment.paid webhook
```

### 5.2 `_shared/paymongo.ts`

**Exports:**

| Function | Purpose |
|---|---|
| `getSecretAuthHeader()` | Returns HTTP Basic Auth header using `PAYMONGO_SECRET_KEY` |
| `createPaymentIntent(amount, description)` | Step 1: Creates Payment Intent with `qrph` in `payment_method_allowed` |
| `createQrPhPaymentMethod()` | Step 2: Creates QR Ph Payment Method |
| `attachPaymentMethod(piId, pmId, clientKey)` | Step 3: Attaches Payment Method, returns base64 QR image |
| `createQrPhPayment(amount, description)` | Orchestrates all 3 steps, returns `{ paymentIntentId, qrImageBase64 }` |
| `verifyWebhookSignature(payload, signature)` | ⚠️ Stub — always returns true (TODO: implement HMAC) |
| `parseWebhookEvent(body)` | Parses PayMongo webhook JSON into typed event |

### 5.3 `create-gcash-payment/index.ts`

**Endpoint:** `POST /functions/v1/create-gcash-payment`  
**Auth:** Supabase client auth (JWT required)  
**Request body:**
```json
{
  "orderId": 123,
  "amount": 599.00
}
```

**Response (200):**
```json
{
  "paymentIntentId": "pi_xxxxxxxxxxxx",
  "qrImageBase64": "data:image/png;base64,iVBORw0KGgo..."
}
```

**Side effects:**
- Updates `orders.gcash_reference_number` with the Payment Intent ID

### 5.4 `gcash-webhook/index.ts`

**Endpoint:** `POST /functions/v1/gcash-webhook`  
**Auth:** ⚠️ Currently no JWT verification (deployed with `--no-verify-jwt`)  
**Webhook signature:** ⚠️ Verification is a stub (TODO: implement HMAC)

**Handles these events:**

| Event | Action |
|---|---|
| `payment.paid` | Updates order: `payment_status='paid'`, sets `gcash_transaction_id` and `payment_verified_at` |
| `payment.failed` | Logs failure (no order update yet) |
| `qrph.expired` | Logs expiry (QR not scanned within 30 minutes) |

---

## 6. Flutter Client — Checkout Sheet

### 6.1 State Variables

```dart
// In _CheckoutSheetState
bool _gcashPaymentPending = false;     // QR is showing, waiting for payment
String? _gcashQrImageBase64;           // Base64 QR Ph image from PayMongo
String? _gcashOrderId;                 // Order ID (for polling/cleanup)
bool _gcashCreatingPayment = false;    // Loading state while creating QR
String? _gcashError;                   // Error message to display
Timer? _pollTimer;                     // Polls payment_status every 3s
```

### 6.2 Key Methods

| Method | Purpose |
|---|---|
| `_createPendingOrder()` | Creates order with `payment_status='pending'` before QR generation |
| `_startGcashPayment()` | Orchestrates: create order → call Edge Function → show QR → start polling |
| `_startPolling(orderId)` | Polls `payment_status` every 3 seconds |
| `_cancelGcashPayment()` | Deletes pending order and resets state |
| `_buildQrPhImage(base64Data)` | Decodes base64 and renders QR Ph image via `Image.memory()` |

### 6.3 UI Layout

```
┌─────────────────────────────────────┐
│  Payment                        [X] │  ← Header (fixed)
├─────────────────────────────────────┤
│  Total:                    ₱599     │
│                                     │
│  Method:                           │
│  [Cash]  [GCash]                   │  ← Scrollable content
│                                     │
│  ┌─────────────────────────────┐   │
│  │                             │   │
│  │      [QR Ph Image]          │   │  ← 300×300px container
│  │       280×280px             │   │
│  │                             │   │
│  └─────────────────────────────┘   │
│                                     │
│  🔄 Waiting for payment...         │
│  Ask customer to scan this QR      │
│                                     │
│  [ Cancel Payment ]                │
├─────────────────────────────────────┤
│  [ Confirm Payment  ₱599 ]         │  ← Fixed footer
└─────────────────────────────────────┘
```

---

## 7. PayMongo API Reference

### 7.1 Authentication

All API calls use **HTTP Basic Auth** with the secret key:

```
Authorization: Basic base64(sk_test_xxx:)
```

### 7.2 Step 1: Create Payment Intent

```
POST https://api.paymongo.com/v1/payment_intents
Authorization: Basic <secret_key>
Content-Type: application/json

{
  "data": {
    "attributes": {
      "amount": 59900,              // Amount in centavos (₱599 × 100)
      "currency": "PHP",
      "payment_method_allowed": ["qrph"],
      "description": "Payment for Order #123"
    }
  }
}
```

**Response:**
```json
{
  "data": {
    "id": "pi_xxxxxxxxxxxx",
    "type": "payment_intent",
    "attributes": {
      "amount": 59900,
      "currency": "PHP",
      "status": "awaiting_next_action",
      "client_key": "pi_xxx_client_xxx",
      "payment_method_allowed": ["qrph"]
    }
  }
}
```

### 7.3 Step 2: Create Payment Method

```
POST https://api.paymongo.com/v1/payment_methods
Authorization: Basic <secret_key>
Content-Type: application/json

{
  "data": {
    "attributes": {
      "type": "qrph"
    }
  }
}
```

**Response:**
```json
{
  "data": {
    "id": "pm_xxxxxxxxxxxx",
    "type": "payment_method",
    "attributes": {
      "type": "qrph",
      "livemode": false
    }
  }
}
```

### 7.4 Step 3: Attach Payment Method

```
POST https://api.paymongo.com/v1/payment_intents/{id}/attach
Authorization: Basic <secret_key>
Content-Type: application/json

{
  "data": {
    "attributes": {
      "payment_method": "pm_xxxxxxxxxxxx",
      "client_key": "pi_xxx_client_xxx"
    }
  }
}
```

**Response (key fields):**
```json
{
  "data": {
    "id": "pi_xxxxxxxxxxxx",
    "attributes": {
      "status": "awaiting_next_action",
      "next_action": {
        "type": "code",
        "code": {
          "image_url": "data:image/png;base64,iVBORw0KGgo..."
        }
      }
    }
  }
}
```

### 7.5 QR Ph Response Structure

```json
{
  "next_action": {
    "type": "code",
    "code": {
      "image_url": "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAA..."
    }
  }
}
```

**Important:** The `image_url` field contains a **full data URI string** (`data:image/png;base64,...`), not a URL. It must be stripped of the prefix before base64 decoding.

---

## 8. Webhook Handling

### 8.1 Webhook URL

```
https://psczvbfoybqhjeqssimw.supabase.co/functions/v1/gcash-webhook
```

### 8.2 Events to Register in PayMongo Dashboard

| Event | Description |
|---|---|
| `payment.paid` | Customer successfully paid via QR Ph |
| `payment.failed` | Payment attempt failed |
| `qrph.expired` | QR code was not scanned within 30 minutes |

### 8.3 Webhook Payload Structure

```json
{
  "data": {
    "id": "pay_xxxxxxxxxxxx",
    "type": "event",
    "attributes": {
      "type": "payment.paid",
      "livemode": false,
      "data": {
        "id": "pay_xxxxxxxxxxxx",
        "type": "payment",
        "attributes": {
          "amount": 59900,
          "currency": "PHP",
          "status": "paid",
          "payment_intent": {
            "id": "pi_xxxxxxxxxxxx"
          }
        }
      }
    }
  }
}
```

### 8.4 Order Lookup Logic

```sql
-- Webhook finds the order by Payment Intent ID
SELECT id FROM orders
WHERE gcash_reference_number = '<payment_intent_id>'
  AND payment_status = 'pending'
LIMIT 1;

-- Then updates it
UPDATE orders SET
  payment_status = 'paid',
  gcash_transaction_id = '<payment_id>',
  payment_verified_at = now()
WHERE id = <order_id>;
```

---

## 9. Security Considerations

### 9.1 API Keys

| Key | Storage | Used By |
|---|---|---|
| `sk_test_*` (Secret) | Supabase Edge Function secret (`PAYMONGO_SECRET_KEY`) | Edge Functions only |
| `pk_test_*` ( Public) | Not currently used | Would be used for client-side SDK |

**Never** commit API keys to source control or reference them from Flutter client code.

### 9.2 Webhook Security

⚠️ **Currently not implemented:**
- `verifyWebhookSignature()` is a stub that always returns `true`
- The `gcash-webhook` Edge Function is deployed with `--no-verify-jwt`

**TODO:** Implement HMAC verification using `PAYMONGO_WEBHOOK_SECRET` and the `Paymongo-Signature` header.

### 9.3 RLS Bypass

Edge Functions use the **service role key** to bypass RLS when updating orders, since the webhook comes from PayMongo (not an authenticated user).

---

## 10. Known Issues & Debugging

### 10.1 🔴 CRITICAL: QR Image Not Scanning in GCash

**Symptom:** GCash app shows nothing when scanning — no error, no payment prompt.

**Most likely root cause:** The `image_url` from PayMongo may be a data URI (`data:image/png;base64,...`) that needs prefix stripping, OR the decoded image is corrupted.

**Current mitigation:**
- Added `debugPrint` logging in `_buildQrPhImage()` to trace raw data
- Added logging in Edge Function `attachPaymentMethod()` to trace PayMongo response
- Increased QR container size from 260→300px and image from 236→280px

**Diagnostic steps:**
1. Check Edge Function logs in Supabase dashboard for `[PAYMONGO]` entries
2. Verify `code.image_url` exists and starts with `data:image/`
3. Take the base64 string, decode externally, and verify it's a valid QR image
4. If `image_url` is missing, check if PayMongo returns the image at a different path

### 10.2 🟡 Inventory Decremented Too Early

**Issue:** `_createPendingOrder()` inserts `order_items` immediately, which triggers the stock check constraint/decrement. Per requirements, inventory should only decrement when payment is confirmed.

**Current behavior:** Stock is decremented when QR is generated, not when payment is confirmed.

**Proposed fix:** Create the order row without items initially, add items only after the webhook marks it paid.

### 10.3 🟡 No Cleanup on Edge Function Failure

**Issue:** If `_createPendingOrder()` succeeds but the Edge Function call fails, the pending order is orphaned with no QR and no way to recover.

**Proposed fix:** Add try/catch that deletes the pending order if the Edge Function call fails.

### 10.4 🟡 Webhook Signature Verification Not Implemented

**Issue:** `verifyWebhookSignature()` always returns `true`. Any forged HTTP request can mark orders as paid.

**Fix:** Implement HMAC verification using `PAYMONGO_WEBHOOK_SECRET`.

### 10.5 🟡 `payment.paid` Event Payload Structure

**Issue:** The webhook extracts `payment_intent_id` via `event.data.attributes?.payment_intent?.id || event.data.attributes?.payment_intent_id`. PayMongo's actual payload may nest this differently.

**Fix:** Verify against the actual webhook payload. If the PI ID isn't directly in the payload, fetch the payment via API using the payment ID.

---

## 11. Testing Checklist

- [ ] Cash flow still works unchanged (regression check)
- [ ] No leftover manual-flow code remains (QR upload, reference number input, store settings GCash section)
- [ ] Selecting GCash shows a real PayMongo QR Ph image within a couple seconds
- [ ] **The generated QR actually scans successfully in the real GCash app** ← CURRENT BLOCKER
- [ ] In test mode, use PayMongo's test URL to simulate payment success/failure
- [ ] Simulated successful payment marks the order `paid` automatically
- [ ] `orders.payment_status` transitions `pending → paid` correctly
- [ ] `gcash_reference_number`, `gcash_transaction_id`, `payment_verified_at` are populated correctly
- [ ] Cancelling a pending GCash payment doesn't leave orphaned order records
- [ ] Webhook signature verification rejects unsigned/forged requests (TODO)
- [ ] Inventory is only decremented once payment is confirmed (TODO)
- [ ] Rapid consecutive GCash orders don't cross-contaminate
- [ ] Seller-facing errors show clearly if PayMongo API call fails
- [ ] No secret key appears in Flutter client code or version control

---

## 12. Deployment Guide

### 12.1 Prerequisites

1. PayMongo test-mode account created
2. Test API keys obtained: `sk_test_*` and `pk_test_*`
3. Supabase project linked

### 12.2 Set Environment Variables

```bash
# Set PayMongo secret key as Edge Function secret
supabase secrets set PAYMONGO_SECRET_KEY=sk_test_xxxxxxxxxxxx
```

### 12.3 Deploy Edge Functions

```bash
# Deploy the payment creation function (with JWT verification)
supabase functions deploy create-gcash-payment

# Deploy the webhook function (without JWT verification — PayMongo calls it externally)
supabase functions deploy gcash-webhook --no-verify-jwt
```

### 12.4 Register Webhook in PayMongo Dashboard

1. Go to https://dashboard.paymongo.com → Webhooks
2. Add webhook URL: `https://psczvbfoybqhjeqssimw.supabase.co/functions/v1/gcash-webhook`
3. Enable events: `payment.paid`, `payment.failed`, `qrph.expired`
4. Copy the webhook signing secret (for future HMAC implementation)

### 12.5 Run Database Migrations

```bash
supabase db push
# Or apply migration 20260730000000_add_paymongo_gcash_columns.sql
```

---

## 13. File Reference

| File | Purpose | Lines |
|---|---|---|
| `supabase/functions/_shared/paymongo.ts` | PayMongo API helpers (auth, create PI, create PM, attach, webhook parsing) | ~200 |
| `supabase/functions/create-gcash-payment/index.ts` | Edge Function: creates QR Ph payment, saves PI ID to order | ~80 |
| `supabase/functions/gcash-webhook/index.ts` | Edge Function: handles payment.paid webhook, updates order status | ~100 |
| `lib/screens/seller/pos_screen.dart` | Flutter POS screen with `_CheckoutSheet` containing GCash flow | ~1900 |
| `lib/providers/order_provider.dart` | Order provider with `placeOrder()` accepting `gcashReference` | ~250 |
| `lib/services/supabase_service.dart` | `createOrder()` persists `gcash_reference_number` to DB | ~950 |
| `lib/services/order_service.dart` | Order service layer | ~350 |
| `supabase/schema.sql` | Full DB schema with GCash columns | ~450 |
| `supabase/migrations/20260730000000_add_paymongo_gcash_columns.sql` | Migration: adds PI columns, updates CHECK constraint | ~30 |
| `pubspec.yaml` | Dependencies (qr_flutter was removed) | ~120 |

---

## 14. Historical Context — Why QR Ph Not Sources API

### First Attempt: PayMongo Sources API (REVERTED)

The initial integration used PayMongo's **Sources API** (`type: 'gcash'`):

```typescript
// OLD approach — REVERTED
POST /v1/sources
{ type: 'gcash', amount: 59900, currency: 'PHP' }
// Returns: checkout_url → rendered as QR via qr_flutter
```

**Problem:** GCash's native scanner rejected this QR code as "not valid" because:
- The Sources API produces a **plain web-link QR**, not a BSP-standard QR Ph
- GCash validates scanned QR codes against the **QR Ph standard** and rejects non-compliant codes

### Second Approach: Manual Verification (REPLACED)

A manual flow was built where sellers uploaded their personal GCash QR and typed reference numbers.

**Problem:** No automatic payment confirmation — the app couldn't know when payment happened.

### Current Approach: QR Ph Payment Intent Flow

The Payment Intent → Payment Method → Attach flow produces a **genuine BSP-standard QR Ph code** that:
- Scans correctly in GCash's native scanner
- Works with 30+ other banks/e-wallets via InstaPay
- Enables automatic payment confirmation via webhook

---

## 15. Future Improvements

### High Priority

1. **Fix QR image scanning** — Diagnose and fix the current issue where the QR doesn't scan
2. **Implement webhook HMAC verification** — Replace the stub with real signature verification
3. **Fix inventory timing** — Defer stock decrement until payment is confirmed

### Medium Priority

4. **Add cleanup on Edge Function failure** — Delete orphaned pending orders
5. **Verify `payment.paid` payload structure** — Ensure PI ID extraction works with actual PayMongo payloads
6. **Remove debug logging** — Clean up `debugPrint` statements after QR scanning is confirmed working

### Low Priority

7. **Add Supabase Realtime** — Replace polling with Realtime subscription for instant payment detection
8. **Handle `qrph.expired`** — Show user-friendly message when QR expires after 30 minutes
9. **Add payment failure handling** — Update order status when payment fails
10. **Receipt display** — Show GCash reference number and transaction ID on POS receipt

---

## Appendix A: Environment Variables

| Variable | Where Set | Purpose |
|---|---|---|
| `PAYMONGO_SECRET_KEY` | `supabase secrets set` | PayMongo API authentication |
| `SUPABASE_URL` | Automatic (Edge Functions) | Supabase project URL |
| `SUPABASE_SERVICE_ROLE_KEY` | Automatic (Edge Functions) | Bypass RLS for order updates |
| `PAYMONGO_WEBHOOK_SECRET` | Not yet set | Webhook HMAC verification (TODO) |

## Appendix B: PayMongo Test Mode Notes

- In test mode, QR Ph generates **real, functional QR codes**
- Do NOT scan and actually pay with a real GCash account — PayMongo processes genuine transactions even in test mode
- Use PayMongo's `test_url` from the response to simulate payment success/failure
- Test keys: `sk_test_*` (secret), `pk_test_*` (public)

## Appendix C: Database State Transitions

```
GCash Payment Flow:
  Order created    → payment_status = 'pending'
  Webhook received → payment_status = 'paid'
  
Cash Payment Flow:
  Order created    → payment_status = 'paid' (immediate)

Cancelled:
  Order deleted    → cascade deletes order_items
```
