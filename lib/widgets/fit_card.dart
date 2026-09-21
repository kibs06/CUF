import 'package:flutter/material.dart';

import '../constants/app_brightness.dart';
import '../constants/app_constants.dart';
import '../constants/app_palette.dart';

/// A category tile whose typography scales to fill the whole card — the "Fit
/// Card" pattern, reference card "Based on your size · EU 42".
///
/// **The text *is* the design.** There are no icons, images or decorative
/// elements inside it, and nothing here hardcodes a font size for the lines or
/// the hero value: every line — including the value under the caption — is laid
/// out at [_referenceFontSize] and scaled by a [FittedBox] to exactly the
/// card's inner width, so a short word renders larger than a long one and every
/// line touches both inner edges. Which line is biggest is therefore decided by
/// the *copy*, not by tuning a number here: to rebalance a card, change its
/// line breaks or the value's length.
///
/// **The one number that sets the spacing is [lineHeight]** — the leading the
/// words are stacked on, and it has to be *applied* to do anything.
///
/// The reference snippet pairs `height: 0.86` with a [TextHeightBehavior] whose
/// `applyHeightToFirstAscent`/`applyHeightToLastDescent` are both `false`, on
/// the reasoning that this removes the padding above and below the text. It
/// does — but it also makes the height multiplier apply only to the space
/// *between* lines, and each line here is its own one-line `Text`, so the
/// multiplier was ignored outright: every word was rendered at the font's full
/// ascent + descent (~1.27em on DM Sans) instead of 0.86em. That is the gap
/// between the words, and because each line is scaled to the card's full width
/// it is a *large* gap — three of them filled the card on device, leaving the
/// hero value no height at all and reporting a sub-pixel overflow.
///
/// So: the default text-height behaviour (both flags `true`), which is what lets
/// [lineHeight] bite. Measured, not assumed — `fit_card_test.dart` asserts the
/// leading that comes out of a laid-out line is the one this widget declares,
/// in whatever font the test happens to run in.
///
/// **Two things make it work, and both are load-bearing:**
///
///  * The line [Column] is `CrossAxisAlignment.stretch`, which gives each
///    [FittedBox] a *tight* width. Without it `FittedBox` would only ever
///    shrink, and the text would stay small.
///  * Every `Text` carries [TextScaler.noScaling]: the card scales with its
///    cell, not with the system font-size setting, so the OS text scale must
///    not reach inside it.
///
/// **The value gets the same treatment as the words.** The hero value is scaled
/// to the card's full width exactly like the lines above it — it is the same
/// [_line] — so the number is as loud as the copy and the card reads as one
/// poster rather than "three big words and a small number". The `EU` label is
/// the one thing that is *not* scaled to the width: it is a caption whose size
/// is a fraction of the card's width ([_labelSizeOfWidth]), so it stays a
/// caption on any tile instead of a fixed pixel size that reads huge on a small
/// card and gets lost on a big one. A value may also carry a small mark at its
/// top ([heroValueSuffix]) — the `%` of a sale poster — which gives those same
/// digits the width the sign would otherwise have shared with them.
///
/// **The closer is the hero, or a footer, or nothing at all.** A hero is no
/// longer required: [footerLabel] is the quiet alternative — a word in the
/// bottom-right corner that the card is not loud about, sized from the card like
/// every other piece of its type, which is what "The Workshop Collection" uses
/// for its current sort. The two are mutually exclusive (asserted): the hero
/// *fills* the height the words leave and the footer only *sits* in it. The line
/// list is not capped either, so that poster can break the three-word rhythm
/// with four while every other card keeps it.
///
/// **Robust by construction, not by arithmetic.** Nothing above the closer is
/// flexible, so the hero can never be squeezed out by its copy: the card's
/// height follows its content, and a cell that is *too short* for that content
/// scales the whole poster down (`scaleDown`) instead of painting a striped
/// overflow. Extra height is spent *between* the words and the closer, so the
/// number — or the footer — always sits on the card's bottom edge. That band is
/// the only place a cell taller than the card's copy has to spend its extra
/// height, and it is why a poster reads as a gap where one is not wanted: the
/// two ways to close it are to give the copy more to say (more lines) or to let
/// the words themselves grow, and neither is a number this widget can tune.
///
/// **Bounding it is the caller's job, and [aspectRatio] is the reference.** Give
/// it a box (the tile does, with `AspectRatio`) and the value lands on that
/// box's bottom edge; leave it unbounded — a masonry grid, a `Column` — and its
/// height is whatever its copy comes to, which on a 2-column cell lands within a
/// few percent of the reference proportion anyway.
///
/// **Colours come from the app's tokens, not from the reference mockup's
/// hexes**, because the app paints from brightness-aware roles and ships a dark
/// mode: fill → [AppConstants.surfaceLight] (the *page* tone — see
/// [backgroundColor]), edge → [edgeColor] at [edgeWidth] (a thin line of the
/// poster's own, **not** the product cards' — see [borderColor]),
/// ink → [AppConstants.secondary] (`onPage`), accent → [AppPalette.primaryInk]
/// (the clay *ink* role, lifted on dark), radius →
/// [AppConstants.productCardRadius] (these cards share a grid with the product
/// cards, so they share the product family's corner).
/// The mockup's warm `#F5F1EC` fill against brown `#9A5B2E` ink predates the
/// neutral palette; every one of those is overridable per card if a surface
/// wants the warmer treatment, and the dark values for the defaults are correct
/// without the caller doing anything.
class FitCard extends StatelessWidget {
  const FitCard({
    super.key,
    required this.lines,
    this.heroValue,
    this.heroValueSuffix,
    this.heroWidget,
    this.heroLabel,
    this.footerLabel,
    this.semanticsLabel,
    this.onHighlightChanged,
    this.onTap,
    this.backgroundColor,
    this.borderColor,
    this.inkColor,
    this.accentColor,
    this.borderRadius,
    this.padding = 16,
  }) : assert(
         !(heroValue != null && heroWidget != null),
         'A card has at most one hero: a value or a widget',
       ),
       assert(
         footerLabel == null ||
             (heroValue == null && heroWidget == null && heroLabel == null),
         'A card has a hero or a footer, never both — and the label belongs '
         'to the hero it sits above',
       ),
       assert(
         heroValueSuffix == null || heroValue != null,
         'The mark belongs to a value: it is drawn at the top of the line the '
         'digits are scaled into',
       );

