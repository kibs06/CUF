import 'package:app/utils/try_on_fit.dart';
import 'package:app/utils/try_on_saved_size.dart';
import 'package:flutter_test/flutter_test.dart';

/// **V4.7's rules, as a table.** Whether the screen may suggest a rescan is a
/// pure function of one live reading and one saved scan length — no camera, no
/// provider, no controller — so every silence and the one sentence can be
/// pinned here.
///
/// Three things are being protected:
///
///   1. **The silences.** No lock, no reading, a broken number on either side,
///      an implausible "foot", or a difference inside the 8 mm band must all
///      produce null — never a suggestion the app cannot back.
///   2. **The threshold is the roadmap's own, and it is strict.** Exactly
///      8 mm is not stale; 8.1 mm is. The boundary is the whole point of the
///      constant.
///   3. **It is a comparison, not a merge, and the notice carries no size** —
///      which is what makes "never silently switch sizes" a property of the
///      types rather than a promise in a comment.
void main() {
  TryOnLiveFoot live(double? lengthMm, {bool locked = true}) =>
      TryOnLiveFoot(lengthMm: lengthMm, quality: 0.9, locked: locked);

  TryOnSavedSizeNotice? notice({
    double? liveMm = 273,
    double? savedMm = 264,
    bool locked = true,
  }) =>
      tryOnSavedSizeNoticeFor(
        live: live(liveMm, locked: locked),
        savedLengthMm: savedMm,
      );

  group('silence', () {
    test('an unlocked tracker stays silent, however far apart the numbers are',
        () {
      expect(notice(locked: false), isNull);
    });

    test('no live reading yet, or a broken one, stays silent', () {
      expect(notice(liveMm: null), isNull);
      expect(notice(liveMm: double.nan), isNull);
      expect(notice(liveMm: double.infinity), isNull);
      expect(notice(liveMm: 0), isNull);
      expect(notice(liveMm: -200), isNull);
    });

    test('an implausible live length is refused, not compared', () {
      // The engine's band, reused: a 40 mm "foot" is a bad reading.
      expect(notice(liveMm: 40), isNull);
      expect(notice(liveMm: 400), isNull);
    });

    test('no saved scan length, or a broken one, stays silent', () {
      expect(notice(savedMm: null), isNull);
      expect(notice(savedMm: double.nan), isNull);
      expect(notice(savedMm: 0), isNull);
      expect(notice(savedMm: -1), isNull);
    });

    test('an implausible saved length is refused too', () {
      expect(notice(savedMm: 40), isNull);
      expect(notice(savedMm: 400), isNull);
    });

    test('a difference inside the band stays silent — both directions', () {
      // Exactly 8 mm is a foot measured twice on different days.
      expect(notice(liveMm: 273, savedMm: 265), isNull);
      expect(notice(liveMm: 265, savedMm: 273), isNull);
      expect(notice(liveMm: 270, savedMm: 264), isNull);
    });
  });

  group('the suggestion', () {
    test('more than 8 mm — live longer — produces the notice', () {
      final result = notice(liveMm: 273.4, savedMm: 264)!;

      expect(result.liveLengthMm, 273.4);
      expect(result.savedLengthMm, 264);
      expect(result.differenceMm, closeTo(9.4, 0.001));
      expect(result.isLiveLonger, isTrue);
    });

    test('more than 8 mm — live shorter — produces it too', () {
      final result = notice(liveMm: 255, savedMm: 265)!;

      expect(result.differenceMm, closeTo(-10, 0.001));
      expect(result.isLiveLonger, isFalse);
    });

    test('just over the line is enough', () {
      expect(notice(liveMm: 273.1, savedMm: 265), isNotNull);
      expect(notice(liveMm: 265, savedMm: 273.1), isNotNull);
    });
  });
}
