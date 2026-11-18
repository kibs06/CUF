// Shared PayMongo API helpers for Edge Functions (Deno)
//
// Flows that live here:
//   1. GCASH E-WALLET VIA CHECKOUT SESSIONS (attempt #6 — CURRENT online
//      checkout). One POST /v1/checkout_sessions → PayMongo-hosted page
//      handles the GCash handoff; the customer returns via success_url /
//      cancel_url; a signature-verified webhook
//      (checkout_session.payment.paid / payment.paid / payment.failed)
//      finalizes the order. Recommended by PayMongo for standard
//      integrations and built for pass-on (Model B) fees.
//   2. LEGACY GCASH E-WALLET REDIRECT (attempt #4 — dormant). Manual
//      Payment Intent + gcash method + attach with return_url →
//      next_action.redirect.url. Kept so the attempt-#4 function still
//      compiles; NOT used by the live flow.
//   3. LEGACY QR Ph helpers (attempt #2 — dormant). Kept so the dormant
//      `create-gcash-payment` function still compiles. Do not extend.

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
// MODE GUARD — sandbox vs live is decided by the SECRET KEY alone.
//
// A `sk_test_…` key creates TEST checkout sessions no matter what
// PAYMONGO_LIVEMODE says; that variable only labels the rows we
// record. When the two disagree, nothing downstream complains: the
// customer pays nothing, the order sits at awaiting_payment, and the
// books claim the opposite of what happened (the Aug 19, 2026
// incident: a test payment in a live store). So the checkout path
// refuses to create a session at all until key and config agree.
//
// Fail closed: a key whose prefix is neither sk_test_ nor sk_live_
// (rotated format, typo, truncated paste) is also refused.
// ────────────────────────────────────────────────────────────────

export type PaymongoMode = "test" | "live";

export class PaymongoModeMismatchError extends Error {
  readonly keyMode: PaymongoMode | "unknown";
  readonly configuredMode: PaymongoMode;

  constructor(keyMode: PaymongoMode | "unknown", configuredMode: PaymongoMode) {
    super(
      `PayMongo mode mismatch: the configured secret key is ` +
        (keyMode === "unknown"
          ? "neither sk_test_ nor sk_live_"
          : `${keyMode}-mode`) +
        ` but PAYMONGO_LIVEMODE=${configuredMode}. Refusing to create a checkout session.`,
    );
    this.name = "PaymongoModeMismatchError";
    this.keyMode = keyMode;
    this.configuredMode = configuredMode;
  }
}

/// Mode encoded in a secret key's prefix.
export function secretKeyMode(secretKey: string): PaymongoMode | "unknown" {
  if (secretKey.startsWith("sk_live_")) return "live";
  if (secretKey.startsWith("sk_test_")) return "test";
  return "unknown";
}

/// Mode PAYMONGO_LIVEMODE asks for.
export function configuredLivemodeMode(flag: string | undefined): PaymongoMode {
  return flag === "true" ? "live" : "test";
}

/// Mode of the secret key currently installed on the project.
export function paymongoKeyMode(): PaymongoMode | "unknown" {
  return secretKeyMode(Deno.env.get("PAYMONGO_SECRET_KEY") ?? "");
}

/// Mode the project is configured to run in.
export function paymongoConfiguredMode(): PaymongoMode {
  return configuredLivemodeMode(Deno.env.get("PAYMONGO_LIVEMODE"));
}

export type ModeMismatchDisposition = "ok" | "retry" | "acknowledge";

/// How a webhook event's `livemode` should be treated against ours.
///
///   ok          — the event is from the environment we are running in.
///   retry       — a LIVE event while we are configured for TEST. Real money
///                 moved, so it must never be dropped: answer 500 so PayMongo
///                 keeps redelivering, and once the configuration is restored
///                 (live key + PAYMONGO_LIVEMODE=true) the retry processes
///                 normally because the guard passes and the event id is
///                 still unclaimed.
///   acknowledge — a TEST event while we are configured for LIVE. A leftover
///                 sandbox checkout can never be valid here, so there is
///                 nothing to retry: audit it and answer 200.
export function eventModeDisposition(
  eventLivemode: boolean,
  configuredLivemode: boolean,
): ModeMismatchDisposition {
  if (eventLivemode === configuredLivemode) return "ok";
  return eventLivemode ? "retry" : "acknowledge";
}

