import 'dart:io';

import 'package:app/models/app_notification.dart';
import 'package:app/models/notification_category.dart';
import 'package:flutter_test/flutter_test.dart';

/// `NotificationCategory` says it matches the `notification_category` Postgres
/// enum. Nothing checked that until this file.
///
/// **Why the drift is worth a test rather than a comment.** The Dart side is an
/// exhaustive `switch`, so a category added *here* without a label fails to
/// compile — but the other direction compiles perfectly and is silent: a label
/// added in SQL (like V2.11's `'models'`, which the fulfil RPC writes) arrives
/// as `unpaid` through `AppNotification._parseCategory`'s default, so a seller
/// would see the brand-new "your model is ready" notice filed under **Unpaid**
/// with a credit-card icon, in the wrong filter, counted in the wrong badge.
/// That is a bug no compiler, analyzer or widget test can see.
///
/// Three assertions, and the third is the one that matters:
///
///  1. every label the migrations can produce has a Dart case;
///  2. every Dart case is a label the migrations can produce (so a value added
///     here without its `ALTER TYPE` fails *before* a database refuses it);
///  3. every label survives the real parse path — `AppNotification.fromMap` —
///     which is what the feed actually calls.
///
/// The last is not redundant with the first two: a label could be in both lists
/// and still be missing its `case` in the parser, and only this one notices.
void main() {
  final dir = Directory('supabase/migrations');

  /// Every label the enum can hold, read from the SQL rather than from a
  /// hand-kept list — a list would be a third copy to drift.
  ///
  /// Two sources, because a Postgres enum grows in two ways: the `CREATE TYPE`
  /// block (the original five) and one `ALTER TYPE … ADD VALUE` per category
  /// added since (`'message'`, `'support'`, `'approval'`, `'reservations'`,
  /// `'models'`). A category added any other way would be missed here, so the
  /// anchor below fails loudly if the creation statement ever moves.
  ({Set<String> labels, Set<String> files}) labelsFromMigrations() {
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.sql'))
        .toList();

    final base = files.firstWhere(
      (f) => f.path.replaceAll(r'\', '/').endsWith('20260702_notifications.sql'),
      orElse: () => throw StateError(
        'the base notifications migration is gone — this guard reads the '
        'CREATE TYPE block from it, so it has to be repointed, not deleted',
      ),
    );
    final src = base.readAsStringSync();
    final start = src.indexOf('CREATE TYPE notification_category AS ENUM');
    expect(
      start,
      greaterThan(-1),
      reason: 'the notification_category enum is no longer created in '
          '20260702_notifications.sql — find where it moved and repoint this '
          'guard instead of deleting it',
    );
    final end = src.indexOf(');', start);
    expect(end, greaterThan(start), reason: 'unterminated CREATE TYPE block');

    final labels = <String>{
      for (final m in RegExp(r"'([a-z0-9_]+)'")
          .allMatches(src.substring(start, end)))
        m.group(1)!,
    };
    expect(
      labels.length,
      greaterThanOrEqualTo(5),
      reason: 'the base enum block parsed to fewer labels than it used to — the '
          'anchor is wrong rather than the enum',
    );

    final adders = RegExp(
      r"ALTER\s+TYPE\s+(?:public\.)?notification_category\s+"
      r"ADD\s+VALUE\s+(?:IF\s+NOT\s+EXISTS\s+)?'([a-z0-9_]+)'",
    );
    final addFiles = <String>{};
    for (final f in files) {
      for (final m in adders.allMatches(f.readAsStringSync())) {
        labels.add(m.group(1)!);
        addFiles.add(f.path.replaceAll(r'\', '/').split('/').last);
      }
    }

    return (labels: labels, files: {...addFiles, '20260702_notifications.sql'});
  }

  test('the SQL actually yields the categories this test thinks it does', () {
    final fromSql = labelsFromMigrations();
    // A floor, not an exact count: adding a category must not fail this test,
    // losing the scanner must.
    expect(fromSql.labels.length, greaterThanOrEqualTo(9));
    expect(fromSql.files.length, greaterThanOrEqualTo(5));
    // The one V2.11 added, named so a silent scanner regression is obvious.
    expect(fromSql.labels, contains('models'));
  });

  test('every category the database can store has a Dart case', () {
    final fromSql = labelsFromMigrations().labels;
    final inDart = NotificationCategory.values.map((c) => c.name).toSet();

    expect(
      fromSql.difference(inDart),
      isEmpty,
      reason: 'a label the migrations define has no NotificationCategory case — '
          'it would parse as `unpaid` (the parser default) in the feed',
    );
  });

  test('every Dart case is a category the database can store', () {
    final fromSql = labelsFromMigrations().labels;
    final inDart = NotificationCategory.values.map((c) => c.name).toSet();

    expect(
      inDart.difference(fromSql),
      isEmpty,
      reason: 'a NotificationCategory with no `ALTER TYPE … ADD VALUE` — reading '
          'one would fail, and writing one would be refused by the database',
    );
  });

  test('every label survives the real parse path, and has a label to show', () {
    final fromSql = labelsFromMigrations().labels;

    for (final label in fromSql) {
      // The actual runtime path: a row's category text becomes an enum.
      final parsed = AppNotification.fromMap({'category': label});
      expect(
        parsed.category.name,
        label,
        reason: 'the feed would show "$label" as ${parsed.category.name}',
      );
      // The filter chip and the tile both read this.
      expect(
        notificationCategoryLabel(parsed.category).trim(),
        isNotEmpty,
        reason: 'no display label for "$label"',
      );
    }
  });
}
