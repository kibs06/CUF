// Shared PayMongo API helpers for Edge Functions (Deno)
//
// Two flows live here:
//   1. GCASH E-WALLET REDIRECT (current online checkout) — Payment Intent
//      with payment_method_allowed ['gcash'], a gcash payment method, and
//      attach → next_action.redirect.url sends the customer into GCash.
//   2. LEGACY QR Ph helpers (createQrPhPayment etc.) — kept so the dormant
//      attempt-#2 function `create-gcash-payment` still compiles. The POS
//      flow does NOT use these (it uses the seller's static QR + manual
//      confirmation).

const PAYMONGO_BASE_URL = "https://api.paymongo.com/v1";

/// Basic Auth header from the secret key (server-side only)
export function getSecretAuthHeader(): string {
  const secretKey = Deno.env.get("PAYMONGO_SECRET_KEY");
  if (!secretKey) {
    throw new Error("PAYMONGO_SECRET_KEY not configured");
  }
  const encoded = btoa(`${secretKey}:`);
  return `Basic ${encoded}`;
}

// ────────────────────────────────────────────────────────────────
// CURRENT FLOW — GCash e-wallet redirect (Payment Intents API)
// ────────────────────────────────────────────────────────────────

export interface GcashRedirectPayment {
  paymentIntentId: string;
  paymentMethodId: string;
  clientKey: string;
  checkoutUrl: string;
}

/// Full e-wallet flow: create intent (gcash) → create gcash method →
/// attach with return_url → return the redirect URL for the customer.
/// @param amount - amount in PHP (converted to centavos server-side)
/// @param description - shown on the payment record
/// @param returnUrl - where PayMongo sends the customer after auth
export async function createGcashRedirectPayment(
  amount: number,
  description: string,
  returnUrl: string,
): Promise<GcashRedirectPayment> {
  const amountInCentavos = Math.round(amount * 100);

  // Step 1: Payment Intent with gcash allowed
  const piRes = await fetch(`${PAYMONGO_BASE_URL}/payment_intents`, {
    method: "POST",
    headers: { "Content-Type": "application/json", "Authorization": getSecretAuthHeader() },
    body: JSON.stringify({
      data: {
        attributes: {
          amount: amountInCentavos,
          currency: "PHP",
          payment_method_allowed: ["gcash"],
          description,
        },
      },
    }),
  });
  if (!piRes.ok) {
    throw new Error(
      `PayMongo createPaymentIntent error (${piRes.status}): ${await piRes.text()}`,
    );
  }
  const pi = (await piRes.json()).data;
  const paymentIntentId: string = pi.id;
  const clientKey: string = pi.attributes?.client_key ?? "";

  // Step 2: Payment Method (gcash e-wallet)
  const pmRes = await fetch(`${PAYMONGO_BASE_URL}/payment_methods`, {
    method: "POST",
    headers: { "Content-Type": "application/json", "Authorization": getSecretAuthHeader() },
    body: JSON.stringify({
      data: { attributes: { type: "gcash" } },
    }),
  });
  if (!pmRes.ok) {
    throw new Error(
      `PayMongo createPaymentMethod error (${pmRes.status}): ${await pmRes.text()}`,
    );
  }
  const paymentMethodId: string = (await pmRes.json()).data?.id ?? "";

  // Step 3: Attach → the response carries next_action.redirect.url.
  // return_url tells PayMongo where to send the customer after they
  // complete or abort the GCash authorization.
  const attachRes = await fetch(
    `${PAYMONGO_BASE_URL}/payment_intents/${paymentIntentId}/attach`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json", "Authorization": getSecretAuthHeader() },
      body: JSON.stringify({
        data: {
          attributes: {
            payment_method: paymentMethodId,
            client_key: clientKey,
            return_url: returnUrl,
          },
        },
      }),
    },
  );
  if (!attachRes.ok) {
    throw new Error(
      `PayMongo attachPaymentMethod error (${attachRes.status}): ${await attachRes.text()}`,
    );
  }

  const attrs = (await attachRes.json()).data?.attributes ?? {};
  const nextAction = attrs.next_action ?? {};
  const checkoutUrl: string = nextAction.redirect?.url ?? "";
  if (!checkoutUrl) {
    console.error("[PAYMONGO] No next_action.redirect.url. attrs:", JSON.stringify(attrs));
    throw new Error("PayMongo did not return a checkout URL");
  }

  return { paymentIntentId, paymentMethodId, clientKey, checkoutUrl };
}

