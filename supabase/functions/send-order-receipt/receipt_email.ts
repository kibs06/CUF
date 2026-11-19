// supabase/functions/send-order-receipt/receipt_email.ts
//
// The email that carries the receipt: subject, HTML body, and the plain-text
// alternative. Kept apart from the handler so the wording can be read (and
// tested) without booting SMTP or a database.

import type { ReceiptData } from "./receipt_pdf.ts";

const BRAND = "#6B4226";
const INK = "#2A1B10";
const MUTED = "#8A7A68";
const RULE = "#EDE4DA";
const CANVAS = "#FAF6F0";

function peso(value: number): string {
  const n = Number.isFinite(value) ? value : 0;
  return "\u20b1" + n.toLocaleString("en-PH", {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });
}

function escapeHtml(value: string): string {
  return (value ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function dateLabel(at: Date): string {
  return at.toLocaleString("en-PH", {
    timeZone: "Asia/Manila",
    month: "short",
    day: "numeric",
    year: "numeric",
    hour: "numeric",
    minute: "2-digit",
  });
}

/** order_items.size is stored as "Size 9"; a bare "9" still reads right. */
function sizeLabel(size: string): string {
  const value = (size ?? "").trim();
  if (!value) return "";
  return value.toLowerCase().startsWith("size") ? value : `Size ${value}`;
}

function paymentLabel(method: string): string {
  const value = (method ?? "").toLowerCase();
  if (value === "cash") return "Cash";
  if (value === "gcash") return "GCash";
  if (value === "cod") return "Cash on delivery";
  if (!value) return "Not recorded";
  return value.charAt(0).toUpperCase() + value.slice(1);
}

/** The subject line both the inbox and the attachment filename lean on. */
export function receiptSubject(data: ReceiptData): string {
  const store = data.store.name || "CUFMAI";
  return `Receipt #${data.order.orderCode} from ${store}`;
}

/** Attachment name; kept simple so mail clients show it cleanly. */
export function receiptFilename(data: ReceiptData): string {
  return `receipt-${data.order.orderCode}.pdf`;
}

/** HTML body. Tables and inline styles only — mail clients are not browsers. */
export function receiptHtml(data: ReceiptData): string {
  const rows = data.lines.map((item) => {
    const size = sizeLabel(item.size);
    const name = size ? `${item.name} (${size})` : item.name;
    return `
      <tr>
        <td style="padding:8px 0;color:${INK};font-size:14px;">
          <span style="color:${MUTED};">${item.quantity}&times;</span>
          ${escapeHtml(name)}
        </td>
        <td align="right" style="padding:8px 0;color:${INK};font-size:14px;white-space:nowrap;">
          ${peso(item.unitPrice * item.quantity)}
        </td>
      </tr>`;
  }).join("");

  const subtotalRow = data.order.subtotal != null
    ? `<tr>
         <td style="padding:4px 0;color:${MUTED};font-size:13px;">Subtotal</td>
         <td align="right" style="padding:4px 0;color:${INK};font-size:13px;">${peso(data.order.subtotal)}</td>
       </tr>`
    : "";

  const discountRow = data.order.discount != null && data.order.discount > 0
    ? `<tr>
         <td style="padding:4px 0;color:${MUTED};font-size:13px;">Discount${
      data.order.voucherCode ? ` (${escapeHtml(data.order.voucherCode)})` : ""
    }</td>
         <td align="right" style="padding:4px 0;color:${INK};font-size:13px;">-${peso(data.order.discount)}</td>
       </tr>`
    : "";

  const referenceRow = data.order.gcashReference
    ? `<tr>
         <td style="padding:4px 0;color:${MUTED};font-size:13px;">GCash reference</td>
         <td align="right" style="padding:4px 0;color:${INK};font-size:13px;">${escapeHtml(data.order.gcashReference)}</td>
       </tr>`
    : "";

  return `<!doctype html>
<html>
  <body style="margin:0;padding:24px;background:${CANVAS};font-family:Helvetica,Arial,sans-serif;">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:520px;margin:0 auto;background:#FFFFFF;border-radius:16px;overflow:hidden;border:1px solid ${RULE};">
      <tr>
        <td style="padding:24px 24px 16px;">
          <p style="margin:0;color:${BRAND};font-size:12px;letter-spacing:2px;text-transform:uppercase;">${escapeHtml(data.store.name || "CUFMAI")}</p>
          ${data.store.location ? `<p style="margin:4px 0 0;color:${MUTED};font-size:12px;">${escapeHtml(data.store.location)}</p>` : ""}
          <h1 style="margin:16px 0 4px;color:${INK};font-size:22px;">Your receipt</h1>
          <p style="margin:0;color:${MUTED};font-size:13px;">
            Order #${escapeHtml(data.order.orderCode)} &middot; ${escapeHtml(dateLabel(data.order.createdAt))}
          </p>
          ${data.customerName ? `<p style="margin:6px 0 0;color:${MUTED};font-size:13px;">For ${escapeHtml(data.customerName)}</p>` : ""}
        </td>
      </tr>
      <tr><td style="padding:0 24px;"><div style="height:1px;background:${RULE};"></div></td></tr>
      <tr>
        <td style="padding:16px 24px 0;">
          <table role="presentation" width="100%" cellpadding="0" cellspacing="0">
            ${rows || `<tr><td style="padding:8px 0;color:${MUTED};font-size:13px;">No line items were recorded for this order.</td></tr>`}
          </table>
        </td>
      </tr>
      <tr>
        <td style="padding:8px 24px 0;">
          <table role="presentation" width="100%" cellpadding="0" cellspacing="0">
            ${subtotalRow}
            ${discountRow}
            <tr>
              <td style="padding:10px 0 0;color:${INK};font-size:15px;font-weight:bold;">Total</td>
              <td align="right" style="padding:10px 0 0;color:${INK};font-size:15px;font-weight:bold;">${peso(data.order.total)}</td>
            </tr>
            <tr>
              <td style="padding:4px 0;color:${MUTED};font-size:13px;">Paid via</td>
              <td align="right" style="padding:4px 0;color:${INK};font-size:13px;">${escapeHtml(paymentLabel(data.order.paymentMethod))}</td>
            </tr>
            ${referenceRow}
            <tr>
              <td style="padding:4px 0;color:${MUTED};font-size:13px;">Fulfilment</td>
              <td align="right" style="padding:4px 0;color:${INK};font-size:13px;">${
    (data.order.fulfillment ?? "").toLowerCase() === "delivery"
      ? "Delivery"
      : "Store pickup"
  }</td>
            </tr>
          </table>
        </td>
      </tr>
      <tr>
        <td style="padding:20px 24px 24px;">
          <p style="margin:0;color:${MUTED};font-size:12px;line-height:1.6;">
            The same receipt is attached as a PDF. Keep it as your proof of
            purchase and quote order #${escapeHtml(data.order.orderCode)} if you
            need help with this order.
          </p>
        </td>
      </tr>
    </table>
    <p style="max-width:520px;margin:16px auto 0;color:${MUTED};font-size:11px;text-align:center;">
      CUFMAI Marketplace &middot; this is an automated message, please do not reply.
    </p>
  </body>
</html>`;
}

/** Plain-text alternative, for clients that refuse HTML. */
export function receiptText(data: ReceiptData): string {
  const lines = data.lines.map((item) => {
    const size = sizeLabel(item.size);
    const name = size ? `${item.name} (${size})` : item.name;
    return `${item.quantity} x ${name} - ${peso(item.unitPrice * item.quantity)}`;
  });
  return [
    data.store.name || "CUFMAI",
    data.store.location,
    "",
    `SALES RECEIPT - #${data.order.orderCode}`,
    dateLabel(data.order.createdAt),
    data.customerName ? `For ${data.customerName}` : "",
    "",
    ...lines,
    "",
    data.order.subtotal != null ? `Subtotal: ${peso(data.order.subtotal)}` : "",
    data.order.discount != null && data.order.discount > 0
      ? `Discount: -${peso(data.order.discount)}`
      : "",
    `TOTAL: ${peso(data.order.total)}`,
    `Paid via: ${paymentLabel(data.order.paymentMethod)}`,
    data.order.gcashReference ? `GCash ref: ${data.order.gcashReference}` : "",
    "",
    `Keep this email as your proof of purchase - quote #${data.order.orderCode} if you need help.`,
  ].filter((line) => line !== "").join("\n");
}
