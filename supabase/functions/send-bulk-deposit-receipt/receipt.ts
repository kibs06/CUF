// supabase/functions/send-bulk-deposit-receipt/receipt.ts
//
// The deposit receipt: the A5 PDF attached to the email, plus the HTML body and
// its plain-text alternative.
//
// It follows the same rules as the order receipt (`send-order-receipt/
// receipt_pdf.ts`) because it lands in the same inbox and is filed the same
// way: base Helvetica (WinAnsi, no Unicode), every string folded to Latin-1
// before it is drawn, and money written as "PHP 1,234.50" (the peso sign is not
// in WinAnsi). A customer comparing this against an order receipt should not
// be able to tell the two were written in different places.
//
// What is different is the subject matter: this is proof of a DEPOSIT on a
// reseller hold, not of a purchase. It states the amount paid, the reference
// the store verified, how long the units are held, and — in as many words as
// the slip can carry — that the deposit is non-refundable.

import {
  PDFDocument,
  PDFFont,
  StandardFonts,
  rgb,
} from "npm:pdf-lib@1.17.1";

/** One size line of the request, e.g. `EU: 38` x 4. */
export interface BulkReceiptSize {
  label: string;
  quantity: string;
}

/** Everything the receipt needs, already resolved from the database. */
export interface BulkReceipt {
  /**
   * `contact` is the shop's own line, set by the seller in Edit Store. Absent
   * for stores that have not set one, which is why it is optional.
   */
  store: { name: string; location: string; contact?: string | null };
  reservation: {
    /** `BR-XXXXXXXX`, derived from the reservation id. */
    code: string;
    requestedAt: Date;
    paidAt: Date | null;
    quantity: number;
    productName: string;
    sizes: BulkReceiptSize[];
    deposit: number;
    /** Voucher claimed when the request was made, if any. */
    voucherCode: string | null;
    voucherDiscount: number | null;
    reference: string | null;
    proofSubmittedAt: Date | null;
    heldUntil: Date | null;
  };
  customerName: string;
  customerEmail: string;
}

const BRAND = "#6B4226";
const INK = "#2A1B10";
const MUTED = "#8A7A68";
const RULE = "#EDE4DA";
const CANVAS = "#FAF6F0";
const SAGE = "#4F6B35";

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

/** `Nov 19, 2026` in Manila time — the store's clock, not the server's. */
function dateLabel(at: Date | null): string {
  if (!at || Number.isNaN(at.getTime())) return "\u2014";
  return at.toLocaleString("en-PH", {
    timeZone: "Asia/Manila",
    month: "short",
    day: "numeric",
    year: "numeric",
  });
}

/** `Nov 19, 2026, 3:04 PM` — date and time, for "paid on" and "submitted". */
function stampLabel(at: Date | null): string {
  if (!at || Number.isNaN(at.getTime())) return "\u2014";
  return at.toLocaleString("en-PH", {
    timeZone: "Asia/Manila",
    month: "short",
    day: "numeric",
    year: "numeric",
    hour: "numeric",
    minute: "2-digit",
  });
}

/** The subject line both the inbox and the attachment filename lean on. */
export function bulkReceiptSubject(data: BulkReceipt): string {
  const store = data.store.name || "CUFMAI";
  return `Deposit receipt #${data.reservation.code} from ${store}`;
}

/** Attachment name; kept simple so mail clients show it cleanly. */
export function bulkReceiptFilename(data: BulkReceipt): string {
  return `deposit-receipt-${data.reservation.code}.pdf`;
}

/**
 * Helvetica has no Unicode support: fold the few characters that would throw at
 * draw time onto their WinAnsi neighbours, and anything above U+00FF onto "?".
 * Mirrors `printable` in the order receipt.
 */
function printable(text: string): string {
  return (text ?? "")
    .replace(/\u20b1/g, "PHP ")
    .replace(/[\u2013\u2014]/g, "-")
    .replace(/[\u2018\u2019]/g, "'")
    .replace(/[\u201c\u201d]/g, '"')
    .replace(/\u00b7/g, "-")
    .replace(/\u2026/g, "...")
    .replace(/[^\x00-\xFF]/g, "?");
}

/** "PHP 1,234.50" — the slip writes currency out because of WinAnsi. */
function money(value: number): string {
  const n = Number.isFinite(value) ? value : 0;
  return "PHP " + n.toLocaleString("en-PH", {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });
}

