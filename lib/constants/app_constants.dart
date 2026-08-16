import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'seller_theme_constants.dart';

class AppConstants {
  // --- SUPABASE ---
  static const String url = 'https://psczvbfoybqhjeqssimw.supabase.co';
  static const String publishableKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBzY3p2YmZveWJxaGplcXNzaW13Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODE3NjU2NDIsImV4cCI6MjA5NzM0MTY0Mn0.31zMQ2VbrcMLYBENzozBht5O7PFwV0JDWH1UQ2ba7W8';

  // --- PRODUCT SHARING (rich link previews) ---
  // Server-rendered Open Graph endpoint (Supabase Edge Function
  // `product-preview`, see supabase/functions/product-preview/index.ts).
  // WhatsApp / Messenger / Facebook fetch this URL and read its meta tags
  // to render a Shopee/Lazada-style preview card when a product is shared.
  // When a custom domain is added later, point this at https://<domain>/p
  // and update docs/AI/SHARE_PRODUCT_ARCHITECTURE.md + DeepLinkService.
  static const String productShareBaseUrl =
      'https://psczvbfoybqhjeqssimw.supabase.co/functions/v1/product-preview';

  /// Shareable URL for a product (triggers the OG rich preview).
  static String productShareUrl(String productId) =>
      '$productShareBaseUrl/$productId';

  // --- MAPTILER ---
  static const String maptilerKey = 'ZsHghTkRWCoZDpjMxUir';

  // --- UPDATE CHECKER (self-hosted) ---
  // Hosted release manifest + changelog for the DIY in-app update checker.
  // Served from the public GitHub repo `kibs06/CUF` via raw.githubusercontent
  // (see README → "In-app update checker" for the JSON shape and release
  // checklist). Commit updated releases/version.json + releases/changelog.json
  // to that repo's `main` branch to publish a new build.
  static const String updateManifestUrl =
      'https://raw.githubusercontent.com/kibs06/CUF/main/releases/version.json';
  static const String updateChangelogUrl =
      'https://raw.githubusercontent.com/kibs06/CUF/main/releases/changelog.json';

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

  // Seller surface — espresso/cream palette. These are repointed at the
  // SellerTheme tokens so the ENTIRE seller module (every seller screen +
  // seller widget) rethemes consistently without touching each file.
  // Shared customer surfaces that used to reference these (e.g. chat_view)
  // now pin their own values so customer UI is unchanged.
  static const Color sellerSurface = SellerTheme.creamBg;
  static const Color sellerCardBg = SellerTheme.card;

  // Neutral shadow for seller cards — soft espresso-tinted (mockup
  // treatment: 10px blur, 2px y, low opacity) instead of Material elevation.
  static final List<BoxShadow> sellerShadow = SellerTheme.cardShadow;

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