// ────────────────────────────────────────────────────────────────
// SHARED SIZE HELPERS — must match the DB inventory trigger, which
// matches sizes via regexp_replace(size, '\D', '', 'g').
// ────────────────────────────────────────────────────────────────

/// Strip non-digits from a size ("EU 8" → "8").
export function normalizeSize(size: string): string {
  return (size ?? "").replace(/\D/g, "");
}

/// Resolve the inventory size to use for a cart item: exact normalized
/// match with stock, else (for sizeless items) any in-stock row.
export function resolveInventorySize(
  inventoryRows: { size: string; stock: number }[],
  cartSize: string,
): string | null {
  const want = normalizeSize(cartSize);
  const exact = inventoryRows.find(
    (r) => normalizeSize(r.size) === want && r.stock > 0,
  );
  if (exact) return exact.size;
  if (!want && inventoryRows.some((r) => r.stock > 0)) {
    return inventoryRows.find((r) => r.stock > 0)!.size;
  }
  return null;
}

// ────────────────────────────────────────────────────────────────
// WEBHOOK SIGNATURE VERIFICATION (mandatory — see task brief §2.2)
//
// Header: Paymongo-Signature: t=<unix_ts>,te=<test sig>,li=<live sig>
// Signed string:  "<timestamp>.<raw JSON body>" (exact bytes)
// Algorithm:      HMAC-SHA256, hex digest, key = webhook secret (whsk_…)
// Replay guard:   timestamps older than 10 minutes are rejected.
// ────────────────────────────────────────────────────────────────

