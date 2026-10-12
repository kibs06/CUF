import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workmanager/workmanager.dart';

import '../constants/app_constants.dart';
import '../models/customer_widget_data.dart';
import '../models/seller_widget_data.dart';
import 'customer_widget_service.dart';
import '../widgets/seller/seller_inventory_row.dart' show kLowStockThreshold;
import 'order_service.dart';
import 'pickup_reservation_service.dart';
import 'product_service.dart';
import 'reservation_service.dart';
import 'sales_service.dart';
import 'seller_notification_service.dart';
import 'store_service.dart';
import 'supabase_service.dart';

/// Pushes the signed-in account's home-screen tile: a seller's dashboard numbers,
/// or a customer's rotating product feed.
///
/// ## Why this can't just read the dashboard
///
/// The widget is drawn by Android/iOS in a process that has no Flutter isolate,
/// no `Provider` tree and no `BuildContext` — `SellerDashboardScreen` and its
/// `_DashboardData` are unreachable from it. So this service is the **only**
/// writer: it fetches the same five numbers the dashboard shows, flattens them
/// through [SellerWidgetData], and hands the result to `home_widget`, which
/// persists it where the native widget reads it.
///
/// ## Two callers, and they are different kinds of process
///
///  * **The app, while it is open.** [syncForCurrentUser] runs on login, on
///    return to the foreground and after a logout, so the widget is fresh
///    whenever the seller has just been looking at the app.
///  * **A background worker.** [registerBackgroundRefresh] schedules a periodic
///    Android/iOS job that calls the same code path with no UI at all — see
///    [sellerWidgetBackgroundDispatcher]. That is what keeps the numbers moving
///    (roughly every [refreshInterval]) when the app has not been opened.
///
/// ## The rule that matters for the seller's data
///
/// **The widget is written from the seller's own session, and cleared when that
/// session ends.** A signed-out phone, a customer account, or a seller whose
/// store was removed must never leave another account's takings frozen on the
/// home screen — [clear] is called on every path where the answer is "no seller
/// here", and the native side shows its empty state instead of stale numbers.
class SellerWidgetService {
  SellerWidgetService._();

  static final SellerWidgetService instance = SellerWidgetService._();

  /// Must match `android:name` of the `AppWidgetProvider` in `AndroidManifest`.
  ///
  /// `home_widget` resolves this against `<package>.<name>`, so the class is
  /// `com.solevision.app.SellerWidgetProvider`. Renaming one without the other
  /// throws `PlatformException(-8)` on Android rather than failing quietly.
  static const String androidWidgetName = 'SellerWidgetProvider';

  /// Must match the `kind` string in the WidgetKit `Widget` declaration.
  static const String iOSWidgetName = 'SellerWidget';

  /// The App Group the iOS widget extension reads the payload from.
  ///
  /// iOS has no shared preferences store between an app and its widget
  /// extension, so the two can only meet inside an **App Group container**.
  /// This must match, exactly:
  ///
  ///   * the `com.apple.security.application-groups` entry in BOTH
  ///     `Runner.entitlements` and the widget extension's entitlements, and
  ///   * the suite name the Swift `TimelineProvider` reads.
  ///
  /// `home_widget` fails loudly (PlatformException -6/-7) if a write happens
  /// before this is set, which is why [_configureiOS] runs first on every path.
  static const String iOSAppGroupId = 'group.com.solevision.app';

  /// Identifies the periodic job. Stable, because
  /// [registerBackgroundRefresh] is idempotent *by this name* — a second call
  /// with the same unique name replaces the schedule instead of stacking a
  /// second worker on top of the first.
  static const String backgroundTaskName = 'seller-widget-refresh';

  /// How often the background worker runs.
  ///
  /// 30 minutes is the floor Android's `WorkManager` honours for periodic work
  /// (anything shorter is silently clamped), and it is inside iOS's own
  /// opportunistic window. The OS treats both as a *hint* — a phone in Doze may
  /// run this hours late — which is why the widget also prints the time it was
  /// last written rather than implying it is live.
  static const Duration refreshInterval = Duration(minutes: 30);

