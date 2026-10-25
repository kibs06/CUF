// ══════════════════════════════════════════════════════════════════
// reconstruct-foot — trigger cloud reconstruction for a 360° foot scan
//
// Called by: the customer portal after a sweep upload finishes
// (`finishFootScanUpload` → job status `queued`), and by the results
// page retry button.
//
// Contract:
//   POST /reconstruct-foot  { jobId: "<uuid>" }   (user JWT required —
//   verify_jwt stays at its default `true`, unlike the pre-auth payment
//   functions in config.toml. The function ALSO checks row ownership,
//   so a valid JWT for user A can never trigger user B's job.)
//
// Flow:
//   1. Load the job, confirm caller owns it and it is `queued`/`failed`
//      (failed jobs may retry — anything else is a 409).
//   2. Flip to `processing` so double-taps do not double-trigger.
//   3. Call the reconstruction worker (`RECONSTRUCT_WORKER_URL`, JSON:
//      { jobId, userId, frameCount }). The worker is pluggable — managed
//      photogrammetry API first, own GPU worker later — and answers
//      { meshPath, measurements } on success.
//   4. Write `done` (+ mesh + measurements) or `failed` (+ machine code
//      and a customer-safe sentence the results page shows verbatim).
//
// No vendor selected yet: with RECONSTRUCT_WORKER_URL unset the job is
// marked failed as `worker_not_configured` instead of hanging in
// `processing` forever — an honest queue, not a silent one.
//
// Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY,
//      RECONSTRUCT_WORKER_URL (optional until vendor chosen),
//      RECONSTRUCT_WORKER_SECRET (optional bearer for the worker).
//
// Deploy: supabase functions deploy reconstruct-foot
// ══════════════════════════════════════════════════════════════════

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { checkRateLimit, rateLimitedResponse } from "../_shared/rate_limit.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const TRIGGER_RATE_LIMIT = 10; // per IP per minute — a sweep triggers once

function json(
  body: unknown,
  status = 200,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function serviceClient() {
  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!url || !key) throw new Error("SUPABASE_URL/KEY not configured");
  return createClient(url, key);
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "method not allowed" }, 405);
  }

  try {
    const rl = await checkRateLimit(req, "reconstruct-foot:trigger", TRIGGER_RATE_LIMIT);
    if (!rl.allowed) return rateLimitedResponse(rl, corsHeaders);

    const { jobId } = (await req.json()) as { jobId?: string };
    if (!jobId || typeof jobId !== "string") {
      return json({ error: "missing jobId" }, 400);
    }

    // Caller identity comes from the verified JWT (verify_jwt = true).
    const authHeader = req.headers.get("authorization") ?? "";
    const jwt = authHeader.replace(/^Bearer\s+/i, "");
    if (!jwt) return json({ error: "unauthorized" }, 401);
    const { data: { user }, error: userError } = await serviceClient().auth.getUser(jwt);
    if (userError || !user) return json({ error: "unauthorized" }, 401);

    const db = serviceClient();
    const { data: job, error: jobError } = await db
      .from("foot_scan_jobs")
      .select("*")
      .eq("id", jobId)
      .single();
    if (jobError || !job) return json({ error: "job not found" }, 404);
    if (job.user_id !== user.id) return json({ error: "forbidden" }, 403);
    if (job.status !== "queued" && job.status !== "failed") {
      return json({ error: `job is ${job.status}, not triggerable` }, 409);
    }

    await db.from("foot_scan_jobs").update({
      status: "processing",
      error_code: null,
      error_message: null,
      updated_at: new Date().toISOString(),
    }).eq("id", jobId);

    const workerUrl = Deno.env.get("RECONSTRUCT_WORKER_URL") ?? "";
    if (!workerUrl) {
      // No vendor wired yet — fail loudly, never stall.
      await db.from("foot_scan_jobs").update({
        status: "failed",
        error_code: "worker_not_configured",
        error_message:
          "3D reconstruction is not switched on yet — your sweep is saved and will process once it is.",
        updated_at: new Date().toISOString(),
      }).eq("id", jobId);
      return json({ ok: true, status: "failed", errorCode: "worker_not_configured" });
    }

    const workerSecret = Deno.env.get("RECONSTRUCT_WORKER_SECRET") ?? "";
    const upstream = await fetch(workerUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        ...(workerSecret ? { Authorization: `Bearer ${workerSecret}` } : {}),
      },
      body: JSON.stringify({
        jobId,
        userId: user.id,
        frameCount: job.frame_count,
      }),
    });
    if (!upstream.ok) {
      console.error(`[reconstruct-foot] worker ${upstream.status} for job ${jobId}`);
      await db.from("foot_scan_jobs").update({
        status: "failed",
        error_code: "worker_error",
        error_message: "Reconstruction failed — retry in a bit.",
        updated_at: new Date().toISOString(),
      }).eq("id", jobId);
      return json({ ok: true, status: "failed", errorCode: "worker_error" });
    }

    const result = (await upstream.json()) as {
      meshPath?: string;
      measurements?: Record<string, unknown>;
    };
    if (!result.meshPath) {
      await db.from("foot_scan_jobs").update({
        status: "failed",
        error_code: "worker_bad_response",
        error_message: "Reconstruction failed — retry in a bit.",
        updated_at: new Date().toISOString(),
      }).eq("id", jobId);
      return json({ ok: true, status: "failed", errorCode: "worker_bad_response" });
    }

    await db.from("foot_scan_jobs").update({
      status: "done",
      mesh_path: result.meshPath,
      measurements: result.measurements ?? {},
      updated_at: new Date().toISOString(),
    }).eq("id", jobId);
    return json({ ok: true, status: "done" });
  } catch (e) {
    console.error("[reconstruct-foot] handler error:", (e as Error)?.message ?? e);
    return json({ error: "internal error" }, 500);
  }
});
