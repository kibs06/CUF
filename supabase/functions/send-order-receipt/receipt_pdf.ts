// supabase/functions/send-order-receipt/receipt_pdf.ts
//
// The PDF attached to an online-order receipt email.
//
// It is the same A5 slip the phone prints from the POS (`lib/utils/
// pos_receipt_pdf.dart`): store header, receipt code, date/time, the item
// lines, the money breakdown, how it was paid, and the thank-you. The layout
// is rewritten here because the Flutter renderer (package:pdf) cannot run in a
// Deno edge function; the rules it follows are the same ones — base Helvetica
// (WinAnsi, no Unicode), every string folded to Latin-1 before it is drawn,
// and money written as "PHP 1,234.50" for the same reason (the peso sign is
// not in WinAnsi).

import {
  PDFDocument,
  PDFFont,
  StandardFonts,
  rgb,
} from "npm:pdf-lib@1.17.1";

/** Everything the slip needs, already read from the order. */
export interface ReceiptStore {
  name: string;
  location: string;
}

export interface ReceiptLine {
  name: string;
  size: string;
  quantity: number;
  unitPrice: number;
}

export interface ReceiptOrder {
  orderCode: string;
  createdAt: Date;
  paymentMethod: string;
  total: number;
  subtotal: number | null;
  discount: number | null;
  voucherCode: string | null;
  gcashReference: string | null;
  fulfillment: string;
  /** "pos" for a sale rung up at the till, "online" for an app order. */
  source?: string;
  /** Who rang the sale up; only a till sale records one. */
  cashier?: string;
  /** Cash handed over and change given; only till cash sales carry them. */
  amountTendered?: number | null;
  changeAmount?: number | null;
}

export interface ReceiptData {
  store: ReceiptStore;
  order: ReceiptOrder;
  lines: ReceiptLine[];
  customerName: string;
  customerEmail: string;
}

/**
 * Helvetica has no Unicode support: fold the few characters that would throw
 * at draw time onto their WinAnsi neighbours, and anything above U+00FF onto
 * "?". Mirrors `_printable` in the Dart renderer.
 */
