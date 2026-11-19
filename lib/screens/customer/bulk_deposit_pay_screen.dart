import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../constants/app_constants.dart';
import '../../constants/bulk_deposit.dart';
import '../../services/gcash_launcher.dart';
import '../../services/reservation_service.dart';
import '../../services/upload_service.dart';
import '../../utils/demo_mode.dart';
import '../../utils/gcash_receipt_parser.dart';
import '../../utils/payout_account.dart';
import '../../widgets/gcash_flow_kit.dart';

/// Deposit payment step for a bulk (reseller) reservation.
///
/// This is the order flow's manual-GCash screen (`GcashPayScreen`) pointed at a
/// reservation's deposit instead of an order total, and it is built from the
/// same kit (`gcash_flow_kit.dart`) on purpose: a customer who has paid an
/// order deposit already knows how to read this screen, and the two surfaces
/// cannot drift into different money language.
///
/// The money moves peer-to-peer to the STORE's GCash account — there is no
/// platform account in this flow — and the store owner verifies the transfer in
/// their own GCash app before confirming the hold. Only that confirmation draws
/// the stock. Hitting the 24h deadline expires the reservation with no stock
/// ever touched.
class BulkDepositPayScreen extends StatefulWidget {
  final BulkReservation reservation;

  const BulkDepositPayScreen({super.key, required this.reservation});

  @override
  State<BulkDepositPayScreen> createState() => _BulkDepositPayScreenState();
}

class _BulkDepositPayScreenState extends State<BulkDepositPayScreen> {
  final _formKey = GlobalKey<FormState>();
  final _refController = TextEditingController();
  final _amountController = TextEditingController();
  final _service = ReservationService.instance;

  bool _submitting = false;
  String? _errorMessage;
  bool _proofSubmitted = false;
  String? _pickedImagePath;

  // Store GCash details (the recipient of this deposit).
  Map<String, dynamic>? _store;
  String? _storeError;

  // Receipt read-back: the attached screenshot is OCR'd on-device so the
  // reference arrives filled in instead of being retyped — the same
  // convenience the order flow offers. Manual entry stays available whenever
  // the screenshot cannot be read.
  TextRecognizer? _recognizer;
  bool _readingReceipt = false;
  GcashReceiptParse? _receipt;

  // Deadline countdown (24h deposit window).
  Timer? _countdownTimer;
  Duration _timeLeft = Duration.zero;

