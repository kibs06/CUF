import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../constants/app_constants.dart';

/// Flat, universal stock cap per size. UI-layer only — a predictable limit
/// for sellers; no DB CHECK constraint (the schema's `stock >= 0` guard is
/// untouched). Shared by `_showStockEditor` and every row so the `+` button,
/// the inline field, and the sheet all agree.
const int kMaxStockPerSize = 99;

/// Per-size stock stepper row inside the Adjust Stock bottom sheet.
///
/// REDESIGN NOTES (Aug 2026):
/// - Filled warm-brown stepper buttons (44×44 hit targets) instead of thin
///   outlined circles.
/// - Stock-state color coding matching the grid's badges: healthy = green,
///   low (≤ [lowStockThreshold]) = amber, zero = urgent red. The count text
///   and number field carry the color (the old progress bar is gone).
/// - Flat universal cap of [kMaxStockPerSize] per size — the `+` button
///   disables at the cap and typed values above it are clamped with an
///   inline "Max 99 per size" message (UI-layer clamp only; no DB constraint).
/// - Tap the number to type an exact value inline (clamped to
///   [0, kMaxStockPerSize]) — the field's controller is owned by this State
///   (created once in [State.initState], disposed in [State.dispose]) so
///   keyboard dismissal / sheet teardown can never touch a dead controller.
/// - Scale pulse on every +/- tap for immediate feedback.
///
/// CONFIRM-TO-SAVE MODEL: edits are staged LOCALLY only. +/− taps and typed
/// values update this row's [currentStock]-seeded local value and immediately
/// notify the parent through [onStockChanged] — the parent owns the dirty
/// flag and does the single Supabase write when the sheet's Confirm button is
/// tapped. There is deliberately NO debounce and NO per-tap write here: the
/// old 800ms autosave timer (which could fire after the row was disposed and
/// was the crash source behind the "TextEditingController used after being
/// disposed" bug) has been removed entirely.
class SellerInventoryRow extends StatefulWidget {
  final String productName;
  final String size;
  final int currentStock;
  final int maxStock;
  final ValueChanged<int> onStockChanged;

  const SellerInventoryRow({
    super.key,
    required this.productName,
    required this.size,
    required this.currentStock,
    required this.maxStock,
    required this.onStockChanged,
  });

  @override
  State<SellerInventoryRow> createState() => _SellerInventoryRowState();
}

