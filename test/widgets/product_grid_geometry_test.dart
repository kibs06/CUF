import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:app/constants/app_constants.dart';

/// Contract test for the shared product-browsing geometry.
///
/// Every customer surface that lays product cards out in a grid or a rail is
/// supposed to take its gutter and its side margin from ONE pair of tokens
/// ([AppConstants.productGridGutter] / [AppConstants.feedMargin]). Before that
/// pair existed, seven files carried their own numbers — a 16px gutter and a
/// 20px margin on the grids, while the home's own search chrome already used
/// 16 — so the feed never quite lined up with the search field above it, and
/// tightening one grid left every other one loose.
///
/// These tests read the sources, because the failure mode here is invisible: a
/// literal `16` still compiles, still looks fine on the screen it was typed
/// on, and only shows up as one grid in the app being looser than the rest.
/// (The technique is the same one `offscreen_timer_pause_contract_test.dart`
/// uses for the seller shell.)

/// Drops `//` comments so the guards below cannot be satisfied by prose.
String withoutLineComments(String source) => source
    .split('\n')
    .map((line) {
      final i = line.indexOf('//');
      return i == -1 ? line : line.substring(0, i);
    })
    .join('\n');

int _count(String source, String pattern) =>
    RegExp(pattern).allMatches(source).length;

