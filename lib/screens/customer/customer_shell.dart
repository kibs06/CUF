import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../constants/app_constants.dart';
import '../../models/update_info.dart';
import '../../providers/notification_provider.dart';
import '../../providers/update_provider.dart';
import '../../utils/nav_perf.dart';
import '../../widgets/active_tab.dart';
import '../../widgets/auth/require_sign_in.dart';
import '../../widgets/cart_icon_button.dart';
import '../../widgets/double_back_to_exit.dart';
import '../../widgets/hide_on_scroll_bottom_bar.dart';
import '../../widgets/keep_alive_page.dart';
import '../../widgets/sole_bottom_nav.dart';
import '../../widgets/update_overlay.dart';
import 'customer_home_screen.dart';
import '../store/store_screen.dart';
import '../notifications_screen.dart';
import '../shared/profile_screen.dart';
import '../shared/settings_screen.dart';

class CustomerShell extends StatefulWidget {
  /// `true` when nobody is signed in — a fresh install, or a shopper who signed
  /// out. Home and Stores are the full storefront; Notifications and Profile
  /// render a sign-in prompt instead of screens that need a session.
  ///
  /// AuthGate decides this, not the shell: the same widget serves both states
  /// so that signing in from a prompt upgrades the tabs in place (the shopper
  /// stays on the tab they were on) instead of rebuilding the whole scaffold.
  final bool guest;

  const CustomerShell({super.key, this.guest = false});

  @override
  State<CustomerShell> createState() => _CustomerShellState();
}

class _CustomerShellState extends State<CustomerShell> {
  int _currentIndex = 0;
  late final PageController _pageController;

