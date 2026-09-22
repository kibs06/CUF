import 'package:flutter/material.dart';

import 'app_brightness.dart';
import 'app_palette.dart';

/// Neutral white/gray palette for the seller dashboard — the same surface
/// language the customer, admin and auth sides now share, so the whole app
/// reads as one designed surface. The brand browns below are kept for
/// accents and data only, never as page or card fills. Styling only — no
/// logic lives here.
///
/// Usage: reference `SellerTheme.*` from dashboard widgets; never hardcode
/// these hex values inline in widget files.
class SellerTheme {
  SellerTheme._();

  // ── Espresso ────────────────────────────────────────────────────
  /// Darkest brand brown — solid fills (GCash icon tile, View Details).
  /// The AppBar uses `AppConstants.secondary` (#3B2314), which is visually
  /// indistinguishable from this; it is kept as-is rather than duplicated.
  static const Color espressoDark = Color(0xFF3A2415);

  /// Mid espresso — secondary accents, "This Week" sparkline stroke.
  static const Color espressoMid = Color(0xFF6B4A32);

  // ── Rust ────────────────────────────────────────────────────────
  /// Primary data accent — today's sales figure, sparklines, status dots,
  /// "View all" links, GCash chevron.
  static const Color rust = Color(0xFFB5622E);

  /// Darker rust — active/pressed states, "Ready" number text.
  static const Color rustDeep = Color(0xFF9C4E22);

  // ── Revenue channels ────────────────────────────────────────────
  //
  // The two channels every revenue visual splits into. They live here rather
  // than on whichever chart happened to be drawn first, because "online is the
  // rust one" is a fact the trend columns and the doughnut both have to agree
  // on — the same month must be the same colour in both cards. Aliases, not new
  // hexes: these are the brand browns above, wearing their data role.

  /// Online orders — the primary data accent.
  static const Color channelOnline = rust;

  /// POS / in-store sales — the second series, mid espresso.
  static const Color channelInStore = espressoMid;

  // ── Sage ────────────────────────────────────────────────────────
  /// Low-stock-OK state, "Received" status.
  static const Color sage = Color(0xFF5B7B52);
  static const Color sageBg = Color(0xFFE7EDE2);
  static const Color sageDark = Color(0xFF3E5836); // text on sageBg

  // ── Amber ───────────────────────────────────────────────────────
  /// "Placed" status, pending pill text.
  static const Color amber = Color(0xFFC98A2C);
  static const Color amberBg = Color(0xFFF4E6C8);
  static const Color amberDark = Color(0xFF8A5D14); // text on amberBg

  // ── Blue (Preparing status only — kept neutral on purpose) ─────
  static const Color blue = Color(0xFF5C7A9E);
  static const Color blueBg = Color(0xFFE1E9F0);

  // ── Neutral surfaces ────────────────────────────────────────────
  //
  // These four are BRIGHTNESS-AWARE (getters over [AppPalette]), because a
  // surface that is white in one mode and near-black in the other cannot be a
  // compile-time constant. The brand and status colours above stay `const`:
  // they are semantic, not surfaces. See docs/AI/DARK_MODE_PLAN.md.
  /// Screen background.
  static Color get creamBg => AppPalette.of(AppBrightness.current).page;

  /// Card surface. On light it is the same white as the page on purpose:
  /// cards are separated by their [cardBorder] hairline rather than by a fill,
  /// so a card can never look dirty against the page it sits on. On dark the
  /// relationship inverts — the card is *lighter* than the page, because that
  /// is what reads as raised when shadows are unavailable.
  static Color get card => AppPalette.of(AppBrightness.current).raised;

  /// Hero card gradient end — a subtle neutral wash off the card white.
  static Color get cardHeroEnd => AppPalette.of(AppBrightness.current).subtle;

  /// Hairline card border — cards use a border instead of elevation.
  ///
  /// This is load-bearing: with a white card on a white page it is the only
  /// thing separating the two, so do not lighten it without re-checking card
  /// legibility on a real device — and on dark it is the card's only edge.
  static Color get cardBorder =>
      AppPalette.of(AppBrightness.current).hairlineOnRaised;

  // ── GCash card ──────────────────────────────────────────────────
  static const Color gcashBgStart = Color(0xFFF6E9D2);
  static const Color gcashBgEnd = Color(0xFFF1DEB8);
  static const Color gcashBorder = Color(0xFFE3CC9C);

  // ── Text ────────────────────────────────────────────────────────
  /// Eyebrow labels, captions, subtitles. BRIGHTNESS-AWARE: muted grey is
  /// muted *relative to the page*, so the value has to move with it.
  static Color get textMuted => AppPalette.of(AppBrightness.current).muted;

  /// Secondary body text.
  static Color get textSecondary =>
      AppPalette.of(AppBrightness.current).mutedStrong;

  /// Ink text on espresso fills (buttons, icon tiles). Pure white now — the
  /// same role as [AppConstants.inkInverse], which aliases this token.
  static const Color creamText = Color(0xFFFFFFFF);

  /// Soft card shadow (10px blur, 2px y, low opacity) — the mockup's
  /// treatment, replacing standard Material elevation on dashboard cards.
  ///
  /// Empty on dark: a shadow on a near-black page is invisible, so seller
  /// cards there rely on [card] being lighter than [creamBg] plus the
  /// [cardBorder] hairline.
  static List<BoxShadow> get cardShadow => AppBrightness.isDark
      ? const <BoxShadow>[]
      : [
          BoxShadow(
            color: const Color(0xFF3A2415).withValues(alpha: 0.12),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ];
}
