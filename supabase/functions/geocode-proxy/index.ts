// ══════════════════════════════════════════════════════════════════
// geocode-proxy — MapTiler proxy for the Flutter app (Threat T6)
// ══════════════════════════════════════════════════════════════════
// Why this exists: the MapTiler API key used to be compiled into the
// Flutter client (AppConstants.maptilerKey) and the client called
// api.maptiler.com directly — anyone unpacking the APK could extract
// the key and burn geocoding/tile quota. This function removes the key
// from the client entirely: the app calls THIS function, which holds
// the key as a server-side secret and forwards to MapTiler.
//
// It also rate-limits per client IP (see _shared/rate_limit.ts), which
// would have been impossible while the client talked to MapTiler
// directly (no backend in the loop).
//
// Routes (verify_jwt = false — the seller application flow calls this
// BEFORE an account exists, so it cannot require a user JWT):
//   GET /geocode-proxy/search?q=<address text>      → forward geocoding
//   GET /geocode-proxy/tiles/{z}/{x}/{y}.png        → raster map tiles
//
// Env secrets: MAPTILER_API_KEY (required), SUPABASE_URL,
// SUPABASE_SERVICE_ROLE_KEY (rate-limit counter store).
//
// Rate limits (per IP, fixed 60s window):
//   search — 30/min. Human-paced: the client debounces 350ms and needs
//            ≥2 chars, so even a heavy searching session stays in the
//            low tens per minute. 30 caps abuse without touching normal
//            use.
//   tiles  — 600/min. Map panning is bursty by design (flutter_map
//            fires ~8–24 concurrent fetches per pan), so this is set
//            high enough to never break real map use but still stops
//            scripted whole-city scraping (which runs thousands/min).
//
// Deploy: supabase functions deploy geocode-proxy
// JWT verification is disabled for this function — already configured:
//   [functions.geocode-proxy]  verify_jwt = false  (supabase/config.toml)
// ══════════════════════════════════════════════════════════════════

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { checkRateLimit, rateLimitedResponse } from "../_shared/rate_limit.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

// Philippine bounding box — mirrors the old client-side parameters so
// search results are scoped to where the app operates.
const PH_BBOX = "116.927,4.587,126.603,21.119";
const SEARCH_LIMIT_RESULTS = 5;

// Tune-here limits (one place, not magic numbers in handlers).
const SEARCH_RATE_LIMIT = 30; // per IP per minute
const TILES_RATE_LIMIT = 600; // per IP per minute

function mapTilerKey(): string {
  const key = Deno.env.get("MAPTILER_API_KEY") ?? "";
  if (!key) {
    throw new Error("MAPTILER_API_KEY is not configured");
  }
  return key;
}

function json(
  body: unknown,
  status = 200,
  extraHeaders: Record<string, string> = {},
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json", ...extraHeaders },
  });
}

// ── Forward geocoding ────────────────────────────────────────────
// Calls MapTiler's geocoding endpoint and returns ONLY the fields the
// Flutter screens consume (place_name + center [lng, lat]) — not the
// whole MapTiler response surface.
async function handleSearch(req: Request, query: string): Promise<Response> {
  const rl = await checkRateLimit(req, "geocode-proxy:search", SEARCH_RATE_LIMIT);
  if (!rl.allowed) return rateLimitedResponse(rl, corsHeaders);

  const encoded = encodeURIComponent(query);
  const url =
    `https://api.maptiler.com/geocoding/${encoded}.json` +
    `?key=${mapTilerKey()}&bbox=${PH_BBOX}&limit=${SEARCH_LIMIT_RESULTS}`;

  try {
    const upstream = await fetch(url, {
      headers: { "User-Agent": "com.solevision.app (geocode-proxy)" },
    });
    if (!upstream.ok) {
      console.error(
        `[geocode-proxy] MapTiler geocoding ${upstream.status}: ${await upstream.text()}`,
      );
      return json(
        { error: "geocoding upstream error" },
        upstream.status === 429 ? 429 : 502,
      );
    }

    const data = await upstream.json() as {
      features?: Array<{
        place_name?: string;
        center?: [number, number];
      }>;
    };
    const features = (data.features ?? []).map((f) => ({
      place_name: f.place_name ?? "",
      center: f.center ?? [0, 0],
    }));
    return json({ features });
  } catch (e) {
    console.error("[geocode-proxy] search failed:", (e as Error)?.message ?? e);
    return json({ error: "geocoding failed" }, 502);
  }
}

