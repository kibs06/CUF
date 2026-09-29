import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The seller's product **action sheet** — the long-press menu on Manage
/// Products, and the second door into the 3D-fitting pipeline (roadmap V2.10).
///
/// Two things are pinned here, and both are invisible until they are wrong on a
/// device.
///
/// **The sheet scrolls.** It shipped with a `Column` under Material's default
/// 9/16 height cap. Adding the 3D-fitting row (a two-line entry) pushed the
/// content 6.6 px past that cap, and a `Column` that exceeds its constraints
/// does not shrink or scroll — it paints the yellow-and-black overflow stripe
/// across its last row, which on this sheet is *Delete*. The row count here is
/// decided by features elsewhere in the app (this one, and whatever V2.x adds
/// next), so the sheet has to be able to scroll rather than be tuned to fit a
/// particular list. The three ListView settings below are asserted because each
/// one is a silent regression: a vertical `ListView` on Android adopts the app's
/// `PrimaryScrollController` unless told not to, and takes `MediaQuery`'s bottom
/// inset as scroll padding unless given an explicit zero — which would double
/// the space `SafeArea` already accounts for.
///
/// **The row is in the right place, behind the right switch.** It sits between
/// "Put on sale" and "Hide from customers", and the whole block — the row and its
/// divider — is behind `AppConstants.shoeModelRequestEnabled`, so a build with
/// the switch off renders the sheet that existed before the feature. A row that
/// escaped the gate would write through an RPC whose table may not be there;
/// `AppConstants` carries that reasoning in full.
///
/// These tests read the source, because the screen cannot be built in a widget
/// test (`Supabase.instance` is not initialized in the test environment) — the
/// same constraint `seller_audience_nudge_test.dart` and
/// `offscreen_timer_pause_contract_test.dart` work under for this file.
void main() {
  const path = 'lib/screens/seller/manage_products_screen.dart';

  late String code;

  setUpAll(() {
    code = withoutLineComments(File(path).readAsStringSync());
  });

  /// The action sheet's own method: from its signature to the next member, so a
  /// guard below cannot be satisfied by a match somewhere else in a 2,000-line
  /// file.
  String sheet() => _slice(code, 'void _showProductActions(', 'Widget _productThumbnail(');

  group('the action sheet can scroll instead of overflowing', () {
    test('its content is a scrolling list, not a Column', () {
      // Scoped to the sheet's OWN child — from its padding to the start of its
      // children — because a `Column` is legitimate deeper inside (the header's
      // name/status stack is one) and an un-scoped search would either fail on
      // that or have to be loosened into saying nothing.
      final outer = _slice(
        sheet(),
        'padding: const EdgeInsets.fromLTRB(20, 12, 20, 20)',
        'children: [',
      );
      expect(
        outer,
        contains('child: ListView('),
        reason: 'the action sheet must lay its rows out in a scrollable, not a '
            'Column — a Column that exceeds the sheet\'s height cap paints the '
            'overflow stripe over the last row (Delete) instead of scrolling',
      );
      expect(
        outer,
        isNot(contains('child: Column(')),
        reason: 'a Column here is the 2026-09-29 overflow: the 3D fitting row '
            'made the content taller than Material\'s 9/16 cap',
      );
    });

    test('the modal is allowed to grow past the 9/16 cap', () {
      expect(
        sheet(),
        contains('isScrollControlled: true'),
        reason: 'without it the sheet is capped at 9/16 of the screen, so a '
            'longer action list is scroll-only even when the screen has room',
      );
    });

    test('the list sizes to its content, and owns its scroll position', () {
      final source = sheet();
      // shrinkWrap: the sheet still hugs its content instead of filling the
      // screen — this is what keeps the pre-feature look.
      expect(source, contains('shrinkWrap: true'));
      // primary: false: or the ListView on Android attaches to the app's
      // PrimaryScrollController, which the page underneath may already be using.
      expect(source, contains('primary: false'));
      // padding: EdgeInsets.zero: or it inherits MediaQuery's bottom inset as
      // scroll padding, on top of the SafeArea the sheet already applies.
      expect(source, contains('padding: EdgeInsets.zero'));
    });
  });

  group('the 3D fitting row is placed and gated', () {
    test('it sits between Put on sale and Hide from customers', () {
      final source = sheet();
      final onSale = source.indexOf('Put on sale');
      final tile = source.indexOf('ShoeModelRequestTile(');
      final hide = source.indexOf('Hide from customers');

      expect(onSale, isNot(-1), reason: 'marker "Put on sale" moved or was '
          'renamed — update this test rather than deleting the assertion');
      expect(tile, isNot(-1), reason: 'the action sheet no longer mounts '
          'ShoeModelRequestTile — has the row been moved or removed?');
      expect(hide, isNot(-1), reason: 'marker "Hide from customers" moved or '
          'was renamed');

      expect(
        onSale < tile && tile < hide,
        isTrue,
        reason: 'the request row belongs above Hide/Delete: it is a request to '
            'a person rather than a state toggle',
      );
    });

    test('the whole block is behind the feature switch', () {
      final source = sheet();
      final gate = source.indexOf('if (AppConstants.shoeModelRequestEnabled)');
      final tile = source.indexOf('ShoeModelRequestTile(');

      expect(gate, isNot(-1), reason: 'the row must be inside the '
          '`shoeModelRequestEnabled` gate — it writes through an RPC whose '
          'table is only there when the feature was rolled out');
      expect(
        gate < tile,
        isTrue,
        reason: 'the gate has to wrap the row, not follow it',
      );
      // The divider is inside the same spread, so "off" means the sheet that
      // shipped before the feature — no orphan rule under "Put on sale".
      expect(
        source.substring(gate, tile).contains('...['),
        isTrue,
        reason: 'the gate opens a spread whose first element is the row',
      );
    });
  });
}

/// The text from [start] up to [end] — used to assert *where* something is
/// applied rather than merely that the file mentions it somewhere.
String _slice(String source, String start, String end) {
  final from = source.indexOf(start);
  expect(from, isNot(-1), reason: 'marker "$start" not found — was the code '
      'moved or the structure renamed? If so, update this test to match rather '
      'than deleting the assertion.');
  final to = source.indexOf(end, from + start.length);
  return source.substring(from, to == -1 ? source.length : to);
}

/// Drops `//` comments so the guards above cannot be satisfied by prose — this
/// file's own explanatory comment names both `Column` and the overflow stripe.
String withoutLineComments(String source) => source
    .split('\n')
    .map((line) {
      final i = line.indexOf('//');
      return i == -1 ? line : line.substring(0, i);
    })
    .join('\n');
