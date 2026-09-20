import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Two equal columns, packed the way a masonry grid packs them: every child
/// goes into whichever column is currently **shorter**, so the columns stay
/// level instead of the layout turning into a row-aligned table.
///
/// The reason this exists rather than `MasonryGridView.count`: the last two
/// children are the **closing pair** and they are placed, not packed. A pinned
/// closing row (both cells at the grid's bottom) can only ever start at the
/// *taller* column's bottom, so the shorter column's leftover height shows up
/// as a hole above the row — a column that visibly breaks. Here each closing
/// cell hangs off its **own** column instead:
///
///  * the **anchor** (second-to-last child) always opens the LEFT column,
///  * the **closer** (last child) always takes the RIGHT column, directly under
///    that column's last child, and is stretched or squeezed so that its bottom
///    lands on the anchor's bottom — so the grid closes on one clean edge
///    whatever the flow above did.
///
/// Heights are read from the children themselves as they are laid out, so
/// nothing here guesses at a card's size from its aspect ratio.
class TwoColumnMasonry extends MultiChildRenderObjectWidget {
  /// [margin] is the side inset, [gutter] the seam between the columns and
  /// between the stacked cells — the page's own pair of tokens.
  const TwoColumnMasonry({
    super.key,
    required this.margin,
    required this.gutter,
    this.closingCount = 0,
    required super.children,
  }) : assert(closingCount == 0 || closingCount == 2, 'the closing pair is two cells'),
       assert(
         closingCount == 0 || children.length >= 2,
         'a closing pair needs an anchor and a closer',
       );

  final double margin;
  final double gutter;

  /// 0 for a plain grid, or 2 when the last two children are the closing pair.
  final int closingCount;

  /// The grid's column count. Stated once so every surface that packs cells
  /// this way agrees on it.
  static const int columnCount = 2;

  /// The shortest the closer may be squeezed, as a fraction of one column's
  /// width. Only reachable when the right column's content already reaches
  /// deeper than the anchor's bottom — matching the bottoms exactly would then
  /// demand a card of nothing, and a legible poster is worth more than a
  /// matched edge in that corner case.
  static const double minCloserWidthFactor = 0.6;

  // `RenderBox` (not the private render object) keeps this widget's public API
  // free of a private type; the object handed in is always our own.
  @override
  RenderBox createRenderObject(BuildContext context) => _RenderTwoColumnMasonry(
    margin,
    gutter,
    closingCount,
    Directionality.maybeOf(context) ?? TextDirection.ltr,
  );

  @override
  void updateRenderObject(BuildContext context, RenderBox renderObject) {
    (renderObject as _RenderTwoColumnMasonry)
      ..margin = margin
      ..gutter = gutter
      ..closingCount = closingCount
      ..textDirection = Directionality.maybeOf(context) ?? TextDirection.ltr;
  }
}

class _CellParentData extends ContainerBoxParentData<RenderBox> {}

/// Where every cell ended up, for one pass over the children.
class _Geometry {
  const _Geometry(this.offsets, this.size);

  final Map<RenderBox, Offset> offsets;
  final Size size;
}

class _RenderTwoColumnMasonry extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _CellParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _CellParentData> {
  _RenderTwoColumnMasonry(
    this._margin,
    this._gutter,
    this._closingCount,
    this._textDirection,
  );


  double _margin;
  double get margin => _margin;
  set margin(double value) {
    if (value == _margin) return;
    _margin = value;
    markNeedsLayout();
  }

  double _gutter;
  double get gutter => _gutter;
  set gutter(double value) {
    if (value == _gutter) return;
    _gutter = value;
    markNeedsLayout();
  }

  int _closingCount;
  int get closingCount => _closingCount;
  set closingCount(int value) {
    if (value == _closingCount) return;
    _closingCount = value;
    markNeedsLayout();
  }

