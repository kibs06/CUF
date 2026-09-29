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
/// **The contract is a subset of §2.8 on purpose.** `setFootPose` and
/// `setFootMask` (V4's detection loop) and the `footLock` event are omitted
/// because nothing can call them yet: a wrapper for a conversation neither side
/// can have is not a contract, it is a guess. They arrive with V4, which also
/// needs `FootPoseFrame`. What is here is what V3 works with — start/stop, the
/// model handover, size and colour, placement, the screenshot, and the QA mode
/// switch.
library;

import 'dart:async';

// `Uint8List` comes from services.dart's export of dart:typed_data.
import 'package:flutter/services.dart';

import '../utils/shoe_model_resolver.dart';

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

/// Async screenshot completion. `captureScreenshot` normally returns the bytes
/// directly; this is the channel's other way of delivering them.
class TryOnScreenshotEvent extends ArTryOnEvent {
  final Uint8List bytes;

  const TryOnScreenshotEvent({required this.bytes});
}

/// Forward-compatibility catch-all: a future event type (V4's `footLock`, for
/// instance) reaches the controller as an unknown rather than as a crash.
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
}
