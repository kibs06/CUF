import 'package:flutter/material.dart';
import '../constants/app_constants.dart';
import '../screens/customer/tracking_screen.dart';
import '../screens/seller/order_detail_screen.dart';
import '../screens/shared/support_chat_screen.dart';
import '../services/supabase_service.dart';
import 'custom_popup_menu.dart';
import 'sole_primary_button.dart';

/// Result data returned from the change request flow.
class ChangeRequestResult {
  final String type; // 'size', 'color', 'address', 'quantity', 'other'
  final String? fromValue; // Current value (optional)
  final String toValue; // Requested new value

  const ChangeRequestResult({
    required this.type,
    this.fromValue,
    required this.toValue,
  });
}

/// Predefined change request types.
class ChangeRequestType {
  final String id;
  final String label;
  final IconData icon;
  final String hint;

  const ChangeRequestType({
    required this.id,
    required this.label,
    required this.icon,
    required this.hint,
  });
}

const changeRequestTypes = [
  ChangeRequestType(
    id: 'size',
    label: 'Change Size',
    icon: Icons.straighten,
    hint: 'e.g. EU 42 → EU 43',
  ),
  ChangeRequestType(
    id: 'color',
    label: 'Change Color/Variant',
    icon: Icons.palette_outlined,
    hint: 'e.g. Burnished Clay → Saddle Brown',
  ),
  ChangeRequestType(
    id: 'address',
    label: 'Change Delivery Address',
    icon: Icons.location_on_outlined,
    hint: 'New delivery address',
  ),
  ChangeRequestType(
    id: 'quantity',
    label: 'Change Quantity',
    icon: Icons.numbers,
    hint: 'e.g. 2 → 1',
  ),
  ChangeRequestType(
    id: 'other',
    label: 'Other Request',
    icon: Icons.edit_outlined,
    hint: 'Describe your request',
  ),
];

/// Bottom sheet for selecting a change request type and entering details.
///
/// [orderId] links the overflow menu's "View Order Details" to the real
/// order screen. [parentContext] is the context that opened the sheet and
/// stays mounted after the sheet pops, so pushed routes land correctly.
Future<ChangeRequestResult?> showChangeRequestSheet(
  BuildContext context, {
  String? orderId,
  String viewerRole = 'customer',
}) {
  return showModalBottomSheet<ChangeRequestResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ChangeRequestSheet(
      orderId: orderId,
      viewerRole: viewerRole,
      parentContext: context,
    ),
  );
}

class _ChangeRequestSheet extends StatefulWidget {
  final String? orderId;
  final String viewerRole;
  final BuildContext parentContext;

  const _ChangeRequestSheet({
    this.orderId,
    this.viewerRole = 'customer',
    required this.parentContext,
  });

  @override
  State<_ChangeRequestSheet> createState() => _ChangeRequestSheetState();
}

class _ChangeRequestSheetState extends State<_ChangeRequestSheet> {
  ChangeRequestType? _selectedType;
  final _detailsController = TextEditingController();
  bool _isNavigating = false;

  bool get _isSeller => widget.viewerRole == 'seller';

