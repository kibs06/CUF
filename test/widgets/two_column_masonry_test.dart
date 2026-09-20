import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/widgets/two_column_masonry.dart';

/// The grid body the size section packs with: two columns filled by the shorter
/// one, and a closing pair placed against their **own** columns.
///
/// The reason this layout exists rather than `MasonryGridView.count` is the
/// last row — a pinned closing row can only start at the taller column's
/// bottom, so the shorter column's leftover height shows up as a hole. These
/// tests pin the properties that replaced it: every cell one gutter under the
/// previous cell of its column, the closer in the right column whatever the
/// flow did, and the pair closing on one bottom edge.
///
/// Fixed-height cells are used so the numbers are the test's, not a card's:
/// each cell is a `SizedBox` whose height the layout must respect.
const double _margin = 8;
const double _gutter = 8;
const double _width = 208; // → (208 - 16 - 8) / 2 = 92 per column

double get _cellWidth => (_width - 2 * _margin - _gutter) / 2;

/// A cell of a known height, painted so failures read on screen too.
Widget cell(double height, {String? label}) =>
    SizedBox(height: height, child: ColoredBox(
      color: Colors.amber,
      child: label == null ? null : Center(child: Text(label)),
    ));

Widget wrap(Widget grid, {TextDirection direction = TextDirection.ltr}) {
  return Directionality(
    textDirection: direction,
    child: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(width: _width, child: grid),
    ),
  );
}

Rect rectOf(WidgetTester tester, String label) =>
    tester.getRect(find.ancestor(
      of: find.text(label),
      matching: find.byType(ColoredBox),
    ));

void main() {
  testWidgets('packs each cell into the shorter column', (tester) async {
    await tester.pumpWidget(
      wrap(
        TwoColumnMasonry(
          margin: _margin,
          gutter: _gutter,
          children: [
            cell(100, label: 'a'),
            cell(40, label: 'b'),
            cell(150, label: 'c'),
            cell(60, label: 'd'),
          ],
        ),
      ),
    );

    final a = rectOf(tester, 'a');
    final b = rectOf(tester, 'b');
    final c = rectOf(tester, 'c');
    final d = rectOf(tester, 'd');

    // The first cell opens the left column; the second takes the empty right
    // one, on the same line.
    expect(a.left, _margin);
    expect(a.top, 0);
    expect(b.left, _margin + _cellWidth + _gutter);
    expect(b.top, 0);

    // The next cell takes whichever column is shorter — the right, which b
    // left at 40 while a's column stands at 100 — and once that column outgrows
    // the left one the fourth comes back to it. The packing rule, not a table
    // that keeps two cells on every line.
    expect(c.left, b.left);
    expect(c.top, b.bottom + _gutter);
    expect(d.left, a.left);
    expect(d.top, a.bottom + _gutter);

    // The grid is as tall as its deepest column — the right: 40 + 150 + gutters.
    expect(tester.getSize(find.byType(TwoColumnMasonry)).height, 198);
  });

  testWidgets('places the closing pair against their own columns', (
    tester,
  ) async {
    // Same flow, plus the pair: the anchor (second-to-last child) opens the
    // left column, the closer takes the right one.
    await tester.pumpWidget(
      wrap(
        TwoColumnMasonry(
          margin: _margin,
          gutter: _gutter,
          closingCount: 2,
          children: [
            cell(100, label: 'a'),
            cell(40, label: 'b'),
            cell(50, label: 'c'),
            // anchor: into the LEFT column, one gutter under 'a'
            cell(60, label: 'anchor'),
            // closer: into the RIGHT column, one gutter under 'c'
            cell(20, label: 'closer'),
          ],
        ),
      ),
    );

    final a = rectOf(tester, 'a');
    final c = rectOf(tester, 'c');
    final anchor = rectOf(tester, 'anchor');
    final closer = rectOf(tester, 'closer');

    expect(anchor.left, a.left);
    expect(anchor.top, a.bottom + _gutter);
    expect(closer.left, c.left);
    expect(closer.top, c.bottom + _gutter);
    // And the closer is sized to reach the anchor's bottom: no hole, and one
    // bottom edge for the section to end on.
    expect(closer.bottom, anchor.bottom);
    expect(
      tester.getSize(find.byType(TwoColumnMasonry)).height,
      anchor.bottom,
    );
  });

  testWidgets('a closer deeper than the anchor is stretched to reach it', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        TwoColumnMasonry(
          margin: _margin,
          gutter: _gutter,
          closingCount: 2,
          children: [
            cell(20, label: 'a'),
            cell(120, label: 'b'),
            cell(200, label: 'anchor'),
            cell(10, label: 'closer'),
          ],
        ),
      ),
    );

    final b = rectOf(tester, 'b');
    final anchor = rectOf(tester, 'anchor');
    final closer = rectOf(tester, 'closer');

    // The anchor reaches deeper than the right column did, so the closer
    // carries the whole leftover: it is a tall card, not a sliver and not a
    // hole.
    expect(closer.top, b.bottom + _gutter);
    expect(closer.height, moreOrLessEquals(100, epsilon: 0.5));
    expect(closer.bottom, anchor.bottom);
  });

  testWidgets('the closer never shrinks below its floor', (tester) async {
    // A right column already deeper than the anchor's bottom: matching the
    // bottoms exactly would demand a card of nothing.
    await tester.pumpWidget(
      wrap(
        TwoColumnMasonry(
          margin: _margin,
          gutter: _gutter,
          closingCount: 2,
          children: [
            cell(10, label: 'a'),
            cell(300, label: 'b'),
            cell(10, label: "anchor"),
            cell(10, label: 'closer'),
          ],
        ),
      ),
    );

    final closer = rectOf(tester, 'closer');
    expect(
      closer.height,
      moreOrLessEquals(
        _cellWidth * TwoColumnMasonry.minCloserWidthFactor,
        epsilon: 0.5,
      ),
    );
  });

  testWidgets('an RTL page mirrors the columns', (tester) async {
    await tester.pumpWidget(
      wrap(
        TwoColumnMasonry(
          margin: _margin,
          gutter: _gutter,
          children: [cell(20, label: 'a'), cell(20, label: 'b')],
        ),
        direction: TextDirection.rtl,
      ),
    );

    final a = rectOf(tester, 'a');
    final b = rectOf(tester, 'b');
    expect(a.left, _width - _margin - _cellWidth);
    expect(b.left, _margin);
  });
}
