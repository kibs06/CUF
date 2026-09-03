// ══════════════════════════════════════════════════════════════════
// Product Preview — server-rendered OG endpoint for product sharing
// ══════════════════════════════════════════════════════════════════
// Serves an HTML page (with Open Graph + Twitter Card meta tags) for a
// single product, so WhatsApp / Messenger / Facebook / Telegram render a
// Shopee/Lazada-style rich link card when a customer shares a product.
//
//   GET /functions/v1/product-preview/{productId}
//   GET /functions/v1/product-preview/og-placeholder.png   (branded fallback image)
//
// Requirements for link previews to work at all:
//   - The page must be SERVER-rendered (scrapers do NOT run JavaScript).
//   - og:image must be an absolute, unauthenticated HTTPS URL.
//   - The HTML is served from the same URL that gets shared (og:url).
//
// Deploy:  supabase functions deploy product-preview
// JWT verification MUST be disabled for this function — hosted edge
// functions default to verify_jwt = true, which would 401 the anonymous
// link-preview scrapers before the function runs. Already configured:
//   [functions.product-preview]  verify_jwt = false  (supabase/config.toml)
//
// NOTE ON SALE PRICING: effectivePrice() below is a PORT of the Flutter
// app's rule in lib/utils/sale_price.dart (single source of truth on the
// client). Both must stay in sync — see docs/AI/SHARE_PRODUCT_ARCHITECTURE.md.
// ══════════════════════════════════════════════════════════════════

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { checkRateLimit, rateLimitedResponse } from "../_shared/rate_limit.ts";

