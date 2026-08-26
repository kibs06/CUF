import 'package:app/constants/app_constants.dart';
import 'package:app/widgets/foot_size_v2/glass_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
        home: ColoredBox(color: Colors.blue, child: Center(child: child)),
      );

  testWidgets('renders its child inside a rounded glass panel', (tester) async {
    await tester.pumpWidget(host(
      const GlassCard(child: Text('Hold still')),
    ));

    expect(find.text('Hold still'), findsOneWidget);
    // ClipRRect + BackdropFilter stack is present.
    expect(find.byType(ClipRRect), findsOneWidget);
    expect(find.byType(BackdropFilter), findsOneWidget);
  });

  testWidgets('tones change the glass tint', (tester) async {
    Future<Color> tintOf(GlassTone tone) async {
      await tester.pumpWidget(host(GlassCard(tone: tone, child: const SizedBox())));
      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(GlassCard),
          matching: find.byType(Container),
        ),
      );
      return (container.decoration! as BoxDecoration).color!;
    }

    final neutral = await tintOf(GlassTone.neutral);
    final warning = await tintOf(GlassTone.warning);
    final success = await tintOf(GlassTone.success);
    final active = await tintOf(GlassTone.active);

    expect(neutral, isNot(equals(warning)));
    expect(success, isNot(equals(active)));
  });

  testWidgets('custom border radius and padding are honored', (tester) async {
    await tester.pumpWidget(host(
      const GlassCard(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        padding: EdgeInsets.all(32),
        child: SizedBox(width: 10, height: 10),
      ),
    ));

    final clip = tester.widget<ClipRRect>(find.byType(ClipRRect));
    expect(clip.borderRadius, equals(const BorderRadius.all(Radius.circular(16))));

    final container = tester.widget<Container>(
      find.descendant(of: find.byType(GlassCard), matching: find.byType(Container)),
    );
    expect(container.padding, equals(const EdgeInsets.all(32)));
  });

  testWidgets('default radius is the stadium pill', (tester) async {
    await tester.pumpWidget(host(
      const GlassCard(child: SizedBox()),
    ));
    final clip = tester.widget<ClipRRect>(find.byType(ClipRRect));
    expect(clip.borderRadius, equals(AppConstants.stadiumRadius));
  });
}
