// ══════════════════════════════════════════════════════════════════
// validate-upload — Server-side magic-byte verification for uploaded files
//
// Called by: the Flutter app after a successful upload, OR configured as
// a storage webhook to run automatically on every upload. Reads the first
// 8 bytes of the uploaded object and verifies they match a real JPEG/PNG
// file signature — independent of the extension or declared Content-Type.
//
// If the file fails validation: deletes the object immediately so a
// rejected file never sits in storage. Returns a clear JSON response
// so the client can surface an error.
//
// Defense-in-depth context:
//   Layer 1 (client): extension allowlist + magic-byte check in
//     verification_document_service.dart — catches accidental mismatches.
//   Layer 2 (bucket): allowed_mime_types + file_size_limit on the
//     storage bucket — blocks casual bypass of the app.
//   Layer 3 (this function): verifies real file bytes server-side,
//     closing the gap where a malicious actor spoofs the Content-Type
//     header and uploads directly via the Supabase REST API.
//
// Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY (for storage access)
//
// Deploy: supabase functions deploy validate-upload --no-verify-jwt
// ══════════════════════════════════════════════════════════════════

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { checkRateLimit, rateLimitedResponse } from "../_shared/rate_limit.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

// ── Magic-byte signatures (must match Layer 1 in Dart) ──────────
const SIGNATURES: Record<string, number[]> = {
  jpg: [0xff, 0xd8, 0xff],
  jpeg: [0xff, 0xd8, 0xff],
  png: [0x89, 0x50, 0x4e, 0x47], // %PNG
};

// Buckets this function validates. Keep tightly scoped — do not
// validate product-images, avatars, or other unrelated buckets.
const VALIDATED_BUCKETS = new Set([
  "seller-verification-docs",
  "store-assets",
]);

function extFromPath(path: string): string {
  const lower = path.toLowerCase();
  if (lower.endsWith(".png")) return "png";
  if (lower.endsWith(".heic") || lower.endsWith(".heif")) return "jpg";
  return "jpg"; // default — image_picker re-encodes HEIC to JPEG
}

function validateMagicBytes(
  header: Uint8Array,
  ext: string,
): { valid: boolean; reason?: string } {
  const expected = SIGNATURES[ext];
  if (!expected) {
    return {
      valid: false,
      reason: `Unknown extension: .${ext}`,
    };
  }
  if (header.length < expected.length) {
    return {
      valid: false,
      reason: `File too small (${header.length} bytes) — cannot verify`,
    };
  }
  for (let i = 0; i < expected.length; i++) {
    if (header[i] !== expected[i]) {
      return {
        valid: false,
        reason: `Magic bytes mismatch: expected [${expected
          .map((b) => "0x" + b.toString(16).padStart(2, "0"))
          .join(", ")}] but got [${Array.from(header.slice(0, expected.length))
          .map((b) => "0x" + b.toString(16).padStart(2, "0"))
          .join(", ")}]`,
      };
    }
  }
  return { valid: true };
}

serve(async (req: Request) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  // T6: per-IP rate limit. A full seller submission bursts ~11 sequential
  // validation calls; 60/min per IP only trips scripted abuse.
  const rl = await checkRateLimit(req, "validate-upload", 60);
  if (!rl.allowed) return rateLimitedResponse(rl, corsHeaders);

  try {
    const payload = await req.json();
    const bucketId: string = payload.bucket_id ?? "";
    const objectName: string = payload.name ?? "";

    if (!bucketId || !objectName) {
      return new Response(
        JSON.stringify({ error: "Missing bucket_id or name" }),
        { status: 400, headers: corsHeaders },
      );
    }

    // Only validate our two target buckets
    if (!VALIDATED_BUCKETS.has(bucketId)) {
      return new Response(JSON.stringify({ ok: true, skipped: true }), {
        headers: corsHeaders,
      });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const supabase = createClient(supabaseUrl, serviceKey);

    // Download the file (service role bypasses RLS)
    const { data: fileData, error: downloadErr } = await supabase.storage
      .from(bucketId)
      .download(objectName);

    if (downloadErr || !fileData) {
      console.error(
        `[validate-upload] Download failed for ${bucketId}/${objectName}:`,
        downloadErr?.message ?? "no data",
      );
      return new Response(
        JSON.stringify({ error: "Could not read file for validation" }),
        { status: 500, headers: corsHeaders },
      );
    }

    // Read the first 8 bytes (covers the longest signature: PNG = 4 bytes)
    const arrayBuffer = await fileData.arrayBuffer();
    const header = new Uint8Array(arrayBuffer.slice(0, 8));
    const ext = extFromPath(objectName);
    const result = validateMagicBytes(header, ext);

    if (result.valid) {
      console.log(
        `[validate-upload] ✓ ${bucketId}/${objectName} — valid ${ext}`,
      );
      return new Response(
        JSON.stringify({ ok: true, ext, bytes: arrayBuffer.byteLength }),
        { headers: corsHeaders },
      );
    }

    // ── Invalid file: delete immediately ──────────────────────────
    console.error(
      `[validate-upload] ✗ REJECTED ${bucketId}/${objectName}: ${result.reason}`,
    );

    const { error: deleteErr } = await supabase.storage
      .from(bucketId)
      .remove([objectName]);

    if (deleteErr) {
      console.error(
        `[validate-upload] Delete failed for ${bucketId}/${objectName}:`,
        deleteErr.message,
      );
      // File is invalid but couldn't be deleted — still return rejection
      // so the client knows. The bucket's file_size_limit and
      // allowed_mime_types (Layer 2) provide additional protection.
    }

    return new Response(
      JSON.stringify({
        ok: false,
        deleted: !deleteErr,
        error:
          "This file doesn't appear to be a valid image. " +
          "Please choose a photo taken with your camera or a proper scan.",
        reason: result.reason,
      }),
      { status: 422, headers: corsHeaders },
    );
  } catch (e) {
    console.error("[validate-upload] Error:", e);
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: corsHeaders,
    });
  }
});
