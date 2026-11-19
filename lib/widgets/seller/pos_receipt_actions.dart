import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../constants/app_constants.dart';
import '../../services/order_service.dart';
import '../../utils/pos_receipt_pdf.dart';

/// What the cashier can do with one finished POS sale: print it, email it, or
/// hand the PDF to any other app.
///
/// All three draw from the same order row, so the paper, the mailbox and the
/// phone never disagree:
/// * **Print** → the system print dialog ([Printing.layoutPdf]).
/// * **Share PDF** → the system share sheet with the file attached.
/// * **Email** → the customer's address is typed once, then the
///   `send-order-receipt` function mails the customer the same receipt card an
///   online order gets, with the A5 PDF attached. Nothing is left for the
///   cashier to finish in a composer, and the address is remembered on the
///   order so the next send starts from it.
class PosReceiptActions extends StatefulWidget {
  final Map<String, dynamic> order;
  final String storeName;
  final String storeLocation;
  final String sellerName;

  const PosReceiptActions({
    super.key,
    required this.order,
    required this.storeName,
    required this.storeLocation,
    required this.sellerName,
  });

  @override
  State<PosReceiptActions> createState() => _PosReceiptActionsState();
}

class _PosReceiptActionsState extends State<PosReceiptActions> {
  bool _printing = false;
  bool _sharing = false;
  bool _emailing = false;

  /// The address this sale was last emailed to, from the order row when the
  /// server has 20261119100000 and filled in locally right after a send.
  String? _customerEmail;

  bool get _busy => _printing || _sharing || _emailing;

  @override
  void initState() {
    super.initState();
    final saved = widget.order['customer_email']?.toString().trim() ?? '';
    _customerEmail = saved.isEmpty ? null : saved;
  }

  Future<Uint8List> _renderPdf() => buildPosReceiptPdf(
        order: widget.order,
        storeName: widget.storeName,
        storeLocation: widget.storeLocation,
        sellerName: widget.sellerName,
      );

  /// The code the customer sees on the screen, reused in the filename.
  String get _fileCode {
    final id = widget.order['id']?.toString() ?? '';
    final head = id.length >= 8 ? id.substring(0, 8) : id;
    return head.isEmpty ? 'sale' : head;
  }

