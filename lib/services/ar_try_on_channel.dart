/// Platform-channel wrapper for the production AR try-on plugin
/// (`docs/RoadMap/VIRTUAL_FITTING_ROADMAP.md` V3.1, contract
/// `VIRTUAL_FITTING_ARCHITECTURE.md` §2.8).
///
/// **This is the Dart half only.** The native side — `ArTryOnPlugin`,
/// `ArTryOnView`, `ShoeModelNode` (V3.1–V3.3) — is not written, and it is
/// deliberately *not* this task: `ArTryOnView` hosts `ArSceneView`, which is
/// exactly the renderer route V0.7 left undecided (SceneView + Compose measured
/// at +27.7 MB on the release APK against a ≤8 MB budget). Writing this file now
/// is the part of the contract that decision cannot invalidate: the channel
/// names, the payload shapes and the failure vocabulary are the same either
/// way, and every native implementation must answer to them.
///
/// On a build with no native plugin every call here throws
/// `MissingPluginException` — which is not a bug to guard against but the
/// expected present-day answer, and the controller turns it into the simulated
/// screen like any other AR failure.
///
/// **Names.** `TryOnStartResult` and the event class names intentionally match
/// the V0 spike's (`ar_try_on_spike_channel.dart`), whose header says the spike
/// exists so its callers can move to this file without relearning the API. The
/// spike, its screen and its native package are deleted together on retirement;
/// until then **import one or the other, never both.**
///
/// **V4 extended the contract rather than guessing at it (2026-10-04).** The V3
/// subset deliberately omitted `setFootPose`, `setFootMask` and the `footLock`
/// event because nothing could call them; V4's detection loop is now that
/// caller, so all three are here, plus [FootPoseFrame] — the payload §2.8
/// specifies (`heelUv`, `toeUv`, `widthUv[2]`, `confidence`, `footSide`).
///
/// **One addition is not in §2.8's table: [ArTryOnChannel.acquireCameraFrame].**
/// §2.8's Dart→native list starts at `setFootPose`, which silently assumes Dart
/// already has frames — and it cannot, because the try-on session owns the
/// camera while the scan's `ArCoreChannel` talks to a *different* plugin. D3
/// keeps detection in Dart, so the frames have to come across; the architecture
/// marks the copied frame acquisition as deliberate debt ("if a third AR screen
/// ever appears, extract a shared `ArSessionController` then — not now"). The
/// payload is the scan's own [ArCameraFrame], so a second frame vocabulary does
/// not exist.
library;

import 'dart:async';

// `Uint8List` and `Offset` come from services.dart's exports of dart:typed_data
// and dart:ui.
import 'package:flutter/services.dart';

import '../utils/shoe_model_resolver.dart';
import 'ar_core_channel.dart' show ArCameraFrame;

/// `MethodChannel` name, beside the scan's `com.solevision/ar_foot_sizing`.
const String kArTryOnMethodChannel = 'com.solevision/ar_try_on';

/// `EventChannel` name for native → Dart events.
const String kArTryOnEventChannel = 'com.solevision/ar_try_on/events';

/// Platform-view type the native side registers (`AR_TRY_ON_VIEW_TYPE` in
/// `ArTryOnPlugin.kt`), and the string V3.5's `AndroidView` embeds.
///
/// It lives here, beside the two channel names, because the rule this file's
/// header states applies to it too: the wire format is the one thing a renderer
/// decision cannot invalidate, and a view type that drifts by a character
/// produces the same symptom as a native side that was never built
/// (`MissingPluginException`, then the simulated screen).
const String kArTryOnViewType = 'com.solevision/ar_try_on/view';

int _asInt(Object? value, {required int fallback}) =>
    value is num ? value.toInt() : fallback;

double _asDouble(Object? value) => value is num ? value.toDouble() : 0;

/// How the native renderer is driven: by the tracked foot, or by a floor tap.
///
/// §2.8 calls this a capability/QA switch, and that is what it is for now —
/// V3's floor-place MVP runs [`floor`]; [`foot`] is V4's mode, and being able to
/// force either is how a device session isolates a tracking bug from a
/// rendering one.
enum TryOnInteractionMode {
  foot,
  floor;

