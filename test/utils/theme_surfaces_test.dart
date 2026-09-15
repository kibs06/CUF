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

/// Fills that are intentionally not cream, matched against the trimmed line.
const Set<String> _allowedFills = {
  // Shimmer.fromColors uses the child purely as an alpha mask, so this colour
  // is never painted; the seller shimmer palette supplies the visible tone.
  'child: Container(color: Colors.white),',
};

/// Walks backwards from [index] to the parenthesis that encloses it and
/// returns the identifier immediately before it (the call being built).
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
        return match?.group(1) ?? '';
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
