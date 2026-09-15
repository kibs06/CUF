# SoleVision / CUFMAI — Email OTP & Device Trust

> ANQUI checklist item 16 ("Send OTP (prefer email)"), in the confirmed
> scope: **(1) sign-up verification** and **(2) a step-up OTP challenge when
> an account is used on a device it has never been seen on**.
>
> **This is NOT passwordless login.** Passwords stay the primary factor;
> TOTP MFA stays whatever it was. This adds an e-mail confirmation for new
> accounts and one extra challenge on an unfamiliar device.
>
> **Where do I start?** Part A → `verifySignupEmail` in
> `lib/providers/auth_provider.dart` and `signUp` in
> `lib/services/auth_service.dart`. Part B → `lib/services/device_trust_service.dart`,
> `lib/services/login_challenge_service.dart`, and `login()` in
> `auth_provider.dart`. Both screens are `lib/screens/shared/email_otp_screen.dart`.

---

## Quick Facts

- **Two purposes, one screen.** `EmailOtpScreen` serves both halves; only the
  copy and which GoTrue send call is used differ.
- **Three migrations.** `20260915140000_add_trusted_devices.sql` (`trusted_devices`
  + the `trust_device` RPC), `20260915150000_enforce_trusted_devices.sql`
  (the `device_secrets` credential + the restrictive RLS policies = **Part C**)
  and `20260915160000_add_admin_account_security.sql` (**Part D** — the
  admin-side diagnostics that make a lockout ticket investigable).
- **The step-up is visible to admins.** Support had no way to see whether an
  account had recorded a device, let alone whether that device still held the
  credential the gate checks. Part D answers that, and states what it cannot
  know rather than letting an empty list read as "nobody tried".
- **The step-up is enforced by the SERVER, not by the screen.** The client-side
  challenge (Part B) is UX; `public.device_is_trusted()` in Part C is the
  control. A hand-crafted client holding a stolen password gets empty results
  from every private table (see §3.6–§3.8).
- **The credential is a device SECRET, never the device id.** The id is a UUID
  the client invents, so it cannot be the server's test. Ids are public;
  secrets are not.
- **Enforcement ships OFF** (`device_enforcement_policy.enforcement_enabled`),
  so applying the migration cannot break a client that predates the header.
- **The 6-digit code is an OPERATIONAL requirement, not a code detail.** The
  stock Supabase emails contain only a confirmation **link**. Without a
  template that renders `{{ .Token }}` the verify screen has nothing to
  accept. See §5 — this is the single most likely way to ship this broken.
- **A `profiles` row cannot be written without a session.** There is no
  `on auth.users` trigger; the INSERT policy is `auth.uid() = id`. With
  "Confirm email" ON, `signUp` returns **no session**, so Part A does not
  just add a screen — it moves *when* the profile row is written.
- **`trusted_devices` is keyed by `(user_id, device_id)`**, so one phone
  shared by two accounts is tracked as two independent trusts.
- **The device id is not a secret.** It is a per-install UUID in secure
  storage; it only decides *whether* the step-up runs.

---

## 1. Why this exists

Before item 16 the app **never called `signInWithOtp`/`verifyOtp`** (zero
references), and `docs/AI/SIGNUP_ARCHITECTURE.md` described auto-login after
sign-up: e-mail confirmation was not enforced, so accounts could exist with
unverified addresses. Item 16 closes that gap and adds a first-seen-device
challenge for accounts with a password but no TOTP factor.

---

## Part A — Sign-up verification

### 2.1 The ordering contract (the important part)

```
AccountEntryScreen (create)          seller flow (Step 5 Submit)
        │                                      │
        ▼                                      ▼
  signUpCustomer()                    controller.submit()
        │                                      │
        ▼                                      ├─ ensureUser()  ──► no session  ┐
  AuthService.signUp()                        │                                  │
   ├─ session != null → write profile NOW     ├─ VERIFY (shared OTP screen) ◄────┘
   └─ session == null → NO profile write      │      ↳ verifyOTP(type: signup)
        │                                     │        ↳ session now exists
        ▼                                     ├─ upload documents (needs session!)
  AuthGate → EmailOtpScreen                   └─ completeSellerApplication()
        │                                          seller_status = 'pending'
        ▼                                          role stays 'customer'
  verifySignupEmail(code)
   ├─ verifyOTP(type: signup) → session
   ├─ writeProfileFromMetadata(user)   ← the profile row is written HERE
   ├─ mark this device trusted
   └─ push FootProfileOnboardingScreen (optional step) → CustomerShell
```

Two consequences worth stating plainly:

1. **`signUp` no longer implies a usable account.** With confirmation ON it
   returns `user` + `session: null`. Anything that treated a non-null `user`
   as "logged in" had to change.
2. **The seller flow must verify BEFORE it uploads.** Document uploads go to
   the private `seller-verification-docs` bucket, whose RLS keys off
   `auth.uid()`; with no session they are a permission error. So
   `SellerApplicationController.submit` was reordered to
   `ensureUser → verify e-mail → upload → completeSellerApplication`,
   and `AuthProvider.signUpSeller` now **throws** if it is called with an
   unconfirmed address rather than half-completing (which would have written
   a plain *customer* profile from signup metadata instead of a pending
   seller application).

Verifying the e-mail **never grants seller access**: `completeSellerApplication`
still writes `seller_status = 'pending'` with `role = 'customer'`, and only an
admin approval flips the role.

### 2.2 `writeProfileFromMetadata` — safe for old accounts too

The signup fields are stashed in the user's **metadata** at `signUp` time
(server-side, so closing the app mid-verification — or typing the code on a
different device — loses nothing). After verification,
`writeProfileFromMetadata` upserts the row from that metadata.

It also runs for accounts that **predate** e-mail confirmation, whose profile
row already exists — so it must not clobber them:

- `role` / `seller_status` are written **only when there is no row yet**.
  (Otherwise a legacy approved *seller*, whose metadata carries no `role`,
  would be silently demoted to customer.)
- `phone` / `birthday` / `gender` are only applied when the metadata actually
  carries a value.

### 2.3 Edge cases handled

