import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The live schema has `profiles.full_name`; there is no `profiles.name`.
///
/// Asking for one is not a soft failure. PostgREST validates the whole select
/// against its schema before running anything and answers 42703 — "column
/// profiles_1.name does not exist" — so the screen that issued the query shows
/// its generic error state instead of the rows the dashboard just counted.
/// That is exactly how the seller's Bulk Reservations queue came up empty
/// while its tile said 2, and the same word was wrong in the pickup queue.
/// One word is cheap to get wrong twice, so this pins it.
///
/// Only `profiles` is checked: it is the one table whose name column is not
/// called `name`. `products(name)` and `stores(name)` are correct.
void main() {
  test('no service asks PostgREST for profiles.name', () {
    final offenders = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;

      final source = entity.readAsStringSync();
      for (final match in _profilesEmbed.allMatches(source)) {
        final columns = match
            .group(1)!
            .split(',')
            .map((column) => column.trim())
            .toList();
        if (!columns.contains('name')) continue;

        final escaped = entity.path.replaceAll(r'\', '/');
        final lineNumber =
            '\n'.allMatches(source.substring(0, match.start)).length + 1;
        offenders.add('$escaped:$lineNumber  ${match.group(0)}');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Found ${offenders.length} profiles embed(s) asking for `name`. The column is `full_name` '
          '(profiles has no `name`), so the request fails with 42703 and the caller renders its error '
          'state. Use profiles(full_name) — or profiles!<fkey>(full_name) where the join is ambiguous.\n\n'
          '${offenders.join('\n')}',
    );
  });
}

/// A `profiles` embed in a PostgREST select: `profiles(col, ...)` or
/// `profiles!foreign_key(col, ...)`, capturing the column list.
final RegExp _profilesEmbed =
    RegExp(r'profiles!?[A-Za-z_]*(?:\(([^)]*)\))');
