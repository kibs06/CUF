import 'package:flutter/material.dart';

import '../../constants/app_constants.dart';
import '../../utils/in_store_barcode.dart';

/// Printable-style preview of an in-store EAN-13 product label.
///
/// Bars are always black-on-white (even in dark mode) because that contrast is
/// what keeps the label scannable. An invalid value renders a muted hint
/// instead of a wrong symbol.
class InStoreBarcodeLabel extends StatelessWidget {
  final String code;

  /// Width of one EAN module in logical pixels. Bigger modules scan easier
  /// from a phone screen or a printed sticker.
  final double moduleWidth;

  /// Height of the bar field, excluding the human-readable digits below.
  final double barHeight;

  const InStoreBarcodeLabel({
    super.key,
    required this.code,
    this.moduleWidth = 2.2,
    this.barHeight = 76,
  });

  static const _leftOdd = <String>[
    '0001101',
    '0011001',
    '0010011',
    '0111101',
    '0100011',
    '0110001',
    '0101111',
    '0111011',
    '0110111',
    '0001011',
  ];
  static const _leftEven = <String>[
    '0100111',
    '0110011',
    '0011011',
    '0100001',
    '0011101',
    '0111001',
    '0000101',
    '0010001',
    '0001001',
    '0010111',
  ];
  static const _right = <String>[
    '1110010',
    '1100110',
    '1101100',
    '1000010',
    '1011100',
    '1001110',
    '1010000',
    '1000100',
    '1001000',
    '1110100',
  ];

  /// First-digit → left-group parity (`O` = odd/L, `E` = even/G).
  static const _parity = <String>[
    'OOOOOO',
    'OOEOEE',
    'OOEEOE',
    'OOEEEO',
    'OEOOEE',
    'OEEOOE',
    'OEEEOO',
    'OEOEOE',
    'OEOEEO',
    'OEEOEO',
  ];

  /// Encodes a validated 13-digit code into its 95-module bar pattern.
  static String encode(String code) {
    final digits = code.split('').map(int.parse).toList();
    final pattern = StringBuffer('101');
    final parity = _parity[digits[0]];
    for (var i = 0; i < 6; i++) {
      final digit = digits[i + 1];
      pattern.write(parity[i] == 'O' ? _leftOdd[digit] : _leftEven[digit]);
    }
    pattern.write('01010');
    for (var i = 0; i < 6; i++) {
      pattern.write(_right[digits[i + 7]]);
    }
    pattern.write('101');
    return pattern.toString();
  }

  @override
  Widget build(BuildContext context) {
    if (!isValidEan13(code)) {
      return Text(
        'A valid 13-digit EAN renders a scannable label preview here.',
        style: AppConstants.bodyStyle(
          fontSize: 12,
          color: AppConstants.secondary.withValues(alpha: 0.6),
        ),
      );
    }
    const quietModules = 10;
    final modules = encode(code.trim());
    final width = (modules.length + quietModules * 2) * moduleWidth;
    return Semantics(
      label: 'In-store barcode $code',
      image: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        decoration: BoxDecoration(
          // Printable barcode paper must stay pure white to stay scannable.
          color: Colors.white, // printable barcode paper stays white for scannability
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppConstants.borderGray.withValues(alpha: 0.5),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CustomPaint(
              size: Size(width, barHeight),
              painter: _Ean13Painter(
                modules: modules,
                moduleWidth: moduleWidth,
                quietModules: quietModules,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              code.trim(),
              style: AppConstants.monoStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
            ),
            Text(
              'IN-STORE USE ONLY',
              style: AppConstants.monoStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: Colors.black54,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Ean13Painter extends CustomPainter {
  final String modules;
  final double moduleWidth;
  final int quietModules;

  const _Ean13Painter({
    required this.modules,
    required this.moduleWidth,
    required this.quietModules,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()..color = Colors.white;
    canvas.drawRect(Offset.zero & size, background);
    final bar = Paint()..color = Colors.black;
    for (var i = 0; i < modules.length; i++) {
      if (modules.codeUnitAt(i) != 0x31) continue;
      final left = (quietModules + i) * moduleWidth;
      canvas.drawRect(Rect.fromLTWH(left, 0, moduleWidth, size.height), bar);
    }
  }

  @override
  bool shouldRepaint(covariant _Ean13Painter oldDelegate) =>
      oldDelegate.modules != modules ||
      oldDelegate.moduleWidth != moduleWidth ||
      oldDelegate.quietModules != quietModules;
}