  bool get _supportedPlatform =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Gather, or clear, for whoever is signed in right now.
  ///
  /// The branch is deliberate and total: there is no state in which this
  /// returns without having written *something*, so a phone that switches
  /// accounts can never keep showing the previous one's numbers.
  ///
  /// **There are now two roles and not two widgets.** A seller sees their
  /// dashboard numbers; a customer sees a rotating feed of products; a phone with
  /// no session sees the empty state. One placed tile changes what it draws when
  /// the account behind it changes — which is the whole reason the seller branch
  /// and the customer branch must each erase the other's keys before writing (see
  /// [_clearKeys]).
  ///
  /// [advance] is passed to the customer feed's rotation and nowhere else: true on
  /// the **scheduled** refresh, false on an app-driven one. A tile that rotated on
  /// every login would change every time the customer opened the app, which is not
  /// a refresh.
  Future<void> syncForCurrentUser({bool advance = false}) async {
    if (!_supportedPlatform) return;
    if (!AppConstants.sellerWidgetEnabled) return;

    try {
      // Every branch below announces itself. This is not debugging scaffolding:
      // the widget's whole state machine is "which of four branches did I take?",
      // and without these lines all four look identical from outside — an empty
      // tile and no log, which is indistinguishable from the code never running.
      // Deliberately no user id, store name, revenue or counts: this is the
      // device log, and the whole point of these lines is which branch, not whose
      // money it is.
      if (Supabase.instance.client.auth.currentUser == null) {
        debugPrint('[SellerWidget] no session → cleared');
        await clear();
        return;
      }

      // "Is this user a seller with a store?" — asked of the same source the
      // seller catalog uses, so the widget and the Products tab can never
      // disagree about whether this account is a seller.
      final storeId = await ProductService.instance.getSellerStoreId();
      if (storeId == null || storeId.isEmpty) {
        // Signed in, but not a seller — which is a customer, and a customer gets
        // a feed rather than an empty tile.
        await _pushCustomerFeed(advance: advance);
        return;
      }

      final store = await StoreService.instance.getMyStore();
      final data = await gather(
        storeId: storeId,
        storeName: (store?['name'] as String?)?.trim() ?? '',
      );
      // The other role's keys go FIRST: both payloads live in one store and the
      // native side branches on a single flag, so a stale customer feed left
      // behind would reappear the moment this phone signed in as a customer
      // again — showing products the account is no longer looking at.
      await _clearKeys(CustomerWidgetKeys.all);
      await push(data);
      debugPrint('[SellerWidget] pushed for a seller store');
    } catch (e) {
      // Never throw into a lifecycle callback: a widget that fails to refresh
      // must not take down the app that is merely being resumed.
      debugPrint('[SellerWidget] sync failed: $e');
    }
  }

  /// The customer branch: a rotating product feed, or an empty tile.
  ///
  /// Clearing is the answer to every "nothing to show" here — the switch is off,
  /// the fetch failed, the catalog is empty, or no group has anything in it — and
  /// that is deliberate: a customer tile with a heading and no products under it
  /// is worse than the honest sign-in prompt, and [CustomerWidgetService.gather]
  /// returns null for each of those rather than inventing a shelf.
  Future<void> _pushCustomerFeed({required bool advance}) async {
    if (!AppConstants.customerWidgetEnabled) {
      debugPrint('[SellerWidget] customer feed is switched off → cleared');
      await clear();
      return;
    }

    final feed = await CustomerWidgetService.instance.gather(advance: advance);
    if (feed == null) {
      // Signed in as a customer with nothing to show. Deliberately NOT [clear]:
      // clearing would let the tile fall back to the seller layouts and tell a
      // signed-in customer to "sign in as a seller" — the wrong role and the wrong
      // words. Writing the customer's empty state keeps it in the customer layouts,
      // where the branch that says "nothing to show right now" is the true one.
      //
      // The seller keys still go, and this is the one branch where it is easy to
      // forget them: the account is not a seller, so anything under `seller_*` is
      // the previous account's — left behind, it would be drawn the moment this
      // phone signed back in as a seller whose own sync had not run yet.
      debugPrint('[SellerWidget] customer with nothing to show → empty state');
      await _clearKeys(SellerWidgetKeys.all);
      await _clearKeys(CustomerWidgetKeys.all);
      for (final entry in CustomerWidgetData.emptyStateValues().entries) {
        await _saveValue(entry.key, entry.value);
      }
      await _updateWidgets();
      return;
    }

    await _clearKeys(SellerWidgetKeys.all);
    await pushCustomer(feed);
    debugPrint('[SellerWidget] pushed a customer feed');
  }

