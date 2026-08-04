import 'package:flutter/material.dart';
import '../constants/app_constants.dart';

/// A reusable bottom sheet showing a static EU/US/CM shoe size conversion chart.
///
/// Triggered from the product detail screen's size selector.
/// Uses a bottom sheet pattern consistent with the rest of the app.
class SizeGuideModal extends StatelessWidget {
  const SizeGuideModal({super.key});

  /// Show the size guide as a modal bottom sheet.
  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const SizeGuideModal(),
    );
  }

  // EU sizes 36–46 mapped to US men's and CM foot length
  static const List<_SizeEntry> _sizes = [
    _SizeEntry('36', '5', '23.0'),
    _SizeEntry('37', '6', '23.5'),
    _SizeEntry('38', '6.5', '24.0'),
    _SizeEntry('39', '7', '24.5'),
    _SizeEntry('40', '7.5', '25.0'),
    _SizeEntry('41', '8', '25.5'),
    _SizeEntry('42', '8.5', '26.0'),
    _SizeEntry('43', '9.5', '26.5'),
    _SizeEntry('44', '10', '27.0'),
    _SizeEntry('45', '11', '27.5'),
    _SizeEntry('46', '12', '28.0'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.65,
      ),
      decoration: const BoxDecoration(
        color: AppConstants.surfaceLight,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppConstants.borderGray,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Title
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
            child: Text(
              'Size Guide',
              style: AppConstants.headlineStyle(fontSize: 20),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
            child: Text(
              'Men\'s footwear — approximate conversions',
              style: AppConstants.bodyStyle(
                fontSize: 13,
                color: AppConstants.secondary.withValues(alpha: 0.5),
              ),
            ),
          ),
          // Table header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                _headerCell('EU', flex: 1),
                _headerCell('US (Men)', flex: 1),
                _headerCell('Foot Length (CM)', flex: 2),
              ],
            ),
          ),
          const SizedBox(height: 4),
          // Table rows
          Flexible(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              shrinkWrap: true,
              itemCount: _sizes.length,
              separatorBuilder: (_, __) => const Divider(
                height: 1,
                color: AppConstants.borderGray,
              ),
              itemBuilder: (context, index) {
                final entry = _sizes[index];
                final isEven = index.isEven;
                return Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: isEven
                        ? AppConstants.primary.withValues(alpha: 0.03)
                        : Colors.transparent,
                  ),
                  child: Row(
                    children: [
                      _dataCell(entry.eu, flex: 1),
                      _dataCell(entry.us, flex: 1),
                      _dataCell(entry.cm, flex: 2),
                    ],
                  ),
                );
              },
            ),
          ),
          // Footer note
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: AppConstants.borderGray.withValues(alpha: 0.3),
                ),
              ),
            ),
            child: Text(
              'Sizes may vary between brands. Visit a store for an exact fit.',
              style: AppConstants.bodyStyle(
                fontSize: 11,
                color: AppConstants.secondary.withValues(alpha: 0.45),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerCell(String label, {required int flex}) {
    return Expanded(
      flex: flex,
      child: Text(
        label,
        style: AppConstants.bodyStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: AppConstants.primary,
        ),
      ),
    );
  }

  Widget _dataCell(String value, {required int flex}) {
    return Expanded(
      flex: flex,
      child: Text(
        value,
        style: AppConstants.monoStyle(
          fontSize: 14,
          color: AppConstants.secondary,
        ),
      ),
    );
  }
}

class _SizeEntry {
  final String eu;
  final String us;
  final String cm;

  const _SizeEntry(this.eu, this.us, this.cm);
}