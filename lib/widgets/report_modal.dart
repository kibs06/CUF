import 'package:flutter/material.dart';
import '../constants/app_constants.dart';
import '../services/report_service.dart';

/// Shared report submission modal used across all 4 report types.
/// Categories use machine keys (e.g. "spam_scam") as stored values.
/// Returns true if a report was successfully submitted.
Future<bool> showReportModal(
  BuildContext context, {
  required String reportType, // 'message' | 'product' | 'seller' | 'other'
  required String reporterRole, // 'customer' | 'seller'
  String? title,
  String? contextPreview, // Read-only preview of what's being reported
  String? targetMessageId,
  int? targetOrderId,
  String? targetSellerId,
  String? targetStoreId,
  String? targetProductId,
  String? conversationId,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _ReportModalSheet(
      reportType: reportType,
      reporterRole: reporterRole,
      title: title,
      contextPreview: contextPreview,
      targetMessageId: targetMessageId,
      targetOrderId: targetOrderId,
      targetSellerId: targetSellerId,
      targetStoreId: targetStoreId,
      targetProductId: targetProductId,
      conversationId: conversationId,
    ),
  );
  return result ?? false;
}

class _ReportModalSheet extends StatefulWidget {
  final String reportType;
  final String reporterRole;
  final String? title;
  final String? contextPreview;
  final String? targetMessageId;
  final int? targetOrderId;
  final String? targetSellerId;
  final String? targetStoreId;
  final String? targetProductId;
  final String? conversationId;

  const _ReportModalSheet({
    required this.reportType,
    required this.reporterRole,
    this.title,
    this.contextPreview,
    this.targetMessageId,
    this.targetOrderId,
    this.targetSellerId,
    this.targetStoreId,
    this.targetProductId,
    this.conversationId,
  });

  @override
  State<_ReportModalSheet> createState() => _ReportModalSheetState();
}

class _ReportModalSheetState extends State<_ReportModalSheet> {
  String? _selectedCategory; // machine key
  bool _isSubmitting = false;
  String? _errorMessage;
  bool _isDuplicate = false;

  // Custom details (only for 'other' category)
  final _customDetailsController = TextEditingController();
  String? _customDetailsError;
  static const int _maxCustomChars = 500;
  static const int _minCustomChars = 10;

  String get _modalTitle {
    if (widget.title != null) return widget.title!;
    switch (widget.reportType) {
      case 'message':
        return 'Report Message';
      case 'product':
        return 'Report Product Issue';
      case 'seller':
        return 'Report Seller';
      case 'other':
        return 'Report a Problem';
      default:
        return 'Report';
    }
  }

  IconData get _typeIcon {
    switch (widget.reportType) {
      case 'message':
        return Icons.chat_bubble_outline;
      case 'product':
        return Icons.shopping_bag_outlined;
      case 'seller':
        return Icons.storefront_outlined;
      case 'other':
        return Icons.help_outline;
      default:
        return Icons.flag_outlined;
    }
  }

  /// Get categories for this report type as [machineKey, displayLabel] pairs.
  /// Filters out 'buyer_misuse' for customer reporters (seller-filed only).
  List<MapEntry<String, String>> get _categories {
    final cats = ReportService.categoriesForType(widget.reportType);
    if (widget.reporterRole == 'customer') {
      return cats.where((e) => e.key != 'buyer_misuse').toList();
    }
    return cats;
  }

  bool get _isOtherSelected => _selectedCategory == 'other';

  bool get _canSubmit {
    if (_selectedCategory == null) return false;
    if (_isOtherSelected) {
      final text = _customDetailsController.text.trim();
      return text.length >= _minCustomChars;
    }
    return true;
  }

  @override
  void dispose() {
    _customDetailsController.dispose();
    super.dispose();
  }

