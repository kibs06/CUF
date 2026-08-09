import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../constants/app_constants.dart';
import '../../services/store_service.dart';
import '../../widgets/sole_primary_button.dart';
import '../../widgets/sole_switch.dart';

/// Edit store screen — same layout as [CreateStoreScreen] but pre-fills
/// all existing store data and allows toggling store open/closed.
class EditStoreScreen extends StatefulWidget {
  final Map<String, dynamic> store;

  const EditStoreScreen({super.key, required this.store});

  @override
  State<EditStoreScreen> createState() => _EditStoreScreenState();
}

class _EditStoreScreenState extends State<EditStoreScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _taglineController = TextEditingController();
  final _locationController = TextEditingController();
  final _storeService = StoreService.instance;
  final _imagePicker = ImagePicker();

  late String _brandColor;
  XFile? _newBannerImage;
  XFile? _newLogoImage;
  bool _removeBanner = false;
  bool _removeLogo = false;
  bool _isOpen = true;
  bool _isSaving = false;

  static const List<Map<String, dynamic>> _presetColors = [
    {'hex': '#8B5A2B', 'name': 'Burnished Clay'},
    {'hex': '#3B2314', 'name': 'Carob Dark'},
    {'hex': '#4ECDC4', 'name': 'Celadon Teal'},
    {'hex': '#E8A020', 'name': 'Amber'},
    {'hex': '#D64545', 'name': 'Crimson'},
    {'hex': '#2C5F2E', 'name': 'Forest Green'},
  ];

  @override
  void initState() {
    super.initState();
    _prefillFromStore();
  }

  void _prefillFromStore() {
    final s = widget.store;
    _nameController.text = s['name'] ?? '';
    _taglineController.text = s['tagline'] ?? '';
    _locationController.text = s['location'] ?? '';
    _brandColor = s['brand_color'] ?? '#8B5A2B';
    _isOpen = s['is_open'] ?? true;

  }

  @override
  void dispose() {
    _nameController.dispose();
    _taglineController.dispose();
    _locationController.dispose();

    super.dispose();
  }

  Future<void> _updateStore() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      // Save store basics (name, logo, banner, etc.)
      await _storeService.updateStoreSeller(
        storeId: widget.store['id'].toString(),
        name: _nameController.text,
        tagline: _taglineController.text,
        location: _locationController.text,
        brandColor: _brandColor,
        isOpen: _isOpen,
        newLogoImage: _newLogoImage,
        newBannerImage: _newBannerImage,
        removeLogo: _removeLogo,
        removeBanner: _removeBanner,
      );



      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Store updated!'),
            backgroundColor: AppConstants.success,
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Error: ${e.toString().replaceAll('Exception: ', '')}'),
            backgroundColor: AppConstants.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      appBar: AppBar(
        title: Text(
          'Edit Store',
          style: AppConstants.headlineStyle(fontSize: 20),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppConstants.secondary),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Stack(
        children: [
          AppConstants.noiseOverlay(opacity: 0.03),
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Section 1: Banner & Logo ──
                  _buildSectionHeader(
                      'Store Banner & Logo', Icons.photo_library_outlined),
                  const SizedBox(height: 12),
                  _buildBannerAndLogoSecion(),
                  const SizedBox(height: 28),

                  // ── Section 2: Store Info ──
                  _buildSectionHeader('Store Info', Icons.store_outlined),
                  const SizedBox(height: 12),
                  _buildStoreInfoSection(),
                  const SizedBox(height: 28),

                  // ── Section 3: Brand Color ──
                  _buildSectionHeader('Brand Color', Icons.palette_outlined),
                  const SizedBox(height: 12),
                  _buildColorSection(),
                  const SizedBox(height: 20),

                  // ── Section 4: Store Open Toggle ──
                  _buildOpenToggle(),
                  const SizedBox(height: 28),

                  const SizedBox(height: 32),

                  // ── Save Button ──
                  SolePrimaryButton(
                    label: 'Update Store',
                    isLoading: _isSaving,
                    onPressed: _isSaving ? null : _updateStore,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppConstants.primary),
        const SizedBox(width: 8),
        Text(title, style: AppConstants.headlineStyle(fontSize: 16)),
      ],
    );
  }

  // ── Banner & Logo ──

  bool get _hasBanner => _newBannerImage != null ||
      (widget.store['banner_url']?.toString().isNotEmpty == true && !_removeBanner);
  bool get _hasLogo => _newLogoImage != null ||
      (widget.store['logo_url']?.toString().isNotEmpty == true && !_removeLogo);

  Widget _buildBannerAndLogoSecion() {
    final existingBannerUrl = widget.store['banner_url']?.toString();
    final existingLogoUrl = widget.store['logo_url']?.toString();
    final showBanner = _newBannerImage != null ||
        (existingBannerUrl != null && !_removeBanner);
    final showLogo = _newLogoImage != null ||
        (existingLogoUrl != null && !_removeLogo);

    return SizedBox(
      height: 200,
      child: Stack(
        children: [
          // Banner
          GestureDetector(
            onTap: () => _pickImage(isBanner: true),
            child: Container(
              height: 160,
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: AppConstants.cardRadius,
                color: AppConstants.borderGray.withValues(alpha: 0.3),
              ),
              child: _newBannerImage != null
                  ? ClipRRect(
                      borderRadius: AppConstants.cardRadius,
                      child: Image.file(
                        File(_newBannerImage!.path),
                        fit: BoxFit.cover,
                      ),
                    )
                  : showBanner && existingBannerUrl != null
                      ? ClipRRect(
                          borderRadius: AppConstants.cardRadius,
                          child: CachedNetworkImage(
                            imageUrl: existingBannerUrl,
                            fit: BoxFit.cover,
                            placeholder: (_, _) => const Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppConstants.primary),
                              ),
                            ),
                          ),
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.camera_alt,
                                size: 36,
                                color: AppConstants.primary
                                    .withValues(alpha: 0.5)),
                            const SizedBox(height: 6),
                            Text(
                              'Tap to add banner',
                              style: AppConstants.bodyStyle(
                                fontSize: 12,
                                color: AppConstants.secondary
                                    .withValues(alpha: 0.5),
                              ),
                            ),
                          ],
                        ),
            ),
          ),
          // Banner delete button
          if (_hasBanner)
            Positioned(
              top: 8,
              right: 8,
              child: GestureDetector(
                onTap: () => _showRemoveDialog(isBanner: true),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.close,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
            ),
          // Logo + delete button
          Positioned(
            bottom: 0,
            left: 20,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                GestureDetector(
                  onTap: () => _pickImage(isBanner: false),
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      border: Border.all(
                          color: AppConstants.surfaceLight, width: 3),
                      boxShadow: AppConstants.warmShadow,
                    ),
                    child: _newLogoImage != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(40),
                            child: Image.file(
                              File(_newLogoImage!.path),
                              fit: BoxFit.cover,
                            ),
                          )
                        : showLogo && existingLogoUrl != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(40),
                                child: CachedNetworkImage(
                                  imageUrl: existingLogoUrl,
                                  fit: BoxFit.cover,
                                  placeholder: (_, _) => Center(
                                    child: SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: AppConstants.primary),
                                    ),
                                  ),
                                ),
                              )
                            : Icon(Icons.store_outlined,
                                size: 32,
                                color: AppConstants.primary
                                    .withValues(alpha: 0.5)),
                  ),
                ),
                if (_hasLogo)
                  Positioned(
                    top: -4,
                    right: -4,
                    child: GestureDetector(
                      onTap: () => _showRemoveDialog(isBanner: false),
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: AppConstants.error,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 12,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showRemoveDialog({required bool isBanner}) {
    final label = isBanner ? 'banner' : 'logo';
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Remove $label',
          style: AppConstants.bodyStyle(
              fontSize: 18, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Are you sure you want to remove the store $label? '
          'You can add a new one later.',
          style: AppConstants.bodyStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: AppConstants.bodyStyle(color: AppConstants.secondary),
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: AppConstants.error,
            ),
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                if (isBanner) {
                  _newBannerImage = null;
                  _removeBanner = true;
                } else {
                  _newLogoImage = null;
                  _removeLogo = true;
                }
              });
            },
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickImage({required bool isBanner}) async {
    final picked = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      maxWidth: isBanner ? 1920 : 512,
      maxHeight: isBanner ? 1080 : 512,
      imageQuality: 85,
    );
    if (picked != null) {
      setState(() {
        if (isBanner) {
          _newBannerImage = picked;
          _removeBanner = false;
        } else {
          _newLogoImage = picked;
          _removeLogo = false;
        }
      });
    }
  }

  // ── Store Info ──

  Widget _buildStoreInfoSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppConstants.cardRadius,
        boxShadow: AppConstants.warmShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Store Name *',
            style: AppConstants.bodyStyle(
                fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: _nameController,
            style: AppConstants.bodyStyle(fontSize: 15),
            decoration: _inputDecoration('e.g. Carcar Footwear Co.'),
            maxLength: 50,
            validator: (val) {
              if (val == null || val.trim().isEmpty) {
                return 'Store name is required';
              }
              if (val.trim().length < 3) {
                return 'Store name must be at least 3 characters';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          Text(
            'Tagline',
            style: AppConstants.bodyStyle(
                fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: _taglineController,
            style: AppConstants.bodyStyle(fontSize: 15),
            decoration: _inputDecoration(
                'e.g. Handcrafted in Carcar since 1998'),
            maxLength: 100,
          ),
          const SizedBox(height: 16),
          Text(
            'Location *',
            style: AppConstants.bodyStyle(
                fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: _locationController,
            style: AppConstants.bodyStyle(fontSize: 15),
            decoration: _inputDecoration('e.g. Carcar City, Cebu'),
            validator: (val) {
              if (val == null || val.trim().isEmpty) {
                return 'Location is required';
              }
              return null;
            },
          ),
        ],
      ),
    );
  }

  // ── Brand Color ──

  Widget _buildColorSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppConstants.cardRadius,
        boxShadow: AppConstants.warmShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Brand Color',
            style: AppConstants.bodyStyle(
                fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: _presetColors.map((c) {
              final hex = c['hex'] as String;
              final colorHex = hex.replaceFirst('#', '');
              final color = Color(int.parse('FF$colorHex', radix: 16));
              final isSelected = _brandColor == hex;

              return GestureDetector(
                onTap: () => setState(() => _brandColor = hex),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: isSelected
                        ? Border.all(
                            color: AppConstants.secondary, width: 3)
                        : Border.all(
                            color: AppConstants.borderGray
                                .withValues(alpha: 0.5)),
                    boxShadow: isSelected ? AppConstants.warmShadow : null,
                  ),
                  child: isSelected
                      ? const Icon(Icons.check,
                          color: Colors.white, size: 20)
                      : null,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
          Text(
            _presetColors.firstWhere(
              (c) => c['hex'] == _brandColor,
              orElse: () => _presetColors.first,
            )['name'] as String,
            style: AppConstants.bodyStyle(
              fontSize: 12,
              color: AppConstants.secondary.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }





  // ── Open Toggle ──

  Widget _buildOpenToggle() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppConstants.cardRadius,
        boxShadow: AppConstants.warmShadow,
      ),
      child: Material(
        color: Colors.transparent,
        child: SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            'Store is Open',
            style: AppConstants.bodyStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            _isOpen
                ? 'Customers can browse and order'
                : 'Store is closed to customers',
            style: AppConstants.bodyStyle(
              fontSize: 12,
            color: AppConstants.secondary.withValues(alpha: 0.6),
            ),
          ),
          value: _isOpen,
          onChanged: (val) => setState(() => _isOpen = val),
          activeThumbColor: SoleSwitch.thumbColor,
          inactiveThumbColor: SoleSwitch.thumbColor,
          inactiveTrackColor: SoleSwitch.offColor,
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: AppConstants.bodyStyle(
        fontSize: 14,
        color: AppConstants.secondary.withValues(alpha: 0.4),
      ),
      filled: true,
      fillColor: Colors.white,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: AppConstants.buttonRadius,
        borderSide: BorderSide(
            color: AppConstants.borderGray.withValues(alpha: 0.5)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: AppConstants.buttonRadius,
        borderSide: BorderSide(
            color: AppConstants.borderGray.withValues(alpha: 0.5)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: AppConstants.buttonRadius,
        borderSide:
            const BorderSide(color: AppConstants.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: AppConstants.buttonRadius,
        borderSide:
            const BorderSide(color: AppConstants.error, width: 1.5),
      ),
    );
  }
}