  /// Write a customer feed and ask the OS to redraw.
  ///
  /// The same three steps as [push] — configure iOS, save every primitive through
  /// the runtime-typed branch, redraw — because the two payloads differ in content
  /// and not in transport, and a second copy of that transport is how one of them
  /// ends up writing an `int` through the `String` branch.
  Future<void> pushCustomer(CustomerWidgetData data) async {
    if (!_supportedPlatform) return;
    await _configureiOS();

    for (final entry in data.toWidgetValues().entries) {
      await _saveValue(entry.key, entry.value);
    }
    await _updateWidgets();
  }

  /// Fetch the five numbers for [storeId].
  ///
  /// Every metric is guarded on its own, and the reason is the same for all of
  /// them: these are six independent queries and a widget that blanks entirely
  /// because the reservations query timed out is worse than one showing the
  /// revenue it does have. A failed metric falls back to its zero and only its
  /// own tile goes quiet.
  Future<SellerWidgetData> gather({
    required String storeId,
    required String storeName,
  }) async {
    final salesService = SalesService();
    final orderService = OrderService();

    // ── Today's revenue ──────────────────────────────────────────
    var todayRevenue = 0.0;
    try {
      todayRevenue = await salesService.getTodayRevenue(storeId);
    } catch (e) {
      debugPrint('[SellerWidget] today revenue failed: $e');
    }

    // ── Orders awaiting the seller ───────────────────────────────
    // `pending` is the one status the seller has to act on (the dashboard's
    // own card opens `ManageOrdersScreen(initialFilter: 'pending')`), so the
    // widget reports that status and not a sum over every order.
    var pendingOrders = 0;
    try {
      final byStatus = await orderService.getOrderCountByStatus(storeId);
      pendingOrders = byStatus['pending'] ?? 0;
    } catch (e) {
      debugPrint('[SellerWidget] order counts failed: $e');
    }

    // ── Custom (made-to-order) requests ──────────────────────────
    var pendingCustoms = 0;
    try {
      final customizations = await SupabaseService.instance.fetchCustomizations();
      pendingCustoms =
          customizations.where((c) => c['status'] == 'pending').length;
    } catch (e) {
      debugPrint('[SellerWidget] customisations failed: $e');
    }

    // ── Bulk reservation requests (deposit-gated) ────────────────
    var pendingReservations = 0;
    try {
      pendingReservations =
          await ReservationService.instance.fetchPendingCount(storeId);
    } catch (e) {
      debugPrint('[SellerWidget] reservations failed: $e');
    }

    // ── Live pickup holds (free, already off the shelf) ──────────
    // Read through the same `fetchStoreStats` the dashboard uses, so the two
    // surfaces cannot drift on what "active" means. `expireStale` is
    // deliberately NOT called here: the sweep releases holds and is a
    // dashboard-open responsibility, and a background job silently walking
    // stock back onto shelves is not something a widget refresh should do.
    var activePickups = 0;
    try {
      final stats =
          await PickupReservationService.instance.fetchStoreStats(storeId);
      activePickups = stats.active;
    } catch (e) {
      debugPrint('[SellerWidget] pickup stats failed: $e');
    }

    // ── Low stock ────────────────────────────────────────────────
    var lowStockCount = 0;
    try {
      final products = await SupabaseService.instance.fetchProducts(
        storeId: storeId,
      );
      lowStockCount = countLowStockRows(products);
    } catch (e) {
      debugPrint('[SellerWidget] low stock failed: $e');
    }

    // ── Unread seller notifications ──────────────────────────────
    var unread = 0;
    try {
      unread = await SellerNotificationService.instance.getUnreadCount(storeId);
    } catch (e) {
      debugPrint('[SellerWidget] unread count failed: $e');
    }

    return SellerWidgetData(
      hasStore: true,
      storeName: storeName,
      todayRevenue: todayRevenue,
      pendingOrders: pendingOrders,
      pendingCustoms: pendingCustoms,
      pendingReservations: pendingReservations,
      activePickups: activePickups,
      lowStockCount: lowStockCount,
      unreadNotifications: unread,
      updatedAt: DateTime.now(),
    );
  }

