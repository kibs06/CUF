import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../constants/app_constants.dart';
import '../../services/reservation_service.dart';
import '../../services/upload_service.dart';
import '../../widgets/sole_card.dart';
import '../../widgets/sole_primary_button.dart';

/// Deposit payment step for a bulk (reseller) reservation — the reuse of
/// the direct-GCash payment UX (`GcashPayScreen`), pointed at the
/// reservation's 20% deposit instead of an order total.
///
/// The customer pays the store's own GCash QR peer-to-peer, then submits
/// proof (reference number + required screenshot). The STORE OWNER then
/// verifies it in their GCash app and confirms — only the seller's
/// confirm draws the stock into the hold. Reaching the 24h deadline
/// expires the reservation (no stock was ever touched).
class BulkDepositPayScreen extends StatefulWidget {
  final BulkReservation reservation;

  const BulkDepositPayScreen({super.key, required this.reservation});

  @override
  State<BulkDepositPayScreen> createState() => _BulkDepositPayScreenState();
}

class _BulkDepositPayScreenState extends State<BulkDepositPayScreen> {
  final _formKey = GlobalKey<FormState>();
  final _refController = TextEditingController();
  final _service = ReservationService.instance;

  bool _submitting = false;
  String? _errorMessage;
  bool _proofSubmitted = false;
  String? _pickedImagePath;

  // Store GCash details (same source the order flow shows).
  Map<String, dynamic>? _store;
  String? _storeError;

  // Deadline countdown (24h deposit window).
  Timer? _countdownTimer;
  Duration _timeLeft = Duration.zero;

  @override
  void initState() {
    super.initState();
    _loadStore();
    _checkExistingProof();
    _startCountdown();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _refController.dispose();
    super.dispose();
  }

  Future<void> _loadStore() async {
    try {
      final row = await Supabase.instance.client
          .from('stores')
          .select('name, gcash_qr_url, gcash_number, gcash_account_name')
          .eq('id', widget.reservation.storeId)
          .single();
      if (!mounted) return;
      setState(() => _store = Map<String, dynamic>.from(row));
    } catch (e) {
      debugPrint('[DEPOSIT] store load failed: $e');
      if (mounted) setState(() => _storeError = 'Could not load the store\'s GCash details.');
    }
  }

  /// A proof may already have been submitted (resumed after an app
  /// restart) — show the awaiting-confirmation state instead of the form.
  Future<void> _checkExistingProof() async {
    try {
      final rows = await Supabase.instance.client
          .from('bulk_reservation_deposits')
          .select('id')
          .eq('reservation_id', widget.reservation.id)
          .limit(1);
      if (!mounted) return;
      setState(() => _proofSubmitted = (rows as List).isNotEmpty);
    } catch (_) {
      // Non-fatal: the form simply re-opens (the RPC blocks double submits).
    }
  }

