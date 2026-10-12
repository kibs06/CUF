//
//  SellerWidget.swift
//  SellerWidget
//
//  The seller home-screen widget — the iOS half of the feature whose Android
//  half lives in `android/app/src/main/kotlin/com/solevision/app/SellerWidgetProvider.kt`.
//
//  ─────────────────────────────────────────────────────────────────────────
//  ⚠️  NOT YET WIRED INTO THE XCODE PROJECT — see ios/README_SELLER_WIDGET.md
//  ─────────────────────────────────────────────────────────────────────────
//
//  This file is the widget's source, not a working widget. A WidgetKit widget
//  only exists once it is a **Widget Extension target** in
//  `Runner.xcodeproj`, and an Xcode target cannot be created by editing files —
//  it is a `project.pbxproj` entry plus a build phase plus a signing
//  configuration. Hand-editing the pbxproj to fake that is how projects get
//  corrupted, so the target is created in Xcode by hand; the steps are in
//  `ios/README_SELLER_WIDGET.md`, and the checklist is short.
//
//  Until then this file is inert: nothing compiles it, and the app's Dart side
//  (`SellerWidgetService`) writes to an App Group no extension is reading.
//  **iOS currently has no visible widget.**
//
//  ── Where the data comes from ────────────────────────────────────────────
//
//  Like Android's provider, this file **fetches nothing.** WidgetKit runs the
//  timeline provider in the extension's own sandbox with no Flutter engine and
//  no Supabase session, so all it can do is render the snapshot Dart wrote.
//  Dart fetches and decides; this renders.
//
//  The snapshot arrives through the **App Group** — the only storage an app and
//  its widget extension can share. `SellerWidgetService` calls
//  `HomeWidget.setAppGroupId('group.com.solevision.app')` before writing, and
//  the three names that must agree are:
//
//    1. `kAppGroupId` below,
//    2. the `com.apple.security.application-groups` value in BOTH
//       `Runner.entitlements` and `SellerWidget.entitlements`, and
//    3. `SellerWidgetService.iOSAppGroupId` in Dart.
//
//  A mismatch is silent on this side — `UserDefaults(suiteName:)` returns nil
//  and the widget renders its empty state forever.
//

import SwiftUI
import WidgetKit

/// Must match `SellerWidgetService.iOSAppGroupId` (Dart) and the entitlements.
private let kAppGroupId = "group.com.solevision.app"

/// Must match `SellerWidgetService.iOSWidgetName` — home_widget reloads the
/// timeline by this `kind`.
private let kWidgetKind = "SellerWidget"

// MARK: - Payload keys

/// The wire format shared with `SellerWidgetKeys` in
/// `lib/models/seller_widget_data.dart`.
///
/// ⚠️ There is no generated binding between a Dart map and `UserDefaults`, so
/// these strings are duplicated on purpose and must be changed on both sides
/// together. A renamed key renders as a blank field on every phone that already
/// has the widget placed — it is not a compile error anywhere.
private enum Key {
    static let hasStore = "seller_has_store"
    static let storeName = "seller_store_name"
    static let revenueLabel = "seller_revenue_label"
    static let pendingOrders = "seller_pending_orders"
    static let pendingCustoms = "seller_pending_customs"
    static let activePickups = "seller_active_pickups"
    static let lowStock = "seller_low_stock"
    static let unread = "seller_unread_notifications"
    static let updatedLabel = "seller_updated_at_label"
}

// MARK: - The snapshot the view renders

/// One reading of the payload, already resolved out of `UserDefaults`.
///
/// Mirrors `SellerWidgetData` on the Dart side, minus the fields the tile does
/// not draw. Everything is a `String` because Dart pre-formats every value it
/// wants shown — the clock and the money are decided once, in Dart, so this
/// widget and the Android provider cannot disagree about how `₱12,500` reads.
struct SellerSnapshot {
    var hasStore: Bool
    var storeName: String
    var revenueLabel: String
    var orders: Int
    var customs: Int
    var pickups: Int
    var lowStock: Int
    var unread: Int
    var updatedLabel: String

    /// The empty state: no seller signed in on this device, or no store yet.
    static let empty = SellerSnapshot(
        hasStore: false,
        storeName: "",
        revenueLabel: "",
        orders: 0,
        customs: 0,
        pickups: 0,
        lowStock: 0,
        unread: 0,
        updatedLabel: ""
    )