export interface WebhookModeGuardResult {
  disposition: ModeMismatchDisposition;
  /** HTTP status the webhook must answer with. */
  status: 200 | 500;
  /** True when PayMongo should redeliver (real money left unconfirmed). */
  retryable: boolean;
  /** True when an admin must be told about this delivery. */
  notifyAdmins: boolean;
}

/// The webhook's whole mode decision, in one pure place.
///
/// An event with no boolean `livemode` cannot be proven to belong to our
/// environment, so it is treated like the retryable case: fail closed, never
/// open (the parser defaults the missing field to `false`).
///
/// Both mismatch directions notify an admin and neither changes what the
/// caller does with the result: `status` is decided here, before any
/// notification is attempted.
export function evaluateWebhookModeGuard(
  eventLivemode: boolean,
  livemodeKnown: boolean,
  configuredLivemode: boolean,
): WebhookModeGuardResult {
  if (!livemodeKnown) {
    return { disposition: "retry", status: 500, retryable: true, notifyAdmins: true };
  }
  const disposition = eventModeDisposition(eventLivemode, configuredLivemode);
  if (disposition === "ok") {
    return { disposition, status: 200, retryable: false, notifyAdmins: false };
  }
  if (disposition === "retry") {
    return { disposition, status: 500, retryable: true, notifyAdmins: true };
  }
  return { disposition, status: 200, retryable: false, notifyAdmins: true };
}

/// Throws PaymongoModeMismatchError unless the key's mode is the one
/// PAYMONGO_LIVEMODE asks for. Returns the agreed mode.
export function assertPaymongoModeMatch(): PaymongoMode {
  const keyMode = paymongoKeyMode();
  const configuredMode = paymongoConfiguredMode();
  if (keyMode !== configuredMode) {
    throw new PaymongoModeMismatchError(keyMode, configuredMode);
  }
  return keyMode;
}

// ────────────────────────────────────────────────────────────────
// CURRENT FLOW — GCash via Checkout Sessions (attempt #6)
// ────────────────────────────────────────────────────────────────

export interface GcashCheckoutSession {
  checkoutSessionId: string; // cs_xxx
  clientKey: string;         // cs_xxx_client_…
  checkoutUrl: string;       // https://checkout.paymongo.com/cs_xxx#…
}

export interface CheckoutSessionLineItem {
  name: string;
  /** Amount PER UNIT in centavos. */
  amount: number;
  quantity: number;
}

/// Create a hosted Checkout Session for GCash.
/// @param lineItems - what the customer sees on the hosted page (items,
///                    delivery fee, and the Model B GCash fee line)
/// @param successUrl / cancelUrl - deep links the customer returns to
///                    after completing/aborting the GCash authorization
/// @param metadata - string-keyed reconciliation data (order id, etc.)
export async function createGcashCheckoutSession(
  lineItems: CheckoutSessionLineItem[],
  successUrl: string,
  cancelUrl: string,
  description: string,
  metadata: Record<string, string>,
): Promise<GcashCheckoutSession> {
  // Chokepoint: no caller can create a session in the wrong mode.
  assertPaymongoModeMatch();

  const body = {
    data: {
      attributes: {
        line_items: lineItems.map((it) => ({
          name: it.name,
          amount: it.amount,
          currency: "PHP",
          quantity: it.quantity,
        })),
        payment_method_types: ["gcash"],
        success_url: successUrl,
        cancel_url: cancelUrl,
        description,
        metadata,
        send_email_receipt: false,
        show_line_items: true,
      },
    },
  };
  const res = await fetch(`${PAYMONGO_BASE_URL}/checkout_sessions`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": getSecretAuthHeader(),
    },
    body: JSON.stringify(body),
  });
  if (!res.ok) {
    throw new Error(
      `PayMongo createCheckoutSession error (${res.status}): ${await res.text()}`,
    );
  }
  const data = (await res.json()).data;
  const attrs = data?.attributes ?? {};
  const checkoutUrl: string = attrs.checkout_url ?? "";
  const clientKey: string = attrs.client_key ?? "";
  const checkoutSessionId: string = data?.id ?? "";
  if (!checkoutUrl || !clientKey || !checkoutSessionId) {
    console.error("[PAYMONGO] Incomplete checkout session response:", JSON.stringify(attrs));
    throw new Error("PayMongo did not return a complete checkout session");
  }
  return { checkoutSessionId, clientKey, checkoutUrl };
}