class _SellerInventoryRowState extends State<SellerInventoryRow>
    with SingleTickerProviderStateMixin {
  /// Matches the low-stock threshold used by the Manage Products "Low Stock"
  /// filter and `ProductService._syncInventoryFromVariants` (stock ≤ 5).
  static const int lowStockThreshold = 5;

  late int _stock;

  // Owned by this State for the row's full lifetime — created once in
  // initState, disposed in dispose. A controller/focus recreated per-build
  // (or owned by a dialog that pops while the exit animation still holds
  // listeners) is what produced the "TextEditingController used after being
  // disposed" crash; never reintroduce that pattern.
  late final TextEditingController _stockController;
  late final FocusNode _stockFocus;

  Timer? _clampMessageTimer;
  bool _showClampMessage = false;

  late final AnimationController _pulseController;
  late final Animation<double> _pulseScale;

  @override
  void initState() {
    super.initState();
    _stock = widget.currentStock;
    _stockController = TextEditingController(text: '$_stock');
    _stockFocus = FocusNode();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
    );
    // Quick dip-and-recover so a tap reads as immediate feedback.
    _pulseScale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.82), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 0.82, end: 1.0), weight: 60),
    ]).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _clampMessageTimer?.cancel();
    _stockController.dispose();
    _stockFocus.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  /// Keep the field in sync if the parent ever pushes a new stock value
  /// (e.g. after Confirm succeeded and the sheet rebuilt). Only touches the
  /// controller while this row is still alive.
  @override
  void didUpdateWidget(SellerInventoryRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentStock != widget.currentStock &&
        widget.currentStock != _stock &&
        !_stockFocus.hasFocus) {
      _stock = widget.currentStock;
      _stockController.text = '$_stock';
    }
  }

  // ─── STOCK STATE ───────────────────────────────────────────────

  bool get _isZero => _stock <= 0;
  bool get _isLow => !_isZero && _stock <= lowStockThreshold;

  /// Row accent color by stock state — mirrors the Manage Products grid's
  /// stock badges: healthy = safe green, low (≤5) = amber, zero = urgent red.
  Color get _stockColor {
    if (_isZero) return AppConstants.lowStockColor;
    if (_isLow) return AppConstants.statusPendingColor;
    return AppConstants.okStockColor;
  }

  // ─── MUTATIONS ─────────────────────────────────────────────────

  /// Single local mutation path shared by the +/− steppers and the inline
  /// field. Clamps to [0, widget.maxStock], updates local state, then
  /// notifies the parent SYNCHRONOUSLY so the sheet can track dirty state.
  /// No timer, no write — the sheet's Confirm button persists everything.
  void _setStock(int newStock) {
    final clamped = newStock.clamp(0, widget.maxStock);
    setState(() {
      _stock = clamped;
    });
    // Keep the field's text in sync with the steppers, but never clobber a
    // value the seller is actively typing.
    if (!_stockFocus.hasFocus) {
      _stockController.text = '$clamped';
    }

    // Synchronous parent notification (ValueChanged<int>). Safe after
    // dispose? This is only ever called from a live tap/submit handler while
    // the sheet is mounted, so the parent is guaranteed alive here.
    widget.onStockChanged(clamped);
  }

  void _changeStock(int delta) {
    _pulse();
    _setStock(_stock + delta);
  }

  void _pulse() => _pulseController.forward(from: 0);

  /// Commit what the seller typed in the inline field: parse → clamp to
  /// [0, widget.maxStock] → surface "Max 99 per size" when the cap was hit →
  /// go through the identical local-mutation path. Empty or unparseable
  /// input just reverts the field to the current count.
  void _commitField() {
    final text = _stockController.text.trim();
    if (text.isEmpty) {
      _stockController.text = '$_stock';
      return;
    }
    var value = int.tryParse(text) ?? _stock;
    if (value > widget.maxStock) {
      value = widget.maxStock;
      _flashClampMessage();
    }
    _stockController.text = '$value';
    if (value != _stock) {
      _setStock(value);
    }
  }

  void _flashClampMessage() {
    _clampMessageTimer?.cancel();
    if (mounted) setState(() => _showClampMessage = true);
    _clampMessageTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _showClampMessage = false);
    });
  }

  // ─── BUILD ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: AppConstants.sellerCardBg,
        borderRadius: BorderRadius.circular(12),
        boxShadow: AppConstants.sellerShadow,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${widget.productName}  ·  Size ${widget.size}',
            style: AppConstants.bodyStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: AppConstants.secondary,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        '$_stock / ${widget.maxStock} units',
                        overflow: TextOverflow.ellipsis,
                        style: AppConstants.bodyStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppConstants.secondary.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                    if (_isZero) ...[
                      const SizedBox(width: 6),
                      _buildStateChip('Out of stock', AppConstants.lowStockColor),
                    ] else if (_isLow) ...[
                      const SizedBox(width: 6),
                      _buildStateChip('Low', AppConstants.statusPendingColor),
                    ],
                  ],
                ),
              ),
              _buildStepperButton(
                icon: Icons.remove,
                enabled: _stock > 0,
                label: 'Decrease stock for size ${widget.size}',
                onTap: () => _changeStock(-1),
              ),
              const SizedBox(width: 6),
              _buildStockField(),
              const SizedBox(width: 6),
              _buildStepperButton(
                icon: Icons.add,
                enabled: _stock < widget.maxStock,
                label: 'Increase stock for size ${widget.size}',
                onTap: () => _changeStock(1),
              ),
            ],
          ),
          if (_showClampMessage) ...[
            const SizedBox(height: 6),
            Text(
              'Max ${widget.maxStock} per size',
              style: AppConstants.bodyStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppConstants.statusPendingColor,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Inline number field — tap to type an exact count, commit on submit or
  /// focus loss. Styled by stock state so the count itself communicates
  /// health at a glance (the progress bar's job in the old design). The
  /// controller/focus are State-owned (see initState/dispose) so keyboard
  /// dismissal or sheet teardown can never hit a disposed controller.
  Widget _buildStockField() {
    return Semantics(
      textField: true,
      label: 'Stock for size ${widget.size}: $_stock. Tap to edit',
      child: SizedBox(
        width: 64,
        child: TextField(
          controller: _stockController,
          focusNode: _stockFocus,
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          textInputAction: TextInputAction.done,
          style: AppConstants.monoStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: _stockColor,
          ),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: _stockColor.withValues(alpha: 0.08),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: _stockColor.withValues(alpha: 0.35),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: _stockColor.withValues(alpha: 0.35),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: _stockColor,
                width: 1.5,
              ),
            ),
          ),
          onSubmitted: (_) {
            _commitField();
            _stockFocus.unfocus();
          },
          onTapOutside: (_) {
            _commitField();
            _stockFocus.unfocus();
          },
        ),
      ),
    );
  }

  /// Filled stepper button — warm dark-brown brand accent, white icon,
  /// 44×44 hit target (WCAG-compliant), grayed + disabled at the floor/cap.
  /// The pulse scales only the visual circle, so the hit target stays 44px.
  Widget _buildStepperButton({
    required IconData icon,
    required bool enabled,
    required String label,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: enabled ? label : null,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: enabled ? onTap : null,
            child: ScaleTransition(
              scale: _pulseScale,
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: enabled
                      ? AppConstants.primary
                      : AppConstants.borderGray.withValues(alpha: 0.4),
                  boxShadow: enabled
                      ? [
                          BoxShadow(
                            color:
                                AppConstants.primary.withValues(alpha: 0.35),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: enabled ? Colors.white : Colors.white60,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStateChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: AppConstants.bodyStyle(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}
