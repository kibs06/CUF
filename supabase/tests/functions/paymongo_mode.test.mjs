// PayMongo mode-guard contract tests.
//
// These cover the pieces that decide whether money moves in the right
// environment: the key/flag mode check, the webhook disposition table, the
// fail-closed `livemode` parsing, and webhook signature verification. They
// live here (not in functions/) because Edge Functions only upload the files
// they import — a test next to the source would ship to production.
//
// Run:  node --experimental-strip-types supabase/tests/functions/paymongo_mode.test.mjs
// (Node >= 22.6; also wired into .github/workflows/ci.yml)
//
// The shared module reads configuration through `Deno.env`, so the runner
// installs a minimal stub. Nothing else here needs the Deno runtime.

import assert from "node:assert/strict";
import { createHmac } from "node:crypto";

let env = {};
globalThis.Deno = { env: { get: (key) => env[key] } };

const m = await import("../../functions/_shared/paymongo.ts");

let passed = 0;
function check(fn) {
  fn();
  passed += 1;
}
async function checkAsync(fn) {
  await fn();
  passed += 1;
}

// ── 1. Key prefix parsing ──────────────────────────────────────────
// Synthetic placeholder, built from parts: the guard only reads the prefix, so
// a key-shaped fixture is enough — and a literal that *looks* like a real
// PayMongo test key trips GitHub push protection (correctly) on every push.
const TEST_KEY = `sk_test_${"fixture".repeat(4)}`;
check(() => assert.equal(m.secretKeyMode(TEST_KEY), "test"));
check(() => assert.equal(m.secretKeyMode("sk_live_abc123"), "live"));
check(() => assert.equal(m.secretKeyMode(""), "unknown"));
check(() => assert.equal(m.secretKeyMode("pk_live_x"), "unknown"));
check(() => assert.equal(m.secretKeyMode("sk_test"), "unknown"));

// ── 2. PAYMONGO_LIVEMODE parsing (exact `true` only) ───────────────
check(() => assert.equal(m.configuredLivemodeMode("true"), "live"));
check(() => assert.equal(m.configuredLivemodeMode(undefined), "test"));
check(() => assert.equal(m.configuredLivemodeMode("TRUE"), "test"));
check(() => assert.equal(m.configuredLivemodeMode("1"), "test"));

// ── 3. assertPaymongoModeMatch fails closed on any disagreement ────
check(() => {
  env = { PAYMONGO_SECRET_KEY: "sk_live_abc", PAYMONGO_LIVEMODE: "true" };
  assert.equal(m.assertPaymongoModeMatch(), "live");
});
check(() => {
  env = { PAYMONGO_SECRET_KEY: "sk_test_abc", PAYMONGO_LIVEMODE: "false" };
  assert.equal(m.assertPaymongoModeMatch(), "test");
});
check(() => {
  env = { PAYMONGO_SECRET_KEY: "sk_test_abc", PAYMONGO_LIVEMODE: "true" };
  assert.throws(() => m.assertPaymongoModeMatch(), m.PaymongoModeMismatchError);
});
check(() => {
  env = { PAYMONGO_SECRET_KEY: "sk_live_abc" };
  assert.throws(() => m.assertPaymongoModeMatch(), m.PaymongoModeMismatchError);
});
check(() => {
  env = { PAYMONGO_SECRET_KEY: "sk_rotated_abc", PAYMONGO_LIVEMODE: "true" };
  assert.throws(() => m.assertPaymongoModeMatch(), m.PaymongoModeMismatchError);
});

// ── 4. Webhook disposition table ──────────────────────────────────
check(() => assert.equal(m.eventModeDisposition(true, true), "ok"));
check(() => assert.equal(m.eventModeDisposition(false, false), "ok"));
check(() => assert.equal(m.eventModeDisposition(true, false), "retry"));
check(() => assert.equal(m.eventModeDisposition(false, true), "acknowledge"));

// ── 5. Event parsing: livemode must be DISTINGUISHED from absent ──
function envelope(attrs) {
  return JSON.stringify({
    data: {
      id: "evt_test_1",
      type: "event",
      attributes: {
        type: "checkout_session.payment.paid",
        ...attrs,
        data: { id: "cs_test_1", type: "checkout_session", attributes: {} },
      },
    },
  });
}
check(() => {
  const e = m.parseWebhookEvent(envelope({ livemode: true }));
  assert.equal(e.livemode, true);
  assert.equal(e.livemodeKnown, true);
});
check(() => {
  const e = m.parseWebhookEvent(envelope({ livemode: false }));
  assert.equal(e.livemode, false);
  assert.equal(e.livemodeKnown, true);
});
check(() => {
  // Absent: parser default is false, but `livemodeKnown` says we cannot trust it.
  const e = m.parseWebhookEvent(envelope({}));
  assert.equal(e.livemode, false);
  assert.equal(e.livemodeKnown, false);
});
check(() => {
  // A non-boolean value is not a mode statement either.
  const e = m.parseWebhookEvent(envelope({ livemode: "false" }));
  assert.equal(e.livemodeKnown, false);
});
check(() => {
  const e = m.parseWebhookEvent(envelope({ livemode: false }));
  assert.equal(e.id, "evt_test_1");
  assert.equal(e.type, "checkout_session.payment.paid");
  assert.equal(e.data.id, "cs_test_1");
  assert.equal(e.redacted.livemode_known, true);
});

// ── 6. Webhook signature verification ─────────────────────────────
const SECRET = "whsk_test_unit_secret";
const BODY = envelope({ livemode: false });
const ts = Math.floor(Date.now() / 1000);
const sign = (secret, timestamp, body) =>
  createHmac("sha256", secret).update(`${timestamp}.${body}`).digest("hex");