  /// The string the native side switches on.
  String get wireName => name;
}

/// Outcome of asking the native side to start an AR session.
///
/// Same contract — and the same reason codes — as `ArSessionStartResult` in
/// `ar_core_channel.dart`, so failure handling is shared with the shipped scan:
/// `unsupported_device`, `needs_install`, `user_opted_out`, `unsupported`,
/// `timeout`, `error`.
class TryOnStartResult {
  final bool started;
  final String? reason;
  final String? message;

  const TryOnStartResult({required this.started, this.reason, this.message});

  factory TryOnStartResult.fromNative(Object? native) {
    if (native is Map) {
      // `is bool`, not `as bool?`: a native build that sends `"true"` instead of
      // `true` must fail closed rather than throw across the channel boundary.
      final started = native['started'];
      return TryOnStartResult(
        started: started is bool && started,
        reason: native['reason']?.toString(),
        message: native['message']?.toString(),
      );
    }
    if (native is bool) return TryOnStartResult(started: native);
    return const TryOnStartResult(
      started: false,
      reason: 'error',
      message: 'Unexpected startSession response from native side',
    );
  }

  @override
  String toString() => 'TryOnStartResult(started: $started, reason: $reason, '
      'message: $message)';
}

/// Everything native needs to show a shoe: the **local** file plus its identity.
///
/// The path is a local file, never a URL: Dart downloads and verifies (V2.5),
/// and the native side does no HTTP in v1 (§2.8, §2.4's `ModelCache`). The
/// digest travels with it so a native build can check what it was handed rather
/// than trusting the caller.
class TryOnModelSpec {
  /// Absolute path of the verified `.glb` on disk.
  final String path;

  /// `product_models.id` — the cache key's identity half.
  final int modelId;

  /// Lowercase SHA-256 hex digest of the bytes at [path].
  final String sha256;

  /// **External** heel-to-toe length of the physical sample, in mm (§2.5.1).
  /// Drives scale; it is not the internal last the fit verdict reads.
  final double? authoredLengthMm;

  /// Optional `{heelOffsetMm, yawOffsetDeg}` (§2.5.1's alignment block).
  final Map<String, dynamic>? alignmentJson;

  const TryOnModelSpec({
    required this.path,
    required this.modelId,
    required this.sha256,
    this.authoredLengthMm,
    this.alignmentJson,
  });

  /// The handover for a model the resolver has already made local.
  ///
  /// **One factory rather than a constructor call at each site**, because there
  /// are two sites now and they feed the *same* renderer: the AR session and the
  /// product page's inline 3D box. A field one of them forgets is a shoe that
  /// renders correctly in one place and wrongly in the other — subtly, and only
  /// on the models that carry that field.
  factory TryOnModelSpec.fromModel(ShoeModelSpec spec, {required String path}) =>
      TryOnModelSpec(
        path: path,
        modelId: spec.id,
        sha256: spec.sha256,
        authoredLengthMm: spec.authoredLengthMm,
        alignmentJson: spec.alignmentJson,
      );

  Map<String, Object?> toMap() => <String, Object?>{
        'path': path,
        'modelId': modelId,
        'sha256': sha256,
        'authoredLengthMm': authoredLengthMm,
        'alignmentJson': alignmentJson,
      };

  @override
  String toString() => 'TryOnModelSpec(id: $modelId, $path)';
}

/// Rolling frame-rate sample from the native side (sampled every ~5 s, §2.8).
///
/// This is the number V3's exit criterion is written against (≥30 fps on a mid
/// device) and V5's dashboard charts; it is carried as a type so the controller
/// never has to hold two loose doubles.
class TryOnPerf {
  final double avgFps;
  final double frameMs;

  const TryOnPerf({required this.avgFps, required this.frameMs});

  @override
  bool operator ==(Object other) =>
      other is TryOnPerf &&
      other.avgFps == avgFps &&
      other.frameMs == frameMs;

