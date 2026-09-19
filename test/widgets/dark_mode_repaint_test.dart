import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/constants/app_brightness.dart';
import 'package:app/constants/app_constants.dart';
import 'package:app/constants/app_palette.dart';
import 'package:app/constants/app_theme.dart';
import 'package:app/providers/theme_provider.dart';

/// The riskiest part of the token architecture: an app that paints from static
/// tokens registers no dependency a theme change can notify, and Flutter's
/// route scope caches its page (`_ModalScopeState` only clears that cache when
/// the route's *own* dependencies change). So switching appearance has to
/// invalidate the tree explicitly, or every already-built screen keeps its old
/// palette until the user navigates.
///
/// This reproduces the app root's arrangement — publish brightness, then
/// `AppThemeRefresh.rebuildAll()` in a post-frame callback — and asserts that a
/// route pushed *before* the switch repaints with dark tokens, without being
/// rebuilt from scratch (its state survives).
class _Probe extends StatefulWidget {
  const _Probe({super.key, required this.log});

  final List<Color> log;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  int buildCount = 0;

  @override
  Widget build(BuildContext context) {
    buildCount++;
    widget.log.add(AppConstants.surfaceLight);
    return ColoredBox(
      color: AppConstants.surfaceLight,
      child: const SizedBox(width: 40, height: 40),
    );
  }
}

/// Mirrors `_ThemedApp`/`_CUFMAIAppState` in lib/main.dart.
class _Harness extends StatefulWidget {
  const _Harness({required this.provider, required this.log});

  final ThemeProvider provider;
  final List<Color> log;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  @override
  void initState() {
    super.initState();
    widget.provider.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    widget.provider.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    // Same order as _ThemedApp: publish while building, so this frame's
    // children already read the new palette.
    final isDark = widget.provider.mode == ThemeMode.dark;
    final brightness = isDark ? Brightness.dark : Brightness.light;
    if (AppBrightness.publish(brightness)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        AppThemeRefresh.rebuildAll();
      });
    }

    return MaterialApp(
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      themeMode: widget.provider.mode,
      home: Builder(
        builder: (context) => Column(
          children: [
            _Probe(key: const ValueKey('home'), log: widget.log),
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      _Probe(key: const ValueKey('pushed'), log: widget.log),
                ),
              ),
              child: const Text('push'),
            ),
          ],
        ),
      ),
    );
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('an already-pushed route repaints when the mode flips',
      (tester) async {
    final provider = ThemeProvider();
    final log = <Color>[];

    await tester.pumpWidget(_Harness(provider: provider, log: log));
    await tester.tap(find.text('push'));
    await tester.pumpAndSettle();

    expect(log, isNotEmpty);
    expect(log.last, AppPalette.light.page);

    final pushedState = tester.state<_ProbeState>(
      find.byKey(const ValueKey('pushed')),
    );
    final buildsBefore = pushedState.buildCount;

    await provider.setMode(ThemeMode.dark);
    // One pump runs the post-frame callback, the next paints the rebuild.
    await tester.pump();
    await tester.pump();

    expect(log.last, AppPalette.dark.page,
        reason: 'the pushed route must pick up the dark palette without a '
            'navigation event');
    expect(
      tester.state<_ProbeState>(find.byKey(const ValueKey('pushed'))),
      same(pushedState),
      reason: 'the repaint must not recreate element state',
    );
    expect(pushedState.buildCount, greaterThan(buildsBefore));
  });

  testWidgets('the first frame does not schedule a pointless repaint',
      (tester) async {
    // Publishing on the very first build reports "unchanged" by design, so a
    // dark-mode user does not get a light frame at launch.
    AppBrightness.reset();
    final provider = ThemeProvider(initialMode: ThemeMode.dark);
    final log = <Color>[];

    await tester.pumpWidget(_Harness(provider: provider, log: log));
    await tester.pump();

    expect(log.last, AppPalette.dark.page);
  });

  testWidgets('the Material layer follows the mode too', (tester) async {
    final dark = buildAppTheme(Brightness.dark);
    final light = buildAppTheme(Brightness.light);

    expect(light.brightness, Brightness.light);
    expect(dark.brightness, Brightness.dark);
    expect(light.colorScheme.surface, AppPalette.light.page);
    expect(dark.colorScheme.surface, AppPalette.dark.page);
    expect(dark.colorScheme.onSurface, AppPalette.dark.onPage);
    expect(dark.dialogTheme.backgroundColor, AppPalette.dark.page);
    // The brand fill is pinned, so the ink on it is too.
    expect(dark.colorScheme.primary, AppConstants.primary);
    expect(dark.colorScheme.onPrimary, AppPalette.dark.inkInverse);
  });
}