  void _startCountdown() {
    _updateTimeLeft();
    _countdownTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _updateTimeLeft(),
    );
  }

  void _updateTimeLeft() {
    final deadline = widget.reservation.depositDeadline;
    if (deadline == null) return;
    final left = deadline.difference(DateTime.now());
    if (!mounted) return;
    setState(() => _timeLeft = left.isNegative ? Duration.zero : left);
  }

  bool get _expired => widget.reservation.depositExpired ||
      (widget.reservation.depositDeadline != null && _timeLeft == Duration.zero);

  bool get _hasQr {
    final qr = _store?['gcash_qr_url']?.toString();
    return qr != null && qr.isNotEmpty;
  }

  Future<void> _pickScreenshot() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (picked == null || !mounted) return;
      setState(() => _pickedImagePath = picked.path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open the photo gallery.'),
            backgroundColor: AppConstants.error,
          ),
        );
      }
    }
  }

  Future<void> _submitProof() async {
    if (!_formKey.currentState!.validate()) return;
    if (_pickedImagePath == null) {
      setState(() {
        _errorMessage = 'Attach a screenshot of your GCash payment.';
      });
      return;
    }
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    String? uploadedPath;
    try {
      // 1. Upload the screenshot to the private bucket → storage path
      //    ({reservationId}/{file}, same convention as order proofs).
      uploadedPath = await _service.uploadDepositProofScreenshot(
        reservationId: widget.reservation.id,
        filePath: _pickedImagePath!,
      );
      // 2. Submit the proof (validated server-side).
      await _service.submitDepositProof(
        reservationId: widget.reservation.id,
        referenceNumber: _refController.text.trim(),
        screenshotPath: uploadedPath,
      );
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _proofSubmitted = true;
      });
    } catch (e) {
      debugPrint('[DEPOSIT] submit error: $e');
      if (!mounted) return;
      // The RPC rejected the proof — the uploaded screenshot is now
      // orphaned in the private bucket; remove it (best-effort), exactly
      // like the order flow does.
      if (uploadedPath != null) {
        unawaited(UploadService()
            .deleteFile('payment-proofs', uploadedPath)
            .catchError((_) {}));
      }
      setState(() {
        _submitting = false;
        _errorMessage = friendlyReservationError(e);
      });
    }
  }

  void _copyToClipboard(String value) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copied to clipboard'),
        backgroundColor: AppConstants.success,
        duration: Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      appBar: AppBar(
        title: Text(
          'Pay Deposit via GCash',
          style: AppConstants.headlineStyle(fontSize: 20),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppConstants.secondary),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Stack(
        children: [
          AppConstants.noiseOverlay(opacity: 0.03),
          _proofSubmitted ? _buildSubmittedState() : _buildPaymentForm(),
        ],
      ),
    );
  }

  // ── Submitted state ─────────────────────────────────────────────

  Widget _buildSubmittedState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: const BoxDecoration(
                color: AppConstants.success,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check,
                size: 48,
                color: AppConstants.surfaceLight,
              ),
            ),
            const SizedBox(height: 28),
            Text(
              'Proof Submitted',
              style: AppConstants.headlineStyle(fontSize: 24),
            ),
            const SizedBox(height: 10),
            Text(
              'The store will verify your deposit in their GCash app and '
              'confirm it. Your units are reserved as soon as they do — '
              'you will see the update here and in your notifications.',
              textAlign: TextAlign.center,
              style: AppConstants.bodyStyle(
                fontSize: 13,
                color: AppConstants.secondary.withValues(alpha: 0.7),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: SolePrimaryButton(
                label: 'Done',
                onPressed: () => Navigator.of(context).pop(true),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Payment + proof form ────────────────────────────────────────

  Widget _buildPaymentForm() {
    final r = widget.reservation;
    final storeName =
        (_store?['name']?.toString().isNotEmpty ?? false)
            ? _store!['name'].toString()
            : r.storeName;
    final accountName =
        _store?['gcash_account_name']?.toString() ?? '';
    final number = _store?['gcash_number']?.toString() ?? '';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Reservation reference
          Text(
            'Reservation ${r.id.length >= 8 ? r.id.substring(0, 8) : r.id}',
            style: AppConstants.monoStyle(
              fontSize: 12,
              color: AppConstants.secondary.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 12),

          // Expired banner
          if (_expired) ...[
            _infoBanner(
              icon: Icons.timer_off_outlined,
              color: AppConstants.error,
              text:
                  'The 24-hour deposit window has closed. This reservation '
                  'expired and no stock was held — you can request a new one '
                  'on the product page.',
            ),
            const SizedBox(height: 16),
          ],

          // Amount card
          SoleCard(
            color: AppConstants.primary,
            child: Column(
              children: [
                Text(
                  'Send this exact amount',
                  style: AppConstants.bodyStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '₱${(r.depositAmount ?? 0).toStringAsFixed(2)}',
                  style: AppConstants.monoStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '20% deposit on ${r.quantity} units',
                  style: AppConstants.bodyStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
                if (!_expired) ...[
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.timer_outlined,
                        size: 14,
                        color: _timeLeft < const Duration(hours: 2)
                            ? Colors.amberAccent
                            : Colors.white.withValues(alpha: 0.85),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Pay within ${_formatDuration(_timeLeft)}',
                        style: AppConstants.bodyStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _timeLeft < const Duration(hours: 2)
                              ? Colors.amberAccent
                              : Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),

          // NON-REFUNDABLE warning — shown BEFORE payment, per policy.
          _infoBanner(
            icon: Icons.gavel_outlined,
            color: AppConstants.error,
            text:
                'The deposit is NON-REFUNDABLE once the store confirms it. '
                'Cancelling or letting the reservation expire forfeits the '
                'full ₱${(r.depositAmount ?? 0).toStringAsFixed(0)} — the '
                'stock is held for you at the seller\'s cost.',
          ),
          const SizedBox(height: 16),

          // QR + account details
          SoleCard(
            color: Colors.white,
            child: _storeError != null
                ? Text(
                    _storeError!,
                    style: AppConstants.bodyStyle(
                        fontSize: 12, color: AppConstants.error),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.qr_code_2,
                            size: 20,
                            color: AppConstants.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Pay ${storeName.isEmpty ? 'the store' : storeName} directly',
                              style: AppConstants.bodyStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Center(
                        child: _hasQr
                            ? Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: AppConstants.borderGray,
                                    width: 1,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    _store!['gcash_qr_url'].toString(),
                                    width: 180,
                                    height: 180,
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, _, _) => Container(
                                      width: 180,
                                      height: 180,
                                      color: AppConstants.borderGray
                                          .withValues(alpha: 0.15),
                                      child: const Icon(
                                        Icons.qr_code_scanner,
                                        size: 60,
                                        color: AppConstants.primary,
                                      ),
                                    ),
                                  ),
                                ),
                              )
                            : Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(18),
                                decoration: BoxDecoration(
                                  color:
                                      AppConstants.primary.withValues(alpha: 0.06),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Column(
                                  children: [
                                    const Icon(
                                      Icons.account_balance_wallet_outlined,
                                      size: 28,
                                      color: AppConstants.primary,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'No QR available — send to the GCash number below',
                                      textAlign: TextAlign.center,
                                      style: AppConstants.bodyStyle(
                                        fontSize: 12,
                                        color: AppConstants.secondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                      ),
                      if (accountName.isNotEmpty || number.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _detailRow('Account Name',
                            accountName.isEmpty ? '—' : accountName,
                            canCopy: accountName.isNotEmpty),
                        _detailRow(
                            'GCash Number', number.isEmpty ? '—' : number,
                            canCopy: number.isNotEmpty),
                      ],
                    ],
                  ),
          ),
          const SizedBox(height: 16),

          // How to pay
          SoleCard(
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'How to pay',
                  style: AppConstants.bodyStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                _stepRow('1', 'Open GCash → Send Money → enter the GCash '
                    'number above for the exact deposit amount.'),
                const SizedBox(height: 8),
                _stepRow('2', 'After paying, come back here and submit the '
                    'reference number from your receipt plus a screenshot.'),
                const SizedBox(height: 8),
                _stepRow('3', 'The store verifies your payment and confirms '
                    '— your units are reserved only after their confirmation.'),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Proof form
          SoleCard(
            color: Colors.white,
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Submit proof of deposit',
                    style: AppConstants.bodyStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'The store confirms your reservation after checking '
                    'their GCash app.',
                    style: AppConstants.bodyStyle(
                      fontSize: 12,
                      color: AppConstants.secondary.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _refController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    maxLength: 13,
                    decoration: InputDecoration(
                      labelText: 'GCash reference number',
                      hintText: 'e.g. 0011223344556',
                      counterText: '',
                      filled: true,
                      fillColor: AppConstants.surfaceLight,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    validator: (v) {
                      final digits = (v ?? '').replaceAll(RegExp(r'\D'), '');
                      if (digits.length != 12 && digits.length != 13) {
                        return 'Enter the 12–13 digit reference number from your receipt';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  _buildScreenshotPicker(),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _errorMessage!,
                      style: AppConstants.bodyStyle(
                        fontSize: 12,
                        color: AppConstants.error,
                        height: 1.3,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: SolePrimaryButton(
                      label: _submitting
                          ? 'Submitting…'
                          : (_expired ? 'Window Expired' : 'Submit Proof'),
                      onPressed: (_submitting || _expired) ? null : _submitProof,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              'GCash payments go directly to the store — this app does '
              'not handle your money.',
              textAlign: TextAlign.center,
              style: AppConstants.bodyStyle(
                fontSize: 11,
                color: AppConstants.secondary.withValues(alpha: 0.45),
                height: 1.3,
              ),
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _buildScreenshotPicker() {
    final path = _pickedImagePath;
    return InkWell(
      onTap: _submitting ? null : _pickScreenshot,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppConstants.surfaceLight,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: path == null
                ? AppConstants.borderGray
                : AppConstants.success.withValues(alpha: 0.5),
          ),
        ),
        child: path == null
            ? Row(
                children: [
                  const Icon(
                    Icons.add_photo_alternate_outlined,
                    size: 22,
                    color: AppConstants.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Attach payment screenshot (required)',
                      style: AppConstants.bodyStyle(
                        fontSize: 13,
                        color: AppConstants.secondary,
                      ),
                    ),
                  ),
                ],
              )
            : Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      File(path),
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Screenshot attached',
                      style: AppConstants.bodyStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppConstants.success,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.check_circle,
                    size: 18,
                    color: AppConstants.success,
                  ),
                ],
              ),
      ),
    );
  }

  // ── Small helpers (mirroring GcashPayScreen) ────────────────────

  Widget _infoBanner({
    required IconData icon,
    required Color color,
    required String text,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: AppConstants.bodyStyle(
                fontSize: 12,
                color: AppConstants.secondary,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value, {required bool canCopy}) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: AppConstants.bodyStyle(
                fontSize: 12,
                color: AppConstants.secondary.withValues(alpha: 0.6),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppConstants.bodyStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if (canCopy)
            InkWell(
              onTap: () => _copyToClipboard(value),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  Icons.copy,
                  size: 16,
                  color: AppConstants.primary.withValues(alpha: 0.7),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _stepRow(String number, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: AppConstants.primary.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            number,
            style: AppConstants.bodyStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: AppConstants.primary,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: AppConstants.bodyStyle(
              fontSize: 12,
              color: AppConstants.secondary.withValues(alpha: 0.8),
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes % 60;
    final seconds = d.inSeconds % 60;
    if (hours >= 1) {
      return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
    }
    return '${minutes}m ${seconds.toString().padLeft(2, '0')}s';
  }
}
