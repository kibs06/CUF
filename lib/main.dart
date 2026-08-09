import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'constants/app_constants.dart';
import 'providers/auth_provider.dart';
import 'providers/product_provider.dart';
import 'providers/cart_provider.dart';
import 'providers/order_provider.dart';
import 'providers/address_provider.dart';
import 'providers/notification_provider.dart';
import 'providers/seller_notification_provider.dart';
import 'providers/message_provider.dart';
import 'providers/chat_attachment_provider.dart';
import 'providers/follow_provider.dart';
import 'providers/review_provider.dart';
import 'providers/foot_measurement_provider.dart';
import 'providers/update_provider.dart';
import 'providers/sale_tag_provider.dart';
import 'services/store_service.dart';
import 'screens/auth/splash_screen.dart';
import 'screens/customer/gcash_payment_screen.dart';
import 'services/connectivity_service.dart';
import 'services/deep_link_service.dart';
import 'services/gcash_payment_service.dart';
import 'services/push_notification_service.dart';
import 'widgets/connectivity_banner.dart';

/// Root navigator key — lets the deep-link handler push the GCash
/// payment screen even from a cold start (before any screen is open).
final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

/// Top-level background message handler for Firebase Cloud Messaging.
/// Required by firebase_messaging — must be a top-level function, not a method.
/// Handles messages when the app is fully terminated.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Background handlers run in a separate isolate — no UI access.
  // Just log for debugging. The actual notification is handled by the OS.
  if (kDebugMode) {
    debugPrint('[Push] Background message: ${message.messageId}');
    debugPrint('[Push] Data: ${message.data}');
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Allow google_fonts to fetch fonts at runtime if not bundled locally.
  // This ensures fonts load correctly even if assets are missing.
  GoogleFonts.config.allowRuntimeFetching = true;

  // Global Flutter error handler — prevents black screen on crash
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    if (kDebugMode) debugPrint('Flutter error: ${details.exception}');
  };

  // Global async/platform error handler
  PlatformDispatcher.instance.onError = (error, stack) {
    if (kDebugMode) debugPrint('Platform error: $error');
    return true;
  };

  // Initialize Supabase — with a timeout to prevent indefinite hang.
  // If this fails or times out, show an error screen instead of a black screen.
  bool supabaseReady = false;
  try {
    await Supabase.initialize(
      url: AppConstants.url,
      publishableKey: AppConstants.publishableKey,
    ).timeout(const Duration(seconds: 10));
    supabaseReady = true;
  } catch (e) {
    if (kDebugMode) debugPrint('Supabase init failed: $e');
  }
  if (supabaseReady) {
    // Start the connectivity service after Supabase is ready
    ConnectivityService.instance.start();

    // Initialize Firebase for push notifications
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      // Register background message handler (must be called before runApp)
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
      // Initialize push notification service (after Firebase is ready)
      PushNotificationService.instance.init();
    } catch (e) {
      if (kDebugMode) debugPrint('Firebase init failed (push notifications disabled): $e');
    }

    runApp(const CUFMAIApp());
  } else {
    runApp(_SupabaseErrorApp());
  }
}

