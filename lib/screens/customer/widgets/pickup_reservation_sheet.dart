import 'package:flutter/material.dart';

import '../../../constants/app_constants.dart';
import '../../../services/pickup_reservation_service.dart';
import '../../../utils/sale_price.dart';
import '../../../widgets/sole_primary_button.dart';
import 'reservation_sheet_parts.dart';

/// Bottom sheet: reserve 1–2 pairs of ONE size of ONE colour for in-store
/// pickup.
///
/// Distinct from [showBulkReservationSheet]: this one holds stock
/// immediately, needs no approval and costs nothing — the customer pays when
/// they collect. Above [PickupReservation.maxQuantity] pairs the sheet
/// points at the bulk (reseller) flow, because that is the flow that
/// requires the seller's agreement and a deposit.
///
/// [stockByColor] is the live {colour: {size: stock}} map from the detail
/// screen, keyed by the seller's colour names with `''` standing in for a
/// product without colour variants: the hold is keyed on
/// `(product_id, size)`, so the colour is what tells the seller which pair to
/// put aside.
///
/// Resolves to `true` once a hold was created, so the caller can refresh the
/// stock it is displaying.
Future<bool?> showPickupReservationSheet(
  BuildContext context, {
  required Map<String, dynamic> product,
  required Map<String, Map<String, int>> stockByColor,
  String? initialColor,
  String? initialSize,
  PickupReservationService? service,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PickupReservationSheet(
      product: product,
      stockByColor: stockByColor,
      initialColor: initialColor,
      initialSize: initialSize,
      service: service,
    ),
  );
}

class _PickupReservationSheet extends StatefulWidget {
  final Map<String, dynamic> product;
  final Map<String, Map<String, int>> stockByColor;
  final String? initialColor;
  final String? initialSize;

  /// Injected in tests; defaults to the live service.
  final PickupReservationService? service;

  const _PickupReservationSheet({
    required this.product,
    required this.stockByColor,
    this.initialColor,
    this.initialSize,
    this.service,
  });

  @override
  State<_PickupReservationSheet> createState() =>
      _PickupReservationSheetState();
}

class _PickupReservationSheetState extends State<_PickupReservationSheet> {
  late final PickupReservationService _service =
      widget.service ?? PickupReservationService.instance;

  String _color = '';
  String? _size;
  int _quantity = 1;
  bool _submitting = false;
  String? _error;

  List<String> get _colors => reservationColors(widget.stockByColor);

  /// The selected colour's {size: stock} — the sizes this hold can pick from.
  Map<String, int> get _sizes => widget.stockByColor[_color] ?? const {};

  /// Sizes that can actually be reserved right now.
  Map<String, int> get _available => {
        for (final e in _sizes.entries)
          if (e.value > 0) e.key: e.value,
      };

  int get _stockForSelectedSize => _size == null ? 0 : (_available[_size] ?? 0);

  /// The stepper can never exceed either the cap or the size's live stock.
  int get _maxForSelectedSize {
    final cap = PickupReservation.maxQuantity;
    final stock = _stockForSelectedSize;
    return stock < cap ? stock : cap;
  }

  bool get _canSubmit => !_submitting && _size != null && _quantity >= 1;

  @override
  void initState() {
    super.initState();
    final colors = _colors;
    final preferredColor = widget.initialColor;
    _color = colors.isEmpty
        ? ''
        : (preferredColor != null && colors.contains(preferredColor)
            ? preferredColor
            : colors.first);
    _pickSize();
  }

  /// Prefer the size already chosen on the detail screen, else the only one
  /// with stock.
  void _pickSize() {
    _size = null;
    final preferred = widget.initialSize;
    if (preferred != null && (_available[preferred] ?? 0) > 0) {
      _size = preferred;
    } else if (_available.length == 1) {
      _size = _available.keys.first;
    }
    _quantity = 1;
  }

  /// Sizes are per colour, so the size carried over from the detail page may
  /// not exist in the new colour: re-pick rather than hold a size the seller
  /// cannot pull from that colour's shelf.
  void _selectColor(String color) {
    if (color == _color) return;
    setState(() {
      _color = color;
      _pickSize();
    });
  }

