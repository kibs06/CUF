import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../constants/app_constants.dart';
import '../../providers/auth_provider.dart';
import '../../providers/follow_provider.dart';
import '../../providers/order_provider.dart';
import '../../utils/notification_formatters.dart';
import '../../utils/recently_viewed.dart';
import '../../widgets/buy_again_section.dart';
import '../../widgets/recently_viewed_section.dart';
import 'following_list_dialog.dart';
import '../../services/auth_service.dart';
import '../../services/profile_service.dart';
import '../../services/store_service.dart';
import '../../providers/update_provider.dart';
import '../../widgets/sole_badge.dart';
import '../../widgets/sole_card.dart';
import '../../widgets/sole_status_chip.dart';
import '../../widgets/sole_switch.dart';
import '../customer/my_orders_screen.dart';
import '../seller/create_store_screen.dart';
import '../seller/store_profile_screen.dart';
import '../seller/gcash_payment_settings_screen.dart';
import 'help_menu_screen.dart';
import 'whats_new_screen.dart';
import 'settings_screen.dart';
import '../auth/seller_application_flow.dart';
import '../seller/seller_business_verification_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  // ── Edit state ────────────────────────────────────────────────
  bool _isEditing = false;
  bool _isSaving = false;
  bool _isUploadingAvatar = false;
  String? _loadedProfileId;

  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;

  // ── Seller state ──────────────────────────────────────────────
  Future<Map<String, dynamic>?>? _sellerStoreFuture;
  Map<String, dynamic>? _sellerStore;
  bool _isTogglingStore = false;

  /// Tier 2 business-verification status ('none' | 'pending' | 'verified'
  /// | 'rejected'), resolved per profile from seller_business_docs.
  /// Refreshed on tab re-entry (TTL) and when returning from the Tier 2
  /// screen, so the pill never shows a stale pre-submit status.
  Future<String>? _businessVerificationFuture;
  DateTime? _businessFetchedAt;

  /// Tracks when the customer's orders were last requested so the
  /// "My Orders" panel and "Buy Again" strip refresh on tab re-entry
  /// without hammering the DB on every build.
  DateTime? _ordersLastRequestedAt;

  // ── Recently viewed (customers) ────────────────────────────────
  List<Map<String, dynamic>> _recentlyViewed = [];
  bool _loadingRecentlyViewed = false;
  DateTime? _recentlyViewedLoadedAt;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _phoneController = TextEditingController();
    _loadRecentlyViewed();
  }

  Future<void> _loadRecentlyViewed() async {
    if (_loadingRecentlyViewed) return;
    _loadingRecentlyViewed = true;
    final items = await RecentlyViewedService.instance.load();
    _loadingRecentlyViewed = false;
    _recentlyViewedLoadedAt = DateTime.now();
    if (mounted) {
      setState(() => _recentlyViewed = items);
    }
  }

  Future<void> _loadMyOrders() async {
    await context.read<OrderProvider>().loadMyOrders();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  // ── Sync controllers when auth profile changes ────────────────
  void _syncControllers(AuthProvider auth) {
    final profileId = auth.profile?['id']?.toString();
    if (_loadedProfileId == profileId) return;

    _loadedProfileId = profileId;
    _nameController.text = auth.displayName;
    _phoneController.text = auth.displayPhone;

    if (auth.userRole == AppConstants.roleSeller) {
      _sellerStoreFuture = StoreService.instance.getMyStore().then((store) {
        if (mounted) {
          setState(() => _sellerStore = store);
        }
        return store;
      });
      // profileId is non-null here: if the profile were missing, the
      // `_loadedProfileId == profileId` guard above would have returned.
      _businessVerificationFuture = AuthService.instance
          .fetchBusinessVerification(profileId!)
          .then((row) =>
              row?['verification_status']?.toString() ?? AppConstants.bizStatusNone);
      _businessFetchedAt = DateTime.now();
    } else {
      _sellerStoreFuture = null;
      _businessVerificationFuture = null;
      _businessFetchedAt = null;
    }
  }

  /// Re-fetches the Tier 2 status pill. Called post-frame (so setState is
  /// safe) when the tab is re-entered after a TTL, or when the seller
  /// returns from the SellerBusinessVerificationScreen.
  void _refreshBusinessStatus() {
    final profileId = context.read<AuthProvider>().profile?['id']?.toString();
    if (profileId == null) return;
    _businessVerificationFuture = AuthService.instance
        .fetchBusinessVerification(profileId)
        .then((row) =>
            row?['verification_status']?.toString() ?? AppConstants.bizStatusNone);
    _businessFetchedAt = DateTime.now();
    if (mounted) setState(() {});
  }

  // ── Store Open/Closed toggle ─────────────────────────────────
  Future<void> _toggleStoreOpen() async {
    if (_sellerStore == null || _isTogglingStore) return;
    final storeId = _sellerStore!['id']?.toString();
    if (storeId == null) return;

    final currentOpen = _sellerStore!['is_open'] ?? true;
    final newOpen = !currentOpen;

    setState(() => _isTogglingStore = true);

    try {
      await StoreService.instance.toggleStoreOpen(storeId, newOpen);
      if (mounted) {
        setState(() {
          _sellerStore!['is_open'] = newOpen;
          _isTogglingStore = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(newOpen ? 'Store is now open' : 'Store is now closed'),
            backgroundColor: AppConstants.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isTogglingStore = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString().replaceAll('Exception: ', '')}'),
            backgroundColor: AppConstants.error,
          ),
        );
      }
    }
  }

  // ── Edit toggle ───────────────────────────────────────────────
  void _toggleEdit(AuthProvider auth) {
    setState(() {
      if (_isEditing) {
        // Cancel: revert to current values
        _nameController.text = auth.displayName;
        _phoneController.text = auth.displayPhone;
      }
      _isEditing = !_isEditing;
    });
  }

  // ── Save profile ──────────────────────────────────────────────
  Future<void> _handleSave(AuthProvider auth) async {
    setState(() => _isSaving = true);
    final success = await auth.updateProfile(
      fullName: _nameController.text.trim(),
      phone: _phoneController.text.trim().isEmpty
          ? null
          : _phoneController.text.trim(),
    );

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (_isEditing) {
      setState(() => _isEditing = false);
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success ? 'Profile updated' : auth.errorMessage ?? 'Failed to update profile.'),
        backgroundColor: success ? AppConstants.success : AppConstants.error,
      ),
    );
  }

  // ── Avatar upload ─────────────────────────────────────────────
  Future<void> _uploadAvatar(AuthProvider auth) async {
    final userId = auth.currentUser?['id']?.toString();
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please log in again before updating your photo.'),
          backgroundColor: AppConstants.error,
        ),
      );
      return;
    }

    try {
      final picked = await ProfileService.instance.pickAvatarImage();
      if (picked == null) return;

      setState(() => _isUploadingAvatar = true);
      final avatarUrl = await ProfileService.instance.uploadAvatar(
        userId: userId,
        filePath: picked.path,
      );
      final success = await auth.updateProfile(
        fullName: _nameController.text.trim().isEmpty
            ? auth.displayName
            : _nameController.text.trim(),
        phone: _phoneController.text.trim().isEmpty
            ? null
            : _phoneController.text.trim(),
        newAvatarUrl: avatarUrl,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? 'Profile photo updated'
                : auth.errorMessage ?? 'Unable to update profile photo.',
          ),
          backgroundColor: success ? AppConstants.success : AppConstants.error,
        ),
      );
    } catch (e) {
      debugPrint('[ProfileScreen] Avatar upload failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Photo upload failed — please try again.'),
          backgroundColor: AppConstants.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isUploadingAvatar = false);
    }
  }

  // ════════════════════════════════════════════════════════════════
  // BUILD
  // ════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    _syncControllers(auth);

    // Keep the Tier 2 status pill fresh when the seller tab is re-entered
    // (the screen lives in an IndexedStack, so re-entry re-runs build but
    // not _syncControllers).
    if (auth.userRole == AppConstants.roleSeller &&
        _businessFetchedAt != null &&
        DateTime.now().difference(_businessFetchedAt!) >
            const Duration(seconds: 30)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _refreshBusinessStatus();
      });
    }

    // Refresh recently viewed when the profile tab is re-entered (same
    // IndexedStack constraint — initState runs once, so re-entry re-runs
    // build; a TTL keeps the strip fresh without reloading every frame).
    if (auth.userRole == AppConstants.roleCustomer &&
        (_recentlyViewedLoadedAt == null ||
            DateTime.now().difference(_recentlyViewedLoadedAt!) >
                const Duration(seconds: 5))) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadRecentlyViewed();
      });
    }

    // Refresh the customer's orders on tab re-entry — powers the My Orders
    // badge counts and the Buy Again strip, so a new purchase shows up
    // without visiting the My Orders screen first.
    if (auth.userRole != AppConstants.roleSeller &&
        (_ordersLastRequestedAt == null ||
            DateTime.now().difference(_ordersLastRequestedAt!) >
                const Duration(seconds: 30))) {
      _ordersLastRequestedAt = DateTime.now();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<OrderProvider>().loadMyOrders();
      });
    }

    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      appBar: AppBar(
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
        actions: [
          IconButton(
            // Sellers: the gear opens Payment Methods (GCash QR setup) — the
            // most-used settings action. Other roles get the placeholder.
            onPressed: () {
              if (auth.userRole == AppConstants.roleSeller) {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const GcashPaymentSettingsScreen(),
                  ),
                );
              } else {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const SettingsScreen(),
                  ),
                );
              }
            },
            tooltip: auth.userRole == AppConstants.roleSeller
                ? 'Payment Methods'
                : 'Settings',
            icon: const Icon(
              Icons.settings_outlined,
              color: AppConstants.secondary,
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          AppConstants.noiseOverlay(opacity: 0.03),
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(auth),
                const SizedBox(height: 8),
                _buildEditPanel(auth),
                const Divider(height: 32),
                if (auth.userRole == AppConstants.roleSeller) ...[
                  _buildSellerSection(auth),
                  const SizedBox(height: 16),
                ],
                if (auth.userRole != AppConstants.roleSeller) ...[
                  if (auth.sellerStatus == AppConstants.statusRejected) ...[
                    _buildRejectedBanner(auth),
                    const SizedBox(height: 16),
                  ],
                  _buildNotificationsPanel(),
                  const SizedBox(height: 16),
                ],
                if (auth.userRole == AppConstants.roleCustomer) ...[
                  BuyAgainSection(
                    orders: context.watch<OrderProvider>().allMyOrders,
                    onProductOpened: _loadMyOrders,
                  ),
                  const SizedBox(height: 16),
                  RecentlyViewedSection(
                    items: _recentlyViewed,
                    onProductOpened: _loadRecentlyViewed,
                  ),
                  const SizedBox(height: 16),
                ],
                _buildSettingsCard(auth),
                const SizedBox(height: 24),
                // Support and Updates section
                Text(
                  'SUPPORT & UPDATES',
                  style: AppConstants.bodyStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade500,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 8),
                SoleCard(
                  color: Colors.white,
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      _settingsRow(
                        icon: Icons.headset_mic_outlined,
                        title: 'Help & Support',
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const HelpMenuScreen(),
                            ),
                          );
                        },
                      ),
                      const Divider(height: 1, color: Color(0xFFE5E7EB)),
                      _settingsRow(
                        icon: Icons.new_releases_outlined,
                        title: "What's New",
                        subtitle: context.watch<UpdateProvider>().installedVersion != null
                            ? 'v${context.watch<UpdateProvider>().installedVersion}'
                            : null,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const WhatsNewScreen(),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  // HEADER — avatar + name + edit icon + role badge
  // ════════════════════════════════════════════════════════════════
  Widget _buildHeader(AuthProvider auth) {
    final roleColor = _roleColor(auth.userRole);

    return Column(
      children: [
        // ── Avatar with camera overlay ───────────────────────────
        Stack(
          clipBehavior: Clip.none,
          children: [
            CircleAvatar(
              radius: 44,
              backgroundColor: AppConstants.primary.withValues(alpha: 0.12),
              backgroundImage:
                  auth.avatarUrl != null ? NetworkImage(auth.avatarUrl!) : null,
              child: _isUploadingAvatar
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppConstants.primary,
                      ),
                    )
                  : auth.avatarUrl == null
                      ? Text(
                          _initials(auth.displayName),
                          style: AppConstants.headlineStyle(
                            fontSize: 28,
                            color: AppConstants.primary,
                          ),
                        )
                      : null,
            ),
            Positioned(
              right: -2,
              bottom: -2,
              child: GestureDetector(
                onTap: _isUploadingAvatar ? null : () => _uploadAvatar(auth),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppConstants.primary,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppConstants.surfaceLight,
                      width: 2.0,
                    ),
                  ),
                  child: const Icon(
                    Icons.camera_alt,
                    size: 14,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // ── Name + edit toggle icon ──────────────────────────────
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              auth.displayName,
              style: AppConstants.headlineStyle(fontSize: 22),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () => _toggleEdit(auth),
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppConstants.borderGray),
                ),
                child: Icon(
                  _isEditing ? Icons.close : Icons.edit_outlined,
                  size: 14,
                  color: AppConstants.secondary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          auth.displayEmail,
          style: AppConstants.bodyStyle(
            fontSize: 13,
            color: Colors.grey.shade500,
          ),
        ),
        const SizedBox(height: 10),
        SoleBadge(
          label: _roleLabel(auth.userRole),
          backgroundColor: roleColor.withValues(alpha: 0.14),
          textColor: roleColor,
        ),
        const SizedBox(height: 12),
        if (auth.userRole != AppConstants.roleSeller)
          _buildFollowingStat(auth),
      ],
    );
  }

  // ════════════════════════════════════════════════════════════════
  // COLLAPSIBLE EDIT PANEL
  // ════════════════════════════════════════════════════════════════
  Widget _buildEditPanel(AuthProvider auth) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
      child: !_isEditing
          ? const SizedBox(width: double.infinity, height: 0)
          : Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),                  border: Border.all(color: AppConstants.borderGray.withValues(alpha: 0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Full name ─────────────────────────────────
                  _fieldLabel('Full Name'),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _nameController,
                    textInputAction: TextInputAction.next,
                    style: AppConstants.bodyStyle(fontSize: 14),
                    decoration: _inputDecoration('Enter your full name'),
                  ),
                  const SizedBox(height: 14),

                  // ── Email (locked) ────────────────────────────
                  _fieldLabel('Email'),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            auth.displayEmail,
                            style: AppConstants.bodyStyle(fontSize: 14),
                          ),
                        ),
                        Icon(Icons.lock_outline, size: 16, color: Colors.grey.shade500),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // ── Phone ─────────────────────────────────────
                  _fieldLabel('Phone Number'),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.done,
                    style: AppConstants.bodyStyle(fontSize: 14),
                    decoration: _inputDecoration('e.g. 09XX-XXX-XXXX'),
                  ),
                  const SizedBox(height: 16),

                  // ── Save button ───────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppConstants.primary,
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _isSaving ? null : () => _handleSave(auth),
                      child: _isSaving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              'Save Changes',
                              style: AppConstants.bodyStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  // REJECTED SELLER BANNER — surface the reason + let them re-apply
  // ════════════════════════════════════════════════════════════════
  Widget _buildRejectedBanner(AuthProvider auth) {
    final reason = auth.profile?['rejection_reason']?.toString() ?? '';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppConstants.error.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppConstants.error.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.error_outline_rounded,
                size: 20,
                color: AppConstants.error,
              ),
              const SizedBox(width: 8),
              Text(
                'Seller application not approved',
                style: AppConstants.bodyStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppConstants.error,
                ),
              ),
            ],
          ),
          if (reason.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              reason,
              style: AppConstants.bodyStyle(
                fontSize: 12,
                color: AppConstants.secondary.withValues(alpha: 0.75),
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: FilledButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        SellerApplicationFlow(prefillProfile: auth.profile),
                  ),
                );
              },
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Re-apply as a seller'),
              style: FilledButton.styleFrom(
                backgroundColor: AppConstants.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  // TIER 2 BUSINESS VERIFICATION STATUS PILL (async, resolved once)
  // ════════════════════════════════════════════════════════════════
  Widget _buildBusinessStatusChip() {
    return FutureBuilder<String>(
      future: _businessVerificationFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.only(right: 6),
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppConstants.primary,
              ),
            ),
          );
        }
        final status = snapshot.data ?? AppConstants.bizStatusNone;
        final (bg, fg, label) = switch (status) {
          AppConstants.bizStatusVerified => (
              AppConstants.success.withValues(alpha: 0.15),
              AppConstants.success,
              'Verified',
            ),
          AppConstants.bizStatusPending => (
              Colors.amber.withValues(alpha: 0.2),
              const Color(0xFFB45309),
              'Pending',
            ),
          AppConstants.bizStatusRejected => (
              AppConstants.error.withValues(alpha: 0.15),
              AppConstants.error,
              'Rejected',
            ),
          _ => (
              AppConstants.secondary.withValues(alpha: 0.08),
              AppConstants.secondary.withValues(alpha: 0.6),
              'Optional',
            ),
        };
        return Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              label,
              style: AppConstants.monoStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: fg,
              ),
            ),
          ),
        );
      },
    );
  }

  // ════════════════════════════════════════════════════════════════
  // NOTIFICATIONS PANEL
  // ════════════════════════════════════════════════════════════════
  Widget _buildNotificationsPanel() {
    // Badge counts come from the customer's REAL orders — computed with the
    // same predicates as the My Orders tabs — so they always match the tabs
    // (previously they were unread-notification counts and drifted).
    final orderProvider = context.watch<OrderProvider>();

    // Orders are loaded once per screen lifetime by the build-level TTL
    // refresh below (keeps My Orders badge counts + the Buy Again strip
    // fresh), so this panel has no load of its own.

    final counts = orderProvider.myOrdersCounts;

    final items = <_NotifItem>[
      _NotifItem(Icons.credit_card_outlined, 'Unpaid', 'unpaid'),
      _NotifItem(Icons.inventory_2_outlined, 'Processing', 'processing'),
      _NotifItem(Icons.local_shipping_outlined, 'Shipped', 'shipped'),
      _NotifItem(Icons.chat_bubble_outline, 'Review', 'review'),
      _NotifItem(Icons.assignment_return_outlined, 'Returns', 'returns'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'My Orders',
              style: AppConstants.bodyStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const MyOrdersScreen(),
                  ),
                );
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'View all',
                    style: AppConstants.bodyStyle(
                      fontSize: 13,
                      color: AppConstants.primary,
                    ),
                  ),
                  const Icon(Icons.chevron_right, size: 16, color: AppConstants.primary),
                ],
              ),
            ),
          ],
        ),
        SoleCard(
          color: Colors.white,
          padding: EdgeInsets.zero,
          margin: EdgeInsets.zero,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: items.map((item) {
              final count = counts[item.filter] ?? 0;
              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => MyOrdersScreen(
                          initialFilter: item.filter,
                        ),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Column(
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Icon(
                              item.icon,
                              size: 24,
                              color: AppConstants.primary,
                            ),
                            if (count > 0)
                              Positioned(
                                top: -8,
                                right: -10,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  constraints: const BoxConstraints(
                                    minWidth: 20,
                                    minHeight: 20,
                                  ),
                                  decoration: const BoxDecoration(
                                    color: AppConstants.error,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Text(
                                    formatBadgeCount(count),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      height: 1.2,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          item.label,
                          style: AppConstants.bodyStyle(
                            fontSize: 11,
                            color: AppConstants.secondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  // ════════════════════════════════════════════════════════════════
  // SETTINGS CARD
  // ════════════════════════════════════════════════════════════════
  Widget _buildSettingsCard(AuthProvider auth) {
    return SoleCard(
      color: Colors.white,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          // Sellers set up their GCash static QR here (shown at POS checkout).
          if (auth.userRole == AppConstants.roleSeller) ...[
            _settingsRow(
              icon: Icons.qr_code_2,
              title: 'Payment Methods',
              subtitle: 'Set up your GCash QR code',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const GcashPaymentSettingsScreen(),
                  ),
                );
              },
            ),
            const Divider(height: 1, color: Color(0xFFE5E7EB)),
            // Tier 2 — optional business verification (never gates selling).
            _settingsRow(
              icon: Icons.business_center_outlined,
              title: 'Business Verification',
              subtitle: 'Optional: DTI, BIR COR & permits',
              trailing: _buildBusinessStatusChip(),
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const SellerBusinessVerificationScreen(),
                  ),
                );
                if (mounted) _refreshBusinessStatus();
              },
            ),
          ],
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  // SELLER SECTION
  // ════════════════════════════════════════════════════════════════
  Widget _buildSellerSection(AuthProvider auth) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('Seller Info'),
        const SizedBox(height: 8),
        SoleCard(
          color: Colors.white,
          padding: EdgeInsets.zero,
          child: FutureBuilder<Map<String, dynamic>?>(
            future: _sellerStoreFuture,
            builder: (context, snapshot) {
              final store = snapshot.data;
              final storeName = _storeName(store);
              return Column(
                children: [
                  Material(
                    color: Colors.transparent,
                    child: ListTile(
                    dense: true,
                    title: Text(
                      'Store',
                      style: AppConstants.bodyStyle(fontSize: 14),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (storeName != null) ...[
                          // Open/Closed pill
                          Builder(
                            builder: (context) {
                              final isOpen = _sellerStore?['is_open'] ?? store?['is_open'] ?? true;
                              return AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeInOut,
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: isOpen
                                      ? AppConstants.success.withValues(alpha: 0.12)
                                      : AppConstants.error.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: AnimatedDefaultTextStyle(
                                  duration: const Duration(milliseconds: 300),
                                  style: AppConstants.bodyStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: isOpen
                                        ? AppConstants.success
                                        : AppConstants.error,
                                  ),
                                  child: Text(isOpen ? 'Open' : 'Closed'),
                                ),
                              );
                            },
                          ),
                          const SizedBox(width: 8),
                          // Open/Closed toggle
                          SizedBox(
                            height: 24,
                            child: Switch(
                              value: _sellerStore?['is_open'] ?? store?['is_open'] ?? true,
                              onChanged: _isTogglingStore
                                  ? null
                                  : (_) => _toggleStoreOpen(),
                              activeThumbColor: SoleSwitch.thumbColor,
                              inactiveTrackColor: SoleSwitch.offColor,
                              inactiveThumbColor: SoleSwitch.thumbColor,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                          const SizedBox(width: 4),
                        ],
                        if (storeName == null)
                          Text(
                            'No store linked',
                            style: AppConstants.bodyStyle(
                              fontSize: 13,
                              color: AppConstants.error,
                            ),
                          ),
                      ],
                    ),
                    onTap: () {
                      if (store != null) {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => StoreProfileScreen(store: store),
                          ),
                        );
                      } else {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const CreateStoreScreen(),
                          ),
                        );
                      }
                    },
                  ),
                  ),
                  const Divider(height: 1, color: Color(0xFFE5E7EB)),
                  Material(
                    color: Colors.transparent,
                    child: ListTile(
                    dense: true,
                    title: Text(
                      'Seller Status',
                      style: AppConstants.bodyStyle(fontSize: 14),
                    ),
                    trailing: SoleStatusChip(status: auth.sellerStatus),
                  ),
                  ),
                  const Divider(height: 1, color: Color(0xFFE5E7EB)),
                  Material(
                    color: Colors.transparent,
                    child: ListTile(
                    dense: true,
                    title: Text(
                      'Member Since',
                      style: AppConstants.bodyStyle(fontSize: 14),
                    ),
                    trailing: Text(
                      _formatMemberSince(auth.profile?['created_at']),
                      style: AppConstants.bodyStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  // ════════════════════════════════════════════════════════════════
  // HELPERS
  // ════════════════════════════════════════════════════════════════
  // ════════════════════════════════════════════════════════════════
  // FOLLOWING STAT (lightweight inline style)
  // ════════════════════════════════════════════════════════════════
  Widget _buildFollowingStat(AuthProvider auth) {
    final followProvider = context.watch<FollowProvider>();
    final count = followProvider.followingCount;
    final isLoaded = followProvider.isLoaded;

    return Semantics(
      label: isLoaded ? 'Following, $count, opens list of followed stores' : 'Loading following count',
      button: true,
      child: GestureDetector(
        onTap: () {
          showDialog(
            context: context,
            builder: (_) => const FollowingListDialog(),
          );
        },
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: isLoaded
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Shop/storefront icon
                    Icon(
                      Icons.storefront_outlined,
                      size: 18,
                      color: AppConstants.primary,
                    ),
                    const SizedBox(width: 6),
                    // Count (bold) + label (regular)
                    Text(
                      '$count ',
                      style: AppConstants.bodyStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppConstants.secondary,
                      ),
                    ),
                    Text(
                      'Following',
                      style: AppConstants.bodyStyle(
                        fontSize: 15,
                        color: AppConstants.secondary,
                      ),
                    ),
                    const SizedBox(width: 4),
                    // Chevron
                    Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: AppConstants.secondary.withValues(alpha: 0.4),
                    ),
                  ],
                )
              : const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppConstants.primary,
                  ),
                ),
        ),
      ),
    );
  }

  String _initials(String fullName) {
    final parts = fullName
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  String _roleLabel(String role) {
    switch (role) {
      case AppConstants.roleSeller:
        return 'Seller';
      case AppConstants.roleAdmin:
        return 'Admin';
      default:
        return 'Customer';
    }
  }

  Color _roleColor(String role) {
    switch (role) {
      case AppConstants.roleSeller:
        return AppConstants.accent;
      case AppConstants.roleAdmin:
        return AppConstants.error;
      default:
        return AppConstants.statusPendingColor;
    }
  }

  String? _storeName(Map<String, dynamic>? store) {
    if (store == null) return null;
    return store['name']?.toString();
  }

  String _formatMemberSince(dynamic value) {
    final date = value is DateTime
        ? value
        : DateTime.tryParse(value?.toString() ?? '');
    if (date == null) return 'Unknown';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[date.month - 1]} ${date.year}';
  }

  Widget _settingsRow({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    String? subtitle,
    Widget? trailing,
  }) {
    return Material(
      color: Colors.transparent,
      child: ListTile(
        dense: subtitle == null,
        leading: Icon(icon, color: AppConstants.primary, size: 22),
        title: Text(title, style: AppConstants.bodyStyle(fontSize: 14)),
        subtitle: subtitle == null
            ? null
            : Text(
                subtitle,
                style: AppConstants.bodyStyle(
                  fontSize: 12,
                  color: AppConstants.secondary.withValues(alpha: 0.5),
                ),
              ),
        trailing: trailing ??
            const Icon(Icons.chevron_right, color: AppConstants.borderGray),
        onTap: onTap,
      ),
    );
  }

  Widget _fieldLabel(String label) {
    return Text(
      label.toUpperCase(),
      style: AppConstants.bodyStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: Colors.grey.shade500,
        letterSpacing: 0.8,
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: AppConstants.bodyStyle(
        fontSize: 14,
        color: Colors.grey.shade400,
      ),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppConstants.primary),
      ),
    );
  }


}

// ══════════════════════════════════════════════════════════════════
// Private helpers
// ══════════════════════════════════════════════════════════════════
class _NotifItem {
  final IconData icon;
  final String label;
  final String filter;
  const _NotifItem(this.icon, this.label, this.filter);
}