void main() {
  /// Every file that lays product cards out in a 2-column grid, with the
  /// number of grids it holds.
  const gridFiles = <String, int>{
    'lib/screens/customer/customer_home_screen.dart': 2, // catalog + On Sale
    'lib/screens/customer/search_results_screen.dart': 1,
    'lib/screens/customer/audience_listing_screen.dart': 1,
    'lib/screens/customer/recently_viewed_screen.dart': 1,
    'lib/screens/store/collection_screen.dart': 1,
    'lib/screens/store/store_profile_screen.dart': 1,
  };

  /// The horizontal rails. Their strips are padded and separated by the same
  /// two tokens, so a rail card's gutter matches the grid's.
  const railFiles = [
    'lib/widgets/product_rail_section.dart',
    'lib/widgets/best_sellers_section.dart',
    'lib/widgets/buy_again_section.dart',
  ];

  group('the two tokens', () {
    test('keep the values the screens were tuned against', () {
      // Tuned on the device: the gutter went 16 → 10 → 8 and the margin
      // followed it to 8, which is what makes the columns read as tiles.
      expect(AppConstants.productGridGutter, 8);
      expect(AppConstants.feedMargin, 8);
    });

    test('never let the page margin go tighter than the card gutter', () {
      // Equal is the intent (one uniform rhythm across the page); *tighter*
      // than the seam is the failure this blocks — the outer cards would read
      // as bleeding off the screen edge.
      expect(
        AppConstants.feedMargin,
        greaterThanOrEqualTo(AppConstants.productGridGutter),
      );
      expect(AppConstants.productGridGutter, greaterThan(0));
    });

    test('the home chrome insets from the same token as the feed', () {
      // One content column: the search rows, the category chips and the
      // hero's own text block all start on the line the grid and the section
      // headers start on. Each of these used to carry a literal (16, 16, 18)
      // next to a feed that used 20 — which is exactly how the page ended up
      // with four nearly-equal left edges.
      const chrome = {
        'lib/screens/customer/widgets/home_sticky_search_bar.dart': 1,
        'lib/screens/customer/widgets/home_category_row.dart': 1,
        // icon row + the banner copy + the page dots
        'lib/screens/customer/widgets/home_hero.dart': 3,
      };
      for (final entry in chrome.entries) {
        final code = withoutLineComments(File(entry.key).readAsStringSync());
        final inColumn = RegExp(
          r'(EdgeInsets\.fromLTRB\(\s*AppConstants\.feedMargin|'
          r'left: AppConstants\.feedMargin)',
        ).allMatches(code).length;
        expect(
          inColumn,
          entry.value,
          reason:
              '${entry.key} must inset from AppConstants.feedMargin '
              '(${AppConstants.feedMargin})',
        );
      }
    });
  });

  group('every customer product grid uses them', () {
    for (final entry in gridFiles.entries) {
      final path = entry.key;
      final grids = entry.value;

      test(path, () {
        final code = withoutLineComments(File(path).readAsStringSync());

        expect(
          _count(code, r'crossAxisSpacing:\s*AppConstants\.productGridGutter'),
          grids,
          reason:
              '$path has $grids grid(s) — each one must take its column '
              'gutter from the shared token',
        );
        expect(
          _count(code, r'mainAxisSpacing:\s*AppConstants\.productGridGutter'),
          grids,
          reason:
              '$path has $grids grid(s) — each one must take its row '
              'gutter from the shared token',
        );

        // A literal gutter is the regression this file exists for.
        for (final literal in [
          r'crossAxisSpacing:\s*16',
          r'mainAxisSpacing:\s*16',
        ]) {
          expect(
            _count(code, literal),
            0,
            reason: '$path still hardcodes a 16px gutter',
          );
        }

        // The grid's own side margin, not just the token imported.
        expect(
          RegExp(
            r'EdgeInsets[^;]{0,120}?AppConstants\.feedMargin',
          ).hasMatch(code),
          isTrue,
          reason:
              '$path must pad its grid (and its headers) from '
              'AppConstants.feedMargin',
        );
      });
    }

    test('the size grid hands them to its own two-column layout', () {
      // `product_grid_section.dart` packs its cells itself (it has to place the
      // closing pair against their own columns), so it has no
      // `crossAxisSpacing` to read: the tokens are what it passes to the
      // layout, and the layout is the only place the columns are derived.
      final code = withoutLineComments(
        File('lib/widgets/product_grid_section.dart').readAsStringSync(),
      );
      expect(
        RegExp(
          r'margin:\s*AppConstants\.feedMargin',
        ).hasMatch(code),
        isTrue,
        reason: 'the grid body must inset from AppConstants.feedMargin',
      );
      expect(
        RegExp(
          r'gutter:\s*AppConstants\.productGridGutter',
        ).hasMatch(code),
        isTrue,
        reason: 'the grid body must seam its columns with the shared gutter',
      );

      final layout = withoutLineComments(
        File('lib/widgets/two_column_masonry.dart').readAsStringSync(),
      );
      // The layout takes both as parameters: a literal in there would be the
      // same regression, one layer down.
      expect(layout, contains('final double margin;'));
      expect(layout, contains('final double gutter;'));
      for (final literal in [
        r'_margin = 8',
        r'_gutter = 8',
        r'horizontal: 16',
      ]) {
        expect(_count(layout, literal), 0);
      }
    });

    test(
      'the home Recently Viewed section derives its cell width from them',
      () {
        final code = withoutLineComments(
          File('lib/widgets/recently_viewed_section.dart').readAsStringSync(),
        );
        // Its `_spacing` is both the masonry gutter AND the subtrahend in
        // `cellWidth = (maxWidth - _spacing) / 2` — a private copy of the number
        // would silently desync the cap measurement from the grid.
        expect(
          RegExp(
            r'static const double _spacing = AppConstants\.productGridGutter;',
          ).hasMatch(code),
          isTrue,
        );
        expect(
          RegExp(
            r'EdgeInsets[^;]{0,120}?AppConstants\.feedMargin',
          ).hasMatch(code),
          isTrue,
        );
      },
    );
  });

  group('the store tab matches the feed', () {
    test('the Top Picks grid is inset and spaced like every other grid', () {
      final code = withoutLineComments(
        File(
          'lib/screens/store/widgets/cross_store_product_row.dart',
        ).readAsStringSync(),
      );

      // It used to run edge to edge on a 14px gutter — the only product grid
      // in the app with no side margin at all.
      expect(
        _count(code, r'crossAxisSpacing:\s*AppConstants\.productGridGutter'),
        1,
      );
      expect(
        _count(code, r'mainAxisSpacing:\s*AppConstants\.productGridGutter'),
        1,
      );
      expect(_count(code, r'final spacing = 14'), 0);
      expect(
        RegExp(
          r'EdgeInsets[^;]{0,120}?AppConstants\.feedMargin',
        ).hasMatch(code),
        isTrue,
        reason: 'the Top Picks label and grid must use AppConstants.feedMargin',
      );
    });

    test('the Top Picks grid is masonry, not a Wrap', () {
      // A `Wrap` is row-based: each run is as tall as its tallest card, so with
      // the per-product aspect ratios (productGridRatio) a shorter card leaves
      // a hole under it. That is the gap this grid used to show whenever two
      // neighbouring products happened to have different ratios.
      final code = withoutLineComments(
        File(
          'lib/screens/store/widgets/cross_store_product_row.dart',
        ).readAsStringSync(),
      );

      expect(code, contains('MasonryGridView.count'));
      expect(
        _count(code, r'Wrap\('),
        0,
        reason: 'a row-based Wrap cannot pack cards of differing heights',
      );
      expect(
        _count(code, r'LayoutBuilder'),
        0,
        reason:
            'masonry owns the column maths now — the padding is the only '
            'geometry left to state',
      );
    });

    test('the store info block uses the same margin as the products', () {
      final code = withoutLineComments(
        File(
          'lib/screens/store/widgets/store_focused_info.dart',
        ).readAsStringSync(),
      );
      expect(
        _count(
          code,
          r'EdgeInsets\.symmetric\(\s*horizontal: AppConstants\.feedMargin',
        ),
        1,
        reason:
            'the store name / address / Enter Store block was the widest '
            'inset on a page whose cards had none',
      );
      expect(_count(code, r'horizontal: 24'), 0);
    });

    test('the store tab skeleton stands in at the same margins', () {
      // A skeleton at 20 next to real content at 8 is a visible jump when the
      // stores land.
      final code = withoutLineComments(
        File('lib/screens/store/store_screen.dart').readAsStringSync(),
      );
      expect(
        _count(code, r'horizontal: AppConstants\.feedMargin'),
        greaterThanOrEqualTo(4),
      );
      expect(_count(code, r'horizontal: 20'), 0);
      expect(
        _count(code, r'SizedBox\(width: 12\)'),
        0,
        reason: 'the skeleton rail must use the shared gutter',
      );
    });
  });

  group('the rails match the grids', () {
    for (final path in railFiles) {
      test(path, () {
        final code = withoutLineComments(File(path).readAsStringSync());

        expect(
          RegExp(
            r'SizedBox\(width: AppConstants\.productGridGutter\)',
          ).hasMatch(code),
          isTrue,
          reason: '$path must separate its cards with the shared gutter',
        );
        expect(
          _count(code, r'SizedBox\(width: 12\)'),
          0,
          reason: '$path still separates its cards with a literal 12',
        );
        expect(
          RegExp(
            r'EdgeInsets[^;]{0,120}?AppConstants\.feedMargin',
          ).hasMatch(code),
          isTrue,
          reason:
              '$path must inset its header and strip from '
              'AppConstants.feedMargin',
        );
      });
    }
  });
}
