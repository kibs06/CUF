// ══════════════════════════════════════════════════════════════════
// validate-shoe-model — the server-side GLB validator (roadmap V2.4)
//
// Called by: the Flutter app right after it uploads a model and inserts
// the `product_models` row. It re-reads the row, downloads the object the
// row points at with the service role, re-runs the authoring contract over
// those bytes, and only then lets the row reach `status='active'`.
//
// Why this exists at all, when the app already validates the file before
// uploading (V2.3): architecture §2.5.4 — client validation is NOT a
// security boundary. Every rule in it can be skipped by anyone willing to
// call the REST API and the storage API directly with their own JWT. This
// function is the boundary, because it is the only thing that (a) reads
// bytes the caller never handled, (b) compares them against the row that
// claims them, and (c) is allowed to set `active`.
//
// That last part is the load-bearing one, and it is enforced in the
// database rather than here: the `product_models` trigger added by
// 20260928120000_gate_product_model_active.sql refuses `status='active'`
// from any PostgREST role, so this function — running with the service
// role — is the only writer that can flip a model live. Which is why the
// function *must* also be the thing that writes `rejected`: a row this
// function never saw can be a draft or a rejected work item, but it can
// never be served to a customer.
//
// ── What it checks, and what it refuses to claim ──────────────────
// The rule set is `lib/utils/glb_validator.dart` (V2.7), mirrored in
// `_shared/glb_validator.ts` because an Edge Function cannot import Dart.
// `tool/check_glb_validator_parity.mjs` diffs the two over 22 fixtures, so
// the app and the server cannot drift into telling a partner two different
// things. On top of that mirror this function checks something no offline
// run can: that the bytes in the bucket hash to `product_models.sha256`
// (the value V2.5's device cache keys on) and that the sidecar numbers the
// client wrote — triangle count, file size — match what the server
// measures. A mismatch is not a style problem: it means the row and the
// object describe different files.
//
// Four things stay reviewer rows in SHOE_MODEL_AUTHORING_GUIDE.md §5.2
// and are named in every response: toe-vs-heel direction (a bounding box
// is symmetric about that question), albedo de-lighting, likeness, and
// on-device frame rate. `ok: true` means "the bytes satisfy the contract",
// not "this is a shippable shoe".
//
// ── Request / response ───────────────────────────────────────────
//   POST { "model_id": 12, "activate": true }
//   -> 200 { ok: true,  action: "activated", status: "active", report, integrity }
//   -> 422 { ok: false, action: "rejected",  status: "rejected", report, integrity }
//   -> 400 / 401 / 403 / 404 / 429 / 500 for the failures the seller can act on
//
// Env: SUPABASE_URL, SUPABASE_ANON_KEY (caller identity), SUPABASE_SERVICE_ROLE_KEY
//
// Deploy: supabase functions deploy validate-shoe-model
// (verify_jwt stays at its default, true — see supabase/config.toml)
// ══════════════════════════════════════════════════════════════════

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  checkRateLimit,
  rateLimitedResponse,
} from "../_shared/rate_limit.ts";
import {
  FILE_SIZE_HARD_CAP_BYTES,
  validateGlb,
} from "../_shared/glb_validator.ts";

/** The client shape, taken from the factory so no type-only import is needed. */
type Client = ReturnType<typeof createClient>;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Content-Type": "application/json",
};

/** The only bucket a model row may point into. */
const MODEL_BUCKET = "shoe-models";

/** `product_models.status` after a verdict. */
type ModelStatus = "active" | "rejected" | "draft";

/**
 * What the contract cannot decide, repeated in every response so no client
 * can render `ok: true` as "this shoe is approved". Same four rows the CLI
 * footer and the guide's §5.2 checklist name.
 */
const REVIEWER_ONLY = [
  "toe vs heel direction (a bounding box is symmetric about it)",
  "de-lit albedo (the bytes cannot show whether lighting was baked in)",
  "likeness to the physical shoe",
  "frame rate on a real device",
];

interface Row {
  id: number;
  product_id: string;
  storage_path: string;
  sha256: string;
  authored_length_mm: number | null;
  authored_size_eu: number | null;
  shoe_side: string | null;
  triangle_count: number | null;
  file_size_bytes: number | null;
  status: string;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: corsHeaders });
}

/** Lowercase hex SHA-256 of the bytes, the form `product_models.sha256` stores. */
async function sha256Hex(bytes: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

function asNumber(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string" && value.trim() !== "") {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) return parsed;
  }
  return null;
}

