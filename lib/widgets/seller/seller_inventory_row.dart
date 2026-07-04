import 'package:flutter/material.dart';
import '../../constants/app_constants.dart';

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

class _SellerInventoryRowState extends State<SellerInventoryRow> {
  late int _stock;
  bool _isSaving = false;
  bool _saved = false;
  final int _maxStock = 20;

  @override
  void initState() {
    super.initState();
    _stock = widget.currentStock;
  }

  double get _stockPercent => (_stock / _maxStock).clamp(0.0, 1.0);

  Color get _stockColor {
    if (_stockPercent > 0.5) return AppConstants.okStockColor;
    if (_stockPercent > 0.1) return AppConstants.statusPendingColor;
    return AppConstants.lowStockColor;
  }

  void _changeStock(int delta) {
    final newStock = (_stock + delta).clamp(0, widget.maxStock);
    setState(() {
      _stock = newStock;
      _isSaving = true;
      _saved = false;
    });

    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _saved = true;
        });
        widget.onStockChanged(_stock);
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) {
            setState(() => _saved = false);
          }
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
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
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: _stockPercent,
                        backgroundColor: Colors.grey[200],
                        color: _stockColor,
                        minHeight: 4,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$_stock / $_maxStock units',
                      style: AppConstants.bodyStyle(fontSize: 11, color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Row(
                children: [
                  IconButton(
                    onPressed: _stock > 0 ? () => _changeStock(-1) : null,
                    icon: Icon(Icons.remove_circle_outline,
                      size: 20, color: _stock > 0 ? AppConstants.secondary : Colors.grey[300]),
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    padding: EdgeInsets.zero,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '$_stock',
                    style: AppConstants.monoStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: _stockColor,
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    onPressed:                     _stock < _maxStock ? () => _changeStock(1) : null,
                    icon: Icon(Icons.add_circle_outline,
                      size: 20, color:                       _stock < _maxStock ? AppConstants.accent : Colors.grey.shade300),
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    padding: EdgeInsets.zero,
                  ),
                ],
              ),
              const SizedBox(width: 8),
              if (_isSaving)
                SizedBox(
                  width: 12, height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppConstants.accent),
                )
              else if (_saved)
                const Icon(Icons.check_circle, size: 12, color: AppConstants.okStockColor),
            ],
          ),
        ],
      ),
    );
  }
}