| Case | Behaviour |
|---|---|
| Abandoned mid-verification, app reopened | The auth user + metadata persist; re-signing up with the same address re-sends the code. The verify screen is reachable again. |
| Pending seller awaiting admin approval | Verification is **before** the uploads and before `completeSellerApplication`; the order lands in `PendingApprovalScreen` with `seller_status='pending'`, never approved. |
| Duplicate e-mail | Still caught inline by `AuthService.emailExists` before signup, and authoritatively by `auth.signUp`. |
| Dev-mode seller submit | Now takes the SAME verification step as production (the code appears in Mailpit at `:54324` locally), so the two paths cannot diverge. |
| Sign-up while confirmation is OFF | Unchanged: `signUp` returns a session and the profile is written immediately. The app supports both configurations. |

---

## Part B — New-device step-up challenge

### 3.1 The decision (exactly one line of policy)

```dart
DeviceTrustPolicy.requiresEmailOtpChallenge({
  required bool deviceKnown,
  required bool mfaEnabled,
}) => !deviceKnown && !mfaEnabled;
```

| Device | TOTP MFA | Result |
|---|---|---|
| known | any | proceed, bump `last_seen_at` |
| unknown | no | **email OTP challenge** |
| unknown | yes | proceed, record the device (see §3.4) |

### 3.2 What "a new device" means

Two things live in `FlutterSecureStorage`, and the difference matters:

| | Key | What it is |
|---|---|---|
| **Device id** | `cufmai_device_id_v1` | A plain UUID v4, once per install. **Not a secret** — it only *names* the device. Shared by every account on the phone, survives logout (which is what keeps "log out, log back in on the same phone" from looking like a new device). |
| **Device secret** | `cufmai_device_secret_v1_<user_id>` | 32 random bytes issued by the server (§3.6). **This is the credential.** Per ACCOUNT, because the server keys its row by `(user_id, device_id)` — two accounts on one phone each hold their own. |

A device counts as **known** only when this install still holds the secret for
that account *and* the server still lists the pair. Either half missing means
the next sign-in is challenged — the `trusted_devices` row alone is not
enough, because the gate checks the secret (§3.8).

> **Generating a new device id retires every stored secret.** The server keys
> its rows by `(user_id, device_id)`, so once the id changes, no existing secret
> can ever match again. Keeping them would make `hasDeviceSecret()` report a
> credential the gate will never accept — which is precisely the signal the app
> uses to decide whether to ask for a code. So a new id clears them, which is
> what makes the documented "bump `_deviceIdKey` to re-challenge every device"
> procedure actually work. Covered by
> `test/services/device_trust_persistence_test.dart`.

### 3.3 The flow, including where the session is withdrawn

```
login(email, password)
  └─ password OK  →  LoginChallengeService.evaluate(userId)
                        ├─ proceed      → normal login (unchanged)
                        └─ challenge    → 1. reset the failure counters
                                            2. sendLoginCode(email)
                                            3. signOut()   ◄── the AAL1 session
                                                              is WITHDRAWN
                                            4. pendingDeviceChallenge = {...}
  └─ AuthGate renders EmailOtpScreen(newDeviceChallenge)
        ├─ verify → verifyOTP(type: email) → session
        │            → trust_device(device_id, label)
        │            → fetch profile → shell
        └─ cancel → back to the sign-in screen (not counted as a failure)
```

The password was correct, so the login is **not** recorded as a failed
attempt; only the session is withheld until the code clears. `AuthGate`
resolves this state *before* any stream/session routing, so the login screen
(and the shell) can never flash while a code is outstanding.

### 3.4 Interaction with TOTP MFA — the decision

**TOTP MFA satisfies the step-up, so the email challenge is skipped for MFA
users.** An authenticator app is a stronger possession factor than an emailed
code, and stacking both on one login is friction without extra assurance.
Such a login *does* record the device as trusted, so removing MFA later does
not suddenly start challenging that phone.

If the factor list cannot be read, the code deliberately **fails toward the
challenge** (see §4) rather than assuming MFA is present — an extra code the
user can clear is recoverable; a silently skipped challenge is not.

### 3.5 Rollout behaviour — the decision

`trusted_devices` ships **empty**, so on each account's first sign-in *after*
rollout its device looks new and gets one code. **No grandfathering logic.**

Why: the alternative would need a "not yet deployed" sentinel, and it would
permanently weaken the feature for anyone who simply had not signed in yet
(their first device would have to be trusted forever). The cost is bounded —
one e-mail, once per account — and it doubles as proof that the mailer works.

The check runs in `login()`. An install that is *already* signed in when this
ships is handled separately and **only if the server is actually gating it** —
see §3.10. A *failed send* fails the login (§4), which is the one sharp edge:
a mail outage blocks first-time logins from new devices while known devices
and existing sessions are unaffected.

---

## Part C — Server-side enforcement (the gate)

> Migration: `supabase/migrations/20260915150000_enforce_trusted_devices.sql`
> Tests: `supabase/tests/trusted_device_enforcement.test.sql` (43 assertions),
> `test/services/device_gate_contract_test.dart` (Dart↔SQL contract guards).

Part B decides whether the **app** shows the OTP screen. That is a UX
affordance: a hand-crafted client — or plain `curl` — holding a stolen
password simply never asks for the code. Part C is what makes the step-up a
security control, by making the private tables refuse to serve a session that
has not cleared it.

### 3.6 The credential: a device secret, not a device id

The device id is public knowledge (it is a UUID the client invents), so "a
`trusted_devices` row exists for this device_id" **cannot** be the server's
test — a hand-crafted client would just claim a plausible id. The server
checks a secret instead:

1. `public.trust_device()` mints 32 bytes from `gen_random_bytes()`, returns
them to the client, and stores only `digest(secret, 'sha256')` in
`public.device_secrets`.
2. The client persists that secret in secure storage, **per account** (see
§3.2), and attaches it to every request as
`x-cufmai-device: <device_id>:<secret>`.
3. `public.device_is_trusted()` splits the header on the first `:`, looks up
the stored hash for `auth.uid()` + that device id, and compares.

`device_secrets` has RLS enabled with **no policies and no grants**: it is not
part of the API surface at all, so the hash cannot be fished out. A stored
hash is used rather than the secret itself because this is a bearer
credential — a leaked dump must not hand an attacker a working device token.