  @override
  int get hashCode => Object.hash(avgFps, frameMs);

  @override
  String toString() => 'TryOnPerf(${avgFps.toStringAsFixed(1)} fps, '
      '${frameMs.toStringAsFixed(1)} ms)';
}

/// One foot observation, as the renderer's tracker consumes it (§2.8).
///
/// Every point is **normalized upright-image UV** (0–1), the space ARCore's
/// `hitTest` takes — the same space `FootPoint` uses, so no conversion happens
/// between detection and the channel.
///
/// **Dart publishes observations, not decisions.** There is no smoothing, no
/// world basis and no lock state in this payload: all of that lives in the
/// native `FootPoseTracker`, which can see the frames between these samples and
/// can undo nothing Dart has already filtered. The one thing Dart *has* decided
/// is which frames are worth sending — `TemporalFootGate`'s consecutive-positive
/// requirement — because dropping an obviously bad frame at the source is
/// cheaper than teaching the tracker to distrust it.
class FootPoseFrame {
  /// Rear-most extent of the foot (the heel).
  final Offset heelUv;

  /// Forward-most extent (the tip of the longest toe).
  final Offset toeUv;

  /// The widest-point pair, or empty when the detector has none (the
  /// pose-based detector never does; segmentation usually does). Two points
  /// when present — the native side uses them to orient the shoe's lateral
  /// axis, and absence is legal rather than an error.
  final List<Offset> widthUv;

  /// The combined quality score the frame was accepted on (§2.9's
  /// `qualityScore`, the same number the scan's sample gate reads). The
  /// native lock enters at ≥0.7 and leaves below 0.45 (§2.9/§2.10).
  final double confidence;

  /// `'left'` or `'right'` when the detector is sure, null when it is not.
  final String? footSide;

  const FootPoseFrame({
    required this.heelUv,
    required this.toeUv,
    this.widthUv = const <Offset>[],
    required this.confidence,
    this.footSide,
  });

  /// The wire shape §2.8 specifies.
  ///
  /// Built by hand rather than reflected: every value crosses a platform
  /// boundary where `Offset` is not a type the channel knows, and `widthUv`
  /// is empty for most frames today, so the list must survive an empty case.
  Map<String, Object?> toMap() => <String, Object?>{
        'heelUv': <String, double>{'x': heelUv.dx, 'y': heelUv.dy},
        'toeUv': <String, double>{'x': toeUv.dx, 'y': toeUv.dy},
        'widthUv': <Map<String, double>>[
          for (final Offset point in widthUv)
            <String, double>{'x': point.dx, 'y': point.dy},
        ],
        'confidence': confidence,
        'footSide': footSide,
      };

  @override
  String toString() => 'FootPoseFrame(heel: $heelUv, toe: $toeUv, '
      'width: ${widthUv.length}, conf: ${confidence.toStringAsFixed(2)}, '
      'side: ${footSide ?? '-'})';
}

/// One message from the native renderer.
sealed class ArTryOnEvent {
  const ArTryOnEvent();

  /// Parses one native payload.
  ///
  /// Every value is read defensively (`is num`, `?.toString()`), the same rule
  /// the scan's channel and the V0 spike's parser follow: a newer native build
  /// sending a shape this Dart build has not heard of has to degrade into an
  /// odd-looking number or an unknown event, never into a crash on a screen the
  /// customer is holding.
  factory ArTryOnEvent.fromMap(Map<dynamic, dynamic> map) {
    final type = map['type']?.toString() ?? 'unknown';
    final rawData = map['data'];
    final data = rawData is Map
        ? Map<String, dynamic>.from(rawData)
        : <String, dynamic>{};
    return switch (type) {
      'modelLoaded' => TryOnModelLoadedEvent(
          loadMs: _asInt(data['loadMs'], fallback: -1),
          triangles: _asInt(data['triangles'], fallback: -1),
        ),
      'perf' => TryOnPerfEvent(
          perf: TryOnPerf(
            avgFps: _asDouble(data['avgFps']),
            frameMs: _asDouble(data['frameMs']),
          ),
        ),
      'error' => TryOnErrorEvent(
          reason: data['reason']?.toString() ?? 'error',
          message: data['message']?.toString(),
        ),
      'footLock' => TryOnFootLockEvent(
          locked: data['locked'] == true,
          quality: _asDouble(data['quality']),
          side: data['side']?.toString(),
        ),
      'footMeasure' => TryOnFootMeasureEvent(
          lengthMm: _asDouble(data['lengthMm']),
          quality: _asDouble(data['quality']),
        ),
      'status' => TryOnStatusEvent(line: data['line']?.toString() ?? ''),
      'screenshot' => TryOnScreenshotEvent(bytes: _asBytes(data['bytes'])),
      _ => ArTryOnUnknownEvent(type: type, data: data),
    };
  }
}

