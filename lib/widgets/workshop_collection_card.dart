import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../constants/app_brightness.dart';
import '../constants/app_constants.dart';
import '../constants/app_palette.dart';
import '../providers/product_provider.dart';
import 'fit_card.dart';

/// The "The Workshop Collection" poster — the section's name on the front, the
/// section's sort list on the back, and the collection's first grid cell.
///
/// **It flips, because the sort belongs to the card.** Tapping the front turns
/// the card over (one Y rotation, [flipDuration], ease in and out) and the back
/// is `Sort by` with every [SortMode], the one in force marked. Choosing an
/// order turns it back over and the corner word is already the new order, so the
/// feed never loses its place behind a sheet — and the card is its own way out,
/// because a tap anywhere on the back that is not an option closes it. A card a
/// customer can open must be a card they can close.
///
/// **The front is the poster.** `THE / WORK / SHOP / COLLECTION`, each line
/// scaled to the cell's full width (so `THE` is loudest and `COLLECTION`, the
/// longest word, closes the stack), full bleed — `padding: 0` like the size
/// poster, so the two read as the same printed block — with the sort in force as
/// a word in the bottom-right corner that `FitCard` sizes from its own width.
///
/// **The back is the sheet's list, in the card's own words.** It offers the
/// **short** labels ([sortModeShortLabel]) — the words this card will show in
/// its corner once they are chosen — while each row *announces* the full one, so
/// nothing is lost to a reader who is not looking at the size of the type. Every
/// row is a real button with its own tap, and the selected state is both drawn
/// (clay, bold, a filled radio) and announced.
///
/// **Every metric on the back is a fraction of the card's width**, so the list
/// scales with its cell exactly like the poster does and cannot overflow a
/// shorter one: the card's height is proportional to its width too, so a list
/// that fits at one cell size fits at every cell size. The `FittedBox` guard is
/// only for the pathological case (a very long label in a very narrow cell).
///
/// **It stays a card-sized thing on purpose.** No sheet, no scroll view: the
/// feed already scrolls vertically, and a second vertical scroller inside a cell
/// would trap the drag (`test/widgets/nested_masonry_scroll_test.dart` pins that
/// the feed reaches its last card).
class WorkshopCollectionCard extends StatefulWidget {
  const WorkshopCollectionCard({
    super.key,
    required this.sort,
    required this.onSelected,
  });

  /// The cell proportion the poster asks for — [FitCard.aspectRatio], the
  /// reference 505×800, i.e. the footprint of a product card's cell. Stated here
  /// so a self-sizing parent (a masonry grid) has one honest way to bound it
  /// without reaching into [FitCard] for it.
  static const double aspectRatio = FitCard.aspectRatio;

  /// The poster's words, one per line, loudest first. Four lines is deliberate:
  /// every other `FitCard` keeps to 2–3 short words, and this one is the
  /// section's name spelled out, so it is the card that breaks that rule.
  static const List<String> titleLines = ['THE', 'WORK', 'SHOP', 'COLLECTION'];

  /// The back's heading.
  static const String backTitle = 'Sort by';

  /// One turn of the card. Long enough to read as a card being turned over,
  /// short enough that the list is not something the customer waits for.
  static const Duration flipDuration = Duration(milliseconds: 420);

  /// Ease in *and* out: the card has to start turning and arrive square on.
  static const Curve flipCurve = Curves.easeInOut;

  /// The sort currently in force — the word in the corner, and the marked row
  /// on the back.
  final SortMode sort;

  /// Reports the chosen order. The card does not sort anything itself: it hands
  /// the mode to whoever owns the list.
  final ValueChanged<SortMode> onSelected;

  /// The back's inner padding, as a fraction of the card's width.
  static const double _backPaddingOfWidth = 0.06;

  /// The back's `Sort by` heading, as a fraction of the card's width.
  static const double _backTitleSizeOfWidth = 0.11;

  /// One option's label, as a fraction of the card's width.
  static const double _backLabelSizeOfWidth = 0.085;

  /// One option's radio mark, as a fraction of the card's width.
  static const double _backIconSizeOfWidth = 0.095;

  /// The gap between an option's mark and its label.
  static const double _backIconGapOfWidth = 0.03;

  /// One option's own vertical padding — what makes a row a row.
  static const double _backRowPaddingOfWidth = 0.025;

  /// The space between the heading and the first option.
  static const double _backGapOfWidth = 0.05;

  @override
  State<WorkshopCollectionCard> createState() => _WorkshopCollectionCardState();
}

