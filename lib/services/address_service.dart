import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/address_model.dart';

/// CRUD service for customer delivery addresses.
/// Follows the project convention: services throw, providers catch.
class AddressService {
  AddressService._();

  static final AddressService instance = AddressService._();

  SupabaseClient get _client => Supabase.instance.client;

  /// Fetch all addresses for a user, newest first.
  Future<List<Address>> getAddresses(String userId) async {
    final data = await _client
        .from('customer_addresses')
        .select()
        .eq('user_id', userId)
        .order('is_default', ascending: false)
        .order('created_at', ascending: false);

    return (data as List)
        .map((row) => Address.fromMap(Map<String, dynamic>.from(row)))
        .toList();
  }

  /// Insert a new address. Returns the created address (with id).
  Future<Address> addAddress(Address address) async {
    final data = await _client
        .from('customer_addresses')
        .insert(address.toInsertMap())
        .select()
        .single();

    return Address.fromMap(Map<String, dynamic>.from(data));
  }

  /// Update an existing address.
  Future<Address> updateAddress(Address address) async {
    if (address.id == null) {
      throw Exception('Address id is required for update.');
    }

    final data = await _client
        .from('customer_addresses')
        .update(address.toUpdateMap())
        .eq('id', address.id!)
        .select()
        .single();

    return Address.fromMap(Map<String, dynamic>.from(data));
  }

  /// Delete an address by id.
  Future<void> deleteAddress(String id) async {
    await _client.from('customer_addresses').delete().eq('id', id);
  }

  /// Set an address as the default for its user.
  /// The database trigger handles unsetting other defaults,
  /// but we also update the local row here for consistency.
  Future<Address> setDefaultAddress(String id, String userId) async {
    // Unset any existing default first (belt-and-suspenders with trigger)
    await _client
        .from('customer_addresses')
        .update({'is_default': false})
        .eq('user_id', userId)
        .eq('is_default', true);

    // Set the new default
    final data = await _client
        .from('customer_addresses')
        .update({'is_default': true})
        .eq('id', id)
        .select()
        .single();

    return Address.fromMap(Map<String, dynamic>.from(data));
  }
}
