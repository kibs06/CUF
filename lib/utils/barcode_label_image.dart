import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../widgets/seller/in_store_barcode_label.dart';
import 'in_store_barcode.dart';

/// Renders an in-store barcode label to PNG bytes, so the seller can send it
/// anywhere the system share sheet reaches (Messenger, Viber, email…).
///
/// The pixels mirror the on-screen preview and the printed sticker: product
/// name on top, the same 95-module EAN-13 symbol from
/// [InStoreBarcodeLabel.encode], the digits, and the in-store caption — always
/// black-on-white, because that contrast is what keeps the label scannable
/// no matter which app displays the image.
///
/// Throws [ArgumentError] for anything [isValidEan13] rejects, so a broken
/// code can never be screenshotted or shared as a wrong symbol.
Future<Uint8List> renderBarcodeLabelPng({
  required String productName,
  required String code,
  double scale = 3,
}) async {
  final digits = code.trim();
  if (!isValidEan13(digits)) {
    throw ArgumentError('Cannot render an invalid EAN-13: "$code".');
  }
  final name = productName.trim().isEmpty ? 'Product' : productName.trim();
  final modules = InStoreBarcodeLabel.encode(digits);

  const quietModules = 10;
  const moduleWidth = 8.0;
  const pad = 64.0;
  const gapName = 36.0;
  const barHeight = 280.0;
  const gapDigits = 28.0;
  const gapCaption = 16.0;

  // Text is laid out once to measure before the canvas is sized.
  final namePainter = _text(
    name,
    const TextStyle(
      fontSize: 52,
      fontWeight: FontWeight.w700,
      color: Color(0xFF1A1A1A),
    ),
    maxLines: 2,
  );
  final digitsPainter = _text(
    digits,
    const TextStyle(
      fontSize: 56,
      fontWeight: FontWeight.w600,
      letterSpacing: 6,
      color: Colors.black,
      fontFamily: 'monospace',
      fontFamilyFallback: ['Courier'],
    ),
    maxLines: 1,
  );
  final captionPainter = _text(
    'IN-STORE USE ONLY',
    const TextStyle(
      fontSize: 30,
      fontWeight: FontWeight.w700,
      letterSpacing: 4,
      color: Color(0x99000000),
    ),
    maxLines: 1,
  );

  final symbolWidth = (modules.length + quietModules * 2) * moduleWidth;
  final contentWidth = [
    symbolWidth,
    namePainter.width,
    digitsPainter.width,
    captionPainter.width,
  ].reduce((a, b) => a > b ? a : b);
  final width = contentWidth + pad * 2;
  final height = pad +
      namePainter.height +
      gapName +
      barHeight +
      gapDigits +
      digitsPainter.height +
      gapCaption +
      captionPainter.height +
      pad;

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.scale(scale);
  canvas.drawRect(
    Offset.zero & Size(width, height),
    Paint()..color = Colors.white,
  );

  var y = pad;
  _drawCentered(canvas, namePainter, width, y);
  y += namePainter.height + gapName;

  final bar = Paint()..color = Colors.black;
  final left = (width - symbolWidth) / 2;
  for (var i = 0; i < modules.length; i++) {
    if (modules.codeUnitAt(i) != 0x31) continue;
    canvas.drawRect(
      Rect.fromLTWH(left + (quietModules + i) * moduleWidth, y, moduleWidth,
          barHeight),
      bar,
    );
  }
  y += barHeight + gapDigits;

  _drawCentered(canvas, digitsPainter, width, y);
  y += digitsPainter.height + gapCaption;
  _drawCentered(canvas, captionPainter, width, y);

  final picture = recorder.endRecording();
  final image = await picture.toImage(
    (width * scale).round(),
    (height * scale).round(),
  );
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  if (bytes == null) throw StateError('Barcode PNG encoding failed.');
  return bytes.buffer.asUint8List();
}

TextPainter _text(String value, TextStyle style, {required int maxLines}) {
  final painter = TextPainter(
    text: TextSpan(text: value, style: style),
    textDirection: TextDirection.ltr,
    textAlign: TextAlign.center,
    maxLines: maxLines,
    ellipsis: '…',
  );
  // Bound only by height: the canvas grows to the widest line instead.
  painter.layout(maxWidth: 1400);
  return painter;
}

void _drawCentered(Canvas canvas, TextPainter painter, double width, double y) {
  painter.paint(canvas, Offset((width - painter.width) / 2, y));
}