await checkAsync(async () => {
  assert.equal(
    await m.verifyWebhookSignature(BODY, `t=${ts},te=${sign(SECRET, ts, BODY)},li=`, SECRET),
    true,
  );
});
await checkAsync(async () => {
  // PayMongo sends one populated part and one empty part; an empty `li` must
  // fall through to `te` (regression: incident 2026-09-07).
  assert.equal(
    await m.verifyWebhookSignature(BODY, `t=${ts},te=,li=${sign(SECRET, ts, BODY)}`, SECRET),
    true,
  );
});
await checkAsync(async () => {
  assert.equal(
    await m.verifyWebhookSignature(BODY, `t=${ts},te=${sign("wrong", ts, BODY)}`, SECRET),
    false,
  );
});
await checkAsync(async () => {
  assert.equal(await m.verifyWebhookSignature(BODY, "", SECRET), false);
});
await checkAsync(async () => {
  const stale = ts - 601;
  assert.equal(
    await m.verifyWebhookSignature(BODY, `t=${stale},te=${sign(SECRET, stale, BODY)}`, SECRET),
    false,
  );
});
await checkAsync(async () => {
  // Tampered body with a signature for the original one.
  const tampered = envelope({ livemode: true });
  assert.equal(
    await m.verifyWebhookSignature(tampered, `t=${ts},te=${sign(SECRET, ts, BODY)}`, SECRET),
    false,
  );
});

// ── 7. Webhook guard: one decision, one status, one notify flag ───
// The status a mismatch produces is decided by this pure function, BEFORE any
// notification is attempted — that ordering is what makes the insert unable to
// change the webhook's outcome.
check(() => {
  assert.deepEqual(m.evaluateWebhookModeGuard(false, true, false), {
    disposition: "ok",
    status: 200,
    retryable: false,
    notifyAdmins: false,
  });
});
check(() => {
  // Leftover sandbox checkout in a live store: audited, acknowledged, admin told.
  assert.deepEqual(m.evaluateWebhookModeGuard(false, true, true), {
    disposition: "acknowledge",
    status: 200,
    retryable: false,
    notifyAdmins: true,
  });
});
check(() => {
  // Real live money while we are configured for test: retry AND tell an admin.
  assert.deepEqual(m.evaluateWebhookModeGuard(true, true, false), {
    disposition: "retry",
    status: 500,
    retryable: true,
    notifyAdmins: true,
  });
});
check(() => {
  // No boolean livemode in the payload: fail closed, retry, tell an admin.
  assert.deepEqual(m.evaluateWebhookModeGuard(false, false, true), {
    disposition: "retry",
    status: 500,
    retryable: true,
    notifyAdmins: true,
  });
});
check(() => {
  assert.equal(m.evaluateWebhookModeGuard(true, false, false).status, 500);
});

// ── 8. Admin notification: requested, and provably non-fatal ──────
const alert = await import("../../functions/_shared/admin_alert.ts");

async function quietly(fn) {
  const original = console.error;
  console.error = () => {};
  try {
    return await fn();
  } finally {
    console.error = original;
  }
}

const ALERT = {
  source: "webhook",
  disposition: "retry",
  detail: "live-mode event refused because this project runs in test-mode.",
  configuredMode: "test",
  eventId: "evt_1",
  eventType: "payment.paid",
};

await checkAsync(async () => {
  const calls = [];
  const ok = await alert.notifyAdminsPaymentModeMismatch(
    {
      rpc: async (fn, args) => {
        calls.push({ fn, args });
        return { error: null };
      },
    },
    ALERT,
  );
  assert.equal(ok, true);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].fn, "notify_admins_payment_mode_mismatch");
  assert.equal(calls[0].args.p_source, "webhook");
  assert.equal(calls[0].args.p_metadata.kind, "payment_mode_mismatch");
  assert.match(calls[0].args.p_body, /live-mode event refused/);
});
await checkAsync(async () => {
  // The expected state while the migration is unapplied: CHECK rejects it.
  const ok = await quietly(() =>
    alert.notifyAdminsPaymentModeMismatch(
      { rpc: async () => ({ error: { message: "violates check constraint" } }) },
      ALERT,
    ),
  );
  assert.equal(ok, false);
});
await checkAsync(async () => {
  const ok = await quietly(() =>
    alert.notifyAdminsPaymentModeMismatch(
      {
        rpc: () => {
          throw new Error("socket hang up");
        },
      },
      ALERT,
    ),
  );
  assert.equal(ok, false);
});
await checkAsync(async () => {
  assert.equal(await alert.notifyAdminsPaymentModeMismatch(null, ALERT), false);
});
await checkAsync(async () => {
  // Non-fatal proof #1: retry disposition (500) survives a throwing insert.
  const guard = m.evaluateWebhookModeGuard(true, true, false);
  const before = { ...guard };
  await quietly(() =>
    alert.notifyAdminsPaymentModeMismatch(
      {
        rpc: () => {
          throw new Error("db down");
        },
      },
      ALERT,
    ),
  );
  assert.deepEqual(guard, before);
  assert.equal(guard.status, 500);
  assert.equal(guard.disposition, "retry");
});
await checkAsync(async () => {
  // Non-fatal proof #2: acknowledgment (200) survives a rejected insert.
  const guard = m.evaluateWebhookModeGuard(false, true, true);
  const before = { ...guard };
  await quietly(() =>
    alert.notifyAdminsPaymentModeMismatch(
      { rpc: async () => ({ error: { message: "type check" } }) },
      { ...ALERT, disposition: "acknowledge", configuredMode: "live" },
    ),
  );
  assert.deepEqual(guard, before);
  assert.equal(guard.status, 200);
  assert.equal(guard.disposition, "acknowledge");
});

console.log(`paymongo mode guards: ${passed} assertions passed`);