function printable(text: string): string {
  return (text ?? "")
    .replace(/\u20b1/g, "PHP ")
    .replace(/[\u2013\u2014]/g, "-")
    .replace(/[\u2018\u2019]/g, "'")
    .replace(/[\u201c\u201d]/g, '"')
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

function dateLabel(at: Date): string {
  const months = [
    "Jan", "Feb", "Mar", "Apr", "May", "Jun",
    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
  ];
  return `${months[at.getMonth()]} ${at.getDate()}, ${at.getFullYear()}`;
}

function timeLabel(at: Date): string {
  const hour = at.getHours();
  const minute = String(at.getMinutes()).padStart(2, "0");
  const period = hour >= 12 ? "PM" : "AM";
  const display = hour === 0 ? 12 : hour > 12 ? hour - 12 : hour;
  return `${display}:${minute} ${period}`;
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

/**
 * Where the order is being sent/collected, in one word for the slip. A till
 * sale has no fulfilment to speak of: the customer walked out with it.
 */
function fulfillmentLabel(order: ReceiptOrder): string {
  if ((order.source ?? "").toLowerCase() === "pos") return "In store";
  return (order.fulfillment ?? "").toLowerCase() === "delivery"
    ? "Delivery"
    : "Store pickup";
}

/** Build the A5 receipt PDF. Returns the finished bytes. */
export async function buildOrderReceiptPdf(data: ReceiptData): Promise<Uint8Array> {
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

  // ── header ──────────────────────────────────────────────────────
  text(data.store.name || "CUFMAI", { size: 14, font: bold });
  y -= 15;
  if (data.store.location) {
    text(data.store.location, { size: 8.5, color: muted });
    y -= 11;
  }
  y -= 3;
  text("SALES RECEIPT", { size: 8.5, font: bold, color: muted });
  y -= 16;

  line();
  y -= 14;

  text("Receipt no.", { size: 8.5, color: muted });
  text(data.order.orderCode, { size: 8.5, font: bold, align: "right" });
  y -= 12;
  text("Date", { size: 8.5, color: muted });
  text(`${dateLabel(data.order.createdAt)} - ${timeLabel(data.order.createdAt)}`, {
    size: 8.5,
    align: "right",
  });
  y -= 12;
  if (data.customerName) {
    text("Customer", { size: 8.5, color: muted });
    text(data.customerName, { size: 8.5, align: "right" });
    y -= 12;
  }
  if (data.order.cashier) {
    text("Cashier", { size: 8.5, color: muted });
    text(data.order.cashier, { size: 8.5, align: "right" });
    y -= 12;
  }
  text("Fulfilment", { size: 8.5, color: muted });
  text(fulfillmentLabel(data.order), { size: 8.5, align: "right" });
  y -= 16;

  line();
  y -= 16;

  // ── items ───────────────────────────────────────────────────────
  for (const item of data.lines) {
    const size = sizeLabel(item.size);
    const name = size ? `${item.name} (${size})` : item.name;
    const left2 = `${item.quantity} x ${name}`;
    const amount = money(item.unitPrice * item.quantity);

    // Long names wrap onto a second line rather than running off the slip.
    const available = right - left - bold.widthOfTextAtSize(amount, 8.5) - 10;
    const trimmed = printable(left2);
    if (regular.widthOfTextAtSize(trimmed, 8.5) > available) {
      let cut = trimmed;
      while (cut.length > 4 && regular.widthOfTextAtSize(cut, 8.5) > available) {
        cut = cut.slice(0, -1);
      }
      text(cut, { size: 8.5 });
      text(amount, { size: 8.5, align: "right" });
      y -= 11;
    } else {
      text(trimmed, { size: 8.5 });
      text(amount, { size: 8.5, align: "right" });
    }
    y -= 13;
    if (y < 180) break; // a runaway cart must not write off the page
  }

  y -= 2;
  line();
  y -= 15;

  // ── money ───────────────────────────────────────────────────────
  const subtotal = data.order.subtotal;
  if (subtotal != null) {
    text("Subtotal", { size: 8.5, color: muted });
    text(money(subtotal), { size: 8.5, align: "right" });
    y -= 12;
  }
  if (data.order.discount != null && data.order.discount > 0) {
    const label = data.order.voucherCode
      ? `Discount (${data.order.voucherCode})`
      : "Discount";
    text(label, { size: 8.5, color: muted });
    text("-" + money(data.order.discount), { size: 8.5, align: "right" });
    y -= 12;
  }
  text("TOTAL", { size: 10, font: bold });
  text(money(data.order.total), { size: 10, font: bold, align: "right" });
  y -= 16;

  text("Paid via", { size: 8.5, color: muted });
  text(paymentLabel(data.order.paymentMethod), { size: 8.5, align: "right" });
  y -= 12;
  if (data.order.amountTendered != null) {
    text("Cash tendered", { size: 8.5, color: muted });
    text(money(data.order.amountTendered), { size: 8.5, align: "right" });
    y -= 12;
  }
  if (data.order.changeAmount != null) {
    text("Change", { size: 8.5, color: muted });
    text(money(data.order.changeAmount), { size: 8.5, align: "right" });
    y -= 12;
  }
  if (data.order.gcashReference) {
    text("GCash ref", { size: 8.5, color: muted });
    text(data.order.gcashReference, { size: 8.5, align: "right" });
    y -= 12;
  }

  // ── footer ──────────────────────────────────────────────────────
  y = 96;
  line();
  y -= 14;
  text("Thank you for shopping with CUFMAI.", { size: 8.5, color: muted });
  y -= 11;
  text(`Sent to ${data.customerEmail}`, { size: 8, color: muted });
  y -= 11;
  text(`Keep this receipt - quote ${data.order.orderCode} if you need help.`, {
    size: 8,
    color: muted,
  });

  return await doc.save();
}
