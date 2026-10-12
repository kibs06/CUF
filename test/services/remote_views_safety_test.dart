import 'dart:io';

import 'package:app/models/customer_widget_data.dart';
import 'package:flutter_test/flutter_test.dart';

/// Everything a widget layout is allowed to contain.
///
/// Android's `RemoteViews` does not inflate arbitrary layouts — it inflates from
/// a **fixed allowlist of fully-qualified classes**, and anything else throws
/// `InflateException` in the *launcher's* process when the widget is placed.
///
/// This is the class of bug that shipped in this feature's first build: the
/// divider between the revenue block and the counters was written as a plain
/// `<View>`, the layout compiled and the APK built and installed cleanly, and
/// the seller's home screen then said **"Problem loading widget"** with the only
/// clue in logcat:
///
///     InflateException: Binary XML file line #69 in
///     com.solevision.app:layout/seller_widget:
///     Error inflating class android.view.View
///
/// Nothing else in the pipeline can catch that — not `flutter analyze`, not
/// `flutter build apk`, not the widget's own unit tests — because the file is
/// valid XML and a valid Android layout, just not a valid *RemoteViews* layout.
/// So the check lives here, on the allowlist, where it fails in a test instead of
/// on someone's home screen.
///
/// Source: https://developer.android.com/develop/ui/views/appwidgets/layouts
const Set<String> remoteViewsInflatable = {
  'FrameLayout',
  'LinearLayout',
  'RelativeLayout',
  'GridLayout',
  'TextView',
  'ImageView',
  'ImageButton',
  'Button',
  'ProgressBar',
  'Chronometer',
  'AnalogClock',
  'ViewFlipper',
  'AdapterViewFlipper',
  'ListView',
  'GridView',
  'StackView',
  'ViewStub',
};

/// The widget layouts in this repo. Every one of them is inflated by a launcher,
/// so every one of them is bound by the allowlist above.
///
/// ⚠️ **This list is the whole point of the size tiers.** The widget draws a
/// different layout per size AND per role (see `SellerWidgetProvider.WidgetTier`),
/// so every file added here inherits the scan automatically — and a layout that
/// someone forgets to add to this list is a layout nothing checks. A test below
/// reads the provider's own source and fails if it names a layout missing here,
/// which is what caught the tall tier needing an entry of its own.
const List<String> sellerWidgetLayouts = [
  'android/app/src/main/res/layout/seller_widget_small.xml',
  'android/app/src/main/res/layout/seller_widget_tall.xml',
  'android/app/src/main/res/layout/seller_widget_medium.xml',
  'android/app/src/main/res/layout/seller_widget_full.xml',
];

/// The same tile drawn for a customer instead: ONE product card, designed for a
/// 3×3 square. A single file, because the customer side has no tiers — the card is
/// `wrap_content` and centred, so what changes with the tile's size is the space
/// around the card and not the layout. The two files this replaced (a stacked list
/// and a row of cells, chosen by a tier plus an aspect ratio) are gone with the
/// three-product design: the last one of them is what drew 106×563 slivers of
/// photographs into a portrait tile on a real phone.
const List<String> customerWidgetLayouts = [
  'android/app/src/main/res/layout/customer_widget_card.xml',
];

const List<String> widgetLayouts = [
  ...sellerWidgetLayouts,
  ...customerWidgetLayouts,
];

/// The tier that draws the full six-cell grid. The grid's structure tests below
/// apply to this file alone: the smaller tiers deliberately hold fewer cells.
const String fullWidgetLayout =
    'android/app/src/main/res/layout/seller_widget_full.xml';

/// The narrow-but-tall tier. Its shape tests apply to this file alone for the
/// same reason as [fullWidgetLayout]'s.
const String tallWidgetLayout =
    'android/app/src/main/res/layout/seller_widget_tall.xml';