  /// Write [data] to the widget and ask the OS to redraw it.
  Future<void> push(SellerWidgetData data) async {
    if (!_supportedPlatform) return;
    await _configureiOS();

    for (final entry in data.toWidgetValues().entries) {
      // `home_widget` types the value on the Dart side; the null case exists so
      // a cleared key is deleted rather than written as "null".
      await _saveValue(entry.key, entry.value);
    }
    await _updateWidgets();
  }

  /// Empty the widget. Called on logout and on any failure that leaves us unsure
  /// who is signed in — see the class note.
  ///
  /// **Both key families, always.** The tile is shared by two roles, so "no seller
  /// here" is not the same statement as "no customer here": clearing one and not
  /// the other is exactly how a signed-out phone keeps showing the last account's
  /// tile, and how a role switch shows the previous role's numbers for a refresh.
  Future<void> clear() async {
    if (!_supportedPlatform) return;
    await _configureiOS();

    await _clearKeys(SellerWidgetKeys.all);
    await _clearKeys(CustomerWidgetKeys.all);
    await _updateWidgets();
  }

  /// Erase one family of payload keys.
  ///
  /// `null` rather than an empty string: `home_widget` deletes the entry, and a
  /// key left holding `""` is a value the native side would read as a real (blank)
  /// one — for `customer_state` that is a blank role flag rather than "no role",
  /// and for a product id it is a row that exists and can be tapped into nothing.
  Future<void> _clearKeys(List<String> keys) async {
    for (final key in keys) {
      await HomeWidget.saveWidgetData<String>(key, null);
    }
  }

  /// Run a background refresh right now, in this isolate.
  ///
  /// Exposed for the test harness and for a manual "refresh the widget"
  /// affordance: it is the same work the scheduled worker does, without
  /// waiting up to [refreshInterval] for the OS to decide to run it.
  Future<void> refreshNow() => syncForCurrentUser();

  /// `saveWidgetData<T>` is generic per call, so the runtime type has to pick
  /// the branch. `home_widget` persists a different native storage type for
  /// each (boolean/int/double/String), and writing a `double` through the
  /// `String` branch would reach the widget as the text "0.0".
  Future<void> _saveValue(String key, Object? value) async {
    if (value is bool) {
      await HomeWidget.saveWidgetData<bool>(key, value);
    } else if (value is int) {
      await HomeWidget.saveWidgetData<int>(key, value);
    } else if (value is double) {
      await HomeWidget.saveWidgetData<double>(key, value);
    } else {
      await HomeWidget.saveWidgetData<String>(key, value?.toString() ?? '');
    }
  }

  Future<void> _updateWidgets() => HomeWidget.updateWidget(
        androidName: androidWidgetName,
        iOSName: iOSWidgetName,
      );

