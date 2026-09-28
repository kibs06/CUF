import 'package:app/models/notification_category.dart';
import 'package:app/utils/model_notice.dart';
import 'package:flutter_test/flutter_test.dart';

/// The rule behind a dead end (roadmap V2.14).
///
/// Until this file's subject existed, tapping a "your 3D model is ready" notice
/// did nothing: the feed's navigation branches all key on `order_id`, and a
/// model notice carries a product instead. Every failure below is therefore a
/// *silent* one — a target that is null where it should not be is a tap that
/// does nothing, and a target built from a half-read notice is a tap that opens
/// the wrong product. Neither throws, neither logs, and no widget test would
/// notice without a harness this feed has never had.
void main() {
  // Null-aware entries: an omitted argument means the key is absent from the
  // notice, which is a different case from a key that arrived blank.
  Map<String, dynamic> metadata({Object? productId, Object? requestId}) => {
        'product_id': ?productId,
        'request_id': ?requestId,
      };

  group('modelNoticeTarget — what a notice may point at', () {
    test('reads the product the notice carries', () {
      final target = modelNoticeTarget(
        category: NotificationCategory.models,
        metadata: metadata(productId: 'prod-1', requestId: 'req-1'),
      );

      expect(target, isNotNull);
      expect(target!.productId, 'prod-1');
      expect(target.requestId, 'req-1');
    });

    test('a notice with no request id still opens the product', () {
      // The request id is carried, not required: the actions sheet has one
      // request row per product, so the product is enough to land on the thing
      // the notice is about.
      final target = modelNoticeTarget(
        category: NotificationCategory.models,
        metadata: metadata(productId: 'prod-1'),
      );

      expect(target?.productId, 'prod-1');
      expect(target?.requestId, isNull);
    });

    test('no category but `models` is ever a target', () {
      // `metadata` is one jsonb column shared by every notification in the app,
      // so a product id on another kind of notice must not become this link.
      for (final category in NotificationCategory.values) {
        final target = modelNoticeTarget(
          category: category,
          metadata: metadata(productId: 'prod-1', requestId: 'req-1'),
        );

        if (category == NotificationCategory.models) {
          expect(target?.productId, 'prod-1', reason: '$category');
        } else {
          expect(target, isNull, reason: '$category must not deep-link here');
        }
      }
    });

    test('the ids are read where the database writes them, and trimmed', () {
      // Written by `jsonb_build_object`, so they arrive as strings — but a
      // numeric id is kept as a number by jsonb, and whitespace would otherwise
      // match nothing in a catalog.
      final target = modelNoticeTarget(
        category: NotificationCategory.models,
        metadata: {'product_id': 42, 'request_id': '  req-1  '},
      );

      expect(target?.productId, '42');
      expect(target?.requestId, 'req-1');
    });

    test('a blank id is not an id', () {
      // The dangerous version of this: a notice whose product id is empty must
      // not resolve to "the first row whose id is also empty".
      for (final blank in <Object?>['', '   ', null]) {
        expect(
          modelNoticeTarget(
            category: NotificationCategory.models,
            metadata: metadata(productId: blank, requestId: 'req-1'),
          ),
          isNull,
          reason: 'product_id: $blank',
        );
      }
    });

    test('a missing or unusable product id leaves nothing to open', () {
      expect(
        modelNoticeTarget(category: NotificationCategory.models),
        isNull,
      );
      expect(
        modelNoticeTarget(
          category: NotificationCategory.models,
          metadata: metadata(requestId: 'req-1'),
        ),
        isNull,
      );
      expect(
        modelNoticeTarget(
          category: NotificationCategory.models,
          metadata: metadata(productId: 'prod-1', requestId: '   '),
        )?.requestId,
        isNull,
        reason: 'a blank request id is dropped, not passed on as whitespace',
      );
    });
  });

  group('modelNoticeTargetFromSellerRow — the bell\'s version', () {
    test('reads the product out of `reference_id`', () {
      final target = modelNoticeTargetFromSellerRow(
        type: kModelRequestSellerType,
        referenceId: 'prod-1',
      );

      expect(target?.productId, 'prod-1');
      // The bell row is store-scoped and carries no per-user metadata, so the
      // request id is simply not there rather than blank.
      expect(target?.requestId, isNull);
    });

    test('every other type on the bell leaves the link alone', () {
      // The centre routes five other types to five other screens; only this one
      // is about a product the seller asked to be modelled.
      for (final type in <String>[
        'new_order',
        'stale_order',
        'low_stock',
        'custom_order_request',
        'new_message',
        '',
        'model_requests', // near-miss: not the wire value
      ]) {
        expect(
          modelNoticeTargetFromSellerRow(type: type, referenceId: 'prod-1'),
          isNull,
          reason: type,
        );
      }
    });

    test('a model notice with no usable product id opens nothing', () {
      // 'low_stock' rows carry a product id too; a `model_request` row whose id
      // is missing must not be routed to a product the way that one is.
      for (final referenceId in <String?>[null, '', '   ']) {
        expect(
          modelNoticeTargetFromSellerRow(
            type: kModelRequestSellerType,
            referenceId: referenceId,
          ),
          isNull,
          reason: 'referenceId: $referenceId',
        );
      }
    });

    test('the wire value is the one the constraint admits', () {
      expect(kModelRequestSellerType, 'model_request');
    });
  });

  group('linkedProduct — where the tap lands', () {
    final catalog = <Map<String, dynamic>>[
      {'id': 'prod-1', 'name': 'Artisan Chelsea Boot'},
      {'id': 'prod-2', 'name': 'Everyday Loafer'},
    ];

    test('finds the row the notice names', () {
      expect(linkedProduct(catalog, 'prod-2')?['name'], 'Everyday Loafer');
    });

    test('a numeric id in the catalog still matches', () {
      // The catalog list is whatever shape this screen was handed; ids are
      // uuids today, and comparing as strings is what keeps that from mattering.
      expect(
        linkedProduct(<Map<String, dynamic>>[
          {'id': 7, 'name': 'Numeric'},
        ], '7')?['name'],
        'Numeric',
      );
    });

    test('a product that is not there is null, not the first row', () {
      // The whole point of the match: a deleted product must not open somebody
      // else's sheet.
      expect(linkedProduct(catalog, 'prod-3'), isNull);
      expect(linkedProduct(const [], 'prod-1'), isNull);
    });

    test('nothing matches a blank or partial id', () {
      expect(linkedProduct(catalog, ''), isNull);
      expect(linkedProduct(catalog, '  '), isNull);
      // Suffix/prefix matching would be the tempting shortcut and the wrong one.
      expect(linkedProduct(catalog, 'prod'), isNull);
      expect(linkedProduct(catalog, 'prod-'), isNull);
    });

    test('a row with no id is skipped rather than matched', () {
      // `null.toString()` is how a lookup written without this guard matches the
      // first id-less row — and every id-less row.
      expect(
        linkedProduct(<Map<String, dynamic>>[
          {'name': 'No id at all'},
          {'id': 'prod-1', 'name': 'Real'},
        ], 'prod-1')?['name'],
        'Real',
      );
      expect(linkedProduct(<Map<String, dynamic>>[{'name': 'No id'}], 'null'),
          isNull);
    });
  });
}