  /// Tab names for the perf marks — index-matched to the pages in [build].
  static const List<String> _tabLabels = [
    'Home',
    'Stores',
    'Notifications',
    'Profile',
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _showUpdateOverlay(UpdateInfo update) {
    final provider = context.read<UpdateProvider>();
    provider.markUpdateOverlayShown();
    UpdateOverlay.show(context, update: update);
  }

  /// The four tabs for the current session.
  ///
  /// Built in `build` (not stored) so a sign-in that flips [CustomerShell.guest]
  /// mounts the real Notifications/Profile pages in place of the prompts.
  List<Widget> _buildScreens() {
    if (!widget.guest) {
      return [
        const CustomerHomeScreen(hideAppBar: true),
        const StoreScreen(hideAppBar: true),
        const NotificationsScreen(hideAppBar: true),
        const ProfileScreen(hideAppBar: true, tabIndex: 3),
      ];
    }

    void browse() => _pageController.jumpToPage(0);

    return [
      const CustomerHomeScreen(hideAppBar: true),
      const StoreScreen(hideAppBar: true),
      _GuestAccountTab(
        icon: Icons.notifications_none_rounded,
        title: 'Sign in to see notifications',
        message:
            'Order updates, replies from stores and offers land here once you '
            'have an account.',
        onBrowse: browse,
      ),
      _GuestAccountTab(
        icon: Icons.person_outline_rounded,
        title: 'Sign in to your profile',
        message:
            'Your orders, addresses and saved shoe size live in your account. '
            'Create one when you are ready — browsing stays open.',
        onBrowse: browse,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> screens = _buildScreens();

    // Listen for late-arriving update checks (e.g. slow network).
    // When the provider finishes checking and finds an update, show
    // the overlay once.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = context.read<UpdateProvider>();
      if (provider.shouldShowUpdateOverlay) {
        _showUpdateOverlay(provider.latestUpdate!);
      }
    });

    // A stray back press on a root tab must warn first, not kill the app.
    return DoubleBackToExit(
      child: Scaffold(
        backgroundColor: AppConstants.surfaceLight,
        appBar: _buildAppBar(),
        // The bar gets out of the way while a feed is scrolled and returns on
        // the drag back up, so a page can be read on a full screen. It wraps the
        // body as well as the bar because the only honest source for "the page is
        // moving" is the scroll notifications from inside it; `resetOn` is the
        // active tab, so a switch never leaves a hidden bar behind.
        body: HideOnScrollBottomBar(
          resetOn: _currentIndex,
          bar: Consumer<NotificationProvider>(
            builder: (context, notifProvider, _) {
              return SoleBottomNav(
                role: AppConstants.roleCustomer,
                currentIndex: _currentIndex,
                onTap: (index) {
                  PerfTrace.mark('tab:${_tabLabels[index]} tapped');
                  _pageController.jumpToPage(index);
                },
                // Nothing can be unread for a guest, and the badge must never
                // suggest there is an account to read it from.
                notificationUnreadCount: widget.guest
                    ? 0
                    : notifProvider.totalUnread,
              );
            },
          ),
          child: screens.isEmpty
              ? const Center(child: Text('Unable to load screen'))
              // Same host contract as the seller shell: publish the visible tab
              // and keep each visited page mounted (see ActiveTab / KeepAlivePage),
              // instead of letting the PageView dispose it and re-run initState.
              : ActiveTab(
                  index: _currentIndex,
                  child: PageView(
                    controller: _pageController,
                    physics: const PageScrollPhysics(),
                    onPageChanged: (index) {
                      setState(() => _currentIndex = index);
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        PerfTrace.mark('tab:${_tabLabels[index]} presented');
                      });
                    },
                    children: [
                      for (final screen in screens)
                        KeepAlivePage(child: screen),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  // ─── SHARED APP BAR ─────────────────────────────────────────────
  PreferredSizeWidget? _buildAppBar() {
    switch (_currentIndex) {
      case 0: // Home — no AppBar (full-bleed hero design)
        return null;
      case 1: // Store
        return AppBar(
          title: Text(
            'Stores',
            style: AppConstants.headlineStyle(fontSize: 22),
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
          automaticallyImplyLeading: false,
          actions: const [CartIconButton()],
        );
      case 2: // Notifications
        return AppBar(
          title: Text(
            'Notifications',
            style: AppConstants.headlineStyle(fontSize: 20),
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
          automaticallyImplyLeading: false,
          actions: [
            if (!widget.guest &&
                context.watch<NotificationProvider>().totalUnread > 0)
              TextButton(
                onPressed: () =>
                    context.read<NotificationProvider>().markAllAsRead(),
                child: Text(
                  'Mark all read',
                  style: AppConstants.bodyStyle(
                    fontSize: 13,
                    color: AppConstants.primary,
                  ),
                ),
              ),
          ],
        );
      case 3: // Profile
        return AppBar(
          title: Text(
            'My Profile',
            style: AppConstants.bodyStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppConstants.secondary,
            ),
          ),
          backgroundColor: AppConstants.surfaceLight,
          elevation: 0,
          automaticallyImplyLeading: false,
          // Settings is an account surface too — a guest has nothing to set.
          actions: [
            if (!widget.guest)
              IconButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  );
                },
                tooltip: 'Settings',
                icon: Icon(
                  Icons.settings_outlined,
                  color: AppConstants.secondary,
                ),
              ),
          ],
        );
      default:
        return null;
    }
  }
}

/// What Notifications and Profile show a signed-out shopper.
///
/// The account tabs stay tappable — they are where a shopper looks for their
/// account — and this page is the honest answer: here is what signing in gives
/// you, here is the button, and browsing stays one tap away.
class _GuestAccountTab extends StatelessWidget {
  const _GuestAccountTab({
    required this.icon,
    required this.title,
    required this.message,
    required this.onBrowse,
  });

  final IconData icon;
  final String title;
  final String message;
  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        AppConstants.noiseOverlay(opacity: 0.03),
        SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      color: AppConstants.primary.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: 40, color: AppConstants.primary),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: AppConstants.headlineStyle(fontSize: 21),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: AppConstants.bodyStyle(
                      fontSize: 13,
                      color: AppConstants.secondary.withValues(alpha: 0.6),
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 26),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton(
                      onPressed: () => openSignIn(context),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppConstants.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: AppConstants.buttonRadius,
                        ),
                      ),
                      child: Text(
                        'Sign in or create account',
                        style: AppConstants.bodyStyle(
                          fontWeight: FontWeight.bold,
                          color: AppConstants.inkInverse,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  TextButton(
                    onPressed: onBrowse,
                    child: Text(
                      'Keep browsing',
                      style: AppConstants.bodyStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppConstants.secondary.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
