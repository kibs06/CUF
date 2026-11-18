import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../constants/app_constants.dart';
import '../../services/reverse_geocode_service.dart';
import '../../widgets/sole_primary_button.dart';

/// Result returned when the seller confirms a store location.
typedef StoreLocationResult = ({
  String address,
  double latitude,
  double longitude,
});

/// Lightweight full-screen store-location picker for the seller application
/// (Step 3).
///
/// Reuses the same infrastructure as the customer's delivery-address picker
/// (MapTiler tiles + geocoding, Geolocator GPS) but WITHOUT the
/// delivery-address form: the seller searches or drags the map pin and
/// confirms with one button. Pops with a [StoreLocationResult].
class StoreLocationPickerScreen extends StatefulWidget {
  const StoreLocationPickerScreen({super.key});

  @override
  State<StoreLocationPickerScreen> createState() =>
      _StoreLocationPickerScreenState();
}

class _StoreLocationPickerScreenState extends State<StoreLocationPickerScreen> {
  final MapController _mapController = MapController();
  // Cebu City default — the app's home market.
  LatLng _center = const LatLng(10.3157, 123.8854);
  bool _isLocating = true;
  bool _isReverseGeocoding = false;
  String? _locationMessage;
  String? _addressPreview;

  // ── Search state (MapTiler geocoding) ─────────────────────────
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _predictions = [];
  bool _showPredictions = false;
  bool _isSearchLoading = false;
  String? _searchError;
  Timer? _searchDebounce;
  Timer? _reverseDebounce;

