import 'package:flutter/material.dart';

import '../../../constants/app_constants.dart';
import '../../../services/reservation_service.dart';
import '../../../services/voucher_service.dart';
import '../../../constants/bulk_buying.dart';
import '../../../constants/bulk_deposit.dart';
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
  VoucherService? voucherService,
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
      voucherService: voucherService,
    ),
  );
}

class _BulkReservationSheet extends StatefulWidget {
  final Map<String, dynamic> product;
  final Map<String, Map<String, int>> stockByColor;
  final String? initialColor;

  /// Injected in tests; defaults to the live service.
  final ReservationService? service;

  /// Injected in tests; defaults to the live voucher client (the same one
  /// checkout uses, so a code is priced by the same server RPC).
  final VoucherService? voucherService;

  const _BulkReservationSheet({
    required this.product,
    required this.stockByColor,
    this.initialColor,
    this.service,
    this.voucherService,
  });

  @override
  State<_BulkReservationSheet> createState() => _BulkReservationSheetState();
}

class _BulkReservationSheetState extends State<_BulkReservationSheet> {
  final _noteCtrl = TextEditingController();
  final _voucherCtrl = TextEditingController();
  late final ReservationService _service =
      widget.service ?? ReservationService.instance;
  late final VoucherService _vouchers =
      widget.voucherService ?? VoucherService();

  /// Pairs requested per size, for the SELECTED colour only (empty key = a
  /// product without colour variants). Sizes left at 0 are simply not sent —
  /// this replaced the old largest-stock-first auto-split, which guessed.
  final Map<String, int> _pairs = {};

  String _color = '';
  bool _submitting = false;
  String? _error;

  /// The last server quote for a voucher code (null until one is applied).
  VoucherQuote? _voucherQuote;
  String? _voucherError;
  bool _voucherBusy = false;

  List<String> get _colors => reservationColors(widget.stockByColor);

  /// The selected colour's {size: stock} — what can actually be requested.
  Map<String, int> get _sizes => widget.stockByColor[_color] ?? const {};

  int get _totalStock => _sizes.values.fold(0, (sum, s) => sum + s);

  int get _totalPairs => _pairs.values.fold(0, (sum, q) => sum + q);

  double get _estimatedValue => effectivePrice(widget.product) * _totalPairs;

  /// The voucher the server priced against this request, or null. Only a
  /// quote that actually took money off counts — the same rule checkout uses.
  VoucherQuote? get _appliedVoucher =>
      (_voucherQuote?.hasDiscount ?? false) ? _voucherQuote : null;

  double get _voucherDiscount => _appliedVoucher?.discountAmount ?? 0;

  /// What the customer is buying: pairs × price, less the voucher. The
  /// store honours this at pickup and the deposit is a share of it.
  double get _discountedValue =>
      (_estimatedValue - _voucherDiscount).clamp(0, double.infinity);

