import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_constants.dart';
import 'app_palette.dart';

/// Builds the app's `ThemeData` for a brightness.
///
/// This is the *Material* layer — dialogs, switches, snackbars, default text
/// styles. The app's own screens mostly do not read it; they paint from the
/// brightness-aware tokens in `AppConstants` / `SellerTheme`. Both layers
/// resolve from the same [AppPalette] and the same published brightness, so
/// they can never disagree.
ThemeData buildAppTheme(Brightness brightness) {
  final palette = AppPalette.of(brightness);
  final isDark = brightness == Brightness.dark;

  // Ink drawn on a clay/espresso/error fill. Those fills keep their brand
  // colour in both modes, so the ink on them stays white.
  final onAccent = palette.inkInverse;

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: ColorScheme(
      brightness: brightness,
      primary: AppConstants.primary,
      onPrimary: onAccent,
      secondary: palette.onPage,
      onSecondary: onAccent,
      error: AppConstants.error,
      onError: onAccent,
      surface: palette.page,
      onSurface: palette.onPage,
    ),

    // Apply custom font themes globally.
    textTheme:
        GoogleFonts.dmSansTextTheme(ThemeData(brightness: brightness).textTheme)
            .copyWith(
      displayLarge: GoogleFonts.playfairDisplay(color: palette.onPage),
      displayMedium: GoogleFonts.playfairDisplay(color: palette.onPage),
      displaySmall: GoogleFonts.playfairDisplay(color: palette.onPage),
      headlineLarge: GoogleFonts.playfairDisplay(color: palette.onPage),
      headlineMedium: GoogleFonts.playfairDisplay(color: palette.onPage),
      headlineSmall: GoogleFonts.playfairDisplay(color: palette.onPage),
    ),

    // Switch theme styles.
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          // White thumb on the clay track, in both modes.
          return onAccent;
        }
        return AppConstants.primary.withValues(alpha: 0.5);
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return AppConstants.primary;
        }
        // An unselected track is the one place the hairline token is the
        // wrong tool: it must read as a *control*, not a divider, so on dark
        // it is drawn stronger than [AppPalette.hairline].
        return palette.hairline.withValues(alpha: isDark ? 0.6 : 0.3);
      }),
    ),

    // Dialog styles.
    dialogTheme: DialogThemeData(
      backgroundColor: palette.page,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  );
}

/// Repaints the whole widget tree after a brightness change.
///
/// **Why this is necessary.** The app paints from static tokens rather than
/// `Theme.of(context)`, so its widgets register no dependency on an
/// `InheritedWidget` that a brightness change could notify. Flutter's own
/// route scope only re-runs a page's builder when *that route's* dependencies
/// change (`_ModalScopeState.didChangeDependencies` → `_page = null`), which
/// never happens here — so without this, toggling the theme in Settings would
/// repaint the Material widgets and leave every custom surface on the old
/// palette.
///
/// It walks the element tree and marks each element dirty. Nothing is
/// disposed: element state (scroll offsets, text controllers, the navigator's
/// route stack) is preserved, unlike swapping in a new key on the app.
///
/// Called once per change from a post-frame callback, so it also can't mark
/// elements dirty in the middle of a build.
class AppThemeRefresh {
  AppThemeRefresh._();

  static void rebuildAll() {
    final root = WidgetsBinding.instance.rootElement;
    if (root == null) return;

    // Collect first: marking elements dirty can rebuild and re-parent
    // children, which would corrupt a walk in progress.
    final elements = <Element>[];
    void collect(Element element) {
      elements.add(element);
      element.visitChildren(collect);
    }

    collect(root);
    for (final element in elements) {
      if (element.mounted) element.markNeedsBuild();
    }
  }
}