    /// Reads the payload. Never throws and never fails: a missing App Group, a
    /// first-run phone or a signed-out account all land on [empty], which is a
    /// state the view already knows how to draw.
    static func read() -> SellerSnapshot {
        guard let defaults = UserDefaults(suiteName: kAppGroupId) else {
            return .empty
        }

        let orders = defaults.integer(forKey: Key.pendingOrders)
        let customs = defaults.integer(forKey: Key.pendingCustoms)
        let pickups = defaults.integer(forKey: Key.activePickups)

        return SellerSnapshot(
            // The ONE flag that decides empty vs populated — never "is the name
            // blank", because a store genuinely can be named "".
            hasStore: defaults.bool(forKey: Key.hasStore),
            storeName: defaults.string(forKey: Key.storeName) ?? "",
            revenueLabel: defaults.string(forKey: Key.revenueLabel) ?? "-",
            orders: orders,
            customs: customs,
            pickups: pickups,
            // NOTE: `integer(forKey:)` returns 0 for a missing key, and a
            // missing key only happens before the first write. That is honest
            // ("nothing yet") and is also why a failure in one Dart metric
            // renders as 0 rather than blanking the tile.
            lowStock: defaults.integer(forKey: Key.lowStock),
            unread: defaults.integer(forKey: Key.unread),
            updatedLabel: defaults.string(forKey: Key.updatedLabel) ?? ""
        )
    }
}

// MARK: - Timeline provider

struct SellerProvider: TimelineProvider {
    func placeholder(in context: Context) -> SellerSnapshot {
        // Shown in the widget gallery and while the first timeline loads.
        SellerSnapshot(
            hasStore: true,
            storeName: "Sole Studio",
            revenueLabel: "₱12.5k",
            orders: 3,
            customs: 2,
            pickups: 1,
            lowStock: 4,
            unread: 5,
            updatedLabel: "2:31 PM"
        )
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (SellerSnapshot) -> Void
    ) {
        completion(SellerSnapshot.read())
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<SellerSnapshot>) -> Void
    ) {
        let snapshot = SellerSnapshot.read()

        // `.never` on purpose, and this is the subtle half.
        //
        // WidgetKit would happily re-ask us on its own schedule, but this
        // provider can only re-read the same bytes — it cannot fetch (no
        // session, no Flutter). A self-refreshing timeline would therefore
        // redraw identical content and, worse, spend the app's limited
        // background-refresh budget doing it. The real refresh is the
        // `workmanager` job in Dart, which fetches AND then calls
        // `HomeWidget.updateWidget` — that reload is what moves this widget.
        //
        // The trade, stated plainly: if the background job stops running (the
        // user disables background refresh in Settings, or iOS declines the
        // budget for a long time), the tile keeps showing its last snapshot and
        // says so via the timestamp rather than pretending to be live.
        completion(Timeline(entries: [snapshot], policy: .never))
    }
}

// MARK: - View

/// `"3 orders"`, `"1 order"` — the same copy the Android provider builds, so the
/// two platforms read alike. Zero still prints, because a blank cell reads as a
/// bug rather than as zero.
private func countLabel(_ value: Int, _ singular: String, _ plural: String) -> String {
    "\(value) \(value == 1 ? singular : plural)"
}

struct SellerWidgetEntryView: View {
    var snapshot: SellerSnapshot

    var body: some View {
        if !snapshot.hasStore {
            emptyState
        } else {
            content
        }
    }

    private var emptyState: some View {
        VStack(spacing: 4) {
            Text("Seller briefing")
                .font(.system(size: 13, weight: .bold))
            Text("Sign in to a seller account to see your store here.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // One tap target for the whole tile, matching Android: the seller lands
        // on the dashboard, where every counter has a real touch target. The
        // scheme is the one already registered in Runner/Info.plist.
        .widgetURL(URL(string: "solvision://seller"))
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(snapshot.storeName)
                .font(.system(size: 13, weight: .bold))
                .lineLimit(1)

            Text("TODAY")
                .font(.system(size: 9))
                .tracking(0.8)
                .foregroundStyle(.secondary)
                .padding(.top, 8)

            Text(snapshot.revenueLabel)
                .font(.system(size: 26, weight: .bold))
                .lineLimit(1)

            Divider().padding(.vertical, 8)

            HStack(spacing: 4) {
                counter(countLabel(snapshot.orders, "order", "orders"), tinted: true)
                counter(countLabel(snapshot.customs, "custom", "custom"), tinted: true)
                counter(countLabel(snapshot.pickups, "hold", "holds"), tinted: true)
            }

            HStack(spacing: 4) {
                counter(countLabel(snapshot.lowStock, "low stock", "low stock"))
                counter(countLabel(snapshot.unread, "unread", "unread"))
            }
            .padding(.top, 4)

            Text("Updated \(snapshot.updatedLabel)")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(URL(string: "solvision://seller"))
    }

    /// Equal-width counter cell. `tinted` matches Android's accent colouring for
    /// the three action queues versus the muted restock/unread pair.
    private func counter(_ text: String, tinted: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 11, weight: tinted ? .bold : .regular))
            .foregroundStyle(tinted ? Color.accentColor : Color.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Widget declaration

@main
struct SellerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kWidgetKind,
            provider: SellerProvider()
        ) { entry in
            SellerWidgetEntryView(snapshot: entry)
                // A container background is required from iOS 17; the widget
                // body is no longer allowed to paint its own background.
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Seller briefing")
        .description(
            "Your store's day at a glance: today's sales, orders to action, low stock and unread messages."
        )
        .supportedFamilies([.systemMedium])
    }
}
