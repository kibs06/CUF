import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:app/constants/app_brightness.dart';

/// Runs before every test file in the suite.
///
/// The colour tokens resolve against [AppBrightness] — one process-wide value
/// the app root publishes. A test that paints in dark mode would otherwise
/// leak that palette into the next test in the same file, where widgets are
/// asserted against the light values they have always had.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  setUp(AppBrightness.reset);
  await testMain();
}