/// Server-side retrieval of a Checkout Session (secret key required).
/// Used by the webhook as a FALLBACK when a checkout_session event
/// payload does not embed payments[] / payment_intent — PayMongo's
/// own docs recommend retrieving the resource as the rollback
/// mechanism, and the payments attribute is only returned to
/// secret-key callers.
export async function fetchCheckoutSessionById(
  checkoutSessionId: string,
): Promise<{ payments: any[]; paymentIntentId: string }> {
  const res = await fetch(
    `${PAYMONGO_BASE_URL}/checkout_sessions/${checkoutSessionId}`,
    { headers: { "Authorization": getSecretAuthHeader() } },
  );
  if (!res.ok) {
    throw new Error(
      `PayMongo fetchCheckoutSession error (${res.status}): ${await res.text()}`,
    );
  }
  const data = (await res.json()).data;
  const attrs = data?.attributes ?? {};
  return {
    payments: Array.isArray(attrs.payments) ? attrs.payments : [],
    paymentIntentId: (attrs.payment_intent?.id as string) ??
      (attrs.payment_intent_id as string) ?? "",
  };
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
// WEBHOOK SIGNATURE VERIFICATION (mandatory — task brief §3.2)
//
// Header: Paymongo-Signature: t=<unix_ts>,te=<test sig>,li=<live sig>
// Signed string:  "<timestamp>.<raw JSON body>" (exact bytes)
// Algorithm:      HMAC-SHA256, hex digest, key = webhook secret (whsk_…)
// Replay guard:   timestamps older than 10 minutes are rejected.
// There is NO bypass flag and no "skip in dev" path.
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
  // PayMongo includes BOTH te (test-mode) and li (live-mode) parts; exactly
  // one is populated depending on the event's mode — the other is present
  // but EMPTY (e.g. "t=…,te=abc,li="). Use ?? only after treating empty
  // strings as absent: an empty li must fall through to te, or every
  // test-mode event is rejected (incident 2026-09-07).
  const providedLive = parts.get("li");
  const providedTest = parts.get("te");
  const provided =
    providedLive && providedLive.length > 0 ? providedLive : providedTest;
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
// EVENT PARSING (attempt #6 — handles both checkout_session.* and
// payment.* payload shapes)
//
// PayMongo envelope:  { data: { id: evt_xxx, type: "event",
//                       attributes: { type: "<event.type>", livemode,
//                                     data: { id: <resource id>,
//                                             type, attributes: {...} } } } }
//   • checkout_session.payment.paid → resource = the checkout session
//     (id cs_xxx; attributes.payments[] with the paid payment; and
//     attributes.payment_intent with the pi_xxx).
//   • payment.paid / payment.failed → resource = the payment object
//     (id pay_xxx; attributes.amount + payment_intent_id pi_xxx).
// ────────────────────────────────────────────────────────────────

export interface PayMongoEvent {
  /// Event id (evt_xxx) — the idempotency key.
  id: string;
  /// Event type (checkout_session.payment.paid, payment.paid, …).
  type: string;
  /// `attributes.livemode`, defaulting to false only when it is ABSENT.
  /// Never trust `livemode` alone for a security decision — pair it with
  /// `livemodeKnown`, which distinguishes "test mode" from "the payload
  /// did not say" (a forged/truncated body, or a new PayMongo shape).
  livemode: boolean;
  /// True only when the payload carried a boolean `livemode`.
  livemodeKnown: boolean;
  /// The resource embedded in the event.
  data: {
    id: string;          // resource id (cs_xxx | pay_xxx)
    type: string;
    attributes: Record<string, unknown>;
  };
  /// Redaction-friendly summary (no payment-method/wallet details).
  redacted: Record<string, unknown>;
}

export function parseWebhookEvent(body: string): PayMongoEvent {
  const parsed = JSON.parse(body);
  const attributes = parsed?.data?.attributes ?? {};
  const resource = attributes?.data ?? {};

  const rawLivemode = attributes?.livemode;
  return {
    id: parsed?.data?.id ?? "",
    type: attributes?.type ?? "",
    livemode: rawLivemode === true,
    livemodeKnown: typeof rawLivemode === "boolean",
    data: {
      id: resource?.id ?? "",
      type: resource?.type ?? "",
      attributes: resource?.attributes ?? {},
    },
    redacted: {
      event_id: parsed?.data?.id ?? "",
      type: attributes?.type ?? "",
      livemode: attributes?.livemode ?? false,
      livemode_known: typeof rawLivemode === "boolean",
      resource_id: resource?.id ?? "",
      resource_type: resource?.type ?? "",
      status: resource?.attributes?.status ?? null,
    },
  };
}

/** Resource attributes as a plain record. */
export function resourceAttrs(event: PayMongoEvent): Record<string, any> {
  return event.data.attributes as Record<string, any>;
}

/// Payment id (pay_xxx) from a payment.* or checkout_session.* event.
export function extractPaymentId(event: PayMongoEvent): string {
  const attrs = resourceAttrs(event);
  if (event.data.type === "checkout_session") {
    const payments = Array.isArray(attrs.payments) ? attrs.payments : [];
    const first = payments[0] as any;
    return (first?.id as string) ?? "";
  }
  return event.data.id; // payment.* → resource is the payment itself
}

/// Payment Intent id (pi_xxx) — checkout sessions embed it post-payment.
export function extractPaymentIntentId(event: PayMongoEvent): string {
  const attrs = resourceAttrs(event);
  if (event.data.type === "checkout_session") {
    return (attrs.payment_intent?.id as string) ??
      (attrs.payment_intent_id as string) ?? "";
  }
  return (attrs.payment_intent_id as string) ??
    (attrs.payment_intent?.id as string) ?? "";
}

/// Charged amount in CENTAVOS for the payment event.
export function extractAmountCents(event: PayMongoEvent): number {
  const attrs = resourceAttrs(event);
  if (event.data.type === "checkout_session") {
    const payments = Array.isArray(attrs.payments) ? attrs.payments : [];
    const first = payments[0] as any;
    return Number(first?.attributes?.amount ?? 0);
  }
  return Number(attrs.amount ?? 0);
}

/// Sum of PayMongo's ACTUAL fees for the payment, in PESOS (each fee
/// entry is in centavos). NULL when the payload carries no fee data —
/// callers must store null, never a fabricated estimate. Only paid
/// payment events carry fees; failure/expiry/cancel audit rows return
/// null.
export function extractPaymongoFeePesos(event: PayMongoEvent): number | null {
  const attrs = resourceAttrs(event);
  const payments = event.data.type === "checkout_session"
    ? (Array.isArray(attrs.payments) ? (attrs.payments as any[]) : [])
    : [event.data];
  let totalCents = 0;
  let found = false;
  for (const p of payments) {
    const fees = (p as any)?.attributes?.fees;
    if (!Array.isArray(fees)) continue;
    for (const f of fees) {
      const amt = Number((f as any)?.amount);
      if (Number.isFinite(amt) && amt > 0) {
        totalCents += amt;
        found = true;
      }
    }
  }
  return found ? Math.round(totalCents) / 100 : null;
}

/// E-wallet reference number for the payment (GCash ref from
/// payment_method_details), when the payload exposes it. NULL otherwise
/// — the reference column stays unset and the admin UI shows "—".
export function extractGcashReference(event: PayMongoEvent): string | null {
  const attrs = resourceAttrs(event);
  const candidates = event.data.type === "checkout_session"
    ? (Array.isArray(attrs.payments)
        ? (attrs.payments as any[]).map((p) => (p as any)?.attributes)
        : [])
    : [attrs];
  for (const a of candidates) {
    const details = (a as any)?.payment_method_details;
    if (!details || typeof details !== "object") continue;
    const ref = details?.gcash?.ref ?? details?.ewallet?.ref;
    if (typeof ref === "string" && ref.trim()) return ref.trim();
  }
  return null;
}

// ────────────────────────────────────────────────────────────────
// LEGACY — attempt #4 e-wallet redirect (dormant). Kept so the
// dormant `create-gcash-payment-intent`-era code still compiles.
// NOT used by the live flow. Do not extend.
// ────────────────────────────────────────────────────────────────

export interface GcashRedirectPayment {
  paymentIntentId: string;
  paymentMethodId: string;
  clientKey: string;
  checkoutUrl: string;
}

/// Full e-wallet flow: create intent (gcash) → create gcash method →
/// attach with return_url → return the redirect URL for the customer.
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
