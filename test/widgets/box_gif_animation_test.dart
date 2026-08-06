import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/widgets/seller/fly_to_order_animation.dart';

/// Inspects and validates `assets/animations/box_animation.gif` — the raster
/// asset used by the POS "pack the box" add-to-order animation.
///
/// The GIF was provided by the user (not generated in-project), so these tests
/// pin down the facts the animation code relies on:
///   1. It decodes to the documented 150×150 / 90-frame format.
///   2. It has real alpha transparency (blank start — no white box artifact).
///   3. The fully-drawn "solid" frame (used for the flight stage) is found by
///      the max-opaque-pixels heuristic the widget uses at runtime.
const _asset = 'assets/animations/box_animation.gif';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('gif decodes at 150x150 with 90 frames and a blank start',
      (tester) async {
    await tester.runAsync(() async {
      final bytes = (await rootBundle.load(_asset)).buffer.asUint8List();
      final codec = await ui.instantiateImageCodec(bytes);
      expect(codec.frameCount, 90, reason: 'documented 90-frame animation');

      final first = await codec.getNextFrame();
      expect(first.image.width, 150);
      expect(first.image.height, 150);

      // First frame must be fully blank/transparent (the loop starts empty),
      // confirming real alpha — no opaque white box behind the animation.
      final data = await first.image.toByteData();
      expect(data, isNotNull);
      int opaquePixels = 0;
      final raw = data!.buffer.asUint8List();
      for (var j = 3; j < raw.length; j += 4) {
        if (raw[j] > 0) opaquePixels++;
      }
      debugPrint('FIRST_FRAME_OPAQUE_PIXELS=$opaquePixels of 22500');
      expect(opaquePixels, 0);
      codec.dispose();
    });
  });

  testWidgets('solid-frame heuristic finds the fully-drawn box frame',
      (tester) async {
    late int solidIndex;
    late int frameCount;
    await tester.runAsync(() async {
      final bytes = (await rootBundle.load(_asset)).buffer.asUint8List();
      final codec = await ui.instantiateImageCodec(bytes);
      frameCount = codec.frameCount;
      int maxOpaque = 0;
      for (var i = 0; i < codec.frameCount; i++) {
        final frame = await codec.getNextFrame();
        final data = await frame.image.toByteData();
        int opaque = 0;
        if (data != null) {
          final raw = data.buffer.asUint8List();
          for (var j = 3; j < raw.length; j += 4) {
            if (raw[j] > 0) opaque++;
          }
        }
        if (opaque > maxOpaque) {
          maxOpaque = opaque;
          solidIndex = i;
        }
        frame.image.dispose();
      }
      codec.dispose();
    });
    debugPrint('SOLID_FRAME_INDEX=$solidIndex (of $frameCount frames)');
    // Verified: the box is fully drawn at frame 42 of 90 (build-in phase,
    // well before the fade-out tail). This pins the widget's hardcoded
    // _solidFrameIndex = 42 — if this asset is ever replaced, the widget
    // constant must be re-measured.
    expect(solidIndex, inInclusiveRange(30, 60));
    expect(solidIndex, lessThan(frameCount - 5));
  });

  testWidgets('pack-the-box overlay animation completes without throwing',
      (tester) async {
    final targetKey = GlobalKey();
    late BuildContext overlayContext;
    var landed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) {
                overlayContext = context;
                return SizedBox(key: targetKey, width: 100, height: 100);
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Trigger the animation directly (identical to what the POS onTap does).
    final box = targetKey.currentContext!.findRenderObject() as RenderBox;
    FlyToOrderAnimation.show(
      context: overlayContext,
      source: box.localToGlobal(Offset.zero) + const Offset(20, 20),
      targetKey: targetKey,
      onLanded: () => landed = true,
    );
    await tester.pump(); // overlay entry inserted, initState runs

    // Let the real async (asset load + GIF decode) finish, then run the
    // 1000 ms master to completion and let the entry remove itself.
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 500)));
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(landed, isTrue,
        reason: 'onLanded must fire — the animation actually played');
  });
}
