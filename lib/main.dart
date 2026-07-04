import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'constants/app_constants.dart';
import 'providers/auth_provider.dart';
import 'providers/product_provider.dart';
import 'providers/cart_provider.dart';
import 'providers/order_provider.dart';
import 'providers/notification_provider.dart';
import 'screens/auth/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Global Flutter error handler — prevents black screen on crash
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('Flutter error: ${details.exception}');
  };

  // Global async/platform error handler
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Platform error: $error');
    return true;
  };

  await Supabase.initialize(
    url: AppConstants.url,
    anonKey: AppConstants.anonKey,
  );

  runApp(const SoleVisionApp());
}

class SoleVisionApp extends StatelessWidget {
  const SoleVisionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ProductProvider()),
        ChangeNotifierProvider(create: (_) => CartProvider()),
        ChangeNotifierProvider(create: (_) => OrderProvider()),
        ChangeNotifierProvider(create: (_) => NotificationProvider()),
      ],
      child: MaterialApp(
        title: 'SoleVision',
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
          return child ?? const SizedBox.shrink();
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
        home: const SplashScreen(),
      ),
    );
  }
}
