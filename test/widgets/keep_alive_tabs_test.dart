import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/widgets/active_tab.dart';
import 'package:app/widgets/keep_alive_page.dart';

/// Regression tests for the "every tab switch re-loads the screen" bug.
///
/// The bottom-nav shells host their tabs in a `PageView`. A `PageView` builds
/// ONLY the page it is showing (its viewport sets `cacheExtent` to 0 unless
/// `allowImplicitScrolling` is on), so switching away **disposed** the previous
/// page — and switching back built it from scratch, re-running `initState()`.
/// That is what re-fired each screen's data fetches and re-showed its loading
/// skeleton on every single tap.
///
/// These tests pin both halves of the fix:
///   1. `KeepAlivePage` keeps a visited page mounted (no second `initState`).
///   2. `ActiveTab` gives a kept-alive page a re-entry signal, because a page
///      that is never rebuilt has no other way to notice it is visible again.

/// Records how many times it is constructed and keeps a local tick counter, so
/// a test can tell "the State survived" from "it was rebuilt from scratch".
class _Spy extends StatefulWidget {
  const _Spy({super.key, required this.label, required this.initCalls});

  final String label;
  final Map<String, int> initCalls;

  @override
  State<_Spy> createState() => _SpyState();
}

class _SpyState extends State<_Spy> {
  int _ticks = 0;

  @override
  void initState() {
    super.initState();
    widget.initCalls[widget.label] = (widget.initCalls[widget.label] ?? 0) + 1;
  }

  @override
  Widget build(BuildContext context) => Text(
        '${widget.label}=$_ticks',
        textDirection: TextDirection.ltr,
      );

  void bump() => setState(() => _ticks++);
}

/// Records every `ActiveTab` value it sees, from `didChangeDependencies`.
class _TabProbe extends StatefulWidget {
  const _TabProbe({required this.label, required this.seen});

  final String label;
  final List<String> seen;

  @override
  State<_TabProbe> createState() => _TabProbeState();
}

class _TabProbeState extends State<_TabProbe> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    widget.seen.add('${widget.label}:${ActiveTab.of(context)}');
  }

  @override
  Widget build(BuildContext context) =>
      Text(widget.label, textDirection: TextDirection.ltr);
}

Widget _pager(PageController controller, List<Widget> children) => MaterialApp(
      home: PageView(controller: controller, children: children),
    );

void main() {
  group('PageView tab host', () {
    testWidgets('the bug: without keep-alive, switching back re-runs initState',
        (tester) async {
      final initCalls = <String, int>{};
      final controller = PageController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(_pager(controller, [
        _Spy(label: 'A', initCalls: initCalls),
        _Spy(label: 'B', initCalls: initCalls),
      ]));
      await tester.pumpAndSettle();
      expect(initCalls['A'], 1);

      controller.jumpToPage(1);
      await tester.pumpAndSettle();
      controller.jumpToPage(0);
      await tester.pumpAndSettle();

      // Documented, not desired: this is the behaviour the fix removes. If this
      // ever starts reading 1, the framework has changed its cacheExtent
      // behaviour and the KeepAlivePage wrapper is no longer load-bearing.
      expect(
        initCalls['A'],
        2,
        reason: 'a bare PageView child is disposed when scrolled away',
      );
    });

    testWidgets('KeepAlivePage keeps a visited page mounted across switches',
        (tester) async {
      final initCalls = <String, int>{};
      final controller = PageController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(_pager(controller, [
        KeepAlivePage(child: _Spy(label: 'A', initCalls: initCalls)),
        KeepAlivePage(child: _Spy(label: 'B', initCalls: initCalls)),
        KeepAlivePage(child: _Spy(label: 'C', initCalls: initCalls)),
      ]));
      await tester.pumpAndSettle();
      expect(initCalls, {'A': 1});

      // Visit every tab, then come back to the first.
      controller.jumpToPage(1);
      await tester.pumpAndSettle();
      controller.jumpToPage(2);
      await tester.pumpAndSettle();
      controller.jumpToPage(0);
      await tester.pumpAndSettle();

      expect(
        initCalls,
        {'A': 1, 'B': 1, 'C': 1},
        reason: 'each page is initialised exactly once per session',
      );
    });

    testWidgets('keep-alive pages stay lazy — unvisited tabs are never built',
        (tester) async {
      final initCalls = <String, int>{};
      final controller = PageController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(_pager(controller, [
        KeepAlivePage(child: _Spy(label: 'A', initCalls: initCalls)),
        KeepAlivePage(child: _Spy(label: 'B', initCalls: initCalls)),
        KeepAlivePage(child: _Spy(label: 'C', initCalls: initCalls)),
      ]));
      await tester.pumpAndSettle();

      // This is why the shells keep the PageView instead of swapping in an
      // IndexedStack: tabs nobody opened must not fetch anything.
      expect(initCalls.containsKey('B'), isFalse);
      expect(initCalls.containsKey('C'), isFalse);
    });

    testWidgets('a kept-alive page keeps its own State, not just its widget',
        (tester) async {
      final initCalls = <String, int>{};
      final controller = PageController();
      addTearDown(controller.dispose);
      final key = GlobalKey<_SpyState>();

      await tester.pumpWidget(_pager(controller, [
        KeepAlivePage(child: _Spy(key: key, label: 'A', initCalls: initCalls)),
        KeepAlivePage(child: _Spy(label: 'B', initCalls: initCalls)),
      ]));
      await tester.pumpAndSettle();

      // Mutate page A's local state, leave, and come back.
      key.currentState!.bump();
      await tester.pumpAndSettle();
      expect(find.text('A=1'), findsOneWidget);

      controller.jumpToPage(1);
      await tester.pumpAndSettle();
      controller.jumpToPage(0);
      await tester.pumpAndSettle();

      // Scroll offset, in-progress edits and loaded data all live in the State;
      // surviving the round trip is the whole point.
      expect(find.text('A=1'), findsOneWidget);
    });
  });

  group('ActiveTab re-entry signal', () {
    testWidgets('every switch notifies kept-alive pages of the new index',
        (tester) async {
      final seen = <String>[];
      final controller = PageController();
      addTearDown(controller.dispose);
      var index = 0;

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) => MaterialApp(
            home: ActiveTab(
              index: index,
              child: PageView(
                controller: controller,
                onPageChanged: (i) => setState(() => index = i),
                children: [
                  KeepAlivePage(child: _TabProbe(label: 'A', seen: seen)),
                  KeepAlivePage(child: _TabProbe(label: 'B', seen: seen)),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(seen, ['A:0']);

      controller.jumpToPage(1);
      await tester.pumpAndSettle();

      // The off-screen but kept-alive page A is notified too — that is what
      // lets a screen tell "I was switched away from" from "I was switched to".
      expect(seen, ['A:0', 'A:1', 'B:1']);

      controller.jumpToPage(0);
      await tester.pumpAndSettle();

      expect(seen, ['A:0', 'A:1', 'B:1', 'A:0', 'B:0']);
    });

    testWidgets('of() returns null outside a tab host', (tester) async {
      int? reported = -1;

      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) {
            reported = ActiveTab.of(context);
            return const SizedBox.shrink();
          },
        ),
      ));

      expect(reported, isNull);
    });
  });
}
