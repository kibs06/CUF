import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/constants/app_brightness.dart';
import 'package:app/constants/app_constants.dart';
import 'package:app/constants/app_palette.dart';
import 'package:app/constants/seller_theme_constants.dart';
import 'package:app/providers/theme_provider.dart';
import 'package:app/services/theme_service.dart';

/// The dark-mode foundation: which tokens follow the brightness, that light
/// mode is unchanged, and that the palette is legible in both modes.
///
/// The light assertions are deliberately exact hexes. Their job is to fail if
/// a later edit moves the light palette while adding a dark value — the one
/// regression this migration is not allowed to cause.

double _luminance(Color color) {
  // WCAG relative luminance: linearise each sRGB channel, then weight them.
  double channel(double value) {
    return value <= 0.03928
        ? value / 12.92
        : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
}

/// WCAG contrast ratio between two opaque colours.
double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  group('light palette is unchanged', () {
    test('every surface and ink token still resolves to its shipped hex', () {
      // Nothing published a brightness, so this is the pre-dark-mode state.
      expect(AppBrightness.isResolved, isFalse);

      expect(AppConstants.surfaceLight, const Color(0xFFFFFFFF));
      expect(AppConstants.surfaceSubtle, const Color(0xFFF5F5F5));
      expect(AppConstants.creamDeep, const Color(0xFFF5F5F5));
      expect(AppConstants.sellerCardBg, const Color(0xFFFFFFFF));
      expect(AppConstants.secondary, const Color(0xFF111111));
      expect(AppConstants.borderGray, const Color(0xFFE5E5E5));

      expect(SellerTheme.creamBg, const Color(0xFFFFFFFF));
      expect(SellerTheme.card, const Color(0xFFFFFFFF));
      expect(SellerTheme.cardBorder, const Color(0xFFE8E8E8));
      expect(SellerTheme.textMuted, const Color(0xFF6B6B6B));
      expect(SellerTheme.textSecondary, const Color(0xFF4A4A4A));

      // Brand and semantic fills stay put in both modes.
      expect(AppConstants.primary, const Color(0xFF8B5A2B));
      expect(AppConstants.accent, const Color(0xFF4ECDC4));
      expect(AppConstants.surfaceDark, const Color(0xFF111111));
      expect(AppConstants.inkInverse, const Color(0xFFFFFFFF));
    });

    test('shadows survive on light', () {
      expect(AppConstants.warmShadow, isNotEmpty);
      expect(AppConstants.sellerShadow, isNotEmpty);
    });
  });

  group('tokens follow the published brightness', () {
    tearDown(AppBrightness.reset);

    test('surfaces and ink flip to the dark roles', () {
      AppBrightness.set(Brightness.dark);

      expect(AppBrightness.isDark, isTrue);
      expect(AppConstants.surfaceLight, AppPalette.dark.page);
      expect(AppConstants.surfaceSubtle, AppPalette.dark.subtle);
      expect(AppConstants.creamDeep, AppPalette.dark.band);
      expect(AppConstants.sellerCardBg, AppPalette.dark.raised);
      expect(AppConstants.secondary, AppPalette.dark.onPage);
      expect(AppConstants.borderGray, AppPalette.dark.hairline);

      expect(SellerTheme.creamBg, AppPalette.dark.page);
      expect(SellerTheme.card, AppPalette.dark.raised);
      expect(SellerTheme.cardBorder, AppPalette.dark.hairlineOnRaised);
      expect(SellerTheme.textMuted, AppPalette.dark.muted);
      expect(SellerTheme.textSecondary, AppPalette.dark.mutedStrong);

      // Pinned tokens must NOT move, or the AR/camera screens and every
      // clay-fill ink would be repainted by a theme toggle.
      expect(AppConstants.primary, const Color(0xFF8B5A2B));
      expect(AppConstants.surfaceDark, const Color(0xFF111111));
      expect(AppConstants.inkInverse, const Color(0xFFFFFFFF));
    });

    test('shadows collapse on dark (they are invisible on near-black)', () {
      AppBrightness.set(Brightness.dark);

      expect(AppConstants.warmShadow, isEmpty);
      expect(AppConstants.sellerShadow, isEmpty);
    });

    // testWidgets, not test: the text helpers build GoogleFonts styles, and
    // under the plain test runner their font fetch surfaces as an unhandled
    // async error. (This is also how every existing widget test tolerates it.)
    testWidgets(
        'text helpers default to the page ink and honour an explicit colour',
        (tester) async {
      AppBrightness.set(Brightness.dark);
      expect(AppConstants.bodyStyle().color, AppPalette.dark.onPage);
      expect(AppConstants.headlineStyle().color, AppPalette.dark.onPage);
      expect(AppConstants.monoStyle().color, AppPalette.dark.onPage);

      // The default is what a rendered Text actually receives — the whole
      // point of resolving it inside the helper.
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) =>
              Text('probe', style: AppConstants.bodyStyle()),
        ),
      ));
      expect(
        tester.widget<Text>(find.text('probe')).style!.color,
        AppPalette.dark.onPage,
      );

      // An explicit colour still wins — call sites that pin ink keep it.
      expect(AppConstants.bodyStyle(color: AppConstants.inkInverse).color,
          AppConstants.inkInverse);

      AppBrightness.set(Brightness.light);
      expect(AppConstants.bodyStyle().color, AppPalette.light.onPage);
    });

    testWidgets('a widget built after the flip paints dark tokens',
        (tester) async {
      const probeKey = ValueKey('brightness-probe');
      Widget probe() => Builder(
            builder: (context) => ColoredBox(
              key: probeKey,
              color: AppConstants.surfaceLight,
              child: const SizedBox(width: 10, height: 10),
            ),
          );

      await tester.pumpWidget(MaterialApp(home: probe()));
      expect(
        tester.widget<ColoredBox>(find.byKey(probeKey)).color,
        AppPalette.light.page,
      );

      AppBrightness.set(Brightness.dark);
      await tester.pumpWidget(MaterialApp(home: probe()));
      expect(
        tester.widget<ColoredBox>(find.byKey(probeKey)).color,
        AppPalette.dark.page,
      );
    });
  });

  group('publish semantics', () {
    tearDown(AppBrightness.reset);

    test('the first publication never asks for a repaint', () {
      // Nothing has been painted with the old palette yet, and asking for a
      // rebuild here would cost dark-mode users a light first frame.
      expect(AppBrightness.publish(Brightness.dark), isFalse);
      expect(AppBrightness.current, Brightness.dark);
      expect(AppBrightness.isResolved, isTrue);
    });

    test('only a change after the first frame asks for a repaint', () {
      AppBrightness.publish(Brightness.light);
      expect(AppBrightness.publish(Brightness.light), isFalse);
      expect(AppBrightness.publish(Brightness.dark), isTrue);
      expect(AppBrightness.publish(Brightness.dark), isFalse);
    });
  });

  group('palette legibility', () {
    // The values in AppPalette are candidates; this is the check that keeps
    // them honest. Failing here means an unreadable dark mode, not a style
    // disagreement.
    for (final entry in {
      'light': AppPalette.light,
      'dark': AppPalette.dark,
    }.entries) {
      final name = entry.key;
      final palette = entry.value;

      test('$name: body ink clears AA on the page', () {
        expect(_contrast(palette.onPage, palette.page), greaterThanOrEqualTo(4.5),
            reason: '$name page ink must be readable');
        expect(_contrast(palette.muted, palette.page), greaterThanOrEqualTo(4.5),
            reason: '$name muted text must be readable');
        expect(_contrast(palette.mutedStrong, palette.page),
            greaterThanOrEqualTo(4.5));
      });

      test('$name: ink on the raised surface clears AA', () {
        expect(_contrast(palette.onPage, palette.raised),
            greaterThanOrEqualTo(4.5));
      });

      test('$name: the card edge is visible against what is behind it', () {
        // Not a text threshold: a hairline only has to be *distinguishable*,
        // and on dark it is the card's only edge.
        expect(_contrast(palette.hairline, palette.page),
            greaterThanOrEqualTo(1.2));
        expect(_contrast(palette.hairlineOnRaised, palette.raised),
            greaterThanOrEqualTo(1.2));
      });

      test('$name: ink on the brand clay fill clears AA', () {
        expect(_contrast(palette.inkInverse, AppConstants.primary),
            greaterThanOrEqualTo(4.5));
      });

      test('$name: the accent ink clears the 3:1 large-text bar', () {
        expect(_contrast(palette.primaryInk, palette.page),
            greaterThanOrEqualTo(3.0));
      });

      test('$name: the fixed accent chips can carry their pinned ink', () {
        // The camel and olive tag chips keep their hex in both modes, so
        // their ink is pinned to AppConstants.inkOnLightAccent.
        expect(_contrast(AppConstants.inkOnLightAccent, const Color(0xFFC08552)),
            greaterThanOrEqualTo(3.0));
        expect(_contrast(AppConstants.inkOnLightAccent, const Color(0xFF556B2F)),
            greaterThanOrEqualTo(3.0));
      });
    }

    test('dark is actually dark and light is actually light', () {
      expect(_luminance(AppPalette.dark.page), lessThan(0.05));
      expect(_luminance(AppPalette.light.page), greaterThan(0.8));
      expect(_luminance(AppPalette.dark.raised),
          greaterThan(_luminance(AppPalette.dark.page)),
          reason: 'on dark, raised must be LIGHTER than the page or cards '
              'flatten once shadows are gone');
    });
  });

  group('ThemeService', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('defaults to system for a fresh install', () async {
      expect(await ThemeService.instance.load(), ThemeMode.system);
    });

    test('round-trips every mode', () async {
      for (final mode in ThemeMode.values) {
        await ThemeService.instance.save(mode);
        expect(await ThemeService.instance.load(), mode);
      }
    });

    test('a stored value it does not recognise falls back to system', () {
      expect(ThemeService.decode('sepia'), ThemeMode.system);
      expect(ThemeService.decode(null), ThemeMode.system);
      expect(ThemeService.decode('dark'), ThemeMode.dark);
      expect(ThemeService.decode('light'), ThemeMode.light);
    });

    test('the stored strings are stable', () {
      // Renaming these silently reverts every existing install to system.
      expect(ThemeService.encode(ThemeMode.system), 'system');
      expect(ThemeService.encode(ThemeMode.light), 'light');
      expect(ThemeService.encode(ThemeMode.dark), 'dark');
    });
  });

  group('ThemeProvider', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('applies immediately and persists in the background', () async {
      final provider = ThemeProvider();
      var notifications = 0;
      provider.addListener(() => notifications++);

      expect(provider.mode, ThemeMode.system);
      expect(provider.isPinned, isFalse);

      await provider.setMode(ThemeMode.dark);
      expect(provider.mode, ThemeMode.dark);
      expect(provider.isPinned, isTrue);
      expect(notifications, 1);
      expect(await ThemeService.instance.load(), ThemeMode.dark);

      // Re-tapping the current option must not repaint the app.
      await provider.setMode(ThemeMode.dark);
      expect(notifications, 1);
    });

    test('labels read as the sheet shows them', () {
      expect(ThemeProvider.label(ThemeMode.system), 'System');
      expect(ThemeProvider.label(ThemeMode.light), 'Light');
      expect(ThemeProvider.label(ThemeMode.dark), 'Dark');
    });
  });
}
