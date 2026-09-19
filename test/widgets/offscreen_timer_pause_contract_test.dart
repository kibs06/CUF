import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Contract test for the two session-long timers that must stop when their tab
/// is off screen.
///
/// Now that the seller shell keeps a visited page mounted (see
/// `KeepAlivePage`), two timers that used to die with their page now live for
/// the whole session:
///   * `ManageProductsScreen`'s 4-second "next alert" rotation, and
///   * the dashboard's 30-second GCash payments-to-confirm sweep.
///
/// Both are gated on [ActiveTab], which publishes the on-screen tab index. The
/// failure modes this file guards are all silent:
///
///   1. **Index drift.** The gate compares against a hardcoded tab index. Nothing
///      in the language ties `_productsTabIndex = 2` to Products actually being
///      third in the shell's `_screens` list. Reorder the bottom nav and the
///      Products ticker would keep running off screen while *another* tab's
///      rotation sat frozen — with no compile error and no visible symptom.
///   2. **A missing pause branch.** A half-wired hook that only resumes is the
///      same as no hook at all.
///   3. **A pause that does not null the field.** Both `_start*` methods bail
///      out early when their timer is non-null ("idempotent, safe to call from
///      both sites"), so a pause that only `cancel()`s but leaves the reference
///      makes every later resume a silent no-op — the timer never comes back.
void main() {
  const shellPath = 'lib/screens/seller/seller_shell.dart';
  const dashboardPath = 'lib/screens/seller/seller_dashboard_screen.dart';
  const productsPath = 'lib/screens/seller/manage_products_screen.dart';
  const profilePath = 'lib/screens/shared/profile_screen.dart';

  late String shell;
  late String dashboard;
  late String products;
  late String profile;

  setUpAll(() {
    shell = withoutLineComments(File(shellPath).readAsStringSync());
    dashboard = withoutLineComments(File(dashboardPath).readAsStringSync());
    products = withoutLineComments(File(productsPath).readAsStringSync());
    profile = withoutLineComments(File(profilePath).readAsStringSync());
  });

  group('tab index contract', () {
    /// The shell's tab order, read from its `_screens` list.
    List<String> shellTabs() => RegExp(r'const (\w+)\(')
        .allMatches(
          shell.substring(
            shell.indexOf('final List<Widget> _screens'),
            shell.indexOf('_tabLabels'),
          ),
        )
        .map((m) => m.group(1)!)
        .toList();

    test('the shell hosts the five expected tabs in bottom-nav order', () {
      expect(shellTabs(), [
        'SellerDashboardScreen',
        'POSScreen',
        'ManageProductsScreen',
        'ManageOrdersScreen',
        'ProfileScreen',
      ]);
    });

    test('every hardcoded tab index matches the real position', () {
      final tabs = shellTabs();

      // Each screen that gates on ActiveTab declares its own index. These must
      // agree with `_screens`, or a timer pauses on the wrong tab.
      final declared = <String, int>{
        'SellerDashboardScreen': _declaredTabIndex(dashboard),
        'ManageProductsScreen': _declaredTabIndex(products),
      };

      for (final entry in declared.entries) {
        expect(
          entry.value,
          tabs.indexOf(entry.key),
          reason: '${entry.key} declares tab index ${entry.value}, but it is '
              'at position ${tabs.indexOf(entry.key)} in the shell.',
        );
      }
    });

    test('ProfileScreen is handed the index matching its position', () {
      final tabs = shellTabs();
      final match = RegExp(r'const ProfileScreen\((.*?)\)').firstMatch(shell);
      expect(match, isNotNull, reason: 'ProfileScreen not found in _screens');

      final tabIndex =
          int.parse(RegExp(r'tabIndex:\s*(\d+)').firstMatch(match!.group(1)!)!.group(1)!);
      expect(tabIndex, tabs.indexOf('ProfileScreen'));
      expect(profile, contains('tabIndex'));
    });
  });

  group('Products alert rotation', () {
    test('is gated on the Products tab being the active one', () {
      final hook = methodBody(products, 'void didChangeDependencies()');

      expect(hook, contains('ActiveTab.of(context)'));
      expect(hook, contains('_pauseAlertTimer()'));
      expect(hook, contains('_startAlertTimer()'));
      // The resume branch must be conditional on THIS tab being on screen.
      expect(hook, contains('_productsTabIndex'));
    });

    test('pausing cancels AND clears, so the resume guard can re-arm', () {
      expect(products, contains('if (_alertTimer != null) return;'),
          reason: 'the start method is documented as idempotent; the pause must '
              'therefore clear the field, not merely cancel it');

      final pause = methodBody(products, 'void _pauseAlertTimer()');
      expect(pause, contains('_alertTimer?.cancel()'));
      expect(pause, contains('_alertTimer = null'));
    });

    test('the timer is also cancelled on dispose', () {
      expect(methodBody(products, 'void dispose()'),
          contains('_alertTimer?.cancel()'));
    });
  });

  group('Dashboard GCash poll', () {
    test('is gated on the Dashboard tab being the active one', () {
      final hook = gcashCardHook(dashboard);

      expect(hook, contains('ActiveTab.of(context)'));
      expect(hook, contains('_pausePoll()'));
      expect(hook, contains('_startPoll()'));
      expect(hook, contains('_dashboardTabIndex'));
    });

    test('resuming sweeps once immediately rather than waiting a full cycle',
        () {
      final hook = gcashCardHook(dashboard);

      // The count is up to 30s stale while the tab is away, so the way back in
      // must refresh — but only if the poll was actually paused first, or the
      // card would duplicate the query `initState` just fired.
      expect(hook, contains('_paused'));
      expect(hook.indexOf('_refresh()'), lessThan(hook.indexOf('_startPoll()')));
    });

    test('pausing cancels AND clears, so the resume guard can re-arm', () {
      expect(dashboard, contains('if (_timer != null) return;'));

      final pause = methodBody(dashboard, 'void _pausePoll()');
      expect(pause, contains('_timer?.cancel()'));
      expect(pause, contains('_timer = null'));
    });
  });

  group('no other uncontrolled periodic timer', () {
    test('every Timer.periodic in the tab screens has a cancel path', () {
      for (final entry in {
        productsPath: products,
        dashboardPath: dashboard,
      }.entries) {
        final periods = 'Timer.periodic'.allMatches(entry.value).length;
        if (periods == 0) continue;

        final cancels = '.cancel()'.allMatches(entry.value).length;
        expect(
          cancels,
          greaterThanOrEqualTo(periods),
          reason: '${entry.key} starts $periods periodic timer(s) but only has '
              '$cancels cancel() call(s) — a timer with no pause/dispose path '
              'now runs for the whole session.',
        );
      }
    });
  });
}

