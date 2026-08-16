import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/screens/auth/seller_application_flow.dart';
import 'package:app/utils/dev_mode.dart';

/// Coverage for the store photos added to Step 4 (Storefront): the seller
/// must upload a store-front photo (which becomes the store banner) and a
/// product photo before the application can be submitted.
///
/// DevMode skips Steps 1–3 (their Continues hit Supabase), then is turned
/// off so Step 4's real submit validation runs.
void main() {
  tearDown(() {
    if (DevMode.instance.isEnabled) DevMode.instance.toggle();
  });

  Future<void> pumpToStorefrontStep(WidgetTester tester) async {
    DevMode.instance.toggle(); // ON
    await tester.pumpWidget(const MaterialApp(home: SellerApplicationFlow()));
    expect(find.text('Create your seller account'), findsOneWidget);

    for (var i = 0; i < 3; i++) {
      final continueBtn = find.widgetWithText(FilledButton, 'Continue');
      await tester.ensureVisible(continueBtn);
      await tester.pumpAndSettle();
      await tester.tap(continueBtn);
      await tester.pumpAndSettle();
    }

    DevMode.instance.toggle(); // OFF — real validation from here on
    await tester.pumpAndSettle();
    expect(find.text('Set up your storefront'), findsOneWidget);
  }

  testWidgets('storefront step shows the store front photo and all 5 '
      'product photo uploads', (tester) async {
    await pumpToStorefrontStep(tester);

    expect(find.text('Store front photo'), findsOneWidget);
    for (var i = 1; i <= 5; i++) {
      expect(find.byKey(ValueKey('product-slot-$i')), findsOneWidget);
    }
  });

  testWidgets('submit is blocked until the store photos are added',
      (tester) async {
    await pumpToStorefrontStep(tester);

    // Fill the store form so only the photo gates remain.
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Reyes Handcrafted Leather');
    await tester.enterText(
      fields.at(1),
      'Handmade leather shoes from Carcar City, crafted by three generations.',
    );
    await tester.pumpAndSettle();

    // No store photos → Submit must refuse (form validates first, then the
    // photo gate fires in order: store front, then product).
    final submitBtn = find.widgetWithText(FilledButton, 'Submit application');
    await tester.ensureVisible(submitBtn);
    await tester.pumpAndSettle();
    await tester.tap(submitBtn);
    await tester.pumpAndSettle();
    expect(
      find.text('Please add a photo of your store front.'),
      findsOneWidget,
    );
  });
}