/** `undefined`/`null` both mean "the row has no number here". */
function rowNumber(value: unknown): number | null {
  const parsed = asNumber(value);
  return parsed === null ? null : parsed;
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "Method not allowed — POST the model row id." }, 405);
  }

  // One publish is a single call, so this limit is only about abuse: each
  // call downloads up to the bucket cap and parses it. 30/min leaves room
  // for a seller fixing and re-publishing a model repeatedly.
  const rl = await checkRateLimit(req, "validate-shoe-model", 30);
  if (!rl.allowed) return rateLimitedResponse(rl, corsHeaders);

  try {
    let payload: Record<string, unknown>;
    try {
      payload = await req.json();
    } catch {
      return json({ error: "Body must be JSON: { model_id: <number> }." }, 400);
    }

    const modelId = asNumber(payload.model_id);
    if (modelId === null || !Number.isInteger(modelId) || modelId <= 0) {
      return json(
        {
          error:
            "Missing model_id. Upload the object and insert the product_models " +
            "row first — this function validates bytes against a row.",
        },
        400,
      );
    }
    const activate = payload.activate === undefined ? true : payload.activate === true;

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    if (!supabaseUrl || !anonKey || !serviceKey) {
      console.error("[validate-shoe-model] missing SUPABASE_* secrets");
      return json({ error: "Server is misconfigured; nothing was validated." }, 500);
    }

    // ── Who is asking ────────────────────────────────────────────
    const authHeader = req.headers.get("Authorization") ?? "";
    if (!authHeader) {
      return json({ error: "Sign in again — no user token on the request." }, 401);
    }
    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: authData, error: authError } = await userClient.auth.getUser();
    const user = authData?.user ?? null;
    if (authError || user === null) {
      console.error("[validate-shoe-model] auth failed:", authError?.message);
      return json({ error: "Sign in again — your session is not valid." }, 401);
    }

    const service = createClient(supabaseUrl, serviceKey);

    // ── The row, and whether this caller may change it ────────────
    // Read with the service role so a missing row and a row the caller does
    // not own can be told apart, then check ownership explicitly rather
    // than borrowing RLS: an `active` row is world-readable, and "I can see
    // it" must not become "I can re-validate it into rejection".
    const { data: rowData, error: rowError } = await service
      .from("product_models")
      .select(
        "id, product_id, storage_path, sha256, authored_length_mm, " +
          "authored_size_eu, shoe_side, triangle_count, file_size_bytes, status",
      )
      .eq("id", modelId)
      .maybeSingle();

    if (rowError) {
      console.error("[validate-shoe-model] row read failed:", rowError.message);
      return json({ error: "Could not read the model row." }, 500);
    }
    if (rowData === null) {
      return json({ error: `No product_models row ${modelId}.` }, 404);
    }
    const row = rowData as unknown as Row;

    if (!(await callerOwnsProduct(userClient, service, row.product_id, user.id))) {
      return json(
        { error: "That model belongs to another store." },
        403,
      );
    }

    // ── The bytes the row claims ─────────────────────────────────
    const { data: fileData, error: downloadError } = await service.storage
      .from(MODEL_BUCKET)
      .download(row.storage_path);

    if (downloadError || fileData === null) {
      console.error(
        `[validate-shoe-model] download failed ${MODEL_BUCKET}/${row.storage_path}:`,
        downloadError?.message ?? "no data",
      );
      return json(
        {
          error:
            "The row points at a file that is not in the bucket, so there is " +
            "nothing to validate. Re-upload the model.",
          storagePath: row.storage_path,
        },
        404,
      );
    }

    const bytes = new Uint8Array(await fileData.arrayBuffer());
    if (bytes.length > FILE_SIZE_HARD_CAP_BYTES) {
      // The bucket cap should make this unreachable; if it is reached, the
      // object is bigger than any row may describe, and parsing it is not
      // worth the memory.
      console.error(
        `[validate-shoe-model] ${bytes.length} B at ${row.storage_path} exceeds the bucket cap`,
      );
      return json(
        { error: `Object is ${bytes.length} B, over the 8 MiB bucket cap.` },
        413,
      );
    }

    // ── The contract, over bytes the caller never handled ────────
    const measuredSha = await sha256Hex(bytes);
    const shaMatches = measuredSha === row.sha256;

    const declaredLengthMm =
      asNumber(payload.external_length_mm) ??
      rowNumber(row.authored_length_mm);

    const report = validateGlb(bytes, {
      label: row.storage_path,
      externalLengthMm: declaredLengthMm,
      authoredSizeEu: rowNumber(row.authored_size_eu),
      shoeSide: row.shoe_side,
    });

    // The two numbers the client also wrote. They are diagnostics, not
    // gates: the sha is the gate, because it is what the device cache keys
    // on. Kept in the response so a mismatch is visible rather than silent.
    const integrity = {
      sha256: {
        declared: row.sha256,
        measured: measuredSha,
        matches: shaMatches,
      },
      triangleCount: {
        declared: row.triangle_count,
        measured: report.triangleCount,
        agrees: row.triangle_count === null || row.triangle_count === report.triangleCount,
      },
      fileSizeBytes: {
        declared: row.file_size_bytes,
        measured: bytes.length,
        agrees: row.file_size_bytes === null || row.file_size_bytes === bytes.length,
      },
      meshExternalLengthMm: report.meshExternalLengthMm,
      declaredExternalLengthMm: declaredLengthMm,
    };

    const passed = report.passed && shaMatches;

    // ── The verdict, written where it counts ─────────────────────
    const patch: Record<string, unknown> = { file_size_bytes: bytes.length };
    if (report.triangleCount !== null && report.triangleCount > 0) {
      // `triangle_count > 0` is a CHECK; a file with no triangles is
      // already failing the contract, so the column keeps whatever it had.
      patch.triangle_count = report.triangleCount;
    }

    const status: ModelStatus = passed
      ? activate
        ? "active"
        : row.status === "active"
        ? "active"
        : "draft"
      : "rejected";
    patch.status = status;

    const { error: updateError } = await service
      .from("product_models")
      .update(patch)
      .eq("id", modelId);

    if (updateError) {
      console.error(
        "[validate-shoe-model] verdict write failed:",
        updateError.message,
      );
      return json(
        {
          error:
            "The model was validated but its status could not be recorded, so " +
            "it stays as it was.",
          detail: updateError.message,
          ok: passed,
          report: report.toJson(),
          integrity,
        },
        500,
      );
    }

    const action = passed
      ? status === "active"
        ? "activated"
        : "validated"
      : "rejected";

    if (passed) {
      console.log(
        `[validate-shoe-model] ✓ ${MODEL_BUCKET}/${row.storage_path} → ${action} ` +
          `(${report.triangleCount} triangles, ${bytes.length} B)`,
      );
    } else {
      const failed = report.checks
        .filter((c) => c.status === "fail")
        .map((c) => c.name);
      console.error(
        `[validate-shoe-model] ✗ REJECTED ${MODEL_BUCKET}/${row.storage_path}: ` +
          `${failed.join(", ")}${shaMatches ? "" : ", sha256"}`,
      );
    }

    return json(
      {
        ok: passed,
        action,
        status,
        modelId,
        storagePath: row.storage_path,
        // Named on every response so a green report is never read as
        // "approved": the same four rows the CLI footer lists.
        notChecked: REVIEWER_ONLY,
        integrity,
        report: report.toJson(),
      },
      passed ? 200 : 422,
    );
  } catch (e) {
    console.error("[validate-shoe-model] Error:", e);
    return json({ error: String(e) }, 500);
  }
});

/**
 * True when the caller owns the store that `productId` belongs to, or is an
 * admin. The admin test is `public.is_admin()` run through the *caller's*
 * client, so it evaluates against their own claims rather than the service
 * role's empty session.
 */
async function callerOwnsProduct(
  userClient: Client,
  service: Client,
  productId: string,
  userId: string,
): Promise<boolean> {
  const { data, error } = await service
    .from("products")
    .select("store_id, stores!inner(owner_id)")
    .eq("id", productId)
    .maybeSingle();

  if (error) {
    console.error(
      "[validate-shoe-model] ownership read failed:",
      error.message,
    );
    return false;
  }

  const store = (data as { stores?: { owner_id?: string } } | null)?.stores;
  if (store?.owner_id === userId) return true;

  const { data: isAdmin, error: adminError } = await userClient.rpc("is_admin");
  if (adminError) {
    console.warn(
      "[validate-shoe-model] is_admin() unavailable:",
      adminError.message,
    );
    return false;
  }
  return isAdmin === true;
}