  // Deliberately no `assert(lines.length <= 3)`: a list's `length` is not
  // const-evaluable, and keeping this constructor `const` (so a card can be a
  // compile-time constant) is worth more than the guard. Three lines is a
  // design rule — see [lines] — not a layout constraint.

  /// The card's proportion (width / height): the reference design's 505×800,
  /// i.e. about the same footprint as a product card in a 2-column grid.
  ///
  /// Exposed so a caller in a self-sizing parent has one honest way to bound
  /// this widget rather than inventing a height of its own.
  static const double aspectRatio = 505 / 800;

  /// The poster family's edge colour for the current brightness — what
  /// [borderColor] defaults to.
  ///
  /// Exposed so a card with two faces (The Workshop Collection, which flips
  /// onto its sort list) can publish the same line on both sides of the turn
  /// without restating the role.
  static Color get edgeColor => AppPalette.of(AppBrightness.current).hairline;

  /// The poster's own edge width: **half** the product cards' 1px line.
  ///
  /// The posters and the product cards share a grid, not an edge. A product
  /// card is a filled tile framed by `AppConstants.cardEdge`; a poster is
  /// page-toned type standing on the same page, and borrowing that full-weight
  /// frame made it read as a box drawn around the copy instead of as the copy
  /// itself. Half the line — the same half-width the cart's row divider uses —
  /// leaves the poster an outline at rest. See [borderColor] for the colour
  /// half of the same decision.
  static const double edgeWidth = 0.5;

  /// The lines, top to bottom — 2 or 3 short ones (1–2 words, ideally 4–8
  /// characters each), the shortest word ideally alone on its line so it can
  /// carry the rhythm. Sentence case, no punctuation.
  ///
  /// The "three lines" rule is a design rule, not a limit (there is no assert
  /// on it — see the note above): the "The Workshop Collection" poster is the
  /// one card that breaks it with four, because each of its words is its own
  /// line by design, and a longer list simply means more, thinner lines.
  final List<String> lines;

