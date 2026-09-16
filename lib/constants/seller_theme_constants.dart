import 'package:flutter/material.dart';

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
  /// Screen background — pure white (was the warm cream `#F3E9D8`).
  static const Color creamBg = Color(0xFFFFFFFF);

  /// Card surface. The same white as the page on purpose: cards are
  /// separated by their [cardBorder] hairline rather than by a fill, so a
  /// card can never look dirty or dingy against the page it sits on.
  static const Color card = Color(0xFFFFFFFF);

  /// Hero card gradient end — a subtle neutral wash off the card white.
  static const Color cardHeroEnd = Color(0xFFF5F5F5);

  /// Hairline card border — cards use a border instead of elevation.
  ///
  /// This is now load-bearing: with a white card on a white page it is the
  /// only thing separating the two, so do not lighten it without re-checking
  /// card legibility on a real device.
  static const Color cardBorder = Color(0xFFE8E8E8);

  // ── GCash card ──────────────────────────────────────────────────
  static const Color gcashBgStart = Color(0xFFF6E9D2);
  static const Color gcashBgEnd = Color(0xFFF1DEB8);
  static const Color gcashBorder = Color(0xFFE3CC9C);

  // ── Text ────────────────────────────────────────────────────────
  /// Eyebrow labels, captions, subtitles.
  static const Color textMuted = Color(0xFF6B6B6B);

  /// Secondary body text.
  static const Color textSecondary = Color(0xFF4A4A4A);

  /// Ink text on espresso fills (buttons, icon tiles). Pure white now — the
  /// same role as [AppConstants.inkInverse], which aliases this token.
  static const Color creamText = Color(0xFFFFFFFF);

  /// Soft card shadow (10px blur, 2px y, low opacity) — the mockup's
  /// treatment, replacing standard Material elevation on dashboard cards.
  static List<BoxShadow> get cardShadow => [
        BoxShadow(
          color: const Color(0xFF3A2415).withValues(alpha: 0.12),
          blurRadius: 10,
          offset: const Offset(0, 2),
        ),
      ];
}