  @override
  void initState() {
    super.initState();
    _autoLocateOnOpen();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _reverseDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  // ── Auto-locate on open ───────────────────────────────────────
  Future<void> _autoLocateOnOpen() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _locationMessage =
            'Location services are off — search or drag the pin to your store';
        if (mounted) setState(() => _isLocating = false);
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        _locationMessage =
            'Location access denied — search or drag the pin to your store';
        if (mounted) setState(() => _isLocating = false);
        return;
      }
      if (permission == LocationPermission.deniedForever) {
        _locationMessage =
            'Location permission off in Settings — search or drag the pin manually';
        if (mounted) setState(() => _isLocating = false);
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      _center = LatLng(position.latitude, position.longitude);
      if (mounted) {
        setState(() {
          _isLocating = false;
          _locationMessage = null;
        });
        // Move after the first frame so the map controller is attached.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _mapController.move(_center, _mapController.camera.zoom);
          }
        });
      }
      await _reverseGeocode();
    } catch (e) {
      debugPrint('[StoreLocationPicker] auto-locate error: $e');
      if (mounted) {
        setState(() {
          _isLocating = false;
          _locationMessage =
              'Could not get location — search or drag the pin to your store';
        });
      }
    }
  }

  // ── Search (MapTiler geocoding) ───────────────────────────────
  void _searchAddress(String query) {
    _searchDebounce?.cancel();
    if (query.trim().length < 2) {
      if (mounted) {
        setState(() {
          _predictions = [];
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

    setState(() {
      _isSearchLoading = true;
      _searchError = null;
    });

    try {
      final encodedQuery = Uri.encodeComponent(query);
      // Search goes through the geocode-proxy Edge Function (holds the
      // MapTiler key server-side + rate-limits per IP — Threat T6).
      final url = Uri.parse(
        '${AppConstants.geocodeProxyBaseUrl}/search?q=$encodedQuery',
      );

      final client = HttpClient();
      try {
        final request = await client.getUrl(url);
        request.headers.set('User-Agent', 'com.solevision.app');
        final response = await request.close().timeout(
          const Duration(seconds: 8),
        );
        final body = await response.transform(utf8.decoder).join();
        if (!mounted) return;

        if (response.statusCode != 200) {
          setState(() {
            _searchError = response.statusCode == 429
                ? 'Search is busy right now — try again in a moment.'
                : 'Search unavailable right now (HTTP ${response.statusCode})';
            _isSearchLoading = false;
          });
          return;
        }

        final data = json.decode(body) as Map<String, dynamic>;
        final features = data['features'] as List<dynamic>? ?? [];
        setState(() {
          _predictions = features.take(5).map((f) {
            final coords = f['center'] as List<dynamic>? ?? [0, 0];
            return {
              'place_name': f['place_name'] ?? '',
              'lng': coords[0],
              'lat': coords[1],
            };
          }).toList();
          _showPredictions = _predictions.isNotEmpty;
          _isSearchLoading = false;
        });
      } finally {
        client.close();
      }
    } catch (e) {
      debugPrint('[StoreLocationPicker] geocoding error: $e');
      if (mounted) {
        setState(() {
          _searchError = 'Search unavailable right now';
          _isSearchLoading = false;
        });
      }
    }
  }

  void _onPredictionSelected(Map<String, dynamic> prediction) {
    FocusScope.of(context).unfocus();
    setState(() {
      _showPredictions = false;
      _searchController.text = prediction['place_name'] as String? ?? '';
    });
    final target = LatLng(
      (prediction['lat'] as num).toDouble(),
      (prediction['lng'] as num).toDouble(),
    );
    _mapController.move(target, 17);
    setState(() {
      _center = target;
      _locationMessage = null;
    });
    _reverseGeocode();
  }

  void _scheduleReverseGeocode() {
    _reverseDebounce?.cancel();
    _reverseDebounce = Timer(const Duration(milliseconds: 600), () {
      if (mounted && !_isReverseGeocoding && !_isLocating) {
        _reverseGeocode();
      }
    });
  }

  // ── GPS recenter ──────────────────────────────────────────────
  Future<void> _useCurrentLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showSnack('Location services are disabled.');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showSnack('Location permission denied.');
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        _showSnack(
          'Location permission permanently denied. Enable it in Settings.',
        );
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      _center = LatLng(position.latitude, position.longitude);
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _mapController.move(_center, _mapController.camera.zoom);
          }
        });
        setState(() => _locationMessage = null);
      }
      await _reverseGeocode();
    } catch (e) {
      debugPrint('[StoreLocationPicker] GPS error: $e');
      _showSnack('Could not get your location.');
    }
  }

  // ── Reverse geocode the pinned center ─────────────────────────
  // Uses the exact same lookup as the customer address picker, so the
  // seller's store location gets the barangay-level label too.
  Future<void> _reverseGeocode() async {
    if (!mounted) return;
    setState(() => _isReverseGeocoding = true);

    final result = await const ReverseGeocodeService().lookupWithDeviceFallback(
      latitude: _center.latitude,
      longitude: _center.longitude,
    );
    if (!mounted) return;

    final label = result?.areaLabel.trim() ?? '';
    setState(() {
      _isReverseGeocoding = false;
      _addressPreview = label.isEmpty ? null : label;
    });
  }

  Future<void> _confirm() async {
    // Make sure the preview belongs to the current pin even if the user
    // tapped before the drag debounce fired.
    await _reverseGeocode();
    if (!mounted) return;

    final address = (_addressPreview == null || _addressPreview!.trim().isEmpty)
        ? '${_center.latitude.toStringAsFixed(5)}, '
              '${_center.longitude.toStringAsFixed(5)}'
        : _addressPreview!.trim();
    Navigator.of(context).pop<StoreLocationResult>((
      address: address,
      latitude: _center.latitude,
      longitude: _center.longitude,
    ));
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), backgroundColor: AppConstants.error),
      );
  }

  // ── Build ─────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[300],
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _center,
              initialZoom: 16,
              onPositionChanged: (position, hasGesture) {
                if (hasGesture && mounted) {
                  setState(() => _center = position.center);
                  _scheduleReverseGeocode();
                }
              },
            ),
            children: [
              TileLayer(
                // Tiles proxy through geocode-proxy so the MapTiler key
                // never ships in the app (Threat T6).
                urlTemplate:
                    '${AppConstants.geocodeProxyBaseUrl}/tiles/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.solevision.app',
              ),
              const RichAttributionWidget(
                attributions: [
                  TextSourceAttribution(
                    '© MapTiler © OpenStreetMap contributors',
                  ),
                ],
                showFlutterMapAttribution: false,
              ),
            ],
          ),

          // Center pin (fixed — the map moves underneath)
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

          // Search bar overlay (top)
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 68,
            right: 16,
            child: _buildSearchBar(),
          ),

          // Prediction dropdown
          if (_showPredictions || _searchError != null)
            Positioned(
              top: MediaQuery.of(context).padding.top + 64,
              left: 68,
              right: 16,
              child: _buildPredictionDropdown(),
            ),

          // My location (bottom-right, above the confirm sheet)
          Positioned(
            bottom: 220,
            right: 16,
            child: _circleButton(
              icon: Icons.my_location,
              onTap: _useCurrentLocation,
            ),
          ),

          // GPS fix loading
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

          // Friendly status message (permission denied, etc.)
          if (!_isLocating && _locationMessage != null)
            Positioned(
              top: MediaQuery.of(context).padding.top + 68,
              left: 68,
              right: 16,
              child: Card(
                color: Colors.white.withValues(alpha: 0.95),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        size: 18,
                        color: AppConstants.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _locationMessage!,
                          style: AppConstants.bodyStyle(
                            fontSize: 12,
                            color: AppConstants.secondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Bottom: address preview + confirm
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
              decoration: BoxDecoration(
                color: AppConstants.surfaceLight,
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
                    'Store Location',
                    style: AppConstants.bodyStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (_isReverseGeocoding) ...[
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: Text(
                          _addressPreview ??
                              (_isLocating
                                  ? 'Finding your location…'
                                  : 'Pinned location'),
                          style: AppConstants.bodyStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_center.latitude.toStringAsFixed(5)}, '
                    '${_center.longitude.toStringAsFixed(5)}',
                    style: AppConstants.bodyStyle(
                      fontSize: 12,
                      color: AppConstants.secondary.withValues(alpha: 0.5),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Search or drag the pin to adjust the exact spot.',
                    style: AppConstants.bodyStyle(
                      fontSize: 11,
                      color: AppConstants.secondary.withValues(alpha: 0.5),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SolePrimaryButton(
                    label: 'Use this location',
                    onPressed: _confirm,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: AppConstants.surfaceLight,
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
          hintText: 'Search for your store address, barangay, or landmark',
          hintStyle: AppConstants.bodyStyle(
            fontSize: 13,
            color: AppConstants.secondary.withValues(alpha: 0.4),
          ),
          prefixIcon: Padding(
            padding: EdgeInsets.only(left: 14, right: 8),
            child: Icon(Icons.search, size: 20, color: AppConstants.secondary),
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
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }

  Widget _buildPredictionDropdown() {
    return Card(
      elevation: 4,
      margin: EdgeInsets.zero,
      child: _searchError != null
          ? Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _searchError!,
                style: AppConstants.bodyStyle(
                  fontSize: 12,
                  color: AppConstants.error,
                ),
              ),
            )
          : ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: _predictions.length,
              separatorBuilder: (_, _) =>
                  Divider(height: 1, color: Colors.grey[200]),
              itemBuilder: (context, index) {
                final p = _predictions[index];
                return ListTile(
                  dense: true,
                  title: Text(
                    p['place_name'] as String? ?? '',
                    style: AppConstants.bodyStyle(
                      fontSize: 13,
                      color: AppConstants.secondary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => _onPredictionSelected(p),
                );
              },
            ),
    );
  }

  Widget _circleButton({required IconData icon, required VoidCallback onTap}) {
    return Material(
      color: AppConstants.surfaceLight,
      shape: const CircleBorder(),
      elevation: 4,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Icon(icon, size: 22, color: AppConstants.secondary),
        ),
      ),
    );
  }
}
