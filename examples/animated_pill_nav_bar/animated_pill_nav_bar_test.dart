import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'animated_pill_nav_bar.dart';

/// Stateful harness driving [AnimatedPillNavBar] with real setState, like
/// the example app.
class _Harness extends StatefulWidget {
  final List<NavItem> items;
  const _Harness({required this.items});

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
        bottomNavigationBar: AnimatedPillNavBar(
          items: widget.items,
          currentIndex: _current,
          onTap: (i) => setState(() => _current = i),
        ),
      ),
    );
  }
}

const _defaultItems = <NavItem>[
  NavItem(icon: Icons.home_outlined, label: 'Home'),
  NavItem(icon: Icons.storefront_outlined, label: 'Store'),
  NavItem(
    icon: Icons.notifications_outlined,
    label: 'Notifications',
    badgeCount: 16,
  ),
  NavItem(icon: Icons.person_outline, label: 'Profile'),
];

/// Alignment.x of the pill when a given tab is active (derived from the
/// widget's own formula: ((index + 0.5) / count) * 2 - 1).
double _pillAlignX(int index, int count) =>
    ((index + 0.5) / count) * 2 - 1;

void main() {
  testWidgets('renders all 4 icons and no visible labels', (tester) async {
    await tester.pumpWidget(const _Harness(items: _defaultItems));

    expect(find.byIcon(Icons.home_outlined), findsOneWidget);
    expect(find.byIcon(Icons.storefront_outlined), findsOneWidget);
    expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);
    expect(find.byIcon(Icons.person_outline), findsOneWidget);
    // Labels are accessibility-only — nothing visible.
    expect(find.text('Home'), findsNothing);
    expect(find.text('Notifications'), findsNothing);
  });

  testWidgets('pill slides to the active tab position', (tester) async {
    await tester.pumpWidget(const _Harness(items: _defaultItems));

    Alignment alignment() => tester
            .widget<AnimatedAlign>(find.byType(AnimatedAlign))
            .alignment as Alignment;

    // Home active initially.
    expect(alignment(), Alignment(_pillAlignX(0, 4), 0));

    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle();
    expect(alignment(), Alignment(_pillAlignX(3, 4), 0));

    await tester.tap(find.byIcon(Icons.notifications_outlined));
    await tester.pumpAndSettle();
    expect(alignment(), Alignment(_pillAlignX(2, 4), 0));
  });

  testWidgets('tapping a tab reports its index', (tester) async {
    int? tapped;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: const SizedBox(),
        bottomNavigationBar: AnimatedPillNavBar(
          items: const [
            NavItem(icon: Icons.home_outlined, label: 'Home'),
            NavItem(icon: Icons.person_outline, label: 'Profile'),
          ],
          currentIndex: 0,
          onTap: (i) => tapped = i,
        ),
      ),
    ));

    await tester.tap(find.byIcon(Icons.person_outline));
    expect(tapped, 1);
  });

  testWidgets('active icon scales up, inactive ones stay at 1.0',
      (tester) async {
    await tester.pumpWidget(const _Harness(items: _defaultItems));

    List<double> scales() => tester
        .widgetList<AnimatedScale>(find.byType(AnimatedScale))
        .map((w) => w.scale)
        .toList();

    // Home (index 0) active.
    expect(scales(), [1.1, 1.0, 1.0, 1.0]);

    await tester.tap(find.byIcon(Icons.storefront_outlined));
    await tester.pumpAndSettle();
    expect(scales(), [1.0, 1.1, 1.0, 1.0]);
  });

  testWidgets('badge renders and hides with badgeCount', (tester) async {
    await tester.pumpWidget(const _Harness(items: _defaultItems));
    expect(find.text('16'), findsOneWidget);

    await tester.pumpWidget(const _Harness(items: [
      NavItem(icon: Icons.home_outlined, label: 'Home'),
      NavItem(
        icon: Icons.notifications_outlined,
        label: 'Notifications',
        badgeCount: 0,
      ),
    ]));
    expect(find.text('0'), findsNothing);
  });
}