  TextDirection _textDirection;
  TextDirection get textDirection => _textDirection;
  set textDirection(TextDirection value) {
    if (value == _textDirection) return;
    _textDirection = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _CellParentData) {
      child.parentData = _CellParentData();
    }
  }

  double _columnLeft(int column, double width, double cellWidth) {
    final left = _margin + column * (cellWidth + _gutter);
    // The first cell still opens the grid's leading edge, which an RTL page
    // reads from the right.
    return _textDirection == TextDirection.rtl
        ? width - left - cellWidth
        : left;
  }

  /// Lays a cell out at the column's width and reports the height it came back
  /// with. [height] pins a cell that is being fitted to a box of its own (the
  /// closer); everything else is content-sized.
  ///
  /// [dry] performs the same measurement without writing anything to the child,
  /// which is what [computeDryLayout] runs on.
  double _measure(
    RenderBox child,
    double cellWidth, {
    required bool dry,
    double? height,
  }) {
    final childConstraints = BoxConstraints.tightFor(
      width: cellWidth,
      height: height,
    );
    if (dry) return child.getDryLayout(childConstraints).height;
    child.layout(childConstraints, parentUsesSize: true);
    return child.size.height;
  }

  _Geometry _computeGeometry({
    required BoxConstraints constraints,
    required bool dry,
  }) {
    final columns = TwoColumnMasonry.columnCount;
    final cellWidth =
        (constraints.maxWidth - columns * _margin - (columns - 1) * _gutter) /
        columns;
    final offsets = <RenderBox, Offset>{};
    final bottoms = List<double>.filled(columns, 0);

    final closer = _closingCount == 2 ? lastChild : null;
    final anchor = closer == null ? null : childBefore(closer);
    final flowCount = childCount - _closingCount;

    var placed = 0;
    for (
      RenderBox? child = firstChild;
      child != null && placed < flowCount;
      child = childAfter(child), placed++
    ) {
      final height = _measure(child, cellWidth, dry: dry);
      // Shortest column wins; a tie opens the left one, so the first cell (the
      // section's poster) lands top-left as the design expects.
      final column = bottoms[0] <= bottoms[1] ? 0 : 1;
      offsets[child] = Offset(
        _columnLeft(column, constraints.maxWidth, cellWidth),
        bottoms[column],
      );
      bottoms[column] += height + _gutter;
    }

    if (anchor != null && closer != null) {
      final anchorHeight = _measure(anchor, cellWidth, dry: dry);
      final anchorTop = bottoms[0];
      final closerTop = bottoms[1];
      final closerHeight = _closerHeight(
        anchorBottom: anchorTop + anchorHeight,
        closerTop: closerTop,
        cellWidth: cellWidth,
      );
      _measure(closer, cellWidth, dry: dry, height: closerHeight);

      final width = constraints.maxWidth;
      offsets[anchor] = Offset(_columnLeft(0, width, cellWidth), anchorTop);
      offsets[closer] = Offset(_columnLeft(1, width, cellWidth), closerTop);
      bottoms[0] = anchorTop + anchorHeight + _gutter;
      bottoms[1] = closerTop + closerHeight + _gutter;
    }

    // Each column already carries a trailing gutter; the grid's own bottom edge
    // is the deepest cell, not the gutter under it.
    final tallest = bottoms[0] > bottoms[1] ? bottoms[0] : bottoms[1];
    return _Geometry(
      offsets,
      Size(constraints.maxWidth, childCount == 0 ? 0 : tallest - _gutter),
    );
  }

  double _closerHeight({
    required double anchorBottom,
    required double closerTop,
    required double cellWidth,
  }) {
    final needed = anchorBottom - closerTop;
    final minimum = cellWidth * TwoColumnMasonry.minCloserWidthFactor;
    return needed < minimum ? minimum : needed;
  }

  @override
  void performLayout() {
    assert(
      constraints.hasBoundedWidth,
      'a two-column grid needs a bounded width to size its columns',
    );
    final geometry = _computeGeometry(constraints: constraints, dry: false);
    for (
      RenderBox? child = firstChild;
      child != null;
      child = childAfter(child)
    ) {
      (child.parentData! as _CellParentData).offset = geometry.offsets[child]!;
    }
    size = constraints.constrain(geometry.size);
  }

  /// Mirrors [performLayout] from the children's dry layouts. Cards that carry a
  /// `LayoutBuilder` (the poster cells) cannot answer a dry layout, and Flutter
  /// marks the whole computation invalid in that case — the same thing that
  /// happens to any ancestor of a `LayoutBuilder` that tries.
  @override
  Size computeDryLayout(BoxConstraints constraints) => _computeGeometry(
    constraints: constraints,
    dry: true,
  ).size;

  @override
  void paint(PaintingContext context, Offset offset) {
    defaultPaint(context, offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
