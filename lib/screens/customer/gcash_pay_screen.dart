import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../constants/app_constants.dart';
import '../../services/direct_gcash_service.dart';
import '../../services/upload_service.dart';
import '../../utils/gcash_receipt_parser.dart';
import '../../widgets/gcash_flow_kit.dart';
import 'tracking_screen.dart';

/// Gateway-free GCash payment step: the customer pays the PLATFORM GCash
/// account (no gateway, no per-store number), then submits proof (reference
/// number, sender name, amount + required screenshot) which the store
/// manually confirms against the platform statement.
///
/// Reached from checkout (after `create_gcash_checkout`) or resumed from
/// the order tracking screen.
class GcashPayScreen extends StatefulWidget {
  final String orderId;
  final String storeId;
  final double totalAmount;
  final DateTime? deadline;
  final String storeName;
  final String? gcashQrUrl;
  final String? gcashNumber;
  final String? gcashAccountName;

  /// Short code the customer puts in the GCash note.
  final String? orderCode;

  /// Set when a previous attempt was rejected — shown with the reason so the
  /// customer knows exactly what to correct.
  final String? rejectionReason;
  final int attemptsLeft;

  /// True when a proof was already submitted (resumed from tracking) —
  /// hides the form and shows the awaiting-confirmation state.
  final bool proofSubmitted;

  /// Injectable for tests: the default talks to Supabase.
  final DirectGcashService? service;

  const GcashPayScreen({
    super.key,
    required this.orderId,
    required this.storeId,
    required this.totalAmount,
    this.deadline,
    this.storeName = '',
    this.gcashQrUrl,
    this.gcashNumber,
    this.gcashAccountName,
    this.orderCode,
    this.rejectionReason,
    this.attemptsLeft = 3,
    this.proofSubmitted = false,
    this.service,
  });

  @override
  State<GcashPayScreen> createState() => _GcashPayScreenState();
}

class _GcashPayScreenState extends State<GcashPayScreen> {
  final _formKey = GlobalKey<FormState>();
  final _refController = TextEditingController();
  final _senderController = TextEditingController();
  final _amountController = TextEditingController();
  late final DirectGcashService _service =
      widget.service ?? DirectGcashService();

  bool _submitting = false;
  bool _error = false;
  late bool _proofSubmitted;
  String? _errorMessage;
  String? _pickedImagePath;

  // Receipt read-back: the attached screenshot is OCR'd on-device so the
  // reference and the amount arrive filled in instead of being retyped.
  // Purely a convenience — manual entry always stays available.
  TextRecognizer? _recognizer;
  bool _readingReceipt = false;
  GcashReceiptParse? _receipt;

  // Deadline countdown
  Timer? _countdownTimer;
  Duration _timeLeft = Duration.zero;

  @override
  void initState() {
    super.initState();
    _proofSubmitted = widget.proofSubmitted;
    _amountController.text = widget.totalAmount.toStringAsFixed(2);
    // Opportunistic expiry sweep (idempotent; frees this order if the
    // window already lapsed — the UI below reacts to the deadline).
    unawaited(_service.expireOverdue());
    _startCountdown();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    try {
      _recognizer?.close();
    } catch (_) {
      // Best-effort cleanup — nothing to release if the engine is gone.
    }
    _refController.dispose();
    _senderController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  void _startCountdown() {
    _updateTimeLeft();
    _countdownTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _updateTimeLeft(),
    );
  }

  void _updateTimeLeft() {
    final deadline = widget.deadline;
    if (deadline == null) return;
    final left = deadline.difference(DateTime.now());
    setState(() => _timeLeft = left.isNegative ? Duration.zero : left);
  }

  bool get _expired => widget.deadline != null && _timeLeft == Duration.zero;

