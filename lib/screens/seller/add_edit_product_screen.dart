import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../constants/app_constants.dart';
import '../../models/product_models.dart';
import '../../services/product_service.dart';
import '../../widgets/sole_card.dart';
import '../../widgets/sole_text_field.dart';
import '../../widgets/sole_primary_button.dart';

/// Full add/edit product form for sellers.
///
/// Pass [product] as `null` for Add mode, or a product map for Edit mode.
/// All data reads from and writes to Supabase via [ProductService].
class AddEditProductScreen extends StatefulWidget {
  final Map<String, dynamic>? product;

  const AddEditProductScreen({super.key, this.product});

  @override
  State<AddEditProductScreen> createState() => _AddEditProductScreenState();
}

class _AddEditProductScreenState extends State<AddEditProductScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _descController = TextEditingController();
  final _tagController = TextEditingController();
  final _productService = ProductService.instance;
  final _imagePicker = ImagePicker();

  final _barcodeController = TextEditingController();
  String _category = 'Casual';
  bool _isActive = true;
  bool _isFeatured = false;
  bool _isSaving = false;
  double _uploadProgress = 0;
  bool _isUploading = false;

  // Images
  final List<_ImageItem> _imageItems = [];
  static const int _maxImages = 6;

  // Tags
  final List<String> _tags = [];
  static const int _maxTags = 10;

  // Variants
  final List<ProductVariant> _variants = [];

  // Customizations
  final List<ProductCustomization> _customizations = [];

  // Store ID (fetched on init)
  String? _storeId;

  static const List<String> _categories = [
    'Casual',
    'Formal',
    'Sports',
    'Sandals',
    'Custom',
    'Other',
  ];

  bool get isEdit => widget.product != null;

  @override
  void initState() {
    super.initState();
    _loadStoreId();
    if (isEdit) {
      _prefillFromProduct();
    }
  }

  Future<void> _loadStoreId() async {
    final storeId = await _productService.getSellerStoreId();
    if (mounted) {
      setState(() => _storeId = storeId);
    }
  }

  void _prefillFromProduct() {
    final p = widget.product!;
    _nameController.text = p['name'] ?? '';
    _priceController.text = (p['price'] ?? '').toString();
    _descController.text = p['description'] ?? '';
    _barcodeController.text = p['barcode'] ?? '';
    _category = p['category'] ?? 'Casual';
    _isActive = p['is_active'] ?? true;
    _isFeatured = p['is_featured'] ?? false;

    // Tags
    if (p['tags'] is List) {
      _tags.addAll(List<String>.from(p['tags']));
    }

    // Existing images
    if (p['product_images'] is List) {
      final images = List<Map<String, dynamic>>.from(p['product_images']);
      images.sort((a, b) =>
          ((a['display_order'] ?? 0) as int)
              .compareTo((b['display_order'] ?? 0) as int));
      for (final img in images) {
        _imageItems.add(_ImageItem(
          id: img['id']?.toString(),
          url: img['url']?.toString() ?? img['image_url']?.toString(),
        ));
      }
    }

    // Variants
    if (p['product_variants'] is List) {
      for (final v in p['product_variants']) {
        _variants.add(ProductVariant.fromMap(Map<String, dynamic>.from(v)));
      }
    }

    // Customizations
    if (p['product_customizations'] is List) {
      for (final c in p['product_customizations']) {
        _customizations
            .add(ProductCustomization.fromMap(Map<String, dynamic>.from(c)));
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _descController.dispose();
    _tagController.dispose();
    _barcodeController.dispose();
    super.dispose();
  }

  // ─── IMAGE ACTIONS ──────────────────────────────────────────────

  Future<void> _pickImages() async {
    final remaining = _maxImages - _imageItems.length;
    if (remaining <= 0) {
      _showSnackBar('Maximum $_maxImages images allowed.', isError: true);
      return;
    }

    final picked = await _imagePicker.pickMultiImage(
      maxWidth: 1200,
      maxHeight: 1200,
      imageQuality: 85,
    );

    if (picked.isNotEmpty) {
      final toAdd = picked.take(remaining).toList();
      setState(() {
        for (final file in toAdd) {
          _imageItems.add(_ImageItem(file: file));
        }
      });
    }
  }

  void _removeImage(int index) {
    final item = _imageItems[index];
    // If it's an existing image, remove from DB
    if (item.id != null && item.url != null) {
      _productService.removeImage(item.id!, item.url!);
    }
    setState(() => _imageItems.removeAt(index));
  }

  // ─── TAG ACTIONS ────────────────────────────────────────────────

  void _addTag() {
    final tag = _tagController.text.trim();
    if (tag.isEmpty) return;
    if (_tags.length >= _maxTags) {
      _showSnackBar('Maximum $_maxTags tags allowed.', isError: true);
      return;
    }
    if (_tags.contains(tag)) {
      _showSnackBar('Tag already exists.', isError: true);
      return;
    }
    setState(() {
      _tags.add(tag);
      _tagController.clear();
    });
  }

  // ─── VARIANT ACTIONS ────────────────────────────────────────────

  /// Sizing systems and their size lists.
  static const Map<String, List<String>> _sizingSystems = {
    'US': [
      '3', '3.5', '4', '4.5', '5', '5.5', '6', '6.5',
      '7', '7.5', '8', '8.5', '9', '9.5', '10', '10.5',
      '11', '11.5', '12', '13', '14', '15',
    ],
    'EU': [
      '35', '35.5', '36', '36.5', '37', '37.5', '38', '38.5',
      '39', '39.5', '40', '40.5', '41', '41.5', '42', '42.5',
      '43', '43.5', '44', '44.5', '45', '45.5', '46', '47',
    ],
    'UK': [
      '2', '2.5', '3', '3.5', '4', '4.5', '5', '5.5',
      '6', '6.5', '7', '7.5', '8', '8.5', '9', '9.5',
      '10', '10.5', '11', '12', '13', '14', '15',
    ],
  };

  /// Detect the sizing system from an existing size string.
  /// Returns the system key (e.g. 'EU', 'US') or 'Other' if unrecognized.
  String _detectSizingSystem(String size) {
    for (final system in _sizingSystems.keys) {
      if (size.toUpperCase().startsWith('$system ')) return system;
    }
    // Check if the numeric part matches a known system
    final numeric = size.replaceAll(RegExp(r'[^0-9.]'), '');
    for (final entry in _sizingSystems.entries) {
      if (entry.value.contains(numeric)) return entry.key;
    }
    return 'Other';
  }

  /// Extract the numeric size value from a size string with a known system prefix.
  String _extractSizeValue(String size, String system) {
    if (system == 'Other') return size;
    // Strip the prefix (e.g. 'EU 40' -> '40', 'US 8' -> '8')
    final prefix = '$system ';
    if (size.toUpperCase().startsWith(prefix.toUpperCase())) {
      return size.substring(prefix.length).trim();
    }
    // Try to extract just the numeric part
    return size.replaceAll(RegExp(r'[^0-9.]'), '');
  }

  void _showVariantSheet({ProductVariant? existing, int? editIndex}) {
    // Determine initial sizing system and size from existing variant
    final existingSize = existing?.size ?? '';
    String selectedSystem = _detectSizingSystem(existingSize);
    String selectedSizePreset = '';
    bool showCustomSize = false;
    bool showCustomSystem = selectedSystem == 'Other';
    final customSizeCtrl = TextEditingController();
    final customSystemCtrl = TextEditingController();

    if (selectedSystem != 'Other' && existingSize.isNotEmpty) {
      final extracted = _extractSizeValue(existingSize, selectedSystem);
      final systemSizes = _sizingSystems[selectedSystem] ?? [];
      if (systemSizes.contains(extracted)) {
        selectedSizePreset = extracted;
      } else {
        showCustomSize = true;
        customSizeCtrl.text = extracted;
      }
    } else if (existingSize.isNotEmpty) {
      showCustomSize = true;
      customSizeCtrl.text = existingSize;
    }

    final colorCtrl = TextEditingController(text: existing?.color ?? '');
    final stockCtrl =
        TextEditingController(text: existing?.stock.toString() ?? '0');
    final priceCtrl = TextEditingController(
        text: existing?.additionalPrice.toString() ?? '0');
    final skuCtrl = TextEditingController(text: existing?.sku ?? '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
              24, 20, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  editIndex != null ? 'Edit Variant' : 'Add Variant',
                  style: AppConstants.headlineStyle(fontSize: 20),
                ),
                const SizedBox(height: 16),
                // Size selector: dropdown + Other fallback
                // Sizing System selector
                Text(
                  'Sizing System *',
                  style: AppConstants.bodyStyle(
                      fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: showCustomSystem ? '__other__' : (selectedSystem.isEmpty ? null : selectedSystem),
                  hint: Text('Select sizing system', style: AppConstants.bodyStyle(fontSize: 14)),
                  style: AppConstants.bodyStyle(fontSize: 15),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: AppConstants.buttonRadius,
                      borderSide: const BorderSide(color: AppConstants.borderGray),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: AppConstants.buttonRadius,
                      borderSide: BorderSide(color: AppConstants.borderGray.withValues(alpha: 0.5), width: 1.5),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: AppConstants.buttonRadius,
                      borderSide: const BorderSide(color: AppConstants.primary, width: 1.5),
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'US', child: Text('US (American)')),
                    DropdownMenuItem(value: 'EU', child: Text('EU (European)')),
                    DropdownMenuItem(value: 'UK', child: Text('UK (British)')),
                    DropdownMenuItem(
                      value: '__other__',
                      child: Text('Other (custom system)'),
                    ),
                  ],
                  onChanged: (val) {
                    setSheetState(() {
                      if (val == '__other__') {
                        showCustomSystem = true;
                        selectedSystem = '';
                        selectedSizePreset = '';
                        showCustomSize = false;
                        customSizeCtrl.clear();
                      } else {
                        showCustomSystem = false;
                        selectedSystem = val ?? '';
                        selectedSizePreset = '';
                        showCustomSize = false;
                        customSizeCtrl.clear();
                      }
                    });
                  },
                ),
                if (showCustomSystem) ...[
                  const SizedBox(height: 10),
                  SoleTextField(
                    labelText: 'Custom Sizing System',
                    hintText: 'e.g. JP, CHN, AUS',
                    controller: customSystemCtrl,
                  ),
                ],
                const SizedBox(height: 12),
                // Size value selector (only shown when a system is selected)
                if (!showCustomSystem && selectedSystem.isNotEmpty) ...[
                  Text(
                    'Size *',
                    style: AppConstants.bodyStyle(
                        fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: showCustomSize ? '__other__' : (selectedSizePreset.isEmpty ? null : selectedSizePreset),
                    hint: Text('Select a size', style: AppConstants.bodyStyle(fontSize: 14)),
                    style: AppConstants.bodyStyle(fontSize: 15),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: AppConstants.buttonRadius,
                        borderSide: const BorderSide(color: AppConstants.borderGray),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: AppConstants.buttonRadius,
                        borderSide: BorderSide(color: AppConstants.borderGray.withValues(alpha: 0.5), width: 1.5),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: AppConstants.buttonRadius,
                        borderSide: const BorderSide(color: AppConstants.primary, width: 1.5),
                      ),
                    ),
                    items: [
                      ...(_sizingSystems[selectedSystem] ?? []).map((s) => DropdownMenuItem(
                        value: s,
                        child: Text(s),
                      )),
                      const DropdownMenuItem(
                        value: '__other__',
                        child: Text('Other (custom size)'),
                      ),
                    ],
                    onChanged: (val) {
                      setSheetState(() {
                        if (val == '__other__') {
                          showCustomSize = true;
                          selectedSizePreset = '';
                        } else {
                          showCustomSize = false;
                          selectedSizePreset = val ?? '';
                          customSizeCtrl.clear();
                        }
                      });
                    },
                  ),
                ],
                if (showCustomSize) ...[
                  const SizedBox(height: 10),
                  SoleTextField(
                    labelText: 'Custom Size',
                    hintText: 'e.g. 48, Kids 12',
                    controller: customSizeCtrl,
                  ),
                ],
                const SizedBox(height: 12),
                SoleTextField(
                  labelText: 'Color (optional)',
                  hintText: 'e.g. Black, Brown',
                  controller: colorCtrl,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: SoleTextField(
                        labelText: 'Stock *',
                        hintText: '0',
                        controller: stockCtrl,
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SoleTextField(
                        labelText: 'Extra Price (₱)',
                        hintText: '0',
                        controller: priceCtrl,
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SoleTextField(
                  labelText: 'SKU (optional)',
                  hintText: 'e.g. SV-OXF-BLK-42',
                  controller: skuCtrl,
                ),
                const SizedBox(height: 20),
                SolePrimaryButton(
                  label: editIndex != null ? 'Update Variant' : 'Add Variant',
                  onPressed: () {
                    // Resolve sizing system
                    final system = showCustomSystem
                        ? customSystemCtrl.text.trim()
                        : selectedSystem;
                    if (system.isEmpty) {
                      _showSnackBar('Sizing system is required.', isError: true);
                      return;
                    }
                    // Resolve size value
                    String sizeValue;
                    if (showCustomSystem || showCustomSize) {
                      sizeValue = customSizeCtrl.text.trim();
                    } else {
                      sizeValue = selectedSizePreset;
                    }
                    if (sizeValue.isEmpty) {
                      _showSnackBar('Size is required.', isError: true);
                      return;
                    }
                    // Format as 'SYSTEM SIZE' (e.g. 'EU 40', 'US 8')
                    final fullSize = '$system $sizeValue';
                    final variant = ProductVariant(
                      size: fullSize,
                      color: colorCtrl.text.trim().isNotEmpty
                          ? colorCtrl.text.trim()
                          : null,
                      stock: int.tryParse(stockCtrl.text) ?? 0,
                      additionalPrice: double.tryParse(priceCtrl.text) ?? 0,
                      sku: skuCtrl.text.trim().isNotEmpty
                          ? skuCtrl.text.trim()
                          : null,
                    );

                    setState(() {
                      if (editIndex != null) {
                        _variants[editIndex] = variant;
                      } else {
                        _variants.add(variant);
                      }
                    });
                    Navigator.of(ctx).pop();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── CUSTOMIZATION ACTIONS ──────────────────────────────────────

  /// Built-in customization type values.
  static const List<String> _builtinCustomizationTypes = ['text', 'select', 'color'];

  void _showCustomizationSheet(
      {ProductCustomization? existing, int? editIndex}) {
    final nameCtrl =
        TextEditingController(text: existing?.optionName ?? '');
    // Determine initial type: check if it's one of the built-in types
    final existingType = existing?.optionType ?? 'text';
    final isBuiltinType = _builtinCustomizationTypes.contains(existingType);
    String selectedTypePreset = isBuiltinType ? existingType : '';
    final customTypeCtrl = TextEditingController(
        text: isBuiltinType ? '' : existingType);
    bool showCustomType = !isBuiltinType && existingType.isNotEmpty;

    final choices = List<String>.from(existing?.options ?? []);
    final choiceCtrl = TextEditingController();
    bool isRequired = existing?.isRequired ?? false;
    final priceCtrl = TextEditingController(
        text: existing?.additionalPrice.toString() ?? '0');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
              24, 20, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  editIndex != null
                      ? 'Edit Customization'
                      : 'Add Customization',
                  style: AppConstants.headlineStyle(fontSize: 20),
                ),
                const SizedBox(height: 16),
                SoleTextField(
                  labelText: 'Option Name *',
                  hintText: 'e.g. Embroidery Text, Sole Color',
                  controller: nameCtrl,
                ),
                const SizedBox(height: 12),
                // Type selector: dropdown + Other fallback
                Text(
                  'Type *',
                  style: AppConstants.bodyStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: showCustomType ? '__other__' : (selectedTypePreset.isEmpty ? null : selectedTypePreset),
                  hint: Text('Select a type', style: AppConstants.bodyStyle(fontSize: 14)),
                  style: AppConstants.bodyStyle(fontSize: 15),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: AppConstants.buttonRadius,
                      borderSide: const BorderSide(color: AppConstants.borderGray),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: AppConstants.buttonRadius,
                      borderSide: BorderSide(color: AppConstants.borderGray.withValues(alpha: 0.5), width: 1.5),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: AppConstants.buttonRadius,
                      borderSide: const BorderSide(color: AppConstants.primary, width: 1.5),
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'text', child: Text('Text')),
                    DropdownMenuItem(value: 'select', child: Text('Select')),
                    DropdownMenuItem(value: 'color', child: Text('Color')),
                    DropdownMenuItem(
                      value: '__other__',
                      child: Text('Other (custom type)'),
                    ),
                  ],
                  onChanged: (val) {
                    setSheetState(() {
                      if (val == '__other__') {
                        showCustomType = true;
                        selectedTypePreset = '';
                      } else {
                        showCustomType = false;
                        selectedTypePreset = val ?? '';
                        customTypeCtrl.clear();
                      }
                    });
                  },
                ),
                if (showCustomType) ...[
                  const SizedBox(height: 10),
                  SoleTextField(
                    labelText: 'Custom Type',
                    hintText: 'e.g. number, date, file upload',
                    controller: customTypeCtrl,
                  ),
                ],
                if (selectedTypePreset == 'select' || selectedTypePreset == 'color') ...[
                  const SizedBox(height: 12),
                  Text(
                    'Choices',
                    style: AppConstants.bodyStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: SoleTextField(
                          labelText: '',
                          hintText: 'Add a choice...',
                          controller: choiceCtrl,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: () {
                          if (choiceCtrl.text.trim().isNotEmpty) {
                            setSheetState(() {
                              choices.add(choiceCtrl.text.trim());
                              choiceCtrl.clear();
                            });
                          }
                        },
                        icon: const Icon(Icons.add_circle,
                            color: AppConstants.primary, size: 28),
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: choices
                        .map((c) => Chip(
                              label: Text(c,
                                  style: AppConstants.bodyStyle(fontSize: 12)),
                              deleteIcon: const Icon(Icons.close, size: 14),
                              onDeleted: () {
                                setSheetState(() => choices.remove(c));
                              },
                              backgroundColor:
                                  AppConstants.accent.withValues(alpha: 0.15),
                              side: BorderSide.none,
                            ))
                        .toList(),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: SoleTextField(
                        labelText: 'Extra Price (₱)',
                        hintText: '0',
                        controller: priceCtrl,
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Column(
                      children: [
                        Text('Required',
                            style: AppConstants.bodyStyle(
                                fontWeight: FontWeight.bold, fontSize: 14)),
                        Switch(
                          value: isRequired,
                          onChanged: (val) {
                            setSheetState(() => isRequired = val);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                SolePrimaryButton(
                  label: editIndex != null
                      ? 'Update Customization'
                      : 'Add Customization',
                  onPressed: () {
                    if (nameCtrl.text.trim().isEmpty) {
                      _showSnackBar('Option name is required.',
                          isError: true);
                      return;
                    }
                    // Resolve type from dropdown or custom input
                    final typeValue = showCustomType
                        ? customTypeCtrl.text.trim()
                        : selectedTypePreset;
                    if (typeValue.isEmpty) {
                      _showSnackBar('Type is required.', isError: true);
                      return;
                    }
                    final customization = ProductCustomization(
                      optionName: nameCtrl.text.trim(),
                      optionType: typeValue,
                      options: choices,
                      isRequired: isRequired,
                      additionalPrice:
                          double.tryParse(priceCtrl.text) ?? 0,
                    );
                    setState(() {
                      if (editIndex != null) {
                        _customizations[editIndex] = customization;
                      } else {
                        _customizations.add(customization);
                      }
                    });
                    Navigator.of(ctx).pop();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── SAVE ───────────────────────────────────────────────────────

  Future<void> _saveProduct() async {
    if (!_formKey.currentState!.validate()) return;

    // Validation checks
    if (_imageItems.isEmpty) {
      _showSnackBar('Please add at least 1 product image.', isError: true);
      return;
    }
    if (_variants.isEmpty) {
      _showSnackBar('Please add at least 1 size/variant.', isError: true);
      return;
    }
    if (_storeId == null) {
      _showSnackBar('No store linked to your account. Contact admin.',
          isError: true);
      return;
    }

    setState(() {
      _isSaving = true;
      _isUploading = true;
      _uploadProgress = 0;
    });

    try {
      // Separate new files from existing URLs
      final newImages =
          _imageItems.where((i) => i.file != null).map((i) => i.file!).toList();
      final existingUrls =
          _imageItems.where((i) => i.url != null).map((i) => i.url!).toList();

      if (isEdit) {
        final productId = widget.product!['id'].toString();
        await _productService.updateProduct(
          productId: productId,
          name: _nameController.text,
          description: _descController.text,
          price: double.parse(_priceController.text),
          category: _category,
          tags: _tags,
          newImages: newImages,
          existingImageUrls: existingUrls,
          variants: _variants,
          customizations: _customizations,
          isActive: _isActive,
          isFeatured: _isFeatured,
          barcode: _barcodeController.text,
        );
        // Sync active status after variant changes
        try {
          await _productService.syncProductActiveStatus(productId);
        } catch (_) {
          // Silently fail — status will self-correct on next update
        }
        if (mounted) {
          _showSnackBar('Product updated!');
          Navigator.of(context).pop(true);
        }
      } else {
        final productId = await _productService.createProduct(
          storeId: _storeId!,
          name: _nameController.text,
          description: _descController.text,
          price: double.parse(_priceController.text),
          category: _category,
          tags: _tags,
          images: newImages,
          variants: _variants,
          customizations: _customizations,
          isActive: _isActive,
          isFeatured: _isFeatured,
          barcode: _barcodeController.text,
        );
        // Sync active status for new product
        try {
          await _productService.syncProductActiveStatus(productId);
        } catch (_) {
          // Silently fail — status will self-correct on next update
        }
        if (mounted) {
          _showSnackBar('Product saved!');
          Navigator.of(context).pop(true);
        }
      }
    } catch (e) {
      if (mounted) {
        String errorMessage = 'Failed to save product.';
        final errStr = e.toString();
        if (errStr.contains('image_url')) {
          errorMessage =
              'Image upload failed. Please check your connection and try again.';
        } else if (errStr.contains('empty URL') ||
            errStr.contains('empty string') ||
            errStr.contains('no valid URLs')) {
          errorMessage =
              'Could not get image URL. Please contact support.';
        } else if (errStr.contains('empty — could not read file')) {
          errorMessage = 'One or more image files could not be read. Try selecting different images.';
        } else {
          errorMessage = errStr.replaceAll('Exception: ', '');
        }

        _showSnackBar(errorMessage, isError: true, duration: const Duration(seconds: 5));
      }
    } finally {
      if (mounted) setState(() {
        _isSaving = false;
        _isUploading = false;
        _uploadProgress = 0;
      });
    }
  }

  void _showSnackBar(String message,
      {bool isError = false, Duration? duration}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppConstants.error : AppConstants.success,
        duration: duration ?? const Duration(seconds: 3),
      ),
    );
  }

  // ─── BUILD ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      appBar: AppBar(
        title: Text(
          isEdit ? 'Edit Product' : 'Add Product',
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
            padding: const EdgeInsets.all(20.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ─── SECTION 1: IMAGES ──────────────────────
                  _buildSectionHeader('Product Images', Icons.photo_library_outlined),
                  const SizedBox(height: 8),
                  _buildImagesSection(),

                  const SizedBox(height: 24),

                  // ─── SECTION 2: BASIC INFO ──────────────────
                  _buildSectionHeader('Basic Info', Icons.info_outline),
                  const SizedBox(height: 8),
                  _buildBasicInfoSection(),

                  const SizedBox(height: 24),

                  // ─── SECTION 3: BARCODE ─────────────────────
                  _buildSectionHeader('Barcode', Icons.qr_code),
                  const SizedBox(height: 8),
                  _buildBarcodeSection(),

                  const SizedBox(height: 24),

                  // ─── SECTION 4: TAGS ────────────────────────
                  _buildSectionHeader('Tags', Icons.label_outline),
                  const SizedBox(height: 8),
                  _buildTagsSection(),

                  const SizedBox(height: 24),

                  // ─── SECTION 5: VARIANTS ────────────────────
                  _buildSectionHeader(
                      'Sizes & Variants', Icons.straighten_outlined),
                  const SizedBox(height: 8),
                  _buildVariantsSection(),

                  const SizedBox(height: 24),

                  // ─── SECTION 6: CUSTOMIZATIONS ──────────────
                  _buildSectionHeader(
                      'Customization Options', Icons.tune_outlined),
                  const SizedBox(height: 8),
                  _buildCustomizationsSection(),

                  const SizedBox(height: 24),

                  // ─── SECTION 7: VISIBILITY ──────────────────
                  _buildSectionHeader('Visibility', Icons.visibility_outlined),
                  const SizedBox(height: 8),
                  _buildVisibilitySection(),

                  const SizedBox(height: 32),

                  // ─── UPLOAD PROGRESS ──────────────────────
                  if (_isUploading) ...[
                    LinearProgressIndicator(
                      value: _uploadProgress > 0 && _uploadProgress < 1
                          ? _uploadProgress
                          : null,
                      backgroundColor: AppConstants.borderGray,
                      color: AppConstants.primary,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Uploading images... ${(_uploadProgress * 100).toInt()}%',
                      style: AppConstants.bodyStyle(
                        fontSize: 12,
                        color: AppConstants.secondary.withValues(alpha: 0.6),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // ─── SAVE BUTTON ────────────────────────────
                  SolePrimaryButton(
                    label: isEdit ? 'Update Product' : 'Save Product',
                    isLoading: _isSaving,
                    onPressed: _isSaving ? null : _saveProduct,
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── SECTION BUILDERS ─────────────────────────────────────────

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: AppConstants.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: AppConstants.primary),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: AppConstants.bodyStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppConstants.secondary,
          ),
        ),
      ],
    );
  }

  // ── Images ──

  Widget _buildImagesSection() {
    return SizedBox(
      height: 100,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          ..._imageItems.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;
            return _buildImageTile(item, index);
          }),
          if (_imageItems.length < _maxImages) _buildAddImageTile(),
        ],
      ),
    );
  }

  Widget _buildImageTile(_ImageItem item, int index) {
    return Container(
      width: 90,
      height: 90,
      margin: const EdgeInsets.only(right: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: index == 0
              ? AppConstants.primary
              : AppConstants.borderGray,
          width: index == 0 ? 2 : 1,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: item.url != null
                ? CachedNetworkImage(
                    imageUrl: item.url!,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(
                      color: AppConstants.borderGray.withValues(alpha: 0.3),
                      child: const Center(
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppConstants.primary),
                        ),
                      ),
                    ),
                  )
                : FutureBuilder<List<int>>(
                    future: item.file!.readAsBytes(),
                    builder: (context, snapshot) {
                      if (snapshot.hasData) {
                        return Image.memory(
                          snapshot.data! as dynamic,
                          fit: BoxFit.cover,
                        );
                      }
                      return Container(
                        color: AppConstants.borderGray.withValues(alpha: 0.3),
                      );
                    },
                  ),
          ),
          // Primary badge
          if (index == 0)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 2),
                decoration: const BoxDecoration(
                  color: AppConstants.primary,
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(11),
                    bottomRight: Radius.circular(11),
                  ),
                ),
                child: Text(
                  'Main',
                  textAlign: TextAlign.center,
                  style: AppConstants.bodyStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          // Remove button
          Positioned(
            top: 2,
            right: 2,
            child: GestureDetector(
              onTap: () => _removeImage(index),
              child: Container(
                width: 20,
                height: 20,
                decoration: const BoxDecoration(
                  color: AppConstants.error,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, size: 12, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddImageTile() {
    return GestureDetector(
      onTap: _pickImages,
      child: Container(
        width: 90,
        height: 90,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppConstants.borderGray,
            style: BorderStyle.solid,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add_a_photo_outlined,
                color: AppConstants.primary, size: 24),
            const SizedBox(height: 4),
            Text(
              'Add Photo',
              style: AppConstants.bodyStyle(
                fontSize: 10,
                color: AppConstants.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Basic Info ──

  Widget _buildBasicInfoSection() {
    return SoleCard(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SoleTextField(
            labelText: 'Product Name *',
            hintText: 'e.g. Carcar Heritage Oxford',
            controller: _nameController,
            validator: (val) {
              if (val == null || val.trim().isEmpty) return 'Name is required';
              if (val.trim().length < 3) return 'Name must be at least 3 characters';
              if (val.trim().length > 100) return 'Name must be under 100 characters';
              return null;
            },
          ),
          const SizedBox(height: 16),

          // Category Dropdown
          Text(
            'Category *',
            style: AppConstants.bodyStyle(
                fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            value: _categories.contains(_category) ? _category : _categories.first,
            style: AppConstants.bodyStyle(fontSize: 15),
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.white,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: AppConstants.buttonRadius,
                borderSide: const BorderSide(color: AppConstants.borderGray),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: AppConstants.buttonRadius,
                borderSide: BorderSide(
                    color: AppConstants.borderGray.withValues(alpha: 0.5),
                    width: 1.5),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: AppConstants.buttonRadius,
                borderSide:
                    const BorderSide(color: AppConstants.primary, width: 1.5),
              ),
            ),
            items: _categories
                .map((cat) =>
                    DropdownMenuItem(value: cat, child: Text(cat)))
                .toList(),
            onChanged: (val) {
              if (val != null) setState(() => _category = val);
            },
            validator: (val) =>
                val == null || val.isEmpty ? 'Please select a category' : null,
          ),
          const SizedBox(height: 16),

          // Price
          Text(
            'Base Price (₱) *',
            style: AppConstants.bodyStyle(
                fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: _priceController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: AppConstants.monoStyle(fontSize: 15),
            decoration: InputDecoration(
              prefixText: '₱ ',
              prefixStyle: AppConstants.monoStyle(
                  fontSize: 15, fontWeight: FontWeight.bold),
              filled: true,
              fillColor: Colors.white,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: AppConstants.buttonRadius,
                borderSide: const BorderSide(color: AppConstants.borderGray),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: AppConstants.buttonRadius,
                borderSide: BorderSide(
                    color: AppConstants.borderGray.withValues(alpha: 0.5),
                    width: 1.5),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: AppConstants.buttonRadius,
                borderSide:
                    const BorderSide(color: AppConstants.primary, width: 1.5),
              ),
            ),
            validator: (val) {
              if (val == null || val.isEmpty) return 'Price is required';
              final price = double.tryParse(val);
              if (price == null || price <= 0) return 'Enter a valid price > 0';
              return null;
            },
          ),
          const SizedBox(height: 16),

          // Description
          SoleTextField(
            labelText: 'Description',
            hintText:
                'Describe details of leather stitching and design craftsmanship...',
            controller: _descController,
            maxLines: 4,
            validator: (val) {
              if (val != null && val.length > 500) {
                return 'Description must be under 500 characters';
              }
              return null;
            },
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${_descController.text.length}/500',
                style: AppConstants.monoStyle(
                  fontSize: 11,
                  color: AppConstants.secondary.withValues(alpha: 0.5),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Barcode ──

  Widget _buildBarcodeSection() {
    return SoleCard(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SoleTextField(
            labelText: 'Barcode (optional)',
            hintText: 'e.g. EAN-13, UPC-A, or QR code value',
            controller: _barcodeController,
            validator: (val) {
              if (val != null && val.length > 50) {
                return 'Barcode must be under 50 characters';
              }
              return null;
            },
          ),
          const SizedBox(height: 8),
          Text(
            'Scanned at POS for quick product lookup.',
            style: AppConstants.bodyStyle(
              fontSize: 12,
              color: AppConstants.secondary.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  // ── Tags ──

  Widget _buildTagsSection() {
    return SoleCard(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: SoleTextField(
                  labelText: '',
                  hintText: 'e.g. handmade, leather, slip-on',
                  controller: _tagController,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 48,
                child: FilledButton(
                  onPressed: _addTag,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppConstants.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: AppConstants.buttonRadius,
                    ),
                  ),
                  child: const Text('Add'),
                ),
              ),
            ],
          ),
          if (_tags.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _tags
                  .map((tag) => Chip(
                        label: Text(tag,
                            style: AppConstants.bodyStyle(
                                fontSize: 12,
                                color: AppConstants.accent)),
                        deleteIcon:
                            const Icon(Icons.close, size: 14, color: AppConstants.accent),
                        onDeleted: () => setState(() => _tags.remove(tag)),
                        backgroundColor:
                            AppConstants.accent.withValues(alpha: 0.12),
                        side: BorderSide.none,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ))
                  .toList(),
            ),
          ],
          if (_tags.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'No tags yet. Add up to $_maxTags tags.',
                style: AppConstants.bodyStyle(
                  fontSize: 12,
                  color: AppConstants.secondary.withValues(alpha: 0.5),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Variants ──

  Widget _buildVariantsSection() {
    return Column(
      children: [
        ..._variants.asMap().entries.map((entry) {
          final index = entry.key;
          final v = entry.value;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: AppConstants.cardRadius,
              boxShadow: AppConstants.warmShadow,
            ),
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppConstants.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(
                    v.size,
                    style: AppConstants.monoStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppConstants.primary,
                    ),
                  ),
                ),
              ),
              title: Text(
                'Size ${v.size}${v.color != null ? ' · ${v.color}' : ''}',
                style: AppConstants.bodyStyle(
                    fontWeight: FontWeight.bold, fontSize: 14),
              ),
              subtitle: Text(
                'Stock: ${v.stock}${v.additionalPrice > 0 ? '  ·  +₱${v.additionalPrice.toStringAsFixed(0)}' : ''}${v.sku != null ? '  ·  ${v.sku}' : ''}',
                style: AppConstants.monoStyle(
                    fontSize: 11,
                    color: AppConstants.secondary.withValues(alpha: 0.6)),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined,
                        size: 18, color: AppConstants.primary),
                    onPressed: () => _showVariantSheet(
                        existing: v, editIndex: index),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline,
                        size: 18, color: AppConstants.error),
                    onPressed: () =>
                        setState(() => _variants.removeAt(index)),
                  ),
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _showVariantSheet(),
            icon: const Icon(Icons.add, color: AppConstants.primary),
            label: Text(
              'Add Variant',
              style: AppConstants.bodyStyle(
                fontWeight: FontWeight.w600,
                color: AppConstants.primary,
              ),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppConstants.primary),
              shape: RoundedRectangleBorder(
                  borderRadius: AppConstants.buttonRadius),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    );
  }

  // ── Customizations ──

  Widget _buildCustomizationsSection() {
    return Column(
      children: [
        ..._customizations.asMap().entries.map((entry) {
          final index = entry.key;
          final c = entry.value;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: AppConstants.cardRadius,
              boxShadow: AppConstants.warmShadow,
            ),
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppConstants.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  c.optionType == 'color'
                      ? Icons.palette_outlined
                      : c.optionType == 'select'
                          ? Icons.list
                          : Icons.text_fields,
                  color: AppConstants.accent,
                  size: 20,
                ),
              ),
              title: Text(
                c.optionName,
                style: AppConstants.bodyStyle(
                    fontWeight: FontWeight.bold, fontSize: 14),
              ),
              subtitle: Text(
                '${c.optionType.toUpperCase()}${c.isRequired ? ' · Required' : ''}${c.additionalPrice > 0 ? ' · +₱${c.additionalPrice.toStringAsFixed(0)}' : ''}${c.options.isNotEmpty ? '\n${c.options.join(', ')}' : ''}',
                style: AppConstants.bodyStyle(
                    fontSize: 11,
                    color: AppConstants.secondary.withValues(alpha: 0.6)),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined,
                        size: 18, color: AppConstants.primary),
                    onPressed: () => _showCustomizationSheet(
                        existing: c, editIndex: index),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline,
                        size: 18, color: AppConstants.error),
                    onPressed: () =>
                        setState(() => _customizations.removeAt(index)),
                  ),
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _showCustomizationSheet(),
            icon: const Icon(Icons.add, color: AppConstants.primary),
            label: Text(
              'Add Customization',
              style: AppConstants.bodyStyle(
                fontWeight: FontWeight.w600,
                color: AppConstants.primary,
              ),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppConstants.primary),
              shape: RoundedRectangleBorder(
                  borderRadius: AppConstants.buttonRadius),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    );
  }

  // ── Visibility ──

  Widget _buildVisibilitySection() {
    return SoleCard(
      color: Colors.white,
      child: Column(
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Active',
                style:
                    AppConstants.bodyStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            subtitle: Text(
              _isActive
                  ? 'Product is visible to customers'
                  : 'Product is hidden from customers',
              style: AppConstants.bodyStyle(
                fontSize: 12,
                color: AppConstants.secondary.withValues(alpha: 0.6),
              ),
            ),
            value: _isActive,
            onChanged: (val) => setState(() => _isActive = val),
          ),
          const Divider(height: 1),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Featured',
                style:
                    AppConstants.bodyStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            subtitle: Text(
              _isFeatured
                  ? 'Appears in the featured section'
                  : 'Not in featured section',
              style: AppConstants.bodyStyle(
                fontSize: 12,
                color: AppConstants.secondary.withValues(alpha: 0.6),
              ),
            ),
            value: _isFeatured,
            onChanged: (val) => setState(() => _isFeatured = val),
          ),
        ],
      ),
    );
  }
}

// ─── Image item helper ────────────────────────────────────────────
/// Represents either an existing remote image or a newly picked local file.
class _ImageItem {
  final String? id; // DB id for existing images
  final String? url; // Remote URL for existing images
  final XFile? file; // Local file for new picks

  _ImageItem({this.id, this.url, this.file})
      : assert(url != null || file != null);
}
