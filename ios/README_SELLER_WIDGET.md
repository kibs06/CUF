# Seller home-screen widget — iOS setup

**Status: the Swift is written, the Xcode target is NOT. iOS currently shows no
widget.**

Android is complete and verified (`SellerWidgetProvider.kt`, the layout, the
manifest receiver, the background worker — the tile appears in the launcher).
iOS cannot be finished from this machine: a WidgetKit widget only exists as a
**target inside `Runner.xcodeproj`**, and a target is not a file you can add —
it is a `project.pbxproj` entry plus a build phase plus a signing configuration
plus an entitlement, all of which Xcode does and none of which hand-editing
does safely. So this document is the remaining work, and the files it refers to
are already in the repo.

---

## What is already in the repo

| File | Role |
| --- | --- |
| `ios/SellerWidget/SellerWidget.swift` | The widget: `TimelineProvider`, SwiftUI view, `@main` declaration |
| `ios/SellerWidget/SellerWidget.entitlements` | The App Group the extension reads |
| `ios/SellerWidget/Info.plist` | Extension metadata (`com.apple.widgetkit-extension`) |
| `lib/services/seller_widget_service.dart` | The **only** writer; calls `setAppGroupId` on iOS |
| `lib/models/customer_widget_data.dart` | The **customer** half of the same payload (`customer_state` + three product slots) |

> **The tile serves two roles, and the Swift as written only draws one.** A
> seller's payload is the counters `SellerWidget.swift` reads; a customer's is
> three products and a shelf name, written to the same App Group under
> `customer_state` / `customer_group` / `customer_product_<n>_*` (see
> `CustomerWidgetKeys`). So when this target is created, a phone signed in as a
> customer will reach the seller's **empty state** — the group's keys are there,
> but a product feed is a grid of images and prices rather than a row of
> counters, and it needs its own view. That is a second Swift file and a branch
> on `customer_state`, not a tweak to this one; until then, an iOS customer sees
> no products rather than a wrong tile.

## What must be done in Xcode (on a Mac)

1. **Open `ios/Runner.xcworkspace`** (not the `.xcodeproj` — the workspace
   carries the CocoaPods/SPM wiring Flutter needs).

2. **Add the target.** File → New → Target… → **Widget Extension**. Name it
   `SellerWidget`. **Uncheck** "Include Configuration Intent" — this widget is a
   `StaticConfiguration`, so an intent would add a generated file that
   contradicts `SellerWidget.swift`.

3. **Replace the generated source.** Delete the `SellerWidget.swift` Xcode
   generates and add the one in this repo instead (right-click the group → Add
   Files). Also set the target's **Info.plist** to the one in this repo (Build
   Settings → `INFOPLIST_FILE` → `SellerWidget/Info.plist`).

4. **Add the App Group to BOTH targets.** For `Runner` *and* `SellerWidget`:
   Signing & Capabilities → **+ Capability** → **App Groups** → add
   `group.com.solevision.app`.

   > The `Runner` half is what makes the app the writer. It is easy to add the
   > group to the extension only, which compiles cleanly and then shows a
   > permanently empty widget — the app is silently writing somewhere the
   > extension cannot read. `Runner/Runner.entitlements` in this repo is a
   > *different*, still-disabled file (Universal Links); let Xcode create or
   > update the entitlements it actually signs with.

5. **Confirm the widget `kind`.** The target's `kind:` string must be
   `SellerWidget` — it is the value `SellerWidgetService.iOSWidgetName` passes to
   `home_widget`, and a mismatch means the Dart side writes data and reloads
   nothing.

6. **Build and place it.** Run on a device or simulator, long-press the home
   screen → add widget → "Seller briefing". Sign in as a seller: the Dart side
   already syncs on launch, on foreground and on auth changes.

## The three names that must match

A mismatch here is silent on both sides — the widget simply renders its empty
state — so they are worth checking together:

| Where | Value |
| --- | --- |
| `SellerWidget.swift` → `kAppGroupId` | `group.com.solevision.app` |
| `SellerWidgetService.iOSAppGroupId` (Dart) | `group.com.solevision.app` |
| Xcode → App Groups, both targets | `group.com.solevision.app` |

…and, for the reload to land:

| Where | Value |
| --- | --- |
| `SellerWidget.swift` → `kWidgetKind` | `SellerWidget` |
| `SellerWidgetService.iOSWidgetName` (Dart) | `SellerWidget` |

## Why the iOS widget refreshes the way it does

`getTimeline` returns a `.never` policy and the provider never fetches. That is
deliberate, not an omission:

- A WidgetKit timeline provider runs in the **extension's sandbox**: no Flutter
  engine, no Dart isolate, no Supabase session. It cannot fetch a seller's
  revenue, so re-asking it on a schedule would only redraw the same bytes.
- The real refresh is the `workmanager` job registered by
  `SellerWidgetService.registerBackgroundRefresh()` — it runs Dart, fetches, and
  then calls `HomeWidget.updateWidget`, which reloads this widget's timeline.

Consequence to be aware of: if iOS declines the background budget for a long
time (Low Power Mode, a rarely-used app), the tile shows its last snapshot and
its "Updated …" line makes that visible rather than implying it is live. This is
the same trade Android makes with a 30-minute `WorkManager` floor.

## Not verified

Everything above is **unrun**. There is no macOS or Xcode on the machine this
feature was built on, so the Swift has never been compiled, the entitlements
have never been signed, and no iOS widget has ever been placed. Treat this file
as work instructions, not as evidence.