  /// The value shown under [lines] — keep it to 1–4 characters (a size, a
  /// count, a percentage); it is scaled to the card's width like the words, so
  /// a longer one comes out smaller, which dilutes the card.
  ///
  /// At most one of [heroValue] / [heroWidget] is given, and neither is
  /// required: a card may close on a [footer] instead, or on the words alone.
  final String? heroValue;

  /// A small mark set at the **top** of the value — the `%` of a sale poster,
  /// where `61` is the number the card is about and `%` only says what it
  /// counts.
  ///
  /// **Why the mark is not part of the value's string:** the value is scaled to
  /// the width, so every character in it is paid for in size. `61%` as one
  /// string gives the digits three characters' worth of width to share; `61`
  /// with `%` as the suffix gives them all of it but the mark's own fraction
  /// ([heroSuffixSizeOfWidth]), which is what makes the number the big thing on
  /// the poster and the sign a mark on it.
  ///
  /// The two are one line: the value is scaled to the width the mark leaves,
  /// and the mark is aligned to the top of that line, so it reads as raised
  /// rather than as a second, smaller character beside the digits. Sized from
  /// the card, like the caption and the footer, so it scales with its cell.
  final String? heroValueSuffix;

  /// A hero that is a *mark* rather than a word — the "See more" arrow, and
  /// anything drawn rather than typed. It keeps its own proportions and is
  /// scaled as a block, bottom-left, at [_heroWidgetWidthOfWidth] of the card's
  /// width: a glyph reads as part of the poster at that size, whereas scaling
  /// it to the full width would turn it into a banner.
  ///
  /// **It needs a fixed intrinsic size** (the arrow is 140×100) — that is what
  /// the [FittedBox] scales. At most one of [heroValue] / [heroWidget] is given.
  final Widget? heroWidget;

  /// Optional small accent label directly above the hero (e.g. `'EU'`).
  ///
  /// It belongs to the hero: a card with a [footerLabel] and no hero has nowhere
  /// to put it, and the constructor asserts against passing one.
  final String? heroLabel;

  /// A word in the card's bottom-right corner, in place of a hero — the "The
  /// Workshop Collection" poster's current sort.
  ///
  /// **A word, not a widget, and that is the point:** the footer is sized from
  /// the card like everything else here ([footerSizeOfWidth]), so it scales
  /// with its cell instead of sitting at a fixed pixel size that reads big on a
  /// small tile and gets lost on a large one. A caller brings the *text*; the
  /// card brings the treatment (weight, tracking, the accent ink, and a
  /// `FittedBox(scaleDown)` so an unusually long word shrinks rather than
  /// overflowing).
  ///
  /// **Deliberately not a button, and the card is what makes that work:** the
  /// footer has no fill, border or chevron, because the WHOLE card is the tap
  /// target and a boxed word in the corner would read as a second, smaller
  /// control next to it.
  ///
  /// A card has a hero **or** a footer, never both (asserted): the hero is the
  /// loud thing that fills the height the words leave, and the footer is the
  /// quiet thing that sits in that space instead. Any height the copy does not
  /// use stays *between* the words and the footer, exactly as it does above a
  /// hero, so the footer lands on the card's bottom edge.
  final String? footerLabel;

  /// Replaces the assembled label (`"Based on your size EU 42"`, one node, not
  /// five fragments). Worth passing whenever [heroWidget] is used, since a
  /// painted mark contributes no words of its own and the copy would otherwise
  /// be announced without it.
  final String? semanticsLabel;

  /// Press feedback, forwarded to the [InkWell]. The "See more" card uses it
  /// to nudge the arrow; the ripple is [InkWell]'s own and stays untouched.
  final ValueChanged<bool>? onHighlightChanged;

  /// The whole card is the tap target. Null renders it as a plain tile —
  /// deliberately still tappable-looking, since a category card with nothing
  /// behind it yet should not advertise a destination it does not have.
  final VoidCallback? onTap;

