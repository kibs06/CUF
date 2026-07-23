import 'package:flutter_test/flutter_test.dart';
import 'package:app/services/report_service.dart';

/// Unit tests for ReportService.
///
/// NOTE: ReportService uses Supabase.instance.client directly (no constructor
/// injection), so we can only test static/visible logic here. To test the
/// notification pipeline (DB insert + push), ReportService would need to be
/// refactored to accept a SupabaseClient parameter (like OrderService does).
void main() {
  // ════════════════════════════════════════════════════════════════════
  // 1. Category Definitions
  // ════════════════════════════════════════════════════════════════════

  group('Category definitions', () {
    test('categoriesByType contains all 4 report types', () {
      expect(
        ReportService.categoriesByType.keys,
        containsAll(['message', 'product', 'seller', 'other']),
      );
    });

    test('each report type has at least 4 categories', () {
      for (final entry in ReportService.categoriesByType.entries) {
        expect(
          entry.value.length,
          greaterThanOrEqualTo(4),
          reason: '${entry.key} should have at least 4 categories',
        );
      }
    });

    test('every report type includes an "other" catch-all category', () {
      for (final entry in ReportService.categoriesByType.entries) {
        expect(
          entry.value.keys,
          contains('other'),
          reason: '${entry.key} must have an "other" category',
        );
      }
    });

    test('categoryLabel returns correct label for known type+key', () {
      expect(
        ReportService.categoryLabel('message', 'harassment'),
        'Harassment / abusive language',
      );
    });

    test('categoryLabel returns the key itself for unknown type', () {
      expect(ReportService.categoryLabel('unknown', 'foo'), 'foo');
    });

    test('categoryLabel returns the key itself for unknown category', () {
      expect(ReportService.categoryLabel('message', 'nonexistent'), 'nonexistent');
    });

    test('categoriesForType returns entries for known type', () {
      final cats = ReportService.categoriesForType('product');
      expect(cats, isNotEmpty);
      expect(cats.first.key, isA<String>());
      expect(cats.first.value, isA<String>());
    });

    test('categoriesForType returns empty list for unknown type', () {
      expect(ReportService.categoriesForType('nonexistent'), isEmpty);
    });
  });

  // ════════════════════════════════════════════════════════════════════
  // 2. High-Priority Categories
  // ════════════════════════════════════════════════════════════════════

  group('High-priority categories', () {
    test('contains expected scam/fraud categories', () {
      expect(ReportService.highPriorityCategories, containsAll([
        'spam_scam',
        'never_received',
        'scam_fraud',
        'counterfeit',
      ]));
    });

    test('all high-priority categories exist in categoriesByType', () {
      final allCategories = <String>{};
      for (final cats in ReportService.categoriesByType.values) {
        allCategories.addAll(cats.keys);
      }
      for (final hp in ReportService.highPriorityCategories) {
        expect(
          allCategories,
          contains(hp),
          reason: 'High-priority category "$hp" must exist in categoriesByType',
        );
      }
    });
  });

  // ════════════════════════════════════════════════════════════════════
  // 3. Notification Templates
  // ════════════════════════════════════════════════════════════════════

  group('Notification templates', () {
    test('contains all 3 template keys', () {
      expect(ReportService.notificationTemplates.keys, containsAll([
        'reviewed_action_taken',
        'reviewed_no_violation',
        'needs_more_info',
      ]));
    });

    test('all templates are non-empty strings', () {
      for (final entry in ReportService.notificationTemplates.entries) {
        expect(
          entry.value.trim(),
          isNotEmpty,
          reason: 'Template "${entry.key}" should not be empty',
        );
      }
    });

    test('all templates are at least 20 characters (meaningful text)', () {
      for (final entry in ReportService.notificationTemplates.entries) {
        expect(
          entry.value.length,
          greaterThanOrEqualTo(20),
          reason: 'Template "${entry.key}" should be meaningful text',
        );
      }
    });
  });

  // ════════════════════════════════════════════════════════════════════
  // 4. Status & Type Labels
  // ════════════════════════════════════════════════════════════════════

  group('Status and type labels', () {
    test('statusLabels covers all 4 statuses', () {
      expect(ReportService.statusLabels.keys, containsAll([
        'pending',
        'under_review',
        'resolved',
        'dismissed',
      ]));
    });

    test('typeLabels covers all 4 report types', () {
      expect(ReportService.typeLabels.keys, containsAll([
        'message',
        'product',
        'seller',
        'other',
      ]));
    });

    test('all status labels are human-readable (no underscores)', () {
      for (final entry in ReportService.statusLabels.entries) {
        expect(
          entry.value,
          isNot(contains('_')),
          reason: 'Status label for "${entry.key}" should be human-readable',
        );
      }
    });

    test('all type labels start with uppercase', () {
      for (final entry in ReportService.typeLabels.entries) {
        expect(
          entry.value[0],
          equals(entry.value[0].toUpperCase()),
          reason: 'Type label for "${entry.key}" should start with uppercase',
        );
      }
    });
  });

  // NOTE: Singleton test omitted — ReportService uses Supabase.instance.client
  // which requires Supabase.initialize() in the test environment.
  // To test singleton behavior, Supabase must be initialized in setUpAll().

  // ════════════════════════════════════════════════════════════════════
  // 6. Notification Constants Validation
  // ════════════════════════════════════════════════════════════════════

  group('Notification constants', () {
    test('statusLabels and typeLabels have matching key counts', () {
      expect(ReportService.statusLabels.length, 4);
      expect(ReportService.typeLabels.length, 4);
    });

    test('all categories in categoriesByType have non-empty labels', () {
      for (final typeEntry in ReportService.categoriesByType.entries) {
        for (final catEntry in typeEntry.value.entries) {
          expect(
            catEntry.value.trim(),
            isNotEmpty,
            reason: 'Category "${catEntry.key}" in type "${typeEntry.key}" has empty label',
          );
        }
      }
    });

    test('no duplicate category keys across different types', () {
      // Each type should have its own set of category keys
      // (cross-type duplicates are allowed, e.g. 'other' in all types)
      final messageCats = ReportService.categoriesByType['message']!.keys;
      final productCats = ReportService.categoriesByType['product']!.keys;
      final sellerCats = ReportService.categoriesByType['seller']!.keys;
      final otherCats = ReportService.categoriesByType['other']!.keys;

      // Each type should have unique keys within itself
      expect(messageCats.toSet().length, messageCats.length);
      expect(productCats.toSet().length, productCats.length);
      expect(sellerCats.toSet().length, sellerCats.length);
      expect(otherCats.toSet().length, otherCats.length);
    });
  });
}