/// The model finished parsing and is in the scene.
class TryOnModelLoadedEvent extends ArTryOnEvent {
  /// Runs from the `setModel` call to the instance becoming available. The V0
  /// budget was ≤1.5 s warm / ≤4 s cold.
  final int loadMs;

  /// Triangle count actually loaded; `-1` when the native side did not say.
  final int triangles;

  const TryOnModelLoadedEvent({required this.loadMs, required this.triangles});
}

/// A frame-rate sample.
class TryOnPerfEvent extends ArTryOnEvent {
  final TryOnPerf perf;

  const TryOnPerfEvent({required this.perf});
}

/// The renderer failed — `renderer_init_failed`, `model_parse_failed`, …
class TryOnErrorEvent extends ArTryOnEvent {
  final String reason;
  final String? message;

  const TryOnErrorEvent({required this.reason, this.message});
}

/// The native tracker's lock state changed (§2.8's `footLock`).
///
/// **This drives the coach card, not the render** — the render is
/// native-resident, and this event exists so Dart can say "hold still" or "got
/// it" without asking. [quality] is the tracker's post-smoothing score, which
/// is why the Dart side does not compare it against the enter/leave thresholds
/// itself: the native hysteresis already decided, and a second opinion here
/// would flicker.
class TryOnFootLockEvent extends ArTryOnEvent {
  /// True when the tracker holds a lock, false when it lost or never had one.
  final bool locked;

  /// Post-smoothing quality (0–1).
  final double quality;

  /// `'left'`/`'right'` when the tracker knows which foot, null otherwise.
  final String? side;

  const TryOnFootLockEvent({
    required this.locked,
    required this.quality,
    this.side,
  });
}

/// **V4.6's live measurement** — the tracker's eased heel→toe length in mm,
/// with the smoothed quality it was read at.
///
/// The first event on this channel that is a *number* rather than a state, and
/// the one Dart's fit engine grades with: the verdict beside the shoe is built
/// from this reading, not from the saved scan, so it describes the foot in the
/// frame. Emitted at ~2 Hz while the tracker has an anchor (the view's own
/// throttle), so a malformed payload degrades to `0` here and the controller
/// refuses it rather than doing arithmetic on it.
class TryOnFootMeasureEvent extends ArTryOnEvent {
  /// Eased heel→toe length in millimetres. Zero/invalid when the native side
  /// said nothing usable; the controller drops those, never the card.
  final double lengthMm;

  /// Post-smoothing quality (0–1) at the instant the length was read.
  final double quality;

  const TryOnFootMeasureEvent({required this.lengthMm, required this.quality});
}

/// **The renderer's own heartbeat (V4.9)** — one line a second while
/// [ArTryOnChannel.setDiagnostics] is on, carrying `loop`, `foot`, `len`,
/// `scale`, `mask` and `thermal` (§2.16's heartbeat fields).
///
/// The native half has written this line since V4.2, but until V4.9 the only
/// switch that could ask for it belonged to the inline preview — the try-on
/// session's own readout was unreachable, which is exactly what a device
/// session would have discovered with no way to explain itself. The event type
/// is the other half: the readout goes on the screen, so a phone with no `adb
/// logcat` carries its numbers in a screenshot.
class TryOnStatusEvent extends ArTryOnEvent {
  /// The whole line, verbatim. Empty when a native build sent the event with
  /// nothing in it — the controller ignores those rather than drawing a blank
  /// strip over the camera.
  final String line;