Why the header is a legitimate channel: PostgREST exposes request headers to
SQL as the `request.headers` setting, so RLS can read it. Verified through
Kong → PostgREST on a real stack, not assumed. When a statement runs outside
PostgREST (psql, pgTAP) the setting is simply absent, and
`current_setting(..., true)` returns NULL rather than raising.

### 3.7 The mint gate — why a stolen password is not enough

Minting is the one privileged act, so it is gated on the JWT itself.
`public.session_proves_possession()` is true only when `amr` contains `otp` or
`magiclink`, or `aal` is `aal2`. A password-only session is **refused**
(42501), which is the whole point: a stolen password cannot mint a secret for
the attacker's device.

Measured against a real stack rather than inferred: **both**
`verifyOtp(type: signup)` and `verifyOtp(type: email)` come back as `amr:
["otp"]`, so a single rule covers sign-up verification and the new-device
challenge. `pw` sessions are `amr: ["password"]` / `aal1`.

So a secret can only be obtained by completing an emailed code or an MFA
factor — and the code arrives in the account's mailbox. jsonb containment
(`@> '[{"method":"otp"}]'`) is used rather than an equality test because
GoTrue stamps each `amr` entry with a timestamp.

### 3.8 What is gated, and what deliberately is not

A **RESTRICTIVE** policy named `Require a trusted device`, carrying both
`USING` and `WITH CHECK`, is applied to the private tables. Restrictive
policies are ANDed with the existing permissive ones, so this can only ever
**remove** access — it never grants anything a user could not already do.
Spelling out `WITH CHECK` as well as `USING` is what gates INSERT/UPDATE, not
just reads (the pgTAP suite asserts both directions).

The sweep is dynamic — every RLS-enabled table in `public` — with an explicit
exemption list, so a NEW table is protected by default rather than silently
open. (Same philosophy as `rls_recursion_canary.test.sql`.) The exempted ones,
each for a concrete failure if it were gated:

| Table | Why it must stay outside the gate |
|---|---|
| `profiles` | The app cannot route to a shell (customer/seller/admin) without it. |
| `trusted_devices` | **The challenge reads this table to decide whether to challenge.** Gating it locks every new device out permanently. |
| `failed_logins` | The lockout counter is written during the password attempt — strictly *before* any step-up can exist. Gating it silently disables brute-force protection. |
| `device_secrets`, `device_enforcement_policy` | Internal (`no grants`); listed for clarity. |
| `products`, `stores`, `inventory`, `banners`, `story_entries`, `store_follows`, `reviews`, `store_reviews`, `review_images`, `product_reviews`, `product_images`, `product_variants`, `product_color_images`, `product_customizations`, `product_review_images`, `payment_fee_config` | Public catalogue/read-only content that anon can already read. A gate here adds friction but no protection. |
| `device_tokens` | Device-scoped push registration, written right after login; leaking it gives an attacker nothing they do not have. |

Everything else — **26 tables** in the migration (27 today: `pickup_reservations`
from item 14 was folded in by its own migration's call to the re-runnable
`install_device_gate_policies()`), including `orders`, `order_items`,
`cart_items`, `customer_addresses`, `messages`, `conversations`,
`notifications`, `payment_intents`, `gcash_payment_proofs`, `vouchers`,
`voucher_redemptions`, `sales_transactions`, `reports`,
`seller_business_docs` — requires a valid device secret.

Admins bypass the gate (`OR public.is_admin()`), so the admin portal keeps
working, and the policy is scoped `TO authenticated`, so anon is untouched.

**This is an RLS control, and RLS is what it covers.** A `SECURITY DEFINER`
function owned by `postgres` bypasses the policies on its own tables, so an
RPC that touches a gated table is reachable from a device with no secret
(measured for `request_pickup_reservation`, §10.14). Read "gated" below and
elsewhere in this document as *direct table access*, not *every code path*.

> **The failure is SILENT.** RLS denies a SELECT by *filtering rows*, so a
gated session receives `200` with `[]` — an empty order list, not an error.
> That is a good property for stability (no crash) and a terrible one for
diagnosis, and it is exactly why §3.10 exists.

### 3.9 The rollout switch — and why it defaults to OFF

`public.device_enforcement_policy` is a single-row table with
`enforcement_enabled boolean NOT NULL DEFAULT false`. While it is false,
`device_is_trusted()` returns true and **nothing is denied**.

That default is load-bearing. The moment the policies start denying, every
already-installed client — none of which sends the device header — would see
empty private tables. So the order is fixed:

1. Apply the migration (wired up, nothing enforced — safe).
2. Ship the build that mints and sends the secret.
3. Flip it on. Either `select public.set_device_enforcement(true);` (admin-only
   RPC, records `updated_by`), or the equivalent `UPDATE` in the SQL editor.

Step 3 is a single row — no schema change, no deploy — and it is reversible
the same way, which is the rollback path if a client turns out not to be
sending the header.

**Does step 2 cost users anything?** No new UX: the client-side challenge in
Part B already ran on unfamiliar devices before this migration existed, so
minting happens at the same moment the code is verified. The one-time extra
cost is for installs that hold a `trusted_devices` row but no secret (they
were trusted by the *old* client, which did not mint one): they are challenged
once more. That is why the client mints eagerly rather than waiting for the
flip — by the time step 3 happens, most devices already carry a secret.

### 3.10 Client changes, and the repair path for in-flight sessions

| Change | File |
|---|---|
| Sends + stores the secret, per account | `lib/services/device_trust_service.dart` (`formatToken`, `deviceSecret`, `storeDeviceSecret`, `applyToken`, `refreshRequestHeader`, `startSyncWithAuthState`) |
| Decides on *holding the secret*, not on the row | `lib/services/login_challenge_service.dart` (`evaluate`) |
| Probes the gate, mints, and reports the secret | `login_challenge_service.dart` (`needsStepUpOnRestoredSession`, `markDeviceTrusted`) |
| Applies the header before the first request | `lib/main.dart` |
| Mints after the TOTP challenge clears | `lib/screens/auth_gate.dart` (`_MfaGateState`) → `AuthProvider.ensureDeviceTrusted()` |

