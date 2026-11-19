// supabase/functions/send-bulk-deposit-receipt/index.ts
//
// Supabase Edge Function: email the customer their receipt when a store
// verifies and confirms their bulk-reservation deposit.
//
// A wholesale hold is money, and until now the only proof it was received was
// a push saying "deposit confirmed" — nothing the customer could keep, forward
// to their own books, or show if a balance was ever disputed. This is the same
// receipt an online order gets: the A5 slip as a PDF attachment plus the same
// facts inline in the body, over the same Gmail SMTP channel
// (`_shared/smtp.ts`) that `send-order-receipt` uses.
//
// Called by: the seller's app, right after `confirm_bulk_reservation_deposit`
// succeeds (`ReservationService.confirmDeposit`). It arrives with the seller's
// own session — exactly like the deposit-confirmation push — so no Vault entry
// and no DB trigger is needed; a fresh project works as soon as the function is
// deployed and GMAIL_SENDER / GMAIL_APP_PASSWORD exist (they already do).
//
// Authorization: the gateway verifies the JWT (`verify_jwt` stays on), and the
// function then requires the caller to own the reservation's store, or to be an
// admin. The service-role key is trusted outright, for a server-side repair.
// An anon key is also a valid JWT, so the gateway check alone proves nothing.
//
// Idempotent: `bulk_reservations.deposit_receipt_emailed_at` (migration
// 20261119235000) is stamped only after SMTP accepts the message, and a row
// that already carries it is skipped unless `force: true`. A retry therefore
// cannot mail the customer twice. On a server without those columns the send
// still works — it just cannot dedupe, and says so in the log.
//
// Secrets required (already set for the other mail senders):
//   - GMAIL_SENDER        the app's Gmail address
//   - GMAIL_APP_PASSWORD  a 16-char App Password for it
//
// Deploy: supabase functions deploy send-bulk-deposit-receipt

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { SmtpClient } from "../_shared/smtp.ts";
import {
  buildBulkDepositReceiptPdf,
  bulkReceiptFilename,
  bulkReceiptHtml,
  bulkReceiptSubject,
  bulkReceiptText,
  type BulkReceipt,
  type BulkReceiptSize,
} from "./receipt.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

