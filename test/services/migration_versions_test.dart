import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the one property of `supabase/migrations/` that the Supabase CLI
/// requires and no Dart code can check at compile time: **every version is
/// unique.**
///
/// The CLI records what it has applied in
/// `supabase_migrations.schema_migrations`, whose PRIMARY KEY is the numeric
/// version — the digits before the first `_` in the filename. Two files sharing
/// a version can therefore never both apply: the second one dies on
///
/// ```
/// ERROR: duplicate key value violates unique constraint "schema_migrations_pkey"
/// Key (version)=(20260917120000) already exists.
/// ```
///
/// That is not a theoretical risk. It is exactly how the `Supabase Migrations`
/// job failed on the Sep 19 commit — `20260917120000_add_foot_size_category.sql`
/// landed beside the pre-existing `20260917120000_add_pickup_reservation_color.sql`
/// — and it is a nasty one to diagnose from the log alone, because the error
/// arrives while a *different* file is being applied and names neither of the
/// two files that actually collide. This test names them.
///
/// The fix is always to renumber the NEWER file (never the one already recorded
/// in `supabase/MIGRATIONS_LIVE_STATUS.md`, whose version may already be a row
/// in a live database's history table), which is why the assertion reports the
/// whole colliding group rather than just the first pair it finds.
void main() {
  const migrationsDir = 'supabase/migrations';

  /// `20260714_push_notifications.sql` and `20260714000000_…sql` both exist and
  /// are both legitimate: the project's older files use an 8-digit date, newer
  /// ones a 14-digit timestamp, and the CLI sorts them lexicographically rather
  /// than parsing them as dates. So this pins only the *shape* — digits, then a
  /// name, then `.sql` — and never the digit count.
  final fileNamePattern = RegExp(r'^\d+_[A-Za-z0-9_]+\.sql$');

  late List<File> files;

  setUpAll(() {
    final dir = Directory(migrationsDir);

    // A missing directory would otherwise glob to nothing and the test would
    // pass while checking zero files. The relative path assumes the working
    // directory is the package root, which is how `flutter test` runs — the
    // same assumption the other cross-artifact contract tests make.
    expect(
      dir.existsSync(),
      isTrue,
      reason: 'Could not find $migrationsDir from ${Directory.current.path}. '
          'This test reads the migrations off disk and must not silently pass.',
    );

    files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.sql'))
        .toList();

    // An empty or one-file glob is a broken lookup, not a clean bill of health.
    expect(
      files.length,
      greaterThan(50),
      reason: 'Only ${files.length} migration(s) found in $migrationsDir — the '
          'lookup is wrong, not the migrations.',
    );
  });

  test('every migration filename is <version>_<name>.sql', () {
    final offenders = <String>[];

    for (final file in files) {
      final name = file.uri.pathSegments.last;
      if (!fileNamePattern.hasMatch(name)) offenders.add(name);
    }

    expect(
      offenders,
      isEmpty,
      reason: 'The Supabase CLI keys migrations on the digits before the first '
          '`_`. These do not match <version>_<name>.sql: ${offenders.join(', ')}',
    );
  });

  test('no two migrations share a version', () {
    final byVersion = <String, List<String>>{};

    for (final file in files) {
      final name = file.uri.pathSegments.last;
      // Parsed with a fallback so a malformed name still participates here
      // instead of throwing: the shape test above owns that complaint.
      final version = name.contains('_') ? name.split('_').first : name;
      byVersion.putIfAbsent(version, () => <String>[]).add(name);
    }

    final collisions = byVersion.entries
        .where((e) => e.value.length > 1)
        .map((e) => '  ${e.key}  →  ${(e.value..sort()).join('  +  ')}')
        .toList()
      ..sort();

    expect(
      collisions,
      isEmpty,
      reason: 'Two migrations share a version. The Supabase CLI tracks applied '
          'migrations by version alone (schema_migrations has it as its PRIMARY '
          'KEY), so the second file fails with SQLSTATE 23505 and the whole '
          'migration job aborts:\n'
          '${collisions.join('\n')}\n'
          'Renumber the NEWER file to an unused version — do not touch the one '
          'recorded in supabase/MIGRATIONS_LIVE_STATUS.md.',
    );
  });

  test('the newest migrations are uniquely versioned on their own', () {
    // A cheap canary for the ordering assumption the CI job depends on: the
    // files added most recently are the ones that most often collide, because
    // two people reach for the same "now" when writing them in one sitting.
    // Sorted by version, not mtime, since mtime is meaningless after a clone.
    final versions = files
        .map((f) => f.uri.pathSegments.last.split('_').first)
        .toList()
      ..sort();

    final newest = versions.last;
    expect(
      versions.where((v) => v == newest).length,
      1,
      reason: 'The newest migration version ($newest) is claimed by more than '
          'one file.',
    );
  });
}
