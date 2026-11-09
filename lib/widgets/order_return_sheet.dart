import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../constants/app_constants.dart';
import 'sole_primary_button.dart';
import 'sole_card.dart';

/// Result data returned from the return-request flow.
class ReturnRequestResult {
  final String reason;
  final String? details;

  /// Local paths of the photo proofs the customer attached (1-4, mandatory).
  /// The caller uploads them and passes the storage paths to the return RPC.
  final List<String> proofFilePaths;

  const ReturnRequestResult({
    required this.reason,
    this.details,
    this.proofFilePaths = const [],
  });
}

/// Bottom sheet for selecting a return reason and optional details.
///
/// Returns a [ReturnRequestResult] if the user confirms, or null if cancelled.
/// Mirrors the cancellation sheet; the Terms summary is shown at the top so
/// the 7-day / unworn / buyer-pays-shipping rules are visible at the point
/// of request.
Future<ReturnRequestResult?> showReturnRequestSheet(BuildContext context) {
  return showModalBottomSheet<ReturnRequestResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _ReturnRequestSheet(),
  );
}

class _ReturnRequestSheet extends StatefulWidget {
  const _ReturnRequestSheet();

  @override
  State<_ReturnRequestSheet> createState() => _ReturnRequestSheetState();
}

class _ReturnRequestSheetState extends State<_ReturnRequestSheet> {
  /// Maximum return photo proofs per request (mirrors the RPC gate).
  static const int maxProofPhotos = 4;

