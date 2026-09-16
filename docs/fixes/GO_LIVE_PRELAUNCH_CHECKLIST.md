# GO-LIVE PRELAUNCH CHECKLIST (before real users)

**Date:** September 3, 2026 (updated Sep 5, 2026 — T5 manual-GCash closure added to pending applies + done list; updated **Sep 17, 2026** — item 8 is now an executable runbook, see §R8)
**Status:** Open — items below must be resolved before the app takes real customers.
**Context:** Compiled from the T6 hardening, gcash-webhook secret outage, and reconciliation session. The live PayMongo account ("Carcar United Footwear") exists with `sk_live_`/`pk_live_` keys, but the app has only ever processed TEST-mode payments.

---

## 🔴 Critical — resolve before real money flows

1. **PayMongo LIVE wiring — verify + test end-to-end**
   - The LIVE webhook was created **Sep 3** at URL `https://psczvbfoybqhjeqssimw.supabase.co/functions/v1/gcash-webhook`. Confirm it exists on the LIVE environment and is subscribed to **`checkout_session.payment.paid`** (and ideally `payment.paid` + `payment.failed` as defensive events).
   - Confirm the project secret **`PAYMONGO_SECRET_KEY` is the LIVE key (`sk_live_…`)** and `PAYMONGO_LIVEMODE=true`. ⚠️ The only recorded payment intent (`pi_BA8zVibfwg16E4qhkfG1bnEi`, Aug 19) was created with a **TEST** key (`livemode: false`) — if the secret is still test, live checkouts will create test sessions or fail.
   - Do a **real end-to-end live test** before launch: place a small real GCash order → pay → confirm `gcash-webhook` returns 200 and the order finalizes (`status: pending`, `payment_status: paid`, `payment_verified_at` set, seller notified). PayMongo's dashboard "Send test webhook" only exercises delivery, not a real payment.
   - `PAYMONGO_WEBHOOK_SECRET` is now a project-wide secret (verified: bad signature → 401). Keep it project-wide, not function-scoped.

2. **MapTiler tiles are broken through the proxy**
   - Geocoding works via `geocode-proxy`, but **raster tiles return 403** from Supabase's servers with the current key (MapTiler error tile). Real users' map pickers will show error tiles.
   - Fix: generate a **server key** in the MapTiler dashboard (no referrer/IP restrictions, tiles + geocoding enabled) and update `MAPTILER_API_KEY`. Also **rotate/delete the old key** — it shipped inside app builds and git history.

3. **Public Edge Functions have NO authorization** (anonymous callers can forge requests)
   - `send-notification-push`, `send-message-push`, `create-gcash-payment`, `send-approval-email`, `send-lockout-email` are deployed `verify_jwt = false` and trust caller-supplied bodies (recipient IDs, user IDs, order IDs). Once real users exist, strangers could: push fake notifications to any user, spoof seller/customer messages, trigger approval/lockout emails, or create PayMongo charge attempts against arbitrary order IDs.
   - Fix (separate task): enable JWT verification and/or validate the caller's identity server-side. Rate limiting (shipped) only caps volume — it does not authenticate.

## 🟡 Should fix before launch