  @override
  void initState() {
    super.initState();
    _amountController.text = (widget.reservation.depositAmount ?? 0)
        .toStringAsFixed(2);
    _loadStore();
    _checkExistingProof();
    _startCountdown();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    try {
      _recognizer?.close();
    } catch (_) {
      // Best-effort: nothing to release if the engine is already gone.
    }
    _refController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  // ── Data ────────────────────────────────────────────────────────

  Future<void> _loadStore() async {
    try {
      final client = Supabase.instance.client;
      final row = await client
          .from('stores')
          .select('name, gcash_qr_url, gcash_number, gcash_account_name')
          .eq('id', widget.reservation.storeId)
          .single();
      // The contact number arrived after this screen did, so it is read on its
      // own: a database that has not had 20261119270000 applied yet must still
      // render the payment details, which are the part that cannot be skipped.
      var contact = '';
      try {
        final extra = await client
            .from('stores')
            .select('contact_number')
            .eq('id', widget.reservation.storeId)
            .maybeSingle();
        contact = extra?['contact_number']?.toString().trim() ?? '';
      } catch (e) {
        debugPrint('[DEPOSIT] store contact number unavailable: $e');
      }
      if (!mounted) return;
      setState(
        () => _store = <String, dynamic>{
          ...Map<String, dynamic>.from(row),
          'contact_number': contact,
        },
      );
    } catch (e) {
      debugPrint('[DEPOSIT] store load failed: $e');
      if (mounted) {
        setState(
          () => _storeError =
              'Could not load the store\'s GCash details. '
              'Pull back and try again in a moment.',
        );
      }
    }
  }

  /// A proof may already have been submitted (resumed after an app restart) —
  /// show the waiting state instead of the form.
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
      // Non-fatal: the form reopens and the RPC blocks a double submit.
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

  bool get _expired =>
      widget.reservation.depositExpired ||
      (widget.reservation.depositDeadline != null &&
          _timeLeft == Duration.zero);

  bool get _hasQr {
    final qr = _store?['gcash_qr_url']?.toString();
    return qr != null && qr.isNotEmpty;
  }

  double get _deposit => widget.reservation.depositAmount ?? 0;

  /// `BR-XXXXXXXX` — the same code the deposit receipt and the seller's queue
  /// show, so the GCash note matches the document the customer keeps.
  String get _reservationCode {
    final compact = widget.reservation.id.replaceAll('-', '');
    final head = compact.length >= 8
        ? compact.substring(0, 8)
        : compact.padRight(8, '0');
    return 'BR-${head.toUpperCase()}';
  }

  String get _storeLabel {
    final name = _store?['name']?.toString() ?? '';
    if (name.isNotEmpty) return name;
    return widget.reservation.storeName.isEmpty
        ? 'the store'
        : widget.reservation.storeName;
  }

  // ── Receipt read-back ───────────────────────────────────────────

  Future<void> _pickScreenshot() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (picked == null || !mounted) return;
      setState(() => _pickedImagePath = picked.path);
      await _readReceipt(picked.path);
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

  /// Read the attached screenshot and pre-fill the proof form from it.
  ///
  /// On-device ML Kit text recognition: a GCash receipt prints its Ref No. as
  /// ordinary text. The amount written back is the receipt's own figure, never
  /// the expected deposit, so a transfer of the wrong size shows up here as a
  /// mismatch instead of being quietly corrected.
  Future<void> _readReceipt(String path) async {
    setState(() {
      _readingReceipt = true;
      _receipt = null;
    });
    var parsed = GcashReceiptParse.empty;
    try {
      _recognizer ??= TextRecognizer(script: TextRecognitionScript.latin);
      final recognized = await _recognizer!.processImage(
        InputImage.fromFilePath(path),
      );
      final lines = <String>[
        for (final block in recognized.blocks)
          for (final line in block.lines)
            if (line.text.trim().isNotEmpty) line.text.trim(),
      ];
      parsed = GcashReceiptParser.parse(lines);
    } catch (e) {
      // An unreadable screenshot is not an error the customer has to clear:
      // the reference field becomes typeable below.
      debugPrint('[DEPOSIT] receipt OCR error: $e');
    }
    if (!mounted) return;
    setState(() {
      _readingReceipt = false;
      _receipt = parsed;
      final reference = parsed.reference.reference;
      if (reference != null) _refController.text = reference;
      final amount = parsed.amount;
      if (amount != null) _amountController.text = amount.toStringAsFixed(2);
    });
  }

  /// The reference is locked only when the screenshot actually produced one;
  /// otherwise the customer types it, so a receipt the OCR cannot read never
  /// traps them on this screen.
  bool get _refReadOnly => _receipt?.reference.detected ?? false;

  // ── Actions ─────────────────────────────────────────────────────

  Future<void> _submitProof() async {
    // Same code-level guard as the order proof screen: one deposit, one proof.
    if (_submitting) return;
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
      // The RPC rejected the proof — the uploaded screenshot is now orphaned
      // in the private bucket; remove it (best-effort), as the order flow does.
      if (uploadedPath != null) {
        unawaited(
          UploadService()
              .deleteFile('payment-proofs', uploadedPath)
              .catchError((_) {}),
        );
      }
      setState(() {
        _submitting = false;
        _errorMessage = friendlyReservationError(e);
      });
    }
  }