class _WorkshopCollectionCardState extends State<WorkshopCollectionCard>
    with SingleTickerProviderStateMixin {
  /// 0 is the poster, 1 is the sort list. The controller's value IS the turn
  /// angle, so the two can never disagree about where the card is.
  late final AnimationController _turn = AnimationController(
    vsync: this,
    duration: WorkshopCollectionCard.flipDuration,
  );

  /// Which face is on top. Swapped at the half-way point — the moment the card
  /// is edge-on and neither face is visible — so the back is never seen
  /// mirrored, and a face is built only when the card actually passes over.
  bool _back = false;

  @override
  void initState() {
    super.initState();
    _turn.addListener(_onTurn);
  }

  @override
  void dispose() {
    _turn.removeListener(_onTurn);
    _turn.dispose();
    super.dispose();
  }

  void _onTurn() {
    final back = _turn.value >= 0.5;
    if (back != _back) setState(() => _back = back);
  }

  void _reveal() {
    if (_turn.value != 1) _turn.forward();
  }

  void _hide() {
    if (_turn.value != 0) _turn.reverse();
  }

  /// Choosing a row always closes the card — and only reports a *change*, so
  /// re-picking the order already in force is not a reload for nothing.
  void _select(SortMode mode) {
    _hide();
    if (mode != widget.sort) widget.onSelected(mode);
  }

  @override
  Widget build(BuildContext context) {
    // Reduced motion gets the state, not the travel: the card is still turned
    // over, it just does not animate there. Assigned here rather than in
    // `initState` because the setting can change while the card is mounted.
    _turn.duration = (MediaQuery.maybeOf(context)?.disableAnimations ?? false)
        ? Duration.zero
        : WorkshopCollectionCard.flipDuration;

    return AnimatedBuilder(
      animation: _turn,
      // The face is the builder's `child`: a turn repaints a transform instead
      // of rebuilding the poster (or the list) on every frame, and a new face is
      // built only when the card passes the half-way point.
      child: _back ? _sortFace() : _posterFace(),
      builder: (context, child) => Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          // A little perspective, or a card turning over reads as a card being
          // squashed rather than turned.
          ..setEntry(3, 2, 0.0015)
          ..rotateY(_turn.value * math.pi),
        child: _back
            // The back is mounted rotated by the other half turn, so it faces
            // the customer when the card has been turned all the way over.
            ? Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()..rotateY(math.pi),
                child: child,
              )
            : child,
      ),
    );
  }

  Widget _posterFace() {
    return FitCard(
      lines: WorkshopCollectionCard.titleLines,
      // No inner inset: the four words are the design, and the block they make
      // is the card — the same full bleed the size poster uses.
      padding: 0,
      // The short form: the corner of a cell has room for `Low to High`, and it
      // is the word this card will keep showing once it is chosen.
      footerLabel: sortModeShortLabel(widget.sort),
      semanticsLabel:
          'The Workshop Collection, sorted by ${sortModeLabel(widget.sort)}. '
          'Double tap to change sort.',
      onTap: _reveal,
    );
  }

  Widget _sortFace() {
    final palette = AppPalette.of(AppBrightness.current);
    return LayoutBuilder(
      builder: (context, card) {
        // Everything below is derived from the card's width, so the list scales
        // with its cell instead of overflowing a shorter one.
        final width = card.maxWidth;
        final pad = width * WorkshopCollectionCard._backPaddingOfWidth;
        final labelSize = width * WorkshopCollectionCard._backLabelSizeOfWidth;

        return Material(
          // The card's own back: same fill, same hairline, same radius, so a
          // turn reads as one card rather than as two widgets.
          color: AppConstants.surfaceSubtle,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: AppConstants.productCardRadius,
            side: BorderSide(color: palette.hairline),
          ),
          child: GestureDetector(
            // Anywhere that is not an option is the way back. `opaque` because
            // the padding bands are painted by no child.
            behavior: HitTestBehavior.opaque,
            onTap: _hide,
            child: Padding(
              padding: EdgeInsets.all(pad),
              child: FittedBox(
                // A guard rail, not the sizing: the fractions above are what
                // make the list scale, and this only catches the pathological
                // case (a very long label in a very narrow cell).
                fit: BoxFit.scaleDown,
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: width - pad * 2,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        WorkshopCollectionCard.backTitle,
                        textScaler: TextScaler.noScaling,
                        style: AppConstants.headlineStyle(
                          fontSize:
                              width *
                              WorkshopCollectionCard._backTitleSizeOfWidth,
                        ),
                      ),
                      SizedBox(
                        height: width * WorkshopCollectionCard._backGapOfWidth,
                      ),
                      for (final mode in SortMode.values)
                        _option(
                          mode: mode,
                          labelSize: labelSize,
                          width: width,
                          selected: mode == widget.sort,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _option({
    required SortMode mode,
    required double labelSize,
    required double width,
    required bool selected,
  }) {
    // One node per option, spelled out by hand: the card shows the SHORT label
    // because that is what fits, and announces the full one (`Price: Low to
    // High`) because that is what the order is called. The subtree is excluded
    // so the row cannot be announced twice, and both the drawn tap and the
    // assistive one call the same handler.
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: sortModeLabel(mode),
      onTap: () => _select(mode),
      child: ExcludeSemantics(
        child: InkWell(
          onTap: () => _select(mode),
          child: Padding(
            padding: EdgeInsets.symmetric(
              vertical: width * WorkshopCollectionCard._backRowPaddingOfWidth,
            ),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: width * WorkshopCollectionCard._backIconSizeOfWidth,
                  color: selected
                      ? AppConstants.primary
                      : AppConstants.borderGray,
                ),
                SizedBox(
                  width: width * WorkshopCollectionCard._backIconGapOfWidth,
                ),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      sortModeShortLabel(mode),
                      maxLines: 1,
                      softWrap: false,
                      textScaler: TextScaler.noScaling,
                      style: AppConstants.bodyStyle(
                        fontSize: labelSize,
                        fontWeight: selected
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: selected
                            ? AppConstants.primary
                            : AppConstants.secondary,
                      ),
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
