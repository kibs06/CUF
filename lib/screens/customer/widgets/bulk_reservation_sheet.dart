import 'package:flutter/material.dart';

import '../../../constants/app_constants.dart';
import '../../../services/reservation_service.dart';
import '../../../utils/sale_price.dart';
import '../../../widgets/sole_primary_button.dart';

/// Bottom sheet: the customer requests a bulk (reseller) hold on this
/// product — how many units, an optional size breakdown, and a note for
/// the seller. Nothing is held until the seller approves.
///
/// [sizesStock] is the live {size: stock} map from the detail screen so the
/// sheet can show availability and pre-fill a proportional breakdown.
Future<void> showBulkReservationSheet(
  BuildContext context, {
  required Map<String, dynamic> product,
  required Map<String, int> sizesStock,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _BulkReservationSheet(
      product: product,
      sizesStock: sizesStock,
    ),
  );
}

class _BulkReservationSheet extends StatefulWidget {
  final Map<String, dynamic> product;
  final Map<String, int> sizesStock;

  const _BulkReservationSheet({
    required this.product,
    required this.sizesStock,
  });

  @override
  State<_BulkReservationSheet> createState() => _BulkReservationSheetState();
}

class _BulkReservationSheetState extends State<_BulkReservationSheet> {
  final _quantityCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _service = ReservationService.instance;
  bool _submitting = false;
  String? _error;

  int get _totalStock =>
      widget.sizesStock.values.fold(0, (sum, s) => sum + s);

  int get _quantity => int.tryParse(_quantityCtrl.text.trim()) ?? 0;

  bool get _isValid => _quantity >= 1 && _quantity <= _totalStock;

  @override
  void dispose() {
    _quantityCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_isValid || _submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      // Optional size breakdown: split the requested quantity across sizes
      // with stock, largest stock first (informational for the seller).
      final breakdown = <Map<String, dynamic>>[];
      var remaining = _quantity;
      final sizes = widget.sizesStock.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      for (final e in sizes) {
        if (remaining <= 0) break;
        if (e.value <= 0) continue;
        final take = e.value < remaining ? e.value : remaining;
        breakdown.add({'size': e.key, 'quantity': take});
        remaining -= take;
      }

      await _service.requestReservation(
        productId: widget.product['id'].toString(),
        storeId: widget.product['store_id'].toString(),
        quantity: _quantity,
        requestedSizes: breakdown,
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppConstants.success,
          content: const Text(
            'Reservation request sent — the seller will review it. If '
            'approved, you\'ll have 24 hours to pay the deposit.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = friendlyReservationError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final price = effectivePrice(widget.product);
    final estimate = price * _quantity;
    return Padding(
      // Keyboard inset so the sheet lifts above the input.
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle + title
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppConstants.secondary.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Request Bulk Reservation',
                style: AppConstants.headlineStyle(fontSize: 18),
              ),
              const SizedBox(height: 4),
              Text(
                'Buying to resell? Ask ${widget.product['store_name'] ?? 'the seller'} '
                'to hold stock for you. If they approve, you\'ll pay a 20% '
                'GCash deposit (non-refundable) within 24 hours to lock the '
                'stock.',
                style: AppConstants.bodyStyle(
                  fontSize: 12,
                  color: AppConstants.secondary,
                ),
              ),
              const SizedBox(height: 16),

              // Quantity stepper
              Row(
                children: [
                  Text(
                    'Quantity',
                    style: AppConstants.bodyStyle(fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  _StepButton(
                    icon: Icons.remove,
                    onTap: _quantity > 1
                        ? () => setState(() => _quantityCtrl.text =
                            (_quantity - 1).toString())
                        : null,
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 64,
                    child: TextField(
                      controller: _quantityCtrl,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      onChanged: (_) => setState(() {}),
                      style: AppConstants.bodyStyle(
                          fontWeight: FontWeight.bold, fontSize: 15),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            vertical: 10, horizontal: 6),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _StepButton(
                    icon: Icons.add,
                    onTap: _quantity < _totalStock
                        ? () => setState(() => _quantityCtrl.text =
                            (_quantity + 1).toString())
                        : null,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  _totalStock > 0
                      ? '$_totalStock in stock'
                      : 'Out of stock',
                  style: AppConstants.bodyStyle(
                    fontSize: 11,
                    color: _totalStock > 0
                        ? AppConstants.secondary.withValues(alpha: 0.6)
                        : AppConstants.error,
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Estimated value (informational only — price locked at pickup)
              if (_quantity >= 1)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppConstants.primary.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Estimated value: ₱${estimate.toStringAsFixed(0)} '
                    '(final price is confirmed at pickup)',
                    style: AppConstants.bodyStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppConstants.primary,
                    ),
                  ),
                ),
              const SizedBox(height: 12),

              // Note to seller
              TextField(
                controller: _noteCtrl,
                maxLines: 2,
                maxLength: 200,
                style: AppConstants.bodyStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Note to seller (optional) — e.g. sizes you want',
                  hintStyle: AppConstants.bodyStyle(
                    fontSize: 12,
                    color: AppConstants.secondary.withValues(alpha: 0.5),
                  ),
                  counterText: '',
                  isDense: true,
                  contentPadding: const EdgeInsets.all(12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: AppConstants.bodyStyle(
                    fontSize: 12,
                    color: AppConstants.error,
                  ),
                ),
              ],
              const SizedBox(height: 16),

              SolePrimaryButton(
                label: 'Send Request',
                onPressed: _isValid ? _submit : null,
                isLoading: _submitting,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _StepButton({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: onTap != null
              ? AppConstants.primary.withValues(alpha: 0.08)
              : AppConstants.secondary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(
          icon,
          size: 18,
          color: onTap != null
              ? AppConstants.primary
              : AppConstants.secondary.withValues(alpha: 0.4),
        ),
      ),
    );
  }
}