Three of these are non-obvious and each prevents a real lockout:

**1. The header is attached per ACCOUNT, and kept in sync.** The secret is
scoped to `(user_id, device_id)`, so a session change that bypassed `login()`
— account switching — would leave the previous account's credential attached
and silently close the gate for the new one. `startSyncWithAuthState()`
re-applies it on every auth-state change (sign-in, switch, sign-out, token
refresh), and a no-op refresh costs nothing because the applied value is
cached.

**2. An MFA user on a new device MUST still mint.** The gate checks the
secret, **not the AAL** — so an AAL2 session with no secret is still denied.
But `login()` deliberately skips the email challenge for MFA users (§3.4),
which means nothing would ever mint one. `_MfaGateState` therefore calls
`AuthProvider.ensureDeviceTrusted()` the moment the session reaches AAL2.
Without it, every MFA user would be let in and then find their orders empty.
`login()`'s own attempt to record the device at AAL1 is *expected to fail* and
returns null rather than throwing.

**3. A restored session is repaired only when it is actually gated.** An
install that updates while signed in holds a valid session but no secret. On
restore the app asks `public.device_gate_open()` — an RPC that returns the
caller's own `device_is_trusted()` — and:

- **enforcement off** → nothing happens. No code is mailed. Shipping this
  feature adds zero friction.
- **enforcement on** → if the session already proves possession (AAL2) one RPC
  mints silently; otherwise the user is asked for one code. Once per install.

This probe is what makes the flip self-healing rather than a silent breakage:
without it, turning enforcement on would blank the private tables for every
already-signed-in session until the user happened to sign in again. A probe
that cannot be read **fails open** — an unreadable probe must never be what
forces a code on a legitimate user.

---

## Part D — Admin diagnostics (answering the support ticket)

> Migration `20260915160000_add_admin_account_security.sql` +
> `lib/screens/admin/admin_account_security_screen.dart`.

Part C makes the app harder to get into, which creates exactly one new
support ticket: *"I got a new phone and I can't get in."* Before Part D
nothing in the admin portal could answer it — an admin could not see whether
the account had a device on record, whether that device still held a
credential, whether a lockout was in force, or whether enforcement was even
switched on. Part D is the view, reachable from **Manage Users → ⋮ → Account
Security**.

### 3.11 What it reads — all server-side, none of it client-reported

One RPC, `public.admin_account_security_overview(p_user_id uuid) → jsonb`,
returns five blocks plus its own caveats:

| Block | Source | Used for |
|---|---|---|
| `account` | `auth.users` LEFT JOIN `profiles` | email confirmation, last sign-in, role, whether a profile row exists |
| `devices` | `trusted_devices` LEFT JOIN `device_secrets` | each device + **whether a credential exists** and when it was minted |
| `otp_challenges` | `auth.audit_log_entries` | the code/sign-in timeline |
| `lockouts` | `failed_logins` | the password lockout counter |
| `enforcement` | `device_enforcement_policy` | is the gate even switched on |
| `cannot_answer` | — | what the report cannot know, stated in the payload |

The device block is the point. `has_secret = false` is the state this whole
screen exists to expose: the app lists the phone as trusted while the server
denies it every private table. It is only reachable from a **legacy row**
(written before Part C, by a `trust_device` that stored no secret), because
the current function writes the row and the credential in the same call — so
the UI says "recorded before the credential existed" rather than "lost".

### 3.12 The security boundary

- `SECURITY DEFINER`, `SET search_path = public`, gate-kept by `public.is_admin()`
  (raises **42501** for anyone else).
- It authorises the **caller**, and takes the subject as an **argument** —
  the one place in this schema where that is the correct shape, because
  investigating someone else's account is the whole purpose.
- `device_secrets` has no grants at all; the function is the only reader, and
  it selects the **minted-at time**, never `secret_hash`. Verified over real
  HTTP: `secret_hash` does not appear in the response text.
- Granted to `authenticated` only. `anon` has no EXECUTE grant, so an
  unauthenticated caller cannot even enumerate accounts (verified: **401**).

### 3.13 The timeline has three identification shapes (measured, not assumed)

GoTrue identifies the user differently per action, and a filter on `actor_id`
alone silently drops events:

| Action | Where the user id is | Mapped to |
|---|---|---|
| `user_recovery_requested` | `actor_id` = the user | `otp_emailed` |
| `user_signedup` | `actor_id` = **the service role**; the user is only in `traits.user_id` | `account_created` |
| `user_confirmation_requested` | `actor_id` = the user | `confirmation_emailed` |

The function matches **all three** shapes plus an email fallback. Both the
pgTAP suite and the verified HTTP run contain a service-role-shaped signup row
specifically to catch a regression to the naive filter.

### 3.14 What the report cannot know — stated in the payload

Measured against a real GoTrue, and surfaced as `cannot_answer` so the caveat
sits next to the timeline rather than in a doc nobody opens:

- **A wrong code leaves no trace.** `verify` with a bad token is rejected by
  GoTrue without touching the database, so failed attempts are recorded
  nowhere. An empty timeline is therefore **not** evidence that nobody tried —
  which is the exact wrong conclusion in a lockout ticket.
- **A device that was refused is not recorded.** The `trusted_devices` row and
  its credential are written together, so a phone that never finished the
  step-up has no row at all. "Not in the list" cannot be shown as "rejected".
- **Codes are known from the send request, not from delivery.**
- The `ip_address` column exists but this stack's GoTrue leaves it empty, so it
  is returned only when present and the UI does not promise it.

### 3.15 The diagnosis, and why the gate's state suppresses it

`AccountSecurityOverview.findingsAt(now)` is a **pure** derivation (no widget,
no network) so the reasoning is unit-tested; the screen just renders it.
Severity ordering, most urgent first:

| Finding | Severity | When |
|---|---|---|
| `password_lockout` | blocking | a lockout is still in force — it blocks sign-in *before* the step-up is reached, so it outranks everything here |
| `email_unconfirmed` | blocking | no code can be verified, so the step-up can never complete |
| `enforcement_off` | info | **returns early**: nothing is being denied by the gate, so the device findings are suppressed rather than shown as a false lead |
| `device_without_credential` | warning | a listed device the gate will refuse |
| `no_trusted_devices` | warning | the step-up has never succeeded for this account |
| `all_devices_credentialed` | info | every recorded device is healthy, so the phone in the ticket is simply not on record |
| `no_profile_row` | warning | auth account without a profile row |

