import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The seller and customer shells are supposed to behave the same way as the
/// customer's does: scroll a tab down and the bottom nav leaves the screen,
/// drag back up and it returns.
///
/// That behaviour lives entirely in one wrapper — `HideOnScrollBottomBar` — which
/// only works if the shell hands it **both** halves: the bar as `bar:`, and the
/// tab host as `child:`. The failure modes are invisible to the compiler and to
/// a widget test of the bar itself:
///
///   1. **The bar left in the Scaffold slot.** `bottomNavigationBar:` still
///      renders a perfectly good bar — it just never moves, because the wrapper
///      it was supposed to be inside is now empty. Nothing errors; the effect is
///      simply absent on one shell.
///   2. **The page outside the wrapper.** With only the bar wrapped, the page's
///      scroll notifications bubble through a `NotificationListener` that is not
///      an ancestor of the scrolling widget, so the bar never hears a scroll —
///      same silent no-op.
///   3. **No `resetOn`.** Without the active tab, switching tabs leaves the next
///      tab ('s page) starting with the bar hidden by the *previous* tab's
///      scroll, which reads as a bar that vanished.
///
/// Read from source rather than rendered: both shells would need a full
/// Supabase-backed provider tree to build, and what is being guarded is a wiring
/// fact, not a layout one.
void main() {
  const shells = <String, String>{
    'seller': 'lib/screens/seller/seller_shell.dart',
    'customer': 'lib/screens/customer/customer_shell.dart',
  };

  late Map<String, String> source;

  setUpAll(() {
    source = {
      for (final entry in shells.entries)
        entry.key: File(entry.value).readAsStringSync(),
    };
  });

  group('both shells hide the bar on scroll', () {
    for (final entry in shells.entries) {
      final name = entry.key;

      test('$name: the wrapper owns the bar and the page', () {
        final args = callOf(source[name]!, 'HideOnScrollBottomBar(');

        expect(
          args,
          contains('bar:'),
          reason: '$name wraps its body but leaves the bar outside it',
        );
        expect(
          args,
          contains('child:'),
          reason: '$name did not hand the page to the wrapper, so its scroll '
              'notifications never reach the bar',
        );
        expect(
          args,
          contains('SoleBottomNav('),
          reason: '$name\'s nav bar is not the widget being collapsed',
        );
        expect(
          args,
          contains('resetOn: _currentIndex'),
          reason: '$name must reset the bar on a tab switch, or the next tab '
              'opens with a bar hidden by the previous one\'s scroll',
        );
      });

      test('$name: the bar is no longer a Scaffold slot', () {
        // The two are mutually exclusive: a bar in `bottomNavigationBar:` sits
        // outside the body, where the wrapper cannot move it.
        expect(
          source[name]!,
          isNot(contains('bottomNavigationBar:')),
          reason: '$name still hands its bar to the Scaffold, which renders it '
              'outside HideOnScrollBottomBar — the scroll effect is dead',
        );
        expect(
          source[name]!,
          contains('body: HideOnScrollBottomBar('),
          reason: '$name must wrap the body, not just add the widget somewhere',
        );
      });
    }

    test('the seller bar keeps its own top border inside the wrapper', () {
      // The hairline above the nav is what separates it from the page. Left
      // outside the wrapper it would stay behind as a floating line when the
      // bar collapses.
      final args = callOf(
        source['seller']!,
        'body: HideOnScrollBottomBar(',
      );
      expect(args, contains('cardBorder'));
    });
  });
}

/// The argument text of the first [signature] call in [source], with its
/// parentheses balanced so a `contains` check cannot be satisfied by something
/// that merely appears later in the file.
String callOf(String source, String signature) {
  final start = source.indexOf(signature);
  expect(start, isNonNegative, reason: 'not found: $signature');

  final open = start + signature.length - 1;
  var depth = 0;
  for (var i = open; i < source.length; i++) {
    if (source[i] == '(') depth++;
    if (source[i] == ')') {
      depth--;
      if (depth == 0) return source.substring(open + 1, i);
    }
  }
  fail('unbalanced parentheses after: $signature');
}