/** Build the A5 deposit-receipt PDF. Returns the finished bytes. */
export async function buildBulkDepositReceiptPdf(
  data: BulkReceipt,
): Promise<Uint8Array> {
  const doc = await PDFDocument.create();
  const page = doc.addPage([420, 595]); // A5 portrait, in points
  const regular: PDFFont = await doc.embedFont(StandardFonts.Helvetica);
  const bold: PDFFont = await doc.embedFont(StandardFonts.HelveticaBold);

  const ink = rgb(0.16, 0.11, 0.07);
  const muted = rgb(0.45, 0.38, 0.31);
  const rule = rgb(0.85, 0.8, 0.74);

  const left = 36;
  const right = 420 - 36;
  let y = 595 - 44;

  const text = (
    value: string,
    opts: {
      x?: number;
      size?: number;
      font?: PDFFont;
      color?: ReturnType<typeof rgb>;
      align?: "left" | "right";
    } = {},
  ) => {
    const size = opts.size ?? 9;
    const font = opts.font ?? regular;
    const body = printable(value);
    const width = font.widthOfTextAtSize(body, size);
    const x = opts.align === "right" ? right - width : (opts.x ?? left);
    page.drawText(body, { x, y, size, font, color: opts.color ?? ink });
  };

  const line = () => {
    page.drawLine({
      start: { x: left, y },
      end: { x: right, y },
      thickness: 0.75,
      color: rule,
    });
  };

  const row = (label: string, value: string) => {
    text(label, { size: 8.5, color: muted });
    text(value, { size: 8.5, align: "right" });
    y -= 12;
  };

  /** Wrapped paragraph; returns the next free y. */
  const paragraph = (body: string, startY: number): number => {
    const maxWidth = right - left;
    const words = printable(body).split(/\s+/);
    const lines: string[] = [];
    let current = "";
    for (const word of words) {
      const candidate = current ? `${current} ${word}` : word;
      if (regular.widthOfTextAtSize(candidate, 8) > maxWidth && current) {
        lines.push(current);
        current = word;
      } else {
        current = candidate;
      }
    }
    if (current) lines.push(current);
    let cursor = startY;
    for (const ln of lines) {
      page.drawText(ln, {
        x: left,
        y: cursor,
        size: 8,
        font: regular,
        color: muted,
      });
      cursor -= 10;
    }
    return cursor - 3;
  };

  // ── header ──────────────────────────────────────────────────────
  text(data.store.name || "CUFMAI", { size: 14, font: bold });
  y -= 15;
  if (data.store.location) {
    text(data.store.location, { size: 8.5, color: muted });
    y -= 11;
  }
  // The shop's line, not its GCash number: this slip is kept, and a customer
  // querying a peso-short transfer needs somebody to ask.
  if (data.store.contact) {
    text(`Contact ${data.store.contact}`, { size: 8.5, color: muted });
    y -= 11;
  }
  y -= 3;
  text("DEPOSIT RECEIPT", { size: 8.5, font: bold, color: muted });
  y -= 16;

  line();
  y -= 14;

  row("Receipt no.", data.reservation.code);
  row(
    "Date",
    stampLabel(data.reservation.paidAt ?? data.reservation.requestedAt),
  );
  if (data.customerName) row("Customer", data.customerName);
  row(
    "Product",
    data.reservation.productName || "Product",
  );
  row("Units", String(data.reservation.quantity));
  // Bulk holds are collected, never couriered — the slip says so in the same
  // place an order receipt says Delivery or Store pickup.
  row("Fulfilment", "Store pickup \u2014 no shipping");
  if (data.reservation.heldUntil) {
    row("Held until", dateLabel(data.reservation.heldUntil));
  }
  // The discount applies to the balance at pickup, not to the deposit that was
  // just paid — saying so avoids reading it as money handed back.
  if (data.reservation.voucherCode) {
    row(
      `Voucher ${data.reservation.voucherCode}`,
      `-${money(data.reservation.voucherDiscount ?? 0)} at pickup`,
    );
  }
  y -= 4;

  line();
  y -= 16;

  // ── sizes ───────────────────────────────────────────────────────
  text("SIZES REQUESTED", { size: 8, font: bold, color: muted });
  y -= 14;
  if (data.reservation.sizes.length > 0) {
    for (const size of data.reservation.sizes) {
      const label = printable(size.label);
      const qty = printable(size.quantity || "0");
      page.drawText(label, {
        x: left + 6,
        y,
        size: 8.5,
        font: regular,
        color: ink,
      });
      const qtyWidth = bold.widthOfTextAtSize(qty, 9);
      page.drawText(qty, {
        x: right - qtyWidth,
        y,
        size: 9,
        font: bold,
        color: ink,
      });
      const start = left + 6 + regular.widthOfTextAtSize(label, 8.5) + 6;
      const end = right - qtyWidth - 6;
      if (end > start) {
        page.drawLine({
          start: { x: start, y: y + 2.5 },
          end: { x: end, y: y + 2.5 },
          thickness: 0.5,
          color: rule,
        });
      }
      y -= 12;
    }
  } else {
    text("No size breakdown was given.", { size: 8.5, color: muted });
    y -= 12;
  }

  y -= 4;
  line();
  y -= 16;

  // ── money ───────────────────────────────────────────────────────
  text("DEPOSIT PAID", { size: 9, font: bold, color: muted });
  y -= 15;
  text(money(data.reservation.deposit), { size: 16, font: bold });
  y -= 16;
  row("Paid via", "GCash");
  if (data.reservation.reference) {
    row("GCash reference", data.reservation.reference);
  }
  if (data.reservation.proofSubmittedAt) {
    row("Proof submitted", stampLabel(data.reservation.proofSubmittedAt));
  }

  y -= 6;
  line();
  y -= 14;

  // ── the terms, in the customer's hands ──────────────────────────
  const notes = [
    data.reservation.heldUntil
      ? `The units are held for you until ${dateLabel(data.reservation.heldUntil)}.`
      : "The units are held for you.",
    "This deposit is non-refundable. Pick the units up at the store and settle the remaining balance there - bulk holds are not shipped.",
    `Keep this receipt - quote ${data.reservation.code} if you need help.`,
    `Sent to ${data.customerEmail}`,
  ];
  for (const note of notes) {
    y = paragraph(note, y);
  }

  return await doc.save();
}

