import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/constants/app_constants.dart';
import 'package:app/widgets/sole_bottom_nav.dart';

/// The pill is the AnimatedPositioned's Container child — the only
/// Container inside it.
final Finder _pillFinder = find.descendant(
  of: find.byType(AnimatedPositioned),
  matching: find.byType(Container),
);

Widget _wrap(SoleBottomNav nav) => MaterialApp(
  home: Scaffold(body: const SizedBox(), bottomNavigationBar: nav),
);

/// Stateful harness driving [SoleBottomNav] with real setState, like the
/// customer shell — SoleBottomNav is parent-controlled, so taps must
/// actually update [currentIndex] for the pill to glide.
class _Harness extends StatefulWidget {
  const _Harness();

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  int _current = 0;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: const SizedBox(),
        bottomNavigationBar: SoleBottomNav(
          role: AppConstants.roleCustomer,
          currentIndex: _current,
          onTap: (i) => setState(() => _current = i),
        ),
      ),
    );
  }
}

void main() {
  testWidgets('renders the 4 customer tabs (active icon is filled)', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        SoleBottomNav(
          role: AppConstants.roleCustomer,
          currentIndex: 0,
          onTap: (_) {},
        ),
      ),
    );

    // Home is active → filled icon; the rest are outlined.
    expect(find.byIcon(Icons.home), findsOneWidget);
    expect(find.byIcon(Icons.storefront_outlined), findsOneWidget);
    expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);
    expect(find.byIcon(Icons.person_outline), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Notifications'), findsOneWidget);
  });

  testWidgets('pill stays centered on the active icon', (tester) async {
    await tester.pumpWidget(const _Harness());

    final iconCenter = tester.getCenter(find.byIcon(Icons.home));
    final pillCenter = tester.getCenter(_pillFinder);

    expect(
      (pillCenter.dx - iconCenter.dx).abs(),
      lessThan(1.0),
      reason: 'pill must stay horizontally centered on the active icon',
    );
    expect(
      (pillCenter.dy - iconCenter.dy).abs(),
      lessThan(1.0),
      reason: 'pill must stay vertically centered on the active icon',
    );
  });

  testWidgets('seller role renders 5 tabs and the pill centers', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        SoleBottomNav(
          role: AppConstants.roleSeller,
          currentIndex: 0,
          onTap: (_) {},
          // The seller shell uses a shorter bar — exercise the derived
          // icon-row math for that height too.
          barHeight: 65,
        ),
      ),
    );

    // Dashboard is active → filled icon; the rest are outlined.
    expect(find.byIcon(Icons.dashboard), findsOneWidget);
    expect(find.byIcon(Icons.point_of_sale_outlined), findsOneWidget);
    expect(find.byIcon(Icons.inventory_2_outlined), findsOneWidget);
    expect(find.byIcon(Icons.receipt_long_outlined), findsOneWidget);
    expect(find.byIcon(Icons.person_outline), findsOneWidget);
    expect(find.text('POS'), findsOneWidget);

    // Pill centered on the active (first of 5) tab.
    final barWidth = tester.getSize(find.byType(SoleBottomNav)).width;
    final pillCenter = tester.getCenter(_pillFinder);
    expect(pillCenter.dx, closeTo(((0 + 0.5) / 5) * barWidth, 0.01));
    expect(
      (pillCenter.dy - tester.getCenter(find.byIcon(Icons.dashboard)).dy).abs(),
      lessThan(1.0),
    );
  });

  testWidgets('pill glides to the active tab position', (tester) async {
    await tester.pumpWidget(const _Harness());

    // Center x of tab [index] — derived from the bar's ACTUAL rendered
    // width, so the test isn't tied to the default 800px test surface.
    double tabCenterX(int index) {
      final barWidth = tester.getSize(find.byType(SoleBottomNav)).width;
      return ((index + 0.5) / 4) * barWidth;
    }

    // The pill's rendered center must land on the active tab's center.
    double pillCenterX() => tester.getCenter(_pillFinder).dx;

    // Home active initially (4 tabs).
    expect(pillCenterX(), closeTo(tabCenterX(0), 0.01));

    await tester.tap(find.byIcon(Icons.storefront_outlined));
    await tester.pumpAndSettle();
    expect(pillCenterX(), closeTo(tabCenterX(1), 0.01));

    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle();
    expect(pillCenterX(), closeTo(tabCenterX(3), 0.01));
  });

  testWidgets('tapping a tab reports its index', (tester) async {
    int? tapped;
    await tester.pumpWidget(
      _wrap(
        SoleBottomNav(
          role: AppConstants.roleCustomer,
          currentIndex: 0,
          onTap: (i) => tapped = i,
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.person_outline));
    expect(tapped, 3);
  });

  testWidgets('bell badge shows the unread count and hides at 0', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        SoleBottomNav(
          role: AppConstants.roleCustomer,
          currentIndex: 0,
          onTap: (_) {},
          notificationUnreadCount: 16,
        ),
      ),
    );
    expect(find.text('16'), findsOneWidget);

    await tester.pumpWidget(
      _wrap(
        SoleBottomNav(
          role: AppConstants.roleCustomer,
          currentIndex: 0,
          onTap: (_) {},
          notificationUnreadCount: 0,
        ),
      ),
    );
    expect(find.text('0'), findsNothing);
  });

  testWidgets('bell badge caps at 99+', (tester) async {
    await tester.pumpWidget(
      _wrap(
        SoleBottomNav(
          role: AppConstants.roleCustomer,
          currentIndex: 0,
          onTap: (_) {},
          notificationUnreadCount: 142,
        ),
      ),
    );
    expect(find.text('99+'), findsOneWidget);
  });
}
