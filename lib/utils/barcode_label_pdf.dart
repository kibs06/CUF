import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../widgets/seller/in_store_barcode_label.dart';
import 'in_store_barcode.dart';

/// Builds a printable shelf/box label for an in-store product barcode.
///
/// The bar pattern comes from the same tested EAN-13 encoder the on-screen
/// preview uses ([InStoreBarcodeLabel.encode]), so what the seller prints is
/// exactly what the preview showed. The PDF is a small label-sized page the
/// seller can print one of — or print N copies of from the system dialog.
Future<Uint8List> buildBarcodeLabelPdf({
  required String productName,
  required String barcode,
}) async {
  final code = barcode.trim();
  if (!isValidEan13(code)) {
    throw ArgumentError.value(barcode, 'barcode', 'Must be a valid EAN-13');
  }
  final modules = InStoreBarcodeLabel.encode(code);
  final name = productName.trim().isEmpty ? 'Untagged product' : productName.trim();

  final doc = pw.Document();
  doc.addPage(
    pw.Page(
      pageFormat: const PdfPageFormat(70 * PdfPageFormat.mm, 45 * PdfPageFormat.mm),
      margin: const pw.EdgeInsets.all(4 * PdfPageFormat.mm),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Text(
            name,
            style: pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
            ),
            maxLines: 1,
          ),
          pw.SizedBox(height: 2 * PdfPageFormat.mm),
          pw.Expanded(
            child: pw.Container(
              color: PdfColors.white,
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < modules.length; i++)
                    pw.Expanded(
                      child: pw.Container(
                        color: modules.codeUnitAt(i) == 0x31
                            ? PdfColors.black
                            : PdfColors.white,
                      ),
                    ),
                ],
              ),
            ),
          ),
          pw.SizedBox(height: 1.5 * PdfPageFormat.mm),
          pw.Text(
            code,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.Text(
            'IN-STORE USE ONLY',
            textAlign: pw.TextAlign.center,
            style: const pw.TextStyle(
              fontSize: 6,
              color: PdfColors.grey600,
            ),
          ),
        ],
      ),
    ),
  );
  return doc.save();
}
