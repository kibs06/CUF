import 'package:app/services/space_view_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('hasSpaceView', () {
    test('a usable path is a door, blanks are not', () {
      expect(hasSpaceView('store-1/p1/abc.glb'), isTrue);
      expect(hasSpaceView(null), isFalse);
      expect(hasSpaceView(''), isFalse);
      expect(hasSpaceView('   '), isFalse);
    });
  });

  group('sceneViewerUrl', () {
    test('points Scene Viewer at the public file in ar_only mode', () {
      final uri = sceneViewerUrl(
        'https://example.supabase.co/storage/v1/object/public/shoe-models/a/b.glb',
      );

      expect(uri.host, 'arvr.google.com');
      expect(uri.path, '/scene-viewer/1.0');
      expect(
        uri.queryParameters['file'],
        'https://example.supabase.co/storage/v1/object/public/shoe-models/a/b.glb',
      );
      expect(uri.queryParameters['mode'], 'ar_only');
    });
  });

  group('launchSpaceView', () {
    test('blank path launches nothing', () async {
      var launched = false;
      final ok = await launchSpaceView(
        '  ',
        launch: (_) async {
          launched = true;
          return true;
        },
        publicUrlFor: (_) => 'https://example.test/a.glb',
      );

      expect(ok, isFalse);
      expect(launched, isFalse);
    });

    test(
      'hands the bucket public URL to the ARCore intent, not the storage path',
      () async {
        Uri? seen;
        final ok = await launchSpaceView(
          'store-1/p1/abc.glb',
          launch: (uri) async {
            seen = uri;
            return true;
          },
          publicUrlFor: (path) => 'https://example.test/public/$path',
        );

        expect(ok, isTrue);
        expect(
          seen?.queryParameters['file'],
          'https://example.test/public/store-1/p1/abc.glb',
        );
      },
    );

    test('a refused launch answers false rather than throwing', () async {
      final ok = await launchSpaceView(
        'store-1/p1/abc.glb',
        launch: (_) async => false,
        publicUrlFor: (_) => 'https://example.test/a.glb',
      );

      expect(ok, isFalse);
    });

    test('a throwing launch answers false rather than throwing', () async {
      final ok = await launchSpaceView(
        'store-1/p1/abc.glb',
        launch: (_) => throw Exception('no handler'),
        publicUrlFor: (_) => 'https://example.test/a.glb',
      );

      expect(ok, isFalse);
    });
  });

  group('SpaceViewChannel', () {
    test('sends the Scene Viewer URL to the native ARCore intent', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      const channel = MethodChannel(kSpaceViewMethodChannel);
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return true;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      final url = Uri.parse(
        'https://arvr.google.com/scene-viewer/1.0?file=https%3A%2F%2Fexample.test%2Fa.glb&mode=ar_only',
      );
      final ok = await const SpaceViewChannel().launch(url);

      expect(ok, isTrue);
      expect(calls.single.method, 'launchSceneViewer');
      expect(calls.single.arguments, <String, Object?>{'url': url.toString()});
    });

    test('a missing native side answers false rather than throwing', () async {
      final ok = await const SpaceViewChannel().launch(
        Uri.parse('https://arvr.google.com/scene-viewer/1.0'),
      );

      expect(ok, isFalse);
    });
  });
}
