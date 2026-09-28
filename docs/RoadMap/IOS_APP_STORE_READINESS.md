# iOS App Store Readiness — Flag

**Version:** 0.1.0
**Created:** September 28, 2026
**Updated:** September 28, 2026 — initial flag: the gap inventory below was verified by inspection, not estimated
**Owner:** Mobile (Flutter/iOS) + Product
**Status:** 🚩 **FLAGGED — not started.** Decision taken 2026-09-28: **the app will be made downloadable on iOS "soon"**. Nothing in this document has been built yet; the inventory is the starting point, not a plan that has begun
**Umbrella roadmap:** `docs/RoadMap/SOLEVISION_ROADMAP.md` Phase 9 ("Platform Expansion")
**Related:** `docs/RoadMap/VIRTUAL_FITTING_ROADMAP.md` (AR is Android-first — iOS/ARKit parity is explicitly out of scope there), `docs/AI/SHARE_PRODUCT_ARCHITECTURE.md` (Universal Links, domain-gated), `lib/widgets/update_overlay.dart` + `lib/screens/shared/whats_new_screen.dart` (the iOS update path is a static stub today)

---

## 1. Why this flag exists

Asked on 2026-09-28: *can this app be downloaded by iOS?* The answer was **no, not by any iOS user** — although the project is a Flutter app with a real `ios/` target, the entire shipping path is Android-only.

The platform is *capable*; the **distribution pipeline and four build prerequisites are missing**. This document is the flag so the "soon" work has a written starting point with exact file evidence.

---

## 2. What is already true (verified by inspection, 2026-09-28)

| Thing | State | Evidence |
|---|---|---|
| iOS project target | ✅ Present | `ios/Runner.xcodeproj`, `ios/Runner.xcworkspace`, `AppDelegate.swift`, `SceneDelegate.swift` |
| Minimum OS | ✅ Set | `IPHONEOS_DEPLOYMENT_TARGET = 13.0` (all three build configs) |
| Bundle identifier | ⚠️ Set but inconsistent | `PRODUCT_BUNDLE_IDENTIFIER = com.solevision.app` (project) vs URL scheme name `com.cufmai.solvision.checkout` (Info.plist) |
| App icons | ✅ Generated & App-Store-clean | `ios/Runner/Assets.xcassets/AppIcon.appiconset/` complete; `remove_alpha_ios: true` in `pubspec.yaml` because App Store validation rejects an alpha channel |
| Display name | ✅ Set | `CFBundleDisplayName` / `CFBundleName` = `CUFMAI` |
| Permission strings | ✅ Present | `NSCameraUsageDescription`, `NSLocationWhenInUseUsageDescription` in `ios/Runner/Info.plist` |
| Plugin registrant | ✅ Present | `ios/Runner/GeneratedPluginRegistrant.m` lists **28 native plugins**, and every one of them has an iOS implementation: `app_badge_plus, app_links, camera_avfoundation, connectivity_plus, device_info_plus, firebase_core, firebase_messaging, flutter_local_notifications, flutter_secure_storage_darwin, geocoding_darwin, geolocator_apple, google_mlkit_{commons,pose_detection,selfie_segmentation,text_recognition}, image_cropper, image_picker_ios, local_auth_darwin, mobile_scanner, open_filex, package_info_plus, permission_handler_apple, share_plus, shared_preferences_foundation, sqflite_darwin, url_launcher_ios, video_player_avfoundation, video_thumbnail` — so B3 is about *resolving* pods, not about missing platform support |
| Firebase iOS *app id* | ⚠️ Declared, not wired | `firebase.json` + `lib/firebase_options.dart` carry an iOS app id (`1:162309360658:ios:ee58ba870bc85c894f1ccb`) |
| CI iOS compile check | ❌ None | `.github/workflows/ci.yml` is `ubuntu-latest`, `flutter analyze` + `flutter test` only |
| iOS release artifact | ❌ None | `.github/workflows/release.yml` builds `flutter build apk` only; `releases/version.json` carries an `apk_url` and no iOS field |