  /// DEMO MODE only (a build-time flag): files a deposit proof with a
  /// generated reference and no screenshot, so the seller can confirm the hold
  /// in a demo without a real GCash transfer. The RPC requires the proof's
  /// path to start with the reservation id, which [demoDepositScreenshotPath]
  /// satisfies; nothing is uploaded and the review sheet says so.
  Future<void> _submitDemoProof() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    try {
      await _service.submitDepositProof(
        reservationId: widget.reservation.id,
        referenceNumber: demoGcashReference(),
        screenshotPath: demoDepositScreenshotPath(widget.reservation.id),
      );
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _proofSubmitted = true;
      });
    } catch (e) {
      debugPrint('[DEPOSIT] demo proof error: $e');
      if (!mounted) return;
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

  /// Copy the number digits-only and put GCash in front of the customer.
  ///
  /// A number stored as "0961 579 8280" is rejected by GCash's send-to field
  /// and the customer cannot see why, so the clipboard gets the digits alone.
  /// Nothing can be prefilled (GCash has no public deep link into send-money),
  /// which is why the clipboard is the hand-off.
  Future<void> _copyGcashNumber() async {
    final raw = (_store?['gcash_number']?.toString() ?? '').trim();
    if (raw.isEmpty) return;
    final digits = normalizeGcashNumber(raw);
    final value = digits.isEmpty ? raw : digits;

    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Number copied — opening GCash…'),
        backgroundColor: AppConstants.success,
        duration: Duration(seconds: 1),
      ),
    );

    final result = await GcashLauncher.open();
    if (!mounted) return;
    messenger.hideCurrentSnackBar();
    switch (result) {
      case GcashLaunchResult.opened:
        messenger.showSnackBar(
          SnackBar(
            content: Text('$value is copied — paste it as the GCash number'),
            backgroundColor: AppConstants.success,
            duration: const Duration(seconds: 4),
          ),
        );
      case GcashLaunchResult.notInstalled:
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              '$value is copied, but GCash is not installed on this phone. '
              'Paste it wherever you send from.',
            ),
            backgroundColor: AppConstants.statusPendingColor,
            duration: const Duration(seconds: 5),
          ),
        );
      case GcashLaunchResult.unsupported:
        messenger.showSnackBar(
          SnackBar(
            content: Text('$value is copied — open GCash and paste it'),
            backgroundColor: AppConstants.success,
            duration: const Duration(seconds: 4),
          ),
        );
    }
  }

  // ── Scaffold ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      appBar: AppBar(
        title: Text(
          'Pay via GCash',
          style: AppConstants.headlineStyle(fontSize: 19),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppConstants.secondary),
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

  // ── Waiting on the store ────────────────────────────────────────

  Widget _buildSubmittedState() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 36),
      children: [
        GcashRiseIn(
          child: GcashFlowHeader(
            eyebrow: 'Bulk deposit · manual GCash',
            title: 'Proof submitted',
            description:
                'The store compares your reference against the deposit that '
                'landed in their GCash account, then confirms the hold.',
          ),
        ),
        const SizedBox(height: 16),
        GcashRiseIn(
          order: 1,
          child: GcashPanel(
            dark: true,
            eyebrow: 'Waiting on the store',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.10),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.hourglass_top_rounded,
                        size: 20,
                        color: kGcashReceiptInk,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '₱${_deposit.toStringAsFixed(2)}',
                        style: AppConstants.monoStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          color: kGcashReceiptInk,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Your units are held as soon as the store confirms. You will '
                  'see it here and in your notifications — then collect them '
                  'at the store. Bulk holds are never shipped.',
                  style: AppConstants.bodyStyle(
                    fontSize: 11.5,
                    height: 1.4,
                    color: kGcashReceiptMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        GcashRiseIn(
          order: 2,
          child: GcashPrimaryButton(
            label: 'Done',
            showIcon: false,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ),
      ],
    );
  }

  // ── Payment + proof form ────────────────────────────────────────

  Widget _buildPaymentForm() {
    final r = widget.reservation;
    final accountName = _store?['gcash_account_name']?.toString() ?? '';
    final number = _store?['gcash_number']?.toString() ?? '';
    final contact = _store?['contact_number']?.toString().trim() ?? '';

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 36),
      children: [
        GcashRiseIn(
          child: GcashFlowHeader(
            eyebrow: '$_reservationCode · bulk deposit',
            title: 'Send ₱${_deposit.toStringAsFixed(2)}',
            description:
                'Pay $_storeLabel\'s GCash account, put the reservation code '
                'in the GCash note, then submit the proof. The store checks '
                'the transfer before your units are held.',
          ),
        ),
        if (_expired) ...[
          const SizedBox(height: 14),
          GcashRiseIn(
            order: 1,
            child: GcashBanner(
              icon: Icons.timer_off_outlined,
              color: AppConstants.error,
              text:
                  'The 24-hour deposit window has closed. This reservation '
                  'expired and no stock was held — you can request a new one '
                  'on the product page.',
            ),
          ),
        ],
        const SizedBox(height: 14),
        // Shown BEFORE payment, per policy — this is the one banner that must
        // not be below the fold when money is about to leave the wallet.
        GcashRiseIn(
          order: 1,
          child: const GcashBanner(
            icon: Icons.gavel_outlined,
            color: AppConstants.error,
            text:
                'The deposit is NON-REFUNDABLE once the store confirms it. '
                'Cancelling or letting the reservation expire forfeits it — '
                'the stock is held for you at the store\'s cost.',
          ),
        ),
        const SizedBox(height: 10),
        GcashRiseIn(
          order: 1,
          child: GcashBanner(
            icon: Icons.storefront_outlined,
            color: AppConstants.primary,
            text:
                'Pickup only — collect your ${r.quantity} units at '
                '$_storeLabel once the deposit is confirmed. Bulk orders are '
                'not shipped or delivered.',
          ),
        ),
        const SizedBox(height: 16),
        GcashRiseIn(order: 1, child: _amountPanel()),
        const SizedBox(height: 14),
        GcashRiseIn(
          order: 2,
          child: _accountPanel(accountName, number, contact),
        ),
        const SizedBox(height: 14),
        GcashRiseIn(order: 3, child: _stepsPanel()),
        if (AppConstants.demoModeEnabled && !_expired) ...[
          const SizedBox(height: 14),
          GcashRiseIn(
            order: 3,
            child: const GcashBanner(
              icon: Icons.build_circle_outlined,
              color: AppConstants.error,
              text:
                  'DEVELOPER MODE — skip the real GCash transfer. This files a '
                  'test deposit proof with a generated reference and no '
                  'screenshot, so the store can confirm the hold during a '
                  'demo. No money moves.',
            ),
          ),
          const SizedBox(height: 8),
          GcashRiseIn(
            order: 3,
            child: GcashGhostPill(
              label: 'Demo: submit test deposit proof',
              icon: Icons.build_circle_outlined,
              color: AppConstants.error,
              onPressed: _submitting ? null : _submitDemoProof,
            ),
          ),
        ],
        const SizedBox(height: 14),
        GcashRiseIn(order: 4, child: _proofPanel()),
        const SizedBox(height: 18),
        Text(
          'GCash payments go directly to $_storeLabel — this app does not '
          'handle your money.',
          textAlign: TextAlign.center,
          style: AppConstants.bodyStyle(
            fontSize: 11,
            height: 1.4,
            color: AppConstants.secondary.withValues(alpha: 0.5),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _amountPanel() {
    final low = _timeLeft < const Duration(hours: 1);
    final voucher = widget.reservation.voucherCode?.trim() ?? '';
    return GcashPanel(
      dark: true,
      eyebrow: 'Exact amount',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '₱${_deposit.toStringAsFixed(2)}',
            style: AppConstants.monoStyle(
              fontSize: 34,
              fontWeight: FontWeight.w700,
              color: kGcashReceiptInk,
            ),
          ),
          const SizedBox(height: 8),
          if (_expired)
            Text(
              'Window expired — the reservation was released.',
              style: AppConstants.bodyStyle(
                fontSize: 12,
                height: 1.35,
                color: kGcashReceiptWarn,
              ),
            )
          else
            Row(
              children: [
                Icon(
                  Icons.timer_outlined,
                  size: 14,
                  color: low ? kGcashReceiptWarn : kGcashReceiptMuted,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Confirm within ${_formatDuration(_timeLeft)}',
                    style: AppConstants.bodyStyle(
                      fontSize: 12,
                      height: 1.3,
                      fontWeight: FontWeight.w600,
                      color: low ? kGcashReceiptWarn : kGcashReceiptMuted,
                    ),
                  ),
                ),
              ],
            ),
          if (voucher.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(
                  Icons.confirmation_number_outlined,
                  size: 14,
                  color: kGcashReceiptMuted,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Voucher $voucher already took '
                    '₱${(widget.reservation.voucherDiscount ?? 0).toStringAsFixed(2)} '
                    'off — this deposit is $kBulkReservationDepositLabel of '
                    'the discounted bulk price.',
                    style: AppConstants.bodyStyle(
                      fontSize: 11,
                      height: 1.4,
                      color: kGcashReceiptMuted,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Text(
            'Any other amount is rejected by the store, so send this exact '
            'figure in one transfer.',
            style: AppConstants.bodyStyle(
              fontSize: 11,
              height: 1.4,
              color: kGcashReceiptMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _accountPanel(String accountName, String number, String contact) {
    final hasName = accountName.isNotEmpty;
    final hasNumber = number.isNotEmpty;
    return GcashPanel(
      eyebrow: 'Send to',
      title: '$_storeLabel GCash account',
      description:
          'Your deposit goes straight to $_storeLabel. They confirm it in '
          'their GCash app and hold the units for you.',
      child: _storeError != null
          ? GcashBanner(
              icon: Icons.error_outline,
              color: AppConstants.error,
              text: _storeError!,
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GcashInsetTile(
                  child: GcashCopyRow(
                    label: 'Reservation code — paste into the GCash note',
                    value: _reservationCode,
                    onCopy: () => _copyToClipboard(_reservationCode),
                    semanticsLabel: 'Copy reservation code',
                  ),
                ),
                const SizedBox(height: 14),
                Center(child: _qrBlock()),
                if (hasName || hasNumber) const SizedBox(height: 16),
                if (hasName)
                  GcashCopyRow(
                    label: 'Account name',
                    value: accountName,
                    onCopy: () => _copyToClipboard(accountName),
                    semanticsLabel: 'Copy account name',
                  ),
                if (hasName && hasNumber) const SizedBox(height: 12),
                if (hasNumber)
                  GcashCopyRow(
                    label: 'GCash number',
                    value: number,
                    onCopy: _copyGcashNumber,
                    semanticsLabel:
                        'Copy GCash number and open GCash to send the deposit',
                  ),
                // The shop's own line, present only when the seller set one in
                // Edit Store — the GCash number above is a payment rail, not a
                // way to ask why the deposit has not been confirmed.
                if (contact.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  GcashInsetTile(
                    child: GcashCopyRow(
                      label: 'Store contact — questions about this deposit',
                      value: contact,
                      onCopy: () => _copyToClipboard(contact),
                      semanticsLabel: 'Copy the store contact number',
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _qrBlock() {
    if (_storeError != null) return const SizedBox.shrink();
    if (!_hasQr) {
      return GcashInsetTile(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.account_balance_wallet_outlined,
              size: 20,
              color: AppConstants.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'No QR on file. Copy the GCash number below and send the exact '
                'amount from your GCash app.',
                style: AppConstants.bodyStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: AppConstants.secondary.withValues(alpha: 0.8),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppConstants.sellerCardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppConstants.borderGray),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          _store!['gcash_qr_url'].toString(),
          width: 190,
          height: 190,
          fit: BoxFit.contain,
          semanticLabel: '$_storeLabel GCash QR code',
          errorBuilder: (_, _, _) => Container(
            width: 190,
            height: 190,
            color: AppConstants.borderGray.withValues(alpha: 0.15),
            child: const Icon(
              Icons.qr_code_scanner,
              size: 60,
              color: AppConstants.primary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _stepsPanel() {
    return GcashPanel(
      eyebrow: 'Steps',
      title: 'How to pay',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _stepRow(
            '1',
            'Open GCash → Send Money → enter the GCash number above for the '
                'exact deposit, and paste the reservation code in the note.',
          ),
          const SizedBox(height: 10),
          _stepRow(
            '2',
            'Come back here and submit the reference number and a screenshot '
                'of the receipt. We read the reference from it.',
          ),
          const SizedBox(height: 10),
          _stepRow(
            '3',
            'The store checks the transfer in their GCash app. Your units are '
                'held only after they confirm — then pick them up at the '
                'store.',
          ),
        ],
      ),
    );
  }

  Widget _proofPanel() {
    return GcashPanel(
      eyebrow: 'Proof',
      title: 'Submit proof of payment',
      description:
          'The reference and screenshot must match the transfer the store '
          'received. A deposit is verified once.',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Locked once the screenshot has been read: a reference a customer
            // can edit is a reference a customer can invent, and the proof is
            // only worth anything if it is checked against the transfer. When
            // the receipt cannot be read, the field opens for typing so the
            // customer is never stuck.
            TextFormField(
              controller: _refController,
              readOnly: _refReadOnly,
              showCursor: !_refReadOnly,
              keyboardType: _refReadOnly ? null : TextInputType.number,
              inputFormatters: _refReadOnly
                  ? null
                  : [FilteringTextInputFormatter.digitsOnly],
              maxLength: 13,
              style: AppConstants.monoStyle(fontSize: 14),
              decoration: _decoration(
                label: 'GCash reference number',
                hint: 'e.g. 0011223344556',
                helper: _refReadOnly
                    ? 'Read from your screenshot'
                    : 'Type the 12–13 digits printed on your receipt',
                suffixIcon: _refReadOnly ? _lockedIcon : null,
              ),
              validator: (v) {
                final digits = (v ?? '').replaceAll(RegExp(r'\D'), '');
                if (digits.length != 12 && digits.length != 13) {
                  return 'Attach your GCash receipt or type the 12–13 digit '
                      'reference';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _amountController,
              readOnly: true,
              showCursor: false,
              style: AppConstants.monoStyle(fontSize: 14),
              decoration: _decoration(
                label: 'Amount you sent',
                prefix: '₱ ',
                helper: 'Must match ₱${_deposit.toStringAsFixed(2)} exactly',
                suffixIcon: _lockedIcon,
              ),
            ),
            const SizedBox(height: 14),
            _buildScreenshotPicker(),
            if (_readingReceipt || _receipt != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: _buildReceiptReadback(),
              ),
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
            const SizedBox(height: 18),
            GcashPrimaryButton(
              label: _expired ? 'Window expired' : 'Submit proof',
              showIcon: false,
              loading: _submitting,
              onPressed: (_submitting || _expired) ? null : _submitProof,
            ),
          ],
        ),
      ),
    );
  }

  /// The small padlock that marks a field as read-only, so a customer does not
  /// assume the app is broken when tapping it does nothing.
  Widget get _lockedIcon => Icon(
    Icons.lock_outline,
    size: 15,
    color: AppConstants.secondary.withValues(alpha: 0.45),
  );

  InputDecoration _decoration({
    required String label,
    String? hint,
    String? helper,
    String? prefix,
    Widget? suffixIcon,
  }) {
    final hairline = AppConstants.primary.withValues(alpha: 0.14);
    return InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helper,
      helperMaxLines: 2,
      prefixText: prefix,
      suffixIcon: suffixIcon,
      counterText: '',
      filled: true,
      fillColor: AppConstants.primary.withValues(alpha: 0.035),
      labelStyle: AppConstants.bodyStyle(
        fontSize: 13,
        color: AppConstants.secondary.withValues(alpha: 0.75),
      ),
      hintStyle: AppConstants.bodyStyle(
        fontSize: 13,
        color: AppConstants.secondary.withValues(alpha: 0.4),
      ),
      helperStyle: AppConstants.bodyStyle(
        fontSize: 11,
        color: AppConstants.secondary.withValues(alpha: 0.55),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: hairline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: hairline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppConstants.primary, width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: AppConstants.error.withValues(alpha: 0.6),
        ),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppConstants.error, width: 1.4),
      ),
    );
  }

  Widget _buildScreenshotPicker() {
    final path = _pickedImagePath;
    final hasShot = path != null;
    return Semantics(
      button: true,
      label: hasShot
          ? 'Payment screenshot attached. Tap to replace.'
          : 'Attach payment screenshot. Required.',
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: _submitting ? null : _pickScreenshot,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: (hasShot ? AppConstants.success : AppConstants.primary)
                  .withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: hasShot
                    ? AppConstants.success.withValues(alpha: 0.45)
                    : AppConstants.primary.withValues(alpha: 0.16),
              ),
            ),
            child: hasShot
                ? Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.file(
                          File(path),
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Screenshot attached',
                              style: AppConstants.bodyStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppConstants.success,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Tap to replace it',
                              style: AppConstants.bodyStyle(
                                fontSize: 11,
                                color: AppConstants.secondary.withValues(
                                  alpha: 0.6,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.check_circle,
                        size: 20,
                        color: AppConstants.success,
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppConstants.primary.withValues(alpha: 0.08),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.add_photo_alternate_outlined,
                          size: 20,
                          color: AppConstants.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Attach payment screenshot',
                              style: AppConstants.bodyStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Required — we read the reference from it',
                              style: AppConstants.bodyStyle(
                                fontSize: 11,
                                height: 1.3,
                                color: AppConstants.secondary.withValues(
                                  alpha: 0.6,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  /// What the attached screenshot yielded, and whether its amount is this
  /// deposit. Not a gate — the field validator and the submit RPC own that — it
  /// just puts the receipt's own figure in front of the customer.
  Widget _buildReceiptReadback() {
    if (_readingReceipt) {
      return Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppConstants.primary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Reading your screenshot…',
              style: AppConstants.bodyStyle(
                fontSize: 11.5,
                color: AppConstants.secondary.withValues(alpha: 0.65),
              ),
            ),
          ),
        ],
      );
    }

    final parsed = _receipt;
    if (parsed == null || parsed.isEmpty) {
      return GcashBanner(
        icon: Icons.info_outline,
        color: AppConstants.statusPendingColor,
        text:
            "Couldn't read the receipt automatically — type the reference "
            'number exactly as it appears on it.',
      );
    }

    final read = parsed.amount;
    if (read != null && (read - _deposit).abs() > 0.009) {
      return GcashBanner(
        icon: Icons.error_outline,
        color: AppConstants.error,
        text:
            'Your receipt shows \u20b1${read.toStringAsFixed(2)}, but this '
            'deposit is \u20b1${_deposit.toStringAsFixed(2)}. Only the exact '
            'amount is accepted — check the receipt before submitting.',
      );
    }

    final reference = parsed.reference;
    final refText = reference.detected
        ? 'reference ${reference.displayGrouped}'
        : 'the reference';
    if (read != null) {
      return GcashBanner(
        icon: Icons.check_circle_outline,
        color: AppConstants.success,
        text:
            'Filled from your screenshot: $refText and '
            '\u20b1${read.toStringAsFixed(2)} — matches the deposit. '
            'Double-check both before submitting.',
      );
    }
    return GcashBanner(
      icon: Icons.info_outline,
      color: AppConstants.statusPendingColor,
      text:
          'Filled the $refText from your screenshot. Add the amount you '
          'actually sent.',
    );
  }

  // ── Small helpers ───────────────────────────────────────────────

  Widget _stepRow(String number, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: AppConstants.primary.withValues(alpha: 0.08),
            shape: BoxShape.circle,
            border: Border.all(
              color: AppConstants.primary.withValues(alpha: 0.18),
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            number,
            style: AppConstants.monoStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppConstants.primary,
            ),
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Text(
            text,
            style: AppConstants.bodyStyle(
              fontSize: 12,
              height: 1.4,
              color: AppConstants.secondary.withValues(alpha: 0.8),
            ),
          ),
        ),
      ],
    );
  }

  /// 24 hours is this window's scale, so hours stay visible: "23h 41m", and
  /// "41m 12s" inside the last hour.
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
