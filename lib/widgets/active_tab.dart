import 'package:flutter/widgets.dart';

/// Publishes which bottom-navigation tab is currently on screen.
///
/// **Why this exists.** Once the tab pages are kept alive (see
/// `KeepAlivePage`) a page's `build` does NOT run again when the user switches
/// back to it: the element is already built and the widget instance is
/// unchanged, so `Element.updateChild` short-circuits. That is exactly what
/// makes switching instant — but it also removes the only moment a screen could
/// notice "I am visible again", which is when data that went stale while the
/// page sat off screen should be refreshed.
///
/// This widget supplies that moment. It is rebuilt with a new [index] on every
/// switch, so every dependent's `didChangeDependencies` runs — including
/// kept-alive pages, which are still active elements even though they are not
/// repainted. A screen therefore implements its re-entry behaviour as:
///
/// ```dart
/// @override
/// void didChangeDependencies() {
///   super.didChangeDependencies();
///   final tab = ActiveTab.of(context);
///   if (tab == null || tab == _lastSeenTab) return;
///   _lastSeenTab = tab;
///   if (tab == myTabIndex) _refreshIfStale();
/// }
/// ```
///
/// **Refetch on re-entry is opt-in and TTL-gated.** The shell publishes the
/// index unconditionally; a screen decides whether that means "fetch again",
/// and should only do so when its cached data has aged past its own staleness
/// window. Re-selecting a tab is never on its own a reason to hit the network.
///
/// [of] returns null when there is no [ActiveTab] ancestor, so a screen that
/// also runs outside a tab host (e.g. pushed as its own route, or hosted by a
/// shell that does not publish one) simply skips its re-entry logic.
class ActiveTab extends InheritedWidget {
  const ActiveTab({super.key, required this.index, required super.child});

  /// Index of the tab currently on screen.
  final int index;

  /// The active tab index, or null when this context is not inside an
  /// [ActiveTab].
  ///
  /// Call from `build` or `didChangeDependencies` — it registers a dependency,
  /// so it must not be used from `initState` or `dispose`.
  static int? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ActiveTab>()?.index;

  @override
  bool updateShouldNotify(ActiveTab oldWidget) => oldWidget.index != index;
}
