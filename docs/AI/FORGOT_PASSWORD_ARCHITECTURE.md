# Forgot Password Architecture

## ⚠️ Live status — the app is correct, the project's mailer is not

**Measured Oct 12, 2026: "Forgot password?" cannot send on the live project.**
The exact request the button makes, replayed with the app's own anon key:

```
POST https://psczvbfoybqhjeqssimw.supabase.co/auth/v1/recover
{"email":"<an address with an account>"}

→ HTTP 500  {"code":500,"error_code":"unexpected_failure",
             "msg":"Error sending recovery email","error_id":"01a12f97-…"}
```

An address with **no** account answers `200` — GoTrue short-circuits and mails
nothing — so the 500 is a **send failure**, not a bad address and not the
user's fault. Nothing in this flow's Dart is broken: the button calls
`resetPasswordForEmail` correctly and GoTrue mails nothing.

**The cause, read off the auth log rather than inferred: the App Password is
stale.** The client cannot see the mailer's own error, but
**Dashboard → Logs → Auth** has it, on the row for that request:

```
path: /recover   status: 500   error_code: unexpected_failure
auth_event: user_recovery_requested  (actor = the account, log_type user)
error: 535 "5.7.8 Username and Password not accepted. For more information,
            go to https://support.google.com/mail/?p=BadCredentials - gsmtp"
```

A `- gsmtp` reply only comes out of an SMTP conversation **with Gmail**, so
custom SMTP *is* configured on the hosted project and Gmail is refusing its
credentials — Google revokes an App Password when the account password changes
or 2-Step Verification is toggled (the rotation §R8 warns about). This is
**a rotation, not a first-time setup**, and the earlier "the project is still on
the built-in mailer" reading is now disproven: a built-in-mailer send never
reaches Gmail's SMTP, so it can never return a 535 from `gsmtp`.

**Every flow that e-mails is down with it**, not just this one, because the
failure is in the SMTP handshake and not in any one message: sign-up
confirmation, the new-device step-up code, password reset, and the "Change
password" action (`account_security_screen.dart`,
`manage_login_device_screen.dart`) all ride the same mailer.

**The fix is a fresh credential, not code:**

```bash
# 1. Google Account → Security → App passwords → create one for CUFMAI Auth
#    (spaces in the 16 chars can stay or go; the tool strips them)
# 2. Point GoTrue's SMTP at it — one command, then it re-reads every field:
SUPABASE_ACCESS_TOKEN=… GMAIL_SENDER=… GMAIL_APP_PASSWORD=… \
  dart run tool/apply_live_auth_mail.dart
# 3. Update the Edge Functions' GMAIL_APP_PASSWORD too — two stores, and a
#    rotation that misses one leaves send-approval-email / send-lockout-email
#    broken while auth starts working (or the reverse).
```

…or the same values by hand in **Authentication → SMTP Settings** (§R8).
Needs the project's access token + the Gmail App Password, so it is a
dashboard/credential step, not a repo change.

**What the app does about it (landed with this note).** gotrue turns *every*
HTTP ≥ 500 into `AuthRetryableFetchException` and discards the body's
`error_code`, so the mapper's mailer branches were unreachable and this 500
read as "CUFMAI couldn't finish that request. Please try again in a few
minutes." — advice that cannot work, because retrying is exactly what fails.
`friendlyAuthErrorMessage` now recovers `error_code` from the body (gotrue
keeps it in `message`) and answers with the mailer copy instead.

### ⚠️ The gap BEHIND that one: the reset LINK resolved to `localhost:3000`

**Measured Oct 12, 2026 — the mail arrives and the reset still cannot be
completed.** The button in the delivered mail opened
`http://localhost:3000/?error=access_denied…` on the customer's phone:
`ERR_CONNECTION_REFUSED`. Fixing the mailer moved the failure to the next
layer, and that layer is *server config*, not Dart. Read off the live project
with the runbook tool:

```
Current uri_allow_list: (empty)
Current site_url:       http://localhost:3000
```

**Why it landed there.** This app sent no `redirectTo` for resets — all three
call sites (`auth_service.dart` ×2, `supabase_service.dart`) called
`resetPasswordForEmail(email)` bare — so GoTrue resolved the recovery link to
the project's **Site URL**: the `localhost:3000` default every new project
ships with. An empty allow list means an explicit redirect could not have been
honoured either, so both fields had to change together.

**The page that finishes a reset is already deployed** —
`https://cufmai-portal.vercel.app` (Vercel project `cufmai-portal`, built from
`customer-portal/` in this repo). Verified live rather than assumed: `/account`
answers `200`, and the served bundle contains `resetPasswordForEmail`,
`updatePassword` and the recovery banner *"You followed a password reset
link"*. That page is the web half of the reset — the app's own
set-new-password screen landed in the same change (item 1 below), so the portal
is the fallback and the destination for a reset started on the website:

**What the app did NOT have at the time** — the reason the link could not be
absorbed in-process (all three landed on Oct 12, 2026, below):

| Absent in the Flutter app THEN | Evidence |
|---|---|
| recovery deep-link handling | no `type=recovery` anywhere in `lib/` |
| a customer "set a new password" screen | the only `updateUser({password:…})` was an **admin** action (`admin_settings_screen.dart`) |
| a recovery redirect scheme | `DeepLinkService` knew only `solvision://auth/confirm` (sign-up) |

**What this flow now does** (all landed with this note):

1. **The reset link comes back INTO the app.** All three reset call sites send
   `redirectTo: DeepLinkService.authRecoveryRedirect`
   (`solvision://auth/recovery`), so the mail's button opens CUFMAI with a
   short-lived recovery session (`#access_token=…&type=recovery`, stored by
   supabase_flutter's own deep-link observer, exactly as for the confirmation
   link) and `AuthGate` renders `ResetPasswordScreen` — the new-password form,
   which calls `AuthService.updatePassword` (`updateUser({password})`) and
   leaves the customer signed in. `AndroidManifest.xml` declares that path
   beside `/confirm` in the same intent-filter.
2. **The portal is the web half of the same flow.** `customerPortalUrl` is the
   live **Site URL** and `/account` is allow-listed, so a reset STARTED ON THE
   WEBSITE (`requestPasswordReset` → `${origin}/account`), or one whose app
   redirect GoTrue will not honour, still lands on a page that can set a
   password.
3. `tool/apply_live_auth_mail.dart` writes the live fields in the same `PATCH`
   it already used for SMTP and the templates: `site_url` = the portal, and
   `uri_allow_list` merged with the app's two deep links and the portal's
   `/account` + `/**`. `--check` prints both values and three rows of its own,
   so the destination is verifiable without opening a mailbox.
4. `test/services/deep_link_service_test.dart` pins both deep links against
   `AndroidManifest.xml`, and `test/services/password_reset_redirect_test.dart`
   pins the recovery constant against the three call sites, the tool's
   literals, the portal's own source and the runbook — none of those compile
   against each other, so nothing else would catch a drift.

**Two limits of the in-app route, stated rather than hidden.** The app link can
only be opened on a device that HAS the app: a customer who requests the reset
in the app and then opens the mail on a laptop gets the browser's "no app to
open" dead end and has to ask for a new link (GoTrue spends the token on the
click). And the reset still proves only what it always proved — whoever holds
the mailbox owns the account — so the mail's arrival IS the authentication; the
link does not add a factor.

**Still owed, and only a click settles it:** request a fresh reset, tap the
button on the phone, and set a password on the screen that opens. A `200` from
`/recover` proves the mail left and nothing about the destination; an older mail
fails as `otp_expired`, which is evidence about the link's age, not about the
config. Step 5 of §R8 in `docs/fixes/GO_LIVE_PRELAUNCH_CHECKLIST.md` has the
check table for both routes.

---

## Overview

Password reset via email using **Supabase Auth**. The reset link returns to the
**app** (`solvision://auth/recovery` → `ResetPasswordScreen`), which is where a
customer who tapped "Forgot password?" already is. The **customer portal's
account page** is the web half — a reset started on the website, and the
project's Site URL fallback — and Supabase hosts no reset UI of its own.

---

## Flow

1. User taps "Forgot password?" on login screen
2. App validates email field is not empty
3. App calls `resetPasswordForEmail(email, redirectTo: DeepLinkService.authRecoveryRedirect)`
4. Supabase sends email with reset link
5. User sees: "Password reset link sent to {email}"
6. User taps the button ON THE PHONE → the app opens, already signed in with the
   short-lived recovery session GoTrue attached (`#access_token=…&type=recovery`)