  /// Card fill. Defaults to [AppConstants.surfaceLight] — the page tone.
  ///
  /// **The poster is a flat tile on the page, not a filled card.** "Based on
  /// your size", "See more", "ON SALE" and "The Workshop Collection" all sit in
  /// the same grid as the product cards, and a product card is already page
  /// toned with a hairline for its edge (see `sole_product_card.dart`). On the
  /// old [AppConstants.surfaceSubtle] fill the posters read as grey squares
  /// beside white tiles — a second, differently-coloured surface inside one
  /// grid — so the fill is now the same tone as the page behind it and the
  /// hairline is what draws the tile, exactly as it does on a product card.
  ///
  /// Dark mode needs nothing here: the page role is brightness-aware, and the
  /// hairline stays the edge on the dark tone (the same contract
  /// `sole_product_card.dart` documents). A surface that wants a poster to
  /// stand off its page can still pass its own fill — every colour remains
  /// overridable per card.
  final Color? backgroundColor;

  /// The card's edge. Defaults to [edgeColor] ([AppPalette.hairline] — one step
  /// lighter than a product card's edge), drawn at [edgeWidth].
  ///
  /// **The posters share a grid with the product cards, not their edge.** A
  /// product card is a filled tile framed by a 1px `AppConstants.cardEdge`;
  /// a poster is page-toned type standing on the same page, and its frame is
  /// what makes the two the same family. Borrowing the product card's
  /// full-weight, darker line made the poster read as a box drawn around the
  /// copy — the tile stopped looking like type. So the poster keeps a line of
  /// its own, thinner and lighter than the product cards' on both counts.
  ///
  /// On dark the two roles meet anyway (`hairline` and `cardEdge` are both
  /// `#555555` there) and the width still halves, so the poster's outline stays
  /// the lighter of the two at every brightness.
  final Color? borderColor;

  /// The lines' ink. Defaults to [AppConstants.secondary].
  final Color? inkColor;

  /// The label and hero value's ink. Defaults to [AppPalette.primaryInk] — the
  /// clay *ink* role, which lifts on dark so the value keeps its contrast on
  /// the dark fill.
  final Color? accentColor;

  /// Defaults to [AppConstants.productCardRadius] — the product cards' own
  /// corner, which the reference's 28 was explicitly allowed to defer to.
  final BorderRadius? borderRadius;

  /// Inner padding on all sides. [FittedBox] scales to the inner box, so this
  /// is also what the lines are measured against.
  final double padding;

  /// The size every line is laid out at before [FittedBox] scales it. Never
  /// render at this size — it exists so the scale factor is the card's width
  /// divided by the text's natural width, with no per-card numbers anywhere.
  static const double _referenceFontSize = 100;

  /// How tall one line's box is, in ems — the leading the words are stacked on,
  /// and the single number that decides how far apart they sit.
  ///
  /// `0.86` is the mockup's value and it is a genuinely tight stack (the font's
  /// own line box is ~1.27em on DM Sans), *provided* the [TextHeightBehavior]
  /// stays at its default — see the class doc for how a `false`
  /// `applyHeightToFirstAscent` silently turns this number into a no-op and
  /// spaces the words a third of a line apart.
  static const double lineHeight = 0.86;

  /// The `EU`-style label's size, as a fraction of the card's inner width.
  ///
  /// The label is the only text here that is not scaled to the card's width, so
  /// this is what keeps it a caption: ~14px on a 2-column cell, ~29px on a card
  /// twice as wide, and never the same absolute size on both.
  static const double _labelSizeOfWidth = 0.1;

  /// [footerLabel]'s size, as a fraction of the card's inner width — the same
  /// treatment the label above a hero gets, for the same reason.
  ///
  /// `0.1` lands the footer on about **18px on a full-bleed 2-column cell**
  /// (~183px), which is the size the design calls for there, and keeps it a
  /// corner mark at every other cell size rather than a fixed pixel size. The
  /// reference mockup's 18 was a number for one cell width; this is that number
  /// stated once, as a proportion.
  static const double footerSizeOfWidth = 0.1;

  /// How tight the footer's tracking is, as a fraction of its size — the
  /// mockup's ~-2%, versus the words' -4% (they are much bigger, so the same
  /// percentage would pinch them).
  static const double _footerTracking = 0.02;

