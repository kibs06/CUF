import 'package:app/constants/app_constants.dart';
import 'package:app/widgets/otp_code_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// [OtpCodeField] owns the awkward parts of a segmented code input: focus
/// advance, backspace in an empty box, and paste redistribution. Each of those
/// is easy to get subtly wrong and invisible until a real user hits it, so
/// each gets a test here rather than being covered only through the screen.
void main() {
  Widget wrap(Widget child) => MaterialApp(
        home: Scaffold(body: Center(child: child)),
      );

  Finder box(int index) => find.byKey(ValueKey<String>('otp-box-$index'));

  /// The visible text of each box, so assertions read like the screen.
  List<String> boxes(WidgetTester tester, {int length = 6}) => List.generate(
        length,
        (i) => tester.widget<TextField>(box(i)).controller!.text,
      );

  testWidgets('typing a digit fills the box and advances the caret',
      (tester) async {
    final changes = <String>[];
    await tester.pumpWidget(
      wrap(OtpCodeField(onChanged: changes.add)),
    );
    await tester.pump();

    await tester.enterText(box(0), '4');
    await tester.pump();

    expect(boxes(tester).first, '4');
    expect(changes.last, '4');
  });

  testWidgets('onCompleted fires once every digit is in', (tester) async {
    final completed = <String>[];
    await tester.pumpWidget(
      wrap(OtpCodeField(onCompleted: completed.add)),
    );
    await tester.pump();

    for (var i = 0; i < 5; i++) {
      await tester.enterText(box(i), '${i + 1}');
      await tester.pump();
    }
    expect(completed, isEmpty, reason: 'five digits is not a complete code');

    await tester.enterText(box(5), '6');
    await tester.pump();

    expect(completed, ['123456']);
  });

  testWidgets('pasting the whole code into one box distributes it',
      (tester) async {
    final completed = <String>[];
    await tester.pumpWidget(
      wrap(OtpCodeField(onCompleted: completed.add)),
    );
    await tester.pump();

    // The paste arrives as one multi-digit change on the first box.
    await tester.enterText(box(0), '246810');
    await tester.pump();

    expect(boxes(tester), ['2', '4', '6', '8', '1', '0']);
    expect(completed, ['246810']);
  });

  testWidgets('a paste with separators keeps only the digits', (tester) async {
    await tester.pumpWidget(wrap(const OtpCodeField()));
    await tester.pump();

    await tester.enterText(box(0), '12 34-56');
    await tester.pump();

    expect(boxes(tester), ['1', '2', '3', '4', '5', '6']);
  });

  testWidgets('backspace in an EMPTY box steps back and clears the digit',
      (tester) async {
    final key = GlobalKey<OtpCodeFieldState>();
    await tester.pumpWidget(wrap(OtpCodeField(key: key)));
    await tester.pump();

    await tester.enterText(box(0), '1');
    await tester.pump();
    await tester.enterText(box(1), '2');
    await tester.pump();

    expect(key.currentState!.code, '12');

    // Focus sits on box 2, which is still empty — the case that produces no
    // onChanged and therefore has to be caught as a key event.
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();

    expect(key.currentState!.code, '1');
    expect(boxes(tester)[1], '');
    expect(boxes(tester)[0], '1', reason: 'only one digit should be removed');
  });

  testWidgets('backspace in a FILLED box deletes that digit', (tester) async {
    final key = GlobalKey<OtpCodeFieldState>();
    await tester.pumpWidget(wrap(OtpCodeField(key: key)));
    await tester.pump();

    await tester.enterText(box(0), '7');
    await tester.pump();
    // Re-focus the filled box so the backspace lands on a non-empty field.
    await tester.enterText(box(0), '');
    await tester.pump();

    expect(key.currentState!.code, '');
  });

  testWidgets('clear() empties every box', (tester) async {
    final key = GlobalKey<OtpCodeFieldState>();
    await tester.pumpWidget(wrap(OtpCodeField(key: key)));
    await tester.pump();

    await tester.enterText(box(0), '135790');
    await tester.pump();
    expect(key.currentState!.isComplete, isTrue);

    key.currentState!.clear();
    await tester.pump();

    expect(key.currentState!.code, '');
    expect(boxes(tester), ['', '', '', '', '', '']);
  });

  testWidgets('each box announces its position to screen readers',
      (tester) async {
    await tester.pumpWidget(wrap(const OtpCodeField()));
    await tester.pump();

    final handle = tester.ensureSemantics();
    expect(find.bySemanticsLabel('Digit 1 of 6'), findsOneWidget);
    expect(find.bySemanticsLabel('Digit 6 of 6'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('the box width adapts so a narrow page cannot overflow',
      (tester) async {
    // 320dp is the smallest width still in use (older Androids, iPhone SE).
    // Six fixed 48px boxes plus their gaps need 328px, and the page's 16px
    // gutters leave only 288px here — so this is the case worth pinning.
    tester.view.physicalSize = const Size(320 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      wrap(
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: OtpCodeField(),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    for (var i = 0; i < 6; i++) {
      expect(box(i), findsOneWidget);
      // Height never shrinks, so the tap target survives the squeeze.
      expect(tester.getSize(box(i)).height, 56);
      // 288px of room: (288 - 5*8) / 6 = 41.3 per box, below the 48 ceiling.
      expect(tester.getSize(box(i)).width, closeTo(41.3, 0.2));
    }
  });

  testWidgets('box width is capped on a wide page', (tester) async {
    tester.view.physicalSize = const Size(1200 * 1, 800 * 1);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap(const OtpCodeField()));
    await tester.pump();

    expect(tester.getSize(box(0)).width, 48);
  });

  testWidgets('a box is only filled once it holds a digit', (tester) async {
    await tester.pumpWidget(wrap(const OtpCodeField()));
    await tester.pump();

    InputDecoration decoration(int index) =>
        tester.widget<TextField>(box(index)).decoration!;

    // Empty: a bare hairline outline, so "still to come" is distinguishable
    // from "entered" without reading the digits.
    expect(decoration(0).filled, isFalse);
    expect(
      decoration(0).enabledBorder!.borderSide.color,
      AppConstants.borderGray,
    );
    expect(decoration(0).enabledBorder!.borderSide.width, 1.5);

    await tester.enterText(box(0), '4');
    await tester.pump();

    // Settled: light fill plus a stronger neutral edge. The FOCUSED edge is
    // the accent, and Flutter selects it for whichever box has focus.
    expect(decoration(0).filled, isTrue);
    expect(decoration(0).fillColor, AppConstants.surfaceSubtle);
    expect(
      decoration(0).enabledBorder!.borderSide.color,
      isNot(AppConstants.borderGray),
    );
    expect(decoration(0).focusedBorder!.borderSide.color, AppConstants.primary);

    // And back again when the digit is removed.
    await tester.enterText(box(0), '');
    await tester.pump();
    expect(decoration(0).filled, isFalse);
  });

  testWidgets('the row honours a non-six length', (tester) async {
    final completed = <String>[];
    await tester.pumpWidget(
      wrap(OtpCodeField(length: 4, onCompleted: completed.add)),
    );
    await tester.pump();

    expect(box(4), findsNothing);

    await tester.enterText(box(0), '9876');
    await tester.pump();

    expect(completed, ['9876']);
  });
}