  /// Open the linked order in the role-appropriate detail screen.
  Future<void> _openOrderDetails() async {
    if (_isNavigating) return;
    final orderId = widget.orderId;
    if (orderId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No order is linked to this conversation'),
        ),
      );
      return;
    }
    setState(() => _isNavigating = true);
    try {
      final Map<String, dynamic>? order = _isSeller
          ? await SupabaseService.instance.fetchSellerOrderById(orderId)
          : await SupabaseService.instance.fetchOrderWithItems(orderId);
      if (!mounted || !widget.parentContext.mounted) return;
      if (order == null) {
        setState(() => _isNavigating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Order is no longer available'),
          ),
        );
        return;
      }
      Navigator.of(context).pop();
      Navigator.of(widget.parentContext).push(
        MaterialPageRoute(
          builder: (_) => _isSeller
              ? OrderDetailScreen(order: order)
              : OrderTrackingScreen(order: order),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isNavigating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load order details: $e')),
      );
    }
  }

  /// Open the support screen (same destination as Profile → Help → Support).
  void _openSupport() {
    if (_isNavigating) return;
    Navigator.of(context).pop();
    Navigator.of(widget.parentContext).push(
      MaterialPageRoute(builder: (_) => const SupportChatScreen()),
    );
  }

  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
  }

  bool get _canSubmit {
    return _selectedType != null && _detailsController.text.trim().isNotEmpty;
  }

  void _submit() {
    if (!_canSubmit) return;
    Navigator.of(context).pop(
      ChangeRequestResult(
        type: _selectedType!.id,
        toValue: _detailsController.text.trim(),
      ),
    );
  }

  void _clearDraft() {
    _detailsController.clear();
    setState(() {});
  }

  void _resetForm() {
    setState(() {
      _selectedType = null;
      _detailsController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: AppConstants.surfaceLight,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppConstants.borderGray,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // ─── FIXED HEADER ─────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 12, 0),
            child: Row(
              children: [
                // Back button
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                  color: AppConstants.secondary,
                ),
                // Title
                Expanded(
                  child: Text(
                    'Request a Change',
                    style: AppConstants.headlineStyle(fontSize: 18),
                  ),
                ),
                // Overflow menu (same animated menu as the chat header).
                Builder(
                  builder: (context) => IconButton(
                    icon: Icon(
                      Icons.more_vert,
                      size: 22,
                      color: AppConstants.secondary,
                    ),
                    onPressed: _isNavigating
                        ? null
                        : () {
                            showCustomPopupMenu(
                              context: context,
                              items: [
                                CustomPopupMenuItem(
                                  label: 'Reset Form',
                                  icon: Icons.refresh,
                                  onTap: _resetForm,
                                ),
                                CustomPopupMenuItem(
                                  label: 'Clear Draft',
                                  icon: Icons.backspace_outlined,
                                  onTap: _clearDraft,
                                ),
                                CustomPopupMenuItem(
                                  label: 'View Order Details',
                                  icon: Icons.receipt_long,
                                  onTap: _openOrderDetails,
                                  showDividerBefore: true,
                                ),
                                CustomPopupMenuItem(
                                  label: 'Contact Support',
                                  icon: Icons.help_outline,
                                  onTap: _openSupport,
                                ),
                              ],
                            );
                          },
                  ),
                ),
              ],
            ),
          ),

          // Subtitle
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Select what you\'d like to change. The seller will review your request.',
              style: AppConstants.bodyStyle(
                fontSize: 13,
                color: AppConstants.secondary.withValues(alpha: 0.6),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Loading bar while the linked order is being fetched.
          if (_isNavigating)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: LinearProgressIndicator(
                color: AppConstants.primary,
                backgroundColor: Colors.transparent,
              ),
            ),

          // ─── SCROLLABLE BODY ──────────────────────────────
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: changeRequestTypes.length,
              itemBuilder: (context, index) {
                final type = changeRequestTypes[index];
                final isSelected = _selectedType?.id == type.id;

                return Column(
                  children: [
                    _TypeOption(
                      type: type,
                      isSelected: isSelected,
                      onTap: () {
                        setState(() {
                          _selectedType = type;
                          _detailsController.clear();
                        });
                      },
                    ),
                    // Show details field when type is selected
                    if (isSelected) ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: _detailsController,
                        maxLines: 3,
                        minLines: 2,
                        decoration: InputDecoration(
                          hintText: type.hint,
                          hintStyle: AppConstants.bodyStyle(
                            fontSize: 13,
                            color: AppConstants.secondary.withValues(alpha: 0.4),
                          ),
                          filled: true,
                          fillColor: AppConstants.surfaceLight,
                          contentPadding: const EdgeInsets.all(12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                              color: AppConstants.borderGray.withValues(alpha: 0.5),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                              color: AppConstants.borderGray.withValues(alpha: 0.5),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                              color: AppConstants.primary,
                              width: 1.5,
                            ),
                          ),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 4),
                    ],
                    const SizedBox(height: 4),
                  ],
                );
              },
            ),
          ),

          // ─── FIXED FOOTER ─────────────────────────────────
          Container(
            padding: EdgeInsets.fromLTRB(
              20,
              12,
              20,
              12 + MediaQuery.of(context).padding.bottom,
            ),
            decoration: BoxDecoration(
              color: AppConstants.surfaceLight,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 12,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: SolePrimaryButton(
              label: _isNavigating ? 'Loading Order…' : 'Send Request',
              onPressed: (_canSubmit && !_isNavigating) ? _submit : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// Single selectable type option.
class _TypeOption extends StatelessWidget {
  final ChangeRequestType type;
  final bool isSelected;
  final VoidCallback onTap;

  const _TypeOption({
    required this.type,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? AppConstants.primary.withValues(alpha: 0.06)
              : AppConstants.sellerCardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? AppConstants.primary.withValues(alpha: 0.3)
                : AppConstants.borderGray.withValues(alpha: 0.3),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            // Icon
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isSelected
                    ? AppConstants.primary.withValues(alpha: 0.12)
                    : AppConstants.surfaceLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                type.icon,
                size: 18,
                color: isSelected ? AppConstants.primary : AppConstants.secondary,
              ),
            ),
            const SizedBox(width: 12),
            // Label
            Expanded(
              child: Text(
                type.label,
                style: AppConstants.bodyStyle(
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: AppConstants.secondary,
                ),
              ),
            ),
            // Radio indicator
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? AppConstants.primary : AppConstants.borderGray,
                  width: 1.5,
                ),
              ),
              child: isSelected
                  ? Center(
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppConstants.primary,
                        ),
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