  /// The air the footer keeps from the card's **right** edge, as a fraction of
  /// the inner width.
  ///
  /// The poster's words are full bleed, but the footer is a caption sitting in
  /// the corner: flush against the edge its last glyph lands on the rounded
  /// corner's own anti-aliased clip and is shaved — a full-bleed card has no
  /// margin to absorb it (the words get away with it because they are
  /// rectangular type, and their own side bearings already hold them in).
  ///
  /// `0.06` is about 11px on a 183px cell — the card's own corner radius, so
  /// the word clears the arc entirely without the inset reading as a stray gap.
  /// Right only: the bottom edge is the footer's, the same one the hero value
  /// sits on.
  static const double footerInsetOfWidth = 0.06;

  /// The words' own tracking, as a fraction of the line size.
  static const double _lineTracking = 0.04;

  /// How much of the card's inner width a [heroWidget] takes. The reference
  /// "See more" arrow sits at about two-thirds of it — big enough to carry the
  /// card, small enough that the words above stay the loudest thing on it.
  static const double _heroWidgetWidthOfWidth = 0.68;

  /// [heroValueSuffix]'s size, as a fraction of the card's inner width — the
  /// same "sized from the card, not in pixels" rule the caption and the footer
  /// follow.
  ///
  /// `0.2` lands the mark on about **37px on a full-bleed 2-column cell**
  /// (~183px), roughly a third of the number it belongs to: read at that size
  /// the sign says what the number counts without competing with it, which is
  /// the point of taking it out of the value's string.
  static const double heroSuffixSizeOfWidth = 0.2;

  /// The air between the value and its mark, as a fraction of the inner width —
  /// small: the mark belongs to the number, it is not a word beside it.
  static const double _suffixGapOfWidth = 0.02;

  TextStyle _style(
    Color color, {
    double fontSize = _referenceFontSize,
    double? height,
    double tracking = _lineTracking,
  }) => AppConstants.bodyStyle(
    fontSize: fontSize,
    fontWeight: FontWeight.w800,
    color: color,
    height: height ?? lineHeight,
    // Proportional, so it stays -4% at any reference size — the tightness
    // is a property of the design, not of this particular font size.
    letterSpacing: -fontSize * tracking,
  );

  /// One line, scaled to the full inner width — the treatment every line gets,
  /// the words and the value alike. `fitWidth` is the only fit that can scale
  /// *up*; `topLeft` keeps the baseline group pinned to the top so the lines
  /// stack with no gap between them.
  Widget _line(String text, Color ink) {
    return FittedBox(
      fit: BoxFit.fitWidth,
      alignment: Alignment.topLeft,
      child: Text(
        text,
        maxLines: 1,
        softWrap: false,
        textScaler: TextScaler.noScaling,
        style: _style(ink),
      ),
    );
  }