  const TryOnStatusEvent({required this.line});
}

/// Async screenshot completion. `captureScreenshot` normally returns the bytes
/// directly; this is the channel's other way of delivering them.
class TryOnScreenshotEvent extends ArTryOnEvent {
  final Uint8List bytes;

  const TryOnScreenshotEvent({required this.bytes});
}

/// Forward-compatibility catch-all: an event type this Dart build has not heard
/// of (V5/V6 additions) reaches the controller as an unknown rather than as a
/// crash.
class ArTryOnUnknownEvent extends ArTryOnEvent {
  final String type;
  final Map<String, dynamic> data;

  const ArTryOnUnknownEvent({required this.type, required this.data});
}

Uint8List _asBytes(Object? value) =>
    value is Uint8List ? value : Uint8List(0);

/// Wrapper over the try-on method + event channels.
///
/// Tests subclass this and override the members they drive (the scan's
/// controllers take an injected channel for exactly this reason), or point the
/// real one at a mocked `MethodChannel`.
class ArTryOnChannel {
  ArTryOnChannel({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
  })  : _methods = methodChannel ?? const MethodChannel(kArTryOnMethodChannel),
        _eventChannel =
            eventChannel ?? const EventChannel(kArTryOnEventChannel);

  final MethodChannel _methods;
  final EventChannel _eventChannel;

  final StreamController<ArTryOnEvent> _events =
      StreamController<ArTryOnEvent>.broadcast();
  StreamSubscription<dynamic>? _subscription;

  /// Events from the native renderer. The first `attach` connects the platform
  /// stream; `detach` disconnects it.
  Stream<ArTryOnEvent> get events => _events.stream;

