import 'package:flutter/material.dart';
import '../models/foot_measurement.dart';
import '../services/foot_measurement_service.dart';

/// Provider for managing foot measurement state across the app.
///
/// Tracks the user's latest measurement and provides methods
/// for saving, updating, and loading scan results.
class FootMeasurementProvider extends ChangeNotifier {
  final FootMeasurementService _service = FootMeasurementService.instance;

  FootMeasurement? _latestMeasurement;
  List<FootMeasurement> _allMeasurements = [];
  bool _isLoading = false;
  String? _error;

  /// The user's most recent foot measurement (or null if no scan yet).
  FootMeasurement? get latestMeasurement => _latestMeasurement;

  /// All measurements for the current user, newest first.
  List<FootMeasurement> get allMeasurements => _allMeasurements;

  /// Whether a measurement has been saved at least once.
  bool get hasMeasurement => _latestMeasurement != null;

  /// Whether data is currently being loaded.
  bool get isLoading => _isLoading;

  /// Any error message from the last operation.
  String? get error => _error;

  /// The recommended EU size (from latest scan), if available.
  String? get recommendedEuSize => _latestMeasurement?.effectiveEuSize;

  /// Load the user's latest foot measurement from Supabase.
  Future<void> loadLatest(String userId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _latestMeasurement = await _service.getLatestMeasurement(userId);
      _allMeasurements = await _service.getAllMeasurements(userId);
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Save a new foot measurement scan result.
  ///
  /// Returns the saved measurement with its generated ID.
  Future<FootMeasurement?> saveScan(FootMeasurement measurement) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final saved = await _service.saveMeasurement(measurement);
      if (saved != null) {
        _latestMeasurement = saved;
        _allMeasurements.insert(0, saved);
      }
      _isLoading = false;
      notifyListeners();
      return saved;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  /// Update the user's manual size adjustment for a measurement.
  Future<bool> updateAdjustedSize(int measurementId, String adjustedEuSize) async {
    try {
      final success = await _service.updateUserAdjustedSize(measurementId, adjustedEuSize);
      if (success) {
        // Update local state
        final index = _allMeasurements.indexWhere((m) => m.id == measurementId);
        if (index >= 0) {
          _allMeasurements[index] = _allMeasurements[index].copyWith(
            userAdjustedEuSize: adjustedEuSize,
          );
        }
        if (_latestMeasurement?.id == measurementId) {
          _latestMeasurement = _latestMeasurement!.copyWith(
            userAdjustedEuSize: adjustedEuSize,
          );
        }
        notifyListeners();
      }
      return success;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Delete a measurement and refresh the state.
  Future<bool> deleteMeasurement(int measurementId, String userId) async {
    try {
      final success = await _service.deleteMeasurement(measurementId);
      if (success) {
        _allMeasurements.removeWhere((m) => m.id == measurementId);
        if (_latestMeasurement?.id == measurementId) {
          _latestMeasurement = _allMeasurements.isNotEmpty ? _allMeasurements.first : null;
        }
        notifyListeners();
      }
      return success;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Clear any error state.
  void clearError() {
    _error = null;
    notifyListeners();
  }
}
