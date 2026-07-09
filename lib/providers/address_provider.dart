import 'package:flutter/foundation.dart';

import '../models/address_model.dart';
import '../services/address_service.dart';

/// Manages the customer address book state.
/// Follows the project convention: services throw, providers catch.
class AddressProvider extends ChangeNotifier {
  final AddressService _service = AddressService.instance;

  List<Address> _addresses = [];
  bool _isLoading = false;
  String? _errorMessage;

  /// Address selected for the current checkout flow.
  Address? _selectedAddress;

  List<Address> get addresses => _addresses;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  Address? get selectedAddress => _selectedAddress;

  /// The default address (or first if none marked default).
  Address? get defaultAddress {
    if (_addresses.isEmpty) return null;
    return _addresses.firstWhere(
      (a) => a.isDefault,
      orElse: () => _addresses.first,
    );
  }

  void setSelectedAddress(Address? address) {
    _selectedAddress = address;
    notifyListeners();
  }

  /// Load all addresses for the current user.
  Future<void> loadAddresses(String userId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _addresses = await _service.getAddresses(userId);
    } catch (e) {
      debugPrint('AddressProvider.loadAddresses error: $e');
      _errorMessage = 'Unable to load addresses. Please try again.';
      _addresses = [];
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Add a new address. Throws on validation errors.
  Future<Address> addAddress(Address address) async {
    final created = await _service.addAddress(address);
    _addresses.insert(0, created);
    notifyListeners();
    return created;
  }

  /// Update an existing address.
  Future<Address> updateAddress(Address address) async {
    final updated = await _service.updateAddress(address);
    final idx = _addresses.indexWhere((a) => a.id == updated.id);
    if (idx >= 0) _addresses[idx] = updated;
    // If this was the selected address, update it too
    if (_selectedAddress?.id == updated.id) _selectedAddress = updated;
    notifyListeners();
    return updated;
  }

  /// Delete an address.
  Future<void> deleteAddress(String id) async {
    await _service.deleteAddress(id);
    _addresses.removeWhere((a) => a.id == id);
    if (_selectedAddress?.id == id) _selectedAddress = null;
    notifyListeners();
  }

  /// Set an address as default.
  Future<void> setDefaultAddress(String id, String userId) async {
    await _service.setDefaultAddress(id, userId);
    // loadAddresses already calls notifyListeners internally
    await loadAddresses(userId);
  }
}