  /// The value and its mark as one line: the digits scaled to the width the
  /// mark leaves, the mark at the top of that line.
  ///
  /// The value keeps the [_line] treatment — it is the same `fitWidth` box, so
  /// it still spans everything but the mark's own fraction — and the mark gets
  /// its own single line box (`height: 1`) so `start` alignment puts its top on
  /// the digits' top rather than centring it on their baseline.
  Widget _valueWithSuffix(
    String value,
    String suffix,
    double innerWidth,
    Color ink,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _line(value, ink)),
        SizedBox(width: innerWidth * _suffixGapOfWidth),
        Text(
          suffix,
          maxLines: 1,
          softWrap: false,
          textScaler: TextScaler.noScaling,
          style: _style(
            ink,
            fontSize: innerWidth * heroSuffixSizeOfWidth,
            height: 1,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(AppBrightness.current);
    final ink = inkColor ?? AppConstants.secondary;
    final accent = accentColor ?? palette.primaryInk;

    // One label, not five fragments: the card reads as "Based on your size EU
    // 42", which is what it says on screen — the mark is part of the value's
    // own word (`61%`), not a fragment of its own. A caller-supplied label wins
    // — a hero widget paints no words of its own to be collected here.
    final value = heroValue == null
        ? null
        : '${heroValue!}${heroValueSuffix ?? ''}';
    final label = semanticsLabel ?? [...lines, ?heroLabel, ?value].join(' ');

    return Semantics(
      container: true,
      button: onTap != null,
      label: label,
      child: ExcludeSemantics(
        child: Material(
          color: backgroundColor ?? AppConstants.surfaceLight,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: borderRadius ?? AppConstants.productCardRadius,
            side: BorderSide(
              color: borderColor ?? edgeColor,
              width: edgeWidth,
            ),
          ),
          child: InkWell(
            onTap: onTap,
            onHighlightChanged: onHighlightChanged,
            child: Padding(
              padding: EdgeInsets.all(padding),
              // The inner box is what the lines are measured against and what
              // bounds the words block, so it is read once here rather than
              // assumed from the card's own size.
              child: LayoutBuilder(
                builder: (context, inner) {
                  final caption = heroLabel;
                  final mark = heroWidget;
                  // Sized from the card, like the lines and the value: the
                  // footer is a caption of the poster, not a fixed pixel size.
                  final footerSize = inner.maxWidth * footerSizeOfWidth;
                  final closing = footerLabel;
                  final hasHero = heroValue != null || mark != null;

                  final content = Column(
                    mainAxisSize: MainAxisSize.min,
                    // Tight width, so each FittedBox scales its line UP to the
                    // inner width. Loose (the default) and every line would
                    // render small and left-aligned instead.
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    // The words sit against the top, whatever closes the card
                    // sits on the bottom edge, and any height the copy does not
                    // need stays between them — never under the last thing.
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [for (final line in lines) _line(line, ink)],
                      ),
                      // One closer, and never two (asserted): the hero, or the
                      // footer, or — a card of words alone — nothing.
                      if (hasHero)
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (caption != null) ...[
                              Text(
                                caption,
                                textScaler: TextScaler.noScaling,
                                style: _style(
                                  accent,
                                  fontSize: inner.maxWidth * _labelSizeOfWidth,
                                ),
                              ),
                              const SizedBox(height: 4),
                            ],
                            if (mark == null && heroValueSuffix == null)
                              // The value is the same line as the copy above
                              // it: the number carries the card the way the
                              // words do.
                              _line(heroValue!, accent)
                            else if (mark == null)
                              // The number with its own small mark at the top:
                              // the digits still take the card, the sign does
                              // not — see [heroValueSuffix].
                              _valueWithSuffix(
                                heroValue!,
                                heroValueSuffix!,
                                inner.maxWidth,
                                accent,
                              )
                            else
                              // A mark, not a word: `Align` opts out of the
                              // stretched width so the glyph keeps its own
                              // proportions instead of being blown up edge to
                              // edge, and the fraction fixes how big it reads.
                              Align(
                                alignment: Alignment.bottomLeft,
                                child: FractionallySizedBox(
                                  widthFactor: _heroWidgetWidthOfWidth,
                                  child: FittedBox(
                                    fit: BoxFit.contain,
                                    alignment: Alignment.bottomLeft,
                                    child: mark,
                                  ),
                                ),
                              ),
                          ],
                        )
                      else if (closing != null)
                        // The footer takes the stretched width and puts the
                        // word itself in the corner — so it reads as a mark on
                        // the poster rather than as a control spanning the
                        // card. `scaleDown` is a guard rail, not the sizing:
                        // the size above is what makes it scale, and this only
                        // catches a word too long for a narrow cell.
                        //
                        // The right inset is what keeps the word off the
                        // corner's own clip — see [footerInsetOfWidth].
                        Padding(
                          padding: EdgeInsets.only(
                            right: inner.maxWidth * footerInsetOfWidth,
                          ),
                          child: Align(
                            alignment: Alignment.bottomRight,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                              child: Text(
                                closing,
                                maxLines: 1,
                                softWrap: false,
                                textScaler: TextScaler.noScaling,
                                style: _style(
                                  accent,
                                  fontSize: footerSize,
                                  // A single line of its own: the natural line
                                  // box would leave a band of empty card under
                                  // the word and lift it off the bottom edge.
                                  height: 1,
                                  tracking: _footerTracking,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  );

                  // A bounded cell is filled — that is what puts the value on
                  // the card's bottom edge — but never overrun: `scaleDown`
                  // reduces the whole poster to fit a cell too short for its
                  // copy, instead of painting a striped overflow. An unbounded
                  // cell (a masonry grid, a `Column`) simply gets the card's own
                  // height.
                  return FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: inner.maxWidth,
                      child: inner.maxHeight.isFinite
                          ? ConstrainedBox(
                              constraints: BoxConstraints(
                                minHeight: inner.maxHeight,
                              ),
                              child: content,
                            )
                          : content,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