  String? _selectedReason;
  final _detailsController = TextEditingController();
  final List<String> _proofFilePaths = [];
  bool _pickingProof = false;
  bool get _isOtherSelected => _selectedReason == 'Other';

  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
  }

  bool get _canSubmit {
    if (_selectedReason == null) return false;
    if (_proofFilePaths.isEmpty) return false;
    if (_isOtherSelected && _detailsController.text.trim().isEmpty) return false;
    return true;
  }

  void _submit() {
    if (!_canSubmit) return;
    Navigator.of(context).pop(
      ReturnRequestResult(
        reason: _selectedReason!,
        details: _isOtherSelected ? _detailsController.text.trim() : null,
        proofFilePaths: List.unmodifiable(_proofFilePaths),
      ),
    );
  }

  int get _proofSlotsLeft => maxProofPhotos - _proofFilePaths.length;

  /// Attach photo proofs (defect, wrong item, …) — gallery adds up to the
  /// remaining slots at once, camera adds one photo per shot.
  Future<void> _pickProofs(ImageSource source) async {
    if (_proofSlotsLeft <= 0) return;
    setState(() => _pickingProof = true);
    try {
      final picker = ImagePicker();
      if (source == ImageSource.gallery) {
        final picked = await picker.pickMultiImage(
          maxWidth: 1600,
          imageQuality: 85,
        );
        if (picked.isNotEmpty && mounted) {
          setState(() => _proofFilePaths.addAll(
                picked.take(_proofSlotsLeft).map((x) => x.path),
              ));
        }
      } else {
        final picked = await picker.pickImage(
          source: source,
          maxWidth: 1600,
          imageQuality: 85,
        );
        if (picked != null && mounted) {
          setState(() => _proofFilePaths.add(picked.path));
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open the camera/gallery.'),
            backgroundColor: AppConstants.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _pickingProof = false);
    }
  }

  void _chooseProofSource() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () {
                Navigator.of(ctx).pop();
                _pickProofs(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () {
                Navigator.of(ctx).pop();
                _pickProofs(ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: AppConstants.surfaceLight,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppConstants.borderGray,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Request a Return',
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
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'Unworn items with tags can be returned within ${AppConstants.returnWindowDays} days of delivery. '
                  'Refunds go to your original payment method within 5–7 business days after inspection. '
                  'You cover return shipping unless the item arrived defective or incorrect — contact us within '
                  '${AppConstants.defectiveReportWindowHours}h for those.',
                  style: AppConstants.bodyStyle(
                    fontSize: 12,
                    color: AppConstants.secondary.withValues(alpha: 0.6),
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: AppConstants.returnReasons.length,
                  itemBuilder: (context, index) {
                    final reason = AppConstants.returnReasons[index];
                    final isSelected = _selectedReason == reason;
                    final isOther = reason == 'Other';
                    return Column(
                      children: [
                        GestureDetector(
                          onTap: () =>
                              setState(() => _selectedReason = reason),
                          child: SoleCard(
                            color: isSelected
                                ? AppConstants.primary.withValues(alpha: 0.06)
                                : Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                            margin: EdgeInsets.zero,
                            border: Border.all(
                              color: isSelected
                                  ? AppConstants.primary.withValues(alpha: 0.4)
                                  : AppConstants.borderGray
                                      .withValues(alpha: 0.3),
                              width: isSelected ? 1.5 : 1,
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 20,
                                  height: 20,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isSelected
                                          ? AppConstants.primary
                                          : AppConstants.borderGray,
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
                                              color: AppConstants.primary,
                                            ),
                                          ),
                                        )
                                      : null,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    reason,
                                    style: AppConstants.bodyStyle(
                                      fontSize: 14,
                                      fontWeight: isSelected
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                      color: AppConstants.secondary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
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
                                color: AppConstants.secondary
                                    .withValues(alpha: 0.4),
                              ),
                              filled: true,
                              fillColor: AppConstants.surfaceLight,
                              contentPadding: const EdgeInsets.all(12),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(
                                  color: AppConstants.borderGray
                                      .withValues(alpha: 0.5),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(
                                  color: AppConstants.borderGray
                                      .withValues(alpha: 0.5),
                                ),
                              ),
                              focusedBorder: const OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.all(Radius.circular(10)),
                                borderSide: BorderSide(
                                  color: AppConstants.primary,
                                  width: 1.5,
                                ),
                              ),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 4),
                          if (_isOtherSelected &&
                              _detailsController.text.trim().isEmpty)
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
              // Photo proof — REQUIRED, 1-4 photos, so the seller can judge
              // the request (defect, wrong item, …) without a chat round-trip.
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: SoleCard(
                  color: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  margin: EdgeInsets.zero,
                  border: Border.all(
                    color: AppConstants.borderGray.withValues(alpha: 0.3),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Photo proof (required)',
                              style: AppConstants.bodyStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppConstants.secondary,
                              ),
                            ),
                          ),
                          Text(
                            '${_proofFilePaths.length}/$maxProofPhotos',
                            style: AppConstants.bodyStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _proofFilePaths.isEmpty
                                  ? AppConstants.error
                                  : AppConstants.secondary
                                      .withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Add 1–4 photos of the defect or wrong item — the seller needs to see it to approve.',
                        style: AppConstants.bodyStyle(
                          fontSize: 12,
                          color:
                              AppConstants.secondary.withValues(alpha: 0.6),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (int i = 0; i < _proofFilePaths.length; i++)
                            Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.file(
                                    File(_proofFilePaths[i]),
                                    width: 64,
                                    height: 64,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => Container(
                                      width: 64,
                                      height: 64,
                                      color: AppConstants.borderGray
                                          .withValues(alpha: 0.2),
                                      child: const Icon(
                                        Icons.image_not_supported_outlined,
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  right: 2,
                                  top: 2,
                                  child: GestureDetector(
                                    onTap: () => setState(
                                        () => _proofFilePaths.removeAt(i)),
                                    child: Container(
                                      padding: const EdgeInsets.all(3),
                                      decoration: const BoxDecoration(
                                        color: AppConstants.error,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.close,
                                        size: 12,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          if (_proofSlotsLeft > 0)
                            GestureDetector(
                              onTap: _pickingProof ? null : _chooseProofSource,
                              child: Container(
                                width: 64,
                                height: 64,
                                decoration: BoxDecoration(
                                  color: AppConstants.primary
                                      .withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: AppConstants.primary
                                        .withValues(alpha: 0.3),
                                  ),
                                ),
                                child: _pickingProof
                                    ? const Padding(
                                        padding: EdgeInsets.all(20),
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.add_a_photo_outlined,
                                        color: AppConstants.primary,
                                      ),
                              ),
                            ),
                        ],
                      ),
                      if (_proofFilePaths.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            'At least 1 photo is required to submit.',
                            style: AppConstants.bodyStyle(
                              fontSize: 11,
                              color: AppConstants.error,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Container(
                padding: EdgeInsets.fromLTRB(
                  20,
                  12,
                  20,
                  12 + MediaQuery.of(context).padding.bottom,
                ),
                decoration: BoxDecoration(
                  color: AppConstants.surfaceLight,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 12,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                child: SolePrimaryButton(
                  label: 'Submit Return Request',
                  onPressed: _canSubmit ? _submit : null,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
