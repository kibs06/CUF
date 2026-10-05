import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../constants/app_constants.dart';
import '../../models/foot_measurement.dart';
import '../../providers/auth_provider.dart';
import '../../providers/foot_measurement_provider.dart';
import '../../screens/customer/foot_instructions_screen.dart';
import '../../utils/try_on_fit.dart';
import '../../utils/try_on_saved_size.dart';
import '../foot_size_v2/glass_card.dart';

/// **V4.7's saved-size suggestion** — the one card that talks about the
/// customer's *saved* profile rather than the shoe in front of them.
///
/// The try-on screen's verdict (V4.6) grades the foot in the frame; this card
/// is the comparison that phase deliberately left out: when the live
/// measurement disagrees with the saved scan by more than 8 mm, the saved
/// recommendation behind the size may be stale, and the customer is told
/// rather than the size being changed for them. The comparison itself is pure
/// (`tryOnSavedSizeNoticeFor` in `lib/utils/try_on_saved_size.dart`); this
/// widget owns the read, the English and the glass.
///
/// **It reads, and it has to — the V1 card's lesson, repeated here.**
/// `FootMeasurementProvider` holds a measurement in memory only after a scan
/// *in this session* (`loadLatest` is called nowhere else in the app), so a
/// customer who scanned last week arrives with nothing. The card therefore
/// performs exactly one `loadLatest` per mount, and only when the profile says
/// the customer has a size on file; while the read is in flight, and if it
/// fails, the card renders nothing at all — a suggestion the app cannot back
/// with a measurement must not be drawn.
///
/// **It never switches sizes.** The notice carries two millimetres and no size;
/// the selected chip on the try-on screen is not read, not written, and not
/// consulted — the only action this card offers is a route to the scan flow
/// (`FootInstructionsScreen`), where a *new* measurement can change the saved
/// recommendation the normal way. The sentence is the roadmap's own (V4.7).
class TryOnSavedSizeCard extends StatefulWidget {
  /// The tracker's latest reading, from `liveFoot` — the same notifier V4.6's
  /// verdict card listens to.
  final TryOnLiveFoot live;

  const TryOnSavedSizeCard({super.key, required this.live});

  @override
  State<TryOnSavedSizeCard> createState() => _TryOnSavedSizeCardState();
}

class _TryOnSavedSizeCardState extends State<TryOnSavedSizeCard> {
  /// Whether the one saved-scan read has been started. Set in `build` (the
  /// value has to be true before the frame that schedules the read paints),
  /// and never reset: a second `loadLatest` for one mount would be a second
  /// query for an answer that cannot have changed.
  bool _readStarted = false;

  @override
  Widget build(BuildContext context) {
    final profile =
        context.select<AuthProvider, Map<String, dynamic>?>((p) => p.profile);
    final measurement = context
        .select<FootMeasurementProvider, FootMeasurement?>(
          (p) => p.latestMeasurement,
        );

    // The app's existing marker for "has a size on file" — the same one the
    // product page's card reads, so the two surfaces agree on who scanned.
    final hasProfile = AppConstants.hasFootSize(profile);

    if (hasProfile && measurement == null && !_readStarted) {
      _readStarted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _readSavedScan());
    }

    if (measurement == null) return const SizedBox.shrink();

    final notice = tryOnSavedSizeNoticeFor(
      live: widget.live,
      // The saved side is the engine's own number, not the raw fields: the
      // recommendation the customer may keep or update was derived from it
      // (the v2 E8 rule), and two sides of one comparison must not come from
      // two conversion paths.
      savedLengthMm: measurement.maxFootLength,
    );
    if (notice == null) return const SizedBox.shrink();

    // Carries its own trailing gap (the V4.6 card's rule), so a hidden notice
    // leaves no hole in the column.
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _body(notice),
    );
  }

  /// One read of the saved scan, once per mount. `loadLatest` never throws —
  /// it records `error` — and a failed read leaves `latestMeasurement` null,
  /// which this card already renders as nothing: a suggestion the app cannot
  /// back with a measurement is exactly the thing to stay quiet about.
  Future<void> _readSavedScan() async {
    if (!mounted) return;
    final provider = context.read<FootMeasurementProvider>();
    final userId =
        context.read<AuthProvider>().currentUser?['id']?.toString();
    if (userId == null || userId.isEmpty) return;
    await provider.loadLatest(userId);
  }

  Widget _body(TryOnSavedSizeNotice notice) {
    return GlassCard(
      key: const ValueKey('try-on-saved-size'),
      // A suggestion about old data, not an error about the shoe: the caution
      // tone, never the wrong-band error tone.
      tone: GlassTone.warning,
      borderRadius: BorderRadius.circular(18),
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.history, size: 22, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Your saved size may be stale — rescan?',
                      style: AppConstants.bodyStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'The foot in view measures ${notice.liveLengthMm.round()}'
                      ' mm; your saved scan measured '
                      '${notice.savedLengthMm.round()} mm.',
                      style: AppConstants.bodyStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.85),
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Your size won't change unless you rescan.",
                      style: AppConstants.bodyStyle(
                        fontSize: 10.5,
                        color: Colors.white.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              key: const ValueKey('try-on-saved-size-rescan'),
              onPressed: _openRescan,
              style: TextButton.styleFrom(
                foregroundColor: AppConstants.accent,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: const Size(0, 40),
              ),
              child: Text(
                'Rescan',
                style: AppConstants.bodyStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppConstants.accent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openRescan() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const FootInstructionsScreen()),
    );
  }
}
