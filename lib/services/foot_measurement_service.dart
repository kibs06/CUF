import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/foot_measurement.dart';

/// Service for managing foot measurement data in Supabase.
///
/// Handles CRUD operations for the `foot_measurements` table,
/// including fetching the user's latest scan and saving new results.
class FootMeasurementService {
  FootMeasurementService._();
  static final FootMeasurementService instance = FootMeasurementService._();

  final SupabaseClient _client = Supabase.instance.client;

  /// Fetch the user's most recent foot measurement.
  ///
  /// Returns `null` if no scan exists yet.
  Future<FootMeasurement?> getLatestMeasurement(String userId) async {
    try {
      final data = await _client
          .from('foot_measurements')
          .select()
          .eq('user_id', userId)
          .order('scan_date', ascending: false)
          .limit(1)
          .maybeSingle();

      if (data == null) return null;
      return FootMeasurement.fromMap(data);
    } catch (e) {
      debugPrint('[FootMeasurementService] getLatestMeasurement error: $e');
      return null;
    }
  }

  /// Fetch all foot measurements for a user, newest first.
  Future<List<FootMeasurement>> getAllMeasurements(String userId) async {
    try {
      final data = await _client
          .from('foot_measurements')
          .select()
          .eq('user_id', userId)
          .order('scan_date', ascending: false);

      return (data as List).map((row) => FootMeasurement.fromMap(row)).toList();
    } catch (e) {
      debugPrint('[FootMeasurementService] getAllMeasurements error: $e');
      return [];
    }
  }

  /// Save a new foot measurement to the database.
  ///
  /// Returns the saved measurement with its generated ID, or `null` on failure.
  Future<FootMeasurement?> saveMeasurement(FootMeasurement measurement) async {
    try {
      final insertData = measurement.toInsertMap();
      final data = await _client
          .from('foot_measurements')
          .insert(insertData)
          .select()
          .single();

      return FootMeasurement.fromMap(data);
    } catch (e) {
      debugPrint('[FootMeasurementService] saveMeasurement error: $e');
      return null;
    }
  }

  /// Update the user's adjusted size for an existing measurement.
  Future<bool> updateUserAdjustedSize(int measurementId, String adjustedEuSize) async {
    try {
      await _client
          .from('foot_measurements')
          .update({'user_adjusted_eu_size': adjustedEuSize})
          .eq('id', measurementId);
      return true;
    } catch (e) {
      debugPrint('[FootMeasurementService] updateUserAdjustedSize error: $e');
      return false;
    }
  }

  /// Delete a foot measurement.
  Future<bool> deleteMeasurement(int measurementId) async {
    try {
      await _client
          .from('foot_measurements')
          .delete()
          .eq('id', measurementId);
      return true;
    } catch (e) {
      debugPrint('[FootMeasurementService] deleteMeasurement error: $e');
      return false;
    }
  }
}
