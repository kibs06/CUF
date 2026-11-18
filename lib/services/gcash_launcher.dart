import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// What happened when we tried to hand the customer to GCash.
enum GcashLaunchResult {
  /// GCash came to the front.
  opened,

  /// The phone answered "no activity" — GCash is not installed.
  notInstalled,

  /// iOS/desktop: we cannot address another app by scheme reliably here, so
  /// the caller should say "copied, open GCash" instead of pretending.
  unsupported,
}

/// Opens the GCash app after the customer copies the platform's number.
///
/// Nothing is prefilled: GCash offers no public deep link into "send money",
/// and guessing one would silently do nothing on most versions. Copying the
/// number and putting GCash in front of the customer is the honest version of
/// "one tap to pay" — they paste, type the amount, and come back.
class GcashLauncher {
  GcashLauncher._();

  /// Android package id of the consumer app. The business app is a different
  /// package and is not what a customer pays from.
  static const String androidPackage = 'com.globe.gcash.android';

  /// GCash's launcher activity, as this phone reports it
  /// (`cmd package resolve-activity --brief com.globe.gcash.android`).
  ///
  /// An explicit component, not just `package:`: on the VOG-L29 a
  /// package-scoped MAIN/LAUNCHER intent comes out as an IMPLICIT intent
  /// (EMUI drops the package filter), so Android shows the "Open with"
  /// chooser — Calendar, Chrome, Contacts… — instead of GCash. Naming the
  /// component leaves nothing to resolve.
  ///
  /// Class name only: android_intent_plus builds
  /// `ComponentName(package, componentName)` itself, so a `pkg/class` string
  /// becomes `pkg/pkg.class` and fails with ACTIVITY_NOT_FOUND.
  static const String androidLauncherActivity =
      'gcash.module.splashscreen.mvp.view.SplashScreenActivity';

  /// Best-effort custom scheme for iOS. GCash does not publish one, so a
  /// failure here is normal and lands on [GcashLaunchResult.unsupported].
  static const String iosScheme = 'gcash://';

  static Future<GcashLaunchResult> open() async {
    if (kIsWeb) return GcashLaunchResult.unsupported;

    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        final intent = AndroidIntent(
          action: 'android.intent.action.MAIN',
          category: 'android.intent.category.LAUNCHER',
          package: androidPackage,
          componentName: androidLauncherActivity,
          flags: const [Flag.FLAG_ACTIVITY_NEW_TASK],
        );
        await intent.launch();
        return GcashLaunchResult.opened;
      } on PlatformException catch (e) {
        debugPrint('[GCASH-LAUNCH] explicit component failed: ${e.code}');
      }

      try {
        // Fallback for a GCash update that renames the splash activity: the
        // package on its own still launches it, at worst after a chooser.
        await AndroidIntent(
          action: 'android.intent.action.MAIN',
          category: 'android.intent.category.LAUNCHER',
          package: androidPackage,
          flags: const [Flag.FLAG_ACTIVITY_NEW_TASK],
        ).launch();
        return GcashLaunchResult.opened;
      } on PlatformException {
        // ACTIVITY_NOT_FOUND — the app is not on this phone.
        return GcashLaunchResult.notInstalled;
      } catch (e) {
        debugPrint('[GCASH-LAUNCH] could not open GCash: $e');
        return GcashLaunchResult.notInstalled;
      }
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      try {
        final uri = Uri.parse(iosScheme);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          return GcashLaunchResult.opened;
        }
      } catch (e) {
        debugPrint('[GCASH-LAUNCH] iOS scheme failed: $e');
      }
      return GcashLaunchResult.unsupported;
    }

    return GcashLaunchResult.unsupported;
  }
}