/// Branded 1200×630 fallback image (solid espresso) for products without
/// a photo. Base64 PNG so no storage setup is required — served from this
/// same function at `/og-placeholder.png`.
const PLACEHOLDER_PNG_B64 =
  "iVBORw0KGgoAAAANSUhEUgAABLAAAAJ2CAIAAADAIuwLAAAMIElEQVR42u3XMQ0AAAgEsfeDIyxhGg3MNKmC2y7TBQAAwEORAAAAwBACAABgCAEAADCEAAAAGEIAAAAMIQAAAIYQAAAAQwgAAIAhBAAAwBACAABgCAEAADCEAAAAGEIAAAAMIQAAAIYQAAAAQwgAAIAhBAAAwBACAABgCAEAADCEAAAAGEIAAAAMIQAAAIYQAAAAQwgAAIAhBAAAwBACAABgCAEAADCEAAAAGEIAAAAMIQAAAIYQAAAAQwgAAGAIAQAAMIQAAAAYQgAAAAwhAAAAhhAAAABDCAAAgCEEAADAEAIAAGAIAQAAMIQAAAAYQgAAAAwhAAAAhhAAAABDCAAAgCEEAADAEAIAAGAIAQAAMIQAAAAYQgAAAAwhAAAAhhAAAABDCAAAgCEEAAAwhCoAAAAYQgAAAAwhAAAAhhAAAABDCAAAgCEEAADAEAIAAGAIAQAAMIQAAAAYQgAAAAwhAAAAhhAAAABDCAAAgCEEAADAEAIAAGAIAQAAMIQAAAAYQgAAAAwhAAAAhhAAAABDCAAAgCEEAADAEAIAAGAIAQAADCEAAACGEAAAAEMIAACAIQQAAMAQAgAAYAgBAAAwhAAAABhCAAAADCEAAACGEAAAAEMIAACAIQQAAMAQAgAAYAgBAAAwhAAAABhCAAAADCEAAACGEAAAAEMIAACAIQQAAMAQAgAAYAgBAAAwhAAAAIZQBQAAAEMIAACAIQQAAMAQAgAAYAgBAAAwhAAAABhCAAAADCEAAACGEAAAAEMIAACAIQQAAMAQAgAAYAgBAAAwhAAAABhCAAAADCEAAACGEAAAAEMIAACAIQQAAMAQAgAAYAgBAAAwhAAAABhCAAAADCEAAIAhBAAAwBACAABgCAEAADCEAAAAGEIAAAAMIQAAAIYQAAAAQwgAAIAhBAAAwBACAABgCAEAADCEAAAAGEIAAAAMIQAAAIYQAAAAQwgAAIAhBAAAwBACAABgCAEAADCEAAAAGEIAAAAMIQAAAIYQAADAEAIAAGAIAQAAMIQAAAAYQgAAAAwhAAAAhhAAAABDCAAAgCEEAADAEAIAAGAIAQAAMIQAAAAYQgAAAAwhAAAAhhAAAABDCAAAgCEEAADAEAIAAGAIAQAAMIQAAAAYQgAAAAwhAAAAhhAAAABDCAAAgCEEAAAwhAAAABhCAAAADCEAAACGEAAAAEMIAACAIQQAAMAQAgAAYAgBAAAwhAAAABhCAAAADCEAAACGEAAAAEMIAACAIQQAAMAQAgAAYAgBAAAwhAAAABhCAAAADCEAAACGEAAAAEMIAACAIQQAAMAQAgAAGEIAAAAMIQAAAIYQAAAAQwgAAIAhBAAAwBACAABgCAEAADCEAAAAGEIAAAAMIQAAAIYQAAAAQwgAAIAhBAAAwBACAABgCAEAADCEAAAAGEIAAAAMIQAAAIYQAAAAQwgAAIAhBAAAwBACAABgCAEAADCEAAAAhhAAAABDCAAAgCEEAADAEAIAAGAIAQAAMIQAAAAYQgAAAAwhAAAAhhAAAABDCAAAgCEEAADAEAIAAGAIAQAAMIQAAAAYQgAAAAwhAAAAhhAAAABDCAAAgCEEAADAEAIAAGAIAQAAMIQAAAAYQgAAAEMIAACAIQQAAMAQAgAAYAgBAAAwhAAAABhCAAAADCEAAACGEAAAAEMIAACAIQQAAMAQAgAAYAgBAAAwhAAAABhCAAAADCEAAACGEAAAAEMIAACAIQQAAMAQAgAAYAgBAAAwhAAAABhCAAAADCEAAIAhlAAAAMAQAgAAYAgBAAAwhAAAABhCAAAADCEAAACGEAAAAEMIAACAIQQAAMAQAgAAYAgBAAAwhAAAABhCAAAADCEAAACGEAAAAEMIAACAIQQAAMAQAgAAYAgBAAAwhAAAABhCAAAADCEAAACGEAAAAEMIAABgCAEAADCEAAAAGEIAAAAMIQAAAIYQAAAAQwgAAIAhBAAAwBACAABgCAEAADCEAAAAGEIAAAAMIQAAAIYQAAAAQwgAAIAhBAAAwBACAABgCAEAADCEAAAAGEIAAAAMIQAAAIYQAAAAQwgAAIAhBAAAMIQqAAAAGEIAAAAMIQAAAIYQAAAAQwgAAIAhBAAAwBACAABgCAEAADCEAAAAGEIAAAAMIQAAAIYQAAAAQwgAAIAhBAAAwBACAABgCAEAADCEAAAAGEIAAAAMIQAAAIYQAAAAQwgAAIAhBAAAwBACAABgCAEAAAwhAAAAhhAAAABDCAAAgCEEAADAEAIAAGAIAQAAMIQAAAAYQgAAAAwhAAAAhhAAAABDCAAAgCEEAADAEAIAAGAIAQAAMIQAAAAYQgAAAAwhAAAAhhAAAABDCAAAgCEEAADAEAIAAGAIAQAAMIQAAACGUAUAAABDCAAAgCEEAADAEAIAAGAIAQAAMIQAAAAYQgAAAAwhAAAAhhAAAABDCAAAgCEEAADAEAIAAGAIAQAAMIQAAAAYQgAAAAwhAAAAhhAAAABDCAAAgCEEAADAEAIAAGAIAQAAMIQAAAAYQgAAAAwhAACAIQQAAMAQAgAAYAgBAAAwhAAAABhCAAAADCEAAACGEAAAAEMIAACAIQQAAMAQAgAAYAgBAAAwhAAAABhCAAAADCEAAACGEAAAAEMIAACAIQQAAMAQAgAAYAgBAAAwhAAAABhCAAAADCEAAACGEAAAwBACAABgCAEAADCEAAAAGEIAAAAMIQAAAIYQAAAAQwgAAIAhBAAAwBACAABgCAEAADCEAAAAGEIAAAAMIQAAAIYQAAAAQwgAAIAhBAAAwBACAABgCAEAADCEAAAAGEIAAAAMIQAAAIYQAAAAQwgAAIAhBAAAMIQAAAAYQgAAAAwhAAAAhhAAAABDCAAAgCEEAADAEAIAAGAIAQAAMIQAAAAYQgAAAAwhAAAAhhAAAABDCAAAgCEEAADAEAIAAGAIAQAAMIQAAAAYQgAAAAwhAAAAhhAAAABDCAAAgCEEAADAEAIAABhCAAAADCEAAACGEAAAAEMIAACAIQQAAMAQAgAAYAgBAAAwhAAAABhCAAAADCEAAACGEAAAAEMIAACAIQQAAMAQAgAAYAgBAAAwhAAAABhCAAAADCEAAACGEAAAAEMIAACAIQQAAMAQAgAAYAgBAAAwhAAAAIYQAAAAQwgAAIAhBAAAwBACAABgCAEAADCEAAAAGEIAAAAMIQAAAIYQAAAAQwgAAIAhBAAAwBACAABgCAEAADCEAAAAGEIAAAAMIQAAAIYQAAAAQwgAAIAhBAAAwBACAABgCAEAADCEAAAAGEIAAABDCAAAgCEEAADAEAIAAGAIAQAAMIQAAAAYQgAAAAwhAAAAhhAAAABDCAAAgCEEAADAEAIAAGAIAQAAMIQAAAAYQgAAAAwhAAAAhhAAAABDCAAAgCEEAADAEAIAAGAIAQAAMIQAAAAYQgAAAAwhAACAIZQAAADAEAIAAGAIAQAAMIQAAAAYQgAAAAwhAAAAhhAAAABDCAAAgCEEAADAEAIAAGAIAQAAMIQAAAAYQgAAAAwhAAAAhhAAAABDCAAAgCEEAADAEAIAAGAIAQAAMIQAAAAYQgAAAAwhAAAAhhAAAABDCAAAYAgBAAAwhAAAABhCAAAADCEAAACGEAAAAEMIAACAIQQAAMAQAgAAYAgBAAAwhAAAABhCAAAADCEAAACGEAAAAEMIAACAIQQAAMAQAgAAYAgBAAAwhAAAABhCAAAADCEAAACGEAAAAEMIAACAIQQAADCEKgAAABhCAAAADCEAAACGEAAAAEMIAACAIQQAAMAQAgAAYAgBAAAwhAAAABhCAAAADCEAAACGEAAAAEMIAACAIQQAAMAQAgAAYAgBAAAwhAAAABhCAAAADCEAAACGEAAAAEMIAACAIQQAAMAQAgAAYAgBAAAMIQAAAIYQAAAAQwgAAIAhBAAAwBACAABgCAEAADCEAAAAGEIAAAAMIQAAAIYQAAAAQwgAAIAhBAAAwBACAABgCAEAADCEAAAAGEIAAAAMIQAAAIYQAAAAQwgAAIAhBAAAwBACAABgCAEAADCEAAAAhlAFAAAAQwgAAIAhBAAAwBACAABgCAEAADCEAAAAGEIAAAAMIQAAAIYQAAAAQwgAAIAhBAAAwBACAABgCAEAADCEAAAAGEIAAAAMIQAAAIYQAAAAQwgAAIAhBAAA4GYBg35p34AL3SgAAAAASUVORK5CYII=";

