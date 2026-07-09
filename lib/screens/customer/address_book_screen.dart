import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../constants/app_constants.dart';
import '../../models/address_model.dart';
import '../../providers/address_provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/shimmer_box.dart';
import '../../widgets/sole_card.dart';
import 'add_edit_address_screen.dart';

/// Customer Address Book screen.
///
/// Shows saved delivery addresses with options to add, edit, delete,
/// and set default. Also supports a selection mode for checkout.
class AddressBookScreen extends StatefulWidget {
  /// When true, tapping an address selects it and pops with the result.
  final bool selectionMode;

  const AddressBookScreen({super.key, this.selectionMode = false});

  @override
  State<AddressBookScreen> createState() => _AddressBookScreenState();
}

class _AddressBookScreenState extends State<AddressBookScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      final userId = auth.profile?['id'] ?? auth.currentUser?['id'];
      if (userId != null) {
        context.read<AddressProvider>().loadAddresses(userId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      appBar: AppBar(
        title: Text(
          widget.selectionMode ? 'Select Address' : 'My Addresses',
          style: AppConstants.headlineStyle(fontSize: 20),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppConstants.secondary),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Stack(
        children: [
          AppConstants.noiseOverlay(opacity: 0.03),
          Consumer<AddressProvider>(
            builder: (context, provider, _) {
              if (provider.isLoading) return _buildLoading();
              if (provider.addresses.isEmpty) return _buildEmptyState();
              return _buildAddressList(provider);
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _navigateToAdd(),
        backgroundColor: AppConstants.primary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: Text(
          'Add New Address',
          style: AppConstants.bodyStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      itemCount: 3,
      itemBuilder: (context, index) {
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          child: SoleCard(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const ShimmerBox(width: 50, height: 14),
                    const SizedBox(width: 8),
                    const ShimmerBox(width: 40, height: 14),
                  ],
                ),
                const SizedBox(height: 10),
                const ShimmerBox(width: 120, height: 12),
                const SizedBox(height: 6),
                const ShimmerBox(width: double.infinity, height: 12),
                const SizedBox(height: 6),
                const ShimmerBox(width: 200, height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: EmptyStateWidget(
          icon: Icons.location_off_outlined,
          title: 'No addresses yet',
          subtitle: 'Add a delivery address to get started.',
        ),
      ),
    );
  }

  Widget _buildAddressList(AddressProvider provider) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      itemCount: provider.addresses.length,
      itemBuilder: (context, index) {
        final address = provider.addresses[index];
        return _AddressCard(
          address: address,
          isSelection: widget.selectionMode,
          isSelected: provider.selectedAddress?.id == address.id,
          onTap: widget.selectionMode
              ? () {
                  provider.setSelectedAddress(address);
                  Navigator.of(context).pop(address);
                }
              : null,
          onEdit: widget.selectionMode
              ? null
              : () => _navigateToEdit(address),
          onDelete: widget.selectionMode
              ? null
              : () => _deleteAddress(address, provider),
          onSetDefault: widget.selectionMode
              ? null
              : () => _setDefault(address, provider),
        );
      },
    );
  }

  Future<void> _navigateToAdd() async {
    final result = await Navigator.of(context).push<Address>(
      MaterialPageRoute(builder: (_) => const AddEditAddressScreen()),
    );
    if (result != null && mounted) {
      final auth = context.read<AuthProvider>();
      final userId = auth.profile?['id'] ?? auth.currentUser?['id'];
      if (userId != null) {
        context.read<AddressProvider>().loadAddresses(userId);
      }
    }
  }

  Future<void> _navigateToEdit(Address address) async {
    final result = await Navigator.of(context).push<Address>(
      MaterialPageRoute(
        builder: (_) => AddEditAddressScreen(existingAddress: address),
      ),
    );
    if (result != null && mounted) {
      final auth = context.read<AuthProvider>();
      final userId = auth.profile?['id'] ?? auth.currentUser?['id'];
      if (userId != null) {
        context.read<AddressProvider>().loadAddresses(userId);
      }
    }
  }

  Future<void> _deleteAddress(
    Address address,
    AddressProvider provider,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Address'),
        content: Text(
          'Remove "${address.label}" address for ${address.recipientName}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppConstants.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      try {
        await provider.deleteAddress(address.id!);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Address deleted.'),
              backgroundColor: AppConstants.success,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to delete: $e'),
              backgroundColor: AppConstants.error,
            ),
          );
        }
      }
    }
  }

  Future<void> _setDefault(
    Address address,
    AddressProvider provider,
  ) async {
    final auth = context.read<AuthProvider>();
    final userId = auth.profile?['id'] ?? auth.currentUser?['id'];
    if (userId == null) return;
    try {
      await provider.setDefaultAddress(address.id!, userId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Default address updated.'),
            backgroundColor: AppConstants.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to set default: $e'),
            backgroundColor: AppConstants.error,
          ),
        );
      }
    }
  }
}