The suppression rule is the one worth keeping: leading with "this device has
no credential" when enforcement is **off** (the shipped default) sends support
down the wrong path, and the device evidence is still on screen anyway. Note
the honest consequence — while enforcement ships **OFF**, this screen leads
with `enforcement_off` by design.

`isHealthyAt()` deliberately ignores `info` findings: "every recorded device
holds a credential" is the correct answer to a ticket and still an
observation, so counting it as a fault would leave the green all-clear state
unreachable for any account that ever signed in.

### 3.16 Verified end-to-end (real HTTP, admin JWT)

Through Kong → PostgREST → the RPC, using the client's exact call shape
(`params: {'p_user_id': …}`):

| Case | Result |
|---|---|
| Admin, real session | **200** — both devices with the expected `has_secret`, exactly the 7 documented device keys, no `secret_hash` in the text, both the `actor_id`-shaped and `traits`-shaped events in the timeline |
| Non-admin, own account | **403 / 42501** |
| Anonymous (no session) | **401** `permission denied for function` — refused at the grant, never reaching the function |
| Unknown account id | **500 / P0002** naming the id, not an empty page |

---

## 4. Failure semantics (deliberate, and asymmetric)

> **Never lock a legitimate user out because of our own plumbing.**

| Failure | Direction | Why |
|---|---|---|
| Device id unavailable (secure storage broken) | **fail OPEN** — proceed | We cannot tell "new" from "known"; challenging every login forever would be a permanent lockout. |
| `trusted_devices` unreadable, **and we hold the secret** | **fail OPEN** — proceed | A transient read error is not evidence of a revoked device, and we hold the credential the server checks. |
| `trusted_devices` unreadable, **no secret held** | **fail CLOSED** — challenge | Nothing proves this install is cleared; proceeding would just hit a shut server gate. |
| `device_gate_open()` unreadable at startup | **fail OPEN** — no code sent | An unreadable *probe* must not be the thing that mails a code to a legitimate user. |
| MFA state unreadable | **fail CLOSED** — challenge | Unknown factor state is not evidence of a second factor. Recoverable friction beats a silent hole. |
| Sending the challenge code fails | **fail CLOSED** — no login | Sending the code *is* the challenge; proceeding anyway would make the feature decorative. The mapped error (rate limit, mailer) is surfaced. |
| `trust_device()` refused (42501) | **swallowed** — returns null | Expected for an MFA user at AAL1 before their TOTP challenge; the AAL2 mint in §3.10 then succeeds. |
| Enforcement on, secret rotated or lost | **challenge on the next login** | `evaluate()` treats "secret held but the row is gone" as unknown, so the device is re-challenged and re-minted instead of being left denied. |

---

## 5. ⚠️ The e-mail templates — the operational half of this feature

**The codes do not exist until a template renders `{{ .Token }}`.** This was
verified against a real local stack, not assumed:

| Observation | Result |
|---|---|
| Stock Supabase sign-up template | e-mail contains **only** a `{{ .ConfirmationURL }}` link — **no 6-digit code** |
| `supabase/config.toml` key `[auth.email.template.signup]` | CLI emits `GOTRUE_MAILER_TEMPLATES_SIGNUP`; GoTrue's mail type is **`confirmation`**, so the value is **silently ignored** and the built-in template is used |
| `supabase/config.toml` key `[auth.email.template.confirmation]` | CLI emits `GOTRUE_MAILER_TEMPLATES_CONFIRMATION`; the custom template is used, and `{{ .Token }}` renders a real 6-digit code |

So the key must be **`confirmation`**, not `signup`. `magic_link` is already
GoTrue's own mail-type name and needs no rename. Both templates live in
`supabase/templates/` and are wired in `supabase/config.toml`.

A second local-only gotcha: GoTrue fetches templates over HTTP from Kong at
boot, and **Kong may not be serving `/email/*` yet** — the fetch fails, the
built-in template is cached, and every e-mail looks stock until the stack is
restarted. The auth log is explicit about it
(`templateloader_template_body_http_error` / `connection refused`). If local
e-mails look wrong, `supabase stop && supabase start` once and check
`docker logs supabase_auth_app | grep -i template`.

### 5.1 What the LIVE project needs (dashboard, not repo)

1. **Authentication → Sign In / Providers → Email → "Confirm email": ON.**
   A `config.toml` default does not change the hosted project.
2. **Authentication → Email Templates → "Confirm signup":** add
   `{{ .Token }}` (mirror `supabase/templates/confirmation.html`).
3. **…→ "Magic Link":** add `{{ .Token }}` (mirror
   `supabase/templates/magic_link.html`) — without it Part B has nothing to
   send.
4. Confirm the numbers the app mirrors: `otp_length = 6`,
   `otp_expiry = 3600` (1 hour) — these are `EmailOtpPolicy.codeLength` and
   `EmailOtpPolicy.expirySeconds`.

### 5.2 Verified end-to-end (local stack, GoTrue v2.196.0)

```
signUp (Confirm email ON)     → session: null, email_confirmed_at: NULL
delivered e-mail              → subject "Confirm your CUFMAI email", 6-digit code
verifyOtp(type: signup)       → access_token + refresh_token, email_confirmed_at set
verifyOtp with a wrong code   → 403 otp_expired      (mapped to friendly copy)
resend(type: signup)          → 200
signInWithOtp(create_user:false), existing user  → 200, e-mail with 6-digit code
signInWithOtp(create_user:false), UNKNOWN user   → 422 otp_disabled, NO account created
verifyOtp(type: email)        → access_token
```

Note the stored `users.confirmation_token` is the 56-char **link** token; the
6-digit code is not stored in plaintext and nothing in the app reads it.

---

## 6. Pre-rollout accounts — the decision

Accounts created while confirmation was OFF may have a NULL
`email_confirmed_at`. Rather than guess (or grandfather them in with a flag),
the app **handles both cases without locking anyone out**:

