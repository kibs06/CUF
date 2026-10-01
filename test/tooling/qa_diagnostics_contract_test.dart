import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Cross-artifact guards for the QA diagnostic channel — the one that has to work
/// without adb.
///
/// ⚠️ **Why this file exists.** The phone this feature is measured on has developer
/// options locked behind a password its previous owner set, so no `adb logcat` will
/// ever be read from it. That turns five files into an interface with no compiler
/// behind it: the two Kotlin sides that write the log, the shell script that pulls a
/// capture off a device that *does* have adb, the workflow that publishes it as an
/// artifact, and the heartbeat file name all of them share. A rename on any side is
/// silent here and expensive there — a capture tool looking for a file the renderer
/// stopped writing produces an empty folder and no error, and a workflow that lost
/// its `abi` input builds the wrong binary for the machine it was dispatched for.
void main() {
  const viewPath =
      'android/app/src/main/kotlin/com/solevision/app/tryon/ArTryOnView.kt';
  const pluginPath =
      'android/app/src/main/kotlin/com/solevision/app/tryon/ArTryOnPlugin.kt';
  const capturePath = 'tool/qa_capture.sh';
  const logcatWorkflowPath = '.github/workflows/qa-logcat.yml';
  const apkWorkflowPath = '.github/workflows/qa-apk.yml';
  const readmePath = 'README.md';

  late String view;
  late String plugin;
  late String capture;
  late String logcatWorkflow;
  late String apkWorkflow;
  late String readme;

  String read(String path) {
    final file = File(path);
    expect(file.existsSync(), isTrue, reason: 'expected $path to exist');
    return file.readAsStringSync();
  }

  setUpAll(() {
    view = read(viewPath);
    plugin = read(pluginPath);
    capture = read(capturePath);
    logcatWorkflow = read(logcatWorkflowPath);
    apkWorkflow = read(apkWorkflowPath);
    readme = read(readmePath);
  });

  group('the try-on renderer writes to the channel a locked phone can export', () {
    test('both native sides relay into the in-app diagnostics file', () {
      // The relay is `DiagRelay`, not a log line: it appends to the same
      // `nav_diag.log` the app's own share-sheet export hands out. Without it a
      // P30 Pro run leaves the page's heartbeat and nothing about the way there.
      for (final source in [view, plugin]) {
        expect(source, contains('import com.solevision.app.arfoot.DiagRelay'));
        expect(source, contains('DiagRelay.log("preview"'));
      }
    });

    test('the events that explain a missing or frozen shoe are all relayed', () {
      // One assertion per fault this channel was built to answer. Each names the
      // line a reader greps for in an exported log, so losing one fails here
      // rather than as a silence in a file nobody can compare against.
      expect(view, contains('renderer facts: '));
      expect(view, contains('REFUSED the load'));
      expect(view, contains('beginFrame refused'));
      expect(view, contains('rebuilding the ')); // the chain repair
      expect(view, contains('swap chain NULL — retry'));
      expect(view, contains('renderFrame threw, loop STOPPED'));
      expect(view, contains('teardown BEGIN'));
      expect(view, contains('dispose(): finished'));
      // Every phase of teardown, because the exit crash destroys its own evidence: the process
      // dies partway through, and what the next launch can read is only what was written before
      // it. One line per completed phase is what turns "it crashed when I left the viewer" into
      // "it reached the swap chain and never reached the engine".
      expect(view, contains('teardown: loop stopped, frame callback removed'));
      expect(view, contains('teardown: asset destroyed'));
      expect(view, contains('teardown: swap chain destroyed, flushAndWait='));
      expect(view, contains('teardown: view/scene/renderer/entities/loader/materials destroyed'));
      expect(view, contains('teardown END'));
      // The bounded surface path writes its own two lines; a surface going away is rare, so they
      // are per event rather than per frame.
      expect(view, contains('surface detached: loop stopped, swap chain destroyed'));
      expect(view, contains('surface detached: flushAndWait='));
      expect(plugin, contains('preview view available — parked:'));
      expect(plugin, contains('setPreviewModel'));
    });

    test('the heartbeat separates loop iterations from presents', () {
      // The first real-device readout could not tell a live loop from a stalled one (it counted
      // loop iterations as `frames=`). These are the counters that separate them, plus the one
      // "why" Filament exposes from Java (`Engine.hasUnrecoverableFailure`).
      for (final field in <String>[
        'iter=',
        'present=',
        'beginFail=',
        'rebuild=',
        'unrec=',
      ]) {
        expect(view, contains(field), reason: 'heartbeat field $field disappeared');
      }
      expect(view, contains('hasUnrecoverableFailure'));
    });

    test('the per-frame refusal branch cannot flood the file', () {
      // ⚠️ The refusal branch runs once per frame and the relay fsyncs every line,
      // so an unconditional call there would push out the lifecycle lines that say
      // what led to the stall. The milestone is what keeps it to a heartbeat of its
      // own — and this is the guard that a future edit cannot quietly drop it.
      expect(view, contains('REFUSAL_MILESTONE_FRAMES'));
      expect(
        view,
        contains('beginFrameFailStreak % REFUSAL_MILESTONE_FRAMES == 0'),
      );
    });
  });

  group('the capture tool pulls the file the renderer writes', () {
    test('the heartbeat file name is the same on both sides', () {
      // The one string that cannot be allowed to drift: the native side writes it
      // into `filesDir`, and `run-as` reads it back by name.
      final name = RegExp(r'const val STATUS_FILE_NAME = "([^"]+)"')
          .firstMatch(view)
          ?.group(1);
      expect(name, isNotNull, reason: 'ArTryOnView should declare STATUS_FILE_NAME');
      expect(capture, contains('files/$name'));
    });

    test('it reads a debuggable app the way only a debuggable app can', () {
      // `run-as` is a debuggable-app privilege, which is why the QA APK is built
      // `--debug` and re-signed rather than released; `exec-out` keeps the device's
      // newlines intact.
      expect(capture, contains('run-as'));
      expect(capture, contains('exec-out'));
      expect(capture, contains('--check'));
      // A capture that silently reports an empty log is worse than one that fails:
      // the missing-device path is an exit code, not an empty folder.
      expect(capture, contains('exit 2'));
      expect(capture, contains('exit 3'));
      // An emulator can never render this model (F14/F24), and the tool says so
      // rather than letting a red box be read as a regression.
      expect(capture, contains('emulator-'));
    });
  });

  group('the workflows stay measurements, not releases', () {
    test('the logcat workflow publishes an artifact and never a release', () {
      expect(logcatWorkflow, contains('workflow_dispatch:'));
      expect(logcatWorkflow, contains('permissions:'));
      expect(logcatWorkflow, contains('contents: read'));
      expect(logcatWorkflow, contains('solevision-qa-logcat-'));
      // The door for the phone with no adb.
      expect(logcatWorkflow, contains('log_url'));
      // …and the door for a machine with the phone plugged in.
      expect(logcatWorkflow, contains('tool/qa_capture.sh'));
      expect(logcatWorkflow, contains('--check'));
      expect(logcatWorkflow, contains('actions/upload-artifact@'));
      // No publishing path, on purpose: this is a measurement.
      expect(logcatWorkflow, isNot(contains('gh release')));
      expect(logcatWorkflow, isNot(contains('contents: write')));
    });

    test('the QA APK workflow can build for an emulator, in Flutter\'s spelling', () {
      // `x86_64` is the input a person types; `android-x64` is what Flutter calls
      // it. There is no `android-x86_64`, and a wrong value here fails the build —
      // but only after a runner has spent four minutes on it.
      expect(apkWorkflow, contains('abi:'));
      expect(apkWorkflow, contains('x86_64'));
      expect(apkWorkflow, contains('PLATFORM=android-x64'));
      // …and not the spelling that looks right and is not a Flutter target at all.
      expect(apkWorkflow, isNot(contains('PLATFORM=android-x86_64')));
      // The default ABI keeps the artifact name the README documents.
      expect(apkWorkflow, contains('solevision-qa-instrumented-apk'));
    });

    test('the README names both routes, because neither works alone', () {
      // One is for the phone that cannot run adb, one is for the machine that can;
      // a reader has to be able to tell which is theirs. Prose wraps, so the text is
      // unwrapped first — otherwise a reflow of the paragraph would fail this instead
      // of a change to what it says.
      final prose = readme.replaceAll(RegExp(r'\s+'), ' ');
      expect(prose, contains('tool/qa_capture.sh'));
      expect(prose, contains('Foot Sizing → the bug icon in the app bar → the share sheet'));
      expect(prose, contains('log_url='));
    });
  });

  test('shell scripts are checked out with LF endings', () {
    // `core.autocrlf=true` is normal on the Windows machines this is built on, and
    // a CRLF shebang makes Git Bash refuse to run the script at all.
    final attributes = read('.gitattributes');
    expect(attributes, contains('*.sh text eol=lf'));
  });
}
