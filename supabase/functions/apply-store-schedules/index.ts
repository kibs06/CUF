// supabase/functions/apply-store-schedules/index.ts
//
// Automated store open/close scheduler.
// The live path is the pg_cron job 'apply-store-schedules' (pure SQL, see
// migration 20260817150000_add_store_auto_schedule_cron.sql) which runs
// every 5 minutes. This function is kept for manual/external invocation
// (e.g. `supabase functions serve` or an out-of-band cron) and mirrors the
// same schedule logic.
// Uses the service_role key to bypass RLS.
//
// Timezone: Asia/Manila (UTC+8). Store open_time/close_time are local wall-clock.
// Overnight schedules: close_time < open_time means the window spans midnight.
// Manual override: respected until the schedule itself agrees with the manual
//                  state (e.g. a manual close persists only until the posted
//                  close time passes), then cleared so automatic control resumes.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { checkRateLimit, rateLimitedResponse } from "../_shared/rate_limit.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const supabase = createClient(supabaseUrl, supabaseKey);

// Philippine time: UTC+8
const TZ_OFFSET_HOURS = 8;

function getLocalNow(): Date {
  const utc = new Date();
  return new Date(utc.getTime() + TZ_OFFSET_HOURS * 60 * 60 * 1000);
}

/** Parse "HH:MM:SS" or "HH:MM" into minutes since midnight (local). */
function parseTimeToMinutes(timeStr: string): number {
  const parts = timeStr.split(":");
  const h = parseInt(parts[0], 10);
  const m = parseInt(parts[1], 10);
  return h * 60 + m;
}

/**
 * Determine if local wall-clock time is within [openMinutes, closeMinutes).
 * Handles overnight schedules where close < open (window wraps past midnight).
 */
function isWithinSchedule(
  currentMinutes: number,
  openMinutes: number,
  closeMinutes: number,
): boolean {
  if (openMinutes <= closeMinutes) {
    // Normal schedule: 09:00–21:00
    return currentMinutes >= openMinutes && currentMinutes < closeMinutes;
  } else {
    // Overnight: 18:00–02:00 → open at 18:00 (1080), close at 02:00 (120)
    return currentMinutes >= openMinutes || currentMinutes < closeMinutes;
  }
}

Deno.serve(async (req) => {
  // T6: per-IP rate limit (30/min — the pg_cron job fires every 5 min;
  // this only stops scripted HTTP invocation of the scheduler).
  const rl = await checkRateLimit(req, "apply-store-schedules", 30);
  if (!rl.allowed) return rateLimitedResponse(rl, {});

  try {
    const localNow = getLocalNow();
    const currentMinutes = localNow.getHours() * 60 + localNow.getMinutes();

    // Fetch all stores with auto-schedule enabled
    const { data: stores, error: fetchError } = await supabase
      .from("stores")
      .select("id, open_time, close_time, manual_override, is_open")
      .eq("auto_schedule_enabled", true)
      .eq("is_active", true);

    if (fetchError) {
      console.error("Failed to fetch stores:", fetchError.message);
      return new Response(JSON.stringify({ error: fetchError.message }), {
        status: 500,
      });
    }

    if (!stores || stores.length === 0) {
      return new Response(JSON.stringify({ processed: 0 }), { status: 200 });
    }

    let processed = 0;

    for (const store of stores) {
      const { id, open_time, close_time, manual_override } = store;

      // Skip stores without valid times set
      if (!open_time || !close_time) continue;

      const openMinutes = parseTimeToMinutes(open_time);
      const closeMinutes = parseTimeToMinutes(close_time);
      const shouldBeOpen = isWithinSchedule(currentMinutes, openMinutes, closeMinutes);

      if (manual_override) {
        // Seller manually forced a state that differs from the schedule.
        // Keep it until the schedule itself agrees with that state — at
        // that point the override is moot and automatic control resumes.
        // (A previous exact-minute equality check missed boundaries the
        // 5-minute cron never hit on the dot, leaving overrides stuck.)
        const agreesWithSchedule = store.is_open === shouldBeOpen;
        if (agreesWithSchedule) {
          // Clear override and apply schedule
          const { error: updateError } = await supabase
            .from("stores")
            .update({
              is_open: shouldBeOpen,
              manual_override: false,
            })
            .eq("id", id);

          if (updateError) {
            console.error(`Failed to update store ${id}:`, updateError.message);
          } else {
            processed++;
          }
        }
        // Otherwise: respect the manual override, do nothing
      } else {
        // No override: apply schedule directly
        const { error: updateError } = await supabase
          .from("stores")
          .update({ is_open: shouldBeOpen })
          .eq("id", id);

        if (updateError) {
          console.error(`Failed to update store ${id}:`, updateError.message);
        } else {
          processed++;
        }
      }
    }

    return new Response(JSON.stringify({ processed, total: stores.length }), {
      status: 200,
    });
  } catch (err) {
    console.error("Unexpected error:", err);
    return new Response(JSON.stringify({ error: String(err) }), { status: 500 });
  }
});
