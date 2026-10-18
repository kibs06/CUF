/// The 3D viewer's orientation, camera and size for a foot captured in AR.
///
/// The viewer is `<model-viewer>` inside a WebView. This file is the one place that turns the
/// native still-capture pose into its attribute strings, so the mapping can be unit-tested without
/// a WebView. It is pure Dart with no Flutter imports.
///
/// **What it applies, and what it does not.** Yaw turns the shoe onto the foot's floor-plane
/// direction, the camera looks straight down at the shoe with its toe pointing up the screen, and
/// the shoe is scaled to the measured heel-to-toe length. Pitch (the foot's tilt) is read by the
/// capture but not applied here: a top view hides it, and the viewer has no tilt control yet.
class ShoeFitView {
  const ShoeFitView({
    required this.orientation,
    required this.cameraOrbit,
    this.scale,
  });

  /// `<model-viewer>` `orientation`: `"roll pitch yaw"`, in degrees.
  final String orientation;

  /// `<model-viewer>` `cameraOrbit`: `"theta phi radius"`.
  final String cameraOrbit;

  /// `<model-viewer>` `scale`: `"x y z"`, or null when no authored length is known to scale against.
  final String? scale;

  @override
  bool operator ==(Object other) =>
      other is ShoeFitView &&
      other.orientation == orientation &&
      other.cameraOrbit == cameraOrbit &&
      other.scale == scale;

  @override
  int get hashCode => Object.hash(orientation, cameraOrbit, scale);

  @override
  String toString() =>
      'ShoeFitView(orientation: $orientation, cameraOrbit: $cameraOrbit, scale: $scale)';
}

/// The top-down camera's polar angle, in degrees from straight above.
///
/// Two degrees off the pole rather than zero. At exactly zero the camera's up vector is degenerate
/// and the view can flip, and two degrees still reads as a top view.
const String kShoeFitTopOrbitPhi = '2deg';

/// The camera's distance, as a share of the auto-framed distance. Matches the default view.
const String kShoeFitOrbitRadius = '105%';

/// Maps a captured foot pose to the viewer's fit, or null when the pose cannot be used.
///
/// **The camera placement.** `<model-viewer>` puts a camera at `theta` around the vertical axis,
/// measured from +Z. From above, the screen's up direction points away from that camera, so the
/// shoe's forward direction (+Z after the yaw) lands up the screen when the camera sits 180° round
/// from it: `theta = yaw + 180`.
///
/// **The size.** The shoe is scaled so its authored length matches the measured foot length, and
/// the shoe's own toe allowance is not modelled. A null [authoredLengthMm] leaves the scale unset,
/// so the orientation and the camera still apply and only the size is skipped.
ShoeFitView? shoeFitViewFor({
  required double yawDeg,
  required double lengthMm,
  required double? authoredLengthMm,
}) {
  if (!yawDeg.isFinite || !lengthMm.isFinite || lengthMm <= 0) return null;

  final yaw = _wrapDegrees(yawDeg);
  final theta = _wrapDegrees(yaw + 180);

  String? scale;
  if (authoredLengthMm != null &&
      authoredLengthMm.isFinite &&
      authoredLengthMm > 0) {
    final factor = lengthMm / authoredLengthMm;
    final uniform = factor.toStringAsFixed(4);
    scale = '$uniform $uniform $uniform';
  }

  return ShoeFitView(
    orientation: '0deg 0deg ${_degrees(yaw)}',
    cameraOrbit: '${_degrees(theta)} $kShoeFitTopOrbitPhi $kShoeFitOrbitRadius',
    scale: scale,
  );
}

/// Wraps an angle into `[-180, 180)`.
double _wrapDegrees(double deg) => ((deg + 180) % 360 + 360) % 360 - 180;

String _degrees(double deg) => '${deg.toStringAsFixed(3)}deg';
