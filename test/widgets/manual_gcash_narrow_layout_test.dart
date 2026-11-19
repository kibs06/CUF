import 'package:app/constants/app_theme.dart';
import 'package:app/screens/customer/gcash_pay_screen.dart';
import 'package:app/screens/seller/gcash_payment_queue_screen.dart';
import 'package:app/services/direct_gcash_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Narrow-width proof for the two densest manual-GCash layouts.
///
/// Both are pumped at a real 320 dp phone width with the worst data the flow
/// can produce: a 13-digit reference, a long payer/store name and a six-figure
/// peso amount. An overflow in either one throws during layout, so
/// `tester.takeException()` is the assertion — plus a rect check that the
/// reference and the copy controls genuinely sit inside the 320 dp surface
/// rather than being clipped off the edge.
const _reference = '0011223344556';
const _longName = 'Maria Clara Santos Del Rosario';
const _longStore = 'CUFMAI Flagship — Ayala Center Cebu';
const _total = 123456.78;
const _orderCode = 'A7K2M9QX';
const _orderId = 'a1b2c3d4-1111-4222-8333-444455556666';

/// The real service resolves `Supabase.instance.client` the moment the screen
/// builds, which needs a signed-in app. The only call this screen makes on
/// entry is the expiry sweep, so that is all this stand-in overrides — every
/// other code path under test is the production widget.
class _OfflineGcashService extends DirectGcashService {
  _OfflineGcashService()
      : super(
          client: SupabaseClient(
            'http://127.0.0.1:1',
            'test-anon-key',
            // No timer means no pending-timer failure in fake async; the
            // client is never allowed to reach the network anyway.
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          ),
        );

  @override
  Future<void> expireOverdue() async {}
}

Map<String, dynamic> _order({bool amountDiffers = false}) =>
    <String, dynamic>{
      'id': _orderId,
      'total_amount': _total,
      'order_code': _orderCode,
      'review_deadline':
          DateTime.now().add(const Duration(hours: 12)).toIso8601String(),
      'payment_flagged': false,
      'profiles': <String, dynamic>{'full_name': _longName},
      'gcash_payment_proofs': <Map<String, dynamic>>[
        <String, dynamic>{
          'reference_number': _reference,
          'sender_name': _longName,
          'amount_paid': amountDiffers ? 999.0 : _total,
          'submitted_at': DateTime.now().toIso8601String(),
          'attempt_no': 2,
        },
      ],
    };

