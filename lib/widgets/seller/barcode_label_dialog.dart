import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../constants/app_constants.dart';
import '../../constants/seller_theme_constants.dart';
import '../../services/product_service.dart';
import '../../utils/barcode_label_image.dart';
import '../../utils/barcode_label_pdf.dart';
import '../../utils/in_store_barcode.dart';
import 'in_store_barcode_label.dart';

/// The product barcode label, presented as a small branded card instead of a
/// plain alert: gold-accent header with the product name, the scannable
/// black-on-white preview, and full-width Share above a Copy/Print row — one
/// action per line of space, so no label can ever wrap mid-word the way three
/// cramped buttons did.
///
/// Two states, one card:
/// * a valid system EAN-13 renders the scannable preview with Copy, Share
///   (PNG through the system share sheet: Messenger, Viber, email…) and
///   Print;
/// * a legacy seller-entered code is not a valid EAN-13, so there is no
///   symbol to preview, print or share — and tapping Share used to die
///   silently inside the PNG renderer. That state instead shows the raw code
///   with an amber explainer and a one-tap repair that swaps in a fresh
///   system code.
///
/// Surfaces come from [SellerTheme] so the card reads correctly in both
/// themes; the bars themselves stay black-on-white either way, because that
/// contrast is what keeps the label scannable.
class BarcodeLabelDialog extends StatefulWidget {
  final String productName;
  final String code;
  final String productId;

  /// Fired with the fresh code after a legacy-code repair, so the opener can
  /// sync its own copy (action sheet, grid) without a full reload.
  final ValueChanged<String>? onCodeAssigned;

  const BarcodeLabelDialog({
    super.key,
    required this.productName,
    required this.code,
    required this.productId,
    this.onCodeAssigned,
  });

  @override
  State<BarcodeLabelDialog> createState() => _BarcodeLabelDialogState();
}

class _BarcodeLabelDialogState extends State<BarcodeLabelDialog> {
  late String _code = widget.code.trim();
  bool _sharing = false;
  bool _repairing = false;

  bool get _busy => _sharing || _repairing;

  /// Only a valid EAN-13 has a symbol worth previewing, printing or sharing.
  bool get _valid => isValidEan13(_code);

  String get _name =>
      widget.productName.trim().isEmpty ? 'Product' : widget.productName.trim();

  void _copy() {
    Clipboard.setData(ClipboardData(text: _code));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Barcode copied.')),
    );
  }

  /// Renders the label to a PNG and opens the system share sheet, so the
  /// seller can send it through Messenger or any other app that takes images.
  Future<void> _share() async {
    if (_busy || !_valid) return;
    setState(() => _sharing = true);
    try {
      final png = await renderBarcodeLabelPng(
        productName: _name,
        code: _code,
      );
      final dir = await Directory.systemTemp.createTemp('barcode');
      final file = File('${dir.path}/barcode-$_code.png');
      await file.writeAsBytes(png);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'image/png')],
          text: '$_name — in-store barcode $_code',
          subject: '$_name barcode',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not share the label. Please try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _print() async {
    if (_busy || !_valid) return;
    Navigator.of(context).pop();
    try {
      await Printing.layoutPdf(
        onLayout: (_) => buildBarcodeLabelPdf(
          productName: _name,
          barcode: _code,
        ),
        name: 'barcode-$_code.pdf',
      );
    } catch (e) {
      // The dialog is gone; there may be no scaffold to hang an error on, so
      // failing silently here is safer than crashing on a dead context.
      debugPrint('Barcode print failed: $e');
    }
  }

  /// Swaps a legacy seller-entered code for a fresh unique system EAN-13.
  Future<void> _assignSystemCode() async {
    if (_busy) return;
    setState(() => _repairing = true);
    try {
      final service = ProductService.instance;
      final fresh = await service.generateUniqueInStoreBarcode(
        excludeProductId: widget.productId,
      );
      await service.updateProductBarcode(
        productId: widget.productId,
        barcode: fresh,
      );
      widget.onCodeAssigned?.call(fresh);
      if (!mounted) return;
      setState(() => _code = fresh);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('System barcode assigned.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not assign a barcode: $e')),
      );
    } finally {
      if (mounted) setState(() => _repairing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: SellerTheme.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: SellerTheme.amber.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.qr_code_2,
                    color: SellerTheme.amber,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _name,
                        style: AppConstants.headlineStyle(fontSize: 16),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'In-store barcode · scan at POS',
                        style: AppConstants.bodyStyle(
                          fontSize: 12,
                          color: SellerTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_valid)
              // Compact modules: the preview only has to read clearly, not
              // fill the card — the tall bars before made the dialog tower
              // over small phones.
              InStoreBarcodeLabel(
                code: _code,
                moduleWidth: 1.6,
                barHeight: 52,
              )
            else
              _LegacyCodeCard(code: _code, onRepair: _assignSystemCode),
            const SizedBox(height: 12),
            // Share owns a full-width row; Copy and Print split the row below.
            // Three buttons shared one row before, and "Share"/"Print" wrapped
            // mid-word on narrow phones — one action per line of space fixes
            // it without shrinking text to unreadable sizes.
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: (_busy || !_valid) ? null : _share,
                style: FilledButton.styleFrom(
                  backgroundColor: SellerTheme.amber,
                  foregroundColor: SellerTheme.espressoDark,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: _sharing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.share_outlined, size: 18),
                label: Text(_sharing ? 'Sending…' : 'Share'),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: _busy ? null : _copy,
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Copy'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: (_busy || !_valid) ? null : _print,
                    icon: const Icon(Icons.print_outlined, size: 18),
                    label: const Text('Print'),
                  ),
                ),
              ],
            ),
          ],
          ),
        ),
      ),
    );
  }
}

/// What a legacy seller-entered code looks like in the label dialog: the raw
/// digits in mono (copy still works), an amber explainer saying why there is
/// no scannable symbol, and the one-tap repair — instead of the old dead-end
/// hint that left Share and Print to fail silently.
class _LegacyCodeCard extends StatelessWidget {
  final String code;
  final VoidCallback onRepair;

  const _LegacyCodeCard({required this.code, required this.onRepair});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppConstants.borderGray.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        children: [
          Text(
            code,
            textAlign: TextAlign.center,
            style: AppConstants.monoStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'This is an old seller-entered code, not a scannable EAN-13 — '
            'it cannot print or share as a barcode.',
            textAlign: TextAlign.center,
            style: AppConstants.bodyStyle(
              fontSize: 12,
              color: SellerTheme.amberDark,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onRepair,
            style: FilledButton.styleFrom(
              backgroundColor: SellerTheme.amber,
              foregroundColor: SellerTheme.espressoDark,
            ),
            icon: const Icon(Icons.auto_fix_high, size: 18),
            label: const Text('Assign system code'),
          ),
        ],
      ),
    );
  }
}
