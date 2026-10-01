import 'dart:io';

import 'package:app/screens/shared/app_logs_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// **The App logs screen** — the one tool a fault gets reported with when the
/// phone it happened on has no adb.
///
/// What is worth asserting here is not cosmetics. It is that the screen reads the
/// *tail* of a file that a dying process may have left mid-write (`utf8` decoded
/// permissively, because the last line is the one that matters), that it is honest
/// when there is nothing to show, that the number of lines is not quietly lied
/// about when the file is bigger than the view, and that the row that opens it
/// cannot appear outside dev mode — the last one read as source, the same way the
/// product-page contract test reads its call sites, because `SettingsScreen`
/// cannot be mounted here without a provider stack and a signed-in user.
///
/// **Why every test injects a reader.** The screen's production read is
/// `dart:io`, and a `testWidgets` body runs in a fake-async zone where that
/// future never completes — `pumpAndSettle` just times out. The seam still reads
/// the real fixture file each test wrote, synchronously, and decodes it with the
/// production [decodeLogBytes], so the truncated-tail case is exercised for real
/// rather than described.
void main() {
  final settingsScreen =
      File('lib/screens/shared/settings_screen.dart').readAsStringSync();

  late Directory temp;
  late String logPath;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('app_logs_test');
    logPath = '${temp.path}${Platform.pathSeparator}nav_diag.log';
  });

  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  /// The production read — bytes off the file, decoded with the same
  /// [decodeLogBytes] the screen uses — run synchronously so it can complete
  /// inside fake async.
  LogTailReader fixtureReader() => (path) async {
        final file = File(path);
        if (!file.existsSync()) return null;
        final bytes = file.readAsBytesSync();
        return LogContents(text: decodeLogBytes(bytes), bytes: bytes.length);
      };

  Future<void> pumpLog(WidgetTester tester, {LogTailReader? reader}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AppLogsScreen(
          pathOverride: logPath,
          reader: reader ?? fixtureReader(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('a log with something in it', () {
    testWidgets('shows the recorded lines, including the last one', (tester) async {
      File(logPath).writeAsStringSync(
        '2026-10-01T19:31:55.000 [preview] engine ready: '
        'backend=OPENGL supported=FEATURE_LEVEL_2 active=FEATURE_LEVEL_2\n'
        '2026-10-01T19:31:55.100 [preview] model 5 loaded in 167ms: renderables=1\n'
        '2026-10-01T19:31:55.200 [preview] beginFrame refused the frame\n',
      );

      await pumpLog(tester);

      // The tail is the whole point: this is the file a crash leaves behind.
      expect(
        find.textContaining('model 5 loaded in 167ms'),
        findsOneWidget,
        reason: 'the lines that led to a fault are what the screen exists for',
      );
      expect(find.textContaining('beginFrame refused the frame'), findsOneWidget);
      expect(find.textContaining('3 lines'), findsOneWidget);
    });

    testWidgets('a tail cut mid-character still reads', (tester) async {
      // A process killed during a write leaves an incomplete UTF-8 sequence.
      // `utf8.decode(allowMalformed: true)` is why this test exists: a strict
      // decode would throw on exactly the write a crash report needs.
      final bytes = <int>[
        ...'2026-10-01T19:31:55.100 [preview] swap chain built 968x1458\n'
            .codeUnits,
        0xE2, 0x80, // a truncated em dash
      ];
      File(logPath).writeAsBytesSync(bytes);

      await pumpLog(tester);

      expect(find.textContaining('swap chain built'), findsOneWidget);
      expect(find.textContaining('Could not read the log'), findsNothing);
    });

    testWidgets('a file bigger than the view says so instead of pretending',
        (tester) async {
      final big = StringBuffer();
      for (var i = 0; i < 2005; i++) {
        big.writeln('2026-10-01T19:31:55.$i [preview] line $i');
      }
      File(logPath).writeAsStringSync(big.toString());

      await pumpLog(tester);

      expect(
        find.textContaining('showing the last 2000'),
        findsOneWidget,
        reason: '2005 lines must not be reported as 5',
      );
      expect(find.textContaining('Send the whole file to get the rest'),
          findsOneWidget);
    });

    testWidgets('copy-all puts every line on the clipboard', (tester) async {
      File(logPath).writeAsStringSync(
        'first line\nsecond line\n',
      );
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          calls.add(call);
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });

      await pumpLog(tester);
      await tester.tap(find.byTooltip('Copy every line'));
      await tester.pumpAndSettle();

      final copied = calls.firstWhere(
        (call) => call.method == 'Clipboard.setData',
        orElse: () => throw StateError('nothing reached the clipboard'),
      );
      expect(
        (copied.arguments as Map)['text'],
        contains('second line'),
        reason: 'pasting the tail into a report is the fastest route out of a '
            'phone with no cable',
      );
    });
  });

  group('a log with nothing in it', () {
    testWidgets('says so, and says what to do about it', (tester) async {
      await pumpLog(tester); // never written

      expect(find.text('Nothing recorded yet'), findsOneWidget);
      expect(find.textContaining('3D preview'), findsOneWidget);
      final copy = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.copy_all_outlined),
      );
      expect(
        copy.onPressed,
        isNull,
        reason: 'the button exists either way; it is disabled, not missing',
      );
    });
  });

  group('the row that opens it', () {
    test('is behind dev mode, and opens this screen', () {
      // Both halves matter. The gate, because a customer must never be handed a
      // screen full of operational words; the push, because a gate nobody wires
      // to a screen is a row that does nothing.
      expect(settingsScreen, contains('AppLogsScreen'));
      expect(
        settingsScreen,
        contains('DevMode.instance.enabledListenable'),
        reason: 'listening rather than reading once, so the row appears the '
            'moment dev mode is flipped on',
      );
      expect(
        settingsScreen,
        contains('if (!devModeOn) return const SizedBox.shrink();'),
        reason: 'nothing of the Developer section may render for a customer',
      );
    });
  });

  testWidgets('the harness itself renders', (tester) async {
    // Guards the harness above: if `AppLogsScreen` ever needs a provider this
    // test fails here rather than inside every other test in the file.
    await pumpLog(tester);
    expect(find.text('App logs'), findsOneWidget);
  });
}
