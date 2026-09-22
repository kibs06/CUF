import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the single warm-cream surface language the whole app now shares.
///
/// Every page, sheet, card, chip and nav band draws from the same cream tokens
/// (`AppConstants.surfaceLight` for pages/cards, `AppConstants.sellerCardBg`
/// for the lighter raised tone, `AppConstants.creamDeep` for grounded bands).
/// A hardcoded near-white fill therefore reads as a cold bright patch on a
/// cream page — the exact regression that prompted the app-wide sweep, and one
/// that silently returns whenever a new card is written by hand.
///
/// Only *fills* are inspected: a `color:` argument of a `Container`,
/// `BoxDecoration`, `SoleCard`, `Card`, `Material` or `ColoredBox`. Foreground
/// whites (icons, text, borders drawn on dark or photographic backgrounds) are
/// deliberately left alone, because white is correct there.
void main() {
  test('no hardcoded white or cold off-white surface fills in lib/', () {
    final offenders = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;

      final source = entity.readAsStringSync();
      for (final match in _fillPattern.allMatches(source)) {
        final escaped = entity.path.replaceAll(r'\', '/');
        final call = _enclosingCall(source, match.start);
        if (!_surfaceCalls.contains(call)) continue;

        final line = _lineOf(source, match.start).trim();
        if (_allowedFills.any(line.contains)) continue;

        final lineNumber = '\n'.allMatches(source.substring(0, match.start)).length + 1;
        offenders.add('$escaped:$lineNumber  $line');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Found ${offenders.length} hardcoded surface colour(s) that clash with the cream '
          'theme. Use AppConstants.surfaceLight for pages/cards, AppConstants.sellerCardBg '
          'for the lighter raised tone, or AppConstants.creamDeep for grounded bands. '
          'If a pure white fill is genuinely intended (e.g. a shimmer base canvas), add '
          'its line to _allowedFills in this test with a comment explaining why.\n\n'
          '${offenders.join('\n')}',
    );
  });

  test('no page-token ink in lib/', () {
    final offenders = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;

      final source = entity.readAsStringSync();
      for (final match in _pageInkPattern.allMatches(source)) {
        final escaped = entity.path.replaceAll(r'\', '/');
        final call = _enclosingCall(source, match.start);
        if (!_inkCalls.contains(call)) continue;
        if (_optsOut(source, match.start)) continue;

        final line = _lineOf(source, match.start).trim();
        final lineNumber = '\n'.allMatches(source.substring(0, match.start)).length + 1;
        offenders.add('$escaped:$lineNumber  $line');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Found ${offenders.length} text/icon colour(s) drawn in AppConstants.surfaceLight, which is the '
          'page tone: white on light, near-black on dark. Use AppConstants.inkInverse for ink on a screen '
          'that is dark in both modes (it is the same white on light), AppConstants.secondary for ink on a '
          'page, or mark a deliberate flip with a `theme-guard:` comment.\n\n'
          '${offenders.join('\n')}',
    );
  });

  test('no opaque ink-token fills in lib/', () {
    // `AppConstants.secondary` is the *ink* role — #111111 on light, #F5F5F5 on
    // dark. Used as a fill it only works while the ink drawn on it flips too,
    // and the app pins white on its chrome, so on dark the fill turns
    // near-white and the label disappears with it. That is the "text is not
    // visible in dark mode" bug this guard exists to stop coming back.
    final offenders = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;

      final source = entity.readAsStringSync();
      for (final match in _inkFillPattern.allMatches(source)) {
        final escaped = entity.path.replaceAll(r'\', '/');
        final call = _enclosingCall(source, match.start);
        if (!_fillCalls.contains(call)) continue;

        final line = _lineOf(source, match.start).trim();
        // A site that flips its fill together with its own ink — instead of
        // carrying the pinned white — opts out in place, so the exception is
        // documented where the colour is written.
        if (_optsOut(source, match.start)) continue;

        final lineNumber = '\n'.allMatches(source.substring(0, match.start)).length + 1;
        offenders.add('$escaped:$lineNumber  $line');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Found ${offenders.length} opaque AppConstants.secondary fill(s). That token is the page '
          'ink: on dark it resolves to near-white, so whatever is drawn on it vanishes. Use '
          'AppConstants.chrome for dark chrome that carries white ink (app bars, swipe actions, dark '
          'buttons), AppConstants.surfaceRaised / surfaceSubtle for a card, or AppConstants.surfaceLight '
          'for a page. If a site genuinely wants its fill to flip with its own label (a SnackBar takes '
          'its text colour from the Material layer, which is why SnackBar is not a fill call here), mark '
          'it with a `theme-guard:` comment on the colour or the line above it.\n\n'
          '${offenders.join('\n')}',
    );
  });
}

/// A `color:` argument set to white, cool grey, or a legacy cool off-white hex.
///
/// Translucent values (`Colors.white.withValues(...)`, `Colors.white24`) are
/// overlays on photos and dark surfaces, not page fills, so they are skipped.
final RegExp _fillPattern = RegExp(
  r'color:\s*('
  r'Colors\.white\b(?!\.|[0-9])'
  r'|Colors\.grey\.shade(?:50|100|200)\b'
  r'|Color\(0xFFF(?:5F5F5|5F0EB|0F0F0|7F5F2|AF6F1|5F5F5)\)'
  r')',
);

/// Calls whose `color:` argument paints a surface.
const Set<String> _surfaceCalls = {
  'Container',
  'BoxDecoration',
  'DecoratedBox',
  'SoleCard',
  'Card',
  'Material',
  'ColoredBox',
};

/// The same calls, plus the ones that paint *chrome* rather than a page:
/// app bars, swipe actions, avatars and filled buttons.
const Set<String> _fillCalls = {
  ..._surfaceCalls,
  'AppBar',
  'SlidableAction',
  'CircleAvatar',
  'SolePrimaryButton',
  'FilledButton',
  'ElevatedButton',
  'OutlinedButton',
};

/// An *ink* argument (text, icon, progress mark) built from the *page* token.
///
/// `AppConstants.surfaceLight` is the page: white on light, `#111111` on dark.
/// As ink it is only ever right on a screen that is dark in *both* modes (the
/// auth hero, the AR and camera screens, the photo lightboxes), and there the
/// pinned role is `AppConstants.inkInverse` — which is the same white on light,
/// so switching is a light-mode no-op. Left as `surfaceLight`, those labels
/// turn near-black on dark: the "the links are not seen" bug.
final RegExp _pageInkPattern = RegExp(
  r'color:\s*AppConstants\.surfaceLight\b(?!\.)',
);

/// Calls whose `color:` argument paints *ink* rather than a surface.
const Set<String> _inkCalls = {
  'Icon',
  'IconThemeData',
  'TextStyle',
  'bodyStyle',
  'headlineStyle',
  'monoStyle',
  'CircularProgressIndicator',
};

/// An opaque fill built from the *ink* token.
///
/// The `(?!\.)` is what keeps the translucent idiom legal:
/// `secondary.withValues(alpha: 0.06)` is a tint on a surface, not a fill, and
/// its own role is tracked separately (docs/AI/DARK_MODE_PLAN.md §4.1).
final RegExp _inkFillPattern = RegExp(
  r'(?:backgroundColor|color):\s*AppConstants\.secondary\b(?!\.)',
);

/// Written on (or directly above) the line of an ink-token fill whose ink flips
/// with it, with the reason. In place, not in a list here: the same `color:`
/// line appears in dozens of files, so a list would whitelist all of them.
const String _themeGuardOptOut = 'theme-guard:';

/// Is the flagged colour a documented exception?
///
/// The marker may sit on the flagged line or anywhere in the comment block
/// directly above it: the reason reads better written out over a couple of
/// lines than crammed in behind the value.
bool _optsOut(String source, int index) {
  final lines = source.split('\n');
  var line = '\n'.allMatches(source.substring(0, index)).length;

  if (lines[line].contains(_themeGuardOptOut)) return true;

  while (line > 0) {
    line--;
    final above = lines[line].trim();
    if (!above.startsWith('//')) return false;
    if (above.contains(_themeGuardOptOut)) return true;
  }
  return false;
}

/// Fills that are intentionally not cream, matched against the trimmed line.
const Set<String> _allowedFills = {
  // Shimmer.fromColors uses the child purely as an alpha mask, so this colour
  // is never painted; the seller shimmer palette supplies the visible tone.
  'child: Container(color: Colors.white),',
};

/// Walks backwards from [index] to the parenthesis that encloses it and
/// returns the identifier immediately before it (the call being built).
///
/// The result is the *last* dot segment, so a qualified helper
/// (`AppConstants.bodyStyle`) is reported as `bodyStyle` — the name the call
/// sets are written against.
String _enclosingCall(String source, int index) {
  var depth = 0;
  for (var i = index - 1; i >= 0; i--) {
    final char = source[i];
    if (char == ')') {
      depth++;
    } else if (char == '(') {
      if (depth == 0) {
        final prefix = source.substring(0, i);
        final match = RegExp(r'([A-Za-z_][A-Za-z0-9_.]*)\s*$').firstMatch(prefix);
        return match?.group(1)?.split('.').last ?? '';
      }
      depth--;
    }
  }
  return '';
}

String _lineOf(String source, int index) {
  final start = source.lastIndexOf('\n', index) + 1;
  final end = source.indexOf('\n', index);
  return source.substring(start, end == -1 ? source.length : end);
}