- If the account is already confirmed, sign-in works exactly as before.
- If it is not, Supabase refuses with `error_code = email_not_confirmed`.
  `AuthProvider.login` catches that specific code, sends a fresh sign-up code,
  and routes the user to the **same verify screen** — which then writes the
  profile via the existing-row-safe path in §2.2.

So **no grandfathering is required and no legacy user can be dead-ended**:
they either sign in normally or get one code and are done. (The generic
friendly message for `email_not_confirmed` — "Confirm your email first…" — is
still used on paths that cannot send a code.)

Side effect worth knowing: because that branch is only reachable for an
address that exists, it is a user-existence oracle for someone who already
knows the password. That is inherent to Supabase's error taxonomy and is an
accepted trade-off; `invalid_credentials` and `user_not_found` still share one
message on the normal failure path.

To measure it before rollout, run against the live project:

```sql
select count(*) filter (where email_confirmed_at is null) as unconfirmed,
       count(*)                                          as total
from auth.users;
```

---

## 7. Data model & RLS

`public.trusted_devices` — `user_id`, `device_id`, `device_label`,
`first_seen_at`, `last_seen_at`, `trusted_at`; primary key
`(user_id, device_id)`, FK to `profiles(id) ON DELETE CASCADE`.

| Operation | How |
|---|---|
| Read own rows | policy `auth.uid() = user_id` |
| Revoke own row | policy `auth.uid() = user_id` (DELETE) |
| Admin audit read | policy `public.is_admin()` |
| **Write** | **no INSERT/UPDATE policy at all** — only `public.trust_device(p_device_id, p_device_label)`, a `SECURITY DEFINER` function that takes the user from `auth.uid()` |

That is deliberate: there is no argument through which a client could trust a
device for another account, and re-trusting a known device goes through the
same call (so `last_seen_at` is always bumped and `first_seen_at` /
`trusted_at` / `device_label` are never rewritten). `anon` has no grant on the
table at all.

Since Part C, `trust_device()` additionally **requires a stepped-up session**
(§3.7) and **returns a freshly minted secret** — so the same call both records
the device and supplies the credential the policies check.

### `public.device_secrets` (Part C)

`user_id`, `device_id`, `secret_hash` (bytea), `minted_at`; primary key
`(user_id, device_id)`, plus a composite FK to
`trusted_devices(user_id, device_id) ON DELETE CASCADE` — so a secret can only
exist for a trusted device, and **revoking a device destroys its secret**, which
is what makes "revoke" mean "this device must clear the step-up again" rather
than "this device keeps a working credential".

RLS enabled, **no policies, no grants** (not even `SELECT`). Reachable only
through `device_is_trusted()` and `trust_device()`, both `SECURITY DEFINER` and
owned by the migration role.

### `public.device_enforcement_policy` (Part C)

A single row (`id boolean PRIMARY KEY CHECK (id)`, `enforcement_enabled NOT
NULL DEFAULT false`, `updated_at`, `updated_by`) — the rollout switch from §3.9.
RLS enabled, no policies, no grants; read by `device_enforcement_enabled()` and
written only by the admin-only `set_device_enforcement(boolean)`.

### The gate helpers (Part C)

| Function | Purpose |
|---|---|
| `device_is_trusted()` | The gate. Reads `x-cufmai-device` from `request.headers`, hashes the secret, compares with the stored hash for `auth.uid()`. Returns true while enforcement is off. |
| `session_proves_possession()` | The mint gate: `amr` otp/magiclink, or `aal2`. |
| `device_enforcement_enabled()` | The rollout switch, readable from a policy. |
| `device_gate_open()` | Read-only probe for the app: "would the gate let this session through?" — lets the app tell *empty* from *gated* (§3.10). |
| `set_device_enforcement(boolean)` | Admin-only flip, records `updated_by`. |

---

## 8. Key file map

| Layer | File |
|---|---|
| Migration — table + RPC | `supabase/migrations/20260915140000_add_trusted_devices.sql` |
| Migration — server-side gate | `supabase/migrations/20260915150000_enforce_trusted_devices.sql` |
| Migration — admin diagnostics | `supabase/migrations/20260915160000_add_admin_account_security.sql` |
| Admin view (screen) | `lib/screens/admin/admin_account_security_screen.dart` (Manage Users → ⋮ → Account Security) |
| Admin view (data) | `lib/services/account_security_service.dart` |
| Admin view (model + diagnosis) | `lib/models/account_security_overview.dart` (`findingsAt` is the pure derivation) |
| Email templates | `supabase/templates/confirmation.html`, `supabase/templates/magic_link.html` (`supabase/config.toml`) |
| Shared screen | `lib/screens/shared/email_otp_screen.dart` (code entry, resend cooldown, expiry countdown) |
| Rules (pure) | `EmailOtpPolicy` in `lib/services/email_otp_service.dart` |
| GoTrue calls | `EmailOtpService` (send signup / verify signup / send login / verify login) |
| Device identity + the secret + the request header | `lib/services/device_trust_service.dart` (`DeviceTrustService`, `DeviceTrustPolicy`, `TrustedDevice`) |
| Decision + round trip + gate probe | `lib/services/login_challenge_service.dart` |
| Header priming at startup | `lib/main.dart` (`refreshRequestHeader` + `startSyncWithAuthState`) |
| MFA-path mint (AAL2) | `_MfaGateState` in `lib/screens/auth_gate.dart` → `AuthProvider.ensureDeviceTrusted()` |
| Restored-session repair | `_maybeStartRestoredSessionChallenge` in `lib/providers/auth_provider.dart` |
| State machine | `login()` / `verifySignupEmail` / `verifyDeviceChallenge` / `resend*` / `cancel*` in `lib/providers/auth_provider.dart` |
| Gates | `_signupVerificationGate` / `_deviceChallengeGate` in `lib/screens/auth_gate.dart` |
| Device list UI | `lib/screens/shared/manage_login_device_screen.dart` (Account & Security → Manage Login Device) |
| Reused by | `lib/screens/auth/customer_register_screen.dart`, `lib/screens/auth/seller_application_flow.dart`, `lib/providers/seller_application_controller.dart`, `lib/services/auth_service.dart` |

---

## 9. Tests