  Future<void> _submit() async {
    final size = _size;
    if (size == null || !_canSubmit) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await _service.request(
        productId: widget.product['id'].toString(),
        size: size,
        quantity: _quantity,
        color: _color.isEmpty ? null : _color,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppConstants.success,
          content: Text(
            'Held for pickup for 24 hours. Pay when you collect — see '
            'Profile → My Pickup Reservations.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = friendlyPickupReservationError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final price = effectivePrice(widget.product);
    final available = _available;
    final colors = _colors;
    // Sizes sorted numerically, like the detail page's picker.
    final sortedAvailable = Map.fromEntries(
      available.entries.toList()
        ..sort((a, b) =>
            (int.tryParse(a.key) ?? 0).compareTo(int.tryParse(b.key) ?? 0)),
    );

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppConstants.surfaceLight,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: SafeArea(
          top: false,
          // The sheet carries a product summary, an optional colour picker and
          // the size chips: on a short screen — or with the keyboard up — it
          // has to scroll rather than overflow.
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              const ReservationSheetHandle(),
              const SizedBox(height: 14),
              Text('Reserve for Pickup',
                  style: AppConstants.headlineStyle(fontSize: 18)),
              const SizedBox(height: 4),
              Text(
                'We hold ${_quantity == 1 ? 'your pair' : 'your $_quantity pairs'} '
                'at ${widget.product['store_name'] ?? 'the store'} for 24 hours. '
                'Free to reserve — you pay when you collect.',
                style: AppConstants.bodyStyle(
                  fontSize: 12,
                  color: AppConstants.secondary,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 14),

              // What is being held, and in which colour.
              ReservationProductRow(product: widget.product, color: _color),
              const SizedBox(height: 14),

              if (colors.length > 1) ...[
                Text('Color',
                    style: AppConstants.bodyStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                ReservationColorChips(
                  colors: colors,
                  selected: _color,
                  onSelect: _selectColor,
                ),
                const SizedBox(height: 14),
              ],

              // ── size (required: a hold is for one pair in one size) ──
              Text('Size',
                  style: AppConstants.bodyStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              if (sortedAvailable.isEmpty)
                Text(
                  'No size is in stock right now.',
                  style: AppConstants.bodyStyle(
                    fontSize: 12,
                    color: AppConstants.error,
                  ),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final entry in sortedAvailable.entries)
                      ReservationSizeChip(
                        label: entry.key,
                        stock: entry.value,
                        selected: _size == entry.key,
                        onTap: () => setState(() {
                          _size = entry.key;
                          // Never leave the stepper above what that size has.
                          if (_quantity > _maxForSelectedSize) {
                            _quantity =
                                _maxForSelectedSize < 1 ? 1 : _maxForSelectedSize;
                          }
                        }),
                      ),
                  ],
                ),
              const SizedBox(height: 16),

              // ── quantity (capped at the hold limit AND live stock) ──
              Row(
                children: [
                  Text('Quantity',
                      style:
                          AppConstants.bodyStyle(fontWeight: FontWeight.w600)),
                  const Spacer(),
                  ReservationStepButton(
                    icon: Icons.remove,
                    onTap: _quantity > 1
                        ? () => setState(() => _quantity--)
                        : null,
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 44,
                    child: Text(
                      '$_quantity',
                      textAlign: TextAlign.center,
                      style: AppConstants.bodyStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ReservationStepButton(
                    icon: Icons.add,
                    onTap: _quantity < _maxForSelectedSize
                        ? () => setState(() => _quantity++)
                        : null,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  _size == null
                      ? 'Choose a size'
                      : '$_stockForSelectedSize in size $_size · max '
                          '${PickupReservation.maxQuantity} per hold',
                  style: AppConstants.bodyStyle(
                    fontSize: 11,
                    color: AppConstants.secondary.withValues(alpha: 0.6),
                  ),
                ),
              ),

              // What it costs (nothing now) — the whole point of this flow.
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppConstants.success.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'FREE to reserve — no deposit',
                      style: AppConstants.bodyStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppConstants.success,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _size == null
                          ? 'Pay ₱${price.toStringAsFixed(0)} per pair when you collect.'
                          : 'Pay ₱${(price * _quantity).toStringAsFixed(0)} when you '
                              'collect. Held 24 hours, then released automatically.',
                      style: AppConstants.bodyStyle(
                        fontSize: 12,
                        color: AppConstants.secondary.withValues(alpha: 0.8),
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),

              // Point large orders at the deposit-gated reseller flow.
              if (_stockForSelectedSize > PickupReservation.maxQuantity) ...[
                const SizedBox(height: 8),
                Text(
                  'Need ${PickupReservation.maxQuantity + 1} or more pairs? '
                  'Ask the store for a bulk reservation instead.',
                  style: AppConstants.bodyStyle(
                    fontSize: 11,
                    color: AppConstants.secondary.withValues(alpha: 0.65),
                    height: 1.3,
                  ),
                ),
              ],

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
                label: 'Reserve for Pickup',
                onPressed: _canSubmit ? _submit : null,
                isLoading: _submitting,
              ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
