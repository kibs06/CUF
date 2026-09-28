import 'diag_logger.dart' show navDiag;

/// Where a fit shadow record goes — one function, on purpose.
///
/// Today: the on-device diag channel, which appends ms-stamped lines to
/// `nav_diag.log` in the app documents directory and exposes a share-sheet
/// export from the foot-instructions screen (`FootInstructionsScreen`, the screen the scan flow starts from). It is the same channel `PerfTrace` uses
/// (`lib/utils/nav_perf.dart`), and for the same reason it documents: adb/USB
/// debugging is unavailable on the test device, so on-device evidence has to be
/// captured in-app and exported from the app.
///
/// **This is the seam, and it is temporary by association.** The diag logger is
/// Phase-1b scaffolding with a removal checklist of its own; when it goes, this
/// one function is repointed at whatever replaces it — a `try_on_events` row
/// (architecture §2.7.4), Sentry breadcrumbs (not integrated in this app
/// today), or a file of its own. Nothing else in the fit-verdict feature knows
/// where the records end up, so that is a one-line change and not a hunt.
///
/// The two switches upstream of every call are worth stating together:
/// `AppConstants.virtualFitShadowEnabled` decides whether a record is *built*
/// (and therefore whether the page reads the saved scan at all), and
/// `kNavDiagEnabled` in `diag_logger.dart` decides whether the channel stores
/// it. Both are off in a build that has not opted in, so a shipped app writes
/// nothing at all.
void logFitShadow(String line) => navDiag(line);