interface ReceiptRequest {
  reservation_id?: string;
  /** Build the receipt but send nothing — used to check the PDF locally. */
  dry_run?: boolean;
  /** Re-send even though deposit_receipt_emailed_at is already set. */
  force?: boolean;
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

/** The bearer token as sent, without the scheme. */
function bearerToken(req: Request): string | null {
  const header = req.headers.get("Authorization") ?? "";
  const token = header.replace(/^Bearer\s+/i, "").trim();
  return token || null;
}

/** The role claim of the bearer token; only the service key may skip the check. */
function bearerRole(req: Request): string | null {
  const token = bearerToken(req);
  if (!token) return null;
  const parts = token.split(".");
  if (parts.length !== 3) return null;
  try {
    const padded = parts[1].replace(/-/g, "+").replace(/_/g, "/");
    const payload = JSON.parse(atob(padded));
    return typeof payload?.role === "string" ? payload.role : null;
  } catch {
    return null;
  }
}

/** `BR-XXXXXXXX` — the code the customer quotes; the row keeps the full uuid. */
function receiptCode(id: string): string {
  const compact = (id ?? "").replace(/-/g, "").toUpperCase();
  return `BR-${compact.slice(0, 8) || "UNKNOWN"}`;
}

function asDate(value: unknown): Date | null {
  if (value == null) return null;
  const at = new Date(String(value));
  return Number.isNaN(at.getTime()) ? null : at;
}

/**
 * The size breakdown, labelled the way the app labels it: `EU: 35`, prefixed
 * with the colour when the request named one. A size that already carries its
 * scale is left alone rather than becoming `EU: EU 35`.
 */
function sizeRows(raw: unknown): BulkReceiptSize[] {
  if (!Array.isArray(raw)) return [];
  return raw
    .filter((entry) => entry && typeof entry === "object")
    .map((entry) => {
      const row = entry as Record<string, unknown>;
      const colour = String(row.color ?? "").trim();
      const rawSize = String(row.size ?? "").trim();
      const size = rawSize === ""
        ? "Size"
        : (rawSize.toUpperCase().startsWith("EU") ? rawSize : `EU: ${rawSize}`);
      return {
        label: colour ? `${colour} \u00b7 ${size}` : size,
        quantity: String(row.quantity ?? "").trim(),
      };
    });
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const token = bearerToken(req);
  const isServiceCall = bearerRole(req) === "service_role";
  if (!isServiceCall && !token) {
    return json({ error: "Missing bearer token" }, 401);
  }

  let payload: ReceiptRequest;
  try {
    payload = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  const reservationId = (payload.reservation_id ?? "").trim();
  if (!reservationId) {
    return json({ error: "Missing required field: reservation_id" }, 400);
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );

  // Who is asking. A service-role call is trusted (it already passed the
  // gateway); anyone else must prove a real session here rather than being
  // trusted from an unverified token.
  let callerId: string | null = null;
  if (!isServiceCall) {
    const { data: caller, error: callerError } = await supabase.auth.getUser(
      token!,
    );
    if (callerError || !caller?.user) {
      return json({ error: "Invalid or expired session" }, 401);
    }
    callerId = caller.user.id;
  }

  // ── the reservation ─────────────────────────────────────────────
  const { data: reservation, error: reservationError } = await supabase
    .from("bulk_reservations")
    // One string literal, not a concatenation: supabase-js only infers the row
    // type from a literal select, and a joined string falls back to
    // GenericStringError.
    .select(
      "id, customer_id, store_id, product_id, quantity, requested_sizes, note, status, deposit_amount, deposit_status, deposit_deadline, deposit_paid_at, expires_at, deposit_proof_id, created_at, voucher_code, voucher_discount",
    )
    .eq("id", reservationId)
    .maybeSingle();

  if (reservationError) {
    console.error(
      "[BulkDepositReceipt] Reservation lookup failed:",
      reservationError.message,
    );
    return json(
      { error: "Reservation lookup failed", detail: reservationError.message },
      500,
    );
  }
  if (!reservation) {
    return json({ error: `Reservation ${reservationId} does not exist` }, 404);
  }

  // Money only changes hands at confirmation; before that there is no deposit
  // to receipt, and after a rejection there is nothing the store received.
  if (reservation.deposit_status !== "paid") {
    return json({
      sent: false,
      reason: "deposit_not_paid",
      reservation_code: receiptCode(reservation.id as string),
    }, 409);
  }

  // A seller may only email the customer of their own store. Admins keep the
  // same access they have everywhere else in the portal.
  if (callerId) {
    const { data: storeOwner } = await supabase
      .from("stores")
      .select("owner_id")
      .eq("id", reservation.store_id as string)
      .maybeSingle();
    let allowed = (storeOwner?.owner_id as string | undefined) === callerId;
    if (!allowed) {
      const { data: callerProfile } = await supabase
        .from("profiles")
        .select("role")
        .eq("id", callerId)
        .maybeSingle();
      allowed = callerProfile?.role === "admin";
    }
    if (!allowed) {
      return json(
        {
          error:
            "Only the store that holds this reservation can email its receipt",
        },
        403,
      );
    }
  }

  // The stamp arrives with migration 20261119235000. Read it on its own so a
  // server without it still sends the receipt (it just cannot dedupe).
  let emailedAt: string | null = null;
  let stampSupported = false;
  try {
    const { data: stampRow, error: stampError } = await supabase
      .from("bulk_reservations")
      .select("deposit_receipt_emailed_at")
      .eq("id", reservationId)
      .maybeSingle();
    if (stampError) {
      console.warn(
        "[BulkDepositReceipt] Receipt stamp not readable (migration " +
          "20261119235000 unapplied?):",
        stampError.message,
      );
    } else {
      stampSupported = true;
      emailedAt = (stampRow as { deposit_receipt_emailed_at?: string | null } |
        null)?.deposit_receipt_emailed_at ?? null;
    }
  } catch (e) {
    console.warn("[BulkDepositReceipt] Receipt stamp check failed:", e);
  }

  if (emailedAt && !payload.force) {
    return json({
      sent: false,
      reason: "already_sent",
      reservation_code: receiptCode(reservation.id as string),
    });
  }

  // ── the facts on the receipt ────────────────────────────────────
  const [{ data: store }, { data: customer }, { data: product }] =
    await Promise.all([
      supabase
        .from("stores")
        .select("name, location, contact_number")
        .eq("id", reservation.store_id as string)
        .maybeSingle(),
      reservation.customer_id
        ? supabase
          .from("profiles")
          .select("full_name, email")
          .eq("id", reservation.customer_id as string)
          .maybeSingle()
        : Promise.resolve({ data: null }),
      reservation.product_id
        ? supabase
          .from("products")
          .select("name")
          .eq("id", reservation.product_id as string)
          .maybeSingle()
        : Promise.resolve({ data: null }),
    ]);

  // The proof the store verified: the reference the customer typed is what
  // makes this receipt checkable against the store's own GCash history.
  let reference: string | null = null;
  let proofSubmittedAt: Date | null = null;
  try {
    const { data: proof } = await supabase
      .from("bulk_reservation_deposits")
      .select("reference_number, submitted_at")
      .eq("reservation_id", reservationId)
      .maybeSingle();
    reference = (proof?.reference_number as string | undefined) ?? null;
    proofSubmittedAt = asDate(proof?.submitted_at);
  } catch (e) {
    console.warn("[BulkDepositReceipt] Proof lookup failed:", e);
  }

  const address = ((customer?.email as string | undefined) ?? "").trim();
  if (!address) {
    return json({
      sent: false,
      reason: "no_email",
      reservation_code: receiptCode(reservation.id as string),
    });
  }

  const data: BulkReceipt = {
    store: {
      name: (store?.name as string) ?? "CUFMAI",
      location: (store?.location as string) ?? "",
      contact: (store?.contact_number as string | undefined) ?? null,
    },
    reservation: {
      code: receiptCode(reservation.id as string),
      requestedAt: asDate(reservation.created_at) ?? new Date(),
      paidAt: asDate(reservation.deposit_paid_at),
      quantity: Number(reservation.quantity ?? 0),
      productName: (product?.name as string) ?? "",
      sizes: sizeRows(reservation.requested_sizes),
      deposit: Number(reservation.deposit_amount ?? 0),
      voucherCode: (reservation.voucher_code as string | undefined) ?? null,
      voucherDiscount: reservation.voucher_discount == null
        ? null
        : Number(reservation.voucher_discount),
      reference,
      proofSubmittedAt,
      heldUntil: asDate(reservation.expires_at),
    },
    customerName: ((customer?.full_name as string | undefined) ?? "").trim(),
    customerEmail: address,
  };

  // ── the receipt itself ──────────────────────────────────────────
  let pdf: Uint8Array;
  try {
    pdf = await buildBulkDepositReceiptPdf(data);
  } catch (e) {
    console.error("[BulkDepositReceipt] PDF build failed:", e);
    return json({
      error: "Could not build the receipt PDF",
      detail: e instanceof Error ? e.message : String(e),
    }, 500);
  }

  const subject = bulkReceiptSubject(data);
  const html = bulkReceiptHtml(data);

  if (payload.dry_run) {
    return json({
      sent: false,
      reason: "dry_run",
      to: address,
      reservation_code: data.reservation.code,
      subject,
      pdf_bytes: pdf.byteLength,
      html_bytes: new TextEncoder().encode(html).byteLength,
      text_preview: bulkReceiptText(data).slice(0, 400),
      pdf_base64: btoa(String.fromCharCode(...pdf)),
    });
  }

  const gmailSender = Deno.env.get("GMAIL_SENDER");
  const gmailAppPassword = Deno.env.get("GMAIL_APP_PASSWORD");
  if (!gmailSender || !gmailAppPassword) {
    console.error(
      "[BulkDepositReceipt] Missing GMAIL_SENDER / GMAIL_APP_PASSWORD",
    );
    return json({
      sent: false,
      reason: "email_not_configured",
      reservation_code: data.reservation.code,
    }, 500);
  }

  const smtp = new SmtpClient();
  try {
    await smtp.connectTLS({
      hostname: "smtp.gmail.com",
      port: 465,
      username: gmailSender,
      password: gmailAppPassword,
    });
    await smtp.send({
      from: gmailSender,
      to: address,
      subject,
      html,
      attachments: [{
        filename: bulkReceiptFilename(data),
        contentType: "application/pdf",
        bytes: pdf,
      }],
    });
  } catch (e) {
    console.error("[BulkDepositReceipt] SMTP send failed:", e);
    return json({
      sent: false,
      reason: "smtp_failed",
      detail: e instanceof Error ? e.message : String(e),
      reservation_code: data.reservation.code,
    }, 502);
  } finally {
    await smtp.close();
  }

  // The stamp is what makes a retry a no-op. Losing it (an un-migrated server)
  // must not undo a send that already happened, so the failure is logged only.
  if (stampSupported) {
    try {
      const { error } = await supabase
        .from("bulk_reservations")
        .update({
          deposit_receipt_emailed_at: new Date().toISOString(),
          deposit_receipt_email_to: address,
        })
        .eq("id", reservationId);
      if (error) {
        console.warn(
          "[BulkDepositReceipt] Could not stamp the receipt:",
          error.message,
        );
      }
    } catch (e) {
      console.warn("[BulkDepositReceipt] Could not stamp the receipt:", e);
    }
  }

  return json({
    sent: true,
    to: address,
    reservation_code: data.reservation.code,
    pdf_bytes: pdf.byteLength,
  });
});