---

## 3. Blockers (B1–B8)

Each of these must be closed before an iPhone user can install the app.

| # | Blocker | Evidence | Effort |
|---|---|---|---|
| **B1** | **No App Store presence.** No App Store Connect app record, no listing, no TestFlight build. The app's own iOS copy admits it: `update_overlay.dart` renders a static *"Open the App Store to update"* panel and `whats_new_screen.dart` says *"Updates are installed from the App Store on iOS."* — neither opens a real URL | `lib/widgets/update_overlay.dart:366`, `lib/screens/shared/whats_new_screen.dart:385` | Medium |
| **B2** | **Signing unconfigured.** `CODE_SIGN_STYLE = Automatic` with **no `DEVELOPMENT_TEAM`** and no provisioning profile → an archive cannot be signed or uploaded. Requires a paid Apple Developer Program membership (also required for TestFlight) | `ios/Runner.xcodeproj/project.pbxproj` (no `DEVELOPMENT_TEAM` key) | Small |
| **B3** | **CocoaPods never resolved.** **No `ios/Podfile` and no `Podfile.lock`** → `flutter build ios` / `pod install` has never run in this repo, so iOS dependency resolution is unproven against the 28 registered native plugins | `ls ios/Podfile ios/Podfile.lock` → both absent | Small |
| **B4** | **Firebase iOS config file missing.** Only `android/app/google-services.json` exists; there is **no `ios/Runner/GoogleService-Info.plist`** → `firebase_core` initialisation and `firebase_messaging` push would fail on iOS. Needs an APNs auth key uploaded to Firebase | `find . -name GoogleService-Info.plist` → no result | Small |
| **B5** | **Bundle identity undecided.** Two identifiers in play (`com.solevision.app`, `com.cufmai.solvision.checkout`) and a third-party brand question between the SoleVision project name and the shipped `CUFMAI` display name. App Store Connect requires one canonical, permanent identifier and one public name | `project.pbxproj:385,564,586`; `Info.plist` | Small |
| **B6** | **Export-compliance key absent.** `Info.plist` has no `ITSAppUsesNonExemptEncryption`, so every upload stalls on the export-compliance question — and the app ships `flutter_secure_storage` / `crypto`, which makes the answer non-trivial | `ios/Runner/Info.plist` | Small |
| **B7** | **Privacy disclosures unwritten.** The app uses `camera`, `google_mlkit_*`, `image_picker`, `geolocator`, `local_auth`, `shared_preferences`, `path_provider`, `flutter_secure_storage`, plus FCM — all of which need App Store privacy nutrition labels and, for camera/photo use, a written justification. Biometric + location are review-sensitive | `pubspec.yaml` dependencies | Medium |
| **B8** | **No iOS build automation.** No macOS runner anywhere; a tag produces only an `.apk`. TestFlight uplifts must be scripted or they will be hand-made every release | `.github/workflows/release.yml`, `.github/workflows/ci.yml` | Medium |

### Deliberately not a blocker

- **AR virtual try-on.** There is no AR implementation under `ios/` — pose detection (`google_mlkit_pose_detection`) is cross-platform, but the ARCore renderer is Android-only. `VIRTUAL_FITTING_ROADMAP.md` records iOS/ARKit parity as **out of scope for v1**. An App Store build does not require it; the feature simply must degrade to the existing simulated screen.
- **Universal Links.** `ios/Runner/Runner.entitlements` holds an `applinks:YOUR-DOMAIN.com` placeholder and is **not wired into Xcode**. Product share links work via the Supabase edge-function URL, so this can wait for a custom domain.

---

## 4. Work packages

Ordered so each one unblocks the next. Effort units as in the other roadmaps: Small < 3 days · Medium 3–7 days · Large 1.5–3 weeks.