/** HTML body. Tables and inline styles only — mail clients are not browsers. */
export function bulkReceiptHtml(data: BulkReceipt): string {
  const sizeRows = data.reservation.sizes
    .map(
      (size) => `
      <tr>
        <td style="padding:4px 0;color:${MUTED};font-size:13px;">${escapeHtml(size.label)}</td>
        <td align="right" style="padding:4px 0;color:${INK};font-size:13px;font-weight:bold;">${escapeHtml(size.quantity || "0")}</td>
      </tr>`,
    )
    .join("");

  const referenceRow = data.reservation.reference
    ? `<tr>
         <td style="padding:4px 0;color:${MUTED};font-size:13px;">GCash reference</td>
         <td align="right" style="padding:4px 0;color:${INK};font-size:13px;">${escapeHtml(data.reservation.reference)}</td>
       </tr>`
    : "";

  const proofRow = data.reservation.proofSubmittedAt
    ? `<tr>
         <td style="padding:4px 0;color:${MUTED};font-size:13px;">Proof submitted</td>
         <td align="right" style="padding:4px 0;color:${INK};font-size:13px;">${escapeHtml(stampLabel(data.reservation.proofSubmittedAt))}</td>
       </tr>`
    : "";

  const voucherRow = data.reservation.voucherCode
    ? `<tr>
         <td style="padding:4px 0;color:${MUTED};font-size:13px;">Voucher ${escapeHtml(data.reservation.voucherCode)}</td>
         <td align="right" style="padding:4px 0;color:${SAGE};font-size:13px;">-${peso(data.reservation.voucherDiscount ?? 0)} at pickup</td>
       </tr>`
    : "";

  const holdRow = data.reservation.heldUntil
    ? `<tr>
         <td style="padding:4px 0;color:${MUTED};font-size:13px;">Units held until</td>
         <td align="right" style="padding:4px 0;color:${INK};font-size:13px;">${escapeHtml(dateLabel(data.reservation.heldUntil))}</td>
       </tr>`
    : "";

  // Bulk holds are collected at the store; there is no shipping leg to
  // describe, and the receipt is the document a customer keeps.
  const fulfilmentRow = `<tr>
         <td style="padding:4px 0;color:${MUTED};font-size:13px;">Fulfilment</td>
         <td align="right" style="padding:4px 0;color:${INK};font-size:13px;">Store pickup \u2014 no shipping</td>
       </tr>`;

  return `<!doctype html>
<html>
  <body style="margin:0;padding:24px;background:${CANVAS};font-family:Helvetica,Arial,sans-serif;">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:520px;margin:0 auto;background:#FFFFFF;border-radius:16px;overflow:hidden;border:1px solid ${RULE};">
      <tr>
        <td style="padding:24px 24px 16px;">
          <p style="margin:0;color:${BRAND};font-size:12px;letter-spacing:2px;text-transform:uppercase;">${escapeHtml(data.store.name || "CUFMAI")}</p>
          ${data.store.location ? `<p style="margin:4px 0 0;color:${MUTED};font-size:12px;">${escapeHtml(data.store.location)}</p>` : ""}
          ${data.store.contact ? `<p style="margin:2px 0 0;color:${MUTED};font-size:12px;">Contact ${escapeHtml(data.store.contact)}</p>` : ""}
          <h1 style="margin:16px 0 4px;color:${INK};font-size:22px;">Your deposit receipt</h1>
          <p style="margin:0;color:${MUTED};font-size:13px;">
            Reservation #${escapeHtml(data.reservation.code)} &middot; ${escapeHtml(stampLabel(data.reservation.paidAt ?? data.reservation.requestedAt))}
          </p>
          ${data.customerName ? `<p style="margin:6px 0 0;color:${MUTED};font-size:13px;">For ${escapeHtml(data.customerName)}</p>` : ""}
        </td>
      </tr>
      <tr><td style="padding:0 24px;"><div style="height:1px;background:${RULE};"></div></td></tr>
      <tr>
        <td style="padding:16px 24px 0;">
          <table role="presentation" width="100%" cellpadding="0" cellspacing="0">
            <tr>
              <td style="padding:4px 0;color:${INK};font-size:14px;">${escapeHtml(data.reservation.productName || "Product")}</td>
              <td align="right" style="padding:4px 0;color:${INK};font-size:14px;white-space:nowrap;">${data.reservation.quantity} units</td>
            </tr>
          </table>
        </td>
      </tr>
      ${
        sizeRows
          ? `<tr>
        <td style="padding:8px 24px 0;">
          <p style="margin:0 0 4px;color:${MUTED};font-size:11px;letter-spacing:1.5px;text-transform:uppercase;">Sizes requested</p>
          <table role="presentation" width="100%" cellpadding="0" cellspacing="0">
            ${sizeRows}
          </table>
        </td>
      </tr>`
          : ""
      }
      <tr>
        <td style="padding:16px 24px 0;">
          <table role="presentation" width="100%" cellpadding="0" cellspacing="0">
            <tr>
              <td style="padding:10px 0 0;color:${SAGE};font-size:12px;letter-spacing:1.5px;text-transform:uppercase;">Deposit paid</td>
              <td align="right" style="padding:10px 0 0;color:${SAGE};font-size:18px;font-weight:bold;white-space:nowrap;">${peso(data.reservation.deposit)}</td>
            </tr>
            <tr>
              <td style="padding:4px 0;color:${MUTED};font-size:13px;">Paid via</td>
              <td align="right" style="padding:4px 0;color:${INK};font-size:13px;">GCash</td>
            </tr>
            ${referenceRow}
            ${proofRow}
            ${fulfilmentRow}
            ${voucherRow}
            ${holdRow}
          </table>
        </td>
      </tr>
      <tr>
        <td style="padding:20px 24px 24px;">
          <p style="margin:0;color:${INK};font-size:12px;line-height:1.6;">
            <strong>This deposit is non-refundable.</strong> Pick the units up at the store and settle the remaining balance there — bulk holds are not shipped.
          </p>
          <p style="margin:8px 0 0;color:${MUTED};font-size:12px;line-height:1.6;">
            The same receipt is attached as a PDF. Keep it as your proof of payment and quote reservation #${escapeHtml(data.reservation.code)} if you need help.
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
export function bulkReceiptText(data: BulkReceipt): string {
  const sizes = data.reservation.sizes.map(
    (size) => `  ${size.label}: ${size.quantity || "0"}`,
  );
  return [
    data.store.name || "CUFMAI",
    data.store.location,
    data.store.contact ? `Contact: ${data.store.contact}` : "",
    "",
    `DEPOSIT RECEIPT - #${data.reservation.code}`,
    stampLabel(data.reservation.paidAt ?? data.reservation.requestedAt),
    data.customerName ? `For ${data.customerName}` : "",
    "",
    `${data.reservation.quantity} units - ${data.reservation.productName || "Product"}`,
    ...(sizes.length > 0 ? ["Sizes requested:", ...sizes] : []),
    "",
    `DEPOSIT PAID: ${peso(data.reservation.deposit)}`,
    "Paid via: GCash",
    data.reservation.reference
      ? `GCash reference: ${data.reservation.reference}`
      : "",
    data.reservation.proofSubmittedAt
      ? `Proof submitted: ${stampLabel(data.reservation.proofSubmittedAt)}`
      : "",
    data.reservation.heldUntil
      ? `Units held until: ${dateLabel(data.reservation.heldUntil)}`
      : "",
    "Fulfilment: Store pickup - no shipping",
    data.reservation.voucherCode
      ? `Voucher ${data.reservation.voucherCode}: -${peso(data.reservation.voucherDiscount ?? 0)} at pickup`
      : "",
    "",
    "This deposit is non-refundable. Pick the units up at the store and settle the remaining balance there - bulk holds are not shipped.",
    `Keep this email as your proof of payment - quote #${data.reservation.code} if you need help.`,
  ].filter((line) => line !== "").join("\n");
}