4. **Rate-limit + T5 migrations not confirmed applied.** `20260903030000_add_rate_limiting.sql` must be run (SQL Editor) + recorded in the migration ledger, or all the new rate limiters **fail open** (functions work, but there is no protection). **Also apply `20260905000000_fix_t5_manual_gcash_dedupe_audit.sql`** — until it runs, the manual-GCash reference dedupe and seller decision audit trail do not exist server-side (code shipped Sep 5, commit `6dee84b`). Also confirm the T3 ledger inserts (20260903000000–20260903020000) were recorded.
5. **Seller re-apply regression (T3):** the Sep 1 status guard blocks a rejected seller's re-submission (`rejected → pending` raises `Cannot change your own seller_status.`). Real rejected applicants cannot re-apply until fixed.
6. **Stale `awaiting_payment` orders are never expired.** The test order from Aug 19 sat in `awaiting_payment` for 2 weeks (no expiry sweep ran for PayMongo checkout sessions). Ensure the expiry/cancel cron is applied before launch so abandoned checkouts auto-cancel and stock is never held.
7. **Admin account hygiene:** the admin login (keithabalo03@gmail.com) was shared in plaintext during this session — change the password before launch.
8. **Auth e-mail delivery is unconfigured for the verify screens — this one blocks new sign-ups outright.** `enable_confirmations` is ON, so a user who never receives the code cannot finish creating an account (and the new-device step-up cannot complete either). GoTrue is still on its **built-in mailer**: `[auth.email.smtp]` in `supabase/config.toml` is commented out and no dashboard SMTP is set, which is a hard refusal for every address outside the Supabase organization and caps sending at 2 messages per hour. Fix: run the **📧 R8 runbook** at the end of this file — either the dashboard (**Authentication → SMTP Settings** → the app's own Gmail (`smtp.gmail.com:465`, `GMAIL_SENDER` + `GMAIL_APP_PASSWORD`, the same account `send-approval-email` already sends from), then `{{ .Token }}` in the **Confirm signup** and **Magic link** templates) or the one-command route, `dart run tool/apply_live_auth_mail.dart`, which does all of it and then re-reads every field. GoTrue must remain the sender — an app-owned sender leaves the session at `amr: ["password"]` and breaks the mint gate in `session_proves_possession()`, locking every device out of the gated tables. See `docs/AI/EMAIL_OTP_AND_DEVICE_TRUST_ARCHITECTURE.md` §5.1.

---

## 📧 R8 — Runbook: send GoTrue's auth e-mail from the app's own Gmail

**Why GoTrue must stay the sender.** The 6-digit code is minted by GoTrue and
stamped into the session as `amr: ["otp"]`, and `public.session_proves_possession()`
requires that claim before `trust_device()` will mint a device secret. A sender
we wrote ourselves would e-mail a code GoTrue never verified: the session stays
`amr: ["password"]`, the mint is refused (42501), and every device is then
denied the gated private tables once enforcement is switched on
(`docs/AI/EMAIL_OTP_AND_DEVICE_TRUST_ARCHITECTURE.md` §3.7, §5.1). The
constraint is on who **mints** the code, not on who relays it — pointing
GoTrue's own SMTP at the app's Gmail makes Gmail the sender *and* keeps the
gate intact.

**What is wrong today, in the order it must be fixed.**

1. **The live "Magic link" template is still the stock link-only one — this is
   the blocking defect.** Measured Sep 17, 2026 on a *delivered* step-up e-mail:
   headed "Your sign-in link", containing a `Sign in` button and **no 6-digit
   code anywhere**. The verify screen therefore has nothing to accept, however
   good delivery is. Fix = Step 3 below, and it comes first.
2. **Custom SMTP is still unconfigured** (`From: noreply@mail.app.supabase.io`),
   so GoTrue is on its built-in mailer: a ceiling of **2 messages/hour** on a
   best-effort service with no SLA, and — per
   https://supabase.com/docs/guides/auth/auth-smtp — delivery restricted to
   addresses inside the Supabase organization. That allowlist **did not bite**
   in the Sep 17 observation (a consumer Gmail received the mail), so treat it as
   documented behaviour to re-check rather than as the reason a code is missing.
   Steps 1–2 are about sender identity, branding and capacity; Step 3 is what
   makes a code exist at all.

> **Who applies this, and with what.** The project owner applies it (decided
> Sep 17, 2026), by either route below. Auth's SMTP settings are **not
> reachable from the Supabase CLI** — `supabase secrets set` feeds Edge
> Functions only, and `[auth.email.smtp]` in `config.toml` is ignored by the
> hosted project — so the switch is not in the CLI either way.
>
> * **Dashboard** — the steps below, one screen at a time. No token needed.
> * **One command** — `dart run tool/apply_live_auth_mail.dart` performs Steps
>   1, 2, 3 and 3b in a single Management API call, from the same two template
>   files, and then re-reads every field to confirm it stuck. This is the
>   route to re-run after a rotation, and it needs a personal access token
>   with `auth:write`.
>
> The two templates are already verified in-repo: both
> `supabase/templates/confirmation.html` and
> `supabase/templates/magic_link.html` carry `{{ .Token }}`, and
> `otp_length = 6` / `otp_expiry = 3600` still match `EmailOtpPolicy`
> (`test/services/email_otp_service_test.dart` passes).

### Steps 1–3b as one command (optional)

> Do the **Pre-flight** table just below first — this route needs both
> credentials to exist before it can set anything.

```bash
# Env first — the App Password never enters shell history or `ps` output.
export SUPABASE_ACCESS_TOKEN=...   # Dashboard → Account → Access Tokens (auth:write)
export GMAIL_SENDER=...            # the mailbox the Edge Functions send from
export GMAIL_APP_PASSWORD=...      # its 16-char App Password

dart run tool/apply_live_auth_mail.dart --dry-run     # what it will send (secret masked)
dart run tool/apply_live_auth_mail.dart               # apply, then verify
dart run tool/apply_live_auth_mail.dart --check       # re-verify only; writes nothing
```

What it sets, all in one `PATCH /v1/projects/{ref}/config/auth`: custom SMTP
(`smtp.gmail.com`, port `465` **as a string**, sender + envelope sender =
`GMAIL_SENDER`, sender name `CUFMAI`), `rate_limit_email_sent` **(100/h)**, the
confirmations/OTP numbers (`mailer_autoconfirm: false`, `mailer_otp_length: 6`,
`mailer_otp_exp: 3600`), both templates' bodies **and** subjects, and the
redirect allow list with `solvision://auth/confirm` **appended to whatever is
already there** (a PATCH replaces that field, so the tool reads it first —
copy-pasting a hand-built list would silently drop the existing entries).

It refuses to send a template that has lost `{{ .Token }}`, and it strips the
authoring `<!-- … -->` note from both files, so neither mistake can reach a
customer's inbox. With no flags it prints a ✅/❌ line per field at the end and
exits non-zero if any field did not read back.

`--print-curl` writes the payload to `supabase/.temp/auth-mail-patch.json`
(git-ignored — it holds the App Password) and prints the equivalent `curl`
commands, for anyone who would rather see the HTTP.

### Pre-flight (once)

| # | Action |
|---|---|
| 1 | Turn on **2-Step Verification** for the sending Gmail, then create an **App Password** (Google Account → Security → App passwords → name it `CUFMAI Auth`). No 2FA means no App Password; the account password must never be used here. |
| 2 | Confirm the *same* mailbox is the one the Edge Functions already send from — Dashboard → **Edge Functions → Secrets** (or `supabase secrets list`) showing `GMAIL_SENDER` + `GMAIL_APP_PASSWORD` (e.g. `cufmai.marketplace@gmail.com`). |
| 3 | Know that **Auth SMTP does not read Edge Function secrets.** The same two values are entered again below: two stores, and a rotated App Password must change in both or auth e-mail silently stops. |

### Step 1 — Authentication → SMTP Settings (Dashboard → Auth → Emails → SMTP)

| Field | Value |
|---|---|
| Enable Custom SMTP | **ON** |
| Sender email | `GMAIL_SENDER` — the authenticated Gmail address itself (or an alias registered in Gmail). Gmail rewrites a `From` it does not own, so `no-reply@cufmai.app` cannot be used here. |
| Sender name | `CUFMAI` |
| Host | `smtp.gmail.com` |
| Port | `465` (implicit TLS — what the Edge Functions use; `587` + STARTTLS also works) |
| Username | `GMAIL_SENDER` |
| Password | the 16-character App Password (`GMAIL_APP_PASSWORD`, spaces removed) |

**As one command**, the SMTP half is part of
`dart run tool/apply_live_auth_mail.dart` (see above) — that is the repeatable
shape to re-run after an incident. If you want the raw HTTP just for SMTP,
export the values rather than typing them so the password stays out of shell
history, and note the port is sent as a **string**:

```bash
export PROJECT_REF=psczvbfoybqhjeqssimw
export SUPABASE_ACCESS_TOKEN=...        # Dashboard → Account → Access Tokens
curl -X PATCH "https://api.supabase.com/v1/projects/$PROJECT_REF/config/auth" \
  -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"smtp_admin_email\":\"$GMAIL_SENDER\",\"smtp_host\":\"smtp.gmail.com\",\"smtp_port\":\"465\",\"smtp_user\":\"$GMAIL_SENDER\",\"smtp_pass\":\"$GMAIL_APP_PASSWORD\",\"smtp_sender_name\":\"CUFMAI\",\"rate_limit_email_sent\":100}"
```

This one does **not** touch the templates (they need their file contents, which
is what the tool exists for) — run Step 3 afterwards.

### Step 2 — Authentication → Rate Limits

Saving custom SMTP **replaces** the 2/hour ceiling with a project setting that
defaults to **30 e-mails/hour** (`rate_limit_email_sent`). Raise it to ~100–200
for launch: the sign-up confirmation and the new-device step-up draw on the same
bucket, and every resend spends another. Do not go unlimited — the built-in
ceiling was also the only thing pacing bots, and
`EmailOtpPolicy.resendCooldownSeconds` (60 s) is only the client half of that.

### Step 3 — the dashboard templates that actually carry the code

`supabase/config.toml` governs local dev only; the LIVE project reads its own
dashboard templates. Add `{{ .Token }}` to **both**:

> **Or skip the paste:** `dart run tool/apply_live_auth_mail.dart` writes both
> bodies AND both subjects straight from these two files (`--dry-run` shows it
> first). It strips the authoring note below automatically and refuses to send
> a body that has lost `{{ .Token }}`, which is the failure this step is about.

- **Confirm signup** — paste the body of `supabase/templates/confirmation.html`,
  subject `Confirm your CUFMAI email`
- **Magic link** — paste the body of `supabase/templates/magic_link.html`,
  subject `Your CUFMAI sign-in code`; this is the one the new-device step-up
  sends, so without it the verify screen has nothing to accept

⚠️ **Copy from the first `<div` to the last `</div>`.** Both files open with an
HTML `<!-- … -->` authoring note that is NOT part of the e-mail — pasting it is
harmless but leaves the notes in a customer's message source. `{{ .Token }}`
must survive the paste verbatim: if the editor escapes or strips it, the mail
ships link-only again and nothing in the app can tell you why. (The tool does
both of these mechanically — see the note above.)

**How you know it took:** the received mail's heading changes from the stock
"Your sign-in link" to "Confirm it's you", and a 6-digit number appears in the
middle of it. An e-mail that arrived BEFORE the save never updates — request a
fresh code (the app's Resend button) and check that one.

Confirm **OTP length = 6** and **OTP expiry = 3600 s** while there — the numbers
`EmailOtpPolicy.codeLength` / `expirySeconds` mirror.

### Step 3b — the confirmation button must return to the APP

The Confirm-signup template embeds `{{ .ConfirmationURL }}`, and the
`redirect_to` inside it comes from the `emailRedirectTo` the app sends:
**`solvision://auth/confirm`** (`DeepLinkService.authConfirmRedirect`). GoTrue
only honours a redirect it has been told about, so add that exact value to
**Authentication → URL Configuration → Redirect URLs**. Without it the button
lands on the Site URL — a browser the app cannot use — and the account keeps
its deferred `profiles` row.

⚠️ **Do not retype the list.** This field replaces wholesale, so the tool
READS the current `uri_allow_list` first and appends to it (keeping `site_url`
in the list, which is where password-reset links resolve). Clearing what is
already configured is how a sign-in fix breaks password recovery instead.

No template edit is needed for this part: the link is already in the e-mail.
The **Magic-link** template deliberately has NO link — the new-device step-up is
a code, and a link would be a second way in.

The path/host must match `AndroidManifest.xml` (`solvision://auth/confirm`) and,
on iOS, the already-registered `solvision` scheme; `deep_link_service_test.dart`
pins that agreement so a rename cannot silently break it.

### Step 4 — verify (a teammate's address proves nothing)

| Check | How | Pass looks like |
|---|---|---|
| Delivery outside the org | Send a sign-up confirmation to an address that is **not** a Supabase org member | It arrives. Before this change the same send is refused |
| Sender is the Gmail | Read the received mail's `From:` | `GMAIL_SENDER`, not `noreply@mail.app.supabase.io` |
| The code is accepted | Enter it on the verify screen | Lands in CustomerShell; `auth.users.email_confirmed_at` set (SQL below) |
| The step-up completes | Turn the gate ON first (`select public.set_device_enforcement(true);`), then sign out, clear app data (new device id) and sign in with the password | "Verify this device" → Gmail code → shell. ⚠️ With enforcement **off there is no device screen at all**: the app asks `device_gate_open()` before mailing a code, so a fresh sign-in goes straight to the shell (architecture doc §3.1/§3.9). Leave the switch on for launch, or re-run this step after the flip |
| GoTrue switched mailers | Dashboard → Logs → Auth: the `mail.send` rows | `mail_from` is `GMAIL_SENDER`; the earlier `429 over_email_send_rate_limit` rows stop |
| Config read back | `dart run tool/apply_live_auth_mail.dart --check` | 12 ✅ lines and exit 0: sender, port, raised limit, confirmations ON, 6/3600, and `{{ .Token }}` present in both templates. A field that did not stick prints ❌ and exits 1 |
| Config read back, raw | `curl -s -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" "https://api.supabase.com/v1/projects/$PROJECT_REF/config/auth"` (pipe to `python -c` if `jq` is unavailable — `jq` is **not** installed on every machine this repo is built on) | `smtp_host: smtp.gmail.com`, `smtp_port: "465"`, your sender, the raised limit |

```sql
-- who has actually confirmed an address (the code was verified, not just sent)
select email, email_confirmed_at is not null as confirmed, last_sign_in_at
from auth.users order by created_at desc limit 10;
```

### Ongoing, and the sharp edges

- **A rotated App Password stops auth e-mail dead.** `fail CLOSED` is the
  documented behaviour for a failed send (architecture doc §4), so new sign-ups
  break outright — and, once the gate is ON, every new-device step-up with them
  (while it is OFF the app asks `device_gate_open()` before mailing, so only
  sign-ups are affected). The user is not left guessing: the code screen now
  shows the mapped reason and offers Resend (architecture doc §4, §3.5).
  Rotate both stores together — Edge Function secret *and* `GMAIL_APP_PASSWORD`
  for `dart run tool/apply_live_auth_mail.dart`, which is the re-run that
  updates GoTrue's copy in one command — then re-run Step 4.
- Gmail's own ceiling is ~500 recipients/day on a free account (~2000 on
  Workspace), with burst throttling — well above this feature's rate, but it is
  the next wall if sign-ups spike.
- Gmail cannot send as a `cufmai.app` address, so auth mail keeps a `@gmail.com`
  From. A branded sender needs Google Workspace with the domain verified — a
  later improvement, not a launch blocker.
- `400 email_address_invalid` for `keithabalo04@gmail.com` (recorded Sep 16) is a
  *validation* refusal, not a delivery one, so this runbook will not fix it.
  Re-test after Step 1; if it persists it needs its own investigation.

### Rollback

Switching Custom SMTP **off** returns GoTrue to the built-in mailer instantly —
and with it the org-members-only recipient list and the 2/hour ceiling, which
breaks sign-up and the step-up for real users. Treat it as an emergency lever
only, and prefer fixing the SMTP credentials.

---

## ✅ Already done (verified this session)

- `gcash-webhook` secret restored as project-wide; function healthy (bad signature → 401).
- LIVE webhook endpoint created (verify events/env per item 1).
- Reconciliation closed: 51 orders, exactly 1 was in `awaiting_payment` — a TEST-mode payment (₱410.25, Aug 19) confirmed paid on PayMongo, **cancelled with a full audit note** (`53194fe1-5633-4066-bda5-c13d6ce8fe1f`). No other orders touched.
- T6 code shipped: `geocode-proxy` (MapTiler proxy + per-IP rate limiting), shared `_shared/rate_limit.ts`, rate limiting wired into 9 public functions, MapTiler key removed from the Flutter client (`app_constants.dart`), both map screens call the proxy. Rate-limit counters need migration item 4 to be active.
- **T5 manual-GCash fraud surface closed in code (Sep 5, commit `6dee84b`):** reference-number dedupe on paid orders (23505 → clear seller error), admin-only `gcash_payment_decision_audit` trail written by POS confirm trigger + confirm/reject RPCs, expected-amount banner above the seller's Confirm/Reject buttons, and `create_gcash_checkout` EXECUTE revoked (no new manual orders from anywhere; legacy Aug 8–9 orders can still resolve). Activation requires migration item 4; pgTAP suite `supabase/tests/t5_manual_gcash_dedupe_audit.test.sql` runs in CI.
- `supabase/config.toml` now documents `verify_jwt = false` for every deployed-public function (prevents accidental JWT flips on redeploy).