  // Numbers & figures - Sora (modern geometric sans). Drives every numeric
  // display app-wide: prices, totals, counts, sizes, measurements, refs.
  // Tabular figures keep price/amount columns aligned in receipts & POS.
  static TextStyle monoStyle({
    double fontSize = 14.0,
    FontWeight fontWeight = FontWeight.normal,
    Color color = secondary,
  }) {
    return GoogleFonts.sora(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
    ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
  }

  // --- VISUAL LANGUAGE RULES ---
  static final BorderRadius cardRadius = BorderRadius.circular(16);
  static final BorderRadius buttonRadius = BorderRadius.circular(12);

  // Organic 20px corners for premium cards (role choice, submission card),
  // with the matching 14px inner field radius so inputs sit concentrically
  // inside those cards.
  static final BorderRadius premiumCardRadius = BorderRadius.circular(20);
  static final BorderRadius fieldRadius = BorderRadius.circular(14);

  // Full pill — chips, quantity steppers, small badges, destructive pills.
  static const BorderRadius stadiumRadius = BorderRadius.all(Radius.circular(999));

  // Premium card treatment (role-choice cards, submission card) — ambient
  // clay shadow instead of a 1px border: high blur, low opacity, and a
  // negative spread so the glow hugs the card's organic 20px corners.
  static final List<BoxShadow> premiumCardShadow = [
    BoxShadow(
      color: primary.withValues(alpha: 0.08),
      blurRadius: 32,
      offset: const Offset(0, 12),
      spreadRadius: -4,
    ),
  ];

  // Pressed state of the premium cards — tighter, deeper shadow that reads
  // as physical depth while the card scales down.
  static final List<BoxShadow> premiumCardShadowPressed = [
    BoxShadow(
      color: primary.withValues(alpha: 0.10),
      blurRadius: 16,
      offset: const Offset(0, 6),
      spreadRadius: -2,
    ),
  ];

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

  // --- ORDER CANCELLATION CONFIG ---
  /// Maximum time (in hours) after entering 'preparing' status
  /// during which the customer can request cancellation.
  static const int processingCancelWindowHours = 2;

  /// Upper-bound alternate for the processing cancellation window.
  static const int processingCancelWindowMaxHours = 5;

  // --- ORDER CANCELLATION REASONS ---
  static const List<String> cancellationReasons = [
    'Changed my mind',
    'Found a better price or deal elsewhere',
    'Ordered by mistake (wrong item, size, color, or quantity)',
    'Need to change delivery address',
    'Want to modify the order (variant, quantity, voucher, etc.)',
    'Shipping/processing is taking too long',
    'Seller is not responding to my inquiries',
    'Payment issue or want to change payment method',
    'Other',
  ];

  // --- PRODUCT CATEGORIES (canonical) ---
  /// Canonical product categories, the single source of truth used by BOTH
  /// the seller product form (category chip selector) and the customer home
  /// category filter, so the two can never drift. Categories saved on
  /// products that aren't in this list (legacy 'Other' values, older free
  /// text, future presets) are still surfaced by the customer filter — the
  /// provider unions this list with whatever categories actually exist on
  /// products.
  static const List<String> productCategories = [
    'Casual',
    'Formal',
    'Sports',
    'Sandals',
    'Boots',
    'Sneakers',
    'Slip-ons',
    'Custom',
  ];

  // --- APP CONSTANTS & STATUSES ---
  static const String roleCustomer = 'customer';
  static const String roleSeller = 'seller';
  static const String roleAdmin = 'admin';

  static const String statusPlaced = 'placed';
  static const String statusPreparing = 'preparing';
  static const String statusReady = 'ready';
  static const String statusReceived = 'received';
  static const String statusCancellationRequested = 'cancellation_requested';

  static const String statusPending = 'pending';
  static const String statusApproved = 'approved';
  static const String statusRejected = 'rejected';

  // --- TIER 2 BUSINESS VERIFICATION (optional, decoupled from approval) ---
  // seller_business_docs.verification_status values.
  static const String bizStatusNone = 'none';
  static const String bizStatusPending = 'pending';
  static const String bizStatusVerified = 'verified';
  static const String bizStatusRejected = 'rejected';

  // --- SELLER IDENTITY — GOVERNMENT ID TYPES (Tier 1 profile field) ---
  /// Valid Philippine government-issued IDs accepted for seller identity
  /// verification (all carry the holder's full name + photo). The `value`
  /// is what gets stored in `profiles.id_type`; `label` is the human-facing
  /// name shown in the application flow and admin review.
  static const List<GovIdType> govIdTypes = [
    GovIdType('philid', 'PhilSys National ID (PhilID / ePhilID)'),
    GovIdType('passport', 'Philippine Passport'),
    GovIdType('drivers_license', "Driver's License (LTO)"),
    GovIdType('umid', 'UMID / SSS Digitized ID'),
    GovIdType('gsis', 'GSIS eCard'),
    GovIdType('prc', 'PRC ID'),
    GovIdType('postal', 'Postal ID (PhilPost)'),
    GovIdType('voters', "Voter's ID (COMELEC)"),
    GovIdType('senior', 'Senior Citizen ID (OSCA)'),
    GovIdType('pwd', 'PWD ID'),
    GovIdType('tin', 'TIN ID (BIR)'),
    GovIdType('nbi', 'NBI Clearance'),
  ];

  /// Human label for a stored [GovIdType.value], or an empty string when
  /// the value is null/unknown (legacy applications have no ID type).
  static String govIdTypeLabel(String? value) {
    if (value == null) return '';
    for (final type in govIdTypes) {
      if (type.value == value) return type.label;
    }
    return value;
  }

  // --- CUSTOMER SIGN-UP PROFILE FIELDS ---
  /// Gender options offered at customer signup (optional field).
  /// 'Self-describe' reveals a free-text field rather than hardcoding a
  /// closed set — see lib/utils/customer_profile_fields.dart for the
  /// validator that guards it.
  static const List<String> customerGenderOptions = [
    'Woman',
    'Man',
    'Prefer not to say',
    'Self-describe',
  ];

  /// Minimum acceptable age for customer sign-up (COPPA-style).
  /// Enforced by [validateBirthday] in lib/utils/customer_profile_fields.dart.
  static const int minimumSignupAgeYears = 13;

  /// Width options for the manual foot-profile entry (the lightweight
  /// fallback to the AR scan). Stored verbatim in profiles.foot_width.
  static const List<String> footWidthOptions = ['Narrow', 'Regular', 'Wide'];

  // --- FOOT PROFILE SNAPSHOT (profiles columns, see migration
  // 20260812130000_add_customer_profile_fields.sql) ---
  // foot_profile_source values — the rest of the app (checkout, size
  // recommendations, the reminder banner) uses these to grade confidence.
  static const String footProfileArScan = 'ar_scan';
  static const String footProfileManual = 'manual';
  static const String footProfileSkipped = 'skipped';

  /// Whether a customer has a usable foot profile (i.e. the reminder banner
  /// should show). NULL (pre-feature accounts) counts as missing — 'skip'
  /// must never mean "never ask again silently".
  static bool needsFootProfile(dynamic source) {
    final s = source?.toString();
    return s == null || s.isEmpty || s == footProfileSkipped;
  }

  // --- PRIVATE VERIFICATION STORAGE ---
  /// Private bucket for ID photos, selfies, barangay proofs and Tier 2
  /// business docs. Owner-only + admin read (see migration
  /// 20260812000000_add_seller_tiered_verification.sql). Never public.
  static const String verificationDocsBucket = 'seller-verification-docs';

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

/// A valid Philippine government-issued ID accepted for seller identity
/// verification. See `AppConstants.govIdTypes` for the full list.
class GovIdType {
  /// Stable value stored in `profiles.id_type` (never change after release —
  /// legacy rows reference it).
  final String value;

  /// Human-facing label shown in the application flow and admin review.
  final String label;

  const GovIdType(this.value, this.label);
}
