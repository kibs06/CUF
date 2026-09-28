import 'dart:io';

import 'package:app/models/notification_category.dart';
import 'package:app/utils/model_notice.dart';
import 'package:flutter_test/flutter_test.dart';

/// The keys in a model notice's `metadata` are a contract between plpgsql and
/// Dart, and nothing else checks it.
///
/// `fulfil_shoe_model_request` and `decline_shoe_model_request` build the notice
/// with `jsonb_build_object('request_id', …, 'product_id', …)`; `modelNotice`
/// reads `product_id` back out of that object to decide where a tap goes. Rename
/// a key on **either** side and:
///
///   * nothing fails to compile — one side is SQL, and Dart reads a map;
///   * no test fails — the pgTAP suite asserts the notice exists, not what its
///     metadata can be used for;
///   * no user sees an error — the notice still arrives, still says the right
///     sentence, and simply stops being tappable.
///
/// That is the same class of drift `notification_category_contract_test.dart`
/// guards for the category label, and the same response: read the contract out
/// of the migration rather than keeping a second copy of it here.
///
/// The rule is exercised end-to-end from the *database's* keys — the metadata
/// map below is built from whatever the SQL actually writes — so the assertion
/// is "a notice this migration can produce is tappable", not "these two string
/// literals are equal".
void main() {
  const migrationPath =
      'supabase/migrations/20260928140000_add_shoe_model_requests.sql';

  /// Every `INSERT INTO public.notifications` in the flow's migration, as
  /// (category literal, metadata key set).
  ///
  /// Anchored on the insert, then on the `jsonb_build_object` inside it: the
  /// only quoted-and-comma-terminated strings in that call are its keys, and
  /// its values are plpgsql variables (`v_product`, `p_request_id`).
  List<({String category, Set<String> keys})> noticeInserts() {
    final file = File(migrationPath);
    expect(
      file.existsSync(),
      isTrue,
      reason: '$migrationPath is gone — this guard reads the notice inserts from '
          'it, so it has to be repointed, not deleted',
    );
    final src = file.readAsStringSync();

    final inserts = <({String category, Set<String> keys})>[];
    final insertRegex = RegExp(
      r'INSERT\s+INTO\s+public\.notifications',
      caseSensitive: false,
    );

    for (final match in insertRegex.allMatches(src)) {
      // The statement runs to the closing `);` of the insert, which is the
      // first `;` after a `jsonb_build_object` block has been seen.
      final tail = src.substring(match.start);
      final objectStart = tail.indexOf('jsonb_build_object');
      expect(
        objectStart,
        greaterThan(-1),
        reason: 'an insert into public.notifications carries no metadata object '
            '— the tap rule reads it, so this notice would be a dead end',
      );
      final statementEnd = tail.indexOf(';', objectStart);
      final statement = tail.substring(0, statementEnd + 1);

      final category = RegExp(r"'([a-z_]+)',\s*\n\s*'").firstMatch(
        statement.substring(statement.indexOf('SELECT')),
      );
      final object = statement.substring(objectStart);

      inserts.add((
        category: category?.group(1) ?? '',
        keys: {
          // `'request_id',` / `'product_id',` — a key, not a value: values are
          // bare plpgsql identifiers or function calls.
          for (final m in RegExp(r"'([a-z_]+)'\s*,").allMatches(object))
            m.group(1)!,
        },
      ));
    }

    return inserts;
  }

  test('the scanner finds the two endings, and not zero of them', () {
    final inserts = noticeInserts();

    // Two: `fulfil` (V2.12) and `decline` (V2.13). A third ending would have to
    // be added here deliberately — which is the point of the exact count.
    expect(
      inserts.length,
      2,
      reason: 'expected the fulfilled and declined notices; the scanner found '
          '${inserts.length} insert(s) into public.notifications',
    );
    for (final insert in inserts) {
      expect(
        insert.category,
        NotificationCategory.models.name,
        reason: 'both endings file under the same category, so the seller finds '
            'them together — the title says which ending it was',
      );
    }
  });

  test('every notice the flow writes is tappable through the real rule', () {
    for (final insert in noticeInserts()) {
      expect(
        insert.keys,
        containsAll(<String>['product_id', 'request_id']),
        reason: 'the notice metadata is ${insert.keys}; the deep link reads '
            '`product_id` out of it',
      );

      // The keys, from SQL, in a notice-shaped map: this is what the tap does.
      final target = modelNoticeTarget(
        category: NotificationCategory.models,
        metadata: {for (final key in insert.keys) key: '<id>'},
      );

      expect(
        target?.productId,
        '<id>',
        reason: 'a notice this migration writes produced no deep link — check '
            'that the key the rule reads is the key the SQL writes',
      );
    }
  });

  /// Every `INSERT INTO public.seller_notifications` in the flow's migration,
  /// as the literal `type` it writes.
  ///
  /// The bell's half of the same news (V2.14): the row `SellerNotificationCenterScreen`
  /// renders and routes on `reference_id`. Its `type` has to be a value the
  /// table's CHECK admits, and the CHECK is in this same file — so the two
  /// halves of that contract are read from one source here.
  List<String> sellerBellTypes() {
    final src = File(migrationPath).readAsStringSync();
    final types = <String>[];
    for (final match in RegExp(
      r'INSERT\s+INTO\s+public\.seller_notifications',
      caseSensitive: false,
    ).allMatches(src)) {
      final tail = src.substring(match.start);
      final values = tail.indexOf('VALUES (');
      // The type literal is the second line of the VALUES list, after the
      // store id — matched as a quoted identifier rather than by position, so
      // a re-ordered insert still reads.
      // The FIRST quoted literal in the VALUES list is the type: the store id
      // ahead of it is a plpgsql variable, not a string. (If that ever stops
      // being true, the assertion against the constraint's own value set below
      // fails rather than this read passing silently.)
      final first = RegExp(r"'([a-z_]+)',")
          .firstMatch(tail.substring(values, tail.indexOf(');', values)));
      types.add(first?.group(1) ?? '');
    }
    return types;
  }

  /// The values `seller_notifications_type_check` admits, read from the ALTERed
  /// constraint definition in the same file.
  Set<String> sellerBellAllowedTypes() {
    final src = File(migrationPath).readAsStringSync();
    final start = src.indexOf('ADD CONSTRAINT seller_notifications_type_check');
    expect(
      start,
      greaterThan(-1),
      reason: 'the seller-bell type constraint is no longer widened in '
          '$migrationPath — if that moved, repoint this guard rather than '
          'deleting it: a type the CHECK refuses fails the CLOSE, not just the '
          'notification',
    );
    final block = src.substring(start, src.indexOf(');', start));
    return {
      for (final m in RegExp(r"'([a-z_]+)'").allMatches(block)) m.group(1)!,
    };
  }

  test('the bell notice writes a type the bell\'s constraint admits', () {
    final writes = sellerBellTypes();
    final allowed = sellerBellAllowedTypes();

    // Two endings, two rows, both on the bell.
    expect(
      writes.length,
      2,
      reason: 'expected the fulfilled and declined bell rows; found '
          '${writes.length}',
    );
    expect(allowed, contains(kModelRequestSellerType));
    for (final type in writes) {
      expect(
        type,
        kModelRequestSellerType,
        reason: 'the bell row this migration writes is not the type the Dart '
            'rule and the bell screen switch on',
      );
      expect(
        allowed,
        contains(type),
        reason: 'the migration inserts a `$type` seller notification, which its '
            'own CHECK would refuse — and that insert runs inside the '
            'transaction that closes the ask',
      );
    }
  });

  test('a bell row this migration writes routes where the seller expects', () {
    // The type the SQL writes, through the rule the screen runs, to the
    // product the tap opens: all three have to agree, and only one of them is
    // compile-checked.
    for (final type in sellerBellTypes()) {
      final target = modelNoticeTargetFromSellerRow(
        type: type,
        referenceId: '<id>',
      );
      expect(
        target?.productId,
        '<id>',
        reason: 'a `$type` bell row from this migration resolved to no deep '
            'link — the screen would open the catalog instead of the product',
      );
    }
  });

  test('the rule is reading `product_id` and not merely returning a target', () {
    // Strip the one key the link needs from the SQL's own key set: if the rule
    // were keyed on something else (or on nothing), this would still pass.
    for (final insert in noticeInserts()) {
      final withoutProduct =
          {for (final key in insert.keys) key: '<id>'}..remove('product_id');

      expect(
        modelNoticeTarget(
          category: NotificationCategory.models,
          metadata: withoutProduct,
        ),
        isNull,
        reason: 'a notice with no product id must not open anything',
      );
    }
  });
}