// ── Ported from lib/utils/sale_price.dart (KEEP IN SYNC) ──────────
function toNum(value: unknown): number | null {
  if (value === null || value === undefined) return null;
  if (typeof value === "number") return value;
  const n = Number(value);
  return Number.isNaN(n) ? null : n;
}

function toDate(value: unknown): Date | null {
  if (value === null || value === undefined) return null;
  const d = new Date(String(value));
  return Number.isNaN(d.getTime()) ? null : d;
}

/// A product is on sale ONLY when sale_price is set, strictly less than
/// price, and inside the optional start/end window. Mirrors
/// sale_price.dart::isOnSale exactly.
function isOnSale(
  p: Record<string, unknown>,
  now: Date,
): boolean {
  const price = toNum(p.price) ?? 0;
  const salePrice = toNum(p.sale_price);
  if (salePrice === null || salePrice <= 0 || salePrice >= price) return false;

  const start = toDate(p.sale_starts_at);
  if (start !== null && now.getTime() < start.getTime()) return false;

  const end = toDate(p.sale_ends_at);
  if (end !== null && now.getTime() > end.getTime()) return false;

  return true;
}

function effectivePrice(p: Record<string, unknown>, now: Date): number {
  return isOnSale(p, now)
    ? toNum(p.sale_price) ?? toNum(p.price) ?? 0
    : toNum(p.price) ?? 0;
}

