/// Platform channel wrapper for the native ARCore foot scanning plugin.
///
/// Provides a Dart-friendly API over the MethodChannel/EventChannel bridge
/// to the Kotlin ARCore implementation. Handles:
/// - Session lifecycle (start/stop)
/// - Tracking state monitoring
/// - Floor plane detection
/// - hitTest raycasting (2D screen → 3D world coordinates)
/// - Camera frame acquisition for ML processing
///
/// Architecture:
/// ┌──────────────────┐     MethodChannel      ┌─────────────────────┐
/// │  Flutter (Dart)  │ ◄────────────────────► │  Kotlin (Android)   │
/// │                  │                         │                     │
/// │  ar_core_channel │     EventChannel        │  ArFootSizingPlugin │
/// │  (this class)    │ ◄────────────────────── │  (native bridge)    │
/// └──────────────────┘                         └─────────────────────┘
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
// Uint8List is provided by flutter/foundation.dart.
import 'package:flutter/services.dart';

// ═══════════════════════════════════════════════════════════════════
// CHANNEL NAMES
// ═══════════════════════════════════════════════════════════════════

const MethodChannel _methodChannel =
    MethodChannel('com.solevision/ar_foot_sizing');

const EventChannel _eventChannel =
    EventChannel('com.solevision/ar_foot_sizing/events');

// ═══════════════════════════════════════════════════════════════════
// DATA CLASSES
// ═══════════════════════════════════════════════════════════════════

/// ARCore tracking state values.
enum ArTrackingState {
  /// ARCore cannot provide reliable tracking.
  /// The session may need to be restarted.
  paused,

  /// ARCore is tracking but with limited accuracy.
  /// Common in low-texture environments or poor lighting.
  limited,

  /// ARCore is tracking with full accuracy.
  /// Measurements taken in this state are reliable.
  tracking,
}

/// Represents a 3D point in real-world space (meters).
class ArWorldPoint {
  final double x;
  final double y;
  final double z;
  final double distanceFromCamera; // Euclidean distance in meters

  const ArWorldPoint({
    required this.x,
    required this.y,
    required this.z,
    required this.distanceFromCamera,
  });

  factory ArWorldPoint.fromMap(Map<String, dynamic> map) {
    final x = (map['x'] as num?)?.toDouble() ?? 0;
    final y = (map['y'] as num?)?.toDouble() ?? 0;
    final z = (map['z'] as num?)?.toDouble() ?? 0;
    final dist = (map['distance'] as num?)?.toDouble() ?? 0;
    return ArWorldPoint(x: x, y: y, z: z, distanceFromCamera: dist);
  }

  /// Compute Euclidean distance to another point.
  double distanceTo(ArWorldPoint other) {
    final dx = x - other.x;
    final dy = y - other.y;
    final dz = z - other.z;
    return _sqrt(dx * dx + dy * dy + dz * dz);
  }

  static double _sqrt(double v) {
    // Newton's method approximation (avoids dart:math import in model)
    if (v <= 0) return 0;
    double guess = v / 2;
    for (int i = 0; i < 10; i++) {
      guess = (guess + v / guess) / 2;
    }
    return guess;
  }
}

/// A single camera frame captured from the ARCore CPU image stream.
///
/// The native side converts ARCore's YUV_420_888 image to NV21 (the format
/// ML Kit accepts on Android) and caches the most recent frame, throttled
/// to the sampling rate. [rotationDegrees] is the display rotation that
/// ML Kit needs to orient the image correctly.
class ArCameraFrame {
  /// NV21-encoded image bytes (Y plane + interleaved VU).
  final Uint8List nv21Bytes;

  /// Width of the image in pixels (sensor orientation, usually landscape).
  final int width;

  /// Height of the image in pixels.
  final int height;

  /// Rotation (in degrees) to apply to make the image upright on screen.
  final int rotationDegrees;

  const ArCameraFrame({
    required this.nv21Bytes,
    required this.width,
    required this.height,
    required this.rotationDegrees,
  });

