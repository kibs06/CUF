import 'package:flutter_test/flutter_test.dart';

import 'package:app/utils/product_images.dart';

/// The product-card photos all come through here, and the two shapes a product
/// map arrives in (a raw row's `product_images`, the mapped model's flattened
/// `images`) are exactly the kind of thing that drifts silently — a card would
/// simply show the wrong photo, in the wrong order, with no error anywhere.
void main() {
  group('productImageUrls', () {
    test('reads product_images in display_order, not list order', () {
      expect(
        productImageUrls({
          'product_images': [
            {'image_url': 'c.jpg', 'display_order': 2},
            {'image_url': 'a.jpg', 'display_order': 0},
            {'image_url': 'b.jpg', 'display_order': 1},
          ],
        }),
        ['a.jpg', 'b.jpg', 'c.jpg'],
      );
    });

    test('treats a missing display_order as first', () {
      expect(
        productImageUrls({
          'product_images': [
            {'image_url': 'later.jpg', 'display_order': 5},
            {'image_url': 'first.jpg'},
          ],
        }),
        ['first.jpg', 'later.jpg'],
      );
    });

    test('drops blanks and repeats', () {
      expect(
        productImageUrls({
          'product_images': [
            {'image_url': 'a.jpg', 'display_order': 0},
            {'image_url': '  ', 'display_order': 1},
            {'image_url': null, 'display_order': 2},
            {'image_url': 'a.jpg', 'display_order': 3},
            {'image_url': 'b.jpg', 'display_order': 4},
          ],
        }),
        ['a.jpg', 'b.jpg'],
      );
    });

    test('falls back to the mapped model\'s flat images list', () {
      expect(
        productImageUrls({
          'images': ['a.jpg', 'b.jpg'],
        }),
        ['a.jpg', 'b.jpg'],
      );
    });

    test('still reads a row shape handed through `images`', () {
      expect(
        productImageUrls({
          'images': [
            {'image_url': 'a.jpg'},
          ],
        }),
        ['a.jpg'],
      );
    });

    test('prefers product_images when both are present', () {
      expect(
        productImageUrls({
          'product_images': [
            {'image_url': 'row.jpg', 'display_order': 0},
          ],
          'images': ['flat.jpg'],
        }),
        ['row.jpg'],
      );
    });

    test('is empty — never null — for a product with no photo', () {
      expect(productImageUrls(null), isEmpty);
      expect(productImageUrls(const <String, dynamic>{}), isEmpty);
      expect(productImageUrls({'images': <String>[]}), isEmpty);
      expect(productImageUrls({'product_images': 'not-a-list'}), isEmpty);
    });

    test('hands back a list no caller can rewrite', () {
      final urls = productImageUrls({
        'images': ['a.jpg'],
      });
      expect(() => urls.add('b.jpg'), throwsUnsupportedError);
    });
  });
}
