import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../constants/app_constants.dart';
import '../../providers/cart_provider.dart';
import '../../widgets/sole_card.dart';
import '../../widgets/sole_primary_button.dart';
import '../../widgets/empty_state_widget.dart';
import '../store/store_profile_screen.dart';
import 'checkout_screen.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  Map<String, int> _itemMaxStock = {};
  bool _isValidating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _validateStock();
      // Remove any lines that were already paid for while the app was
      // away (e.g. the GCash webhook confirmed during a killed app) so
      // they can't be accidentally re-ordered.
      context.read<CartProvider>().reconcilePurchasedCart();
    });
  }

  Future<void> _validateStock() async {
    if (_isValidating) return;
    setState(() => _isValidating = true);
    try {
      final cart = context.read<CartProvider>();
      final results = await cart.validateForCheckout();
      if (!mounted) return;
      final maxStock = <String, int>{};
      for (final r in results) {
        if (r.isAvailable && r.currentStock > 0) {
          maxStock[r.cartItemId] = r.currentStock;
        }
      }
      setState(() {
        _itemMaxStock = maxStock;
        _isValidating = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isValidating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final grouped = cart.groupedByStore;

    return Scaffold(
        backgroundColor: AppConstants.surfaceLight,
        appBar: AppBar(
          title: Text(
            'My Cart',
            style: AppConstants.headlineStyle(fontSize: 20),
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
          automaticallyImplyLeading: false,
          actions: [
            if (cart.items.isNotEmpty)
              TextButton(
                onPressed: () {
                  if (cart.allSelected) {
                    cart.toggleAll();
                  } else {
                    cart.selectAll();
                  }
                },
                child: Text(
                  cart.allSelected ? 'Deselect All' : 'Select All',
                  style: AppConstants.bodyStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppConstants.accent,
                  ),
                ),
              ),
          ],
        ),
        body: grouped.isEmpty
            ? _buildEmptyState()
            : Column(
                children: [
                  Expanded(
                    child: RefreshIndicator(
                      color: AppConstants.primary,
                      backgroundColor: AppConstants.surfaceLight,
                      onRefresh: () => cart.refreshFromServer(),
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: grouped.length,
                        itemBuilder: (context, index) {
                          final group = grouped[index];
                          return _StoreGroupCard(
                            storeId: group['store_id'] as String,
                            storeName: group['store_name'] as String,
                            items: group['items'] as List<Map<String, dynamic>>,
                            itemMaxStock: _itemMaxStock,
                          );
                        },
                      ),
                    ),
                  ),
                  const _CartCheckoutBar(),
                ],
              ),
      );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: EmptyStateWidget(
          icon: Icons.shopping_bag_outlined,
          title: 'Your cart is empty',
          subtitle: 'Browse products and try them on in AR!',
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Store Group Card
// ═══════════════════════════════════════════════════════════════════

class _StoreGroupCard extends StatelessWidget {
  final String storeId;
  final String storeName;
  final List<Map<String, dynamic>> items;
  final Map<String, int> itemMaxStock;

  const _StoreGroupCard({
    required this.storeId,
    required this.storeName,
    required this.items,
    required this.itemMaxStock,
  });

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final isFullySelected = cart.isStoreFullySelected(storeId);
    final isPartiallySelected = cart.isStorePartiallySelected(storeId);

    return SoleCard(
      color: Colors.white,
      padding: EdgeInsets.zero,
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Store Header ──────────────────────────────────
          GestureDetector(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => StoreProfileScreen(
                    storeId: storeId,
                  ),
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: AppConstants.borderGray.withValues(alpha: 0.4),
                    width: 0.5,
                  ),
                ),
              ),
              child: Row(
                children: [
                  // Store checkbox (indeterminate / full / empty)
                  GestureDetector(
                    onTap: () => cart.toggleStore(storeId),
                    child: _SoleCheckbox(
                      value: isFullySelected
                          ? true
                          : isPartiallySelected
                              ? null
                              : false,
                      onTap: () => cart.toggleStore(storeId),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Icon(
                    Icons.storefront_outlined,
                    size: 16,
                    color: AppConstants.primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      storeName,
                      style: AppConstants.bodyStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppConstants.secondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: AppConstants.borderGray,
                  ),
                ],
              ),
            ),
          ),

          // ── Item Rows ─────────────────────────────────────
          for (int i = 0; i < items.length; i++) ...[
            _CartItemRow(
              item: items[i],
              maxStock: itemMaxStock[items[i]['server_id']],
            ),
            if (i < items.length - 1)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Divider(
                  height: 0.5,
                  color: AppConstants.borderGray.withValues(alpha: 0.3),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Cart Item Row
// ═══════════════════════════════════════════════════════════════════

class _CartItemRow extends StatelessWidget {
  final Map<String, dynamic> item;
  final int? maxStock; // null = stock not yet validated

  const _CartItemRow({required this.item, this.maxStock});

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final itemKey = item['id'] as String;
    final isSelected = cart.selectedKeys.contains(itemKey);
    final quantity = item['quantity'] as int;
    final price = item['price'] as double;
    final lineTotal = price * quantity;
    final atMax = maxStock != null && quantity >= maxStock!;

    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        color: isSelected ? AppConstants.accent.withValues(alpha: 0.03) : Colors.transparent,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Item checkbox
            GestureDetector(
              onTap: () => cart.toggleItem(itemKey),
              child: _SoleCheckbox(
                value: isSelected,
                onTap: () => cart.toggleItem(itemKey),
              ),
            ),
            const SizedBox(width: 10),

            // Product thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                item['imageUrl'] ?? '',
                width: 60,
                height: 60,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  width: 60,
                  height: 60,
                  color: AppConstants.borderGray.withValues(alpha: 0.2),
                  child: const Icon(Icons.broken_image, color: AppConstants.primary, size: 20),
                ),
              ),
            ),
            const SizedBox(width: 10),

            // Name + variant + stepper
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Product name
                  Text(
                    item['product_name'] ?? '',
                    style: AppConstants.bodyStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),

                  // Size · Color · Max stock label
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'EU ${item['size']} · ${item['color']}',
                          style: AppConstants.bodyStyle(
                            fontSize: 11,
                            color: AppConstants.secondary.withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                      if (maxStock != null && maxStock! <= 5)
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppConstants.error.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Only $maxStock left',
                              style: AppConstants.bodyStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: AppConstants.error,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),

                  // Quantity stepper
                  Row(
                    children: [
                      _QuantityButton(
                        icon: Icons.remove,
                        onTap: () => cart.decrementQuantity(itemKey),
                      ),
                      Container(
                        width: 32,
                        alignment: Alignment.center,
                        child: Text(
                          '$quantity',
                          style: AppConstants.monoStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: AppConstants.secondary,
                          ),
                        ),
                      ),
                      _QuantityButton(
                        icon: Icons.add,
                        onTap: atMax ? null : () => cart.incrementQuantity(itemKey),
                        disabled: atMax,
                      ),
                      // "Max: N" is flexible so it ellipsizes instead of
                      // overflowing the row on narrow screens; the delete
                      // button stays pinned to the right.
                      if (maxStock != null)
                        Flexible(
                          child: Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Text(
                              'Max: $maxStock',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppConstants.bodyStyle(
                                fontSize: 10,
                                color: atMax
                                    ? AppConstants.error
                                    : AppConstants.secondary.withValues(alpha: 0.4),
                              ),
                            ),
                          ),
                        )
                      else
                        const Spacer(),
                      // Delete button
                      GestureDetector(
                        onTap: () => _showDeleteConfirmation(context, cart, itemKey),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          child: Icon(
                            Icons.delete_outline,
                            size: 16,
                            color: AppConstants.error.withValues(alpha: 0.7),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // Price
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '₱${lineTotal.toStringAsFixed(2)}',
                  style: AppConstants.monoStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppConstants.primary,
                  ),
                ),
                if (quantity > 1)
                  Text(
                    '₱${price.toStringAsFixed(2)} each',
                    style: AppConstants.bodyStyle(
                      fontSize: 10,
                      color: AppConstants.secondary.withValues(alpha: 0.4),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context, CartProvider cart, String itemKey) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppConstants.borderGray,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Icon(
              Icons.delete_outline,
              size: 32,
              color: AppConstants.error,
            ),
            const SizedBox(height: 12),
            Text(
              'Remove Item?',
              style: AppConstants.headlineStyle(fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(
              'This item will be removed from your cart.',
              style: AppConstants.bodyStyle(
                fontSize: 13,
                color: AppConstants.secondary.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: AppConstants.borderGray),
                      shape: RoundedRectangleBorder(
                        borderRadius: AppConstants.buttonRadius,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(
                      'Cancel',
                      style: AppConstants.bodyStyle(
                        fontWeight: FontWeight.bold,
                        color: AppConstants.secondary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SolePrimaryButton(
                    label: 'Remove',
                    backgroundColor: AppConstants.error,
                    onPressed: () {
                      cart.removeFromCart(itemKey);
                      Navigator.of(ctx).pop();
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Quantity Button
// ═══════════════════════════════════════════════════════════════════

class _QuantityButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool disabled;

  const _QuantityButton({
    required this.icon,
    required this.onTap,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDisabled = disabled || onTap == null;
    return GestureDetector(
      onTap: isDisabled ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          border: Border.all(
            color: isDisabled
                ? AppConstants.borderGray.withValues(alpha: 0.3)
                : AppConstants.borderGray,
            width: 1,
          ),
          borderRadius: BorderRadius.circular(6),
          color: isDisabled
              ? AppConstants.borderGray.withValues(alpha: 0.08)
              : Colors.transparent,
        ),
        child: Icon(
          icon,
          size: 14,
          color: isDisabled
              ? AppConstants.secondary.withValues(alpha: 0.25)
              : AppConstants.secondary,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// SoleCheckbox — branded checkbox with indeterminate support
// ═══════════════════════════════════════════════════════════════════

class _SoleCheckbox extends StatelessWidget {
  final bool? value; // true = checked, false = unchecked, null = indeterminate
  final VoidCallback onTap;

  const _SoleCheckbox({required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isChecked = value == true;
    final isIndeterminate = value == null;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: isChecked || isIndeterminate ? AppConstants.accent : Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isChecked || isIndeterminate ? AppConstants.accent : AppConstants.borderGray,
            width: 1.5,
          ),
        ),
        child: isChecked
            ? const Icon(Icons.check, size: 14, color: Colors.white)
            : isIndeterminate
                ? Container(
                    margin: const EdgeInsets.symmetric(horizontal: 5),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.all(Radius.circular(1)),
                    ),
                  )
                : null,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Sticky Checkout Bar
// ═══════════════════════════════════════════════════════════════════

class _CartCheckoutBar extends StatelessWidget {
  const _CartCheckoutBar();

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final hasItems = cart.items.isNotEmpty;
    final selectedCount = cart.selectedCount;
    final canCheckout = selectedCount > 0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      child: Row(
        children: [
          // Master "All" checkbox
          if (hasItems) ...[
            GestureDetector(
              onTap: () => cart.toggleAll(),
              child: _SoleCheckbox(
                value: cart.allSelected
                    ? true
                    : cart.selectedKeys.isEmpty
                        ? false
                        : null, // partial
                onTap: () => cart.toggleAll(),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'All',
              style: AppConstants.bodyStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppConstants.secondary.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(width: 12),
          ],

          // Delivery info
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (canCheckout)
                  Text(
                    'Delivery: ₱${cart.selectedDeliveryFee.toStringAsFixed(2)}',
                    style: AppConstants.bodyStyle(
                      fontSize: 11,
                      color: AppConstants.secondary.withValues(alpha: 0.5),
                    ),
                  ),
                Text(
                  '₱${cart.selectedTotal.toStringAsFixed(2)}',
                  style: AppConstants.monoStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppConstants.primary,
                  ),
                ),
              ],
            ),
          ),

          // Checkout button — fixed generous width so it doesn't shrink
          // to just the label and look cramped in the bar.
          SizedBox(
            width: 150,
            child: SolePrimaryButton(
              label: 'Check Out',
              expandToFill: true,
              onPressed: canCheckout
                  ? () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const CheckoutScreen(),
                        ),
                      );
                    }
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}