  void _validateCustomDetails() {
    final text = _customDetailsController.text;
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      setState(() => _customDetailsError = null); // empty is ok until submit
    } else if (trimmed.length < _minCustomChars) {
      setState(() => _customDetailsError = 'Please add a few more details (min 10 characters).');
    } else {
      setState(() => _customDetailsError = null);
    }
  }

  Future<void> _submit() async {
    if (!_canSubmit || _isSubmitting) return;

    // Final validation for 'other'
    if (_isOtherSelected) {
      final trimmed = _customDetailsController.text.trim();
      if (trimmed.length < _minCustomChars) {
        setState(() => _customDetailsError = 'Please add a few more details (min 10 characters).');
        return;
      }
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
      _customDetailsError = null;
    });

    try {
      await ReportService.instance.submitReport(
        reporterRole: widget.reporterRole,
        type: widget.reportType,
        category: _selectedCategory!,
        customDetails: _isOtherSelected ? _customDetailsController.text.trim() : null,
        targetMessageId: widget.targetMessageId,
        targetOrderId: widget.targetOrderId,
        targetSellerId: widget.targetSellerId,
        targetStoreId: widget.targetStoreId,
        targetProductId: widget.targetProductId,
        conversationId: widget.conversationId,
      );

      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Report submitted. Our team will review it.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString();
        if (msg.contains('duplicate_report')) {
          setState(() {
            _isDuplicate = true;
            _isSubmitting = false;
          });
        } else {
          setState(() {
            _errorMessage = msg.replaceAll('Exception: ', '');
            _isSubmitting = false;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // ── Handle bar ─────────────────────────────────────
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppConstants.secondary.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // ── Fixed Header ───────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                Icon(_typeIcon, color: AppConstants.primary, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _modalTitle,
                    style: AppConstants.bodyStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppConstants.secondary,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 22),
                  onPressed: () => Navigator.of(context).pop(false),
                  color: AppConstants.secondary,
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFF0EBE6)),

          // ── Scrollable Body ────────────────────────────────
          Expanded(
            child: _isDuplicate
                ? _buildDuplicateState()
                : ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    children: [
                      // Context preview (read-only)
                      if (widget.contextPreview != null) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppConstants.surfaceLight,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: AppConstants.secondary.withValues(alpha: 0.1),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Reported content',
                                style: AppConstants.bodyStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppConstants.secondary.withValues(alpha: 0.6),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                widget.contextPreview!,
                                style: AppConstants.bodyStyle(
                                  fontSize: 13,
                                  color: AppConstants.secondary,
                                ),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],

                      // Category selection
                      Text(
                        'Why are you reporting this?',
                        style: AppConstants.bodyStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppConstants.secondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ..._categories.map((entry) {
                        final machineKey = entry.key;
                        final displayLabel = entry.value;
                        final isSelected = _selectedCategory == machineKey;
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedCategory = machineKey;
                              _errorMessage = null;
                              // Clear custom details when switching away from 'other'
                              if (machineKey != 'other') {
                                _customDetailsController.clear();
                                _customDetailsError = null;
                              }
                            });
                          },
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppConstants.primary.withValues(alpha: 0.08)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isSelected
                                    ? AppConstants.primary
                                    : AppConstants.secondary.withValues(alpha: 0.15),
                                width: isSelected ? 1.5 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  isSelected
                                      ? Icons.radio_button_checked
                                      : Icons.radio_button_off,
                                  size: 20,
                                  color: isSelected
                                      ? AppConstants.primary
                                      : AppConstants.secondary.withValues(alpha: 0.4),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    displayLabel,
                                    style: AppConstants.bodyStyle(
                                      fontSize: 14,
                                      color: isSelected
                                          ? AppConstants.primary
                                          : AppConstants.secondary,
                                      fontWeight:
                                          isSelected ? FontWeight.w600 : FontWeight.normal,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),

                      // Custom details textarea (only when 'other' is selected)
                      if (_isOtherSelected) ...[
                        const SizedBox(height: 4),
                        TextField(
                          controller: _customDetailsController,
                          maxLines: 4,
                          minLines: 3,
                          maxLength: _maxCustomChars,
                          textCapitalization: TextCapitalization.sentences,
                          onChanged: (_) => _validateCustomDetails(),
                          style: AppConstants.bodyStyle(fontSize: 14),
                          decoration: InputDecoration(
                            hintText: 'Please describe the issue...',
                            hintStyle: AppConstants.bodyStyle(
                              fontSize: 14,
                              color: AppConstants.secondary.withValues(alpha: 0.4),
                            ),
                            filled: true,
                            fillColor: AppConstants.surfaceLight,
                            contentPadding: const EdgeInsets.all(12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(
                                color: _customDetailsError != null
                                    ? AppConstants.error
                                    : AppConstants.secondary.withValues(alpha: 0.15),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(
                                color: _customDetailsError != null
                                    ? AppConstants.error
                                    : AppConstants.secondary.withValues(alpha: 0.15),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(
                                color: _customDetailsError != null
                                    ? AppConstants.error
                                    : AppConstants.primary,
                              ),
                            ),
                            counterText: '',
                          ),
                        ),
                        // Character counter + validation hint
                        if (_customDetailsController.text.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              if (_customDetailsError != null)
                                Expanded(
                                  child: Text(
                                    _customDetailsError!,
                                    style: AppConstants.bodyStyle(
                                      fontSize: 12,
                                      color: AppConstants.error,
                                    ),
                                  ),
                                ),
                              Text(
                                '${_customDetailsController.text.length}/$_maxCustomChars',
                                style: AppConstants.bodyStyle(
                                  fontSize: 12,
                                  color: _customDetailsController.text.length >= _minCustomChars
                                      ? AppConstants.success
                                      : AppConstants.secondary.withValues(alpha: 0.5),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],

                      // Error message
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _errorMessage!,
                          style: AppConstants.bodyStyle(
                            fontSize: 13,
                            color: AppConstants.error,
                          ),
                        ),
                      ],
                    ],
                  ),
          ),

          // ── Fixed Footer ───────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                top: BorderSide(
                  color: AppConstants.secondary.withValues(alpha: 0.1),
                ),
              ),
            ),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _canSubmit && !_isSubmitting ? _submit : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppConstants.primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor:
                      AppConstants.secondary.withValues(alpha: 0.15),
                  disabledForegroundColor:
                      AppConstants.secondary.withValues(alpha: 0.4),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 0,
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        'Submit Report',
                        style: AppConstants.bodyStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDuplicateState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 48,
              color: AppConstants.success,
            ),
            const SizedBox(height: 16),
            Text(
              "You've already reported this recently.",
              style: AppConstants.bodyStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppConstants.secondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Our team is reviewing it.',
              style: AppConstants.bodyStyle(
                fontSize: 14,
                color: AppConstants.secondary.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(false),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: AppConstants.primary),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(
                  'Close',
                  style: AppConstants.bodyStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppConstants.primary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