class CUFMAIApp extends StatelessWidget {
  const CUFMAIApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ProductProvider()),
        ChangeNotifierProvider(create: (_) => CartProvider()),
        ChangeNotifierProvider(create: (_) => OrderProvider()),
        ChangeNotifierProvider(create: (_) => AddressProvider()),
        ChangeNotifierProvider(create: (_) => NotificationProvider()),
        ChangeNotifierProvider(create: (_) => SellerNotificationProvider()),
        ChangeNotifierProvider(create: (_) => MessageProvider()),
        ChangeNotifierProvider(create: (_) => ChatAttachmentProvider()),
        ChangeNotifierProvider(create: (_) => FollowProvider(StoreService.instance)),
        ChangeNotifierProvider(create: (_) => ReviewProvider()),
        ChangeNotifierProvider(create: (_) => FootMeasurementProvider()),
        ChangeNotifierProvider(create: (_) => UpdateProvider()),
        ChangeNotifierProvider(create: (_) => SaleTagProvider()),
      ],
      child: MaterialApp(
        title: 'CUFMAI',
        debugShowCheckedModeBanner: false,
        builder: (context, child) {
          ErrorWidget.builder = (FlutterErrorDetails details) {
            return Scaffold(
              backgroundColor: AppConstants.surfaceLight,
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Something went wrong:\n${details.exceptionAsString()}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppConstants.error),
                  ),
                ),
              ),
            );
          };
          // Wrap with ConnectivityBanner for mid-session connection loss
          return ConnectivityBanner(child: child ?? const SizedBox.shrink());
        },
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: const ColorScheme(
            brightness: Brightness.light,
            primary: AppConstants.primary,
            onPrimary: AppConstants.surfaceLight,
            secondary: AppConstants.secondary,
            onSecondary: AppConstants.surfaceLight,
            error: AppConstants.error,
            onError: AppConstants.surfaceLight,
            surface: AppConstants.surfaceLight,
            onSurface: AppConstants.secondary,
          ),

          // Apply custom font themes globally
         textTheme: GoogleFonts.dmSansTextTheme(ThemeData.light().textTheme)
              .copyWith(
                displayLarge: GoogleFonts.playfairDisplay(
                  color: AppConstants.secondary,
                ),
                displayMedium: GoogleFonts.playfairDisplay(
                  color: AppConstants.secondary,
                ),
                displaySmall: GoogleFonts.playfairDisplay(
                  color: AppConstants.secondary,
                ),
                headlineLarge: GoogleFonts.playfairDisplay(
                  color: AppConstants.secondary,
                ),
                headlineMedium: GoogleFonts.playfairDisplay(
                  color: AppConstants.secondary,
                ),
                headlineSmall: GoogleFonts.playfairDisplay(
                  color: AppConstants.secondary,
                ),
              ),

          // Switch theme styles
          switchTheme: SwitchThemeData(
            thumbColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return AppConstants.surfaceLight;
              }
              return AppConstants.primary.withValues(alpha: 0.5);
            }),
            trackColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return AppConstants.primary;
              }
              return AppConstants.borderGray.withValues(alpha: 0.3);
            }),
          ),

          // Dialog styles
          dialogTheme: DialogThemeData(
            backgroundColor: AppConstants.surfaceLight,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),

        // Start screen is Splash, which auto-navigates to AuthGate
        home: const DeepLinkHost(child: SplashScreen()),
        navigatorKey: _navigatorKey,
      ),
    );
  }
}

/// Wraps the app so `solvision://checkout/gcash/*` deep links are heard
/// even when the app is launched cold from the GCash redirect.
///
/// The link is INFORMATIONAL ONLY: it never marks a payment paid. It
/// merely resumes the pending checkout's payment screen (which polls the
/// authoritative server status). Warm returns are skipped here — the
/// already-open GcashPaymentScreen handles those with its own poll.
class DeepLinkHost extends StatefulWidget {
  final Widget child;

  const DeepLinkHost({super.key, required this.child});

  @override
  State<DeepLinkHost> createState() => _DeepLinkHostState();
}

class _DeepLinkHostState extends State<DeepLinkHost> {
  @override
  void initState() {
    super.initState();
    DeepLinkService.instance.init(onLink: _onLink);
  }

  @override
  void dispose() {
    DeepLinkService.instance.dispose();
    super.dispose();
  }

  Future<void> _onLink(Uri uri) async {
    if (!DeepLinkService.isGcashReturn(uri)) return;
    // Warm return: the payment screen is open and polling — skip.
    if (GcashPaymentScreen.isOpen) return;

    // Cold start: auth may still be restoring — wait briefly, then resume
    // the customer's pending checkout if one exists.
    for (var attempt = 0; attempt < 30; attempt++) {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid != null) {
        final intent = await GcashPaymentService().fetchPendingIntent();
        if (intent != null && intent.checkoutUrl.isNotEmpty && mounted) {
          _navigatorKey.currentState?.push(
            MaterialPageRoute(
              builder: (_) => GcashPaymentScreen(intent: intent),
            ),
          );
        }
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Fallback app shown when Supabase fails to initialize.
/// Prevents a black screen by showing a clear error with retry.
class _SupabaseErrorApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CUFMAI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppConstants.primary,
          brightness: Brightness.light,
        ),
      ),
      home: Scaffold(
        backgroundColor: AppConstants.surfaceLight,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppConstants.error.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.cloud_off_rounded,
                    size: 32,
                    color: AppConstants.error,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Unable to connect',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppConstants.secondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'CUFMAI could not reach its servers.\nPlease check your internet connection and try again.',
                  style: GoogleFonts.dmSans(
                    fontSize: 14,
                    color: AppConstants.secondary.withValues(alpha: 0.6),
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: () {
                    // Re-launch the app — restarts main()
                    main();
                  },
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Retry'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppConstants.primary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
