/// Platform-channel wrapper for the **V0 virtual-fitting renderer spike**.
///
/// Not a product feature. It drives the throwaway native spike in
/// `android/app/src/main/kotlin/com/solevision/app/artryon/` so the team can
/// answer the V0 questions in `docs/RoadMap/VIRTUAL_FITTING_ROADMAP.md`:
/// does a glTF shoe render in AR on real hardware, how long does it load, and
/// what frame rate does it hold. Results go in
/// `docs/RoadMap/AR_TRY_ON_SPIKE_FINDINGS.md`.
///
/// The shape deliberately mirrors a subset of the planned production contract
/// (`VIRTUAL_FITTING_ARCHITECTURE.md` §2.8) — `startSession`, `setModel(path)`,
/// `setModelScale`, one-shot events — so this wrapper's callers can move to
/// `ArTryOnChannel` + `TryOnSessionController` without relearning the API.
///
/// Delete this file, its screen and the native package together when the spike
/// is retired.
library;

import 'dart:async';

import 'package:flutter/services.dart';

int _asInt(Object? value, {required int fallback}) =>
    value is num ? value.toInt() : fallback;

double _asDouble(Object? value) => value is num ? value.toDouble() : 0;

const MethodChannel _methodChannel =
    MethodChannel('com.solevision/ar_try_on_spike');

const EventChannel _eventChannel =
    EventChannel('com.solevision/ar_try_on_spike/events');

/// Outcome of asking the native side to start an AR session.
///
/// Same contract (and the same reason codes) as `ArSessionStartResult` in
/// `ar_core_channel.dart`, so failure handling is shared: `unsupported_device`,
/// `needs_install`, `user_opted_out`, `unsupported`, `timeout`, `error`.
class TryOnStartResult {
  final bool started;
  final String? reason;
  final String? message;

  const TryOnStartResult({required this.started, this.reason, this.message});

  factory TryOnStartResult.fromNative(Object? native) {
    if (native is Map) {
      // `is bool`, not `as bool?`: a native build that sends `"true"` instead of `true`
      // must fail closed rather than throw across the channel boundary.
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

/// One-shot events the native spike emits.
sealed class TryOnSpikeEvent {
  const TryOnSpikeEvent();

  factory TryOnSpikeEvent.fromMap(Map<dynamic, dynamic> map) {
    final type = map['type']?.toString() ?? 'unknown';
    final rawData = map['data'];
    final data = rawData is Map
        ? Map<String, dynamic>.from(rawData)
        : <String, dynamic>{};
    // Every value is read defensively (`is num`, `?.toString()`): this is a debugging screen
    // whose whole job is to report what the renderer did, so a malformed or future payload
    // has to degrade into a weird-looking number, never into a crash.
    return switch (type) {
      'status' => TryOnStatusEvent(
          phase: data['phase']?.toString() ?? 'unknown',
          reason: data['reason']?.toString(),
          message: data['message']?.toString(),
        ),
      'modelLoaded' => TryOnModelLoadedEvent(
          loadMs: _asInt(data['loadMs'], fallback: -1),
          source: data['source']?.toString() ?? '',
        ),
      'perf' => TryOnPerfEvent(
          avgFps: _asDouble(data['avgFps']),
          frameMs: _asDouble(data['frameMs']),
        ),
      _ => TryOnUnknownEvent(type: type, data: data),
    };
  }
}

/// Session state changed: `starting` | `ready` | `searching` | `placed` |
/// `failed`.
class TryOnStatusEvent extends TryOnSpikeEvent {
  final String phase;
  final String? reason;
  final String? message;

  const TryOnStatusEvent({required this.phase, this.reason, this.message});
}

/// The model finished parsing and is in the scene. [loadMs] runs from the
/// `setModel` call to the instance becoming available — the number V0 is
/// measuring (budget: ≤ 1.5 s warm / ≤ 4 s cold).
class TryOnModelLoadedEvent extends TryOnSpikeEvent {
  final int loadMs;
  final String source;

  const TryOnModelLoadedEvent({required this.loadMs, required this.source});
}

/// Rolling fps sample from the native side (one every ~5 s).
class TryOnPerfEvent extends TryOnSpikeEvent {
  final double avgFps;
  final double frameMs;

  const TryOnPerfEvent({required this.avgFps, required this.frameMs});
}

/// Forward-compatibility catch-all: a future event type must never crash the
/// screen that is supposed to be measuring it.
class TryOnUnknownEvent extends TryOnSpikeEvent {
  final String type;
  final Map<String, dynamic> data;

  const TryOnUnknownEvent({required this.type, required this.data});
}

/// Singleton wrapper over the spike's method + event channels.
class ArTryOnSpikeChannel {
  ArTryOnSpikeChannel._();

  static final ArTryOnSpikeChannel instance = ArTryOnSpikeChannel._();

  final StreamController<TryOnSpikeEvent> _eventController =
      StreamController<TryOnSpikeEvent>.broadcast();
  StreamSubscription<dynamic>? _subscription;

  /// Events from the native spike. The first listener attaches the platform
  /// stream; the last one detaches it.
  Stream<TryOnSpikeEvent> get events => _eventController.stream;

  /// Starts listening. Call once when the spike screen mounts; this also warms
  /// the event channel so no event is lost between `startSession` and the first
  /// listener.
  void attach() {
    _subscription ??= _eventChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        if (event is Map) {
          _eventController.add(TryOnSpikeEvent.fromMap(event));
        }
      },
      onError: (Object error) {
        _eventController.add(
          TryOnStatusEvent(
            phase: 'failed',
            reason: 'error',
            message: error.toString(),
          ),
        );
      },
    );
  }

  /// Detaches the platform stream. Call when the spike screen unmounts.
  Future<void> detach() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  /// Asks the native spike to start ARCore. Resolves when the session is
  /// actually resumed, failed, or the native 15 s safety net fires.
  Future<TryOnStartResult> startSession() async {
    attach();
    final native = await _methodChannel.invokeMethod<Object?>('startSession');
    return TryOnStartResult.fromNative(native);
  }

  Future<void> stopSession() => _methodChannel.invokeMethod<void>('stopSession');

  /// Hands the native side a model location. Accepts what SceneView accepts:
  /// a `file://` URI (how a downloaded model arrives), a plain asset path, or
  /// an https URL. The spike sends `file://`.
  Future<void> setModel(String path) =>
      _methodChannel.invokeMethod<void>('setModel', {'path': path});

  /// Uniform model scale — the seam the size chart will drive in production
  /// (`VIRTUAL_FITTING_ARCHITECTURE.md` §2.5.2). 1.0 means "as authored".
  Future<void> setModelScale(double scale) =>
      _methodChannel.invokeMethod<void>('setModelScale', {'scale': scale});

  /// Native status snapshot, useful when an event was missed.
  Future<Map<String, dynamic>> getStatus() async {
    final native = await _methodChannel.invokeMethod<Object?>('getStatus');
    return Map<String, dynamic>.from(native as Map? ?? {});
  }
}
