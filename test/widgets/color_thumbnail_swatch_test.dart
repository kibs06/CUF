import 'package:app/constants/app_constants.dart';
import 'package:app/widgets/color_thumbnail_swatch.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The white/cream fallback the product detail screen resolves for light
/// variant colors — `_swatchColorFor` maps white / cream / beige / off-white /
/// suede to this. A swatch with this color and no image is the exact case that
/// used to be invisible on a white card.
const _cream = Color(0xFFF1E8DC);

void main() {
  Widget wrap(Widget child) =>
      MaterialApp(home: Scaffold(body: Center(child: child)));

  ColorThumbnailSwatch swatch({bool selected = false, String? imageUrl}) {
    return ColorThumbnailSwatch(
      name: 'Off-White Suede',
      fallbackColor: _cream,
      selected: selected,
      imageUrl: imageUrl,
      onTap: () {},
    );
  }

  BoxDecoration decorationOf(WidgetTester tester, Key key) {
    final container = tester.widget<Container>(find.byKey(key));
    return container.decoration! as BoxDecoration;
  }

  testWidgets('an unselected white/cream swatch still draws a visible border',
      (tester) async {
    await tester.pumpWidget(wrap(swatch()));

    final ring = find.byKey(ColorThumbnailSwatch.hairlineRingKey);
    expect(ring, findsOneWidget,
        reason: 'the always-on hairline ring must be in the tree');

    final border =
        decorationOf(tester, ColorThumbnailSwatch.hairlineRingKey).border!
            as Border;
    expect(border.top.width, 1);
    expect(border.top.style, BorderStyle.solid);
    expect(border.top.color, isNot(Colors.transparent),
        reason: 'a transparent ring is what made the white swatch invisible');
    expect(border.top.color, AppConstants.borderGray.withValues(alpha: 0.5),
        reason: 'must match the seller-side swatch ring for consistency');
  });

  testWidgets('the hairline ring wraps (sits outside) the ClipOval',
      (tester) async {
    await tester.pumpWidget(wrap(swatch()));

    // The ring must be the PARENT of the ClipOval — a ring drawn inside the
    // clip gets clipped away and is never visible.
    expect(
      find.descendant(
        of: find.byKey(ColorThumbnailSwatch.hairlineRingKey),
        matching: find.byType(ClipOval),
      ),
      findsOneWidget,
      reason: 'the ring should contain the ClipOval',
    );
    expect(
      find.ancestor(
        of: find.byKey(ColorThumbnailSwatch.hairlineRingKey),
        matching: find.byType(ClipOval),
      ),
      findsNothing,
      reason: 'the ring must not be inside the ClipOval or it would be clipped',
    );
  });

  testWidgets('the swatch content box stays 40x40 after adding the ring',
      (tester) async {
    await tester.pumpWidget(wrap(swatch()));

    // Guards the padding compensation: the extra 1px inner ring must not
    // shrink the visible thumbnail.
    expect(tester.getSize(find.byType(ClipOval)), const Size(40, 40));
  });

  testWidgets('a selected swatch still shows the primary selection ring',
      (tester) async {
    await tester.pumpWidget(wrap(swatch(selected: true)));

    final hasSelectionRing = tester
        .widgetList<Container>(find.byType(Container))
        .map((c) => c.decoration)
        .whereType<BoxDecoration>()
        .map((d) => d.border)
        .whereType<Border>()
        .any((b) => b.top.color == AppConstants.primary && b.top.width == 2);

    expect(hasSelectionRing, isTrue,
        reason: 'the selection ring must survive the hairline-ring change');
  });
}