void main() {
  /// 320 dp wide, tall enough that the whole tree is laid out (a short surface
  /// would hide the rows below the fold and prove nothing about them).
  Future<void> pumpAt(
    WidgetTester tester,
    Widget page, {
    double scale = 1.0,
  }) async {
    tester.view.physicalSize = const Size(320, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: page,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  group('seller review card at 320 dp', () {
    Future<void> pumpCard(
      WidgetTester tester, {
      required VoidCallback onAccept,
      required VoidCallback onReject,
      bool amountDiffers = false,
      double scale = 1.0,
    }) async {
      await pumpAt(
        tester,
        Scaffold(
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: GcashOrderCard(
                order: _order(amountDiffers: amountDiffers),
                screenshotUrl: null,
                now: DateTime.now(),
                onConfirm: onAccept,
                onReject: onReject,
              ),
            ),
          ),
        ),
        scale: scale,
      );
    }

    testWidgets('long reference, payer and amount lay out without overflow',
        (tester) async {
      await pumpCard(tester, onAccept: () {}, onReject: () {});

      expect(tester.takeException(), isNull);
      expect(find.text(_reference), findsOneWidget);
      expect(find.text(_longName), findsNWidgets(2));
      expect(find.text('₱123456.78'), findsWidgets);

      // The 13-digit reference is inside the surface, not clipped past it.
      expect(tester.getRect(find.text(_reference)).right, lessThanOrEqualTo(320));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the decision pills stack and stay tappable at this width',
        (tester) async {
      var accepted = 0;
      var rejected = 0;
      await pumpCard(
        tester,
        onAccept: () => accepted++,
        onReject: () => rejected++,
      );
      expect(tester.takeException(), isNull);

      final accept = find.text('Verify & accept');
      final reject = find.text('Reject');
      expect(accept, findsOneWidget);
      expect(reject, findsOneWidget);

      // Below 320 dp of card width the pills stack: accept above reject, so
      // neither is squeezed to an ellipsis or pushed off the edge.
      expect(tester.getCenter(accept).dy, lessThan(tester.getCenter(reject).dy));
      expect(tester.getCenter(accept).dx, lessThan(320));
      expect(tester.getCenter(reject).dx, lessThan(320));

      await tester.tap(accept);
      await tester.pump();
      await tester.tap(reject);
      await tester.pump();

      expect(accepted, 1);
      expect(rejected, 1);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a mismatched amount is named at width', (tester) async {
      await pumpCard(
        tester,
        onAccept: () {},
        onReject: () {},
        amountDiffers: true,
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Differs from ₱123456.78'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('survives a larger text scale without overflowing',
        (tester) async {
      await pumpCard(
        tester,
        onAccept: () {},
        onReject: () {},
        scale: 1.3,
      );
      expect(tester.takeException(), isNull);
      expect(find.text(_reference), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('buyer pay screen at 320 dp', () {
    Future<void> pumpPay(
      WidgetTester tester, {
      String? gcashNumber = '09171234567',
      String? accountName = _longName,
      double scale = 1.0,
    }) async {
      await pumpAt(
        tester,
        GcashPayScreen(
          service: _OfflineGcashService(),
          orderId: _orderId,
          storeId: 'store-1',
          totalAmount: _total,
          storeName: _longStore,
          gcashNumber: gcashNumber,
          gcashAccountName: accountName,
          orderCode: _orderCode,
        ),
        scale: scale,
      );
    }

    testWidgets('order code, long account name, number and amount all fit',
        (tester) async {
      await pumpPay(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Send ₱123456.78'), findsOneWidget);
      expect(find.text(_orderCode), findsOneWidget);
      expect(find.text(_longName), findsOneWidget);
      expect(find.text('09171234567'), findsOneWidget);

      expect(tester.getRect(find.text('09171234567')).right, lessThanOrEqualTo(320));
      expect(tester.getRect(find.text(_longName)).right, lessThanOrEqualTo(320));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the copy controls are hit-testable at this width',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpPay(tester);
      expect(tester.takeException(), isNull);

      // One copy circle per value: order code, account name, GCash number.
      final copyControls = find.byIcon(Icons.content_copy_rounded);
      expect(copyControls, findsNWidgets(3));

      // Each control is one labeled, actionable button rather than an unnamed
      // icon that happens to respond to taps.
      final labelled = tester
          .widgetList<Semantics>(find.byType(Semantics))
          .where((node) => (node.properties.label ?? '').startsWith('Copy '))
          .toList();
      expect(
        labelled.map((node) => node.properties.label),
        containsAll(
          <String>[
            'Copy order code',
            'Copy account name',
            // The number's control also brings GCash to the front, so its
            // label names that follow-up action.
            'Copy GCash number and open GCash to send the payment',
          ],
        ),
      );
      expect(labelled.every((node) => node.properties.button == true), isTrue);
      expect(labelled.every((node) => node.properties.onTap != null), isTrue);

      // Every 40 dp target sits inside the surface, not half off it.
      for (var i = 0; i < 3; i++) {
        final rect = tester.getRect(copyControls.at(i));
        expect(rect.width, greaterThanOrEqualTo(40));
        expect(rect.right, lessThanOrEqualTo(320));
      }

      // Clipboard.setData is a platform call. No handler means its future
      // never completes under the test binding, so answer it the way Android
      // does and keep whatever the control asked to copy.
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            final args = call.arguments as Map?;
            copied.add(args?['text'] as String? ?? '');
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );

      await tester.tap(copyControls.last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(copied, <String>['09171234567']);
      // Tapping the number also hands the customer to GCash, so the
      // confirmation names the copy instead of leaving the next step
      // implicit.
      expect(find.textContaining('copied'), findsWidgets);

      semantics.dispose();
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('survives a larger text scale without overflowing',
        (tester) async {
      await pumpPay(tester, scale: 1.3);
      expect(tester.takeException(), isNull);
      expect(find.text(_orderCode), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