function formatPeso(value: number): string {
  return "₱" + value.toFixed(2);
}

function escapeHtml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

// ── HTML templates ────────────────────────────────────────────────

function htmlDocument(meta: {
  title: string;
  description: string;
  imageUrl: string;
  url: string;
  body: string;
}): string {
  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>${meta.title}</title>
<meta property="og:title" content="${meta.title}"/>
<meta property="og:description" content="${meta.description}"/>
<meta property="og:image" content="${meta.imageUrl}"/>
<meta property="og:url" content="${meta.url}"/>
<meta property="og:type" content="product"/>
<meta name="twitter:card" content="summary_large_image"/>
<meta name="twitter:title" content="${meta.title}"/>
<meta name="twitter:description" content="${meta.description}"/>
<meta name="twitter:image" content="${meta.imageUrl}"/>
<link rel="canonical" href="${meta.url}"/>
<style>
  body { margin:0; font-family: -apple-system, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
         background:#F5F0EB; color:#3B2314; }
  .wrap { max-width:560px; margin:0 auto; padding:48px 20px; }
  img.hero { width:100%; max-height:420px; object-fit:cover; border-radius:16px; }
  .card { background:#fff; border-radius:16px; padding:20px 20px 24px; margin-top:20px;
          box-shadow: 0 4px 12px rgba(139,90,43,0.08); }
  h1 { font-size:24px; margin:0 0 6px; }
  .price { font-size:22px; font-weight:700; color:#8B5A2B; margin:6px 0; }
  .store { color:#8B5A2B; font-weight:600; margin:0; }
  .note { color:#8b6f52; font-size:13px; margin-top:20px; text-align:center; }
  .cta { display:inline-block; margin-top:16px; background:#8B5A2B; color:#F5F0EB;
         text-decoration:none; padding:12px 22px; border-radius:12px; font-weight:600; }
</style>
</head>
<body>
<div class="wrap">${meta.body}</div>
</body>
</html>`;
}

function productPage(p: Record<string, unknown>, now: Date, origin: string, id: string): string {
  const name = escapeHtml(String(p.name ?? "CUFMAI Footwear"));
  const storeName = escapeHtml(
    (p.stores as Record<string, unknown> | null)?.name?.toString() ?? "CUFMAI",
  );
  const price = effectivePrice(p, now);
  const priceStr = escapeHtml(formatPeso(price));
  const description = escapeHtml(`Handcrafted artisan footwear — ${priceStr} at ${storeName}`);

  const images = (p.product_images as Array<Record<string, unknown>> | null) ?? [];
  const sortedImages = [...images].sort(
    (a, b) => Number(a.display_order ?? 0) - Number(b.display_order ?? 0),
  );
  let imageUrl = sortedImages.map((i) => i.image_url?.toString()).find((u) => u && u.startsWith("https://")) ?? "";
  if (!imageUrl) {
    const logo = (p.stores as Record<string, unknown> | null)?.logo_url?.toString() ?? "";
    imageUrl = logo.startsWith("https://") ? logo : "";
  }
  if (!imageUrl) {
    imageUrl = `${origin}/functions/v1/product-preview/og-placeholder.png`;
  }

  const pageUrl = `${origin}/functions/v1/product-preview/${encodeURIComponent(id)}`;
  const descriptionText =
    (p.description as string | null)?.trim() ??
    "Handcrafted artisan footwear from Carcar, Cebu.";

  const body = `
    <img class="hero" src="${escapeHtml(imageUrl)}" alt="${name}"/>
    <div class="card">
      <p class="store">${storeName}</p>
      <h1>${name}</h1>
      <div class="price">${priceStr}</div>
      <p style="color:#5b4632;line-height:1.5;">${escapeHtml(descriptionText)}</p>
      <a class="cta" href="${pageUrl}">View in the CUFMAI app</a>
    </div>
    <p class="note">Available in the CUFMAI app — artisan footwear marketplace.</p>`;

  return htmlDocument({
    title: name,
    description: description,
    imageUrl: escapeHtml(imageUrl),
    url: pageUrl,
    body,
  });
}

function unavailablePage(origin: string, id: string): string {
  const pageUrl = `${origin}/functions/v1/product-preview/${encodeURIComponent(id)}`;
  const placeholder = `${origin}/functions/v1/product-preview/og-placeholder.png`;
  return htmlDocument({
    title: "Product no longer available",
    description: "This product is no longer available in the CUFMAI app.",
    imageUrl: placeholder,
    url: pageUrl,
    body: `
      <div class="card" style="text-align:center;padding:48px 20px;">
        <h1>Product no longer available</h1>
        <p style="color:#5b4632;">The product you're looking for was removed or is out of stock.</p>
      </div>`,
  });
}

const TEXT_HEADERS = {
  "Content-Type": "text/html; charset=utf-8",
  "Cache-Control": "public, max-age=3600",
  "X-Robots-Tag": "index, nofollow",
};

function textResponse(status: number, html: string): Response {
  return new Response(html, { status, headers: TEXT_HEADERS });
}

function pngResponse(): Response {
  const bytes = Uint8Array.from(atob(PLACEHOLDER_PNG_B64), (c) => c.charCodeAt(0));
  return new Response(bytes, {
    headers: {
      "Content-Type": "image/png",
      "Cache-Control": "public, max-age=86400",
    },
  });
}

function isValidProductId(id: string): boolean {
  return id.length > 0 && id.length <= 64 && /^[A-Za-z0-9-]+$/.test(id);
}

serve(async (req: Request) => {
  // T6: per-IP rate limit. Link-preview scrapers fetch each shared URL
  // once or twice; 120/min per IP is far beyond any legit pattern but
  // stops scripted hotlinking that would hammer the DB per request.
  const rl = await checkRateLimit(req, "product-preview", 120);
  if (!rl.allowed) {
    return rateLimitedResponse(rl, {
      "Access-Control-Allow-Origin": "*",
    });
  }

  const url = new URL(req.url);
  const segments = url.pathname.split("/").filter(Boolean); // e.g. [functions, v1, product-preview, {id}]

  // Branded fallback image route.
  if (segments[segments.length - 1] === "og-placeholder.png") {
    return pngResponse();
  }

  let id = segments[segments.length - 1];
  // Also accept a future custom-domain shape /p/{productId}.
  if (segments.length >= 3 && segments[segments.length - 2] === "p") {
    id = segments[segments.length - 1];
  }

  if (!isValidProductId(id)) {
    return textResponse(400, htmlDocument({
      title: "Invalid product link",
      description: "This link is malformed.",
      imageUrl: `${url.origin}/functions/v1/product-preview/og-placeholder.png`,
      url: escapeHtml(url.href),
      body: `<div class="card" style="text-align:center;padding:48px 20px;"><h1>Invalid product link</h1></div>`,
    }));
  }

  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "http://localhost:54321",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    );

    const { data, error } = await supabase
      .from("products")
      .select(
        "id, name, description, price, sale_price, sale_starts_at, sale_ends_at, is_active, stores(name, logo_url), product_images(image_url, display_order)",
      )
      .eq("id", id)
      .maybeSingle();

    if (error) throw error;

    const now = new Date();
    if (!data || data.is_active === false) {
      return textResponse(404, unavailablePage(url.origin, id));
    }

    return textResponse(200, productPage(data, now, url.origin, id));
  } catch (err) {
    console.error("[product-preview] error:", err);
    return textResponse(500, htmlDocument({
      title: "Something went wrong",
      description: "The preview could not be loaded. Please try again later.",
      imageUrl: `${url.origin}/functions/v1/product-preview/og-placeholder.png`,
      url: escapeHtml(url.href),
      body: `<div class="card" style="text-align:center;padding:48px 20px;"><h1>Something went wrong</h1><p style="color:#5b4632;">Please try again later.</p></div>`,
    }));
  }
});
