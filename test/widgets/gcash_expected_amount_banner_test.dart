import 'package:app/screens/seller/gcash_payment_queue_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders the expected amount with two decimals and a verify label',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: GcashExpectedAmountBanner(total: 1234.56)),
      ),
    );

    expect(find.text('Verify this exact amount in your GCash app'),
        findsOneWidget);
    expect(find.text('₱1234.56'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders whole amounts with a .00 suffix (integer-valued total)',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: GcashExpectedAmountBanner(total: 490)),
      ),
    );

    expect(find.text('₱490.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders zero defensively', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: GcashExpectedAmountBanner(total: 0)),
      ),
    );

    expect(find.text('₱0.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}