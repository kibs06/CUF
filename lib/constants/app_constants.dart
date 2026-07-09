import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppConstants {
  // --- SUPABASE ---
  static const String url = 'https://psczvbfoybqhjeqssimw.supabase.co';
  static const String anonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBzY3p2YmZveWJxaGplcXNzaW13Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODE3NjU2NDIsImV4cCI6MjA5NzM0MTY0Mn0.31zMQ2VbrcMLYBENzozBht5O7PFwV0JDWH1UQ2ba7W8';

  // --- COLOR PALETTE ---
  // Primary – Burnished Clay (aged leather)
  static const Color primary = Color(0xFF8B5A2B);

  // Secondary – Carob Dark (deep sole color, text & icons)
  static const Color secondary = Color(0xFF3B2314);

  // Accent – Celadon Teal (AR mode, CTAs, highlights)
  static const Color accent = Color(0xFF4ECDC4);

  // Surface Light – Off-White Suede
  static const Color surfaceLight = Color(0xFFF5F0EB);

  // Surface Dark – Midnight Canvas (dark mode / AR overlay)
  static const Color surfaceDark = Color(0xFF1A1208);

  // Success – Olive Stitch
  static const Color success = Color(0xFF6B8F47);

  // Error – Crimson Welt
  static const Color error = Color(0xFFD64545);

  // Gray color for borders/dividers
  static const Color borderGray = Color(0xFFD2C7BC);

  // --- BRAND COLOR PARSER ---
  /// Safely parse a hex brand color string (e.g. '#8B5A2B') into a Flutter Color.
  /// Returns [fallback] if the input is null, empty, or malformed.
  static Color parseBrandColor(dynamic brandColor, {Color fallback = const Color(0xFF8B5A2B)}) {
    try {
      if (brandColor == null) return fallback;
      final hex = brandColor.toString().replaceAll('#', '');
      if (hex.length == 6) {
        return Color(int.parse('FF$hex', radix: 16));
      }
      return fallback;
    } catch (_) {
      return fallback;
    }
  }

  // --- SELLER-SPECIFIC COLORS ---
  // Status colors — used heavily on the Seller side
  static const Color statusPendingColor = Color(0xFFF59E0B); // amber
  static const Color statusConfirmedColor = Color(0xFF3B82F6); // blue
  static const Color statusReadyColor = Color(0xFF8B5A2B); // primary (brand)
  static const Color statusDeliveredColor = Color(0xFF6B8F47); // success green
  static const Color statusCancelledColor = Color(0xFFD64545); // error red
  static const Color lowStockColor = Color(0xFFEF4444); // urgent red
  static const Color okStockColor = Color(0xFF6B8F47); // safe green

  // Seller surface — slightly cooler than customer
  static const Color sellerSurface = Color(0xFFF8F9FA);
  static const Color sellerCardBg = Color(0xFFFFFFFF);

  // Neutral shadow for seller cards
  static final List<BoxShadow> sellerShadow = [
    BoxShadow(
      color: Colors.black.withAlpha(15),
      blurRadius: 10,
      offset: const Offset(0, 2),
    ),
  ];

  // --- TYPOGRAPHY ---
  // Headlines - Playfair Display
  static TextStyle headlineStyle({
    double fontSize = 24.0,
    FontWeight fontWeight = FontWeight.bold,
    Color color = secondary,
  }) {
    return GoogleFonts.playfairDisplay(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
    );
  }

  // Body & Labels - DM Sans
  static TextStyle bodyStyle({
    double fontSize = 14.0,
    FontWeight fontWeight = FontWeight.normal,
    Color color = secondary,
    double? height,
    double? letterSpacing,
  }) {
    return GoogleFonts.dmSans(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );
  }

  // Monospace / Codes - JetBrains Mono
  static TextStyle monoStyle({
    double fontSize = 14.0,
    FontWeight fontWeight = FontWeight.normal,
    Color color = secondary,
  }) {
    return GoogleFonts.jetBrainsMono(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
    );
  }

  // --- VISUAL LANGUAGE RULES ---
  static final BorderRadius cardRadius = BorderRadius.circular(16);
  static final BorderRadius buttonRadius = BorderRadius.circular(12);

  // Subtle warm shadow for surfaceLight cards
  static final List<BoxShadow> warmShadow = [
    BoxShadow(
      color: primary.withValues(alpha: 0.08),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
  ];

  // Subtle dark overlay shadow
  static final List<BoxShadow> darkShadow = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.2),
      blurRadius: 8,
      offset: const Offset(0, 2),
    ),
  ];

  // --- APP CONSTANTS & STATUSES ---
  static const String roleCustomer = 'customer';
  static const String roleSeller = 'seller';
  static const String roleAdmin = 'admin';

  static const String statusPlaced = 'placed';
  static const String statusPreparing = 'preparing';
  static const String statusReady = 'ready';
  static const String statusReceived = 'received';

  static const String statusPending = 'pending';
  static const String statusApproved = 'approved';
  static const String statusRejected = 'rejected';

  // --- MOCK NOISE OVERLAY PATTERN PAINT ---
  // Renders a very fine organic-looking noise pattern using CustomPainter
  static Widget noiseOverlay({required double opacity}) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _NoisePainter(opacity: opacity),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _NoisePainter extends CustomPainter {
  final double opacity;
  _NoisePainter({required this.opacity});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppConstants.primary.withValues(alpha: opacity)
      ..style = PaintingStyle.fill;

    // Generate pseudo-random organic speckles for texture.
    // Uses 6px steps to balance visual density (~6.8K dots) with
    // performance (~45K loop iterations vs ~200K at the old 3.5px).
    final rand = _javaRand(42);
    for (double x = 0; x < size.width; x += 6) {
      for (double y = 0; y < size.height; y += 6) {
        if (rand() < 0.08) {
          canvas.drawRect(Rect.fromLTWH(x, y, 1, 1), paint);
        }
      }
    }
  }

  // Simple deterministic pseudo-random generator
  static double Function() _javaRand(int seed) {
    int current = seed;
    return () {
      current = (current * 1103515245 + 12345) & 0x7fffffff;
      return (current / 0x7fffffff);
    };
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