7. `ResetPasswordScreen` takes the new password → `updateUser({password})`
8. The session is now a normal one: the customer is in the shell, and the old
   password no longer works (the website route instead lands them on the
   portal's `/account`, step 7 happening there)

---

## Entry Points

### 1. Login Screen
**File:** `lib/screens/auth/account_entry_screen.dart`

- "Forgot password?" text button in sign-in mode
- Takes email from login form's email field
- Shows SnackBar with success/error

### 2. Lockout Overlay
**File:** `lib/widgets/lockout_overlay.dart`

- "Reset password" button shown when account is locked (5+ failed attempts)
- Uses the email that triggered the lockout
- Account remains locked until reset or 30-minute timer expires
- Shows **where the attempts came from** — the place the attempt's IP resolves
to, its coordinate pair and the network that owns the address (see
[Where the attempt came from](#where-the-attempt-came-from))

---

## Code

### Service Layer
```dart
// lib/services/auth_service.dart — and the same in SupabaseService.resetPassword,
// which is the one the sign-in screen's button actually reaches.
Future<void> resetPassword(String email) async {
  await _client.auth.resetPasswordForEmail(
    email.trim(),
    redirectTo: DeepLinkService.authRecoveryRedirect,
  );
}

// The screen the link then opens (AuthGate → ResetPasswordScreen).
Future<void> updatePassword(String newPassword) async {
  await _client.auth.updateUser(UserAttributes(password: newPassword));
}
```

### Provider Layer
```dart
// lib/providers/auth_provider.dart
Future<bool> resetPassword(String email) async {
  try {
    await _db.resetPassword(email);
    return true;
  } catch (e) {
    _errorMessage = friendlyAuthErrorMessage(e);
    return false;
  }
}
```

### UI Layer
```dart
// lib/screens/auth/account_entry_screen.dart
Future<void> _forgotPassword() async {
  final email = _emailController.text.trim();
  if (email.isEmpty) {
    _showError('Please enter your email address first.');
    return;
  }
  
  final auth = Provider.of<AuthProvider>(context, listen: false);
  final success = await auth.resetPassword(email);
  
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(success
          ? 'Password reset link sent to $email'
          : auth.errorMessage ?? 'Unable to send reset email.'),
      backgroundColor: success ? AppConstants.success : AppConstants.error,
    ),
  );
}
```

---

## Security

- **Email enumeration protection**: Same message for existing/non-existing emails
- **Rate limiting**: Supabase limits email sends (shows "Too many attempts" error)
- **Token security**: Managed by Supabase (cryptographic, one-time use, expires)
- **Lockout integration**: Accounts stay locked during reset process

---

## Error Messages

| Scenario | Message |
|----------|---------|
| Empty email field | "Please enter your email address first." |
| Success | "Password reset link sent to {email}" |
| Rate limited | "Too many attempts. Try again in about a minute." |
| New password too weak (the screen) | "That password's too weak. Use at least 6 characters." (`weak_password`) |
| New password is the old one (the screen) | "That is already your password — choose a different one." (`same_password`) |
| Reset finished (the screen) | "Password updated — you are signed in." |
| The customer declines (the screen) | "Not now" leaves the session in place; the password can be changed later from Account security |
| Mailer cannot send (or refuses the recipient) | "We couldn't deliver that email — that one is on us. Contact support and we will sort it out." (`authErrorMailNotSent`) |
| Nothing reached the server | "We couldn't reach CUFMAI. Check your connection and try again." (`authErrorNetwork`) |
| 5xx with no readable reason | "CUFMAI couldn't finish that request. Please try again in a few minutes." (`authErrorServer`) |

All of these come from `friendlyAuthErrorMessage` in
`lib/utils/auth_error_messages.dart` — the table mirrors those constants rather
than restating copy of its own.

---

## Key Files

| File | Purpose |
|------|---------|
| `lib/screens/auth/account_entry_screen.dart` | Login screen with forgot password link |
| `lib/widgets/lockout_overlay.dart` | Lockout overlay with reset button, the attempt's device/IP **and its approximate location** |
| `lib/services/ip_geolocation_service.dart` | `IpLocation` + `IpGeolocationService` — the city-level lookup behind every location the lockout shows |
| `test/services/ip_geolocation_service_test.dart`, `test/widgets/lockout_overlay_test.dart` | The contracts: parsing/formatting against a real measured `ipwho.is` body, the HTTPS host, every failure path returning null, and the overlay showing the place, the caveat, and nothing at all when there is no location |
| `lib/providers/auth_provider.dart` | `resetPassword()`, plus the recovery link's state machine (`pendingPasswordRecovery`, `completePasswordRecoveryFromEmailLink`, `applyRecoveredPassword`, `cancelPasswordRecovery`) |
| `lib/services/auth_service.dart` | Supabase `resetPasswordForEmail()` call and `updatePassword()` |
| `lib/services/deep_link_service.dart` | `authRecoveryRedirect` (`solvision://auth/recovery`) + its routing predicate |
| `lib/screens/auth/reset_password_screen.dart` | The set-new-password screen the reset link opens |
| `lib/screens/auth_gate.dart` | Renders that screen ahead of every profile-based route |
| `lib/main.dart` (`DeepLinkHost`) | Routes the incoming recovery link into the provider |
| `lib/utils/auth_error_messages.dart` | Error message mapping (`weak_password`, `same_password`) |
| `tool/apply_live_auth_mail.dart` | Writes the live Site URL + allow list (`--check` reads them back) |
| `test/services/deep_link_service_test.dart`, `test/services/password_reset_redirect_test.dart`, `test/screens/reset_password_screen_test.dart` | The contracts: the constants against `AndroidManifest.xml`, the tool and the runbook; and the screen's own form |

---

## Where the attempt came from

A lockout records two things about the other end: the device and the IP
address. Neither answers the first question an owner asks — *where was this?* —
so the app resolves the address to an approximate location and shows it on
**all three** surfaces the lockout already reaches: the overlay, the e-mail to
the account owner, and the admin's intruder view.

| Piece | Where |
|-------|-------|
| `IpGeolocationService` + `IpLocation` | `lib/services/ip_geolocation_service.dart` — one keyless HTTPS GET to `ipwho.is` (1,000/day per client IP, commercial use allowed on the free endpoint) |
| Collected | `AuthProvider._collectDeviceInfo()` — device → IP → location, in that order, every step best-effort |
| Owner surfaces | `lib/widgets/lockout_overlay.dart` (place, coordinates, network, plus the caveat) and `supabase/functions/send-lockout-email/index.ts` (same three fields in the mail, and in the admin push + the "this wasn't me" report text) |
| Admin surfaces | `lib/screens/admin/intruder_suspicious_login_screen.dart` (the chip under the IP) and `lib/screens/admin/admin_account_security_screen.dart` (the lockout card), fed by the `failed_logins` columns |
| Persisted | `failed_logins.location` / `.latitude` / `.longitude` — `supabase/migrations/20261012120000_add_location_to_failed_logins.sql` |

**⚠️ It is city-level, and every surface says so.** An IP address identifies a
network, not a person. The lookup resolves to the city the address block is
registered in; for a mobile pool that is the carrier's hub, which can be a
different city — sometimes a different region — from the one the device is
physically in. The coordinates are that city's centroid, not a device position.
The overlay carries the sentence *"Location comes from the IP address, so it is
city-level — not a street address"*, the mail says *approximate, city-level*,
the admin card labels the place *(approximate)*, and the diagnostics RPC's
`cannot_answer` block repeats it where an admin is most likely to misread a city
as an address. **Nothing may render any of this as an address.**

**Nothing here can fail a lockout.** No network, a rate limit, a malformed body
and a timeout all return null, and the geo fields are dropped from the write when
the database does not have the columns yet (`advanceFailedCounter` retries the
same row without them — see that migration's status row). The lockout decision
does not read any of it.

**How the row is written, and why it is not an upsert.** `advanceFailedCounter`
reads the account's newest `failed_logins` row (id included) and then either
**updates it by primary key** or **inserts** one — an explicit choice rather than
`upsert(..., onConflict: 'user_id')`. Postgres refuses that conflict target here
because the only unique index on `user_id` is partial, so the upsert answered
`42P10` and, with the caller treating the write as best-effort, every lockout
went unrecorded. The measured details, and the schema fix that would let an
upsert work again, are in `supabase/MIGRATIONS_LIVE_STATUS.md`.

**Also resolved server-side.** The e-mail function looks the address up itself
when the caller sent no location, so an installed build that predates these
fields still produces a location in the mail the owner receives, and the server
truth does not depend on which APK happens to be on the other end.

---

## Lockout Behavior

When account is locked (5+ failed attempts):
1. Lockout overlay appears with 30-minute countdown
2. "Reset password" is the primary action
3. The reset mail goes to the locked address through the SAME call site as the
   sign-in screen's link (`AuthService.sendLockoutNotificationEmail`), so it
   returns to the app's set-new-password screen
4. The lockout itself is **local** (SharedPreferences, keyed by email) and is
   cleared on a successful sign-in. A recovery link IS one: the screen sets the
   password on the session the link already established, so the customer is
   signed in without passing the pre-login lockout check at all. A reset
   started from the website does not do that for them — the portal sets the
   password but leaves no app session, so they still wait out the timer (or
   sign in on a device that holds no lockout).

---

## Supabase Configuration

- Reset token expiration: 3600 seconds (1 hour) - configurable in dashboard
- Email template: Managed by Supabase Auth
- Rate limiting: Enabled by default

---

## Summary

Simple flow: User taps "Forgot password?" → App calls `resetPasswordForEmail()`
with the app's own deep link → Supabase sends the mail → the customer taps the
button on their phone → the app opens on the set-new-password screen, already
signed in by the link → the new password is set with `updateUser()` and the
customer lands in the shell. The website route ends on the portal's `/account`
instead. Security is Supabase's (single-use tokens, expiry, rate limiting) plus
the app's (email validation, error mapping, the project's own password rule
checked on both sides).