  /// Rounded UP to a whole peso, matching the server's rule at approval.
  double get _depositEstimate => bulkDepositFor(_discountedValue);

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
  ///
  /// The floor is [kBulkMinimumQuantity], not 1: below ten pairs this is an
  /// ordinary purchase, and the server refuses the request outright
  /// (`BULK_MINIMUM_QUANTITY`) rather than tying up stock for a single sale.
  bool get _isValid =>
      _totalPairs >= kBulkMinimumQuantity &&
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
    _voucherCtrl.dispose();
    super.dispose();
  }

  /// Asks the server what [code] is worth on this request.
  ///
  /// The quote is priced from the product and the pair count by
  /// `validate_voucher` (sale-aware, store-scoped, usage-capped), so the
  /// discount shown here is the one the request will carry — the client never
  /// computes it.
  Future<void> _applyVoucher() async {
    final code = _voucherCtrl.text.trim();
    if (code.isEmpty || _totalPairs < 1 || _voucherBusy) return;
    setState(() {
      _voucherBusy = true;
      _voucherError = null;
    });
    final quote = await _vouchers.validate(
      code: code,
      items: [
        {
          'product_id': widget.product['id'].toString(),
          'size': '',
          'quantity': _totalPairs,
        },
      ],
    );
    if (!mounted) return;
    setState(() {
      _voucherBusy = false;
      if (quote.hasDiscount) {
        _voucherQuote = quote;
        _voucherCtrl.text = quote.code;
      } else {
        _voucherQuote = null;
        _voucherError = quote.message.trim().isEmpty
            ? 'That code could not be applied.'
            : quote.message;
      }
    });
  }

  void _clearVoucher() {
    setState(() {
      _voucherQuote = null;
      _voucherError = null;
      _voucherCtrl.clear();
    });
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
      // The quote was priced on the old request; a discount carried over to a
      // different set of pairs would be a number nobody verified.
      _voucherQuote = null;
      _voucherError = null;
      _voucherCtrl.clear();
    });
  }

  void _step(String size, int delta) {
    final stock = _sizes[size] ?? 0;
    final next = (_pairs[size] ?? 0) + delta;
    if (next < 0 || next > stock) return;
    setState(() {
      _pairs[size] = next;
      // Same reason as the colour switch: the voucher was priced on the
      // previous pair count, so it is dropped rather than silently reused.
      _voucherQuote = null;
      _voucherError = null;
      _voucherCtrl.clear();
    });
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
        voucherCode: _appliedVoucher?.code,
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
    final storeName = (widget.product['store_name'] ?? '').toString().trim();
    final storeLabel = storeName.isEmpty ? 'the store' : storeName;
    // Sizes sorted numerically, the same order as the detail page's picker —
    // half sizes included, and unparseable keys last (plan §4.3).
    final sizes = _sizes.entries.toList()
      ..sort((a, b) => compareSizes(a.key, b.key));

    return Padding(
      // Keyboard inset so the sheet lifts above the note field.
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
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
                  'held until they approve. Bulk orders start at '
                  '$kBulkMinimumQuantity pairs.',
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
                  'never requested. A bulk hold needs at least '
                  '$kBulkMinimumQuantity pairs in total.',
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
                          ? 'Total: pick at least $kBulkMinimumQuantity pairs'
                          : _totalPairs < kBulkMinimumQuantity
                          ? 'Total: $_totalPairs of $kBulkMinimumQuantity '
                                'required'
                          : 'Total: $_totalPairs '
                                '${_totalPairs == 1 ? 'pair' : 'pairs'}',
                      style: AppConstants.bodyStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: _totalPairs == 0
                            ? AppConstants.secondary.withValues(alpha: 0.55)
                            : _totalPairs < kBulkMinimumQuantity
                            ? const Color(0xFFD97706)
                            : AppConstants.primary,
                      ),
                    ),
                    const Spacer(),
                    Text(
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
                  ],
                ),

                // How far the customer still is from the bulk floor — a disabled
                // button alone would not say what to change.
                if (_totalPairs > 0 && _totalPairs < kBulkMinimumQuantity)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Add ${kBulkMinimumQuantity - _totalPairs} more '
                      'pair${kBulkMinimumQuantity - _totalPairs == 1 ? '' : 's'} '
                      'to reach the $kBulkMinimumQuantity-pair bulk minimum.',
                      style: AppConstants.bodyStyle(
                        fontSize: 11,
                        color: const Color(0xFFD97706),
                      ),
                    ),
                  ),

                // ── Voucher ────────────────────────────────────────────
                // Priced by the server against THIS request (sale-aware,
                // store-scoped, usage-capped), so the discount shown is the one
                // the request will carry.
                const SizedBox(height: 10),
                if (_appliedVoucher != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppConstants.success.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.confirmation_number_outlined,
                          size: 16,
                          color: AppConstants.success,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${_appliedVoucher!.code} — '
                            '−₱${_voucherDiscount.toStringAsFixed(2)} off this '
                            'request',
                            style: AppConstants.bodyStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppConstants.success,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: _submitting ? null : _clearVoucher,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: const Size(44, 32),
                          ),
                          child: Text(
                            'Remove',
                            style: AppConstants.bodyStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppConstants.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _voucherCtrl,
                          textCapitalization: TextCapitalization.characters,
                          autocorrect: false,
                          enabled: _totalPairs >= 1 && !_voucherBusy,
                          style: AppConstants.bodyStyle(fontSize: 13),
                          decoration: InputDecoration(
                            hintText: _totalPairs >= 1
                                ? 'Voucher code (optional)'
                                : 'Pick sizes first, then apply a code',
                            hintStyle: AppConstants.bodyStyle(
                              fontSize: 12,
                              color: AppConstants.secondary.withValues(
                                alpha: 0.5,
                              ),
                            ),
                            isDense: true,
                            contentPadding: const EdgeInsets.all(12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: (_totalPairs >= 1 && !_voucherBusy)
                            ? _applyVoucher
                            : null,
                        child: _voucherBusy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Apply'),
                      ),
                    ],
                  ),
                if (_voucherError != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    _voucherError!,
                    style: AppConstants.bodyStyle(
                      fontSize: 11.5,
                      color: AppConstants.error,
                    ),
                  ),
                ],

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
                        '$kBulkReservationDepositLabel GCash deposit if '
                        'approved',
                        style: AppConstants.bodyStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppConstants.primary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _totalPairs == 0
                            ? 'Pick your sizes to see the deposit. It is '
                                  '$kBulkReservationDepositLabel of '
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
                      if (_appliedVoucher != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Voucher ${_appliedVoucher!.code} takes '
                          '₱${_voucherDiscount.toStringAsFixed(2)} off the price '
                          'at pickup, and the deposit is '
                          '$kBulkReservationDepositLabel of the discounted value.',
                          style: AppConstants.bodyStyle(
                            fontSize: 12,
                            color: AppConstants.secondary.withValues(
                              alpha: 0.8,
                            ),
                            height: 1.3,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Bulk buying has no shipping leg: the customer collects at the
                // store. Said here — before the request is sent — so nobody waits
                // for a courier this flow never had.
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.storefront_outlined,
                      size: 16,
                      color: AppConstants.primary.withValues(alpha: 0.8),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Pickup only — collect your units at $storeLabel. Bulk '
                        'orders are not shipped or delivered.',
                        style: AppConstants.bodyStyle(
                          fontSize: 11.5,
                          color: AppConstants.secondary.withValues(alpha: 0.8),
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
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
