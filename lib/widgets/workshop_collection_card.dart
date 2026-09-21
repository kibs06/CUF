import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../constants/app_brightness.dart';
import '../constants/app_constants.dart';
import '../constants/app_palette.dart';
import '../providers/product_provider.dart';
import '../services/workshop_sort_hint_service.dart';
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
///
/// **It says out loud that it turns over — three cues, and each one carries a
/// different customer.** A card the customer has to guess about is a card they
/// never use, so this one carries all three of the affordances the feed already
/// teaches with:
///
///  * **The idle beat.** Every few seconds the card leans a few degrees toward
///    the back and settles square again ([teaseHold] / [teaseOut] / [teaseBack]
///    / [teaseFraction]) — timer-scheduled, `TickerMode`-gated and skipped under
///    reduced motion, exactly the shape of the "See more" arrow's glide
///    (`see_more_card.dart`). Motion is what this feed uses for "there is
///    something to do here" — the hang tag swings, the price tape shimmers, the
///    arrow glides — and this was the one interactive tile in it that sat
///    perfectly still.
///  * **The lift.** The poster casts the product cards' shadow
///    ([AppConstants.productCardShadow]) and keeps casting it while the card
///    turns, so it reads as an object standing on the page rather than as
///    printed type. The posters deliberately used to stay flat; a card with two
///    sides is not a printed label any more, and depth is what says so.
///  * **The first-run hint.** `Tap to sort` ([hintLabel]) appears in the empty
///    band under the words, opposite the corner word it is about, the first time
///    the card is ever shown, and retires the moment the card is used — or after
///    [hintLifetime] — for good ([WorkshopSortHintService], device-local). It is
///    the one cue here that is not motion, deliberately: a beat can be missed,
///    and the customer who misses it is the one the list was for.
///
/// The beat and the hint are both **hints, never state**: neither is ever
/// reported anywhere, and the beat is dropped before a flip so a tap landing
/// mid-beat cannot leave the card resting a few degrees off square.
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

  /// The first-run hint's copy — the card's own words for what a tap does. Short
  /// on purpose: it shares the card's bottom band with the corner word it is
  /// about, and anything longer stops fitting beside it on a two-column cell.
  static const String hintLabel = 'Tap to sort';

  /// How long the first-run hint stays on screen before retiring itself. Long
  /// enough to be read on the way past a feed, short enough that it is gone
  /// before it becomes furniture — and the customer who taps the card in the
  /// meantime retires it immediately.
  static const Duration hintLifetime = Duration(seconds: 7);

  /// The idle beat's rhythm: stillness, then the lean out, then square again.
  /// The same shape as the "See more" arrow's beat (`SeeMoreCard`), because it
  /// is the same job — the holds are what make it a beat rather than a hum.
  static const Duration teaseHold = Duration(milliseconds: 3600);
  static const Duration teaseOut = Duration(milliseconds: 520);
  static const Duration teaseBack = Duration(milliseconds: 420);

  /// How far the beat leans the card toward its back, as a fraction of the
  /// half-turn a flip travels: `0.09` ≈ 16°. Enough to read as the card turning
  /// (and to show it has a second side), not enough to look like it is opening
  /// by itself — the beat hints, the tap does.
  static const double teaseFraction = 0.09;

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
    with TickerProviderStateMixin {
  /// The hint's text size, as a fraction of the card's width — the same "sized
  /// from the card, not in pixels" rule every other piece of type here follows,
  /// so it stays a small label on any cell.
  static const double _hintSizeOfWidth = 0.07;

  /// The hint's own padding, as a fraction of the card's width.
  static const double _hintPadOfWidth = 0.035;

  /// The hint's inset from the card's left and bottom edges, as a fraction of
  /// the width: the bottom-left corner is the one piece of the poster with
  /// nothing in it, so the hint lands there and the corner word it is about
  /// stays opposite it.
  static const double _hintInsetOfWidth = 0.05;

  /// How long the hint takes to arrive. Short and once — it is a nudge, not an
  /// entrance.
  static const Duration _hintFadeIn = Duration(milliseconds: 220);

  /// 0 is the poster, 1 is the sort list. The controller's value IS the turn
  /// angle, so the two can never disagree about where the card is.
  late final AnimationController _turn = AnimationController(
    vsync: this,
    duration: WorkshopCollectionCard.flipDuration,
  );

  /// The idle beat's motor: an *additive* lean on top of [_turn]'s angle, so the
  /// beat and the flip can never disagree about where the card is — a flip
  /// cancels the beat (see [_reveal]) and the card lands square either way.
  /// Its sequence ENDS at zero, so a finished beat leaves no tilt behind.
  late final AnimationController _tease = AnimationController(
    vsync: this,
    duration: WorkshopCollectionCard.teaseOut + WorkshopCollectionCard.teaseBack,
  );

  /// The beat's shape: a fast ease out to the lean, then an easier settle back.
  late final Animation<double> _leanFraction = TweenSequence<double>([
    TweenSequenceItem(
      tween: CurveTween(curve: Curves.easeOutCubic),
      weight: WorkshopCollectionCard.teaseOut.inMilliseconds.toDouble(),
    ),
    TweenSequenceItem(
      tween: CurveTween(
        curve: Curves.easeInOutCubic,
      ).chain(Tween(begin: 1.0, end: 0.0)),
      weight: WorkshopCollectionCard.teaseBack.inMilliseconds.toDouble(),
    ),
  ]).animate(_tease);

  /// One beat's worth of stillness ahead of the next lean. A [Timer], not a
  /// repeating controller, so nothing is animating between beats at all.
  Timer? _teaseTimer;

  bool _reducedMotion = false;

  /// Which face is on top. Swapped at the half-way point — the moment the card
  /// is edge-on and neither face is visible — so the back is never seen
  /// mirrored, and a face is built only when the card actually passes over.
  bool _back = false;

  /// The first-run hint. `_hintVisible` is the chip's own gate (it is mounted
  /// only while it has a turn left, so "retired" and "faded to nothing" cannot
  /// be confused), and `_hintSpent` is the store's — the flag is written once,
  /// whether the hint timed out or the customer got there first.
  bool _hintVisible = false;
  bool _hintSpent = false;
  Timer? _hintTimer;

  @override
  void initState() {
    super.initState();
    _turn.addListener(_onTurn);
    _turn.addStatusListener(_onTurnStatus);
    _loadHint();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The setting can change while the card is mounted, so it is re-read here
    // rather than latched in `initState`.
    _reducedMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (_reducedMotion) {
      _stopTease();
    } else {
      // Guarded inside `_scheduleTease`, so re-entering this method cannot stack
      // two beats on one card.
      _scheduleTease();
    }
  }

  @override
  void dispose() {
    _teaseTimer?.cancel();
    _hintTimer?.cancel();
    _turn.removeListener(_onTurn);
    _turn.removeStatusListener(_onTurnStatus);
    _turn.dispose();
    _tease.dispose();
    super.dispose();
  }

  void _onTurn() {
    final back = _turn.value >= 0.5;
    if (back != _back) setState(() => _back = back);
  }

  /// The beat belongs to the poster face only: a settled turn to the back stops
  /// it, and a settled turn back to the poster starts it again.
  void _onTurnStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _stopTease();
    } else if (status == AnimationStatus.dismissed) {
      _scheduleTease();
    }
  }

  // ── The idle beat ─────────────────────────────────────────────────────

  /// One beat = [WorkshopCollectionCard.teaseHold] of stillness, then the lean
  /// and the settle. Chained through [_onTeaseEnd], so it loops for as long as
  /// the poster is the face showing.
  void _scheduleTease() {
    if (_teaseTimer != null || _reducedMotion || _back || _turn.value != 0) {
      return;
    }
    _teaseTimer = Timer(WorkshopCollectionCard.teaseHold, _startTease);
  }

  void _startTease() {
    _teaseTimer = null;
    if (!mounted || _reducedMotion || _back || _turn.value != 0) return;
    _tease.forward(from: 0).whenComplete(_onTeaseEnd);
  }

  void _onTeaseEnd() {
    if (!mounted) return;
    // Runs too when the beat is cut short (a tap, a flip to the back) — which is
    // exactly when the next one must NOT be scheduled, so the reschedule is
    // gated on the same conditions as the start.
    if (_reducedMotion || _back || _turn.value != 0) return;
    _scheduleTease();
  }

  /// Cancels the beat and puts the card back square. Called before every flip:
  /// the beat is a hint, never a state, and a tap landing mid-lean must not
  /// leave the card resting a few degrees off square.
  void _stopTease() {
    _teaseTimer?.cancel();
    _teaseTimer = null;
    if (_tease.isAnimating) _tease.stop();
    if (_tease.value != 0) _tease.value = 0;
  }

  // ── The first-run hint ────────────────────────────────────────────────

  /// Arms the hint on the first mount of a customer's first run — and never
  /// again once the flag is stored. The card is usable the whole time the store
  /// is answering (the flag is only ever an *addition*), so nothing here blocks
  /// a build or a tap.
  Future<void> _loadHint() async {
    final seen = await WorkshopSortHintService.instance.hasBeenSeen();
    if (!mounted || seen) return;
    // Used while the store was still answering (the customer flipped the card in
    // its first frames): they have learnt it, so the hint is spent without ever
    // being shown — see [_retireHint].
    if (_hintSpent) return;
    setState(() => _hintVisible = true);
    _hintTimer = Timer(WorkshopCollectionCard.hintLifetime, _retireHint);
  }

  /// Spends the hint: it leaves the card, and the store is told once.
  void _retireHint() {
    _hintTimer?.cancel();
    _hintTimer = null;
    if (_hintVisible) setState(() => _hintVisible = false);
    if (_hintSpent) return;
    _hintSpent = true;
    // Fire-and-forget on purpose: a failed write must never hold up the flip
    // that is happening right now (see [WorkshopSortHintService].
    WorkshopSortHintService.instance.markSeen();
  }

  void _reveal() {
    // The beat is a hint, never a state (see [_stopTease]), and a card being
    // opened spends the hint that taught it — whether or not it was still on
    // screen when the finger landed.
    _stopTease();
    _retireHint();
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
    // over (and the hint still arrives), it just does not animate there.
    // Re-read here as well as in `didChangeDependencies`, because the setting
    // can change while the card is mounted.
    final reducedMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    _turn.duration = reducedMotion
        ? Duration.zero
        : WorkshopCollectionCard.flipDuration;

    return Container(
      // The lift — and it is deliberately OUTSIDE the turn: it is the shadow the
      // card casts on the page, so it stays where it is while the card turns
      // over above it (the same trick the price tape's shadow uses). Collapses
      // to nothing on dark, where `productCardShadow` is empty and raised
      // surfaces separate by tone instead.
      decoration: BoxDecoration(
        borderRadius: AppConstants.productCardRadius,
        boxShadow: AppConstants.productCardShadow,
      ),
      // The beat's ticker lives under this so a covered route mutes it, and
      // between beats there is nothing animating at all (the stillness is a
      // Timer). Disposal cancels it outright.
      child: TickerMode(
        enabled: !reducedMotion,
        child: AnimatedBuilder(
          animation: Listenable.merge([_turn, _tease]),
          // The face is the builder's `child`: a turn repaints a transform
          // instead of rebuilding the poster (or the list) on every frame, and a
          // new face is built only when the card passes the half-way point.
          child: _back ? _sortFace() : _posterFace(),
          builder: (context, child) => Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              // A little perspective, or a card turning over reads as a card
              // being squashed rather than turned.
              ..setEntry(3, 2, 0.0015)
              // The turn, PLUS the idle beat's lean: one is the state and the
              // other is a hint, and they add rather than fight (the beat is
              // cancelled the moment a flip starts — see [_reveal]).
              ..rotateY(
                (_turn.value +
                        _leanFraction.value *
                            WorkshopCollectionCard.teaseFraction) *
                    math.pi,
              ),
            child: _back
                // The back is mounted rotated by the other half turn, so it
                // faces the customer when the card has been turned all the way
                // over.
                ? Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()..rotateY(math.pi),
                    child: child,
                  )
                : child,
          ),
        ),
      ),
    );
  }

  /// The poster, with the first-run hint over it.
  ///
  /// The hint is an overlay (the same `Stack` + `Positioned` + `IgnorePointer`
  /// shape the product card gives the hang tag and the price tape): it never
  /// takes a line from the poster's copy, and a tap on it still reaches the card
  /// — the hint is a label for the card, not a second control on it.
  Widget _posterFace() {
    return LayoutBuilder(
      builder: (context, card) {
        final width = card.maxWidth;
        return Stack(
          fit: StackFit.expand,
          children: [
            FitCard(
              lines: WorkshopCollectionCard.titleLines,
              // No inner inset: the four words are the design, and the block
              // they make is the card — the same full bleed the size poster
              // uses.
              padding: 0,
              // The short form: the corner of a cell has room for `Low to
              // High`, and it is the word this card will keep showing once it
              // is chosen.
              footerLabel: sortModeShortLabel(widget.sort),
              semanticsLabel:
                  'The Workshop Collection, sorted by '
                  '${sortModeLabel(widget.sort)}. Double tap to change sort.',
              onTap: _reveal,
            ),
            if (_hintVisible)
              Positioned(
                left: width * _hintInsetOfWidth,
                bottom: width * _hintInsetOfWidth,
                child: IgnorePointer(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: 1),
                    duration: _reducedMotion
                        ? Duration.zero
                        : _hintFadeIn,
                    curve: Curves.easeOut,
                    builder: (context, t, child) =>
                        Opacity(opacity: t, child: child),
                    // Redundant for a reader: the card's own label already ends
                    // "Double tap to change sort", and a second announcement of
                    // the same instruction is noise.
                    child: ExcludeSemantics(
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: width * _hintPadOfWidth,
                          vertical: width * _hintPadOfWidth * 0.55,
                        ),
                        decoration: BoxDecoration(
                          color: AppConstants.primary.withValues(alpha: 0.10),
                          borderRadius: AppConstants.stadiumRadius,
                          border: Border.all(
                            color: AppConstants.primary.withValues(alpha: 0.28),
                            width: FitCard.edgeWidth,
                          ),
                        ),
                        child: Text(
                          WorkshopCollectionCard.hintLabel,
                          maxLines: 1,
                          softWrap: false,
                          textScaler: TextScaler.noScaling,
                          style: AppConstants.bodyStyle(
                            fontSize: width * _hintSizeOfWidth,
                            fontWeight: FontWeight.bold,
                            color: AppPalette.of(
                              AppBrightness.current,
                            ).primaryInk,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _sortFace() {
    return LayoutBuilder(
      builder: (context, card) {
        // Everything below is derived from the card's width, so the list scales
        // with its cell instead of overflowing a shorter one.
        final width = card.maxWidth;
        final pad = width * WorkshopCollectionCard._backPaddingOfWidth;
        final labelSize = width * WorkshopCollectionCard._backLabelSizeOfWidth;

        return Material(
          // The card's own back: same fill, same edge, same radius, so a turn
          // reads as one card rather than as two widgets. Both come from
          // `FitCard`'s defaults — the page tone and the poster's own thin line
          // ([FitCard.edgeColor] at [FitCard.edgeWidth]), which is what draws
          // the tile now that the fill is the page itself.
          color: AppConstants.surfaceLight,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: AppConstants.productCardRadius,
            side: BorderSide(
              color: FitCard.edgeColor,
              width: FitCard.edgeWidth,
            ),
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
