import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_brightness.dart';
import 'app_palette.dart';
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

  // --- GEOCODING / MAP TILES (proxied — see supabase/functions/geocode-proxy) ---
  // Address search + map tiles go through the geocode-proxy Edge Function
  // so the MapTiler API key never ships inside the app (Threat T6). The
  // proxy holds the key as the MAPTILER_API_KEY server secret and
  // rate-limits per client IP. Call shapes:
  //   GET $geocodeProxyBaseUrl/search?q=<address>      → JSON features
  //   GET $geocodeProxyBaseUrl/tiles/{z}/{x}/{y}.png   → PNG tile bytes
  static const String geocodeProxyBaseUrl =
      'https://psczvbfoybqhjeqssimw.supabase.co/functions/v1/geocode-proxy';

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
  //
  // Two kinds of token live here, and the difference is load-bearing for dark
  // mode (see docs/AI/DARK_MODE_PLAN.md):
  //
  //   • PINNED `const` colours — brand and semantic values that must look the
  //     same in both brightnesses, because they are a fill someone puts ink
  //     on, a status meaning, or the intentionally-dark canvas of the AR and
  //     camera screens. They stay compile-time constants.
  //
  //   • BRIGHTNESS-AWARE getters — surfaces and ink, which resolve through
  //     [AppPalette] against [AppBrightness]. These are getters, not `const`,
  //     so anywhere a `const` expression used one is now a compile error the
  //     analyzer names for you.
  //
  // Primary – Burnished Clay (aged leather). PINNED: it is a fill (buttons,
  // badges, icon tiles) that other colours are drawn on, and the brand should
  // not drift between modes. The *ink* role for clay lives on
  // `AppPalette.primaryInk` for the Phase 3 sweep.
  static const Color primary = Color(0xFF8B5A2B);

  // Secondary – Ink (text, icons, dark chrome fills). BRIGHTNESS-AWARE: this
  // is the default colour of every text style below, so flipping it is what
  // makes ~2,000 text call sites follow the theme.
  static Color get secondary => AppPalette.of(AppBrightness.current).onPage;

  // Accent – Celadon Teal (AR mode, CTAs, highlights)
  static const Color accent = Color(0xFF4ECDC4);

  // Cart – Basket Orange (the shopping-bag glyph in every app bar)
  //
  // A warm orange rather than an ink tone: the bag is the one glyph that
  // floats over BOTH the light page surfaces and dark photographic headers
  // (the product-detail sliver, the home hero, the store hero). The old
  // near-black [secondary] default vanished on those photos.
  static const Color cartIcon = Color(0xFFFC5E03);

  // Surface Light – Page White
  //
  // The app-wide light surface (page backgrounds, sheets, cards, dialogs).
  // `main.dart` maps `colorScheme.surface` here and no screen sets
  // `ThemeData.scaffoldBackgroundColor`, so a plain Scaffold already inherits
  // this tone. Referenced from [SellerTheme.creamBg] so the two can never
  // drift. Was the warm cream #F3E9D8, which read as dingy beside the
  // photographic product imagery.
  //
  // This token is ALSO still used as light-on-dark text; [inkInverse] is the
  // explicit token for that job — see docs/AI/NEUTRAL_THEME_PLAN.md §5.
  static Color get surfaceLight => AppPalette.of(AppBrightness.current).page;

  // Surface Subtle – the light neutral fill.
  //
  // Deliberately NOT pure white: a chip, input, popup row or section band has
  // to stay visible ON a [surfaceLight] page. On the old cream ladder those
  // fills sat lighter than the page (`SellerTheme.card`); with a white page
  // they have to go darker instead — lighter is no longer available.
  static Color get surfaceSubtle => AppPalette.of(AppBrightness.current).subtle;

  // Stage – the backdrop a rendered object stands on.
  //
  // BRIGHTNESS-AWARE, and the only role that follows the *3D viewer* rather than
  // the page: light for a light-mode customer, the renderer's own near-black
  // `#0E0F12` on dark. All three faces of the 3D box read it — `ShoePreviewIdle`
  // (the box while no engine is mounted), `_BoxFace` (the WebView engine's
  // cannot-draw state) and the two engines themselves: the WebView's
  // `ModelViewer.backgroundColor` and the native renderer's
  // `Renderer.ClearOptions.clearColor`, which is handed over the preview channel
  // (`ShoePreviewChannel.setBackground` → `setPreviewBackground` →
  // `ArTryOnView.setBackground`). One token, so a box that cannot draw is the
  // same rectangle as a box that is drawing.
  //
  // ⚠️ The *AR* screen is untouched by this and must stay so: it is a camera
  // feed, it keeps [surfaceDark] in both modes, and the AR view is never sent a
  // stage colour — the preview channel is the only caller.
  static Color get stage => AppPalette.of(AppBrightness.current).stage;

  // Surface Raised – the card / popup tone.
  //
  // The customer-side name for the role [sellerCardBg] serves on the seller
  // side: a card that has to read as *lifted* off the page. On dark the raised
  // tone is LIGHTER than the page, because depth there comes from the tone
  // plus a hairline, not from a shadow ([AppPalette.shadow] is transparent on
  // dark). This is what replaced the hand-written `Colors.white` card fills:
  // white under near-white dark ink paints a bright slab with no text on it.
  static Color get surfaceRaised => AppPalette.of(AppBrightness.current).raised;

  // Unread tint – the wash behind an unread notification row.
  //
  // A role rather than `primary.withValues(alpha: 0.04)`, because a fade tuned
  // for a white page lands on a dark card as nothing at all: the role carries
  // the brightness instead of the call site.
  static Color get unreadTint => AppPalette.of(AppBrightness.current).unreadTint;

  // Grounded band – the bottom navigation bar's default and section bands.
  // Retargeted at [surfaceSubtle] so the two can never drift.
  static Color get creamDeep => AppPalette.of(AppBrightness.current).band;

  // Chrome – the dark bar and control fill (app bars, swipe actions, dark
  // buttons, the search submit button).
  //
  // Deliberately NOT [secondary] any more: that token is the page *ink* and
  // resolves to #F5F5F5 on dark, while the ink drawn on this chrome is pinned
  // light (`Colors.white`, [inkInverse], the cream #F5EDE4). Using the ink
  // token as the fill turned every one of those bars near-white with white
  // text on it — the "text is not visible in dark mode" bug. Light is
  // unchanged (#111111, exactly the value the ink token has on light); on dark
  // it keeps its dark tone so the pinned light ink stays legible.
  static Color get chrome => AppPalette.of(AppBrightness.current).chrome;

  // Surface Dark – Neutral Black (AR overlay, camera screens). PINNED: the
  // screens that use it are dark by design in BOTH brightnesses, so it must
  // never follow the theme. Do not "fix" it during a dark-mode sweep.
  static const Color surfaceDark = Color(0xFF111111);

  // Ink on a FIXED light-ish accent fill — the camel (`#C08552`) and olive
  // (`#556B2F`) tag chips keep their hex in both modes, so ink on them must be
  // pinned too: the brightness-aware [secondary] would put near-white text on
  // camel in dark mode.
  static const Color inkOnLightAccent = Color(0xFF111111);

  // Ink on dark – text and icons sitting on a clay, espresso or black fill.
  //
  // Split out of [surfaceLight] deliberately: that token used to serve as both
  // the page fill AND the light-on-dark ink, because the cream page and the
  // cream ink happened to be the same value. White clears AA on every dark
  // fill the app uses (≈5.9:1 on clay, ≈14:1 on espresso), so nothing changes
  // visually today — but the intent is now explicit, and no future page colour
  // change can silently repaint button labels.
  static const Color inkInverse = SellerTheme.creamText;

  // Success – Olive Stitch
  static const Color success = Color(0xFF6B8F47);

  // Error – Crimson Welt
  static const Color error = Color(0xFFD64545);

  // Neutral hairline for borders/dividers (was the warm #D2C7BC).
  // BRIGHTNESS-AWARE: on a dark page a light hairline vanishes, and on a
  // white page a dark one would.
  static Color get borderGray => AppPalette.of(AppBrightness.current).hairline;

  /// Stronger outline reserved for product card edges.
  static Color get cardEdge => AppPalette.of(AppBrightness.current).cardEdge;

  /// Shared seam between product cards in every two-column grid and rail.
  static const double productGridGutter = 8;

  /// Shared horizontal content margin for product feeds and aligned home chrome.
  static const double feedMargin = 8;

  /// The air the home feed's Workshop Collection opens with.
  ///
  /// Every curated section above it owns its own TRAILING gap
  /// ([ProductGridSection] / [ProductRailSection] end with 16), so a section
  /// that hides itself leaves no residue. The catalog is not one of those
  /// sections — it is the feed's own grid, and it has no trailing gap to hang
  /// its lead off — so without this it opened one trailing gap under the On
  /// Sale section and read as flush against it. This is that lead, and it is a
  /// token rather than a literal so the feed's most important boundary moves
  /// as one number.
  static const double catalogLeadGap = 16;

  // --- BRAND COLOR PARSER ---
  /// Safely parse a hex brand color string (e.g. '#8B5A2B') into a Flutter Color.
  /// Returns [fallback] if the input is null, empty, or malformed.
  static Color parseBrandColor(
    dynamic brandColor, {
    Color fallback = const Color(0xFF8B5A2B),
  }) {
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

  // Seller surface — the shared neutral palette. These are repointed at the
  // SellerTheme tokens so the ENTIRE seller module (every seller screen +
  // seller widget) rethemes consistently without touching each file.
  // Shared customer surfaces that used to reference these (e.g. chat_view)
  // now pin their own values so customer UI is unchanged.
  static Color get sellerSurface => AppPalette.of(AppBrightness.current).page;
  static Color get sellerCardBg => AppPalette.of(AppBrightness.current).raised;

  // Neutral shadow for seller cards — soft espresso-tinted (mockup
  // treatment: 10px blur, 2px y, low opacity) instead of Material elevation.
  // Collapses to nothing on dark (see [AppPalette.shadow]).
  static List<BoxShadow> get sellerShadow => SellerTheme.cardShadow;

  // --- TYPOGRAPHY ---
  // Headlines - Playfair Display
  // The three text helpers keep their signatures and their
  // `color: secondary` *behaviour* without making the default a compile-time
  // constant — `secondary` is brightness-aware now, so it is resolved at call
  // time. `Color?` accepts every existing call unchanged.
  static TextStyle headlineStyle({
    double fontSize = 24.0,
    FontWeight fontWeight = FontWeight.bold,
    Color? color,
  }) {
    return GoogleFonts.playfairDisplay(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color ?? secondary,
    );
  }

  // Body & Labels - DM Sans
  static TextStyle bodyStyle({
    double fontSize = 14.0,
    FontWeight fontWeight = FontWeight.normal,
    Color? color,
    double? height,
    double? letterSpacing,
  }) {
    return GoogleFonts.dmSans(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color ?? secondary,
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
    Color? color,
  }) {
    return GoogleFonts.sora(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color ?? secondary,
    ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
  }

  // --- VISUAL LANGUAGE RULES ---
  static final BorderRadius cardRadius = BorderRadius.circular(16);

  /// The product-card family's corner: the grid card, the rail card, and the
  /// poster cards that share a cell with them ("Based on your size", "See
  /// more", The Workshop Collection).
  ///
  /// Deliberately tighter than [cardRadius]. A feed of photographic tiles reads
  /// as a catalog of goods when the corner hugs the image rather than curling
  /// away from it, and the posters sitting in the same grid have to agree or the
  /// section looks like two designs. It is its own token, not an edit to
  /// [cardRadius], so every other card in the app (auth, seller, sheets,
  /// dialogs) keeps the corner it was designed with — and so this one number
  /// moves the whole family at once.
  static const double productCardCorner = 10;
  static final BorderRadius productCardRadius = BorderRadius.circular(
    productCardCorner,
  );

  /// The radius a product card's image clip takes: the card's own corner less
  /// the 1px hairline, which insets the clip's frame. Without the subtraction
  /// the image's corner pokes past the card's on the top two corners.
  static final BorderRadius productCardImageRadius = BorderRadius.vertical(
    top: Radius.circular(productCardCorner - 1),
  );

  static final BorderRadius buttonRadius = BorderRadius.circular(12);

  // Organic 20px corners for premium cards (role choice, submission card),
  // with the matching 14px inner field radius so inputs sit concentrically
  // inside those cards.
  static final BorderRadius premiumCardRadius = BorderRadius.circular(20);
  static final BorderRadius fieldRadius = BorderRadius.circular(14);

  // Full pill — chips, quantity steppers, small badges, destructive pills.
  static const BorderRadius stadiumRadius = BorderRadius.all(
    Radius.circular(999),
  );

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

  // Subtle warm shadow for surfaceLight cards.
  // Collapses on dark: a warm tint on near-black is invisible, so cards there
  // separate by the raised surface tone + hairline instead (which is why the
  // product cards are hairline-first).
  static List<BoxShadow> get warmShadow => AppBrightness.isDark
      ? const <BoxShadow>[]
      : [
          BoxShadow(
            color: primary.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ];

  // The lift under product cards — the one card family that carries a real
  // drop shadow rather than the 8% warm wash above.
  //
  // The product card and the page behind it are BOTH pure white (see
  // `sole_product_card.dart`): the hairline draws the edge, but across a
  // two-column feed of white-on-white tiles that edge alone reads as printed
  // rather than raised. Depth comes from two layers instead of one — a wide
  // ambient shadow plus a tight contact one — which is what a single
  // 8%-at-12px wash could not do at this card size.
  //
  // The plain poster tiles (`FitCard`: "Based on your size", "See more", "ON
  // SALE" and The Workshop Collection's front) deliberately stay flat: their
  // typography carries the block, and a shadow under them would read as a
  // floating label. The EXCEPTION is The Workshop Collection card itself, which
  // casts this lift so it reads as an object with a second side rather than as
  // printed type on the page (see `workshop_collection_card.dart`) — it is a
  // control that turns over, and depth is what says so.
  //
  // Collapses on dark, like [warmShadow] — see [AppPalette.shadow].
  static List<BoxShadow> get productCardShadow => AppBrightness.isDark
      ? const <BoxShadow>[]
      : [
          BoxShadow(
            color: _cardShadowTint.withValues(alpha: 0.10),
            blurRadius: 16,
            offset: const Offset(0, 6),
            spreadRadius: -4,
          ),
          BoxShadow(
            color: _cardShadowTint.withValues(alpha: 0.05),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ];

  // The same card, pressed: the lift all but disappears and what is left pulls
  // in under the tile, so the card reads as sitting *down* on the page for as
  // long as the finger is on it.
  //
  // Not a second colour and not a flash — the same two-layer construction as
  // [productCardShadow], tightened (offset 6 → 2, blur 16 → 6, spread -4 → -2,
  // and the ambient alpha with them). Same length as the idle list on purpose:
  // `BoxShadow.lerpList` pairs the layers up and cannot interpolate two lists
  // of different lengths, which is what makes the press an interpolation of one
  // shadow rather than a swap. Mirrors [premiumCardShadow] /
  // [premiumCardShadowPressed].
  //
  // Collapses on dark with the rest of them.
  static List<BoxShadow> get productCardShadowPressed => AppBrightness.isDark
      ? const <BoxShadow>[]
      : [
          BoxShadow(
            color: _cardShadowTint.withValues(alpha: 0.07),
            blurRadius: 6,
            offset: const Offset(0, 2),
            spreadRadius: -2,
          ),
          BoxShadow(
            color: _cardShadowTint.withValues(alpha: 0.05),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ];

  /// Every shadow's tint — the espresso of [AppPalette]'s own `shadow`
  /// (`0x148B5A2B`), so each shadow in the app is the same colour at a
  /// different weight rather than a second, unrelated grey.
  static const Color _cardShadowTint = Color(0xFF8B5A2B);

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

  // --- SIZE-AWARE SHOPPING ---
  /// Whether the customer's saved foot size drives browse surfaces.
  ///
  /// On: the home feed shows the "Based on your size" grid, listing only
  /// products that actually stock the customer's size right now (later phases add the
  /// size chip, card badges and the product-page pre-select — see
  /// `docs/AI/SIZE_AWARE_SHOPPING_PLAN.md`).
  ///
  /// Every size surface is ABSENT-SAFE: no size on file, no catalog match, or
  /// a size the catalog cannot honestly compare against renders nothing at
  /// all. So this switch exists only to kill the surfaces wholesale, not to
  /// stage them — unlike `kBestSellersRailEnabled`, nothing here is
  /// half-finished. Same one-const kill-switch shape as that rail.
  static const bool sizeAwareShoppingEnabled = true;

  // --- PRODUCT AUDIENCE (Men's / Women's / Kids') ---
  /// Gates the product-audience feature — the audience rails and chips on the
  /// home feed, the audience listing pages, and audience-aware size-chart
  /// labels.
  ///
  /// **Now ON.** It shipped `false` through P2/P3 of
  /// `docs/AI/PRODUCT_AUDIENCE_PLAN.md` while the surfaces were being built;
  /// it was flipped once the seller form (P1) made audiences settable and the
  /// home entry points existed. Turning it on is safe with an untagged
  /// catalog, and that property is what let it be flipped early: every surface
  /// is data-derived, so with every product still `audience = null` the rails
  /// render nothing, the audience chips render nothing, and
  /// `productSizeChart()` returns the shopper's own scale verbatim — i.e. Home
  /// and every size label are byte-for-byte what they were with it off.
  ///
  /// Flipping it back to `false` is still the whole rollback: no surface is
  /// half-built behind it.
  ///
  /// Everything that reads it: `AudienceSection` (rails),
  /// `ProductProvider.audiencesInCatalog` as surfaced by `HomeHero` (chips),
  /// and `productSizeChart()`'s `audienceEnabled` argument at the product
  /// page. Nothing else reads the audience column.
  static const bool productAudienceEnabled = true;

  // --- VIRTUAL FITTING: V1 FIT VERDICT ---
  /// Gates the **fit verdict card** on product detail — the V1 surface that
  /// reads the customer's saved scan and the product's last spec and answers
  /// "how does this size fit me" without any 3D (`lib/utils/fit_engine.dart`,
  /// `docs/RoadMap/VIRTUAL_FITTING_ROADMAP.md` §V1).
  ///
  /// **OFF by default, and off on purpose.** Three things gate the flip:
  ///
  ///  • the bands and the 2 mm width grade are **workshop defaults nobody has
  ///    measured** (architecture §2.6) — V0.8 tunes them with artisan partners;
  ///  • the spec columns are live but the **catalog is not filled in**: one
  ///    demo spec and nothing measured (roadmap V1.3 is applied; sellers are
  ///    the only thing that can move that number), so the card hides itself on
  ///    nearly every page of today's catalog;
  ///  • V1.7 shadow mode (log the verdict, show nothing) is where accuracy is
  ///    eyeballed against artisan opinion *before* a customer reads it.
  ///
  /// Off means **nothing happens**: no card, and — like every surface behind
  /// this switch — no fetch either, since the card is also what loads the
  /// saved scan's millimetres. Flipping it back to `false` is the whole
  /// rollback: the columns are nullable and no other surface reads the verdict.
  ///
  /// **How it is turned on.** The default is off, and a build opts in with
  /// `flutter build apk --dart-define=VIRTUAL_FIT=true` (the
  /// `arTryOnSpikeEnabled` shape) — one command, no source edit, and no way
  /// for a release build to show the card by accident. Flipping this default
  /// to `true` is how the real rollout happens, once the sample and the
  /// V0.8 workshop say the bands are right.
  ///
  /// Everything that reads it: `FitVerdictCard` (its only mount point is the
  /// product page today; the cart reuse is the same widget).
  static const bool virtualFitEnabled = bool.fromEnvironment('VIRTUAL_FIT');

  /// Gates **shadow mode** — the V1.7 record of what the verdict *would* say,
  /// written to a log and shown to nobody (`lib/utils/fit_shadow.dart`, one
  /// sink in `lib/services/fit_shadow_log.dart`).
  ///
  /// **OFF by default, and this is the switch that collects the evidence for
  /// the one above.** The V1 exit criterion is that the verdict matches an
  /// artisan's opinion on 10 real products; that sample has to exist *before*
  /// a customer reads a verdict, which is why this can be on while
  /// [virtualFitEnabled] is off. Turn it on in a build whose diag log can be
  /// exported, walk (or have a partner walk) real product pages with a saved
  /// scan, and compare `[FIT]` lines with what the artisan says about each
  /// shoe.
  ///
  /// **How it is turned on:** `--dart-define=VIRTUAL_FIT_SHADOW=true`, with the
  /// card's own switch left off — that combination is the whole collection
  /// configuration.
  ///
  /// **What turning it on costs:** the product page reads the saved scan once
  /// per visit for customers who have a foot profile (the same read the card
  /// makes when it is on), and writes one line per distinct outcome to the
  /// diag log. Foot millimetres are personal data; they stay in a local file
  /// the app can share only by explicit user action, and both switches are off
  /// in a shipped build.
  ///
  /// Nothing renders either way — the record is the only output.
  static const bool virtualFitShadowEnabled = bool.fromEnvironment(
    'VIRTUAL_FIT_SHADOW',
  );

  /// Gates the seller's **model upload** — the "3D Model (Optional)" section in
  /// the product form (roadmap V2.2/V2.3: fetch the handover `.glb`, run the
  /// authoring contract over it, publish it to `product_models` + the
  /// `shoe-models` bucket).
  ///
  /// **ON by default since 2026-09-28 — the rollout this switch was waiting
  /// for.** `20260927180000_add_try_on_models.sql` **is applied** on the hosted
  /// project, verified by object rather than by trust: `product_models` has its
  /// 17 columns, its two partial unique indexes, its four policies and its
  /// `updated_at` trigger, and `shoe-models` is a public 8 MiB
  /// `model/gltf-binary` bucket with folder-scoped seller write policies (see
  /// `supabase/MIGRATIONS_LIVE_STATUS.md`). The section used to be hidden
  /// because a shipped build's Upload would have raised "relation does not
  /// exist"; that is no longer the state of the database.
  ///
  /// **How it is turned off:** `--dart-define=SHOE_MODEL_UPLOAD=false`. The kill
  /// switch matters more now than it did: this is the one surface here that
  /// writes to a shared table, so turning it off must restore exactly the
  /// pre-V2.2 product form — and it does, because the section, the link fetch
  /// and the save-path publish are all read through this one constant.
  ///
  /// Off means **nothing happens**: no section, no link fetch, and the save
  /// path never reaches the model upload. Turning it off is the whole rollback
  /// — a published model is inert until V3's renderer reads it (the only caller
  /// of `ShoeModelService` is the V2.6 prefetch), so a draft or stale asset
  /// cannot reach a customer.
  ///
  /// **What is still missing is an asset, not a switch.** The table holds **0
  /// rows**: the only `.glb` in the repo is V0's 29 KB placeholder, and the
  /// partner capture sessions (V2.8/V2.9) have not happened. Turning this on
  /// makes the pipeline *reachable*; nothing makes it *populated* yet.
  static const bool shoeModelUploadEnabled =
      bool.fromEnvironment('SHOE_MODEL_UPLOAD', defaultValue: true);

  /// Gates the **seller's 3D model request** — the "Request a 3D model" row in
  /// the product action sheet, and the admin queue that answers it (roadmap
  /// V2.10, `supabase/migrations/20260928140000_add_shoe_model_requests.sql`).
  ///
  /// **ON by default since 2026-09-29, because the apply it was waiting on
  /// landed.** The paragraph this replaces said the opposite for a good reason:
  /// the row writes through an RPC, so on a database without that migration the
  /// seller would tap it and be told the function does not exist — the failure
  /// V2.2 already learned to avoid by shipping its upload section hidden until
  /// the table was verified.
  ///
  /// That migration is now applied to the live project **and verified by
  /// object** (twelve checks true, zero rows — `MIGRATIONS_LIVE_STATUS.md`), and
  /// the release build has carried this switch on since v1.0.33 through
  /// `RELEASE_DART_DEFINES`. So `false` stopped protecting anybody and started
  /// hiding the row from *every build that passes no dart-defines* — an IDE's
  /// **Android App** run configuration, a bare `flutter run` — while the release
  /// of the same commit had it. A build that disagrees with its own release
  /// about whether a feature exists is the worse of the two failures, and it is
  /// the one this default was causing.
  ///
  /// **Why the feature exists at all:** the upload section next door assumes a
  /// seller who can produce a contract-compliant `.glb`. That is not this
  /// market — V2.7's first real partner asset came from a marketplace and still
  /// needed a normaliser run before it passed. So the pipeline gets a second
  /// door: the seller measures the pair with a ruler, the team does the
  /// modelling.
  ///
  /// **How it is turned off:** `--dart-define=SHOE_MODEL_REQUEST=false`. The
  /// rule this project keeps re-learning (V1.3, V2.1, and the docs that denied
  /// an apply that had already happened) still holds where it came from: an
  /// apply is finished when a `--linked` query says so, not when the SQL Editor
  /// says "Success" — which is exactly what this default was waiting for and
  /// what it now records as done.
  ///
  /// Off means **nothing happens**: no row in the sheet, no admin queue entry
  /// in the dashboard, and `ShoeModelRequestService` is never constructed.
  static const bool shoeModelRequestEnabled =
      bool.fromEnvironment('SHOE_MODEL_REQUEST', defaultValue: true);

  /// Gates the **admin's model upload** — "Upload a 3D model" on a request in
  /// the queue, which fetches a `.glb`, publishes it against the requested
  /// product and closes the ask in one step (roadmap V2.11, the second half of
  /// the V2.10 flow).
  ///
  /// **ON by default since 2026-09-29, with the seller's switch and for the same
  /// reason** (see [shoeModelRequestEnabled]): the apply it was waiting on is
  /// done and verified, and v1.0.33 already shipped it on. It is still the first
  /// surface where an *admin* writes a model row, so the switch keeps its whole
  /// purpose — `--dart-define=ADMIN_MODEL_UPLOAD=false` restores today's
  /// behaviour exactly: the queue can still claim, decline and close-as-done, it
  /// just cannot *make* the model, and the close-as-done dialog says so instead
  /// of offering a button that could not work.
  ///
  /// **[adminModelUploadAllowed] is the constant to read, not this one.** The
  /// action also needs [shoeModelUploadEnabled] — the pipeline's own "this build
  /// may write model rows at all" switch — so a build that killed the seller's
  /// upload does not keep writing models through the admin's door. Both on is
  /// the only combination that shows it.
  ///
  /// **How it is turned off:** `--dart-define=ADMIN_MODEL_UPLOAD=false`, or
  /// `--dart-define=SHOE_MODEL_UPLOAD=false`, which clears it too — the
  /// conjunction in [adminModelUploadAllowed] is what makes the pipeline's own
  /// write switch decisive.
  ///
  /// **No migration of its own, and that is a design fact rather than a
  /// coincidence.** An admin may already insert a `product_models` row and
  /// upload to `shoe-models` — both policies read `public.is_admin()` — and
  /// `validate-shoe-model` resolves an admin caller through `is_admin()` too. So
  /// this is the one phase of the pipeline that needed a screen rather than a
  /// schema.
  ///
  /// Off means **nothing happens**: no action on the card, no sheet, and no
  /// write to either the bucket or the table.
  static const bool adminModelUploadEnabled =
      bool.fromEnvironment('ADMIN_MODEL_UPLOAD', defaultValue: true);

  /// Whether the admin's model upload may be shown at all: **both** this
  /// surface's switch and the pipeline's own write switch.
  ///
  /// One constant rather than the conjunction spelled out at each call site, so
  /// "which flag turns this off?" has exactly one answer to read.
  static const bool adminModelUploadAllowed =
      adminModelUploadEnabled && shoeModelUploadEnabled;

  /// Gates the **try-on model prefetch** — warming the local model cache while
  /// the customer is still reading the product page (roadmap V2.6,
  /// `lib/services/try_on_prefetch.dart`).
  ///
  /// **ON by default since 2026-09-28**, now that `product_models` is live.
  ///
  /// **What that costs, stated plainly, because the renderer is still V3.** The
  /// class cannot degrade the page — every failure is returned, never thrown —
  /// and there is **nothing to download yet**: the table holds 0 rows, so the
  /// live effect on today's catalogue is one extra table read per product page
  /// view, which finds nothing and stops. The day a seller publishes a model,
  /// that read starts warming up to ~5 MB **per product page viewed**, on
  /// whatever connection the customer is on, for a cache nothing reads until V3.
  ///
  /// **The hardening to land before models exist in numbers** is the
  /// `connectivity_plus` guard the service's header names: never pull a model
  /// over cellular. It is a refinement, not a correctness gap — the prefetch is
  /// best-effort and its failure is invisible by design.
  ///
  /// **How it is turned off:** `--dart-define=TRY_ON_PREFETCH=false`. Off means
  /// nothing happens: no model table read, no download, no cache write.
  static const bool tryOnPrefetchEnabled =
      bool.fromEnvironment('TRY_ON_PREFETCH', defaultValue: true);

  /// Gates the **real AR try-on surface** — V3's platform view, the one that
  /// puts an actual `.glb` in the camera feed instead of the placeholder
  /// (`docs/RoadMap/VIRTUAL_FITTING_ROADMAP.md` V3.5/V3.9).
  ///
  /// **OFF by default, and this one is unlike the switches above.** It is not
  /// waiting on a database or on another team: it is waiting on **its own
  /// renderer**, and on the two facts that decide whether one may ship.
  ///
  ///   1. **The renderer route is undecided.** V0.7 measured SceneView + Compose
  ///      at **+27.7 MB on the release APK against a ≤8 MB budget**, so the phase
  ///      it would open into is either "accept the size" or "drive Filament
  ///      directly". V3's `ArTryOnView` is written against one of those.
  ///   2. **No device numbers and no real asset exist.** V0.6's fps/load matrix
  ///      needs a physical ARCore phone (finding F14: at feature level 1 no
  ///      model loads at all on an emulator), and `product_models` holds **0
  ///      rows**, so there is nothing to render even on a device that supports
  ///      it.
  ///
  /// So this switch is the *last* flip of the pipeline, not the next one: what
  /// is behind it today is the renderer-independent core (the phase machine, the
  /// session controller and the capability gate — `lib/providers/try_on/`),
  /// which is deliberately inert and testable without a device.
  ///
  /// **How it is turned on:** `--dart-define=TRY_ON_V3=true` for a device build.
  /// Off means **nothing happens**: no model resolution on the try-on route, no
  /// channel traffic at all, and the try-on entry keeps opening the simulated
  /// screen it opens today (decision D8 — the fallback is a success case, never
  /// a dead end). Flipping it back is the whole rollback.
  static const bool tryOnV3Enabled = bool.fromEnvironment('TRY_ON_V3');

  /// **QA/development seam: let the try-on path render the repo's bundled
  /// block-out.** Default **off**; nothing is constructed and no asset is read
  /// while it is.
  ///
  /// The renderer is unreachable without it. `product_models` is applied and
  /// verified live but holds **0 rows** (V2.8/V2.9 need a partner's exported
  /// shoe), so the capability gate answers `modelMissing` on every product and
  /// the real platform view never gets a model to draw — which is why V3.2 could
  /// only claim "it compiles". With this on, `ShoeModelService` is pointed at
  /// `BundledPlaceholderModelDataSource` (`lib/services/try_on_placeholder_model.dart`),
  /// so resolve → digest verify → `.part` rename → LRU budget → native handover
  /// all run as production code over a bundled `.glb`.
  ///
  /// Two are bundled and the choice is a build one:
  /// `--dart-define=TRY_ON_QA_MODEL=assets/models/qa_partner_shoe_v1.glb` serves
  /// the first real partner asset to pass the authoring contract (1.66 MiB,
  /// 49,954 triangles, three 1024² PBR maps — findings F21/V2.7) instead of the
  /// 29,340 B block-out. That matters because an untextured block-out cannot
  /// exercise texture decoding or fill rate, which is where a mid-range phone
  /// actually differs. An unknown value falls back to the block-out rather than
  /// throwing.
  ///
  /// It is a boundary substitution, not a mock: the only thing that changes is
  /// where the bytes come from. Delete this flag, the service file, the asset and
  /// its `pubspec.yaml` line when V2.9 lands a real model (findings §9's
  /// retirement checklist) — and it must never be on in a build shipped to
  /// customers, because neither bundled file is a product: the block-out is
  /// block geometry and the partner asset is unlicensable marketplace content
  /// whose declared length is an assumption, not a measurement.
  static const bool tryOnPlaceholderModelEnabled =
      bool.fromEnvironment('TRY_ON_PLACEHOLDER_MODEL');

  /// Gates the **3D icon on the product photograph**, and behind it the
  /// full-screen 3D viewer whose section carries the "Try On in AR" button
  /// (`lib/widgets/shoe_preview_3d.dart`,
  /// `lib/screens/customer/shoe_preview_screen.dart`; native side
  /// `ArTryOnView.Mode.PREVIEW`).
  ///
  /// **OFF by default, and off is the whole rollback.** With it off the product
  /// page shows no 3D icon at all: no box, no native preview view, no channel
  /// traffic. With it on, a product with a verified local model gets the icon in
  /// the photo's lower-right corner and a tap opens the viewer; a product with
  /// **no model gets neither**, because the AR button lives inside the section
  /// the viewer mounts rather than on the page itself
  /// (`resolveShoePreview`, `lib/utils/shoe_preview_visibility.dart`).
  ///
  /// ⚠️ **Two things moved on 2026-10-01.** The pinned "Try On in AR" pill came
  /// off the page (the icon replaced it: a full-width bar that asked for a
  /// decision before it offered a look), and the box left the page's scroll for
  /// the full-screen viewer. So with this switch off a product page has **no 3D
  /// entry at all** — the pill used to be the switch-off path, and AR is now
  /// reachable only through the viewer.
  ///
  /// **What it does not need.** Not ARCore, not a camera permission, not an AR
  /// session: the preview is the same Filament renderer with no session created
  /// at all, so it draws on phones that could never install ARCore — a strictly
  /// larger audience than the AR button has had. What it does need is a model
  /// that is **verified and on disk**, which the V2.6 prefetch already provides
  /// (`tryOnPrefetchEnabled`, on by default): the native side is handed a local
  /// path and never does HTTP.
  ///
  /// ⚠️ **It has now been seen to render, on 2026-10-01, and the missing piece was
  /// never this switch.** A GLES 3.2 phone (Redmi 24094RAD4G) drew the sandal at
  /// `FEATURE_LEVEL_2` — the level the engine had never been *asked* for, because
  /// Filament's builder defaults to level 1 and clamps `min(requested, driver)`;
  /// see the newest CHANGELOG entry and `ArTryOnView.createEngineIfNeeded`. So the
  /// framing, the idle spin and the light rig have a device behind them. What still
  /// does **not** is the frame-refusal burst Filament reported on the same run
  /// (`beginFail` in the heartbeat): presenting stalls and recovers, and the owner's
  /// phone has not been re-run since the level fix.
  ///
  /// **The compile-time default stays `off`, and that is about *this* build rather
  /// than about customers.** The release channel passes `SHOE_PREVIEW=true` in
  /// `RELEASE_DART_DEFINES` (measured 2026-10-01 with `gh variable list`), which is
  /// why the owner's shipped 1.0.38 already had the icon and the refusal sentence on
  /// the sandal. Keeping the default off leaves one define — or, for a release, one
  /// variable — as the whole rollback.
  ///
  /// **What the emulator run on 2026-09-29 did settle.** The box mounts, the
  /// handover works, and on a renderer below Filament's `FEATURE_LEVEL_2` the
  /// native side *refuses* the load and reports `renderer_feature_level_unsupported`
  /// — the section then removes itself, so the page shows neither the box nor the
  /// AR button. Without that refusal the same path was a **process abort**
  /// (`SIGSEGV` in `libfilament-jni.so`, finding F22). The unresolved half is
  /// commercial: phones capped at OpenGL ES 3.0 can render no 3D shoe at all
  /// until the material path moves to precompiled `.filamat` files (finding D10).
  ///
  /// **How it is turned off:** `--dart-define=SHOE_PREVIEW=false`, or by clearing
  /// the define from `RELEASE_DART_DEFINES`. A build that passes nothing gets the
  /// default above (off in the code, on in a release).
  static const bool shoePreviewEnabled = bool.fromEnvironment('SHOE_PREVIEW');

  /// Whether the 3D box's refusal line also prints **the measured renderer
  /// facts** underneath the honest sentence.
  ///
  /// **OFF by default, and it is not customer copy.** The sentence a shopper
  /// needs is "3D preview isn't supported on this phone."; this adds a second,
  /// dimmer line with the renderer the device advertises, whether it advertises
  /// cube-map arrays, the backend and Filament's supported/active feature level
  /// — the four facts that decide whether `FEATURE_LEVEL_2` is reachable at all
  /// (`OpenGLContext::resolveFeatureLevel`).
  ///
  /// **Why it has to be on the page rather than in a log.** The phone this was
  /// written for is a Huawei P30 Pro whose developer options are locked behind a
  /// password its previous owner set: no `adb logcat` will ever be read from it,
  /// so `[shoe-preview]` and Filament's own `Feature level:` lines are
  /// unreachable there. The app has to explain itself on screen — the same
  /// conclusion v1.0.35 reached for the prefetch.
  ///
  /// **How it is turned on:** `--dart-define=SHOE_PREVIEW_DIAGNOSTICS=true`.
  static const bool shoePreviewDiagnosticsEnabled =
      bool.fromEnvironment('SHOE_PREVIEW_DIAGNOSTICS');

  /// ⚠️ **QA-only: let the native renderer attempt a glTF load below Filament's
  /// `FEATURE_LEVEL_2` instead of refusing.**
  ///
  /// **OFF by default, and this is the most dangerous switch in this file.** The
  /// refusal it relaxes exists because loading at `FEATURE_LEVEL_1` took the
  /// process down — a `SIGSEGV` inside `libfilament-jni.so`, 126 ms after
  /// `Engine.create()`, on a customer's product page (finding F22) — and it is
  /// not catchable. On a phone this flag was written for, a load may therefore
  /// **kill the app**.
  ///
  /// **What it is for, stated so nobody mistakes it for a feature.** The
  /// level-1 story has never been measured on real hardware: F14's
  /// "nothing loads at level 1" came from one emulator whose GLES is a
  /// translator (F24), and D10 still reads "unverified on real hardware".
  /// Meanwhile nothing in Filament's own ubershader materials marks them
  /// level-2-only (they are built with `matc -a opengl -a vulkan -p mobile` from
  /// `libs/gltfio/materials/*.mat.in`, which declare no feature level). So the
  /// only way to learn whether the cheapest phones in this market can draw a
  /// shoe is to let one try — on a device that is allowed to die, which is what
  /// this flag is for. It is a measurement, not a shipped surface.
  ///
  /// **Two locks.** This define (nothing in the release define file turns it
  /// on), and the native side, which honours the request only in a debuggable
  /// build — a published release APK is not `FLAG_DEBUGGABLE`, so a customer
  /// build ignores it even if the define leaks into one. The build also
  /// announces itself on the product page (`ShoePreviewQaBanner`), so a
  /// screenshot from a QA phone can never be mistaken for a customer's.
  ///
  /// **How it is turned on:** `--dart-define=SHOE_PREVIEW_ALLOW_LEVEL1=true`.
  static const bool shoePreviewAllowLevel1 =
      bool.fromEnvironment('SHOE_PREVIEW_ALLOW_LEVEL1');

  /// ⚠️ **QA-only: bring the engine itself down to `FEATURE_LEVEL_1`** —
  /// `Engine.Builder.featureLevel(FEATURE_LEVEL_1)` when the engine does not
  /// exist yet, `Engine.setActiveFeatureLevel(FEATURE_LEVEL_1)` when it does.
  ///
  /// **It lowers, it never raises.** Filament's builder asserts
  /// `featureLevel <= getSupportedFeatureLevel()`: the ceiling is whatever
  /// `OpenGLContext::resolveFeatureLevel` read off the driver (ES 3.1+ *and* a
  /// cube-map-array extension for level 2), and this flag only takes the engine
  /// *down* to the level a level-2 phone would otherwise never have. On a device
  /// already at level 1 or 0 it is a no-op.
  ///
  /// **Why it exists.** [shoePreviewAllowLevel1] only lifts the refusal — on a
  /// modern phone the guard was never going to fire, so that flag by itself
  /// measures nothing (the box simply draws). This is the other half: it
  /// *manufactures* the phone class the guard was written for, so the level-1
  /// path can be exercised on hardware that is sitting right here instead of on
  /// the one device that cannot be read (D10: "unverified on real hardware").
  /// The two are meant to be used together when the question is "can a level-1
  /// renderer draw a shoe?", and alone when it is "what does a level-1 renderer
  /// tell a customer?" — on its own this one produces the refusal, because a
  /// level-1 engine fails the same `canLoadModels()` the owner's phone failed.
  ///
  /// **The pair is the point, and it is why the readout prints both.** With
  /// `SHOE_PREVIEW_DIAGNOSTICS` on, the refusal line reads
  /// `… supported=FEATURE_LEVEL_2 active=FEATURE_LEVEL_1`, which is the same
  /// shape as the P30 Pro's `supported=FEATURE_LEVEL_1` — a *lowered* engine and
  /// a *capped* one have to be distinguishable in a screenshot, and only the
  /// `supported=` half can do that.
  ///
  /// **Two locks**, the same two as the load override: this define (never on in
  /// the release define file), and the native side, which honours the request
  /// only in a debuggable build. A published release APK is not
  /// `FLAG_DEBUGGABLE`, so a customer build ignores it even if the define leaks
  /// into one. ⚠️ **Not to be confused with [shoePreviewAllowLevel1]:** that one
  /// lets a load happen, this one changes the renderer; neither is a customer
  /// surface, and the build announces both on the page
  /// (`ShoePreviewQaBanner`).
  ///
  /// **How it is turned on:** `--dart-define=SHOE_PREVIEW_LOWER_ENGINE_TO_LEVEL1=true`.
  static const bool shoePreviewLowerEngineToLevel1 =
      bool.fromEnvironment('SHOE_PREVIEW_LOWER_ENGINE_TO_LEVEL1');

  /// **Which engine draws the 3D box: the native Filament view, or a WebView.**
  ///
  /// `false` (the default) mounts `ArTryOnView` — the Filament platform view the
  /// whole feature was built on. `true` mounts a `WebViewWidget` running Google's
  /// `<model-viewer>` web component instead, against the **same verified `.glb`
  /// on disk**. Nothing else about the feature moves: the gate, the prefetch, the
  /// two channel sets, the AR pill and the photo fallback are all unchanged.
  ///
  /// **Why a second engine exists at all, stated as the measurement that asked
  /// for it.** Six rounds of device work on the owner's Huawei P30 Pro produced a
  /// renderer that *draws* the shoe at `FEATURE_LEVEL_2` and ~57 fps — and then
  /// stops returning from two specific native calls, on two specific paths:
  /// `TransformManager.setTransform` on the load tail (2 of 5 launches) and
  /// `AssetLoader.destroyAsset` on a **second** teardown in one process (2 of 2
  /// re-opens). Neither is catchable and neither is a crash: the call simply never
  /// comes back, and the process dies behind it. Both live in the vendor GL
  /// driver, reached through Filament's JNI.
  ///
  /// A WebView changes that failure's *shape* rather than its probability. The
  /// renderer runs in Chromium's own process, on its own driver calls, behind a
  /// sandbox; when it stalls or dies the app is still standing and the box is
  /// merely blank — which is a state this feature already knows how to be honest
  /// about (`ShoePreviewHint`). That is the whole argument for this switch, and it
  /// is an argument about **blast radius, not about picture quality**.
  ///
  /// **What it buys beyond that, and it is not nothing.** `<model-viewer>` needs
  /// no ARCore and no `FEATURE_LEVEL_2`, so it draws on the OpenGL ES 3.0 phones
  /// that Filament provably cannot (`canLoadModels()`, finding D10) — a strictly
  /// larger audience than the native engine has ever had. Its gestures (drag,
  /// pinch, momentum) are Chromium's rather than ours, which is the same code path
  /// every e-commerce site on the internet already ships.
  ///
  /// **What it costs, so this is a trade and not a free win.** The model is
  /// served to the WebView over a **loopback-only** HTTP server the package binds
  /// (`HttpServer.bind(InternetAddress.loopbackIPv4, 0)`) — the bytes never leave
  /// the device and never touch the network, but it does mean the app must permit
  /// cleartext to `127.0.0.1`, which is why `android/app/src/main/res/xml/
  /// network_security_config.xml` exists. It also needs a WebView that can run
  /// WebGL2 (any Chromium since 2017; the P30 Pro has GMS, so its WebView is
  /// Play-updatable), and the box is a second rendering surface rather than the
  /// app's own frame.
  ///
  /// **⚠️ The default is now `true`, and a device measurement is why.** On a vivo
  /// V2022 (Android 12, Adreno — a different GPU vendor from the P30 Pro's Mali),
  /// the native engine **killed the app on 2 of 3 attempts** to open the 3D box,
  /// every death at `load: entities added — applying the transform` with a
  /// `SIGSEGV` in `TransformManager_nSetTransform+64`; the third survived and
  /// reported the frozen-frame burst, which is the P30 Pro's *"it loads but I
  /// cannot touch it"* symptom on a second vendor. The WebView engine on the same
  /// phone, same model: **five opens in one process, zero crashes, zero errors**, a
  /// correct `396x520` canvas every time, and a drag that turns the shoe. The
  /// default follows the engine that has a device behind it — not the one that was
  /// written first.
  ///
  /// **⚠️ This is still additive, and the native engine is not being deleted.**
  /// Both engines stay compiled in and the switch picks one, so the rollback from
  /// a shipped build is one define — the same rule §9 of
  /// `docs/AI/PRODUCT_3D_VIEW_ARCHITECTURE.md` states for every other switch here.
  /// The native path keeps its QA instrumentation and its tests either way, and
  /// **AR is untouched**: `Mode.AR` needs a GL surface and ARCore, so the WebView
  /// engine cannot draw it and the native view still does.
  ///
  /// **How it is turned off:** `--dart-define=SHOE_PREVIEW_WEBVIEW=false`, which
  /// puts the Filament platform view back.
  static const bool shoePreviewWebViewEnabled =
      bool.fromEnvironment('SHOE_PREVIEW_WEBVIEW', defaultValue: true);

  // --- VIRTUAL FITTING: V0 RENDERER SPIKE (dev-only, delete on retirement) ---
  /// Gates the V0 virtual-fitting renderer spike — a dev-only screen that
  /// renders a placeholder GLB in AR through the native SceneView integration
  /// (`com.solevision.app.artryon`), behind a platform view.
  ///
  /// **OFF by default.** Enable with
  /// `flutter run --dart-define=AR_TRY_ON_SPIKE=true`; when off, the entry
  /// point in `ARVirtualFitScreen` renders nothing and no native view is
  /// created. It exists to answer the V0 questions in
  /// `docs/RoadMap/VIRTUAL_FITTING_ROADMAP.md` — frame rate, model load time,
  /// APK size delta — with the results recorded in
  /// `docs/RoadMap/AR_TRY_ON_SPIKE_FINDINGS.md`.
  ///
  /// Not a product surface: no size or colour selection, no fit verdict, no
  /// add-to-cart. Those stay in the simulated try-on until V3.
  static const bool arTryOnSpikeEnabled = bool.fromEnvironment('AR_TRY_ON_SPIKE');

  /// Whether the customer actually has a foot size on file — the signal the
  /// home reminder banner keys off ("only show it when they haven't set a
  /// size"). TWO independent markers count as set:
  ///
  ///   • the onboarding source (`ar_scan` / `manual`), and
  ///   • a stored EU size (`profiles.foot_size_ph`).
  ///
  /// `AuthProvider.saveFootProfile` writes both together, but its snapshot
  /// write is best-effort — a failed write (offline) or a size stored by a
  /// build that predates the source column can leave only ONE of them
  /// behind. Either signal still means the customer has a size, so the
  /// banner must stay out of the way rather than nag them again.
  static bool hasFootSize(Map<String, dynamic>? profile) {
    if (profile == null) return false;
    if (!needsFootProfile(profile['foot_profile_source'])) return true;

    final size = profile['foot_size_ph'];
    if (size == null) return false;
    if (size is num) return true;
    return size.toString().trim().isNotEmpty;
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