async function hmacSha256Hex(keyBytes: Uint8Array, message: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    keyBytes,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(message));
  return [...new Uint8Array(sig)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function timingSafeEqualHex(a: string, b: string): boolean {
  const max = Math.max(a.length, b.length);
  let diff = a.length ^ b.length;
  for (let i = 0; i < max; i++) {
    diff |= (a.charCodeAt(i) ^ b.charCodeAt(i)) >>> 0;
  }
  return diff === 0;
}

export async function verifyWebhookSignature(
  rawBody: string,
  signatureHeader: string,
  webhookSecret: string,
): Promise<boolean> {
  if (!signatureHeader || !webhookSecret) return false;

  const parts = new Map<string, string>();
  for (const part of signatureHeader.split(",")) {
    const eq = part.indexOf("=");
    if (eq < 1) continue;
    parts.set(part.slice(0, eq).trim(), part.slice(eq + 1).trim());
  }

  const timestamp = parts.get("t");
  // Prefer the live-mode signature; fall back to test mode (sandbox dev).
  const provided = parts.get("li") ?? parts.get("te");
  if (!timestamp || !provided) return false;

  const ts = Number.parseInt(timestamp, 10);
  if (Number.isNaN(ts)) return false;
  // Replay guard: reject anything older than 10 minutes.
  if (Math.abs(Date.now() / 1000 - ts) > 600) return false;

  const expected = await hmacSha256Hex(
    new TextEncoder().encode(webhookSecret),
    `${timestamp}.${rawBody}`,
  );
  return timingSafeEqualHex(expected, provided);
}

// ────────────────────────────────────────────────────────────────
// EVENT PARSING
// ────────────────────────────────────────────────────────────────

export interface PayMongoEvent {
  /// Event id (evt_xxx) — the idempotency key.
  id: string;
  /// Event type (payment.paid, payment.failed, …).
  type: string;
  livemode: boolean;
  /// The resource embedded in the event (payment object) — may be absent.
  data: {
    id: string;          // resource id (pay_xxx)
    attributes: Record<string, unknown>;
  };
  /// Raw redaction-friendly summary (no payment-method details).
  redacted: Record<string, unknown>;
}

export function parseWebhookEvent(body: string): PayMongoEvent {
  const parsed = JSON.parse(body);
  const attributes = parsed?.data?.attributes ?? {};
  const resource = attributes?.data ?? {};

  return {
    id: parsed?.data?.id ?? "",
    type: attributes?.type ?? "",
    livemode: attributes?.livemode === true,
    data: {
      id: resource?.id ?? "",
      attributes: resource?.attributes ?? {},
    },
    redacted: {
      event_id: parsed?.data?.id ?? "",
      type: attributes?.type ?? "",
      livemode: attributes?.livemode ?? false,
      resource_id: resource?.id ?? "",
      amount: resource?.attributes?.amount ?? null,
      status: resource?.attributes?.status ?? null,
      payment_intent: resource?.attributes?.payment_intent?.id ?? null,
      payment_intent_id: resource?.attributes?.payment_intent_id ?? null,
    },
  };
}

// ────────────────────────────────────────────────────────────────
// LEGACY — QR Ph helpers (attempt #2). Kept so the dormant
// `create-gcash-payment` function still compiles. NOT used by any
// live flow. Do not extend these.
// ────────────────────────────────────────────────────────────────

export async function createPaymentIntent(
  amount: number,
  description: string,
): Promise<{ id: string; clientKey: string; status: string }> {
  const amountInCentavos = Math.round(amount * 100);
  const response = await fetch(`${PAYMONGO_BASE_URL}/payment_intents`, {
    method: "POST",
    headers: { "Content-Type": "application/json", "Authorization": getSecretAuthHeader() },
    body: JSON.stringify({
      data: {
        attributes: {
          amount: amountInCentavos,
          currency: "PHP",
          payment_method_allowed: ["qrph"],
          description,
        },
      },
    }),
  });
  if (!response.ok) {
    throw new Error(`PayMongo createPaymentIntent error (${response.status}): ${await response.text()}`);
  }
  const pi = (await response.json()).data;
  return { id: pi.id, clientKey: pi.attributes?.client_key || "", status: pi.attributes?.status || "awaiting_next_action" };
}

export async function createQrPhPaymentMethod(): Promise<string> {
  const response = await fetch(`${PAYMONGO_BASE_URL}/payment_methods`, {
    method: "POST",
    headers: { "Content-Type": "application/json", "Authorization": getSecretAuthHeader() },
    body: JSON.stringify({ data: { attributes: { type: "qrph" } } }),
  });
  if (!response.ok) {
    throw new Error(`PayMongo createPaymentMethod error (${response.status}): ${await response.text()}`);
  }
  return (await response.json()).data?.id || "";
}

export async function attachPaymentMethod(
  paymentIntentId: string,
  paymentMethodId: string,
  clientKey: string,
): Promise<{ qrImageBase64: string; status: string }> {
  const response = await fetch(
    `${PAYMONGO_BASE_URL}/payment_intents/${paymentIntentId}/attach`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json", "Authorization": getSecretAuthHeader() },
      body: JSON.stringify({
        data: { attributes: { payment_method: paymentMethodId, client_key: clientKey } },
      }),
    },
  );
  if (!response.ok) {
    throw new Error(`PayMongo attachPaymentMethod error (${response.status}): ${await response.text()}`);
  }
  const attrs = (await response.json()).data?.attributes || {};
  const nextAction = attrs.next_action || {};
  const code = nextAction.code || {};
  const qrImageBase64 = code.image_url || code.payload || "";
  if (!qrImageBase64) {
    throw new Error("No QR image found in PayMongo response");
  }
  return { qrImageBase64, status: attrs.status || "awaiting_next_action" };
}

export async function createQrPhPayment(
  amount: number,
  description: string,
): Promise<{ paymentIntentId: string; qrImageBase64: string }> {
  const pi = await createPaymentIntent(amount, description);
  const pmId = await createQrPhPaymentMethod();
  const attachResult = await attachPaymentMethod(pi.id, pmId, pi.clientKey);
  return { paymentIntentId: pi.id, qrImageBase64: attachResult.qrImageBase64 };
}