  bool get _hasQr =>
      widget.gcashQrUrl != null && widget.gcashQrUrl!.isNotEmpty;

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
  /// On-device ML Kit text recognition, because a GCash receipt prints its
  /// Ref No. as ordinary text (this is OCR, not barcode scanning). The amount
  /// is written back EXACTLY as the receipt shows it rather than as the
  /// expected total, so a transfer of the wrong size shows up as a mismatch in
  /// the form instead of being quietly corrected.
  Future<void> _readReceipt(String path) async {
    setState(() {
      _readingReceipt = true;
      _receipt = null;
    });
    var parsed = GcashReceiptParse.empty;
    try {
      _recognizer ??= TextRecognizer(script: TextRecognitionScript.latin);
      final recognized =
          await _recognizer!.processImage(InputImage.fromFilePath(path));
      final lines = <String>[
        for (final block in recognized.blocks)
          for (final line in block.lines)
            if (line.text.trim().isNotEmpty) line.text.trim(),
      ];
      parsed = GcashReceiptParser.parse(lines);
    } catch (e) {
      // An unreadable screenshot is not an error the customer has to clear:
      // the fields are typed in by hand, exactly as before.
      debugPrint('[GCASH-PAY] receipt OCR error: $e');
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

  Future<void> _submitProof() async {
    if (!_formKey.currentState!.validate()) return;
    if (_pickedImagePath == null) {
      setState(() {
        _error = true;
        _errorMessage = 'Attach a screenshot of your GCash payment.';
      });
      return;
    }
    setState(() {
      _submitting = true;
      _error = false;
      _errorMessage = null;
    });
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      setState(() {
        _error = true;
        _errorMessage = 'Enter the amount you actually sent.';
      });
      return;
    }
    String? uploadedPath;
    try {
      // 1. Hash the exact bytes we are about to upload. The server keeps a
      //    platform-wide unique index on this digest, so one screenshot can
      //    never back two orders.
      final bytes = await File(_pickedImagePath!).readAsBytes();
      final hash = sha256.convert(bytes).toString();
      // 2. Upload the screenshot to the private bucket → storage path.
      uploadedPath = await _service.uploadProofScreenshot(
        orderId: widget.orderId,
        filePath: _pickedImagePath!,
      );
      // 3. Submit the proof (validated server-side: amount must equal the
      //    order total, reference and screenshot must be unused).
      await _service.submitProof(
        orderId: widget.orderId,
        referenceNumber: _refController.text.trim(),
        senderName: _senderController.text.trim(),
        amountPaid: amount,
        screenshotPath: uploadedPath,
        screenshotHash: hash,
      );
      // 3. Ping the seller's device now — the in-app row is already
      // written by the RPC (realtime bell covers the open app); this
      // covers the closed app. Fire-and-forget, never blocks this screen.
      unawaited(_service.notifySellerOfProof(
        orderId: widget.orderId,
        storeId: widget.storeId,
        totalAmount: widget.totalAmount,
      ));
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _proofSubmitted = true;
      });
    } on DirectGcashException catch (e) {
      if (!mounted) return;
      // The RPC rejected the proof — the uploaded screenshot is now
      // orphaned in the private bucket; remove it (best-effort).
      if (uploadedPath != null) {
        unawaited(UploadService().deleteFile('payment-proofs', uploadedPath));
      }
      setState(() {
        _submitting = false;
        _error = true;
        _errorMessage = e.message;
      });
    } catch (e) {
      debugPrint('[GCASH-PAY] submit error: $e');
      if (!mounted) return;
      if (uploadedPath != null) {
        unawaited(UploadService().deleteFile('payment-proofs', uploadedPath));
      }
      setState(() {
        _submitting = false;
        _error = true;
        _errorMessage =
            'Could not submit your proof. Check your connection and try again.';
      });
    }
  }

  Future<void> _openTracking() async {
    try {
      final order = await Supabase.instance.client
          .from('orders')
          .select('*')
          .eq('id', widget.orderId)
          .single();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => OrderTrackingScreen(order: order),
        ),
      );
    } catch (e) {
      debugPrint('[GCASH-PAY] open tracking error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open the order. Find it under My Orders.'),
          backgroundColor: AppConstants.error,
        ),
      );
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

  // ── Submitted state ─────────────────────────────────────────────

  Widget _buildSubmittedState() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 36),
      children: [
        GcashRiseIn(
          child: GcashFlowHeader(
            eyebrow: 'Manual GCash',
            title: 'Proof submitted',
            description:
                'The store compares your reference, sender name and amount '
                'against the platform GCash account, then confirms the order.',
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
                        '₱${widget.totalAmount.toStringAsFixed(2)}',
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
                  'You will see the confirmation here and in your '
                  'notifications. Preparing starts only after the store '
                  'accepts the payment.',
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
            label: 'Track my order',
            icon: Icons.arrow_forward,
            onPressed: _openTracking,
          ),
        ),
        const SizedBox(height: 10),
        GcashRiseIn(
          order: 3,
          child: GcashGhostPill(
            label: 'Back to home',
            icon: Icons.home_outlined,
            onPressed: () {
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
          ),
        ),
      ],
    );
  }

  // ── Payment + proof form ────────────────────────────────────────

  Widget _buildPaymentForm() {
    final shortId = widget.orderId.length >= 8
        ? widget.orderId.substring(widget.orderId.length - 8)
        : widget.orderId;
    final storeLabel =
        widget.storeName.isEmpty ? 'the store' : widget.storeName;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 36),
      children: [
        GcashRiseIn(
          child: GcashFlowHeader(
            eyebrow: 'Order #$shortId · manual GCash',
            title: 'Send ₱${widget.totalAmount.toStringAsFixed(2)}',
            description:
                'Pay the platform account, put the order code in the GCash '
                'note, then submit the proof. The store verifies the transfer '
                'before your order is prepared.',
          ),
        ),
        if (widget.rejectionReason != null &&
            widget.rejectionReason!.trim().isNotEmpty) ...[
          const SizedBox(height: 14),
          GcashRiseIn(
            order: 1,
            child: GcashBanner(
              icon: Icons.report_gmailerrorred_outlined,
              color: AppConstants.error,
              text: 'Your last proof was rejected: ${widget.rejectionReason} '
                  'You have ${widget.attemptsLeft} attempt(s) left. Pay again '
                  'only if the money did not leave your GCash.',
            ),
          ),
        ],
        if (_expired) ...[
          const SizedBox(height: 14),
          GcashRiseIn(
            order: 1,
            child: GcashBanner(
              icon: Icons.timer_off_outlined,
              color: AppConstants.error,
              text: 'The payment window for this order has expired. Your '
                  'items were released. You can place a new order anytime.',
            ),
          ),
        ],
        const SizedBox(height: 16),
        GcashRiseIn(order: 1, child: _amountPanel()),
        const SizedBox(height: 14),
        GcashRiseIn(order: 2, child: _accountPanel(storeLabel)),
        const SizedBox(height: 14),
        GcashRiseIn(order: 3, child: _stepsPanel()),
        const SizedBox(height: 14),
        GcashRiseIn(order: 4, child: _proofPanel()),
        const SizedBox(height: 18),
        Text(
          'CUFMAI receives your GCash payment and remits it to $storeLabel '
          'after the transfer is verified. Your order is only prepared once '
          'the store accepts your proof.',
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
    final low = _timeLeft < const Duration(minutes: 5);
    return GcashPanel(
      dark: true,
      eyebrow: 'Exact amount',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '₱${widget.totalAmount.toStringAsFixed(2)}',
            style: AppConstants.monoStyle(
              fontSize: 34,
              fontWeight: FontWeight.w700,
              color: kGcashReceiptInk,
            ),
          ),
          const SizedBox(height: 8),
          if (_expired)
            Text(
              'Window expired — the items were released.',
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

  Widget _accountPanel(String storeLabel) {
    final hasName = widget.gcashAccountName?.isNotEmpty ?? false;
    final hasNumber = widget.gcashNumber?.isNotEmpty ?? false;
    final hasCode = widget.orderCode?.isNotEmpty ?? false;
    return GcashPanel(
      eyebrow: 'Send to',
      title: 'Platform GCash account',
      description:
          'CUFMAI receives the payment and $storeLabel is paid out at the '
          'end of the day.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasCode) ...[
            GcashInsetTile(
              child: GcashCopyRow(
                label: 'Order code — paste into the GCash note',
                value: widget.orderCode!,
                onCopy: () => _copyToClipboard(widget.orderCode!),
                semanticsLabel: 'Copy order code',
              ),
            ),
            const SizedBox(height: 14),
          ],
          Center(child: _qrBlock()),
          if (hasName || hasNumber) const SizedBox(height: 16),
          if (hasName)
            GcashCopyRow(
              label: 'Account name',
              value: widget.gcashAccountName!,
              onCopy: () => _copyToClipboard(widget.gcashAccountName!),
              semanticsLabel: 'Copy account name',
            ),
          if (hasName && hasNumber) const SizedBox(height: 12),
          if (hasNumber)
            GcashCopyRow(
              label: 'GCash number',
              value: widget.gcashNumber!,
              onCopy: () => _copyToClipboard(widget.gcashNumber!),
              semanticsLabel: 'Copy GCash number',
            ),
        ],
      ),
    );
  }

  Widget _qrBlock() {
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
          widget.gcashQrUrl!,
          width: 190,
          height: 190,
          fit: BoxFit.contain,
          semanticLabel: 'Platform GCash QR code',
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
                'exact amount, and paste the order code in the note.',
          ),
          const SizedBox(height: 10),
          _stepRow(
            '2',
            'Come back here and submit the reference number, the account name '
                'you sent from, the amount and a screenshot of the receipt.',
          ),
          const SizedBox(height: 10),
          _stepRow(
            '3',
            'The store checks the transfer against the platform account. If '
                'something does not match you get the reason and can resubmit '
                '(3 tries total).',
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
          'The reference, sender and amount must match the transfer the '
          'platform account received.',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              controller: _refController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              maxLength: 13,
              style: AppConstants.monoStyle(fontSize: 14),
              decoration: _decoration(
                label: 'GCash reference number',
                hint: 'e.g. 0011223344556',
              ),
              validator: (v) {
                final digits = (v ?? '').replaceAll(RegExp(r'\D'), '');
                if (digits.length != 12 && digits.length != 13) {
                  return 'Enter the 12–13 digit reference number from your receipt';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _senderController,
              textCapitalization: TextCapitalization.words,
              maxLength: 60,
              decoration: _decoration(
                label: 'GCash account name you sent from',
                hint: 'e.g. Juan D.',
              ),
              validator: (v) => (v ?? '').trim().length < 2
                  ? 'Enter the name on the GCash account you paid from'
                  : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _amountController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              style: AppConstants.monoStyle(fontSize: 14),
              decoration: _decoration(
                label: 'Amount you sent',
                prefix: '₱ ',
                helper: 'Must match '
                    '₱${widget.totalAmount.toStringAsFixed(2)} exactly',
              ),
              validator: (v) {
                final parsed = double.tryParse((v ?? '').trim());
                if (parsed == null || parsed <= 0) {
                  return 'Enter the amount you sent';
                }
                if ((parsed - widget.totalAmount).abs() > 0.009) {
                  return 'Send exactly ₱${widget.totalAmount.toStringAsFixed(2)}';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            _buildScreenshotPicker(),
            if (_readingReceipt || _receipt != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: _buildReceiptReadback(),
              ),
            if (_error && _errorMessage != null) ...[
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
              icon: Icons.arrow_forward,
              loading: _submitting,
              onPressed: (_submitting || _expired) ? null : _submitProof,
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _decoration({
    required String label,
    String? hint,
    String? helper,
    String? prefix,
  }) {
    final hairline = AppConstants.primary.withValues(alpha: 0.14);
    return InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helper,
      helperMaxLines: 2,
      prefixText: prefix,
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
                                color:
                                    AppConstants.secondary.withValues(alpha: 0.6),
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
                              'Required — we read the reference and amount '
                              'from it',
                              style: AppConstants.bodyStyle(
                                fontSize: 11,
                                height: 1.3,
                                color:
                                    AppConstants.secondary.withValues(alpha: 0.6),
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

  /// What the attached screenshot yielded, and whether its amount is the order
  /// total. Not a gate — the field validator and the submit RPC own that — it
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
        text: "Couldn't read the receipt automatically — type the reference "
            'number and the amount exactly as they appear on it.',
      );
    }

    final expected = widget.totalAmount;
    final read = parsed.amount;
    if (read != null && (read - expected).abs() > 0.009) {
      return GcashBanner(
        icon: Icons.error_outline,
        color: AppConstants.error,
        text: 'Your receipt shows \u20b1${read.toStringAsFixed(2)}, but this '
            'order is \u20b1${expected.toStringAsFixed(2)}. Only the exact '
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
        text: 'Filled from your screenshot: $refText and '
            '\u20b1${read.toStringAsFixed(2)} — matches the order total. '
            'Double-check both before submitting.',
      );
    }
    return GcashBanner(
      icon: Icons.info_outline,
      color: AppConstants.statusPendingColor,
      text: 'Filled the $refText from your screenshot. Add the amount you '
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

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '${minutes}m ${seconds.toString().padLeft(2, '0')}s';
  }
}