/// The value a screen declares for its own tab index, e.g.
/// `static const int _productsTabIndex = 2;`
int _declaredTabIndex(String source) {
  final match =
      RegExp(r'static const int _\w*[Tt]abIndex = (\d+);').firstMatch(source);
  expect(
    match,
    isNotNull,
    reason: 'a screen gating on ActiveTab must declare its own tab index, so '
        'this test can check it against the shell',
  );
  return int.parse(match!.group(1)!);
}

/// The body of the [`_PaymentsToConfirmCardState`] visibility hook.
///
/// The dashboard has two `didChangeDependencies` — the screen's own re-entry
/// check and this card's poll gate — so the card's is located by class rather
/// than by being "the second one".
String gcashCardHook(String dashboard) => methodBody(
      dashboard,
      'void didChangeDependencies()',
      after: 'class _PaymentsToConfirmCardState',
    );

/// The body of the declaration starting at [signature], with braces balanced.
///
/// [signature] must stop before the body's opening brace, e.g.
/// `'void dispose()'` — the brace is located from the signature's end.
///
/// Search starts at [after] when given, so sibling classes that each declare the
/// same lifecycle method can be told apart.
String methodBody(String source, String signature, {String? after}) {
  final start = source.indexOf(signature, after == null ? 0 : source.indexOf(after));
  expect(start, isNonNegative, reason: 'not found: $signature');

  final open = source.indexOf('{', start + signature.length);
  expect(open, isNonNegative, reason: 'no body after: $signature');

  var depth = 0;
  for (var i = open; i < source.length; i++) {
    if (source[i] == '{') depth++;
    if (source[i] == '}') {
      depth--;
      if (depth == 0) return source.substring(open + 1, i);
    }
  }
  fail('unbalanced braces after: $signature');
}

/// Drops `//` comments so the guards above cannot be satisfied by prose.
String withoutLineComments(String source) => source
    .split('\n')
    .map((line) {
      final i = line.indexOf('//');
      return i == -1 ? line : line.substring(0, i);
    })
    .join('\n');
