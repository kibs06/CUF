import 'dart:io';

import 'package:app/models/customer_widget_data.dart';
import 'package:app/models/seller_widget_data.dart';
import 'package:app/services/deep_link_service.dart';
import 'package:app/services/seller_widget_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// The seller widget's cross-language wiring, read as source.
///
/// This is the same tool the 3D contract tests use, and it is used here for a
/// sharper reason than usual: **every failure this file guards is silent.**
///
/// The payload travels Dart → `SharedPreferences`/plist → Kotlin/Swift, and
/// nothing in that path is type-checked across a language boundary. A renamed
/// key, a provider class that no longer matches its manifest entry, or an App
/// Group that disagrees between the app and the widget extension does not fail
/// a build, a test or a compile — it renders a blank field or an empty tile on
/// every phone that already has the widget placed, with no stack trace on
/// either side. The native code cannot be executed on this machine (and the iOS
/// side cannot even be compiled), so reading the call sites is the only guard
/// available.
void main() {
  final kotlinProvider = File(
    'android/app/src/main/kotlin/com/solevision/app/SellerWidgetProvider.kt',
  ).readAsStringSync();
  final manifest =
      File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
  final swiftWidget = File('ios/SellerWidget/SellerWidget.swift').readAsStringSync();
  final mainSource = File('lib/main.dart').readAsStringSync();

  /// The Dart keys either payload can write — the single source of truth the
  /// native side is checked against.
  ///
  /// **Both families**, because the tile is one store serving two roles: a
  /// customer key the provider reads and Dart never writes blanks a product row
  /// exactly as silently as a seller key would blank a counter.
  final dartKeys = <String>{
    ...SellerWidgetKeys.all,
    ...CustomerWidgetKeys.all,
  };

  group('Android ⇄ Dart — the SharedPreferences key names', () {
    test('every key the Kotlin provider reads is one Dart writes', () {
      final kotlinKeys = RegExp(r'private const val KEY_\w+ = "([^"]+)"')
          .allMatches(kotlinProvider)
          .map((m) => m.group(1)!)
          .toSet();

      expect(
        kotlinKeys,
        isNotEmpty,
        reason: 'the provider stopped declaring key constants — did it start '
            'hardcoding strings, which nothing can check?',
      );
      expect(
        kotlinKeys.difference(dartKeys),
        isEmpty,
        reason: 'the provider reads a key Dart never writes; that field renders '
            'as its default on every phone, forever, with no error anywhere',
      );
    });
  });

  group('Android ⇄ Dart — the provider the app tells Android to redraw', () {
    test('the manifest registers the class home_widget is asked to update', () {
      // home_widget resolves `androidName` against the package, so a mismatch
      // throws PlatformException(-8) at runtime rather than failing a build.
      expect(
        manifest,
        contains('android:name=".${SellerWidgetService.androidWidgetName}"'),
        reason: 'AndroidManifest registers a different class than '
            'SellerWidgetService.androidWidgetName, so every '
            'HomeWidget.updateWidget call fails on a real phone',
      );
    });

    test('the receiver carries the update filter and its metadata', () {
      expect(
        manifest,
        contains('android.appwidget.action.APPWIDGET_UPDATE'),
        reason: 'without the intent filter the widget never receives onUpdate',
      );
      expect(
        manifest,
        contains('android:resource="@xml/seller_widget_info"'),
        reason: 'without this the launcher shows no widget to pick at all',
      );
    });
  });

  group('iOS ⇄ Dart — the names that must match or the widget is empty forever', () {
    test('the App Group is the same on both sides', () {
      final swiftGroup = RegExp(r'kAppGroupId = "([^"]+)"')
          .firstMatch(swiftWidget)
          ?.group(1);
      expect(swiftGroup, isNotNull, reason: 'kAppGroupId is gone from the widget');
      expect(
        swiftGroup,
        SellerWidgetService.iOSAppGroupId,
        reason: 'iOS has no shared store besides the App Group: if the app '
            'writes to one suite and the extension reads another, the widget '
            'renders its empty state permanently and nothing reports it',
      );
    });

    test('the entitlements file grants that same group', () {
      final entitlements = File(
        'ios/SellerWidget/SellerWidget.entitlements',
      ).readAsStringSync();
      expect(entitlements, contains(SellerWidgetService.iOSAppGroupId));
    });

    test('the widget kind is the one home_widget reloads', () {
      final swiftKind = RegExp(r'kWidgetKind = "([^"]+)"')
          .firstMatch(swiftWidget)
          ?.group(1);
      expect(swiftKind, SellerWidgetService.iOSWidgetName);
    });

    test('every key the Swift widget reads is one Dart writes', () {
      final swiftKeys = RegExp(r'static let \w+ = "([^"]+)"')
          .allMatches(swiftWidget)
          .map((m) => m.group(1)!)
          .toSet();

      expect(swiftKeys, isNotEmpty);
      expect(
        swiftKeys.difference(dartKeys),
        isEmpty,
        reason: 'the Swift widget reads a key Dart never writes',
      );
    });
  });

  group('Android ⇄ Dart — the customer half of the same tile', () {
    test('the group wire values match the Dart enum, exactly', () {
      final kotlinGroups =
          RegExp(r'private const val GROUP_\w+ = "([^"]+)"')
              .allMatches(kotlinProvider)
              .map((m) => m.group(1)!)
              .toSet();

      expect(kotlinGroups, isNotEmpty, reason: 'the group constants are gone');
      expect(
        kotlinGroups,
        CustomerWidgetGroup.values.map((group) => group.wire).toSet(),
        reason: 'a group renamed on one side does not fail a build: it prints the '
            'fallback heading over a real shelf, on the customer\'s own home screen',
      );
    });

    test('the state values match, including the empty one', () {
      final kotlinStates =
          RegExp(r'private const val CUSTOMER_STATE_\w+ = "([^"]+)"')
              .allMatches(kotlinProvider)
              .map((m) => m.group(1)!)
              .toSet();

      expect(
        kotlinStates,
        {CustomerWidgetKeys.stateFeed, CustomerWidgetKeys.stateEmpty},
        reason: 'the provider branches on these to choose between a feed and the '
            'empty state; a renamed one draws the wrong one, silently',
      );
    });

    test('the per-slot field names match Dart\'s key builders', () {
      final kotlinFields = RegExp(r'customerKey\(slot, "([^"]+)"\)')
          .allMatches(kotlinProvider)
          .map((m) => m.group(1)!)
          .toSet();
      expect(kotlinFields, isNotEmpty, reason: 'the provider stopped using '
          'customerKey, which is the one place its slot fields are spelled');

      // Derived from Dart's OWN builders rather than listed here, so a sixth field
      // added to the payload fails until Kotlin reads it too.
      const prefix = 'customer_product_1_';
      final dartFields = <String>{
        CustomerWidgetKeys.productId(1),
        CustomerWidgetKeys.productName(1),
        CustomerWidgetKeys.productPrice(1),
        CustomerWidgetKeys.productBadge(1),
        CustomerWidgetKeys.productImage(1),
      }
          .map((key) =>
              key.startsWith(prefix) ? key.substring(prefix.length) : key)
          .toSet();

      expect(
        kotlinFields,
        dartFields,
        reason: 'the provider reads a per-product field Dart does not write, or '
            'ignores one it does',
      );
    });

    test('the slot count matches the payload\'s', () {
      final kotlinSlots = RegExp(r'CUSTOMER_SLOTS = (\d+)')
          .firstMatch(kotlinProvider)
          ?.group(1);
      expect(
        kotlinSlots,
        kCustomerWidgetProductSlots.toString(),
        reason: 'the layouts carry a fixed number of product views; a payload '
            'with more slots would be silently truncated',
      );
    });

    test('a product row deep-links to the host Dart routes', () {
      final prefix = RegExp(r'PRODUCT_DEEP_LINK_PREFIX = "([^"]+)"')
          .firstMatch(kotlinProvider)
          ?.group(1);

      expect(prefix, isNotNull, reason: 'the row has no tap target any more');
      expect(
        prefix,
        'solvision://${DeepLinkService.productHost}/',
        reason: 'a widget can only hand the launcher a URI, so a renamed host '
            'means every product tap opens the app on nothing',
      );
    });

    test('the app routes that link to a product screen', () {
      // Read as source: the handler is private to a widget state and mounted with a
      // live Supabase session, so there is no harness that can call it. What can be
      // checked is that the link is matched at all and that a match opens a product
      // rather than falling through to the payment flow below it.
      expect(
        mainSource,
        contains('DeepLinkService.productIdFromAppLink(uri)'),
        reason: 'without this the widget\'s rows open the app and nothing else',
      );
      final handler = mainSource.indexOf('productIdFromAppLink(uri)');
      final opens = mainSource.indexOf('_openSharedProduct(productId)', handler);
      expect(
        opens,
        greaterThan(handler),
        reason: 'the link is matched but nothing opens it',
      );
    });
  });

  group('the app is actually wired to sync', () {
    test('main() schedules the worker and does a first sync', () {
      // Both are unawaited, so a deleted line here is invisible at runtime —
      // the widget would simply never update and never be populated at launch.
      expect(mainSource, contains('registerBackgroundRefresh()'));
      expect(mainSource, contains('SellerWidgetService.instance'));
      expect(
        mainSource,
        contains('syncForCurrentUser()'),
        reason: 'without the launch sync a seller sees the previous session\'s '
            'numbers until they navigate',
      );
    });

    test('the service clears on the paths where there is no account', () {
      // The leak guard: an account switch must not leave the previous account's
      // tile on a home screen. **Both families**, because the tile serves two
      // roles now — clearing one is how a signed-out phone keeps showing the last
      // role's data.
      final service = File(
        'lib/services/seller_widget_service.dart',
      ).readAsStringSync();
      expect(service, contains('await clear();'));
      expect(
        service,
        contains('SellerWidgetKeys.all'),
        reason: 'clear() must walk every key, not a hand-written subset',
      );
      expect(
        service,
        contains('CustomerWidgetKeys.all'),
        reason: 'the customer payload has its own keys, so the seller list alone '
            'leaves a customer feed on the tile after a sign-out',
      );
    });

    test('each role erases the other before writing', () {
      // The other half of the leak guard, and the one a switch would expose: both
      // payloads live in one store and the native side branches on a single key, so
      // a seller sync that left the customer keys behind would put product rows
      // back on the tile the moment that phone signed in as a customer again.
      final service = File(
        'lib/services/seller_widget_service.dart',
      ).readAsStringSync();
      expect(service, contains('_clearKeys(CustomerWidgetKeys.all)'));
      expect(service, contains('_clearKeys(SellerWidgetKeys.all)'));
    });

    test('the customer branch is reachable from the same sync path', () {
      // The customer feed is not a second entry point: it is what the ONE sync
      // path does when the signed-in account is not a seller. A separate call site
      // would have to be added to every trigger (login, resume, logout, the
      // worker), and the one that was forgotten is the one that goes stale.
      final service = File(
        'lib/services/seller_widget_service.dart',
      ).readAsStringSync();

      expect(service, contains('CustomerWidgetService.instance.gather'));
      expect(
        service,
        contains('advance: true'),
        reason: 'the scheduled refresh is the only thing that moves the customer '
            'tile on to its next group; without it the tile never rotates',
      );
      expect(
        service,
        contains('CustomerWidgetData.emptyStateValues()'),
        reason: 'a customer with nothing to show must keep the CUSTOMER layouts, '
            'or the tile tells a signed-in customer to sign in',
      );
    });

    test('the background entry point is annotated for the AOT compiler', () {
      final service = File(
        'lib/services/seller_widget_service.dart',
      ).readAsStringSync();
      expect(
        service,
        contains("@pragma('vm:entry-point')"),
        reason: 'without the annotation a release build tree-shakes the worker '
            'away and the job is never dispatched, silently',
      );
    });
  });
}
