import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/widgets/app_error_toast.dart';

const String _message = 'Something went wrong. Please try again.';
const String _detail = 'Double-check and try again.';

Widget _harness({
  Duration duration = const Duration(milliseconds: 4500),
  String message = _message,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () => AppErrorToast.show(
              context,
              message: message,
              detail: _detail,
              duration: duration,
            ),
            child: const Text('Trigger'),
          ),
        ),
      ),
    ),
  );
}

/// Tap the trigger and settle the 200ms entrance animation.
Future<void> _showToast(WidgetTester tester) async {
  await tester.tap(find.text('Trigger'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
}

void main() {
  testWidgets('renders the message, detail and a labeled close control',
      (tester) async {
    await tester.pumpWidget(_harness());
    await _showToast(tester);

    expect(find.text(_message), findsOneWidget);
    expect(find.text(_detail), findsOneWidget);
    expect(find.byTooltip('Dismiss'), findsOneWidget);
  });

  testWidgets('announces itself as a live region to screen readers',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_harness());
    await _showToast(tester);

    // The live-region node's label merges the headline + detail + close
    // control, so match with a pattern rather than the exact merged string.
    expect(
      find.bySemanticsLabel(RegExp(_message)),
      findsAtLeastNWidgets(1),
    );
    handle.dispose();
  });

  testWidgets('auto-dismisses after its duration', (tester) async {
    await tester.pumpWidget(
      _harness(duration: const Duration(milliseconds: 500)),
    );
    await _showToast(tester);
    expect(find.text(_message), findsOneWidget);

    // Past the auto-dismiss duration + reverse animation.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text(_message), findsNothing);
  });

  testWidgets('manual close dismisses immediately', (tester) async {
    await tester.pumpWidget(_harness());
    await _showToast(tester);
    expect(find.byTooltip('Dismiss'), findsOneWidget);

    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text(_message), findsNothing);
  });

  testWidgets('a second toast replaces the first instead of stacking',
      (tester) async {
    await tester.pumpWidget(_harness());
    await _showToast(tester);
    expect(find.text(_message), findsOneWidget);

    // Trigger again — the old toast must be removed, not stacked.
    await _showToast(tester);
    expect(find.text(_message), findsOneWidget);
  });

  testWidgets('message and detail text resolve with no underline decoration',
      (tester) async {
    await tester.pumpWidget(_harness());
    await _showToast(tester);

    for (final text in [find.text(_message), find.text(_detail)]) {
      final style = tester.widget<Text>(text).style!;
      // Fully self-contained: nothing from the ambient theme can merge in.
      expect(style.inherit, isFalse);
      // No underline — the toast text must never be decorated.
      expect(
        style.decoration,
        anyOf(isNull, TextDecoration.none),
        reason: 'toast text must never carry an underline decoration',
      );
    }
  });

  testWidgets('appears without shifting the underlying form layout',
      (tester) async {
    await tester.pumpWidget(_harness());
    final before = tester.getTopLeft(find.byType(ElevatedButton));

    await _showToast(tester);
    final after = tester.getTopLeft(find.byType(ElevatedButton));

    expect(after, before, reason: 'toast must float, not push content');
  });
}
