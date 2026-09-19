import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/widgets/lazy_indexed_stack.dart';

/// Tests for [LazyIndexedStack] — the admin shell's tab host.
///
/// It has to satisfy two properties at once, and they pull in opposite
/// directions:
///   * **state preservation** — every visited tab stays mounted, so switching
///     back does not re-run `initState` (the reason a shell uses an
///     `IndexedStack` at all);
///   * **laziness** — an unvisited tab is never constructed, so it never runs
///     its data fetches. A plain `IndexedStack` builds all six admin screens on
///     the first frame.
///
/// These tests pin both, plus the guarantee that a tab is built exactly once
/// for the session and reused on every later visit.

/// Records how many times it is constructed and holds mutable local state.
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

/// A host that owns the selected index, like a real shell.
class _Host extends StatefulWidget {
  const _Host({required this.labels, required this.initCalls});

  final List<String> labels;
  final Map<String, int> initCalls;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  int index = 0;
  final List<GlobalKey<_SpyState>> keys = [];

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < widget.labels.length; i++) {
      keys.add(GlobalKey<_SpyState>());
    }
  }

  void select(int i) => setState(() => index = i);

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: LazyIndexedStack(
          index: index,
          children: [
            for (var i = 0; i < widget.labels.length; i++)
              _Spy(
                key: keys[i],
                label: widget.labels[i],
                initCalls: widget.initCalls,
              ),
          ],
        ),
      );
}

void main() {
  group('LazyIndexedStack', () {
    testWidgets('builds only the visible tab on the first frame',
        (tester) async {
      final initCalls = <String, int>{};
      await tester.pumpWidget(_Host(
        labels: const ['A', 'B', 'C', 'D', 'E', 'F'],
        initCalls: initCalls,
      ));
      await tester.pumpAndSettle();

      // The whole point: six admin tabs, one screen constructed. A plain
      // IndexedStack would show all six here.
      expect(initCalls, {'A': 1});
    });

    testWidgets('opening a tab builds just that tab, not the ones skipped over',
        (tester) async {
      final initCalls = <String, int>{};
      await tester.pumpWidget(_Host(
        labels: const ['A', 'B', 'C', 'D', 'E', 'F'],
        initCalls: initCalls,
      ));
      await tester.pumpAndSettle();

      final state = tester.state<_HostState>(find.byType(_Host));

      // Jump straight from tab 0 to tab 4 — tabs 1-3 are never visited.
      state.select(4);
      await tester.pumpAndSettle();

      expect(initCalls, {'A': 1, 'E': 1});
      expect(initCalls.containsKey('B'), isFalse);
    });

    testWidgets('the newly selected tab appears in the frame it is selected',
        (tester) async {
      final initCalls = <String, int>{};
      await tester.pumpWidget(_Host(
        labels: const ['A', 'B', 'C'],
        initCalls: initCalls,
      ));
      await tester.pumpAndSettle();

      final state = tester.state<_HostState>(find.byType(_Host));
      state.select(1);
      // A single pump: the real child must alreadly have replaced its
      // placeholder, with no blank intermediate frame.
      await tester.pump();

      expect(find.text('B=0'), findsOneWidget);
      expect(initCalls['B'], 1);
    });

    testWidgets('a visited tab is never rebuilt from scratch', (tester) async {
      final initCalls = <String, int>{};
      await tester.pumpWidget(_Host(
        labels: const ['A', 'B', 'C'],
        initCalls: initCalls,
      ));
      await tester.pumpAndSettle();
      final state = tester.state<_HostState>(find.byType(_Host));

      // Leave tab 0 and come back twice.
      state.select(1);
      await tester.pumpAndSettle();
      state.select(0);
      await tester.pumpAndSettle();
      state.select(2);
      await tester.pumpAndSettle();
      state.select(0);
      await tester.pumpAndSettle();

      expect(initCalls, {'A': 1, 'B': 1, 'C': 1});
    });

    testWidgets('a revisited tab keeps its existing State', (tester) async {
      final initCalls = <String, int>{};
      await tester.pumpWidget(_Host(
        labels: const ['A', 'B'],
        initCalls: initCalls,
      ));
      await tester.pumpAndSettle();
      final state = tester.state<_HostState>(find.byType(_Host));

      state.keys[0].currentState!.bump();
      await tester.pumpAndSettle();
      expect(find.text('A=1'), findsOneWidget);

      state.select(1);
      await tester.pumpAndSettle();
      state.select(0);
      await tester.pumpAndSettle();

      // Loaded data, scroll offsets and filters live in the State — surviving
      // the round trip is why the shell uses an IndexedStack at all.
      expect(find.text('A=1'), findsOneWidget);
      expect(initCalls['A'], 1);
    });

    testWidgets('an out-of-range index fails loudly instead of rendering blank',
        (tester) async {
      final initCalls = <String, int>{};
      await tester.pumpWidget(_Host(
        labels: const ['A', 'B'],
        initCalls: initCalls,
      ));
      await tester.pumpAndSettle();

      final state = tester.state<_HostState>(find.byType(_Host));
      // This widget deliberately inherits `IndexedStack`'s contract rather than
      // clamping: a tab index past the end of the child list is a bug in the
      // shell's nav state, and silently showing an empty frame would hide it.
      state.select(5);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isAssertionError);
    });
  });
}
