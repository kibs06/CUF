import 'dart:io';

import 'package:app/constants/app_constants.dart';
import 'package:app/services/webview_composition.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

/// A stand-in for `AndroidWebViewPlatform`.
///
/// It exists so the *decision* — wrap or not, once or twice, on which platform —
/// can be tested without a device, a channel or a plugin host: the four creation
/// methods it inherits all throw `UnimplementedError`, and nothing here calls
/// them, because what is asserted is which platform the wrapper wraps and how
/// often. The widget it builds is asserted at the source level below, and the
/// real one is measured on hardware: building an `AndroidWebViewWidget` needs a
/// real `AndroidWebViewController`, whose constructor calls into the WebView's
/// settings channel and would fail on the test harness rather than on the box.
class _FakePlatform extends WebViewPlatform {}

void main() {
  tearDown(() {
    // The install writes a process-wide singleton, so a test that left one behind
    // would decide the next test's reading.
    WebViewPlatform.instance = _FakePlatform();
  });

  group('the hybrid-composition install', () {
    test('wraps the registered platform on Android, once', () {
      final inner = _FakePlatform();
      expect(
        installHybridCompositionWebViews(
          isAndroid: true,
          enabled: true,
          current: inner,
        ),
        isTrue,
      );
      final installed = WebViewPlatform.instance;
      expect(installed, isA<HybridCompositionWebViewPlatform>());
      expect(
        (installed! as HybridCompositionWebViewPlatform).inner,
        same(inner),
      );

      // A second call finds its own wrapper and does nothing — a double wrap
      // would delegate through itself and rebuild the widget twice.
      expect(
        installHybridCompositionWebViews(isAndroid: true, enabled: true),
        isFalse,
      );
      expect(WebViewPlatform.instance, same(installed));
    });

    test('leaves iOS alone, and leaves the switch in charge', () {
      final inner = _FakePlatform();
      WebViewPlatform.instance = inner;
      expect(
        installHybridCompositionWebViews(
          isAndroid: false,
          enabled: true,
          current: inner,
        ),
        isFalse,
        reason: 'iOS has no Android platform views to compose',
      );
      expect(WebViewPlatform.instance, same(inner));

      expect(
        installHybridCompositionWebViews(
          isAndroid: true,
          enabled: false,
          current: inner,
        ),
        isFalse,
        reason: 'SHOE_PREVIEW_HYBRID=false must restore the package default',
      );
      expect(WebViewPlatform.instance, same(inner));
    });

    test('the default is the shipped one — a release APK needs no define', () {
      expect(AppConstants.shoePreviewHybridComposition, isTrue);
    });
  });

  group('the wiring, read as source', () {
    // The flag itself cannot be exercised here (it needs a real controller), and
    // the call site cannot be mounted (main() starts Firebase and Supabase), so
    // the same tool the other 3D contract tests use: read the call site.
    final service =
        File('lib/services/webview_composition.dart').readAsStringSync();
    final main = File('lib/main.dart').readAsStringSync();

    test('the widget is built with hybrid composition, not the package default',
        () {
      expect(service, contains('displayWithHybridComposition: true'));
      expect(service, isNot(contains('displayWithHybridComposition: false')));
      expect(
        service,
        contains('AndroidWebViewWidget('),
        reason:
            'the wrapper has to build the Android widget itself — the package '
            'builds its own with the default and exposes no switch',
      );
    });

    test('every other creation stays on the platform it wrapped', () {
      for (final method in const [
        'createPlatformCookieManager',
        'createPlatformNavigationDelegate',
        'createPlatformWebViewController',
      ]) {
        expect(
          service,
          contains('inner.$method(params)'),
          reason: "$method must be the platform's own, not a re-implementation",
        );
      }
    });

    test('main installs it before the first frame, and Android only', () {
      final callIndex = main.indexOf('installHybridCompositionWebViews();');
      expect(callIndex, greaterThan(0));
      expect(
        main.indexOf('WidgetsFlutterBinding.ensureInitialized();'),
        lessThan(callIndex),
      );
      // After the binding (the platform implementation is registered by then) and
      // before the app is built: a controller created earlier would keep the
      // texture path for the whole session.
      expect(main.indexOf('runApp('), greaterThan(callIndex));
      expect(service, contains('Platform.isAndroid'));
    });
  });
}
