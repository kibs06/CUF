# Social sign-in setup (Google + Facebook)

The code is fully wired — buttons, service methods, portal callback — but the
buttons stay dormant until this one-time console setup lands. Until then both
providers fail with **setup copy, not a crash**:

- App: *"Google/Facebook sign-in is not switched on yet. Use your email and
  password for now."*
- Portal: *"Social sign-in is not switched on yet. Use your email and password
  for now."*

Ship order: **Google first, Facebook second** (Facebook needs a Meta app taken
Live before the public can use it).

## 1. Supabase (both providers)

1. Dashboard → Authentication → Providers: enable **Google** (Web client ID +
   secret) and **Facebook** (App ID + secret).
2. Copy the provider callback URL shown there
   (`https://<project-ref>.supabase.co/auth/v1/callback`):
   - Google Cloud → OAuth client → Authorized redirect URIs.
   - Meta → Facebook Login → Valid OAuth Redirect URIs.
3. Enable **Skip nonce check** for Google (the native `signInWithIdToken`
   flow needs it).
4. Auth → URL Configuration: Site URL = production portal origin. Add
   EACH portal's callback (they are different deployments, so each origin
   needs its own entry — same rule as `/auth/confirm`):
   - Admin portal: `<admin-origin>/auth/callback` (prod + `http://localhost:5173` for dev).
   - Customer storefront: `<storefront-origin>/auth/callback`
     (prod, e.g. `https://cufmai-portal.vercel.app/auth/callback`, + the local
     `vite dev` origin for dev).
   Confirm `solvision://auth/confirm` + `solvision://auth/recovery`
   are still listed (email flows are untouched).

## 2. Google Cloud

- One **Web application** OAuth client (its ID doubles as `serverClientId`).
  Pass it at build time — never commit it:
  `flutter run --dart-define=GOOGLE_SERVER_CLIENT_ID=<web-client-id>`.
  Until it is supplied the app keeps the dormant *"not switched on yet"*
  copy (guard in `AuthService.signInWithGoogle`). `google-services.json`
  carries no `oauth_client` entry, so the explicit ID is required.
- Android: **3 clients**, all package `com.solevision.app`, one SHA-1 each:
  - debug: `B2:CC:A2:B2:84:74:E6:67:C4:41:BC:78:88:C8:50:70:C3:5F:14:6E`
  - release: extract locally with
    `keytool -list -v -keystore android/app/cufmai-release.jks`
    (password lives in your local `android/key.properties`, never committed).
  - Play: **Play Console → Test and release → App signing** → App signing
    key certificate (NOT the upload key — the store strips it, so a
    Play-installed build fails without this client).
- iOS: bundle ID `com.solevision.app`. Put the iOS client ID in
  `ios/Runner/Info.plist` as `GIDClientID` (replacing
  `REPLACE_WITH_GOOGLE_IOS_CLIENT_ID`) and its **reversed** form
  (`com.googleusercontent.apps.…`, replacing
  `REPLACE_WITH_REVERSED_IOS_CLIENT_ID`) in `CFBundleURLSchemes`
  (merged with the existing `solvision` entry — do not replace it).

## 3. Meta (Facebook)

- App with **Facebook Login**; permissions `email` + `public_profile`
  (Android also requests `openid` for the OIDC token — already in code).
- Android package name + **key hashes** (debug, release, Play Signing).
- Replace the placeholders:
  - `android/app/src/main/res/values/strings.xml`: `facebook_app_id`,
    `facebook_client_token`, `fb_login_protocol_scheme` (`fb` + app ID).
  - `android/app/src/main/AndroidManifest.xml`: provider `authorities` must
    end with the real app ID (`…FacebookContentProvider<APP_ID>`).
  - `ios/Runner/Info.plist`: add `FacebookAppID`, `FacebookClientToken`,
    `FacebookDisplayName`, and the `fb<APP_ID>` URL scheme (merge with the
    existing schemes, as with Google above).
- Take the app **Live** with Advanced Access for `email`/`public_profile`
  (needs Business Verification; anything beyond that needs App Review with a
  testable build + screen recordings) — dev-mode apps work only for listed
  test users.

## 4. Rules that stay true after setup

- Social proves **identity**, never **role**: new app users are `customer`s;
  sellers still apply; the portal signs non-admins straight back out.
- Facebook often returns **no email** — the app signs the user in anyway and
  asks them to add one in Edit Profile (the `emailMissing` return).
- Email/password is untouched and stays: every social button is an *extra*
  path on the existing screens, never a replacement.