void main() {
  for (final path in widgetLayouts) {
    group('$path is RemoteViews-safe', () {
      final raw = File(path).readAsStringSync();

      // Comments must go first, and the reason is not hypothetical: the fix for
      // the `<View>` bug documents itself by *naming* `<View>` in a comment, and
      // a naive scan would read that as another offending element and fail the
      // test that the comment is explaining.
      final xml = raw.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');

      final tags = RegExp(r'<([A-Za-z][A-Za-z0-9_.]*)')
          .allMatches(xml)
          .map((m) => m.group(1)!)
          // Closing tags (`</LinearLayout>`) repeat the element name; the set
          // makes that harmless either way.
          .toSet();

      test('the layout has views to check at all', () {
        // Guards the guard: if the regex or the path ever stops matching, the
        // allowlist assertion below would pass over an empty set and quietly
        // protect nothing.
        expect(
          tags,
          isNotEmpty,
          reason: 'no elements were found in $path — this test is not checking '
              'anything',
        );
      });

      test('every element is a class RemoteViews can inflate', () {
        expect(
          tags.difference(remoteViewsInflatable),
          isEmpty,
          reason: 'these elements are not on RemoteViews\' allowlist and will '
              'throw InflateException in the launcher, showing "Problem loading '
              'widget" on a real phone: '
              '${tags.difference(remoteViewsInflatable).join(', ')}',
        );
      });
    });
  }

  group('the metric grid is complete and its columns align', () {
    // Two design faults from the first working build, both of which were only
    // visible on the phone:
    //
    //   * the two counter rows held a DIFFERENT number of cells (three then
    //     two), each weighted equally, so the second row's columns started at
    //     unrelated x positions and the block read as broken alignment;
    //   * `seller_pending_reservations` was written by Dart on every refresh and
    //     never displayed, because the layout had no cell for it.
    //
    // Neither is a compile error and neither can be seen from a test harness —
    // they are properties of the layout FILE, which is why they are asserted
    // here rather than left to a screenshot.
    final raw = File(fullWidgetLayout).readAsStringSync();

    /// Each metric cell carries the pill background, so counting pills counts
    /// cells. That is a more robust handle than parsing LinearLayout nesting.
    int pillsIn(String text) =>
        RegExp('@drawable/seller_widget_pill').allMatches(text).length;

    const metricIds = [
      'widget_orders',
      'widget_customs',
      'widget_holdings',
      'widget_requests',
      'widget_low_stock',
      'widget_unread',
    ];

    test('every metric the payload carries has a cell', () {
      // Six: orders, custom, holds, requests, low stock, unread. If the payload
      // grows a seventh number, this fails until the tile shows it — which is the
      // check that would have caught `requests` being fetched for nothing.
      expect(
        pillsIn(raw),
        metricIds.length,
        reason: 'the payload carries ${metricIds.length} metrics and the layout '
            'draws a different number of cells',
      );
    });

    test('each metric id appears exactly once', () {
      for (final id in metricIds) {
        expect(
          RegExp('android:id="@\\+id/$id"').allMatches(raw).length,
          1,
          reason: '$id must have exactly one cell — a duplicate would mean two '
              'views compete for the same id and the provider fills only one',
        );
      }
    });

    test('the two grid rows hold the same number of cells', () {
      // The ragged-column regression, asserted directly. The markers are the
      // "Row 1" / "Row 2" comments in the layout; `indexOf` is case-sensitive, so
      // Row 2's prose mentioning "row 1" cannot be mistaken for the Row 1 marker.
      final row1 = raw.indexOf('Row 1');
      final row2 = raw.indexOf('Row 2');
      expect(row1, greaterThan(-1), reason: 'the "Row 1" marker is gone');
      expect(
        row2,
        greaterThan(row1),
        reason: 'the "Row 2" marker is gone',
      );

      final firstRow = pillsIn(raw.substring(row1, row2));
      final secondRow = pillsIn(raw.substring(row2));
      expect(
        firstRow,
        secondRow,
        reason: 'the rows hold $firstRow and $secondRow cells — unequal rows are '
            'exactly what made the columns look misaligned on the launcher',
      );
      expect(firstRow, 3, reason: 'three columns is what the sizing assumes');
    });
  });

  group('every size tier is covered by the scan', () {
    // The tier list lives in Kotlin and the scan list lives here, so nothing but
    // this test connects them. Adding a fourth layout to the provider and not to
    // `widgetLayouts` would leave it the only widget layout in the app that no
    // test protects — and RemoteViews violations there are exactly the ones that
    // reach a user's home screen as "Problem loading widget".
    final provider = File(
      'android/app/src/main/kotlin/com/solevision/app/SellerWidgetProvider.kt',
    ).readAsStringSync();

    test('the provider names exactly the layouts this scan checks', () {
      // Both roles' layouts: the tile draws a customer's product feed from the
      // same provider, so a `customer_widget_*` file left out of the scan list
      // would be the one layout nothing protects.
      final referenced = RegExp(r'R\.layout\.((?:seller|customer)_widget_[a-z_]+)')
          .allMatches(provider)
          .map((m) => 'android/app/src/main/res/layout/${m.group(1)}.xml')
          .toSet();

      expect(referenced, isNotEmpty, reason: 'no layouts found in the provider');
      expect(
        referenced.difference(widgetLayouts.toSet()),
        isEmpty,
        reason: 'the provider draws a layout that this test does not scan, so '
            'its RemoteViews violations would only surface on a phone',
      );
      expect(
        widgetLayouts.toSet().difference(referenced),
        isEmpty,
        reason: 'this test scans a layout the provider never draws',
      );
    });

    test('the smallest tier is reachable, and the range is resizable', () {
      final info = File(
        'android/app/src/main/res/xml/seller_widget_info.xml',
      ).readAsStringSync();
      // A minimum larger than 2 cells would make the small tier dead code: it
      // could never be selected, because no instance could be that small.
      expect(
        info,
        contains('android:minResizeWidth="110dp"'),
        reason: 'without a 2-cell minResizeWidth the launcher offers no handle '
            'that reaches the small tier',
      );
      expect(info, contains('android:resizeMode="horizontal|vertical"'));
      expect(
        info,
        contains('android:initialLayout="@layout/seller_widget_full"'),
        reason: 'the initial layout must be the tier an unknown size falls back '
            'to, or a fresh widget flashes the wrong design',
      );
    });
  });

  group('the tall tier stacks rows instead of stretching the square', () {
    // The fault this tier was added for, and it was only visible on a phone: a
    // 2×3 tile has extra HEIGHT, and no tier spent it — a tile dragged taller
    // drew the 2×2, which is the same four lines with a hole under them and
    // nothing on screen to say the size had been noticed. Asserting the shape
    // that fixes it belongs here because "the tall layout is really just the
    // small one again" is not visible to any compiler or analyser.
    final raw = File(tallWidgetLayout).readAsStringSync();

    test('it carries the medium tier\'s three metrics, and the clock', () {
      for (final id in const [
        'widget_orders',
        'widget_low_stock',
        'widget_unread',
        'widget_updated',
      ]) {
        expect(
          RegExp('android:id="@\\+id/$id"').allMatches(raw).length,
          1,
          reason: '$id must appear exactly once in the tall tier',
        );
      }

      // Three rows, one pill each. Six pills would mean the medium tier's cells
      // were relabelled as rows, which is the copy-this-file mistake.
      expect(
        RegExp('@drawable/seller_widget_pill').allMatches(raw).length,
        3,
        reason: 'the tall tier is three stacked rows, not a six-cell grid',
      );
    });

    test('the counts hold a fixed column, so the labels share a left edge', () {
      for (final id in const [
        'widget_orders',
        'widget_low_stock',
        'widget_unread',
      ]) {
        final cell = RegExp(
          '<TextView\\s+android:id="@\\+id/$id".*?/>',
          dotAll: true,
        ).firstMatch(raw)?.group(0);
        expect(cell, isNotNull, reason: 'no cell for $id');
        expect(
          cell,
          contains('android:layout_width="34dp"'),
          reason: 'a weighted or wrap_content count would let a two-digit '
              'number shove its label sideways and break the column — the same '
              'ragged-alignment fault the full tier documents',
        );
      }
    });

    test('it can absorb the height it was given', () {
      // The band that spans the slack. Without a weighted container the taller
      // tile is the square layout with a void beneath it, which is the whole
      // reason a second tier exists.
      expect(
        raw,
        contains('android:layout_weight="1"'),
        reason: 'nothing in the tall tier absorbs extra height',
      );
    });
  });

  group('every id the provider fills exists on the layout it fills it on', () {
    // ⚠️ `RemoteViews` SKIPS an action whose view is absent — it does not throw
    // and it does not warn. So a provider that fills `widget_revenue` on a
    // layout with no such view does not crash: it draws a tile with a blank
    // where the money goes, forever, and the only way to notice is to look at
    // the phone. Nothing else in the pipeline relates these two files across
    // the Dart/Kotlin line, so the relation is asserted here.
    //
    // It is per-tier AND per-role on purpose: the tile now has two render paths
    // (a seller's counters, a customer's product feed) and the ids each one fills
    // are read out of its OWN slice of the provider, so this fails if either is
    // ever edited to fill a view its layouts do not have.
    final provider = File(
      'android/app/src/main/kotlin/com/solevision/app/SellerWidgetProvider.kt',
    ).readAsStringSync();

    Set<String> idsIn(String text) => RegExp(r'R\.id\.(\w+)')
        .allMatches(text)
        .map((m) => m.group(1)!)
        .toSet();

    const sellerTiers = {
      'Small': 'android/app/src/main/res/layout/seller_widget_small.xml',
      'Tall': 'android/app/src/main/res/layout/seller_widget_tall.xml',
      'Medium': 'android/app/src/main/res/layout/seller_widget_medium.xml',
      'Full': 'android/app/src/main/res/layout/seller_widget_full.xml',
    };

    /// The source between two markers, or a thrown error.
    ///
    /// Throws rather than asserting: a parse that quietly found nothing would
    /// leave every test below asserting over an empty string — passing while
    /// protecting nothing — and it cannot use `expect` anyway, because this runs
    /// while the group is being DECLARED, where `expect` is illegal and throws
    /// `OutsideTestException`.
    String slice(String from, String to) {
      final start = provider.indexOf(from);
      final end = provider.indexOf(to);
      if (start < 0 || end <= start) {
        throw StateError(
          'the provider no longer contains "$from" → "$to", so the assertions '
          'built on that slice would pass over nothing',
        );
      }
      return provider.substring(start, end);
    }

    /// One span per tier inside [region], from its branch marker to the next.
    Map<String, String> tierSpans(String region, List<String> tiers) {
      final spans = <String, String>{};
      for (var i = 0; i < tiers.length; i++) {
        final start = region.indexOf('WidgetTier.${tiers[i]} -> {');
        if (start < 0) throw StateError('no ${tiers[i]} branch in this region');
        final end = i + 1 < tiers.length
            ? region.indexOf('WidgetTier.${tiers[i + 1]} -> {')
            : region.length;
        if (end <= start) throw StateError('could not bound ${tiers[i]}');
        spans[tiers[i]] = region.substring(start, end);
      }
      return spans;
    }

    final sellerRender = slice('private fun render(', 'private fun renderCustomer(');
    final customerRender =
        slice('private fun renderCustomer(', 'private fun speak(');
    final sellerSpans = tierSpans(sellerRender, sellerTiers.keys.toList());
    // No tier split for the customer path: its layouts are chosen by size but its
    // views are filled by SLOT, and `customerKey(slot, …)` means one branch serves
    // every slot and both layouts — so the whole slice is what both must declare.

    test('each seller tier only fills views its own layout declares', () {
      sellerSpans.forEach((tier, span) {
        final layout = File(sellerTiers[tier]!).readAsStringSync();
        final ids = idsIn(span);
        expect(ids, isNotEmpty, reason: 'the $tier branch fills nothing?');
        for (final id in ids) {
          expect(
            layout,
            contains('android:id="@+id/$id"'),
            reason: 'the $tier branch fills $id, but ${sellerTiers[tier]} has no '
                'such view — RemoteViews skips it silently, so that field would '
                'simply never appear on the tile',
          );
        }
      });
    });

    test('the seller ids outside the tiers are on all four seller layouts', () {
      // The ids the provider touches before the `when` — identity, the hero and
      // the populated/empty pair — are filled at every size, so they have to exist
      // on all four layouts. Derived rather than listed, so moving an id out of the
      // shared preamble into one tier moves it out of this set with it.
      final tierIds =
          sellerSpans.values.map(idsIn).reduce((a, b) => a.union(b));
      final shared = idsIn(sellerRender).difference(tierIds);
      expect(
        shared,
        isNotEmpty,
        reason: 'no shared seller ids were found, so the split above is wrong',
      );

      for (final path in sellerWidgetLayouts) {
        final layout = File(path).readAsStringSync();
        for (final id in shared) {
          expect(
            layout,
            contains('android:id="@+id/$id"'),
            reason: '$id is filled at every seller size, so every seller layout '
                'needs it',
          );
        }
      }
    });

    test('the customer path only fills views the customer layouts declare', () {
      final ids = idsIn(customerRender);
      expect(ids, isNotEmpty, reason: 'the customer slot branch fills nothing?');

      for (final path in customerWidgetLayouts) {
        final layout = File(path).readAsStringSync();
        for (final id in ids) {
          expect(
            layout,
            contains('android:id="@+id/$id"'),
            reason: 'the customer render path fills $id, but $path has no such '
                'view — RemoteViews skips it silently, so that product would '
                'never appear (or never hide) on the tile',
          );
        }
      }
    });

    test('every customer layout carries every product slot', () {
      // The provider fills five views for each slot in the payload, so a layout
      // missing one would fail in the way this file exists to catch: silently.
      // The count is read from `kCustomerWidgetProductSlots` rather than written
      // here, because that is the number the provider mirrors (`CUSTOMER_SLOTS`) and
      // the contract test pins — a layout short a slot is then caught by the two
      // numbers disagreeing rather than by someone remembering to update a list.
      for (final path in customerWidgetLayouts) {
        final layout = File(path).readAsStringSync();
        for (var slot = 1; slot <= kCustomerWidgetProductSlots; slot++) {
          for (final field in const ['product', 'image', 'name', 'price', 'badge']) {
            expect(
              layout,
              contains('android:id="@+id/customer_${field}_$slot"'),
              reason: '$path has no $field slot $slot, so the provider would fill '
                  'a view that is not there',
            );
          }
        }
      }
    });

    test('both roles share one tile skeleton', () {
      // The root, the populated branch and the empty branch are the same three ids
      // in every layout, which is what lets one update path clear a tile of either
      // role. `widget_root` is also the seller path's tap target.
      for (final path in widgetLayouts) {
        final layout = File(path).readAsStringSync();
        for (final id in const ['widget_root', 'widget_content', 'widget_empty']) {
          expect(
            layout,
            contains('android:id="@+id/$id"'),
            reason: '$path is missing $id, which every layout shares',
          );
        }
      }
    });
  });

  group('the customer tile is ONE card, at every size', () {
    // The design the owner asked for, and the fault it replaces — the exact class
    // this file exists for. A 3×3 portrait tile (624×942 px) once drew three cells
    // 154×740 px with each photograph a 106×563 sliver, because the tile's shape was
    // chosen by tier and then by aspect, and the arrangement it picked had to fit a
    // photograph into whatever box was left over. Only the phone could show it: the
    // build was clean, `flutter analyze` was clean, and every Dart test passed.
    //
    // One card with a FIXED SQUARE photograph cannot do that at any size, so the
    // assertions below are about the card's own geometry rather than about tiers.
    // Nothing else in the pipeline can catch their removal either: a weighted image
    // compiles and passes every other test in this repo.
    final provider = File(
      'android/app/src/main/kotlin/com/solevision/app/SellerWidgetProvider.kt',
    ).readAsStringSync();
    final card = File(customerWidgetLayouts.single).readAsStringSync();

    test('the provider and the payload agree on the slot count', () {
      // Read as exact source text rather than as "contains the number": with the
      // count at 1, a bare contains() would match any other 1 in the file and the
      // guard would be worth nothing.
      expect(
        provider,
        contains('CUSTOMER_SLOTS = $kCustomerWidgetProductSlots'),
        reason: 'the provider fills a different number of cards than the payload '
            'writes: an extra one renders blank forever, and a missing one is a '
            'slot of data nothing draws',
      );
    });

    test('there is exactly one customer layout, and no size chooses it', () {
      expect(provider, contains('R.layout.customer_widget_card'));
      expect(
        RegExp(r'R\.layout\.customer_widget_').allMatches(provider).length,
        1,
        reason: 'a second customer layout means the design is chosen by size again',
      );
      // The removed pair, by name. Their files are deleted, so a reference to
      // either is a build error rather than a silent fallback — and this assertion
      // is what proves the source was cleaned up with them.
      expect(provider, isNot(contains('customer_widget_list')));
      expect(provider, isNot(contains('customer_widget_grid')));
    });

    /// The photograph's own element, for the two assertions that are about it.
    String? image() => RegExp(
          r'<ImageView\s+android:id="@\+id/customer_image_1".*?/>',
          dotAll: true,
        ).firstMatch(card)?.group(0);

    test('the photograph is LETTERBOXED, so no tile shape can crop it to a strip', () {
      final element = image();
      expect(element, isNotNull, reason: 'the card has no photograph');
      expect(
        element,
        contains('android:scaleType="fitCenter"'),
        reason: 'this is the assertion that would have caught the fault on a real '
            'phone: centerCrop fills whatever box the launcher grants by cutting '
            'the picture down to it, and a portrait tile turns that into a '
            '106×563 strip of a shoe. fitCenter draws the whole product inside the '
            'box at its own aspect ratio, at every size',
      );
      expect(
        element,
        isNot(contains('centerCrop')),
        reason: 'a crop scale type is the fault this layout exists to have fixed',
      );
    });

    test('the photograph absorbs the tile\'s slack, and the card fills it', () {
      // The seller tiles' own rule, applied here: a launcher that grants extra
      // height gives it to the content rather than to a void. The card fills the
      // tile because with ONE product there is nothing to centre against, and a
      // `wrap_content` card would pool every spare pixel at the bottom.
      final element = image();
      expect(element, contains('android:layout_height="0dp"'));
      expect(element, contains('android:layout_weight="1"'));
      expect(
        RegExp(r'@\+id/customer_product_1"[\s\S]{0,400}?layout_weight="1"')
            .hasMatch(card),
        isTrue,
        reason: 'the card itself no longer takes the height it was given',
      );
    });
  });

  group('the allowlist itself', () {
    test('rejects the exact class that broke the first build', () {
      // The regression this file exists for, stated as a fact about the rule
      // rather than only as a fact about the layout: a plain View is NOT
      // inflatable by RemoteViews, which is unintuitive enough that it was
      // written by hand and shipped.
      expect(remoteViewsInflatable, isNot(contains('View')));
      expect(remoteViewsInflatable, contains('FrameLayout'));
    });
  });
}