| # | Package | Contents | Depends on | Effort |
|---|---|---|---|---|
| **I1** | Signing & identity | Enroll/confirm Apple Developer Program; pick the canonical bundle id (B5); register the App Store Connect app record; set `DEVELOPMENT_TEAM`; enable the capabilities the app needs | — | Small |
| **I2** | First real iOS build | On a Mac: `flutter pub get` → `flutter build ios --no-codesign` → fix whatever the plugin set surfaces; **commit `ios/Podfile` and `Podfile.lock`** | I1 | Small–Medium |
| **I3** | Firebase iOS | Add the iOS app in the Firebase console, drop in `GoogleService-Info.plist`, upload the APNs auth key, confirm `firebase_options.dart`'s iOS entry matches, verify a push arrives | I1, I2 | Small |
| **I4** | Info.plist hardening | Add `ITSAppUsesNonExemptEncryption`; re-check every purpose string against what the app actually does; confirm iPad orientations (`UIInterfaceOrientation*~ipad`) are genuinely supported | I2 | Small |
| **I5** | Listing & review pack | Public name decision (CUFMAI vs SoleVision), subtitle/description, screenshots for the required device sizes, privacy nutrition labels (B7), age rating, review notes explaining biometric login, camera scanning and why location is asked for | I4 | Medium |
| **I6** | TestFlight + release automation | macOS CI job (or a scripted local path) that archives, exports an `.ipa` and uploads to TestFlight using an App Store Connect API key; extend `releases/version.json` with an iOS field | I2, I3 | Medium |
| **I7** | In-app update parity | Point the iOS branch of the update overlay / What's-New screen at the real App Store listing; audit `lib/services/update_checker.dart`, which is Android-oriented | I5 | Small |
| **I8** | *(deferred)* ARKit parity | Only if iOS AR becomes a goal in its own right — see `VIRTUAL_FITTING_ROADMAP.md` | — | Very Large |

---

## 5. Definition of done

The flag can only be cleared when **all** of these hold:

1. A version tag produces an iOS build that is uploaded to **TestFlight** alongside the existing APK.
2. A TestFlight build installs on a physical iPhone and passes a smoke run of: signup/login (incl. biometric), browse, cart, checkout, order tracking, messaging, **push notification received**, and camera-based barcode scan.
3. Seller flows (POS, orders, dashboard) work on an iOS device, or the app correctly hides them if seller mode is Android-only by design.
4. The **public App Store listing is live** and approved by review.
5. `flutter analyze lib test && flutter test` still passes, and CI fails if the iOS target stops compiling.

---

## 6. Decisions still owed (not engineering)

| # | Decision | Why it matters |
|---|---|---|
| **D1** | Canonical bundle identifier | Permanent once published; drives signing, Firebase, Universal Links and push |
| **D2** | Public app name (CUFMAI vs SoleVision) | Listing + brand; the binary currently says `CUFMAI` |
| **D3** | Does iOS v1 need push notifications? | No → B4/I3 can slip; Yes → I3 is on the critical path |
| **D4** | Does iOS v1 need AR try-on? | Recommended **no** (Android-first per `VIRTUAL_FITTING_ROADMAP.md`), otherwise add I8 |
| **D5** | Who owns the Apple Developer account and the $99/yr membership | Blocks I1 entirely |

---

## 7. How to re-check the current state

```bash
# Is the iOS target still there and what is the tiny minimum OS?
grep -n "IPHONEOS_DEPLOYMENT_TARGET\|PRODUCT_BUNDLE_IDENTIFIER\|DEVELOPMENT_TEAM" ios/Runner.xcodeproj/project.pbxproj

# Has CocoaPods ever been resolved?
ls ios/Podfile ios/Podfile.lock

# Is Firebase wired for iOS?
find . -name "GoogleService-Info.plist" -not -path "./build/*"

# Does any pipeline produce an iOS artifact?
grep -rn "ios\|ipa\|TestFlight\|app store connect" .github/workflows/
```

If §7 shows a `Podfile.lock`, a `GoogleService-Info.plist`, a `DEVELOPMENT_TEAM`, and an iOS job in `.github/workflows`, this flag is stale — update it.
