import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/widgets/seller/in_store_barcode_label.dart';

void main() {
  testWidgets('renders bars and digits for a valid EAN-13', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: InStoreBarcodeLabel(code: '4006381333931'),
        ),
      ),
    );

    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.text('4006381333931'), findsOneWidget);
    expect(find.text('IN-STORE USE ONLY'), findsOneWidget);
  });

  testWidgets('renders a hint instead of a symbol for an invalid value',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: InStoreBarcodeLabel(code: 'not-a-barcode'),
        ),
      ),
    );

    expect(
      find.descendant(
        of: find.byType(InStoreBarcodeLabel),
        matching: find.byType(CustomPaint),
      ),
      findsNothing,
    );
    expect(find.textContaining('scannable label preview'), findsOneWidget);
  });

  test('encodes the full 95-module EAN-13 pattern with guards', () {
    final modules = InStoreBarcodeLabel.encode('4006381333931');
    expect(modules.length, 95);
    expect(modules.startsWith('101'), isTrue);
    expect(modules.endsWith('101'), isTrue);
    expect(modules.contains('01010'), isTrue);
    expect(RegExp(r'^[01]+$').hasMatch(modules), isTrue);
  });
}