// ── Raster tiles ─────────────────────────────────────────────────
// Forwards MapTiler streets-v2 PNG tiles and returns the bytes with a
// long browser cache header (tiles are immutable per z/x/y).
async function handleTile(
  req: Request,
  z: string,
  x: string,
  y: string,
): Promise<Response> {
  const rl = await checkRateLimit(req, "geocode-proxy:tiles", TILES_RATE_LIMIT);
  if (!rl.allowed) return rateLimitedResponse(rl, corsHeaders);

  const zoom = Number(z);
  const tileX = Number(x);
  const tileY = Number(y);
  if (
    !Number.isInteger(zoom) || zoom < 0 || zoom > 22 ||
    !Number.isInteger(tileX) || tileX < 0 ||
    !Number.isInteger(tileY) || tileY < 0
  ) {
    return json({ error: "invalid tile coordinates" }, 400);
  }

  const url =
    `https://api.maptiler.com/maps/streets-v2/${zoom}/${tileX}/${tileY}.png` +
    `?key=${mapTilerKey()}`;

  try {
    const upstream = await fetch(url);
    if (!upstream.ok) {
      console.error(
        `[geocode-proxy] MapTiler tile ${upstream.status} for ${zoom}/${tileX}/${tileY}`,
      );
      // 404 = transparent/no-data tile — pass through so flutter_map
      // doesn't retry forever; other errors surface as 502.
      return upstream.status === 404
        ? new Response(null, { status: 404, headers: corsHeaders })
        : json({ error: "tile upstream error" }, 502);
    }
    const bytes = await upstream.arrayBuffer();
    return new Response(bytes, {
      status: 200,
      headers: {
        ...corsHeaders,
        "Content-Type": "image/png",
        "Cache-Control": "public, max-age=86400",
      },
    });
  } catch (e) {
    console.error("[geocode-proxy] tile failed:", (e as Error)?.message ?? e);
    return json({ error: "tile fetch failed" }, 502);
  }
}

serve(async (req: Request) => {
  // CORS preflight (web debug clients)
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const url = new URL(req.url);
    // The runtime request URL may or may not include the function slug
    // (.../functions/v1/geocode-proxy/<route> vs /<route>), so locate the
    // slug anywhere in the path and take everything after it, then strip
    // trailing slashes so "/search/" == "/search".
    const path = url.pathname;
    const slugIdx = path.indexOf("/geocode-proxy");
    const raw = slugIdx >= 0
      ? path.slice(slugIdx + "/geocode-proxy".length)
      : path;
    const route = (raw.startsWith("/") ? raw : "/" + raw).replace(/\/+$/, "");

    // Search: /search?q=… (also accept ?q= on the bare route for ease)
    const query = url.searchParams.get("q");
    if (route === "/search" || route === "" || route === "/") {
      if (!query || query.trim().length === 0) {
        return json({ error: "missing q parameter" }, 400);
      }
      return handleSearch(req, query.trim());
    }

    // Tiles: /tiles/{z}/{x}/{y}.png  (optionally .png suffix omitted)
    const tileMatch = route.match(/^\/tiles\/(\d+)\/(\d+)\/(\d+)(?:\.png)?$/);
    if (tileMatch) {
      return handleTile(req, tileMatch[1], tileMatch[2], tileMatch[3]);
    }

    console.warn(`[geocode-proxy] unmatched route path=${path} route=${route}`);
    // Debug aid (temporary): echo the received path so routing issues are
    // visible without log access. Remove once routing is confirmed stable.
    return json({ error: "not found", receivedPath: path, computedRoute: route }, 404);
  } catch (e) {
    const msg = (e as Error)?.message ?? "internal error";
    console.error("[geocode-proxy] handler error:", msg);
    return json({ error: msg }, 500);
  }
});