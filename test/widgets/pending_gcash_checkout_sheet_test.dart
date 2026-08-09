import 'package:app/services/direct_gcash_service.dart';
import 'package:app/widgets/pending_gcash_checkout_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A pending order with a live 7-minute window and one reserved item.
PendingGcashOrder _order({
  bool proofSubmitted = false,
  List<PendingGcashItem>? items,
}) {
  final now = DateTime.now();
  return PendingGcashOrder(
    id: 'order-64fabc26',
    storeId: 'store-1',
    totalAmount: 490,
    deadline: now.add(const Duration(minutes: 7)),
    createdAt: now.subtract(const Duration(minutes: 23)),
    proofSubmitted: proofSubmitted,
    items: items ??
        const [
          PendingGcashItem(
            productId: 'p1',
            productName: 'Classic Leather Loafers',
            size: '42',
            quantity: 1,
            unitPrice: 390,
          ),
        ],
  );
}

Future<void> _openSheet(WidgetTester tester, PendingGcashOrder pending) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () =>
                  showPendingGcashCheckoutSheet(context: context, pending: pending),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  // Entrance: route slide (~250ms) + content fade/slide (280ms).
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

void main() {
  testWidgets('renders headline, order meta, amount and reserved item',
      (tester) async {
    await _openSheet(tester, _order());

    expect(find.text('You have a pending GCash checkout'), findsOneWidget);
    expect(find.text('Order #64fabc26'), findsOneWidget);
    expect(find.text('₱490.00'), findsOneWidget);
    expect(find.text('Classic Leather Loafers'), findsOneWidget);
    expect(find.text('EU 42 · Qty 1'), findsOneWidget);
    expect(find.text('₱390.00'), findsOneWidget); // item line total
    expect(find.text('1 item'), findsOneWidget); // "In this order" count chip
    expect(tester.takeException(), isNull);
  });

  testWidgets('countdown chip renders a ticking time label and a ring',
      (tester) async {
    // Injectable clock makes the 1s tick deterministic (widget tests cannot
    // advance DateTime.now(), so the sheet accepts a `now` provider).
    var current = DateTime.now();
    final pending = PendingGcashOrder(
      id: 'order-64fabc26',
      storeId: 'store-1',
      totalAmount: 490,
      deadline: current.add(const Duration(minutes: 7)),
      createdAt: current.subtract(const Duration(minutes: 23)),
      items: const [
        PendingGcashItem(
          productId: 'p1',
          productName: 'Classic Leather Loafers',
          size: '42',
          quantity: 1,
          unitPrice: 390,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => showPendingGcashCheckoutSheet(
                  context: context,
                  pending: pending,
                  now: () => current,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    String label() => tester
            .widget<Text>(find.textContaining('left', findRichText: false))
            .data ??
        '';

    // Live label: `7m 00s left`-style countdown in tabular mono text.
    expect(label(), '7m 00s left');

    // Advance the injected clock + fake time → the periodic timer repaints.
    current = current.add(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 3));
    expect(label(), '6m 57s left');

    // The ring painter is present and paints a fraction of the window.
    final ringPainters = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .where((p) => p.painter != null);
    expect(ringPainters.isNotEmpty, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Complete Payment returns the complete action',
      (tester) async {
    PendingCheckoutAction? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await showPendingGcashCheckoutSheet(
                    context: context,
                    pending: _order(),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    await tester.ensureVisible(find.text('Complete Payment'));
    await tester.tap(find.text('Complete Payment'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(result, PendingCheckoutAction.complete);
  });

  testWidgets('Not Now dismisses with a null result', (tester) async {
    PendingCheckoutAction? result;
    var completed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await showPendingGcashCheckoutSheet(
                    context: context,
                    pending: _order(),
                  );
                  completed = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    await tester.ensureVisible(find.text('Not Now'));
    await tester.tap(find.text('Not Now'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(completed, isTrue);
    expect(result, isNull);
  });

  testWidgets('Cancel Pending Order returns the cancel action',
      (tester) async {
    PendingCheckoutAction? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await showPendingGcashCheckoutSheet(
                    context: context,
                    pending: _order(),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    await tester.ensureVisible(find.text('Cancel Pending Order'));
    await tester.tap(find.text('Cancel Pending Order'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(result, PendingCheckoutAction.cancel);
  });

  testWidgets('multi-item order: +1 badge and expand reveals all items',
      (tester) async {
    final items = const [
      PendingGcashItem(
        productId: 'p1',
        productName: 'Classic Leather Loafers',
        size: '42',
        quantity: 1,
        unitPrice: 390,
      ),
      PendingGcashItem(
        productId: 'p2',
        productName: 'Suede Chelsea Boots',
        size: '43',
        quantity: 2,
        unitPrice: 50,
      ),
    ];
    await _openSheet(tester, _order(items: items));

    // Collapsed: primary item visible, the second hidden behind +1.
    expect(find.text('Classic Leather Loafers'), findsOneWidget);
    expect(find.text('Suede Chelsea Boots'), findsNothing);
    expect(find.text('+1'), findsOneWidget);
    expect(find.text('3 items'), findsOneWidget); // 1 + 2 = 3 total qty

    // Expand → both items + their line totals visible. The toggle counts
    // remaining QUANTITY (2) to stay consistent with the "3 items" chip.
    await tester.ensureVisible(find.text('View 2 more items'));
    await tester.tap(find.text('View 2 more items'));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Suede Chelsea Boots'), findsOneWidget);
    expect(find.text('₱100.00'), findsOneWidget); // 50 × 2
    expect(find.text('+1'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('proof-submitted order: Track My Order, no cancel action',
      (tester) async {
    await _openSheet(tester, _order(proofSubmitted: true));

    expect(find.text('Track My Order'), findsOneWidget);
    expect(find.text('Complete Payment'), findsNothing);
    expect(find.text('Cancel Pending Order'), findsNothing);
    // Proof-specific body copy replaces the "window still open" wording.
    expect(find.textContaining('proof is with the store'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('order without items falls back to a reserved-items card',
      (tester) async {
    await _openSheet(tester, _order(items: const []));

    expect(find.text('Items reserved for this order'), findsOneWidget);
    expect(find.text('₱490.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('close (X) dismisses the sheet', (tester) async {
    var completed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  await showPendingGcashCheckoutSheet(
                    context: context,
                    pending: _order(),
                  );
                  completed = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    await tester.tap(find.byTooltip('Not now'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(completed, isTrue);
    expect(find.text('You have a pending GCash checkout'), findsNothing);
  });
}
