import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'label_fade_nav_bar.dart';

/// Stateful harness that drives [LabelFadeNavBar] with real setState, so
/// tests exercise the same tap → label-switch flow as the example app.
class _Harness extends StatefulWidget {
  final List<NavBarItem> items;
  const _Harness({required this.items});

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: const SizedBox(),
        bottomNavigationBar: LabelFadeNavBar(
          items: widget.items,
          selectedIndex: _selected,
          onTap: (i) => setState(() => _selected = i),
        ),
      ),
    );
  }
}

const _defaultItems = <NavBarItem>[
  NavBarItem(icon: Icons.home_outlined, label: 'Home'),
  NavBarItem(icon: Icons.storefront_outlined, label: 'Store'),
  NavBarItem(
    icon: Icons.notifications_outlined,
    label: 'Notifications',
    badgeCount: 16,
  ),
  NavBarItem(icon: Icons.person_outline, label: 'Profile'),
];

void main() {
  testWidgets('only the selected tab shows its label', (tester) async {
    await tester.pumpWidget(const _Harness(items: _defaultItems));

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Store'), findsNothing);
    expect(find.text('Notifications'), findsNothing);
    expect(find.text('Profile'), findsNothing);
  });

  testWidgets('tapping a tab reveals its label and hides the old one',
      (tester) async {
    await tester.pumpWidget(const _Harness(items: _defaultItems));

    await tester.tap(find.byIcon(Icons.storefront_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Store'), findsOneWidget);
    expect(find.text('Home'), findsNothing);
  });

  testWidgets('every tab is reachable by tapping its icon', (tester) async {
    await tester.pumpWidget(const _Harness(items: _defaultItems));

    for (final (icon, label) in [
      (Icons.storefront_outlined, 'Store'),
      (Icons.notifications_outlined, 'Notifications'),
      (Icons.person_outline, 'Profile'),
      (Icons.home_outlined, 'Home'),
    ]) {
      await tester.tap(find.byIcon(icon));
      await tester.pumpAndSettle();
      expect(find.text(label), findsOneWidget, reason: '$label should show');
    }
  });

  testWidgets('badge renders independently of selection', (tester) async {
    await tester.pumpWidget(const _Harness(items: _defaultItems));

    // Badge visible while Notifications is unselected…
    expect(find.text('16'), findsOneWidget);

    // …and still visible when Notifications is selected.
    await tester.tap(find.byIcon(Icons.notifications_outlined));
    await tester.pumpAndSettle();
    expect(find.text('16'), findsOneWidget);
    expect(find.text('Notifications'), findsOneWidget);
  });

  testWidgets('no badge when badgeCount is null or zero', (tester) async {
    await tester.pumpWidget(const _Harness(items: [
      NavBarItem(icon: Icons.home_outlined, label: 'Home'),
      NavBarItem(
        icon: Icons.notifications_outlined,
        label: 'Notifications',
        badgeCount: 0,
      ),
    ]));

    expect(find.text('0'), findsNothing);
    expect(find.byType(Text), findsOneWidget); // only the 'Home' label
  });
}