**Dart** (750 total suite, all green):

| File | Covers |
|---|---|
| `test/services/email_otp_service_test.dart` | code shape, resend cooldown, expiry window, countdown format, constants vs config |
| `test/services/device_trust_service_test.dart` | the decision table **including the MFA carve-out**, row parsing, label fallback |
| `test/services/login_challenge_service_test.dart` | known device skips, unknown triggers, MFA skips and still records, every fail-open/fail-closed branch, send-failure propagates, verify returns the user, **the secret is the credential** (a row without a secret still challenges; a revoked device challenges even holding a secret), the restored-session gate probe, a refused mint returning null instead of throwing |
| `test/services/device_gate_contract_test.dart` | the Dart↔SQL **contract**: header name matches the migration, token shape, the safe `DEFAULT false`, the mint gate's accepted `amr`, the check coming *before* the first write, and the bootstrap exemptions that keep the step-up from deadlocking itself |
| `test/services/device_trust_persistence_test.dart` | the **real** `DeviceTrustService` against a mocked `FlutterSecureStorage`: the id is generated once and written under its documented key, is stable across instances (a simulated relaunch), adopts a stored id, replaces rubbish rather than trusting it, and **survives the actual logout cleanup** (`BiometricService.clearCredentials` + `AccountManager.removeAccount`, the real services) — plus per-account secret isolation, the `>= 32` guard, revoke-drops-the-secret-but-keeps-the-id, and that a regenerated id retires every stale secret without touching another service's keys |
| `test/services/device_trust_storage_failure_test.dart` | the **keychain-unavailable** half, deliberately un-mocked (the mock is process-global, so it must live in its own file): the id is reported unknown rather than thrown or invented, no secret is assumed, a failed write does not undo a completed verification, and the header refresh cannot crash startup |
| `test/widgets/email_otp_screen_test.dart` | auto-submit, short code, wrong/expired code copy, rate-limit copy on resend, cooldown, expiry, first-send per purpose, masking, cancel |
| `test/providers/seller_application_controller_test.dart` | the submit **pre-flight ordering**: a verification step is required when `signUp` returned no session, and backing out (or "verified" with no session) never half-completes the application |
| `test/models/account_security_overview_test.dart` | Part D parsing (nulls, wrong types, an empty document, device-key fallbacks) and **every diagnosis rule**: the locked-out-new-phone case, the pluralised variant, enforcement-OFF *suppressing* the device findings, a live lockout outranking an unconfirmed address, an expired lockout staying silent, the three-shape timeline, severity ordering, and that no finding ever claims a device was refused |
| `test/services/account_security_service_test.dart` | Part D calls the RPC with `p_user_id` and trims it, parses the payload, refuses an empty id without a round trip, and maps **42501 / P0002 / network / empty document** to distinct messages — plus the non-obvious one: the fake RPC builder must complete a *real* `Future` rather than throw from `then`, because `PostgrestFilterBuilder` implements `Future` and an error thrown out of `then` bypasses the caller's `onError` and hangs the test |
| `test/widgets/admin_account_security_screen_test.dart` | Part D on screen: it asks for the account it was opened with, leads with the diagnosis, renders the credential chips, shows the gate state, **does not blame the credential-less device when enforcement is off**, shows the lockout/unconfirmed-address findings, renders the server's own caveats, handles the empty device list, surfaces a 42501 reason with a working Retry, and never leaks a raw error |

The contract test is deliberately cross-artifact: neither a Dart type nor a
SQL type can catch a renamed header or a dropped exemption, and both of those
fail silently (one gates the app out of its own orders, the other deadlocks the
challenge).

**SQL** — three suites (plus the pre-existing unrelated ones), all run by
`supabase test db` / the `supabase-migrations.yml` CI job, each in a
transaction that is rolled back so the `enforcement_enabled = true` they set
cannot leak:

| File | Assertions | Covers |
|---|---|---|
| `supabase/tests/trusted_devices.test.sql` | 30 | schema + PK, unauthenticated refusal, blank device id refused, the row is written for `auth.uid()` (not a spoofable argument), re-trust preserves history, **direct INSERT denied (no policy)**, same phone / two accounts stays two rows, revoke is scoped to the owner, admin read, anon lockout. Its fixtures carry a **stepped-up** `amr`, because the mint gate (Part C) correctly refuses a password-only session — the test had to be updated *with* the feature, not around it |
| `supabase/tests/admin_account_security.test.sql` | 31 | Part D: the function exists and is granted to `authenticated` but **not** `anon`; a session-less caller and a normal user (even for their own account) both get 42501; an unknown account raises P0002; the account/devices/enforcement blocks parse; the device objects carry **exactly their 7 documented keys**; the timeline matches all three identification shapes while excluding another account's events; lockouts are reported; `secret_hash` appears as neither a field **nor a value**; and the future-table invariant (every RLS table is gated or exempt) — read from the same `device_gate_exempt_tables()` the installer uses |
| `supabase/tests/trusted_device_enforcement.test.sql` | 44 | the gate itself: the policy is **RESTRICTIVE**, on the named high-value private tables plus a floor on the total (27 today — it used to assert an exact 26, which broke on every legitimately-gated new table and trained the next author to bump a constant instead of asking whether *their* table is private), with **no bootstrap table in it**; enforcement off denies nothing and the off-switch restores access; a password-only session gets 0 rows on gated tables, cannot INSERT (42501), and its DELETE/UPDATE do not touch the row; **a wrong secret, an id with no secret, an unknown device and a malformed token are all refused**; another user presenting the same device+secret sees nothing; the correct secret reads, writes and deletes; `device_secrets` is not even granted; an admin bypasses; anon is unaffected; and the mint gate: password-only refused, otp/magiclink/aal2 accepted, the minted secret works immediately, **re-trusting rotates the secret and the old one dies**, and revoking cascades the secret away |

Verified command sequence (matches CI):

```bash
supabase start && supabase db reset && supabase test db   # 7 files / 229 tests PASS
flutter analyze && flutter test                            # 750 PASS
```

Two guards are worth calling out because they are the ones that *bit* while
being written, and both were confirmed to have teeth by mutation (break it,
watch it fail, restore the file byte-identically):