  /// Create an [ArCameraFrame] from the method channel result map.
  factory ArCameraFrame.fromMap(Map<dynamic, dynamic> map) {
    return ArCameraFrame(
      nv21Bytes: (map['bytes'] as Uint8List?) ?? Uint8List(0),
      width: (map['width'] as num?)?.toInt() ?? 0,
      height: (map['height'] as num?)?.toInt() ?? 0,
      rotationDegrees: (map['rotationDegrees'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Detected horizontal plane (floor).
class ArPlane {
  final double centerX;
  final double centerY;
  final double centerZ;
  final double extentX; // Width of detected region in meters
  final double extentZ; // Depth of detected region in meters
  final double normalX;
  final double normalY;
  final double normalZ;

  const ArPlane({
    required this.centerX,
    required this.centerY,
    required this.centerZ,
    required this.extentX,
    required this.extentZ,
    required this.normalX,
    required this.normalY,
    required this.normalZ,
  });

  factory ArPlane.fromMap(Map<String, dynamic> map) {
    return ArPlane(
      centerX: (map['centerX'] as num?)?.toDouble() ?? 0,
      centerY: (map['centerY'] as num?)?.toDouble() ?? 0,
      centerZ: (map['centerZ'] as num?)?.toDouble() ?? 0,
      extentX: (map['extentX'] as num?)?.toDouble() ?? 0,
      extentZ: (map['extentZ'] as num?)?.toDouble() ?? 0,
      normalX: (map['normalX'] as num?)?.toDouble() ?? 0,
      normalY: (map['normalY'] as num?)?.toDouble() ?? 0,
      normalZ: (map['normalZ'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// Event emitted from the native ARCore session.
class ArSessionEvent {
  final String type; // 'tracking', 'plane', 'frame', 'error'
  final Map<String, dynamic> data;

  const ArSessionEvent({required this.type, required this.data});

  factory ArSessionEvent.fromMap(Map<dynamic, dynamic> map) {
    return ArSessionEvent(
      type: map['type']?.toString() ?? 'unknown',
      data: Map<String, dynamic>.from(map['data'] ?? {}),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// PLATFORM CHANNEL WRAPPER
// ═══════════════════════════════════════════════════════════════════

/// Singleton wrapper for the ARCore foot scanning platform channel.
///
/// Usage:
/// ```dart
/// final arCore = ArCoreChannel.instance;
/// final result = await arCore.startSession();
/// if (result) {
///   // Listen for events
///   arCore.events.listen((event) { ... });
///   // Hit test a point
///   final point = await arCore.hitTest(x: 0.5, y: 0.5);
/// }
/// await arCore.stopSession();
/// ```
class ArCoreChannel {
  ArCoreChannel._();
  static final ArCoreChannel instance = ArCoreChannel._();

  bool _sessionActive = false;
  StreamSubscription<ArSessionEvent>? _eventSubscription;
  final StreamController<ArSessionEvent> _eventController =
      StreamController<ArSessionEvent>.broadcast();

  /// Whether an ARCore session is currently active.
  bool get isSessionActive => _sessionActive;

  /// Stream of session events (tracking changes, plane detection, errors).
  Stream<ArSessionEvent> get events => _eventController.stream;

  // ── Session Lifecycle ──

  /// Start a new ARCore session.
  ///
  /// The native side will:
  /// 1. Create an ARCore Session
  /// 2. Configure for plane detection (horizontal)
  /// 3. Start the camera feed
  /// 4. Begin tracking
  ///
  /// Returns `true` if the session started successfully.
  /// Returns `false` if ARCore is not supported or permission denied.
  Future<bool> startSession() async {
    if (_sessionActive) return true;

    try {
      final result = await _methodChannel.invokeMethod<bool>('startSession');
      _sessionActive = result ?? false;

      if (_sessionActive) {
        _startListening();
      }

      return _sessionActive;
    } on PlatformException catch (e) {
      debugPrint('[ArCoreChannel] startSession error: ${e.message}');
      return false;
    }
  }

  /// Stop the current ARCore session and release resources.
  Future<void> stopSession() async {
    if (!_sessionActive) return;

    _stopListening();

    try {
      await _methodChannel.invokeMethod('stopSession');
    } on PlatformException catch (e) {
      debugPrint('[ArCoreChannel] stopSession error: ${e.message}');
    } finally {
      _sessionActive = false;
    }
  }

  // ── Hit Testing ──

  /// Cast a ray from a 2D screen point onto detected AR planes.
  ///
  /// [x], [y] are normalized coordinates (0.0–1.0) where (0,0) is
  /// top-left and (1,1) is bottom-right of the camera view.
  ///
  /// Returns the closest hit point in world coordinates, or `null`
  /// if the ray doesn't intersect any detected plane.
  Future<ArWorldPoint?> hitTest({required double x, required double y}) async {
    if (!_sessionActive) return null;

    try {
      final result = await _methodChannel.invokeMethod<Map<dynamic, dynamic>>(
        'hitTest',
        {'x': x, 'y': y},
      );
      if (result == null) return null;
      return ArWorldPoint.fromMap(Map<String, dynamic>.from(result));
    } on PlatformException catch (e) {
      debugPrint('[ArCoreChannel] hitTest error: ${e.message}');
      return null;
    }
  }

  /// Perform hit test for multiple points (batch).
  ///
  /// More efficient than calling [hitTest] in a loop because it
  /// avoids repeated platform channel round-trips.
  Future<List<ArWorldPoint?>> hitTestBatch({
    required List<Offset> screenPoints,
  }) async {
    if (!_sessionActive) return List.filled(screenPoints.length, null);

    try {
      final pointsData = screenPoints
          .map((p) => {'x': p.dx, 'y': p.dy})
          .toList();

      final result = await _methodChannel.invokeMethod<List<dynamic>>(
        'hitTestBatch',
        {'points': pointsData},
      );

      if (result == null) return List.filled(screenPoints.length, null);

      return result.map((r) {
        if (r == null) return null;
        return ArWorldPoint.fromMap(Map<String, dynamic>.from(r));
      }).toList();
    } on PlatformException catch (e) {
      debugPrint('[ArCoreChannel] hitTestBatch error: ${e.message}');
      return List.filled(screenPoints.length, null);
    }
  }

  // ── Camera Frame ──

  /// Request the most recently cached camera frame (NV21 bytes + metadata).
  ///
  /// The native side captures ARCore's CPU image stream at a throttled rate
  /// (matching the scan sampling interval), converts it to NV21, and caches
  /// it. This is used for ML foot detection/segmentation on the sampled frame.
  ///
  /// Returns `null` if the session is inactive, no frame is available yet
  /// (first few frames after session start), or on platform error.
  Future<ArCameraFrame?> acquireCameraFrame() async {
    if (!_sessionActive) return null;

    try {
      final result = await _methodChannel.invokeMethod<Map<dynamic, dynamic>>(
        'acquireCameraFrame',
      );
      if (result == null) return null;
      return ArCameraFrame.fromMap(result);
    } on PlatformException catch (e) {
      debugPrint('[ArCoreChannel] acquireCameraFrame error: ${e.message}');
      return null;
    }
  }

  // ── Query State ──

  /// Get the current tracking state.
  Future<ArTrackingState> getTrackingState() async {
    if (!_sessionActive) return ArTrackingState.paused;

    try {
      final result = await _methodChannel.invokeMethod<String>('getTrackingState');
      switch (result) {
        case 'tracking':
          return ArTrackingState.tracking;
        case 'limited':
          return ArTrackingState.limited;
        default:
          return ArTrackingState.paused;
      }
    } on PlatformException {
      return ArTrackingState.paused;
    }
  }

  /// Get the best detected floor plane, or `null` if none found.
  Future<ArPlane?> getFloorPlane() async {
    if (!_sessionActive) return null;

    try {
      final result = await _methodChannel.invokeMethod<Map<dynamic, dynamic>>(
        'getFloorPlane',
      );
      if (result == null) return null;
      return ArPlane.fromMap(Map<String, dynamic>.from(result));
    } on PlatformException {
      return null;
    }
  }

  /// Get the distance from the camera to the floor plane in meters.
  Future<double?> getFloorDistance() async {
    if (!_sessionActive) return null;

    try {
      final result = await _methodChannel.invokeMethod<double>('getFloorDistance');
      return result;
    } on PlatformException {
      return null;
    }
  }

  // ── Internal ──

  void _startListening() {
    _eventSubscription?.cancel();
    _eventSubscription = _eventChannel
        .receiveBroadcastStream()
        .where((event) => event is Map)
        .map((event) => ArSessionEvent.fromMap(event as Map<dynamic, dynamic>))
        .listen(
      (event) {
        if (!_eventController.isClosed) {
          _eventController.add(event);
        }
      },
      onError: (error) {
        debugPrint('[ArCoreChannel] Event stream error: $error');
      },
    );
  }

  void _stopListening() {
    _eventSubscription?.cancel();
    _eventSubscription = null;
  }

  /// Dispose all resources.
  void dispose() {
    stopSession();
    _eventController.close();
  }
}
