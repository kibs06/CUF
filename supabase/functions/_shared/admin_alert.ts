// Best-effort admin alerting for PayMongo mode-guard trips.
//
// The guard's job is to stop the wrong money from moving; telling a human
// about it is a courtesy layered on top, and must never become a new way for
// a payment request to fail. So every function here:
//
//   • never throws — an error, a rejected insert (e.g. the
//     `admin_notifications.type` CHECK not yet migrated on the live DB), or
//     a missing RPC all resolve to `false` and a log line;
//   • never touches the caller's control flow — the webhook's 500/200 and
//     checkout's 503 are decided entirely by the disposition, before this is
//     called;
//   • writes through the service role, because `admin_notifications` has no
//     INSERT policy by design (the RPC is SECURITY DEFINER and granted to
//     service_role only).
//
// Deliberately dependency-free (no Deno globals, no supabase-js import) so the
// pure behaviour is testable under Node — see
// supabase/tests/functions/paymongo_mode.test.mjs.

/** The slice of a supabase-js client this module needs. */
export interface AdminAlertClient {
  rpc: (
    fn: string,
    args?: Record<string, unknown>,
  ) => PromiseLike<{ error?: { message?: string } | null }> | { error?: { message?: string } | null };
}

export interface ModeMismatchAlert {
  /** Which guard tripped. */
  source: "webhook" | "checkout";
  /** `retry` (500) or `acknowledge` (200) for webhook; `blocked` for checkout. */
  disposition: string;
  /** Human sentence describing what was refused. */
  detail: string;
  /** Mode encoded in the configured secret key, when known. */
  keyMode?: string;
  /** Mode we are configured to run in. */
  configuredMode: string;
  orderId?: string | null;
  eventId?: string | null;
  eventType?: string | null;
}

const ALERT_TITLE = "GCash payment blocked — PayMongo mode mismatch";

function buildBody(alert: ModeMismatchAlert): string {
  const where = alert.source === "webhook"
    ? `Webhook ${alert.eventId ? `${alert.eventId} ` : ""}${alert.eventType ? `(${alert.eventType}) ` : ""}`
    : "Online checkout ";
  const modes = alert.keyMode
    ? `Key mode: ${alert.keyMode}. Configured: ${alert.configuredMode}.`
    : `Configured mode: ${alert.configuredMode}.`;
  return `${where}${alert.detail} ${modes}`.replace(/\s+/g, " ").trim();
}

/**
 * Ask the database to notify every admin about a guard trip.
 *
 * @returns true when the RPC accepted the write, false on ANY failure
 *          (including a missing RPC or a CHECK that has not been migrated).
 *          Never throws.
 */
export async function notifyAdminsPaymentModeMismatch(
  client: AdminAlertClient | null | undefined,
  alert: ModeMismatchAlert,
): Promise<boolean> {
  if (!client || typeof client.rpc !== "function") return false;
  try {
    const result = await client.rpc("notify_admins_payment_mode_mismatch", {
      p_source: alert.source,
      p_title: ALERT_TITLE,
      p_body: buildBody(alert),
      p_metadata: {
        kind: "payment_mode_mismatch",
        source: alert.source,
        disposition: alert.disposition,
        key_mode: alert.keyMode ?? null,
        configured_mode: alert.configuredMode,
        order_id: alert.orderId ?? null,
        event_id: alert.eventId ?? null,
        event_type: alert.eventType ?? null,
      },
    });
    const error = result?.error;
    if (error) {
      // Expected while the migration is unapplied (type CHECK / missing
      // function). Log it and carry on: the guard already did its job.
      console.error(
        "[ALERT] admin mode-mismatch notification not written:",
        error.message ?? "unknown error",
      );
      return false;
    }
    return true;
  } catch (e) {
    console.error(
      "[ALERT] admin mode-mismatch notification threw (swallowed):",
      (e as any)?.message ?? e,
    );
    return false;
  }
}
