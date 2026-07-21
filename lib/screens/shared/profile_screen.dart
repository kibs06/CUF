import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../constants/app_constants.dart';
import '../../models/notification_category.dart';
import '../../providers/auth_provider.dart';
import '../../providers/follow_provider.dart';
import '../../providers/notification_provider.dart';
import 'following_list_dialog.dart';
import '../../services/profile_service.dart';
import '../../services/store_service.dart';
import '../../widgets/sole_badge.dart';
import '../../widgets/sole_card.dart';
import '../../widgets/sole_status_chip.dart';
import '../customer/my_orders_screen.dart';
import '../seller/create_store_screen.dart';
import '../seller/store_profile_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _phoneController = TextEditingController();
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
      _sellerStoreFuture = StoreService.instance.getMyStore();
    } else {
      _sellerStoreFuture = null;
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: AppConstants.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isUploadingAvatar = false);
    }
  }

  // ── Password reset ────────────────────────────────────────────
  Future<void> _sendReset(AuthProvider auth) async {
    final success = await auth.resetPassword(auth.displayEmail);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Password reset email sent to ${auth.displayEmail}'
              : auth.errorMessage ?? 'Unable to send reset email.',
        ),
        backgroundColor: success ? AppConstants.success : AppConstants.error,
      ),
    );
  }

  // ── Logout ────────────────────────────────────────────────────
  Future<void> _confirmLogout(AuthProvider auth) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log Out'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Log Out',
              style: TextStyle(color: AppConstants.error),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await auth.logout();
    }
  }

  // ════════════════════════════════════════════════════════════════
  // BUILD
  // ════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    _syncControllers(auth);

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
      ),
      body: Stack(
        children: [
          AppConstants.noiseOverlay(opacity: 0.03),
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 80),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(auth),
                const SizedBox(height: 8),
                _buildEditPanel(auth),
                const Divider(height: 32),
                _buildNotificationsPanel(),
                const SizedBox(height: 16),
                _buildSettingsCard(auth),
                if (auth.userRole == AppConstants.roleSeller) ...[
                  const SizedBox(height: 16),
                  _buildSellerSection(auth),
                ],
                const SizedBox(height: 32),
                _buildLogoutButton(auth),
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
  // NOTIFICATIONS PANEL
  // ════════════════════════════════════════════════════════════════
  Widget _buildNotificationsPanel() {
    final notifProvider = context.watch<NotificationProvider>();
    final counts = notifProvider.unreadCounts;

    final items = <_NotifItem>[
      _NotifItem(NotificationCategory.unpaid, Icons.credit_card_outlined, 'Unpaid', 'unpaid'),
      _NotifItem(NotificationCategory.processing, Icons.inventory_2_outlined, 'Processing', 'processing'),
      _NotifItem(NotificationCategory.shipped, Icons.local_shipping_outlined, 'Shipped', 'shipped'),
      _NotifItem(NotificationCategory.review, Icons.chat_bubble_outline, 'Review', 'review'),
      _NotifItem(NotificationCategory.returns, Icons.assignment_return_outlined, 'Returns', 'returns'),
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
              final count = counts[item.category] ?? 0;
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
                                top: -6,
                                right: -8,
                                child: Container(
                                  padding: const EdgeInsets.all(3),
                                  constraints: const BoxConstraints(
                                    minWidth: 16,
                                    minHeight: 16,
                                  ),
                                  decoration: const BoxDecoration(
                                    color: AppConstants.error,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Text(
                                    count > 9 ? '9+' : '$count',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 9,
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
          _settingsRow(
            icon: Icons.lock_outline,
            title: 'Change Password',
            onTap: () => _sendReset(auth),
          ),
          const Divider(height: 1, color: Color(0xFFE5E7EB)),
          _settingsRow(
            icon: Icons.description_outlined,
            title: 'Terms & Privacy',
            onTap: () => _openPlaceholder('Terms & Privacy'),
          ),
          const Divider(height: 1, color: Color(0xFFE5E7EB)),
          _settingsRow(
            icon: Icons.info_outline,
            title: 'About SoleVision',
            onTap: () => _openPlaceholder('About SoleVision'),
          ),
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
                        Text(
                          storeName ?? 'No store linked',
                          style: AppConstants.bodyStyle(
                            fontSize: 13,
                            color: storeName != null
                                ? AppConstants.secondary
                                : AppConstants.error,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.chevron_right,
                          color: AppConstants.borderGray,
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
  // LOGOUT
  // ════════════════════════════════════════════════════════════════
  Widget _buildLogoutButton(AuthProvider auth) {
    return OutlinedButton.icon(
      icon: const Icon(Icons.logout, color: AppConstants.error),
      label: Text(
        'Log Out',
        style: AppConstants.bodyStyle(color: AppConstants.error),
      ),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: AppConstants.error.withValues(alpha: 0.4)),
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: () => _confirmLogout(auth),
    );
  }

  // ════════════════════════════════════════════════════════════════
  // HELPERS
  // ════════════════════════════════════════════════════════════════
  // ════════════════════════════════════════════════════════════════
  // FOLLOWING STAT
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
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: AppConstants.primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppConstants.primary.withValues(alpha: 0.15),
            ),
          ),
          child: isLoaded
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$count ',
                      style: AppConstants.bodyStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppConstants.primary,
                      ),
                    ),
                    Text(
                      'Following',
                      style: AppConstants.bodyStyle(
                        fontSize: 14,
                        color: AppConstants.secondary,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: AppConstants.primary,
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
  }) {
    return Material(
      color: Colors.transparent,
      child: ListTile(
      dense: true,
      leading: Icon(icon, color: AppConstants.primary, size: 22),
      title: Text(title, style: AppConstants.bodyStyle(fontSize: 14)),
      trailing: const Icon(Icons.chevron_right, color: AppConstants.borderGray),
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

  void _openPlaceholder(String title) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: AppConstants.surfaceLight,
          appBar: AppBar(
            title: Text(
              title,
              style: AppConstants.bodyStyle(fontWeight: FontWeight.bold),
            ),
            backgroundColor: AppConstants.surfaceLight,
          ),
          body: Center(
            child: Text('Coming soon', style: AppConstants.bodyStyle()),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// Private helpers
// ══════════════════════════════════════════════════════════════════
class _NotifItem {
  final NotificationCategory category;
  final IconData icon;
  final String label;
  final String filter;
  const _NotifItem(this.category, this.icon, this.label, this.filter);
}
