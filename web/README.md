# `web/` — static hosting root for Universal/App Links (Phase B)

This folder holds the platform-verification files needed for **tap-to-open-app**
behavior on shared product links. **It is not deployed anywhere yet** — and it
cannot be until the team owns a custom domain (links currently live on
`*.supabase.co`, which can't host these files).

## What to do when a custom domain exists

1. Point a domain (e.g. `YOUR-DOMAIN.com`) at **any static host** and serve the
   contents of this folder at the domain root, or add these two files to an
   existing site:
   - `https://YOUR-DOMAIN.com/.well-known/assetlinks.json`
   - `https://YOUR-DOMAIN.com/.well-known/apple-app-site-association`

2. Fill in the placeholders:
   - `assetlinks.json`: replace `REPLACE_WITH_SIGNING_CERT_SHA256` with the
     release keystore's SHA-256 (from `keytool -list -v`). You can list more
     than one fingerprint (one per signing key used over the app's life).
   - `apple-app-site-association`: replace `TEAMID` with your Apple Developer
     Team ID (10-char).

3. Flip the app-side config:
   - `android/app/src/main/AndroidManifest.xml`: uncomment + fill the App Links
     `<intent-filter>` (instructions are inline).
   - `ios/Runner/Runner.entitlements` + Xcode Associated Domains capability
     (instructions are inline in the file).

4. Update `AppConstants.productShareBaseUrl` to `https://YOUR-DOMAIN.com/p` so
   newly shared links are the clean domain form.

Verification commands:
- Android: `adb shell pm verify-app-links --re-verify com.solevision.app`
- iOS: ship to TestFlight; tap a link and confirm it opens the app.

The OG preview card itself does NOT depend on this folder — it is served by the
`product-preview` Supabase Edge Function (see `docs/AI/SHARE_PRODUCT_ARCHITECTURE.md`).