- The pgTAP diagnosis test originally read `auth.users` **after** switching the
  session to `authenticated`, which has no `SELECT` there — the suite died with
  a permission error instead of a helpful message. The expected timestamp is now
  a literal.
- `device_gate_contract_test.dart` anchored on a `v_exempt text[] := ARRAY[`
  literal that Part D's supporting refactor **removed** (the list became
  `device_gate_exempt_tables()`), so the guard threw a `RangeError` instead of
  telling anyone the list had moved. It now reads the function, reports a
  missing anchor as a named failure, and additionally asserts that the genuinely
  private tables (`orders`, `cart_items`, `payment_intents`, …) are **never**
  exempt — the half of the invariant the pgTAP suite structurally cannot check,
  because it reads the same list it is validating.

---

## 10. Known limitations & follow-ups

1. **~~Part B is only a client-side gate.~~ Resolved by Part C** (§3.6–§3.8):
   the private tables now require a device secret that only an emailed code or
   an MFA factor can mint, so a hand-crafted client holding a stolen password
   gets empty results instead of data. **The MFA gate itself is still
   client-side** — an AAL1 session with a correct password can still reach any
   table that is *not* device-gated, and the MFA challenge is still a UI gate.
   The same claim/AAL-aware pattern in Part C is the template for fixing it.
2. **The gate must be switched on deliberately.** `enforcement_enabled` is
   `false` in the migration (§3.9). Until someone flips it, Part C is wired up
   but not enforcing — that is the intended staging, not a bug, but it does
   mean "the migration is applied" ≠ "the step-up is enforced".
3. **Storage buckets and edge functions are outside this gate.** Storage has
   its own policies (see `20260901000000_lock_down_storage_buckets.sql`) and
   does receive the header, but no bucket policy reads it; edge functions run
   with the service role and bypass RLS entirely. A future pass could extend the
   same check to both.
4. **A running app does not notice the flip.** The repair path (§3.10) runs on
   session restore, so a session that is live *at the moment* enforcement is
   switched on will show empty private tables until the next launch. In-flight
   sessions are not re-probed on a timer.
5. **One e-mail send per new device.** Fine at this scale; a rate-limit-aware
   queue would be the next step if sign-ins spike.
6. **`otp_disabled` copy.** GoTrue returns it when `signInWithOtp` is asked to
   create an unknown user; the app maps it to a generic "email codes are not
   available" message. It is unreachable in practice (we only send after a
   correct password), but the message is not literally accurate.
7. **Dev mode.** The dev-mode seller submit now requires the e-mail code too,
   so it cannot silently diverge from production — read the code from Mailpit
   (`http://127.0.0.1:54324`) locally.
8. **~~Secure storage is not exercised by the test suite.~~ Closed** —
   `FlutterSecureStorage.setMockInitialValues` (the plugin's own seam) now
   drives the real `DeviceTrustService`, so the persistence claim behind "logout
   does not re-trigger the OTP" is executed rather than asserted structurally:
   the id is stable across simulated relaunches and survives the real logout
   cleanup. Writing it immediately paid for itself — see the two bugs below.
   What is still *not* covered is a real Android keystore / iOS keychain (the
   mock is an in-memory map), which is a device-QA question, not a test one.
9. **Two defects the new tests found, both fixed.**
   - `BiometricService.clearAll()` used `_storage.deleteAll()`, which on a
     *shared* secure store would have wiped the device id, the per-account
     secrets and `AccountManager`'s keys — i.e. made the phone look brand new
     and destroyed its step-up credential. It was unreachable (no callers)
     but was the obvious method to call for "reset app data". Now scoped to
     its own four keys, with a regression guard.
   - `DeviceTrustService._retireDeviceSecrets()` iterated `readAll().keys`
     while deleting, which **skips entries** when the platform hands back a
     live view of the store — silently retiring one account's secret and
     leaving the rest behind (exactly the state that makes
     `hasDeviceSecret()` lie and stops the app asking for a code). Caught by
     retiring *two* accounts in one test; one account passes either way.
   - Related, and deliberately new behaviour: a regenerated device id now
     **retires every stored secret**, so the documented "bump `_deviceIdKey` to
     re-challenge every device" procedure actually re-challenges instead of
     leaving users holding credentials that can never match.
10. **Part D reports, it does not act.** There is no "re-issue this device's
    credential" or "clear this lockout" button — the fix is always "have them
    sign in and enter the code", which needs the customer anyway. An admin-side
    revoke (which would *force* the step-up again) is the natural next step.
11. **Part D cannot show what was never recorded.** No failed OTP attempts and
    no refused devices, for the reasons in §3.14. The screen says so rather than
    letting an empty list look like "nobody tried".
12. **Part D is a view onto a feature that ships switched off.** While
    `enforcement_enabled` is `false`, the screen leads with
    `enforcement_off` and the credential state is context, not the answer. If
    anything, that makes it a useful pre-flight check before the flip: it shows
    how many accounts would be holding credential-less devices when enforcement
    starts.
13. **The timeline is capped at 100 events** (`LIMIT 100`, newest first) —
    enough for a support conversation, not an audit export.
14. **The gate is an RLS control, so `SECURITY DEFINER` RPCs are outside it**
    (measured, not assumed — see §3.8). The policies cover direct PostgREST
    table access, which is what a hand-crafted client does; a definer function
    owned by `postgres` bypasses RLS on its own tables, so a client with no
    device secret can still *call* an RPC that touches a gated table. Concretely
    verified for `request_pickup_reservation` (item 14) with enforcement ON: the
    call succeeds, while the matching direct `SELECT` on `pickup_reservations`
    returns nothing. In that case the effect is benign — the RPC enforces
    ownership itself, and the untrusted client cannot *read* what it created —
    but it means **"the table is gated" ≠ "every path to the table is gated"**,
    and the same is true of the voucher and order RPCs. Closing it means adding
    an explicit `device_is_trusted()` check at the top of the definer RPCs that
    touch gated tables; doing it per-RPC makes forgetting one easy, so it is
    worth a single deliberate pass (with a guard test that every definer RPC
    touching a gated table calls it) rather than sprinkling it in as each
    feature lands. Until then, treat this document's claims as being about RLS,
    not about every code path.
