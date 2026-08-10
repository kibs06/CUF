import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import '../../constants/app_constants.dart';
import '../../constants/seller_theme_constants.dart';
import '../../services/store_service.dart';
import '../../utils/qr_image_crop.dart';
import '../../widgets/sole_primary_button.dart';

/// Seller-facing GCash payment setup — the static QR the customer scans at
/// POS checkout. Replaces the PayMongo dynamic-QR flow: the seller uploads
/// their own GCash "Receive Money" QR once, and POS simply displays it.
class GcashPaymentSettingsScreen extends StatefulWidget {
  const GcashPaymentSettingsScreen({super.key});

  @override
  State<GcashPaymentSettingsScreen> createState() =>
      _GcashPaymentSettingsScreenState();
}

class _GcashPaymentSettingsScreenState extends State<GcashPaymentSettingsScreen> {
  final StoreService _storeService = StoreService.instance;
  final ImagePicker _imagePicker = ImagePicker();

  Map<String, dynamic>? _store;
  bool _isLoadingStore = true;

  XFile? _newQrImage;
  bool _removeQr = false;
  bool _isSaving = false;
  bool _isAnalyzing = false;

  /// Fresh per screen-open. The QR is uploaded to a STABLE storage URL, so
  /// CachedNetworkImage would otherwise keep showing the previous (e.g.
  /// uncropped) image after a replacement.
  final String _cacheBustVersion =
      DateTime.now().millisecondsSinceEpoch.toString();

