import 'package:flutter/material.dart';

/// The role-based colour palette — every surface and ink role the app paints
/// from, with a light and a dark value.
///
/// **Why roles instead of `Theme.of(context)`.** The app paints from
/// `AppConstants` tokens rather than from Flutter's `ThemeData`:
/// `Theme.of(context)` appears six times in 300 files, and there is no
/// `scaffoldBackgroundColor` anywhere. A dark theme therefore cannot come from
/// the theme layer — it comes from these roles resolving against
/// [AppBrightness]. Keeping the *names* stable is what lets the switch happen
/// without touching thousands of call sites.
///
/// See `docs/AI/DARK_MODE_PLAN.md` for the measured blast radius and the
/// phased rollout this belongs to.
///
/// **Contrast rule:** every role must clear AA against the surface it is drawn
/// on — 4.5:1 for body text, 3:1 for large text and icons. Values here are
/// candidates under that rule, not final art direction.
///
/// **Light values are the pre-dark-mode hexes**, so `AppPalette.light` is
/// byte-identical to the palette the app shipped before dark mode existed.
/// That is a hard constraint: light mode must not move.
@immutable
class AppPalette {
  const AppPalette({
    required this.page,
    required this.raised,
    required this.subtle,
    required this.band,
    required this.hairline,
    required this.hairlineSoft,
    required this.hairlineOnRaised,
    required this.cardEdge,
    required this.onPage,
    required this.muted,
    required this.mutedStrong,
    required this.inkInverse,
    required this.primaryInk,
    required this.accentSoft,
    required this.scrim,
    required this.shadow,
  });

  /// Page, scaffold, sheet and dialog background — the surface everything
  /// else sits on. `colorScheme.surface` maps here.
  final Color page;

  /// A card, popup or chip that must read as raised *above* [page].
  final Color raised;

  /// Input fields, unselected chips and section bands.
  final Color subtle;

  /// Grounded band (the bottom navigation bar's default).
  final Color band;

  /// Solid 1px border/divider.
  final Color hairline;

  /// A hairline that is *already* faded — for internal separators where the
  /// caller would otherwise write `hairline.withValues(alpha: 0.5)`. On dark a
  /// solid hairline faded with an alpha lands on the page and disappears, so
  /// the fade belongs in the token, not the call site.
  final Color hairlineSoft;

  /// The hairline outlining a raised card, where the surface *behind* it is
  /// [raised] rather than [page]. Slightly stronger than [hairline] on light
  /// and on dark, because it is that card's only edge.
  final Color hairlineOnRaised;

  /// The stronger edge used only around product cards.
  final Color cardEdge;

  /// Primary text and icon ink on [page] / [raised].
  final Color onPage;

  /// Secondary text: captions, subtitles, overlines.
  final Color muted;

  /// Text that is de-emphasised but still body-weight.
  final Color mutedStrong;

  /// Ink drawn on clay, espresso, teal or black fills. Pinned white on both
  /// brightnesses: those fills keep their brand colour, so the ink on them
  /// must not follow the page.
  final Color inkInverse;

  /// The clay accent when it is used as *ink* (text, icons, links) rather
  /// than as a fill. On dark, brand clay (#8B5A2B) sits at roughly 3:1 against
  /// the page — fine for large marks, short of AA for body copy — so it has a
  /// lifted dark value. Fills keep [AppConstants.primary] on both.
  final Color primaryInk;

  /// A soft teal tint used behind highlighted content.
  final Color accentSoft;

  /// Modal barrier / photographic overlay.
  final Color scrim;

  /// The tint used for drop shadows. On dark this is fully transparent:
  /// depth has to read as a *lighter* raised surface plus a hairline, because
  /// a shadow on near-black is invisible.
  final Color shadow;

  static const AppPalette light = AppPalette(
    page: Color(0xFFFFFFFF),
    raised: Color(0xFFFFFFFF),
    subtle: Color(0xFFF5F5F5),
    band: Color(0xFFF5F5F5),
    hairline: Color(0xFFE5E5E5),
    hairlineSoft: Color(0xFFEFEFEF),
    hairlineOnRaised: Color(0xFFE8E8E8),
    cardEdge: Color(0xFFC9C9C9),
    onPage: Color(0xFF111111),
    muted: Color(0xFF6B6B6B),
    mutedStrong: Color(0xFF4A4A4A),
    inkInverse: Color(0xFFFFFFFF),
    primaryInk: Color(0xFF8B5A2B),
    accentSoft: Color(0x1A4ECDC4),
    scrim: Color(0x80000000),
    shadow: Color(0x148B5A2B),
  );

  /// Dark values.
  ///
  /// `hairline` is deliberately a **mid** grey rather than a subtle near-page
  /// tone: at the time of writing, 358 call sites still consume the hairline
  /// token *both* solid and faded (`withValues(alpha: 0.3–0.7)`). A value
  /// tuned for the solid case alone would leave every faded hairline invisible
  /// on dark. Phase 3 of `docs/AI/DARK_MODE_PLAN.md` splits those two uses
  /// into `hairline` / `hairlineSoft`, after which this can drop to a real
  /// dark-mode hairline.
  static const AppPalette dark = AppPalette(
    page: Color(0xFF111111),
    raised: Color(0xFF1C1C1C),
    subtle: Color(0xFF1F1F1F),
    band: Color(0xFF171717),
    hairline: Color(0xFF555555),
    hairlineSoft: Color(0x24FFFFFF),
    hairlineOnRaised: Color(0xFF3A3A3A),
    cardEdge: Color(0xFF555555),
    onPage: Color(0xFFF5F5F5),
    muted: Color(0xFFA3A3A3),
    mutedStrong: Color(0xFFD0D0D0),
    inkInverse: Color(0xFFFFFFFF),
    primaryInk: Color(0xFFC08A4E),
    accentSoft: Color(0x2E4ECDC4),
    scrim: Color(0xB3000000),
    shadow: Color(0x00000000),
  );

  /// The role set for a brightness. Anything other than [Brightness.dark] is
  /// treated as light, so a null/unknown platform value can never accidentally
  /// paint a dark app.
  static AppPalette of(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;
}
