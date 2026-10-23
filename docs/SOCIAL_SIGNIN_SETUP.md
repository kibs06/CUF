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
4. Auth → URL Configuration: Site URL = production portal origin; add
   `<portal-origin>/auth/callback` (prod + `http://localhost:5173`) to
   Redirect URLs. Confirm `solvision://auth/confirm` + `solvision://auth/recovery`
   are still listed (email flows are untouched).

## 2. Google Cloud

- One **Web application** OAuth client (its ID doubles as `serverClientId`).
- Android apps: package name + **SHA-1** for debug, release, AND the Play App
  Signing certificate (a release built with the upload key but installed via
  Play fails Google sign-in otherwise).
- iOS app: bundle ID; put the iOS client ID in `ios/Runner/Info.plist` as
  `GIDClientID` and register its **reversed** form in `CFBundleURLSchemes`
  (merge with the existing `solvision` entry — do not replace it).
- If the app has no `google-services` config with a Web client entry, pass the
  Web client ID as `serverClientId` in `AuthService.signInWithGoogle`.

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
