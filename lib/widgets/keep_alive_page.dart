import 'package:flutter/material.dart';

/// Keeps a page inside a lazily-built viewport alive once it has been visited.
///
/// **Why this exists.** A [PageView] builds ONLY the page it is currently
/// showing: its viewport sets `cacheExtent` to 0 unless
/// `allowImplicitScrolling` is on, and none of the shell's tab pages ask to be
/// kept alive. So jumping to another tab scrolls the previous page out of the
/// viewport and **disposes** it. Coming back then builds it from scratch:
/// `initState()` runs again, which re-fires that screen's data fetches, and the
/// screen re-shows its loading skeleton. Every single tab tap paid for a full
/// rebuild *and* a refetch — the exact behaviour this widget removes.
///
/// Wrapping each page in this widget makes the page request keep-alive on its
/// subtree's behalf: a visited page stays mounted, so its `State` (loaded data,
/// scroll offset, text controllers, open sheets) survives, while an unvisited
/// page is still built lazily on first visit.
///
/// Note what this deliberately is NOT: a plain [IndexedStack]. An `IndexedStack`
/// builds all its children up front, so the seller shell would fire every tab's
/// data fetches in the first frame — five concurrent loaders on the landing
/// screen. Keeping the lazy viewport and making pages sticky gives the same
/// instant switching without the launch-time fan-out, and it preserves the
/// existing horizontal swipe between tabs.
///
/// **How it works.** [AutomaticKeepAliveClientMixin] dispatches a
/// [KeepAliveNotification]. The `AutomaticKeepAlive` that the sliver's
/// child-list delegate inserts around each page listens for that notification
/// from anywhere in its subtree — which is precisely why a *wrapper* can send
/// it for a child it does not own. Keeping this widget separate also means the
/// five tab screens (and the shared `ProfileScreen`) stay untouched.
class KeepAlivePage extends StatefulWidget {
  const KeepAlivePage({super.key, required this.child});

  /// The page to keep alive. Must be the widget the viewport would otherwise
  /// dispose — i.e. one entry of the `PageView`'s children.
  final Widget child;

  @override
  State<KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<KeepAlivePage>
    with AutomaticKeepAliveClientMixin {
  /// Always true: a page that has been built once should never be torn down
  /// while it is still part of the viewport's children.
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    // Required by the mixin — this call is what registers the keep-alive
    // handle for this element. Removing it silently disables all of the above.
    super.build(context);
    return widget.child;
  }
}