  final TextEditingController _accountNameController = TextEditingController();
  final TextEditingController _gcashNumberController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadStore();
  }

  @override
  void dispose() {
    _accountNameController.dispose();
    _gcashNumberController.dispose();
    super.dispose();
  }

  Future<void> _loadStore() async {
    setState(() => _isLoadingStore = true);
    try {
      final store = await _storeService.getMyStore();
      if (mounted) {
        setState(() {
          _store = store;
          _isLoadingStore = false;
          _accountNameController.text = store?['gcash_account_name'] ?? '';
          _gcashNumberController.text = store?['gcash_number'] ?? '';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingStore = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not load store settings: $e'),
            backgroundColor: AppConstants.error,
          ),
        );
      }
    }
  }

  String? get _currentQrUrl => _store?['gcash_qr_url']?.toString();

  /// The stored QR URL with a cache-busting query param so a replaced QR is
  /// re-fetched from storage instead of CachedNetworkImage's disk cache.
  String? get _currentQrDisplayUrl {
    final url = _currentQrUrl;
    if (url == null || url.isEmpty) return null;
    return '$url${url.contains('?') ? '&' : '?'}v=$_cacheBustVersion';
  }

  bool get _hasQr =>
      _newQrImage != null ||
      ((_currentQrUrl?.isNotEmpty ?? false) && !_removeQr);

  Future<void> _pickQrImage() async {
    final picked = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 90,
    );
    if (picked == null || !mounted) return;

    // Provisional — the preview sheet decides what is actually kept.
    setState(() {
      _newQrImage = picked;
      _removeQr = false;
      _isAnalyzing = true;
    });

    final result = await QrImageAutoCrop.detectAndCrop(picked.path);
    if (!mounted) return;
    setState(() => _isAnalyzing = false);

    await _showPreviewSheet(picked, result);
  }

  /// Preview step between picking and saving. The seller always sees exactly
  /// what will be uploaded and explicitly confirms it — an auto-crop is never
  /// saved without confirmation.
  Future<void> _showPreviewSheet(XFile picked, QrAutoCropResult result) async {
    var displayPath = result.croppedPath ?? picked.path;
    var isCropped = result.detected;
    var statusText = isCropped
        ? 'QR code detected — cropped for a clean, scannable look.'
        : (result.message ??
            'We couldn\'t detect a QR code — using the full image instead.');

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final Color bannerColor =
                isCropped ? AppConstants.success : AppConstants.statusPendingColor;
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              padding: EdgeInsets.fromLTRB(
                20,
                12,
                20,
                MediaQuery.of(ctx).viewPadding.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppConstants.borderGray,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'QR Code Preview',
                      style: AppConstants.headlineStyle(fontSize: 18),
                    ),
                    const SizedBox(height: 12),
                    // ── Preview image ──
                    Container(
                      height: 240,
                      decoration: BoxDecoration(
                        color: AppConstants.sellerSurface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppConstants.borderGray.withValues(alpha: 0.4),
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Image.file(
                        File(displayPath),
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => Center(
                          child: Icon(
                            Icons.broken_image_outlined,
                            color: AppConstants.borderGray,
                            size: 40,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // ── Status banner ──
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: bannerColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: bannerColor.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            isCropped ? Icons.qr_code_2 : Icons.info_outline,
                            size: 18,
                            color: bannerColor,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              statusText,
                              style: AppConstants.bodyStyle(
                                fontSize: 12,
                                color: AppConstants.secondary,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // ── Actions ──
                    if (isCropped) ...[
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppConstants.primary,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          setState(() => _newQrImage = XFile(displayPath));
                        },
                        icon: const Icon(
                          Icons.check_circle_outline,
                          color: Colors.white,
                          size: 18,
                        ),
                        label: Text(
                          'Use Cropped QR',
                          style: AppConstants.bodyStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: AppConstants.primary.withValues(alpha: 0.5),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        setState(() => _newQrImage = picked);
                      },
                      icon: const Icon(
                        Icons.image_outlined,
                        size: 18,
                        color: AppConstants.primary,
                      ),
                      label: Text(
                        'Use Original Image',
                        style: AppConstants.bodyStyle(
                          color: AppConstants.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: AppConstants.secondary.withValues(alpha: 0.3),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () async {
                        // Manual crop fallback — stays inside the sheet so the
                        // seller sees the result before confirming.
                        final cropped = await _cropManually(displayPath);
                        if (cropped != null) {
                          setSheetState(() {
                            displayPath = cropped;
                            isCropped = true;
                            statusText =
                                'Cropped manually — this is what customers will scan.';
                          });
                        }
                      },
                      icon: const Icon(
                        Icons.crop,
                        size: 18,
                        color: AppConstants.secondary,
                      ),
                      label: Text(
                        'Crop Manually',
                        style: AppConstants.bodyStyle(
                          color: AppConstants.secondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        _pickQrImage();
                      },
                      child: Text(
                        'Re-pick a different photo',
                        style: AppConstants.bodyStyle(
                          color: AppConstants.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Launch the system crop UI (image_cropper) for cases where auto-detection
  /// produced a poor result but a QR genuinely exists. Returns the cropped
  /// path, or null if the seller cancelled.
  Future<String?> _cropManually(String sourcePath) async {
    try {
      final cropper = ImageCropper();
      final cropped = await cropper.cropImage(
        sourcePath: sourcePath,
        // QR codes are square — lock the crop to 1:1.
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        maxWidth: QrImageAutoCrop.maxOutputDimension,
        maxHeight: QrImageAutoCrop.maxOutputDimension,
        compressFormat: ImageCompressFormat.png,
        compressQuality: 100,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop QR Code',
            lockAspectRatio: true,
            hideBottomControls: false,
            backgroundColor: AppConstants.secondary,
            toolbarColor: AppConstants.primary,
            toolbarWidgetColor: Colors.white,
          ),
          IOSUiSettings(
            title: 'Crop QR Code',
            aspectRatioLockEnabled: true,
          ),
        ],
      );
      // Discard any crop cached from a previous activity-lifecycle round so
      // the next cropImage call starts clean (per the package docs).
      await cropper.recoverImage();
      return cropped?.path;
    } catch (e) {
      debugPrint('[GcashSettings] Manual crop failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not open the crop tool: '
              '${e.toString().replaceAll('Exception: ', '')}',
            ),
            backgroundColor: AppConstants.error,
          ),
        );
      }
      return null;
    }
  }

  Future<void> _removeQrImage() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Remove QR code?',
          style: AppConstants.bodyStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'GCash will be unavailable at checkout until you upload a new one.',
          style: AppConstants.bodyStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancel',
              style: AppConstants.bodyStyle(color: AppConstants.secondary),
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppConstants.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      setState(() {
        _newQrImage = null;
        _removeQr = true;
      });
    }
  }

  Future<void> _save() async {
    final store = _store;
    if (store == null) return;

    setState(() => _isSaving = true);
    try {
      await _storeService.updateGcashSettings(
        storeId: store['id'].toString(),
        qrImage: _newQrImage,
        accountName: _accountNameController.text,
        gcashNumber: _gcashNumberController.text,
        removeQr: _removeQr,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('GCash settings saved!'),
            backgroundColor: AppConstants.success,
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString().replaceAll('Exception: ', '')}'),
            backgroundColor: AppConstants.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      appBar: AppBar(
        title: Text(
          'Payment Methods',
          style: AppConstants.headlineStyle(fontSize: 20),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppConstants.secondary),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _isLoadingStore
          ? const Center(
              child: CircularProgressIndicator(color: AppConstants.primary),
            )
          : Stack(
              children: [
                AppConstants.noiseOverlay(opacity: 0.03),
                SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Section 1: How it works ──
                      _buildSectionHeader(
                        'How it works',
                        Icons.help_outline,
                      ),
                      const SizedBox(height: 12),
                      _buildGuideCard(),
                      const SizedBox(height: 28),

                      // ── Section 2: QR code ──
                      _buildSectionHeader(
                        'Your GCash QR Code',
                        Icons.qr_code_2,
                      ),
                      const SizedBox(height: 12),
                      _buildQrSection(),
                      const SizedBox(height: 28),

                      // ── Section 3: Account details ──
                      _buildSectionHeader(
                        'Account Details',
                        Icons.account_balance_wallet_outlined,
                      ),
                      const SizedBox(height: 12),
                      _buildAccountSection(),
                      const SizedBox(height: 32),

                      SolePrimaryButton(
                        label: 'Save GCash Settings',
                        isLoading: _isSaving,
                        onPressed: _isSaving ? null : _save,
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppConstants.primary),
        const SizedBox(width: 8),
        Text(title, style: AppConstants.headlineStyle(fontSize: 16)),
      ],
    );
  }

  // ── Guide ──

  Widget _buildGuideCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppConstants.cardRadius,
        boxShadow: AppConstants.warmShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          _GuideStep(
            number: '1',
            text: 'Open the GCash app on your phone.',
          ),
          _GuideStep(
            number: '2',
            text: 'Tap "My QR" (or the QR icon near your name/balance).',
          ),
          _GuideStep(
            number: '3',
            text: 'Make sure you are on the "Scan to Pay" / receive view — this is the QR that lets customers pay directly into your wallet.',
          ),
          _GuideStep(
            number: '4',
            text: 'Take a screenshot, or use Save/Share → Save to Photos.',
          ),
          _GuideStep(
            number: '5',
            text: 'Upload that screenshot below. At checkout, customers scan YOUR QR and the money goes straight to your GCash wallet.',
          ),
        ],
      ),
    );
  }

  // ── QR section ──

  Widget _buildQrSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppConstants.cardRadius,
        boxShadow: AppConstants.warmShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_isAnalyzing) ...[
            Row(
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppConstants.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Detecting QR code…',
                  style: AppConstants.bodyStyle(
                    fontSize: 12,
                    color: AppConstants.secondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          if (!_hasQr) ...[
            Container(
              height: 220,
              decoration: BoxDecoration(
                color: AppConstants.borderGray.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppConstants.borderGray.withValues(alpha: 0.5),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.qr_code_2,
                    size: 56,
                    color: AppConstants.primary.withValues(alpha: 0.4),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'No QR code uploaded yet',
                    style: AppConstants.bodyStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'GCash will be hidden at checkout until you upload one.',
                    textAlign: TextAlign.center,
                    style: AppConstants.bodyStyle(
                      fontSize: 12,
                      color: AppConstants.secondary.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            Center(
              child: Container(
                width: 220,
                height: 220,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: SellerTheme.card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppConstants.borderGray.withValues(alpha: 0.5),
                  ),
                  boxShadow: AppConstants.sellerShadow,
                ),
                child: _newQrImage != null
                    ? Image.file(File(_newQrImage!.path), fit: BoxFit.contain)
                    : CachedNetworkImage(
                        imageUrl: _currentQrDisplayUrl!,
                        fit: BoxFit.contain,
                        placeholder: (_, _) => const Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppConstants.primary,
                            ),
                          ),
                        ),
                        errorWidget: (_, _, _) => const Center(
                          child: Icon(
                            Icons.broken_image_outlined,
                            color: AppConstants.borderGray,
                          ),
                        ),
                      ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickQrImage,
                  icon: const Icon(Icons.upload_outlined, size: 18),
                  label: Text(_hasQr ? 'Replace QR' : 'Upload QR Code'),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: AppConstants.primary.withValues(alpha: 0.6),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              if (_hasQr) ...[
                const SizedBox(width: 10),
                IconButton(
                  tooltip: 'Remove QR',
                  onPressed: _removeQrImage,
                  icon: const Icon(
                    Icons.delete_outline,
                    color: AppConstants.error,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // ── Account details ──

  Widget _buildAccountSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppConstants.cardRadius,
        boxShadow: AppConstants.warmShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'GCash Account Name (optional)',
            style: AppConstants.bodyStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _accountNameController,
            style: AppConstants.bodyStyle(fontSize: 15),
            decoration: _inputDecoration('e.g. Juan Dela Cruz'),
          ),
          const SizedBox(height: 16),
          Text(
            'GCash Number (optional)',
            style: AppConstants.bodyStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _gcashNumberController,
            keyboardType: TextInputType.phone,
            style: AppConstants.bodyStyle(fontSize: 15),
            decoration: _inputDecoration('e.g. 0917 123 4567'),
          ),
          const SizedBox(height: 10),
          Text(
            'Shown under the QR at checkout so customers can verify they are paying the right account.',
            style: AppConstants.bodyStyle(
              fontSize: 11,
              color: AppConstants.secondary.withValues(alpha: 0.55),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: AppConstants.bodyStyle(
        fontSize: 14,
        color: AppConstants.secondary.withValues(alpha: 0.4),
      ),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: AppConstants.buttonRadius,
        borderSide: BorderSide(
          color: AppConstants.borderGray.withValues(alpha: 0.5),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: AppConstants.buttonRadius,
        borderSide: BorderSide(
          color: AppConstants.borderGray.withValues(alpha: 0.5),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: AppConstants.buttonRadius,
        borderSide: const BorderSide(color: AppConstants.primary, width: 1.5),
      ),
    );
  }
}

class _GuideStep extends StatelessWidget {
  final String number;
  final String text;

  const _GuideStep({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppConstants.primary,
              shape: BoxShape.circle,
            ),
            child: Text(
              number,
              style: AppConstants.bodyStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: AppConstants.bodyStyle(
                fontSize: 13,
                height: 1.35,
                color: AppConstants.secondary.withValues(alpha: 0.8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
