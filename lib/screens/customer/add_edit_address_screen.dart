import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';


import '../../constants/app_constants.dart';
import '../../models/address_model.dart';
import '../../providers/address_provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/sole_card.dart';
import '../../widgets/sole_primary_button.dart';
import '../../widgets/sole_text_field.dart';

/// Add or Edit Address screen.
///
/// Step A: Full-screen map pin-drop (Shopee-style center pin).
/// Step B: Address details form (shown after confirming location,
///         or directly when editing an existing address).
class AddEditAddressScreen extends StatefulWidget {
  /// If provided, the screen operates in edit mode.
  final Address? existingAddress;

  const AddEditAddressScreen({super.key, this.existingAddress});

  @override
  State<AddEditAddressScreen> createState() => _AddEditAddressScreenState();
}

class _AddEditAddressScreenState extends State<AddEditAddressScreen> {
  bool get _isEditing => widget.existingAddress != null;

  // ── Map state ─────────────────────────────────────────────────
  final MapController _mapController = MapController();
  LatLng _currentCenter = const LatLng(10.3157, 123.8854); // Cebu default
  bool _showMap = true; // true = Step A (map), false = Step B (form)
  bool _isReverseGeocoding = false;
  bool _isLocating = true; // true while GPS fix is being obtained on open
  String? _locationMessage; // friendly status/error message shown on map
  final _maptilerKey = AppConstants.maptilerKey;

  // ── Address search state ──────────────────────────────────────
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchPredictions = [];
  bool _isSearchLoading = false;
  String? _searchError;
  Timer? _searchDebounce;
  bool _showPredictions = false;