  Future<void> _print() async {
    if (_busy) return;
    setState(() => _printing = true);
    try {
      await Printing.layoutPdf(
        onLayout: (_) => _renderPdf(),
        name: 'receipt-$_fileCode.pdf',
      );
    } catch (e) {
      debugPrint('[POS] printing the receipt failed: $e');
      _say('Could not open the print dialog. Try Share instead.');
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  Future<void> _share() async {
    if (_busy) return;
    setState(() => _sharing = true);
    try {
      await _shareFile();
    } catch (e) {
      debugPrint('[POS] sharing the receipt failed: $e');
      _say('Could not share the receipt. Try Print instead.');
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  /// Writes the PDF to a temp file and opens the system share sheet.
  ///
  /// No busy check of its own: the email fallback calls it while its own flag
  /// is still up.
  Future<void> _shareFile() async {
    final bytes = await _renderPdf();
    // Sharing needs a file on disk; the system sheet copies it to whichever
    // app the cashier picks, and the OS reaps the temp dir.
    final dir = await Directory.systemTemp.createTemp('pos-receipt');
    final file = File('${dir.path}/receipt-$_fileCode.pdf');
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/pdf')],
        subject: 'Receipt $_fileCode',
        text: 'Your receipt from ${widget.storeName}.',
      ),
    );
  }

  /// Ask for the customer's address, then have the receipt emailed by the
  /// `send-order-receipt` function: the same HTML card and A5 PDF an online
  /// order gets, straight from the store's mail identity, with nothing left for
  /// the cashier to finish in a composer.
  Future<void> _email() async {
    if (_busy) return;
    final address = await showDialog<String>(
      context: context,
      builder: (_) => EmailReceiptDialog(initialValue: _customerEmail),
    );
    if (address == null || address.isEmpty || !mounted) return;

    final id = widget.order['id']?.toString() ?? '';
    if (id.isEmpty) {
      _say('This sale is still saving — try again in a moment.');
      return;
    }

    // The function reads orders.customer_email, so the address has to be on the
    // order before it is asked to send; otherwise it would fall back to a
    // profile email that is not this customer's.
    _customerEmail = address;
    widget.order['customer_email'] = address;
    setState(() => _emailing = true);
    try {
      final stored =
          await OrderService().savePosCustomerEmail(orderId: id, email: address);
      if (!stored) {
        _say('Could not save the address. Check the connection, then retry.');
        return;
      }
      final result = await OrderService().sendReceiptEmail(id);
      if (!mounted) return;
      if (result['sent'] == true) {
        // The same stamp the function wrote on the server, so this sale now
        // shows as emailed here too.
        setState(() {
          widget.order['receipt_emailed_at'] ??=
              DateTime.now().toUtc().toIso8601String();
          widget.order['receipt_email_to'] = address;
        });
      }
      _say(_receiptResultMessage(result, address));
    } catch (e) {
      debugPrint('[POS] emailing the receipt failed: $e');
      _say('Could not email the receipt. Try again, or Share PDF.');
    } finally {
      if (mounted) setState(() => _emailing = false);
    }
  }

  /// What the cashier reads after the function answers. Every refusal it can
  /// return has a line here, so "it did nothing" never happens on screen.
  String _receiptResultMessage(Map<String, dynamic> result, String address) {
    if (result['sent'] == true) return 'Receipt emailed to $address.';
    switch ((result['reason'] ?? '').toString()) {
      case 'already_sent':
        return "This sale's receipt was already emailed.";
      case 'no_email':
        return 'No email address on this sale — add one and try again.';
      case 'in_flight':
        return 'This receipt is already being sent. Give it a moment.';
      case 'email_not_configured':
        return 'Email is not set up on the server. Use Share PDF instead.';
      case 'smtp_failed':
        final detail = (result['detail'] ?? '').toString().trim();
        return detail.isEmpty
            ? 'The mail server refused the receipt. Try again shortly.'
            : 'The mail server refused the receipt: $detail';
      default:
        return 'The receipt was not sent. Try again, or Share PDF.';
    }
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: AppConstants.bodyStyle(fontSize: 13)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  ButtonStyle _outlinedStyle() => OutlinedButton.styleFrom(
        foregroundColor: AppConstants.primary,
        side: BorderSide(color: AppConstants.primary.withValues(alpha: 0.4)),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      );

  Widget _spinner() => SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: AppConstants.primary,
        ),
      );

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _share,
                  icon: _sharing ? _spinner() : const Icon(Icons.ios_share, size: 18),
                  label: Text(
                    'Share PDF',
                    style: AppConstants.bodyStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: _outlinedStyle(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _email,
                  icon: _emailing
                      ? _spinner()
                      : const Icon(Icons.mail_outline, size: 18),
                  label: Text(
                    'Email',
                    style: AppConstants.bodyStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: _outlinedStyle(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _busy ? null : _print,
              icon: _printing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.print_outlined, size: 18),
              label: Text(
                'Print receipt',
                style: AppConstants.bodyStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppConstants.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Asks for the customer's address before Gmail opens.
///
/// One field: the cashier is mid-handover, and the address is the only thing
/// the receipt email is missing.
class EmailReceiptDialog extends StatefulWidget {
  /// Prefills the field with the address this sale was last sent to.
  final String? initialValue;

  const EmailReceiptDialog({super.key, this.initialValue});

  @override
  State<EmailReceiptDialog> createState() => _EmailReceiptDialogState();
}

class _EmailReceiptDialogState extends State<EmailReceiptDialog> {
  static final _pattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  late final TextEditingController _controller =
      TextEditingController(text: widget.initialValue ?? '');
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (!_pattern.hasMatch(value)) {
      setState(() => _error = 'Enter a valid email address');
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppConstants.surfaceLight,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(
        'Email the receipt',
        style: AppConstants.bodyStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'The customer gets the same receipt card and PDF an online order '
            'does. Check the address, then send.',
            style: AppConstants.bodyStyle(
              fontSize: 12.5,
              color: AppConstants.secondary.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _submit(),
            style: AppConstants.bodyStyle(fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'customer@example.com',
              errorText: _error,
              filled: true,
              fillColor: AppConstants.sellerSurface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Cancel',
            style: AppConstants.bodyStyle(
              fontSize: 13,
              color: AppConstants.secondary.withValues(alpha: 0.7),
            ),
          ),
        ),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(backgroundColor: AppConstants.primary),
          child: Text(
            'Send receipt',
            style: AppConstants.bodyStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}
