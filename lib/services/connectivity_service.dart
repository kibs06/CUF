import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import 'supabase_service.dart';

/// Shared connectivity service that verifies actual backend reachability,
/// not just OS-reported network presence.
///
/// Use `ConnectivityService.instance` app-wide. Listen to [isOnline] to
/// react to connectivity changes.
class ConnectivityService {
  static final ConnectivityService instance = ConnectivityService._();
  ConnectivityService._();

  final _connectivity = Connectivity();
  final _controller = StreamController<bool>.broadcast();

  bool _isOnline = true;
  bool get isOnline => _isOnline;

  /// Broadcast stream of connectivity state. Emits `true` when the device
  /// can actually reach the backend, `false` when it cannot.
  Stream<bool> get isOnlineStream => _controller.stream;

  Timer? _periodicCheck;
  StreamSubscription? _connectivitySub;
  bool _isChecking = false;

  /// Start listening to connectivity changes and performing reachability
  /// checks. Call once at app startup (e.g. from the ConnectivityProvider).
  void start() {
    // Listen to OS-reported connectivity changes
    _connectivitySub = _connectivity.onConnectivityChanged.listen((results) {
      _onConnectivityChanged(results);
    });

    // Also do a periodic fallback check every 20s while the app is in the
    // foreground — catches cases where the OS says "connected" but the
    // network is actually unreachable (e.g. captive portal, VPN issues).
    _periodicCheck = Timer.periodic(const Duration(seconds: 20), (_) {
      _checkReachability();
    });

    // Initial check
    _checkReachability();
  }

  /// Stop all listeners. Call on app disposal if needed.
  void stop() {
    _periodicCheck?.cancel();
    _connectivitySub?.cancel();
  }

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    final hasNetwork = results.any((r) => r != ConnectivityResult.none);
    if (!hasNetwork) {
      // Definitely offline — no need to ping
      _updateState(false);
    } else {
      // OS says connected — verify with an actual reachability check
      _checkReachability();
    }
  }

  /// Perform a lightweight reachability check against the actual backend.
  Future<void> _checkReachability() async {
    if (_isChecking) return; // debounce: prevent overlapping checks
    _isChecking = true;
    try {
      // Single lightweight Supabase ping — covers DNS + backend reachability
      await SupabaseService.instance
          .ping()
          .timeout(const Duration(seconds: 8));
      _updateState(true);
    } catch (_) {
      _updateState(false);
    } finally {
      _isChecking = false;
    }
  }

  void _updateState(bool online) {
    if (_isOnline == online) return;
    _isOnline = online;
    if (!_controller.isClosed) {
      _controller.add(online);
    }
    debugPrint('[Connectivity] ${online ? "Online" : "Offline"}');
  }

  /// Dispose of resources.
  void dispose() {
    stop();
    _controller.close();
  }
}
