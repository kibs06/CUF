import 'package:flutter/material.dart';

import '../../../constants/app_constants.dart';
import '../../../services/reservation_service.dart';
import '../../../utils/sale_price.dart';
import '../../../utils/size_key.dart';
import '../../../widgets/sole_primary_button.dart';
import 'reservation_sheet_parts.dart';

/// Bottom sheet: the customer requests a bulk (reseller) hold on this
/// product — WHICH colour, WHICH sizes and how many pairs of each, plus an
/// optional note for the seller. Nothing is held until the seller approves.
///
/// [stockByColor] is the live {colour: {size: stock}} map from the detail
/// screen, keyed by the seller's colour names with `''` standing in for a
/// product that has no colour variants. The sheet picks the colour (hidden
/// when there is only one) and then offers that colour's sizes, because the
/// request is keyed on `product_id` alone — a bulk hold that does not say
/// what it is holding is a request the seller has to guess at.
Future<void> showBulkReservationSheet(
  BuildContext context, {
  required Map<String, dynamic> product,
  required Map<String, Map<String, int>> stockByColor,
  String? initialColor,
  ReservationService? service,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _BulkReservationSheet(
      product: product,
      stockByColor: stockByColor,
      initialColor: initialColor,
      service: service,
    ),
  );
}

class _BulkReservationSheet extends StatefulWidget {
  final Map<String, dynamic> product;
  final Map<String, Map<String, int>> stockByColor;
  final String? initialColor;

  /// Injected in tests; defaults to the live service.
  final ReservationService? service;

  const _BulkReservationSheet({
    required this.product,
    required this.stockByColor,
    this.initialColor,
    this.service,
  });

  @override
  State<_BulkReservationSheet> createState() => _BulkReservationSheetState();
}

class _BulkReservationSheetState extends State<_BulkReservationSheet> {
  final _noteCtrl = TextEditingController();
  late final ReservationService _service =
      widget.service ?? ReservationService.instance;

  /// Pairs requested per size, for the SELECTED colour only (empty key = a
  /// product without colour variants). Sizes left at 0 are simply not sent —
  /// this replaced the old largest-stock-first auto-split, which guessed.
  final Map<String, int> _pairs = {};

  String _color = '';
  bool _submitting = false;
  String? _error;

  /// 20% of the estimated value, rounded up to a whole peso — the same rule
  /// the server applies at approval (see
  /// `20260913140000_add_bulk_reservation_deposits.sql`). Shown here as an
  /// estimate only; the seller confirms the real amount at approval.
  static const double _depositRate = 0.20;

  List<String> get _colors => reservationColors(widget.stockByColor);

  /// The selected colour's {size: stock} — what can actually be requested.
  Map<String, int> get _sizes => widget.stockByColor[_color] ?? const {};

  int get _totalStock => _sizes.values.fold(0, (sum, s) => sum + s);

  int get _totalPairs => _pairs.values.fold(0, (sum, q) => sum + q);

  double get _estimatedValue => effectivePrice(widget.product) * _totalPairs;

  /// Rounded UP to a whole peso, matching the server's rule at approval.
  double get _depositEstimate =>
      (_estimatedValue * _depositRate).ceilToDouble();

  /// Only the sizes actually picked, each tagged with the colour — this is
  /// what the seller reads and what the deposit is computed from.
  List<Map<String, dynamic>> get _breakdown => [
        for (final entry in _pairs.entries)
          if (entry.value > 0)
            {
              'size': entry.key,
              'quantity': entry.value,
              if (_color.isNotEmpty) 'color': _color,
            },
      ];

  /// A size can never be asked for beyond its own stock (the RPC re-checks,
  /// but the stepper should not let the customer build a request it rejects).
  bool get _isValid =>
      _totalPairs >= 1 &&
      _pairs.entries.every((e) => e.value <= (_sizes[e.key] ?? 0));

