import 'package:flutter/material.dart';

/// An [IndexedStack] whose children are built **on first visit**, then kept.
///
/// **Why this exists.** An `IndexedStack` keeps every child it is handed
/// mounted, so passing it all of a shell's tabs at once constructs every one of
/// them — running all of their `initState`s, and therefore all of their data
/// fetches, on the first frame of the session. For a shell with six data-heavy
/// tabs that is six concurrent loaders competing with the tab the user is
/// actually looking at.
///
/// This widget keeps the `IndexedStack`'s state-preservation guarantees while
/// removing the eager fan-out: a slot renders nothing until its index has been
/// visited at least once, and from then on receives the same widget instance on
/// every build, so the element is reused and the page's `State` (loaded data,
/// scroll offset, filters, open sheets) survives — exactly as with a plain
/// `IndexedStack`.
///
/// The `PageView`-based shells (`SellerShell`, `CustomerShell`) get the same
/// effect from `KeepAlivePage`, which is the equivalent primitive for a lazy
/// *sliver* host. This is the one for a host that switches by index instead of
/// by scrolling.
///
/// Note that unlike its callers, this widget does not publish an `ActiveTab`:
/// hosting and visibility-signalling are separate concerns, and a page here is
/// never rebuilt on a switch either — so a child that needs a re-entry signal
/// still relies on the shell publishing one above this widget.
class LazyIndexedStack extends StatefulWidget {
  const LazyIndexedStack({
    super.key,
    required this.index,
    required this.children,
    this.sizing = StackFit.loose,
    this.alignment = AlignmentDirectional.topStart,
  });

  /// Index of the child currently shown. Selecting an index is what causes that
  /// child to be built for the first time.
  final int index;

  /// The tabs, in bottom-nav order. Pass the SAME instances on every build
  /// (e.g. from a `const` list) — replacing an instance rebuilds that page from
  /// scratch and discards its state.
  final List<Widget> children;

  final StackFit sizing;
  final AlignmentGeometry alignment;

  @override
  State<LazyIndexedStack> createState() => _LazyIndexedStackState();
}

class _LazyIndexedStackState extends State<LazyIndexedStack> {
  /// Indexes that have been shown at least once.
  ///
  /// Seeded with the child shown on the first build, which is the only one that
  /// must exist immediately.
  late final Set<int> _visited = {widget.index};

  @override
  void didUpdateWidget(LazyIndexedStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Recording the newly selected index here (rather than in the parent's
    // setState) means the real child replaces its placeholder during the very
    // frame that first shows it — no second rebuild, and no empty frame where
    // the tab would appear blank.
    _visited.add(widget.index);
  }

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: widget.index,
      sizing: widget.sizing,
      alignment: widget.alignment,
      children: [
        for (var i = 0; i < widget.children.length; i++)
          if (_visited.contains(i)) widget.children[i] else const SizedBox.shrink(),
      ],
    );
  }
}
