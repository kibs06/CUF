// Shared PayMongo API helpers for Edge Functions
// QR Ph Payment Intent flow — produces genuine BSP-standard QR codes

const PAYMONGO_BASE_URL = 'https://api.paymongo.com/v1';

/// Get Basic Auth header using the secret key (server-side only)
export function getSecretAuthHeader(): string {
  const secretKey = Deno.env.get('PAYMONGO_SECRET_KEY');
  if (!secretKey) {
    throw new Error('PAYMONGO_SECRET_KEY not configured');
  }
  const encoded = btoa(`${secretKey}:`);
  return `Basic ${encoded}`;
}

/// Step 1: Create a Payment Intent with qrph in payment_method_allowed
/// @param amount - Amount in PHP (will be converted to centavos)
/// @param description - Payment description
/// @returns Payment Intent ID and client_key
export async function createPaymentIntent(
  amount: number,
  description: string,
): Promise<{
  id: string;
  clientKey: string;
  status: string;
}> {
  const amountInCentavos = Math.round(amount * 100);

  const response = await fetch(`${PAYMONGO_BASE_URL}/payment_intents`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': getSecretAuthHeader(),
    },
    body: JSON.stringify({
      data: {
        attributes: {
          amount: amountInCentavos,
          currency: 'PHP',
          payment_method_allowed: ['qrph'],
          description,
        },
      },
    }),
  });

  if (!response.ok) {
    const errorBody = await response.text();
    throw new Error(`PayMongo createPaymentIntent error (${response.status}): ${errorBody}`);
  }

  const result = await response.json();
  const pi = result.data;

  return {
    id: pi.id,
    clientKey: pi.attributes?.client_key || '',
    status: pi.attributes?.status || 'awaiting_next_action',
  };
}

/// Step 2: Create a Payment Method with type: qrph
/// @returns Payment Method ID
export async function createQrPhPaymentMethod(): Promise<string> {
  const response = await fetch(`${PAYMONGO_BASE_URL}/payment_methods`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': getSecretAuthHeader(),
    },
    body: JSON.stringify({
      data: {
        attributes: {
          type: 'qrph',
        },
      },
    }),
  });

  if (!response.ok) {
    const errorBody = await response.text();
    throw new Error(`PayMongo createPaymentMethod error (${response.status}): ${errorBody}`);
  }

  const result = await response.json();
  return result.data?.id || '';
}

/// Step 3: Attach Payment Method to Payment Intent
/// Returns the QR Ph image (base64-encoded) from next_action.code.image_url
export async function attachPaymentMethod(
  paymentIntentId: string,
  paymentMethodId: string,
  clientKey: string,
): Promise<{
  qrImageBase64: string;
  status: string;
}> {
  const response = await fetch(
    `${PAYMONGO_BASE_URL}/payment_intents/${paymentIntentId}/attach`,
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': getSecretAuthHeader(),
      },
      body: JSON.stringify({
        data: {
          attributes: {
            payment_method: paymentMethodId,
            client_key: clientKey,
          },
        },
      }),
    },
  );

  if (!response.ok) {
    const errorBody = await response.text();
    throw new Error(`PayMongo attachPaymentMethod error (${response.status}): ${errorBody}`);
  }

  const result = await response.json();
  const attrs = result.data?.attributes || {};

  // Log the full response structure for debugging
  console.log('[PAYMONGO] Attach response status:', attrs.status);
  console.log('[PAYMONGO] next_action type:', attrs.next_action?.type);
  console.log('[PAYMONGO] next_action keys:', Object.keys(attrs.next_action || {}));
  
  // Extract the QR image from next_action
  const nextAction = attrs.next_action || {};
  const code = nextAction.code || {};
  
  // Log all possible image locations for debugging
  console.log('[PAYMONGO] code keys:', Object.keys(code));
  console.log('[PAYMONGO] code.image_url exists:', !!code.image_url);
  console.log('[PAYMONGO] code.image_url length:', code.image_url?.length || 0);
  console.log('[PAYMONGO] code.image_url starts with:', code.image_url?.substring(0, 50));
  console.log('[PAYMONGO] code.payload exists:', !!code.payload);
  console.log('[PAYMONGO] code.payload length:', code.payload?.length || 0);
  
  // image_url may be a base64 data string or a URL
  const qrImageBase64 = code.image_url || code.payload || '';

  if (!qrImageBase64) {
    console.error('[PAYMONGO] No QR image found. Full attrs:', JSON.stringify(attrs, null, 2));
    throw new Error('No QR image found in PayMongo response');
  }

  return {
    qrImageBase64,
    status: attrs.status || 'awaiting_next_action',
  };
}

/// Full QR Ph flow: create intent → create method → attach → return QR image
export async function createQrPhPayment(
  amount: number,
  description: string,
): Promise<{
  paymentIntentId: string;
  qrImageBase64: string;
}> {
  console.log(`[PAYMONGO] Creating QR Ph payment for: ${description}, amount: ₱${amount}`);

  // Step 1: Create Payment Intent
  const pi = await createPaymentIntent(amount, description);
  console.log(`[PAYMONGO] Payment Intent created: ${pi.id}, status: ${pi.status}`);

  // Step 2: Create QR Ph Payment Method
  const pmId = await createQrPhPaymentMethod();
  console.log(`[PAYMONGO] Payment Method created: ${pmId}`);

  // Step 3: Attach Payment Method to Payment Intent
  const attachResult = await attachPaymentMethod(pi.id, pmId, pi.clientKey);
  console.log(`[PAYMONGO] Payment Method attached, status: ${attachResult.status}`);

  return {
    paymentIntentId: pi.id,
    qrImageBase64: attachResult.qrImageBase64,
  };
}

/// Verify webhook signature from PayMongo
export function verifyWebhookSignature(
  payload: string,
  signature: string,
): boolean {
  // TODO: Implement proper HMAC verification with PAYMONGO_WEBHOOK_SECRET
  // For now, accept all requests in test mode
  console.log('[WEBHOOK] Signature verification skipped (TODO: implement HMAC)');
  return true;
}

/// Parse PayMongo webhook event
export interface PayMongoEvent {
  type: string;
  data: {
    id: string;
    attributes: Record<string, any>;
  };
}

export function parseWebhookEvent(body: string): PayMongoEvent {
  const parsed = JSON.parse(body);
  return {
    type: parsed.data?.attributes?.type || parsed.type || '',
    data: {
      id: parsed.data?.id || '',
      attributes: parsed.data?.attributes || {},
    },
  };
}