  @override
  void initState() {
    super.initState();
    final colors = _colors;
    final preferred = widget.initialColor;
    _color = colors.isEmpty
        ? ''
        : (preferred != null && colors.contains(preferred)
            ? preferred
            : colors.first);
    for (final size in _sizes.keys) {
      _pairs[size] = 0;
    }
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  /// Sizes are per colour, so a quantity picked for "Brown US 9" says nothing
  /// about "Black US 9" — switching colours starts the counts over rather than
  /// silently carrying a request the new colour may not have stock for.
  void _selectColor(String color) {
    if (color == _color) return;
    setState(() {
      _color = color;
      _pairs.clear();
      for (final size in _sizes.keys) {
        _pairs[size] = 0;
      }
    });
  }

  void _step(String size, int delta) {
    final stock = _sizes[size] ?? 0;
    final next = (_pairs[size] ?? 0) + delta;
    if (next < 0 || next > stock) return;
    setState(() => _pairs[size] = next);
  }

  Future<void> _submit() async {
    if (!_isValid || _submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await _service.requestReservation(
        productId: widget.product['id'].toString(),
        storeId: widget.product['store_id'].toString(),
        quantity: _totalPairs,
        requestedSizes: _breakdown,
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
    final colors = _colors;
    // Sizes sorted numerically, the same order as the detail page's picker —
    // half sizes included, and unparseable keys last (plan §4.3).
    final sizes = _sizes.entries.toList()
      ..sort((a, b) => compareSizes(a.key, b.key));

    return Padding(
      // Keyboard inset so the sheet lifts above the note field.
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: AppConstants.surfaceLight,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: SafeArea(
          top: false,
          // The sheet carries a product summary, a colour picker and a size
          // list: on a short screen — or with the keyboard up over the note
          // field — it must scroll rather than overflow.
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              const ReservationSheetHandle(),
              const SizedBox(height: 14),
              Text(
                'Request Bulk Reservation',
                style: AppConstants.headlineStyle(fontSize: 18),
              ),
              const SizedBox(height: 4),
              Text(
                'Buying to resell? Ask ${widget.product['store_name'] ?? 'the seller'} '
                'to hold stock for you. They review every request — nothing is '
                'held until they approve.',
                style: AppConstants.bodyStyle(
                  fontSize: 12,
                  color: AppConstants.secondary,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 14),

              // What is being reserved.
              ReservationProductRow(product: widget.product, color: _color),
              const SizedBox(height: 14),

              // Which variant — hidden on colourless products.
              if (colors.length > 1) ...[
                Text(
                  'Color',
                  style: AppConstants.bodyStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                ReservationColorChips(
                  colors: colors,
                  selected: _color,
                  onSelect: _selectColor,
                ),
                const SizedBox(height: 14),
              ],

              // Which sizes, and how many pairs of each.
              Text(
                'Sizes',
                style: AppConstants.bodyStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                'Set how many pairs you want per size. Sizes left at 0 are '
                'never requested.',
                style: AppConstants.bodyStyle(
                  fontSize: 11,
                  color: AppConstants.secondary.withValues(alpha: 0.65),
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 8),
              if (sizes.isEmpty)
                Text(
                  'No size of this ${colors.isEmpty ? 'product' : 'colour'} '
                  'is in stock right now.',
                  style: AppConstants.bodyStyle(
                    fontSize: 12,
                    color: AppConstants.error,
                  ),
                )
              else
                // A long size run must not push the CTA off screen.
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 216),
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        for (final entry in sizes)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _SizeRequestRow(
                              size: entry.key,
                              stock: entry.value,
                              pairs: _pairs[entry.key] ?? 0,
                              onStep: (delta) => _step(entry.key, delta),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

              // The bill of materials, in one line.
              const SizedBox(height: 4),
              Row(
                children: [
                  Text(
                    _totalPairs == 0
                        ? 'Total: pick at least one size'
                        : 'Total: $_totalPairs '
                            '${_totalPairs == 1 ? 'pair' : 'pairs'}',
                    style: AppConstants.bodyStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: _totalPairs == 0
                          ? AppConstants.secondary.withValues(alpha: 0.55)
                          : AppConstants.primary,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _totalStock > 0 ? '$_totalStock in stock' : 'Out of stock',
                    style: AppConstants.bodyStyle(
                      fontSize: 11,
                      color: _totalStock > 0
                          ? AppConstants.secondary.withValues(alpha: 0.6)
                          : AppConstants.error,
                    ),
                  ),
                ],
              ),

              // Same info-card slot as the pickup sheet's "FREE to reserve"
              // panel — here it carries the deposit instead.
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppConstants.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '20% GCash deposit if approved',
                      style: AppConstants.bodyStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppConstants.primary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _totalPairs == 0
                          ? 'Pick your sizes to see the deposit. It is 20% of '
                              'the estimated value, paid within 24 hours of '
                              'approval and non-refundable once confirmed.'
                          : 'About ₱${_depositEstimate.toStringAsFixed(0)} for '
                              '$_totalPairs '
                              '${_totalPairs == 1 ? 'pair' : 'pairs'} at '
                              '₱${price.toStringAsFixed(0)} each (₱'
                              '${_estimatedValue.toStringAsFixed(0)} total, final '
                              'price confirmed at pickup). Nothing is charged '
                              'now — pay within 24 hours of approval, '
                              'non-refundable once confirmed.',
                      style: AppConstants.bodyStyle(
                        fontSize: 12,
                        color: AppConstants.secondary.withValues(alpha: 0.8),
                        height: 1.3,
                      ),
                    ),
                  ],
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
      ),
    );
  }
}

/// One size line: the size, its live stock, and the pairs stepper.
class _SizeRequestRow extends StatelessWidget {
  final String size;
  final int stock;
  final int pairs;
  final ValueChanged<int> onStep;

  const _SizeRequestRow({
    required this.size,
    required this.stock,
    required this.pairs,
    required this.onStep,
  });

  @override
  Widget build(BuildContext context) {
    final selected = pairs > 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      decoration: BoxDecoration(
        color: selected
            ? AppConstants.primary.withValues(alpha: 0.06)
            : AppConstants.surfaceSubtle,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: selected
              ? AppConstants.primary.withValues(alpha: 0.5)
              : Colors.transparent,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  size,
                  style: AppConstants.bodyStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.bold : FontWeight.w600,
                    color: selected
                        ? AppConstants.primary
                        : AppConstants.secondary,
                  ),
                ),
                Text(
                  '$stock in stock',
                  style: AppConstants.bodyStyle(
                    fontSize: 10,
                    color: AppConstants.secondary.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          ReservationStepButton(
            icon: Icons.remove,
            onTap: pairs > 0 ? () => onStep(-1) : null,
          ),
          SizedBox(
            width: 36,
            child: Text(
              '$pairs',
              textAlign: TextAlign.center,
              style: AppConstants.bodyStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
          ReservationStepButton(
            icon: Icons.add,
            onTap: pairs < stock ? () => onStep(1) : null,
          ),
        ],
      ),
    );
  }
}