  /// Points `home_widget` at the App Group before any write on iOS.
  ///
  /// Android needs nothing here: its payload lands in the app's own
  /// `SharedPreferences` and the provider runs in the same process group. iOS is
  /// the platform where the widget extension is a *separate process* with its
  /// own sandbox, so the shared container is the only meeting point — and the
  /// plugin throws (`-7`, "AppGroupId not set") rather than writing somewhere the
  /// widget can never read. Cheap and idempotent, so it is called per write
  /// rather than tracked with a flag that could drift.
  Future<void> _configureiOS() async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return;
    await HomeWidget.setAppGroupId(iOSAppGroupId);
  }

  /// Schedule the periodic background refresh.
  ///
  /// Safe to call on every launch: `registerPeriodicTask` is keyed on
  /// [backgroundTaskName], and `ExistingPeriodicWorkPolicy.keep` means a job
  /// that is already scheduled is left alone rather than restarted (restarting
  /// it on every launch would reset the 30-minute clock and, on a phone opened
  /// often, mean it never fires at all).
  Future<void> registerBackgroundRefresh() async {
    if (!_supportedPlatform) return;
    if (!AppConstants.sellerWidgetEnabled) return;

    try {
      await Workmanager().initialize(sellerWidgetBackgroundDispatcher);
      await Workmanager().registerPeriodicTask(
        backgroundTaskName,
        backgroundTaskName,
        frequency: refreshInterval,
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      );
    } catch (e) {
      debugPrint('[SellerWidget] background registration failed: $e');
    }
  }

  /// Stop the background job — used when the switch is turned off or a seller
  /// signs out for good, so a device that is no longer a seller's does not keep
  /// waking up to query their store.
  Future<void> cancelBackgroundRefresh() async {
    if (!_supportedPlatform) return;
    try {
      await Workmanager().cancelByUniqueName(backgroundTaskName);
    } catch (e) {
      debugPrint('[SellerWidget] background cancel failed: $e');
    }
  }
}

/// Counts product/size rows at or below the seller's low-stock threshold.
///
/// A pure function, lifted out of [SellerWidgetService.gather] so the counting
/// rule is testable without a database. It mirrors
/// `SellerDashboardScreen._getLowStockItems` exactly — `sizes` is a
/// `{size: quantity}` map, and only **positive** quantities count: `0` is
/// *out of stock*, which the inventory UI paints as a different (worse) state
/// and which this count deliberately excludes, because "low" and "gone" are
/// answered by different screens.
///
/// The threshold is [kLowStockThreshold] rather than a literal, because that is
/// the one definition the stock sheet, the Manage Products filter and the
/// customer portal's `lowStockRows` all read.
int countLowStockRows(
  List<Map<String, dynamic>> products, {
  int? threshold,
}) {
  final int limit = threshold ?? kLowStockThreshold;
  var count = 0;
  for (final product in products) {
    final rawSizes = product['sizes'];
    if (rawSizes is! Map) continue;
    for (final quantity in rawSizes.values) {
      if (quantity is int && quantity > 0 && quantity <= limit) count++;
    }
  }
  return count;
}

/// Entry point the OS calls for the periodic job.
///
/// **Must stay a top-level function with `@pragma('vm:entry-point')`**: it is
/// invoked in a fresh isolate that has no reference to anything created in
/// `main()`, and the annotation is what keeps the Dart AOT compiler from
/// tree-shaking it away. Removing either half produces a worker that silently
/// never runs (Android) or is dropped at link time (release builds).
@pragma('vm:entry-point')
void sellerWidgetBackgroundDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    if (taskName != SellerWidgetService.backgroundTaskName) return true;
    try {
      // The background isolate gets a cold Dart environment — Supabase is NOT
      // initialised here. `Supabase.initialize` restores the session the app
      // persisted, so the queries below run with the seller's own RLS context
      // and nothing else.
      //
      // Called unconditionally rather than behind an "is it already up?" check,
      // because the only such check — `Supabase.instance` — *asserts* when it
      // is not initialised, so asking the question is what would throw. The
      // call itself is safe to repeat: `initialize` returns the existing
      // instance when `_isInitialized` is already true.
      await Supabase.initialize(
        url: AppConstants.url,
        publishableKey: AppConstants.publishableKey,
      );
      // `advance: true` is the difference between this call and the app's: the
      // scheduled run is the one that moves the customer tile on to its next
      // group. Everything else — claiming the session, gathering, choosing what
      // to erase — is the same code path, on purpose.
      await SellerWidgetService.instance.syncForCurrentUser(advance: true);
    } catch (e) {
      debugPrint('[SellerWidget] background refresh failed: $e');
      // `false` lets the platform retry with backoff instead of waiting the
      // full interval, which matters for a transient network failure.
      return false;
    }
    return true;
  });
}