  // ── Form state ────────────────────────────────────────────────
  final _formKey = GlobalKey<FormState>();
  final _recipientNameController = TextEditingController();
  final _recipientPhoneController = TextEditingController();
  final _regionController = TextEditingController();
  final _provinceController = TextEditingController();
  final _cityController = TextEditingController();
  final _barangayController = TextEditingController();
  final _streetController = TextEditingController();
  final _landmarkController = TextEditingController();
  String _label = 'Home';
  bool _isDefault = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      final addr = widget.existingAddress!;
      _currentCenter = LatLng(addr.latitude, addr.longitude);
      _showMap = false; // Skip map, go straight to form
      _fillForm(addr);
      _isLocating = false;
    } else {
      _autoLocateOnOpen();
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _recipientNameController.dispose();
    _recipientPhoneController.dispose();
    _regionController.dispose();
    _provinceController.dispose();
    _cityController.dispose();
    _barangayController.dispose();
    _streetController.dispose();
    _landmarkController.dispose();
    super.dispose();
  }

  void _fillForm(Address addr) {
    _recipientNameController.text = addr.recipientName;
    _recipientPhoneController.text = addr.recipientPhone;
    _regionController.text = addr.region;
    _provinceController.text = addr.province;
    _cityController.text = addr.cityMunicipality;
    _barangayController.text = addr.barangay;
    _streetController.text = addr.streetAddress;
    _landmarkController.text = addr.landmark ?? '';
    _label = addr.label;
    _isDefault = addr.isDefault;
  }

  // ════════════════════════════════════════════════════════════════
  // ADDRESS SEARCH (MapTiler Geocoding)
  // ════════════════════════════════════════════════════════════════

  void _searchAddress(String query) {
    _searchDebounce?.cancel();
    if (query.trim().length < 2) {
      if (mounted) {
        setState(() {
          _searchPredictions = [];
          _showPredictions = false;
          _searchError = null;
        });
      }
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      _fetchPredictions(query.trim());
    });
  }

  Future<void> _fetchPredictions(String query) async {
    if (!mounted) return;

    // Guard: check API key is configured (not empty or placeholder)
    if (_maptilerKey.isEmpty || _maptilerKey.contains('YOUR_')) {
      if (mounted) {
        setState(() {
          _searchError = 'Search is not configured — add a valid MapTiler API key';
          _isSearchLoading = false;
        });
      }
      return;
    }

    setState(() {
      _isSearchLoading = true;
      _searchError = null;
    });

    try {
      final encodedQuery = Uri.encodeComponent(query);
      final url = Uri.parse(
        'https://api.maptiler.com/geocoding/$encodedQuery.json'
        '?key=$_maptilerKey'
        '&bbox=116.927,4.587,126.603,21.119'
        '&limit=5',
      );

      debugPrint('[SEARCH] Geocoding request for: "$query"');

      final client = HttpClient();
      try {
        final request = await client.getUrl(url);
        request.headers.set('User-Agent', 'com.solevision.app');
        final response = await request.close().timeout(
          const Duration(seconds: 8),
        );
        final body = await response.transform(utf8.decoder).join();

        if (!mounted) return;

        debugPrint('[SEARCH] Response status: ${response.statusCode}');

        if (response.statusCode != 200) {
          debugPrint('[SEARCH] Error body: $body');
          setState(() {
            _searchError = response.statusCode == 401 || response.statusCode == 403
                ? 'Invalid API key — check your MapTiler configuration'
                : 'Search unavailable right now (HTTP ${response.statusCode})';
            _isSearchLoading = false;
          });
          return;
        }

        final data = json.decode(body) as Map<String, dynamic>;
        final features = data['features'] as List<dynamic>? ?? [];

        debugPrint('[SEARCH] Found ${features.length} results for "$query"');

        setState(() {
          _searchPredictions = features.take(5).map((f) {
            final coords = f['center'] as List<dynamic>? ?? [0, 0];
            return {
              'place_name': f['place_name'] ?? '',
              'lng': coords[0],
              'lat': coords[1],
            };
          }).toList();
          _showPredictions = _searchPredictions.isNotEmpty;
          _isSearchLoading = false;
        });
      } finally {
        client.close();
      }
    } catch (e) {
      debugPrint('[SEARCH] Geocoding error: $e');
      if (mounted) {
        setState(() {
          _searchError = 'Search unavailable right now';
          _isSearchLoading = false;
        });
      }
    }
  }

  void _onPredictionSelected(Map<String, dynamic> prediction) {
    // Dismiss keyboard and dropdown
    FocusScope.of(context).unfocus();
    if (mounted) {
      setState(() {
        _showPredictions = false;
        _searchController.text = prediction['place_name'] as String? ?? '';
      });
    }

    // Animate map to selected location
    final lat = (prediction['lat'] as num).toDouble();
    final lng = (prediction['lng'] as num).toDouble();
    final target = LatLng(lat, lng);
    _mapController.move(target, 17);
    if (mounted) {
      setState(() {
        _currentCenter = target;
        _locationMessage = null;
      });
    }

    // Reverse geocode to fill form fields
    _reverseGeocode();
  }

  // ════════════════════════════════════════════════════════════════
  // AUTO-LOCATE ON OPEN
  // ════════════════════════════════════════════════════════════════

  Future<void> _autoLocateOnOpen() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _locationMessage = 'Location services are off — drag the pin to your address';
        if (mounted) setState(() => _isLocating = false);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        _locationMessage = 'Location access denied — drag the pin to set your delivery address';
        if (mounted) setState(() => _isLocating = false);
        return;
      }

      if (permission == LocationPermission.deniedForever) {
        _locationMessage = 'Location permission off in Settings — drag the pin manually';
        if (mounted) setState(() => _isLocating = false);
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      _currentCenter = LatLng(position.latitude, position.longitude);
      if (mounted) {
        setState(() {
          _isLocating = false;
          _locationMessage = null;
        });
        // Delay map move until after the first frame renders so the controller is attached
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _mapController.move(_currentCenter, _mapController.camera.zoom);
          }
        });
      }

      // Pre-fill form fields via reverse geocoding
      await _reverseGeocode();
    } catch (e) {
      debugPrint('Auto-locate error: $e');
      _locationMessage = 'Could not get location — drag the pin to your address';
      if (mounted) setState(() => _isLocating = false);
    }
  }

  // ════════════════════════════════════════════════════════════════
  // LOCATION PERMISSIONS (manual recenter button)
  // ════════════════════════════════════════════════════════════════

  Future<void> _useCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location services are disabled.'),
              backgroundColor: AppConstants.error,
            ),
          );
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Location permission denied.'),
                backgroundColor: AppConstants.error,
              ),
            );
          }
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Location permission permanently denied. Please enable in Settings.',
              ),
              backgroundColor: AppConstants.error,
              action: SnackBarAction(
                label: 'Settings',
                textColor: Colors.white,
                onPressed: () => Geolocator.openAppSettings(),
              ),
            ),
          );
        }
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      _currentCenter = LatLng(position.latitude, position.longitude);
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _mapController.move(_currentCenter, _mapController.camera.zoom);
          }
        });
        if (_locationMessage != null) {
          setState(() => _locationMessage = null);
        }
      }
    } catch (e) {
      debugPrint('Error getting current location: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not get location: $e'),
            backgroundColor: AppConstants.error,
          ),
        );
      }
    }
  }

  // ════════════════════════════════════════════════════════════════
  // REVERSE GEOCODING
  // ════════════════════════════════════════════════════════════════

  Future<void> _reverseGeocode() async {
    if (!mounted) return;
    setState(() => _isReverseGeocoding = true);

    try {
      final geocoding = Geocoding();
      final placemarks = await geocoding.placemarkFromCoordinates(
        _currentCenter.latitude,
        _currentCenter.longitude,
      );

      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        _regionController.text = place.administrativeArea ?? '';
        _provinceController.text = place.subAdministrativeArea ?? '';
        _cityController.text = place.locality ?? place.subLocality ?? '';
        _barangayController.text = place.thoroughfare ?? '';
        // Pre-fill street with name + subThoroughfare if available
        final streetParts = <String>[
          if (place.subThoroughfare != null) place.subThoroughfare!,
          if (place.thoroughfare != null) place.thoroughfare!,
        ];
        if (streetParts.isNotEmpty) {
          _streetController.text = streetParts.join(' ');
        }
      }
    } catch (e) {
      debugPrint('Reverse geocoding error: $e');
      // Not critical — fields remain editable
    }

    if (mounted) {
      setState(() => _isReverseGeocoding = false);
    }
  }

  // ════════════════════════════════════════════════════════════════
  // SAVE
  // ════════════════════════════════════════════════════════════════

  Future<void> _saveAddress() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final auth = context.read<AuthProvider>();
      final userId = auth.profile?['id'] ?? auth.currentUser?['id'] ?? '';
      final provider = context.read<AddressProvider>();

      final address = Address(
        id: widget.existingAddress?.id,
        userId: userId,
        label: _label,
        recipientName: _recipientNameController.text.trim(),
        recipientPhone: _recipientPhoneController.text.trim(),
        region: _regionController.text.trim(),
        province: _provinceController.text.trim(),
        cityMunicipality: _cityController.text.trim(),
        barangay: _barangayController.text.trim(),
        streetAddress: _streetController.text.trim(),
        landmark: _landmarkController.text.trim().isEmpty
            ? null
            : _landmarkController.text.trim(),
        latitude: _currentCenter.latitude,
        longitude: _currentCenter.longitude,
        isDefault: _isDefault,
      );

      Address result;
      if (_isEditing) {
        result = await provider.updateAddress(address);
      } else {
        result = await provider.addAddress(address);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isEditing ? 'Address updated.' : 'Address saved.',
            ),
            backgroundColor: AppConstants.success,
          ),
        );
        Navigator.of(context).pop(result);
      }
    } catch (e) {
      debugPrint('Save address error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: $e'),
            backgroundColor: AppConstants.error,
          ),
        );
      }
    }

    if (mounted) setState(() => _isSaving = false);
  }

  // ════════════════════════════════════════════════════════════════
  // BUILD
  // ════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _showMap ? Colors.grey[300]! : AppConstants.surfaceLight,
      body: _showMap ? _buildMapStep() : _buildFormStep(),
    );
  }

  // ── Step A: Map Pin-Drop ──────────────────────────────────────

  Widget _buildMapStep() {
    return Stack(
      children: [
        // MapTiler tiles via flutter_map
        FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _currentCenter,
                initialZoom: 16,
                onPositionChanged: (position, hasGesture) {
                  if (hasGesture && mounted) {
                    setState(() => _currentCenter = position.center);
                  }
                },
              ),
          children: [
            TileLayer(
              urlTemplate: 'https://api.maptiler.com/maps/streets-v2/{z}/{x}/{y}.png?key=${AppConstants.maptilerKey}',
              userAgentPackageName: 'com.solevision.app',
            ),
            // MapTiler attribution (required by usage policy)
            const RichAttributionWidget(
              attributions: [
                TextSourceAttribution('© MapTiler © OpenStreetMap contributors'),
              ],
              showFlutterMapAttribution: false,
            ),
          ],
        ),

        // Center pin icon (fixed — map moves underneath)
        const Center(
          child: Padding(
            padding: EdgeInsets.only(bottom: 32),
            child: Icon(
              Icons.location_on,
              size: 48,
              color: AppConstants.primary,
            ),
          ),
        ),

        // Back button (top-left)
        Positioned(
          top: MediaQuery.of(context).padding.top + 12,
          left: 16,
          child: _circleButton(
            icon: Icons.arrow_back,
            onTap: () => Navigator.of(context).pop(),
          ),
        ),

        // ── Search bar overlay ────────────────────────────────
        Positioned(
          top: MediaQuery.of(context).padding.top + 12,
          left: 68,
          right: 16,
          child: _buildSearchBar(),
        ),

        // ── Prediction dropdown ───────────────────────────────
        if (_showPredictions || _searchError != null)
          Positioned(
            top: MediaQuery.of(context).padding.top + 64,
            left: 68,
            right: 16,
            child: _buildPredictionDropdown(),
          ),

        // Use My Current Location (bottom-right)
        Positioned(
          bottom: 120,
          right: 16,
          child: _circleButton(
            icon: Icons.my_location,
            onTap: _useCurrentLocation,
          ),
        ),

        // Loading overlay while GPS fix is being obtained
        if (_isLocating)
          const Positioned(
            top: 80,
            left: 0,
            right: 0,
            child: Center(
              child: Card(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 10),
                      Text('Finding your location...'),
                    ],
                  ),
                ),
              ),
            ),
          ),

        // Friendly status message (permission denied, fallback, etc.)
        if (!_isLocating && _locationMessage != null)
          Positioned(
            top: MediaQuery.of(context).padding.top + 12 + 56 + (_showPredictions ? 180 : 0),
            left: 16,
            right: 16,
            child: Card(
              color: Colors.white.withValues(alpha: 0.95),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 18, color: AppConstants.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _locationMessage!,
                        style: AppConstants.bodyStyle(fontSize: 12, color: AppConstants.secondary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // Reverse geocoding indicator
        if (_isReverseGeocoding)
          Positioned(
            top: MediaQuery.of(context).padding.top + 12 + 56 + (_locationMessage != null ? 60 : 0),
            left: 0,
            right: 0,
            child: const Center(
              child: Card(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 8),
                      Text('Getting address...'),
                    ],
                  ),
                ),
              ),
            ),
          ),

        // Bottom: Address preview + Confirm button
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: EdgeInsets.fromLTRB(
              20,
              16,
              20,
              MediaQuery.of(context).padding.bottom + 16,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 12,
                  offset: Offset(0, -2),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Drag indicator
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Delivery Location',
                  style: AppConstants.bodyStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_currentCenter.latitude.toStringAsFixed(5)}, '
                  '${_currentCenter.longitude.toStringAsFixed(5)}',
                  style: AppConstants.bodyStyle(
                    fontSize: 12,
                    color: AppConstants.secondary.withValues(alpha: 0.5),
                  ),
                ),
                const SizedBox(height: 16),
                SolePrimaryButton(
                  label: 'Confirm Location',
                  onPressed: () async {
                    await _reverseGeocode();
                    if (mounted) {
                      setState(() => _showMap = false);
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Search bar widget ─────────────────────────────────────────

  Widget _buildSearchBar() {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: const Color(0xFFF5F0EB),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        onChanged: _searchAddress,
        onTapOutside: (_) => FocusScope.of(context).unfocus(),
        style: AppConstants.bodyStyle(fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Search for your address, barangay, or landmark',
          hintStyle: AppConstants.bodyStyle(
            fontSize: 13,
            color: AppConstants.secondary.withValues(alpha: 0.4),
          ),
          prefixIcon: const Padding(
            padding: EdgeInsets.only(left: 14, right: 8),
            child: Icon(
              Icons.search,
              size: 20,
              color: AppConstants.secondary,
            ),
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 0,
            minHeight: 0,
          ),
          suffixIcon: _isSearchLoading
              ? const Padding(
                  padding: EdgeInsets.only(right: 14),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppConstants.primary,
                    ),
                  ),
                )
              : _searchController.text.isNotEmpty
                  ? GestureDetector(
                      onTap: () {
                        _searchController.clear();
                        _searchAddress('');
                      },
                      child: const Padding(
                        padding: EdgeInsets.only(right: 14),
                        child: Icon(
                          Icons.close,
                          size: 18,
                          color: AppConstants.secondary,
                        ),
                      ),
                    )
                  : null,
          suffixIconConstraints: const BoxConstraints(
            minWidth: 0,
            minHeight: 0,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
        ),
      ),
    );
  }

  // ── Prediction dropdown widget ────────────────────────────────

  Widget _buildPredictionDropdown() {
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        constraints: const BoxConstraints(maxHeight: 280),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: ListView.builder(
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          itemCount: _searchError != null
              ? 1
              : _searchPredictions.isEmpty
                  ? 1
                  : _searchPredictions.length,
          itemBuilder: (context, index) {
            // Error state
            if (_searchError != null) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 18,
                      color: AppConstants.error.withValues(alpha: 0.7),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _searchError!,
                        style: AppConstants.bodyStyle(
                          fontSize: 13,
                          color: AppConstants.error.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }

            // Empty state
            if (_searchPredictions.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      Icons.search_off,
                      size: 18,
                      color: AppConstants.secondary.withValues(alpha: 0.4),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'No results found — try a different search',
                        style: AppConstants.bodyStyle(
                          fontSize: 13,
                          color: AppConstants.secondary.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }

            // Prediction row
            final prediction = _searchPredictions[index];
            final placeName = prediction['place_name'] as String? ?? '';
            return InkWell(
              onTap: () => _onPredictionSelected(prediction),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.location_on_outlined,
                      size: 18,
                      color: AppConstants.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        placeName,
                        style: AppConstants.bodyStyle(fontSize: 13),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _circleButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, size: 22, color: AppConstants.secondary),
      ),
    );
  }

  // ── Step B: Address Details Form ──────────────────────────────

  Widget _buildFormStep() {
    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      appBar: AppBar(
        title: Text(
          _isEditing ? 'Edit Address' : 'Add Address',
          style: AppConstants.headlineStyle(fontSize: 20),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppConstants.secondary),
          onPressed: () {
            if (_showMap) {
              Navigator.of(context).pop();
            } else {
              setState(() => _showMap = true);
            }
          },
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Recipient Section ───────────────────────────
              _sectionHeader('Recipient Details'),
              const SizedBox(height: 12),
              SoleCard(
                color: Colors.white,
                child: Column(
                  children: [
                    SoleTextField(
                      labelText: 'Recipient Name',
                      hintText: 'Full name',
                      controller: _recipientNameController,
                      prefixIcon: Icons.person_outline,
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) {
                          return 'Recipient name is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    SoleTextField(
                      labelText: 'Phone Number',
                      hintText: '+63 9XX XXX XXXX',
                      controller: _recipientPhoneController,
                      keyboardType: TextInputType.phone,
                      prefixIcon: Icons.phone_outlined,
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) {
                          return 'Phone number is required';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // ── Address Section ─────────────────────────────
              _sectionHeader('Address Details'),
              const SizedBox(height: 12),
              SoleCard(
                color: Colors.white,
                child: Column(
                  children: [
                    SoleTextField(
                      labelText: 'Region',
                      controller: _regionController,
                      prefixIcon: Icons.map_outlined,
                      validator: (val) =>
                          val == null || val.trim().isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 16),
                    SoleTextField(
                      labelText: 'Province',
                      controller: _provinceController,
                      prefixIcon: Icons.location_city_outlined,
                      validator: (val) =>
                          val == null || val.trim().isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 16),
                    SoleTextField(
                      labelText: 'City / Municipality',
                      controller: _cityController,
                      prefixIcon: Icons.apartment_outlined,
                      validator: (val) =>
                          val == null || val.trim().isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 16),
                    SoleTextField(
                      labelText: 'Barangay',
                      controller: _barangayController,
                      prefixIcon: Icons.holiday_village_outlined,
                      validator: (val) =>
                          val == null || val.trim().isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 16),
                    SoleTextField(
                      labelText: 'Street Address / House No.',
                      hintText: 'House #, Unit, Building, Street',
                      controller: _streetController,
                      prefixIcon: Icons.home_outlined,
                      validator: (val) =>
                          val == null || val.trim().isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 16),
                    SoleTextField(
                      labelText: 'Landmark (Optional)',
                      hintText: 'e.g. near SM City Cebu',
                      controller: _landmarkController,
                      prefixIcon: Icons.place_outlined,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // ── Label & Default ─────────────────────────────
              _sectionHeader('Address Label'),
              const SizedBox(height: 12),
              SoleCard(
                color: Colors.white,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Label chips
                    Row(
                      children: [
                        _labelChip('Home', Icons.home_outlined),
                        const SizedBox(width: 8),
                        _labelChip('Work', Icons.work_outline),
                        const SizedBox(width: 8),
                        _labelChip('Other', Icons.location_on_outlined),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(color: AppConstants.borderGray),
                    const SizedBox(height: 8),
                    // Default toggle
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Set as default address',
                          style: AppConstants.bodyStyle(fontSize: 14),
                        ),
                        Switch(
                          value: _isDefault,
                          onChanged: (val) =>
                              setState(() => _isDefault = val),
                          activeThumbColor: AppConstants.primary,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // ── Save Button ─────────────────────────────────
              SolePrimaryButton(
                label: _isEditing ? 'Update Address' : 'Save Address',
                onPressed: _isSaving ? null : _saveAddress,
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 16,
          decoration: BoxDecoration(
            color: AppConstants.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: AppConstants.bodyStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppConstants.secondary,
          ),
        ),
      ],
    );
  }

  Widget _labelChip(String label, IconData icon) {
    final isSelected = _label == label;
    final color = isSelected ? AppConstants.primary : AppConstants.secondary;

    return GestureDetector(
      onTap: () => setState(() => _label = label),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppConstants.primary.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? AppConstants.primary
                : AppConstants.secondary.withValues(alpha: 0.2),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppConstants.bodyStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
