import 'package:flutter/material.dart';
import '../constants/app_constants.dart';
import 'sole_primary_button.dart';
import 'sole_card.dart';

/// Result data returned from the cancellation flow.
class CancellationResult {
  final String reason;
  final String? details;

  const CancellationResult({required this.reason, this.details});
}

/// Bottom sheet for selecting a cancellation reason and optional details.
///
/// Returns a [CancellationResult] if the user confirms, or null if cancelled.
Future<CancellationResult?> showCancellationSheet(BuildContext context) {
  return showModalBottomSheet<CancellationResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _CancellationSheet(),
  );
}

class _CancellationSheet extends StatefulWidget {
  const _CancellationSheet();

  @override
  State<_CancellationSheet> createState() => _CancellationSheetState();
}

class _CancellationSheetState extends State<_CancellationSheet> {
  String? _selectedReason;
  final _detailsController = TextEditingController();
  bool _isOtherSelected = false;

  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
  }

  bool get _canSubmit {
    if (_selectedReason == null) return false;
    if (_isOtherSelected && _detailsController.text.trim().isEmpty) return false;
    return true;
  }

  void _submit() {
    if (!_canSubmit) return;
    Navigator.of(context).pop(
      CancellationResult(
        reason: _selectedReason!,
        details: _isOtherSelected ? _detailsController.text.trim() : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppConstants.surfaceLight,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppConstants.borderGray,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Cancel Order',
                        style: AppConstants.headlineStyle(fontSize: 20),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 22),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              // Subtitle
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'Please select a reason for cancellation.',
                  style: AppConstants.bodyStyle(
                    fontSize: 13,
                    color: AppConstants.secondary.withValues(alpha: 0.6),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Reasons list
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: AppConstants.cancellationReasons.length,
                  itemBuilder: (context, index) {
                    final reason = AppConstants.cancellationReasons[index];
                    final isSelected = _selectedReason == reason;
                    final isOther = reason == 'Other';

                    return Column(
                      children: [
                        _ReasonOption(
                          reason: reason,
                          isSelected: isSelected,
                          onTap: () {
                            setState(() {
                              _selectedReason = reason;
                              _isOtherSelected = isOther;
                            });
                          },
                        ),
                        // Show free-text field when "Other" is selected
                        if (isOther && isSelected) ...[
                          const SizedBox(height: 8),
                          TextField(
                            controller: _detailsController,
                            maxLines: 3,
                            minLines: 2,
                            decoration: InputDecoration(
                              hintText: 'Please provide details...',
                              hintStyle: AppConstants.bodyStyle(
                                fontSize: 13,
                                color: AppConstants.secondary.withValues(alpha: 0.4),
                              ),
                              filled: true,
                              fillColor: Colors.white,
                              contentPadding: const EdgeInsets.all(12),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(
                                  color: AppConstants.borderGray.withValues(alpha: 0.5),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(
                                  color: AppConstants.borderGray.withValues(alpha: 0.5),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(
                                  color: AppConstants.primary,
                                  width: 1.5,
                                ),
                              ),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 4),
                          if (_isOtherSelected && _detailsController.text.trim().isEmpty)
                            Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: Text(
                                'Required when "Other" is selected',
                                style: AppConstants.bodyStyle(
                                  fontSize: 11,
                                  color: AppConstants.error,
                                ),
                              ),
                            ),
                        ],
                        const SizedBox(height: 4),
                      ],
                    );
                  },
                ),
              ),

              // Submit button
              Container(
                padding: EdgeInsets.fromLTRB(
                  20,
                  12,
                  20,
                  12 + MediaQuery.of(context).padding.bottom,
                ),
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
                child: SolePrimaryButton(
                  label: 'Submit Cancellation',
                  onPressed: _canSubmit ? _submit : null,
                  backgroundColor: AppConstants.error,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Single selectable reason option.
class _ReasonOption extends StatelessWidget {
  final String reason;
  final bool isSelected;
  final VoidCallback onTap;

  const _ReasonOption({
    required this.reason,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SoleCard(
        color: isSelected
            ? AppConstants.error.withValues(alpha: 0.05)
            : Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        margin: EdgeInsets.zero,
        border: Border.all(
          color: isSelected
              ? AppConstants.error.withValues(alpha: 0.3)
              : AppConstants.borderGray.withValues(alpha: 0.3),
          width: isSelected ? 1.5 : 1,
        ),
        child: Row(
          children: [
            // Radio indicator
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? AppConstants.error : AppConstants.borderGray,
                  width: 1.5,
                ),
              ),
              child: isSelected
                  ? Center(
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppConstants.error,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            // Reason text
            Expanded(
              child: Text(
                reason,
                style: AppConstants.bodyStyle(
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: AppConstants.secondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