// ══════════════════════════════════════════════════════════════════
// Address Card
// ══════════════════════════════════════════════════════════════════

class _AddressCard extends StatelessWidget {
  final Address address;
  final bool isSelection;
  final bool isSelected;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onSetDefault;

  const _AddressCard({
    required this.address,
    this.isSelection = false,
    this.isSelected = false,
    this.onTap,
    this.onEdit,
    this.onDelete,
    this.onSetDefault,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: onTap,
        child: SoleCard(
          color: isSelected
              ? AppConstants.primary.withValues(alpha: 0.06)
              : Colors.white,
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Row 1: Label badge + Default badge + actions
              Row(
                children: [
                  _labelBadge(),
                  const SizedBox(width: 8),
                  if (address.isDefault)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppConstants.success.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Default',
                        style: AppConstants.bodyStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: AppConstants.success,
                        ),
                      ),
                    ),
                  if (isSelection)
                    const Spacer()
                  else
                    const Spacer(),
                  if (isSelection)
                    Icon(
                      isSelected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      size: 22,
                      color: isSelected
                          ? AppConstants.primary
                          : AppConstants.secondary.withValues(alpha: 0.3),
                    ),
                  if (!isSelection)
                    PopupMenuButton<String>(
                      icon: Icon(
                        Icons.more_vert,
                        size: 20,
                        color: AppConstants.secondary.withValues(alpha: 0.4),
                      ),
                      onSelected: (value) {
                        switch (value) {
                          case 'edit':
                            onEdit?.call();
                            break;
                          case 'default':
                            onSetDefault?.call();
                            break;
                          case 'delete':
                            onDelete?.call();
                            break;
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(Icons.edit_outlined, size: 18),
                              SizedBox(width: 8),
                              Text('Edit'),
                            ],
                          ),
                        ),
                        if (!address.isDefault)
                          const PopupMenuItem(
                            value: 'default',
                            child: Row(
                              children: [
                                Icon(Icons.star_outline, size: 18),
                                SizedBox(width: 8),
                                Text('Set as Default'),
                              ],
                            ),
                          ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete_outline,
                                  size: 18, color: AppConstants.error),
                              SizedBox(width: 8),
                              Text('Delete',
                                  style: TextStyle(color: AppConstants.error)),
                            ],
                          ),
                        ),
                      ],
                    ),
                ],
              ),

              const SizedBox(height: 8),

              // Row 2: Recipient name + phone
              Text(
                '${address.recipientName}  •  ${address.recipientPhone}',
                style: AppConstants.bodyStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),

              const SizedBox(height: 4),

              // Row 3: Full formatted address
              Text(
                address.formattedAddress,
                style: AppConstants.bodyStyle(
                  fontSize: 12,
                  color: AppConstants.secondary.withValues(alpha: 0.6),
                  height: 1.4,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),

              // Landmark
              if (address.landmark != null &&
                  address.landmark!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  'Landmark: ${address.landmark}',
                  style: AppConstants.bodyStyle(
                    fontSize: 11,
                    color: AppConstants.secondary.withValues(alpha: 0.4),
                  ).copyWith(fontStyle: FontStyle.italic),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _labelBadge() {
    final colors = {
      'Home': AppConstants.primary,
      'Work': AppConstants.accent,
    };
    final icons = {
      'Home': Icons.home_outlined,
      'Work': Icons.work_outline,
    };
    final color = colors[address.label] ??
        AppConstants.secondary.withValues(alpha: 0.5);
    final icon = icons[address.label] ?? Icons.location_on_outlined;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            address.label,
            style: AppConstants.bodyStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
