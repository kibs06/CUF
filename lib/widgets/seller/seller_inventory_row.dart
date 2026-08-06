import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../constants/app_constants.dart';

/// Per-size stock stepper row inside the Adjust Stock bottom sheet.
///
/// VISUAL REDESIGN NOTES (Aug 2026):
/// - Filled warm-brown stepper buttons (44×44 hit targets) instead of thin
///   outlined circles.
/// - Stock-state color coding matching the grid's badges: healthy = green,
///   low (≤ [lowStockThreshold]) = amber, zero = urgent red.
/// - Threshold-aware progress bar: an amber "danger zone" spans the low-stock
///   cutoff so the seller sees at a glance which sizes need restocking.
/// - Tap the number to type an exact value (clamped to [0, maxStock]).
/// - Scale pulse on every +/- tap + a fading "saved" checkmark.
///
/// THE WRITE CONTRACT IS UNCHANGED: every edit (stepper or typed) funnels
/// through the same 800ms-debounced [onStockChanged] callback — the parent
/// owns all Supabase writes. Do not add any DB call here.
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
  bool _isSaving = false;
  bool _saved = false;

  late final AnimationController _pulseController;
  late final Animation<double> _pulseScale;

  @override
  void initState() {
    super.initState();
    _stock = widget.currentStock;
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
    );
    // Quick dip-and-recover so a tap reads as immediate feedback before the
    // debounced save fires.
    _pulseScale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.82), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 0.82, end: 1.0), weight: 60),
    ]).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
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

  /// Single mutation path shared by the +/− steppers and the tap-to-edit
  /// field. Clamps to [0, maxStock] and schedules the SAME 800ms debounce —
  /// write behavior is byte-for-byte identical to the previous inline logic.
  void _setStock(int newStock) {
    final clamped = newStock.clamp(0, widget.maxStock);
    setState(() {
      _stock = clamped;
      _isSaving = true;
      _saved = false;
    });

    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _saved = true;
        });
      }
      // Fire the change even if this row was disposed (e.g. the sheet was
      // closed right after tapping). Dropping it here would silently lose
      // the seller's restock — the parent decides what to do with it.
      widget.onStockChanged(_stock);
      if (mounted) {
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) {
            setState(() => _saved = false);
          }
        });
      }
    });
  }

  void _changeStock(int delta) {
    _pulse();
    _setStock(_stock + delta);
  }

  void _pulse() => _pulseController.forward(from: 0);

  /// Tap-to-edit: type an exact count (clamped to [0, maxStock]) then
  /// confirm — goes through the identical debounced [onStockChanged] path.
  Future<void> _openDirectEditor() async {
    final controller = TextEditingController(text: '$_stock');
    final entered = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Set stock — Size ${widget.size}',
          style: AppConstants.bodyStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: AppConstants.monoStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
          decoration: InputDecoration(
            labelText: 'Units',
            hintText: '0 – ${widget.maxStock}',
            border: const OutlineInputBorder(),
          ),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => Navigator.of(ctx)
              .pop(int.tryParse(controller.text.trim())),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Cancel',
              style: AppConstants.bodyStyle(color: AppConstants.secondary),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppConstants.primary),
            onPressed: () =>
                Navigator.of(ctx).pop(int.tryParse(controller.text.trim())),
            child: Text(
              'Save',
              style: AppConstants.bodyStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
    controller.dispose();
    if (entered == null || !mounted) return;
    _setStock(entered.clamp(0, widget.maxStock));
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
          _buildProgressBar(),
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
              _buildNumberEditor(),
              const SizedBox(width: 6),
              _buildStepperButton(
                icon: Icons.add,
                enabled: _stock < widget.maxStock,
                label: 'Increase stock for size ${widget.size}',
                onTap: () => _changeStock(1),
              ),
              const SizedBox(width: 10),
              _buildStatusIndicator(),
            ],
          ),
        ],
      ),
    );
  }

  /// Progress bar with an amber "danger zone" under the low-stock cutoff, a
  /// stock-state-colored fill, and a tick at the threshold — communicates the
  /// restock threshold at a glance instead of just a percentage.
  Widget _buildProgressBar() {
    final maxStock = widget.maxStock > 0 ? widget.maxStock : 1;
    final stockFrac = (_stock / maxStock).clamp(0.0, 1.0);
    final thresholdFrac = (lowStockThreshold / maxStock).clamp(0.0, 1.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 8,
            width: width,
            child: Stack(
              children: [
                // Track
                Positioned.fill(
                  child: Container(
                    color: AppConstants.borderGray.withValues(alpha: 0.3),
                  ),
                ),
                // Amber danger zone (0 → low-stock threshold)
                if (thresholdFrac > 0)
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: width * thresholdFrac,
                    child: Container(
                      color: AppConstants.statusPendingColor
                          .withValues(alpha: 0.18),
                    ),
                  ),
                // Actual stock fill
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: width * stockFrac,
                  child: Container(color: _stockColor),
                ),
                // Threshold tick marker
                if (thresholdFrac > 0 && thresholdFrac < 1)
                  Positioned(
                    left: (width * thresholdFrac) - 1,
                    top: 0,
                    bottom: 0,
                    width: 2,
                    child: Container(
                      color: AppConstants.statusPendingColor
                          .withValues(alpha: 0.55),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
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

  /// Tappable number chip — opens the direct-entry dialog on tap. Colored by
  /// stock state so the count itself communicates health at a glance.
  Widget _buildNumberEditor() {
    return Semantics(
      button: true,
      label: 'Stock for size ${widget.size}: $_stock. Tap to edit',
      child: InkWell(
        onTap: _openDirectEditor,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          // Min-width so the tap area is comfortable; grows for large counts.
          constraints: const BoxConstraints(minWidth: 52),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: _stockColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _stockColor.withValues(alpha: 0.35)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$_stock',
                style: AppConstants.monoStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: _stockColor,
                ),
              ),
              Text(
                'edit',
                style: AppConstants.bodyStyle(
                  fontSize: 8,
                  color: AppConstants.secondary.withValues(alpha: 0.45),
                ),
              ),
            ],
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

  /// Saving spinner → fading "saved" checkmark (same debounce-driven signal
  /// as before, now animated). No new save path — purely visual feedback.
  Widget _buildStatusIndicator() {
    return SizedBox(
      width: 18,
      height: 18,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: _isSaving
            ? const SizedBox(
                key: ValueKey('saving'),
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppConstants.accent,
                ),
              )
            : _saved
                ? const Icon(
                    Icons.check_circle,
                    key: ValueKey('saved'),
                    size: 16,
                    color: AppConstants.okStockColor,
                  )
                : const SizedBox.shrink(key: ValueKey('idle')),
      ),
    );
  }
}
