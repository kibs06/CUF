import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../constants/app_constants.dart';
import '../../services/store_service.dart';
import '../../widgets/sole_primary_button.dart';

/// First-time store setup screen for sellers.
///
/// Shown when a seller has no store yet. Collects store name, tagline,
/// location, brand color, and optional banner/logo images.
class CreateStoreScreen extends StatefulWidget {
  const CreateStoreScreen({super.key});

  @override
  State<CreateStoreScreen> createState() => _CreateStoreScreenState();
}

class _CreateStoreScreenState extends State<CreateStoreScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _taglineController = TextEditingController();
  final _locationController = TextEditingController();
  final _storeService = StoreService.instance;
  final _imagePicker = ImagePicker();

  String _brandColor = '#8B5A2B';
  XFile? _bannerImage;
  XFile? _logoImage;
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
  void dispose() {
    _nameController.dispose();
    _taglineController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _createStore() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      await _storeService.createStore(
        name: _nameController.text,
        tagline: _taglineController.text,
        location: _locationController.text,
        brandColor: _brandColor,
        logoImage: _logoImage,
        bannerImage: _bannerImage,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Your store is ready!'),
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
          'Set Up Your Store',
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
                  // Subtitle
                  Text(
                    'Tell customers about your craft',
                    style: AppConstants.bodyStyle(
                        fontSize: 14,
                        color: AppConstants.secondary.withValues(alpha: 0.6)),
                  ),
                  const SizedBox(height: 24),

                  // ── Section 1: Banner & Logo ──
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
                  const SizedBox(height: 32),

                  // ── Save Button ──
                  SolePrimaryButton(
                    label: 'Create My Store',
                    isLoading: _isSaving,
                    onPressed: _isSaving ? null : _createStore,
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

  Widget _buildBannerAndLogoSecion() {
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
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF8B5A2B),
                    Color(0xFF3B2314),
                  ],
                ),
              ),
              child: _bannerImage != null
                  ? ClipRRect(
                      borderRadius: AppConstants.cardRadius,
                      child: Image.file(
                        File(_bannerImage!.path),
                        fit: BoxFit.cover,
                      ),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.camera_alt,
                            size: 40,
                            color: Colors.white.withValues(alpha: 0.7)),
                        const SizedBox(height: 8),
                        Text(
                          'Add Banner',
                          style: AppConstants.bodyStyle(
                            fontSize: 13,
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          // Logo (overlapping bottom-left)
          Positioned(
            bottom: 0,
            left: 20,
            child: GestureDetector(
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
                child: _logoImage != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(40),
                        child: Image.file(
                          File(_logoImage!.path),
                          fit: BoxFit.cover,
                        ),
                      )
                    : Icon(Icons.store_outlined,
                        size: 32, color: AppConstants.primary.withValues(alpha: 0.5)),
              ),
            ),
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
          _bannerImage = picked;
        } else {
          _logoImage = picked;
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
          // Store Name
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
          // Tagline
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
          // Location
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