  /// Starts listening, so no event is lost between `startSession` and the first
  /// listener. Idempotent; `startSession` calls it too.
  void attach() {
    _subscription ??= _eventChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        if (event is Map) _events.add(ArTryOnEvent.fromMap(event));
      },
      onError: (Object error) {
        _events.add(
          TryOnErrorEvent(reason: 'error', message: error.toString()),
        );
      },
    );
  }

  /// Disconnects the platform stream.
  Future<void> detach() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  /// Asks the native side to start ARCore. Resolves when the session is
  /// resumed, refused, or the native 15 s safety net fires.
  ///
  /// **The platform view must already exist** — findings F17–F19: awaiting this
  /// before the native view is created deadlocks into that timeout on every
  /// device. `TryOnSessionController.startAr` is where that precondition is
  /// enforced from Dart.
  Future<TryOnStartResult> startSession() async {
    attach();
    final native = await _methods.invokeMethod<Object?>('startSession');
    return TryOnStartResult.fromNative(native);
  }

  /// Tears the session down. **Not called from Dart during normal teardown** —
  /// native teardown is single-owned by the platform view's disposal (the D1
  /// rule the scan controller follows too, after a double-stop caused a
  /// session-restart storm). Kept for QA and tests.
  Future<void> stopSession() => _methods.invokeMethod<void>('stopSession');

  /// Hands the native side the model. Legal before the view exists: the plugin
  /// parks it and applies it on view creation (F18).
  Future<void> setModel(TryOnModelSpec spec) =>
      _methods.invokeMethod<void>('setModel', spec.toMap());

  /// Recomputes the uniform scale for a selected size (§2.5.2). V3.3's caller.
  Future<void> setSize({
    required String sizeEu,
    num? refSizeEu,
    num? lastLengthMm,
  }) =>
      _methods.invokeMethod<void>('setSize', <String, Object?>{
        'sizeEu': sizeEu,
        'refSizeEu': refSizeEu,
        'lastLengthMm': lastLengthMm,
      });

  /// Applies the chosen colour's material overrides. V3.3's caller.
  Future<void> setColor(Map<String, dynamic> materialOverrides) =>
      _methods.invokeMethod<void>(
        'setColor',
        <String, Object?>{'materialOverrides': materialOverrides},
      );

  /// Publishes one foot observation (V4.1's caller, ≥5 Hz while searching).
  ///
  /// Answers `true` when the native tracker accepted the frame. The reply is
  /// deliberately not awaited by the loop's cadence logic: a dropped frame must
  /// not back-pressure the next one, and a failure here is already the
  /// simulated screen's business — not the renderer's.
  Future<void> setFootPose(FootPoseFrame frame) =>
      _methods.invokeMethod<void>('setFootPose', frame.toMap());

  /// Sends the downsampled foot mask for stencil occlusion (§2.10). V4.4's
  /// caller — **nothing calls this yet**, and the shape is here so the native
  /// side can be written against a pinned payload rather than a guess: 32×32
  /// bytes, ~1 KB per frame.
  Future<void> setFootMask({
    required Uint8List bytes32x32,
    required double confidence,
  }) =>
      _methods.invokeMethod<void>('setFootMask', <String, Object?>{
        'bytes': bytes32x32,
        'confidence': confidence,
      });

  /// **The detection loop's frame source.** Returns the most recent throttled
  /// CPU frame (NV21 + geometry), or null when the native side has none yet.
  ///
  /// Copied from the scan's plugin on purpose (the architecture records the
  /// duplication as debt): two ARCore sessions cannot exist at once, so the
  /// try-on session's plugin is the only thing that can serve frames while the
  /// try-on screen is up, and ML Kit needs NV21 — not a GPU texture. The
  /// response is the scan channel's own `ArCameraFrame`, parsed by the same
  /// `fromMap`, so there is exactly one frame vocabulary.
  Future<ArCameraFrame?> acquireCameraFrame() async {
    final native = await _methods.invokeMethod<Object?>('acquireCameraFrame');
    if (native is Map) return ArCameraFrame.fromMap(native);
    return null;
  }

  /// Places the shoe at a screen point — the manual fallback when no foot is
  /// found. V3.4's caller.
  Future<void> placeShoe({required double x, required double y}) =>
      _methods.invokeMethod<void>('placeShoe', <String, Object?>{'x': x, 'y': y});

  /// A PNG of the current frame, for the share sheet only (§2.8) — never
  /// auto-uploaded. Returns null when the native side has nothing to give.
  /// V3.7's caller.
  Future<Uint8List?> captureScreenshot() async {
    final native =
        await _methods.invokeMethod<Object?>('captureScreenshot');
    return native is Uint8List ? native : null;
  }

  /// Capability/QA switch between foot-driven and floor-placed rendering.
  Future<void> setTryOnMode(TryOnInteractionMode mode) =>
      _methods.invokeMethod<void>(
        'setTryOnMode',
        <String, Object?>{'mode': mode.wireName},
      );

  /// Ask the native renderer for its one-line heartbeat (`status` events, at
  /// most once a second) — **V4.9's readout seam.**
  ///
  /// QA only: the native side cannot read a Dart define, so this call *is* the
  /// switch's other half, and the try-on session's `foot=` / `len=` / `scale=`
  /// / `mask=` / `thermal=` line is emitted only for a build that makes it.
  /// Legal before the native view exists — the plugin parks it and applies it
  /// on view creation (the F18 contract) — so the readout is already on for a
  /// view whose session never starts.
  Future<void> setDiagnostics(bool enabled) =>
      _methods.invokeMethod<void>(
        'setDiagnostics',
        <String, Object?>{'enabled': enabled},
      );

  /// **V4.9: the night-aid torch** — the AR screen's flash toggle, passed
  /// straight to the native view. The native side stores the wish and applies
  /// it at session configure time, or reconfigures a live session on the spot.
  /// Fire-and-forget: a failed toggle is retried by the next tap, and losing
  /// one is one frame of dark feed, never a session fault.
  Future<void> setTorch(bool enabled) =>
      _methods.invokeMethod<void>(
        'setTorch',
        <String, Object?>{'enabled': enabled},
      );
}
