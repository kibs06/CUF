import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../constants/app_constants.dart';
import '../../constants/seller_theme_constants.dart';
import '../../models/product_models.dart';
import '../../services/product_service.dart';
import '../../widgets/sole_card.dart';
import '../../widgets/sole_text_field.dart';
import '../../widgets/sole_primary_button.dart';
import '../../widgets/sole_switch.dart';
import '../../widgets/seller/tag_selector.dart';

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
  final _productService = ProductService.instance;
  final _imagePicker = ImagePicker();

  final _barcodeController = TextEditingController();
  final _salePriceController = TextEditingController();
  DateTime? _saleStartsAt;
  DateTime? _saleEndsAt;
  String _category = 'Casual';
  bool _isActive = true;
  bool _isFeatured = false;
  bool _isSaving = false;
  double _uploadProgress = 0;
  bool _isUploading = false;

  // Images
  final List<_ImageItem> _imageItems = [];
  static const int _maxImages = 6;

  // Tags — persisted on the product (products.tags). Presets are stored as
  // snake_case ids; custom "Other" entries as `custom:<group>:<text>` so they
  // stay distinguishable. See _ProductTagSelector for parse/serialize.
  final List<String> _tags = [];

  // Variants
  final List<ProductVariant> _variants = [];

  // Customizations
  final List<ProductCustomization> _customizations = [];

  // Store ID (fetched on init)
  String? _storeId;

  // Single source of truth lives in AppConstants so the seller form and the
  // customer home filter share the same preset list and can never drift.
  static const List<String> _categories = AppConstants.productCategories;

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
    _salePriceController.text = (p['sale_price'] ?? '').toString();
    _saleStartsAt =
        DateTime.tryParse(p['sale_starts_at']?.toString() ?? '');
    _saleEndsAt = DateTime.tryParse(p['sale_ends_at']?.toString() ?? '');

    // Tags — passed through raw; the grouped selector parses every stored
    // string (presets, `custom:<group>:<text>` entries, and legacy free text)
    // and pre-selects / re-renders the right chips.
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
    _barcodeController.dispose();
    _salePriceController.dispose();
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
    // Determine initial sizing system and size from an existing variant.
    // Sizes are stored as 'SYSTEM SIZE' (e.g. 'EU 40', 'JP 25').
    final existingSize = existing?.size ?? '';
    String selectedSystem = '';
    // Multi-select sizes: each selected size becomes its own variant on save.
    List<String> selectedSizes = [];
    String customSystemSizeText = ''; // free-text size for CUSTOM systems
    final detectedSystem = _detectSizingSystem(existingSize);
    if (detectedSystem != 'Other' && existingSize.isNotEmpty) {
      // Known system prefix (e.g. 'EU 40' → system 'EU', size '40').
      selectedSystem = detectedSystem;
      selectedSizes = [_extractSizeValue(existingSize, detectedSystem)];
    } else if (existingSize.isNotEmpty) {
      // Unknown system — try splitting 'SYSTEM SIZE' on the first space so a
      // custom system (e.g. 'JP 25') prefills as system 'JP' + size '25'.
      final space = existingSize.indexOf(' ');
      if (space > 0) {
        selectedSystem = existingSize.substring(0, space).trim();
        customSystemSizeText = existingSize.substring(space + 1).trim();
      } else {
        // No recoverable system — keep the raw value for a custom-system size.
        customSystemSizeText = existingSize;
      }
    }
    // Free-text size field, only shown when a custom system is selected
    // (custom systems have no size presets).
    final customSizeCtrl = TextEditingController(text: customSystemSizeText);

    final colorCtrl = TextEditingController(text: existing?.color ?? '');
    final stockCtrl =
        TextEditingController(text: existing?.stock.toString() ?? '0');
    final priceCtrl = TextEditingController(
        text: existing?.additionalPrice.toString() ?? '0');
    final skuCtrl = TextEditingController(text: existing?.sku ?? '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppConstants.sellerCardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          // Live count of sizes about to be created — powers the button label
          // ("Add 3 Variants"). Recomputes on every sheet rebuild.
          final sizeCount = _sizingSystems.containsKey(selectedSystem)
              ? selectedSizes.length
              : (customSizeCtrl.text.trim().isNotEmpty ? 1 : 0);
          return Padding(
          padding: EdgeInsets.fromLTRB(
              24, 20, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  editIndex != null
                      ? (sizeCount > 1
                          ? 'Edit $sizeCount Variants'
                          : 'Edit Variant')
                      : (sizeCount > 1
                          ? 'Add $sizeCount Variants'
                          : 'Add Variant'),
                  style: AppConstants.headlineStyle(fontSize: 20),
                ),
                const SizedBox(height: 16),
                // Sizing System — single-select chips (+ Other for custom
                // systems like JP/CHN). Values stay compact codes; the chips
                // show the friendly full names.
                Text(
                  'Sizing System *',
                  style: AppConstants.bodyStyle(
                      fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 6),
                _PresetChipSelector(
                  key: const ValueKey('sizing-system'),
                  initialValue: selectedSystem,
                  presets: const ['US', 'EU', 'UK'],
                  presetLabels: const {
                    'US': 'US (American)',
                    'EU': 'EU (European)',
                    'UK': 'UK (British)',
                  },
                  otherHint: 'e.g. JP, CHN, AUS',
                  emptyError: 'Type a sizing system first.',
                  duplicateError:
                      'That is already a system — tap it above instead.',
                  onChanged: (value) {
                    setSheetState(() {
                      selectedSystem = value;
                      selectedSizes = [];
                      customSizeCtrl.clear();
                    });
                  },
                ),
                const SizedBox(height: 12),
                // Size value selector — MULTI-select chips (each selected
                // size becomes its own variant on save); free text when the
                // system is custom (no preset sizes).
                if (selectedSystem.isNotEmpty) ...[
                  Text(
                    'Size * (select multiple)',
                    style: AppConstants.bodyStyle(
                        fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 6),
                  if (_sizingSystems.containsKey(selectedSystem))
                    _SizeMultiSelector(
                      // Re-created whenever the system changes so sizes
                      // picked for one system can't leak into another.
                      key: ValueKey('sizes-$selectedSystem'),
                      initialSelected: selectedSizes,
                      presets: _sizingSystems[selectedSystem] ?? const [],
                      otherHint: 'e.g. 48, Kids 12',
                      emptyError: 'Type a size first.',
                      duplicateError:
                          'That is already a size — tap it above instead.',
                      onChanged: (values) {
                        setSheetState(() => selectedSizes = values);
                      },
                    )
                  else ...[
                    SoleTextField(
                      labelText: 'Custom Size',
                      hintText: 'e.g. 48, Kids 12',
                      controller: customSizeCtrl,
                    ),
                  ],
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
                  label: editIndex != null
                      ? (sizeCount > 1
                          ? 'Update $sizeCount Variants'
                          : 'Update Variant')
                      : (sizeCount > 1
                          ? 'Add $sizeCount Variants'
                          : 'Add Variant'),
                  onPressed: () {
                    // Resolve sizing system — preset code or custom text from
                    // the chip selector (single source of truth).
                    final system = selectedSystem.trim();
                    if (system.isEmpty) {
                      _showSnackBar('Sizing system is required.', isError: true);
                      return;
                    }
                    // Resolve size values — each selected chip (or the custom
                    // free-text size for custom systems) becomes its own
                    // variant, sharing color/stock/price/sku.
                    final sizeValues = _sizingSystems.containsKey(system)
                        ? selectedSizes
                            .map((s) => s.trim())
                            .where((s) => s.isNotEmpty)
                            .toList()
                        : (customSizeCtrl.text.trim().isNotEmpty
                            ? [customSizeCtrl.text.trim()]
                            : <String>[]);
                    if (sizeValues.isEmpty) {
                      _showSnackBar('Select at least one size.',
                          isError: true);
                      return;
                    }
                    final color = colorCtrl.text.trim().isNotEmpty
                        ? colorCtrl.text.trim()
                        : null;
                    final stock = int.tryParse(stockCtrl.text) ?? 0;
                    final additionalPrice =
                        double.tryParse(priceCtrl.text) ?? 0;
                    final sku = skuCtrl.text.trim().isNotEmpty
                        ? skuCtrl.text.trim()
                        : null;
                    // Format each as 'SYSTEM SIZE' (e.g. 'EU 40', 'US 8').
                    // When one entry creates several sizes, each variant
                    // suffixes its size onto the shared SKU so SKUs stay
                    // unique (e.g. SV-OXF-BLK-42-8 / -9 / -10).
                    final makeSku = sku != null && sizeValues.length > 1
                        ? (String size) => '$sku-$size'
                        : (String _) => sku;
                    final variants = [
                      for (final sizeValue in sizeValues)
                        ProductVariant(
                          size: '$system $sizeValue',
                          color: color,
                          stock: stock,
                          additionalPrice: additionalPrice,
                          sku: makeSku(sizeValue),
                        ),
                    ];

                    setState(() {
                      if (editIndex != null) {
                        // Replace the single edited variant with the new set.
                        _variants.removeAt(editIndex);
                        _variants.insertAll(editIndex, variants);
                      } else {
                        _variants.addAll(variants);
                      }
                    });
                    Navigator.of(ctx).pop();
                  },
                ),
              ],
            ),
          ),
          );
        },
      ),
    );
  }

  // ─── CUSTOMIZATION ACTIONS ──────────────────────────────────────

  void _showCustomizationSheet(
      {ProductCustomization? existing, int? editIndex}) {
    final nameCtrl =
        TextEditingController(text: existing?.optionName ?? '');
    // Type selector: single-select chips (Text / Select / Color) with a
    // custom "+ Other" fallback. The selector prefills a built-in type as a
    // selected chip, a previously-saved custom type as a custom chip, and
    // defaults new customizations to 'text' (matching the old dropdown's
    // pre-selected "Text" so adding a customization never requires touching
    // the type field).
    String selectedType = existing?.optionType ?? 'text';

    final choices = List<String>.from(existing?.options ?? []);
    final choiceCtrl = TextEditingController();
    bool isRequired = existing?.isRequired ?? false;
    final priceCtrl = TextEditingController(
        text: existing?.additionalPrice.toString() ?? '0');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppConstants.sellerCardBg,
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
                // Type selector: single-select chips (+ Other for custom
                // types like number/date/file upload).
                Text(
                  'Type *',
                  style: AppConstants.bodyStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 6),
                _PresetChipSelector(
                  key: const ValueKey('customization-type'),
                  initialValue: selectedType,
                  presets: const ['text', 'select', 'color'],
                  presetLabels: const {
                    'text': 'Text',
                    'select': 'Select',
                    'color': 'Color',
                  },
                  otherHint: 'e.g. number, date, file upload',
                  duplicateError:
                      'That is already a type — tap it above instead.',
                  onChanged: (value) {
                    setSheetState(() => selectedType = value);
                  },
                ),
                if (selectedType == 'select' || selectedType == 'color') ...[
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
                                  AppConstants.primary.withValues(alpha: 0.12),
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
                        SoleSwitch(
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
                    // Resolve type — preset value or custom text from the
                    // chip selector (single source of truth).
                    final typeValue = selectedType.trim();
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

    // Sale price validation — a sale only counts while it is strictly below
    // the base price (enforced by the shared sale_price.dart helper; we
    // surface a clear message here for better UX).
    final double? salePrice =
        double.tryParse(_salePriceController.text.trim());
    if (salePrice != null &&
        salePrice > 0 &&
        salePrice >= double.parse(_priceController.text)) {
      _showSnackBar('Sale price must be lower than the base price.',
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
          salePrice: salePrice,
          saleStartsAt: _saleStartsAt,
          saleEndsAt: _saleEndsAt,
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
          salePrice: salePrice,
          saleStartsAt: _saleStartsAt,
          saleEndsAt: _saleEndsAt,
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
      if (mounted) {
        setState(() {
        _isSaving = false;
        _isUploading = false;
        _uploadProgress = 0;
      });
      }
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
      backgroundColor: AppConstants.sellerSurface,
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

                  // ─── SALE (OPTIONAL) ────────────────────────
                  _buildSectionHeader('Sale (Optional)',
                      Icons.local_offer_outlined),
                  const SizedBox(height: 8),
                  _buildSaleSection(),

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
                        color: SellerTheme.textSecondary,
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

  // ─── SALE SECTION ──────────────────────────────────────────────

  String _formatSaleDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickSaleDate({required bool isEnd}) async {
    final current = isEnd ? _saleEndsAt : _saleStartsAt;
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2036),
    );
    if (picked != null) {
      setState(() {
        if (isEnd) {
          _saleEndsAt = picked;
        } else {
          _saleStartsAt = picked;
        }
      });
    }
  }

  Widget _buildSaleSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Discounted price (₱)',
          style: AppConstants.bodyStyle(
              fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: _salePriceController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: AppConstants.monoStyle(fontSize: 15),
          decoration: InputDecoration(
            prefixText: '₱ ',
            prefixStyle: AppConstants.monoStyle(
                fontSize: 15, fontWeight: FontWeight.bold),
            hintText: 'Leave empty for no sale',
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
              borderSide: const BorderSide(color: AppConstants.borderGray),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Original price is never changed — customers see the discounted '
          'price with the original crossed out.',
          style: AppConstants.bodyStyle(
            fontSize: 11,
            color: AppConstants.secondary.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _pickSaleDate(isEnd: false),
                icon: const Icon(Icons.event_outlined, size: 16),
                label: Text(
                  _saleStartsAt != null
                      ? 'Starts: ${_formatSaleDate(_saleStartsAt!)}'
                      : 'Start date (optional)',
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppConstants.secondary,
                  side: const BorderSide(color: AppConstants.borderGray),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _pickSaleDate(isEnd: true),
                icon: const Icon(Icons.event_outlined, size: 16),
                label: Text(
                  _saleEndsAt != null
                      ? 'Ends: ${_formatSaleDate(_saleEndsAt!)}'
                      : 'End date (optional)',
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppConstants.secondary,
                  side: const BorderSide(color: AppConstants.borderGray),
                ),
              ),
            ),
          ],
        ),
        if (_saleStartsAt != null || _saleEndsAt != null)
          TextButton.icon(
            onPressed: () => setState(() {
              _saleStartsAt = null;
              _saleEndsAt = null;
            }),
            icon: const Icon(Icons.close, size: 16),
            label: const Text('Clear sale dates'),
            style: TextButton.styleFrom(foregroundColor: AppConstants.error),
          ),
      ],
    );
  }

  // ─── SECTION BUILDERS ─────────────────────────────────────────

  /// Seller-styled form card — warm cream surface with the hairline espresso
  /// border and soft shadow used across the seller module, so the product
  /// form reads as part of the same espresso/cream design.
  Widget _formCard({required Widget child}) {
    return SoleCard(
      color: AppConstants.sellerCardBg,
      border: Border.all(color: SellerTheme.cardBorder),
      shadow: AppConstants.sellerShadow,
      child: child,
    );
  }

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
                    placeholder: (_, _) => Container(
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
    return _formCard(
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

          // Category — single-select animated chips (replaces the dropdown).
          // Radio-style: tapping a chip selects it and deselects the previous
          // one; the dashed "+ Other" chip reveals an inline custom-category
          // input. Wrapped in a FormField so the dropdown's required
          // validation still blocks submission if nothing is selected.
          Text(
            'Category *',
            style: AppConstants.bodyStyle(
                fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 6),
          FormField<String>(
            initialValue: _category,
            validator: (val) =>
                val == null || val.isEmpty ? 'Please select a category' : null,
            builder: (field) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _PresetChipSelector(
                    initialValue: field.value ?? '',
                    presets: _categories,
                    otherHint: 'Add your own category…',
                    emptyError: 'Type a category first.',
                    duplicateError:
                        'That is already a category option — tap it above instead.',
                    onChanged: (value) {
                      field.didChange(value);
                      _category = value;
                    },
                  ),
                  if (field.hasError) ...[
                    const SizedBox(height: 6),
                    Text(
                      field.errorText!,
                      style: AppConstants.bodyStyle(
                        fontSize: 12,
                        color: AppConstants.error,
                      ),
                    ),
                  ],
                ],
              );
            },
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
                  color: SellerTheme.textSecondary,
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
    return _formCard(
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
    return _formCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Select all that apply across each group, or add your own with '
            'the + Other option. These help customers find your product.',
            style: AppConstants.bodyStyle(
              fontSize: 12,
              color: AppConstants.secondary.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 16),
          // Grouped multi-select chips. The selector owns its state +
          // animation scope so a chip tap rebuilds only this section, and it
          // reports the serialized tag list back via onChanged.
          _ProductTagSelector(
            initialTags: _tags,
            onChanged: (tags) => _tags..clear()..addAll(tags),
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
              color: AppConstants.sellerCardBg,
              borderRadius: AppConstants.cardRadius,
              border: Border.all(color: SellerTheme.cardBorder),
              boxShadow: AppConstants.sellerShadow,
            ),
            child: Material(
              color: Colors.transparent,
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
              color: AppConstants.sellerCardBg,
              borderRadius: AppConstants.cardRadius,
              border: Border.all(color: SellerTheme.cardBorder),
              boxShadow: AppConstants.sellerShadow,
            ),
            child: Material(
              color: Colors.transparent,
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
                child: Icon(
                  c.optionType == 'color'
                      ? Icons.palette_outlined
                      : c.optionType == 'select'
                          ? Icons.list
                          : Icons.text_fields,
                  color: AppConstants.primary,
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
    return _formCard(
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: SwitchListTile(
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
                  color: SellerTheme.textMuted,
                ),
              ),
              value: _isActive,
              onChanged: (val) => setState(() => _isActive = val),
              activeThumbColor: SoleSwitch.thumbColor,
              inactiveThumbColor: SoleSwitch.thumbColor,
              inactiveTrackColor: SoleSwitch.offColor,
            ),
          ),
          const Divider(height: 1),
          Material(
            color: Colors.transparent,
            child: SwitchListTile(
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
                  color: SellerTheme.textMuted,
                ),
              ),
              value: _isFeatured,
              onChanged: (val) => setState(() => _isFeatured = val),
              activeThumbColor: SoleSwitch.thumbColor,
              inactiveThumbColor: SoleSwitch.thumbColor,
              inactiveTrackColor: SoleSwitch.offColor,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Grouped product tag selector ────────────────────────────────
// The preset vocabulary (TagPreset/TagGroup/tagGroups) lives in
// lib/widgets/seller/tag_selector.dart so the seller application's
// Storefront step and the store forms share the SAME tags as products.
// This file keeps its own private widget copies (selector + chips) and
// aliases the shared definitions so the two never drift apart.
// (`_TagGroup` aliases the shared TagGroup so the group/chip widgets below
// keep their original private names while sharing the preset vocabulary.)
typedef _TagGroup = TagGroup;

const List<_TagGroup> _tagGroups = tagGroups;

const _TagGroup _otherBucketGroup = otherBucketGroup;

const int _maxCustomTagLength = 30;

/// Lowercased preset id → canonical stored id, for parsing legacy values
/// case-insensitively (e.g. "Handmade" -> "handmade").
final Map<String, String> _presetCanonicalByLower = {
  for (final g in _tagGroups)
    for (final p in g.presets) p.id.toLowerCase(): p.id,
};

/// One selected tag entry (a preset or a custom value) scoped to a group.
class _TagEntry {
  final String group;
  final String value; // preset id, or raw custom text
  final bool custom;
  const _TagEntry({
    required this.group,
    required this.value,
    required this.custom,
  });
}

/// Serialize a custom entry into its stored form: `custom:<group>:<text>`.
/// The fixed prefix makes customs unambiguously distinguishable from preset
/// ids (plain snake_case strings) and records the group so edit mode can
/// re-render the chip in the right section.
String _customStoredValue(String group, String text) => 'custom:$group:$text';

/// Parse one stored tag string into a [_TagEntry].
///   * known preset id (case-insensitive) → preset in its group
///   * `custom:<group>:<text>`            → custom in that group
///   * anything else (legacy free text)   → custom in the 'other' bucket
_TagEntry _parseStoredTag(String raw) {
  final t = raw.trim();
  final lower = t.toLowerCase();
  final canonical = _presetCanonicalByLower[lower];
  if (canonical != null) {
    final group = _tagGroups
        .firstWhere((g) => g.presets.any((p) => p.id == canonical))
        .id;
    return _TagEntry(group: group, value: canonical, custom: false);
  }
  if (lower.startsWith('custom:')) {
    final parts = t.split(':');
    if (parts.length >= 3) {
      final group = parts[1].toLowerCase();
      final text = parts.sublist(2).join(':').trim();
      final known = _tagGroups.any((g) => g.id == group) || group == 'other';
      if (known && text.isNotEmpty) {
        return _TagEntry(group: group, value: text, custom: true);
      }
    }
    // Malformed custom entry (e.g. "custom:type:" with no text) — drop it
    // rather than rendering the raw prefix as a chip.
    return const _TagEntry(group: 'other', value: '', custom: true);
  }
  return _TagEntry(group: 'other', value: t, custom: true);
}

/// Parse a list of stored tags, dropping entries that produced no value
/// (empty strings and malformed `custom:` entries).
List<_TagEntry> _parseTags(List<String> raw) {
  final result = <_TagEntry>[];
  for (final t in raw) {
    final e = _parseStoredTag(t);
    if (e.value.isNotEmpty) result.add(e);
  }
  return result;
}

/// Grouped, multi-select tag selector for the product form.
///
/// Renders the three preset groups (Product type / Material / Sustainability)
/// plus a custom "+ Other" input per group. Owns its selection state and
/// animation scope so a chip tap rebuilds only this section, and reports the
/// fully-serialized tag list up via [onChanged] — the form persists exactly
/// what's shown in the same write as the rest of the form.
class _ProductTagSelector extends StatefulWidget {
  final List<String> initialTags;
  final ValueChanged<List<String>> onChanged;

  const _ProductTagSelector({
    required this.initialTags,
    required this.onChanged,
  });

  @override
  State<_ProductTagSelector> createState() => _ProductTagSelectorState();
}

class _ProductTagSelectorState extends State<_ProductTagSelector> {
  late final List<_TagEntry> _entries = _parseTags(widget.initialTags);

  // Per-group "Other" input state. The controllers are owned by this widget
  // (created lazily, disposed here) — never disposed mid-teardown of a route,
  // which is what prevents the framework's `_dependents.isEmpty` assertion.
  final Map<String, TextEditingController> _otherControllers = {};
  final Map<String, bool> _otherOpen = {};
  final Map<String, String?> _otherErrors = {};

  TextEditingController _controllerFor(String group) =>
      _otherControllers.putIfAbsent(group, TextEditingController.new);

  @override
  void dispose() {
    for (final c in _otherControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  List<_TagEntry> _groupEntries(String group) =>
      _entries.where((e) => e.group == group).toList();

  /// Serialize the selection in display order (group by group, presets then
  /// customs) and report it up so the form persists exactly what's shown.
  void _push() {
    final stored = <String>[];
    void addGroup(String gid) {
      stored.addAll(
          _groupEntries(gid).where((e) => !e.custom).map((e) => e.value));
      stored.addAll(_groupEntries(gid)
          .where((e) => e.custom)
          .map((e) => _customStoredValue(e.group, e.value)));
    }

    for (final g in _tagGroups) {
      addGroup(g.id);
    }
    addGroup(_otherBucketGroup.id);
    widget.onChanged(stored);
  }

  void _togglePreset(_TagGroup group, String id) {
    setState(() {
      final idx = _entries.indexWhere(
          (e) => !e.custom && e.group == group.id && e.value == id);
      if (idx >= 0) {
        _entries.removeAt(idx);
      } else {
        _entries.add(_TagEntry(group: group.id, value: id, custom: false));
      }
    });
    _push();
  }

  void _toggleOtherInput(String group) {
    setState(() {
      _otherOpen[group] = !(_otherOpen[group] ?? false);
      _otherErrors.remove(group);
    });
  }

  void _addCustom(String group) {
    final ctrl = _controllerFor(group);
    final text = ctrl.text.trim();
    if (text.isEmpty) {
      setState(() => _otherErrors[group] = 'Type a tag first.');
      return;
    }
    if (text.length > _maxCustomTagLength) {
      setState(() => _otherErrors[group] =
          'Keep it under $_maxCustomTagLength characters.');
      return;
    }
    final lower = text.toLowerCase();
    final groupPresets = _tagGroups.firstWhere((g) => g.id == group).presets;
    if (groupPresets.any((p) => p.id.toLowerCase() == lower)) {
      setState(() => _otherErrors[group] =
          'That is already a preset option — tap it above instead.');
      return;
    }
    if (_groupEntries(group)
        .any((e) => e.custom && e.value.toLowerCase() == lower)) {
      setState(() => _otherErrors[group] = 'That tag is already added.');
      return;
    }
    setState(() {
      _entries.add(_TagEntry(group: group, value: text, custom: true));
      ctrl.clear();
      _otherErrors.remove(group);
    });
    _push();
  }

  void _removeCustom(String group, String value) {
    setState(() {
      _entries.removeWhere(
          (e) => e.custom && e.group == group && e.value == value);
    });
    _push();
  }

  @override
  Widget build(BuildContext context) {
    final otherEntries = _groupEntries(_otherBucketGroup.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final group in _tagGroups) ...[
          _buildGroup(group),
          const SizedBox(height: 22),
        ],
        if (otherEntries.isNotEmpty) ...[
          _buildGroupLabel(_otherBucketGroup),
          _buildCustomChips(_otherBucketGroup, otherEntries),
        ],
      ],
    );
  }

  Widget _buildGroup(_TagGroup group) {
    final entries = _groupEntries(group.id);
    final customs = entries.where((e) => e.custom).toList();
    final isOpen = _otherOpen[group.id] ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildGroupLabel(group),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in group.presets)
              _TagChip(
                label: p.label,
                icon: p.icon,
                color: group.color,
                onColor: group.onColor,
                selected: entries.any((e) => !e.custom && e.value == p.id),
                onTap: () => _togglePreset(group, p.id),
              ),
            _OtherTagChip(
              color: group.color,
              open: isOpen,
              onTap: () => _toggleOtherInput(group.id),
            ),
          ],
        ),
        // Custom chips animate in/out via AnimatedSwitcher — only on user
        // interaction; the initial render (edit-mode pre-fill) is static.
        _buildCustomChips(group, customs),
        if (isOpen) ...[
          const SizedBox(height: 10),
          _buildOtherInput(group),
        ],
      ],
    );
  }

  Widget _buildCustomChips(_TagGroup group, List<_TagEntry> customs) {
    return _CustomChipSwitcher(
      keyValue: customs.isEmpty
          ? null
          : customs.map((e) => e.value.toLowerCase()).join('\u0001'),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final e in customs)
            _CustomTagChip(
              label: e.value,
              color: group.color,
              onColor: group.onColor,
              onRemove: () => _removeCustom(group.id, e.value),
            ),
        ],
      ),
    );
  }

  Widget _buildGroupLabel(_TagGroup group) {
    return Row(
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: group.color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(group.icon, size: 14, color: group.color),
        ),
        const SizedBox(width: 8),
        Text(
          group.label,
          style: AppConstants.bodyStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppConstants.secondary,
          ),
        ),
      ],
    );
  }

  Widget _buildOtherInput(_TagGroup group) {
    final ctrl = _controllerFor(group.id);
    final error = _otherErrors[group.id];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: ctrl,
                autofocus: true,
                maxLength: _maxCustomTagLength,
                style: AppConstants.bodyStyle(fontSize: 14),
                decoration: InputDecoration(
                  counterText: '',
                  isDense: true,
                  hintText: 'Add your own ${group.label.toLowerCase()}…',
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: AppConstants.buttonRadius,
                    borderSide:
                        const BorderSide(color: AppConstants.borderGray),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: AppConstants.buttonRadius,
                    borderSide:
                        const BorderSide(color: AppConstants.borderGray),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: AppConstants.buttonRadius,
                    borderSide: BorderSide(color: group.color, width: 1.5),
                  ),
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _addCustom(group.id),
              ),
            ),
            const SizedBox(width: 8),
            _AddCustomButton(
              color: group.color,
              onColor: group.onColor,
              onPressed: () => _addCustom(group.id),
            ),
          ],
        ),
        if (error != null) ...[
          const SizedBox(height: 6),
          Text(
            error,
            style: AppConstants.bodyStyle(
              fontSize: 12,
              color: AppConstants.error,
            ),
          ),
        ],
      ],
    );
  }
}

/// One preset chip with a subtle "pop" on tap (quick scale up ~1.07 then
/// settle back) and an animated fill/border/color transition on selection.
/// Colors come from the owning [_TagGroup]. The animation only plays on user
/// interaction — the initial render (edit-mode pre-fill) is static.
class _TagChip extends StatefulWidget {
  final String label;
  final IconData? icon; // null → text-only chip (used by the category row)
  final Color color;
  final Color onColor;
  final bool selected;
  final VoidCallback onTap;

  const _TagChip({
    required this.label,
    this.icon,
    required this.color,
    required this.onColor,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_TagChip> createState() => _TagChipState();
}

class _TagChipState extends State<_TagChip> with SingleTickerProviderStateMixin {
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  );
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(begin: 1.0, end: 1.07)
          .chain(CurveTween(curve: Curves.easeOut)),
      weight: 45,
    ),
    TweenSequenceItem(
      tween: Tween(begin: 1.07, end: 1.0)
          .chain(CurveTween(curve: Curves.easeInOut)),
      weight: 55,
    ),
  ]).animate(_pop);

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  void _handleTap() {
    _pop.forward(from: 0);
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    // Unselected chips stay uniform (white fill, muted carob text, suede
    // border); selection fills the chip with the group's accent color and
    // swaps the content to the group's on-color.
    final offColor = AppConstants.secondary.withValues(alpha: 0.65);

    return Semantics(
      button: true,
      selected: selected,
      label: widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _handleTap,
        child: AnimatedBuilder(
          animation: _scale,
          builder: (context, child) =>
              Transform.scale(scale: _scale.value, child: child),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: selected ? widget.color : Colors.white,
              borderRadius: AppConstants.stadiumRadius,
              border: Border.all(
                color: selected ? widget.color : AppConstants.borderGray,
                width: 1.5,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: widget.color.withValues(alpha: 0.25),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.icon != null) ...[
                  Icon(widget.icon,
                      size: 16, color: selected ? widget.onColor : offColor),
                  const SizedBox(width: 6),
                ],
                Text(
                  widget.label,
                  style: AppConstants.bodyStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected ? widget.onColor : offColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A selected custom tag chip. Always shown in the selected (filled) state;
/// tapping removes it from the selection entirely (custom entries have no
/// reason to persist as an option once unchecked).
class _CustomTagChip extends StatefulWidget {
  final String label;
  final Color color;
  final Color onColor;
  final VoidCallback onRemove;

  const _CustomTagChip({
    required this.label,
    required this.color,
    required this.onColor,
    required this.onRemove,
  });

  @override
  State<_CustomTagChip> createState() => _CustomTagChipState();
}

class _CustomTagChipState extends State<_CustomTagChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  );
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(begin: 1.0, end: 1.07)
          .chain(CurveTween(curve: Curves.easeOut)),
      weight: 45,
    ),
    TweenSequenceItem(
      tween: Tween(begin: 1.07, end: 1.0)
          .chain(CurveTween(curve: Curves.easeInOut)),
      weight: 55,
    ),
  ]).animate(_pop);

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  void _handleRemove() {
    _pop.forward(from: 0);
    widget.onRemove();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Remove ${widget.label}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _handleRemove,
        child: AnimatedBuilder(
          animation: _scale,
          builder: (context, child) =>
              Transform.scale(scale: _scale.value, child: child),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: widget.color,
              borderRadius: AppConstants.stadiumRadius,
              border: Border.all(color: widget.color, width: 1.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.close, size: 14, color: widget.onColor),
                const SizedBox(width: 6),
                Text(
                  widget.label,
                  style: AppConstants.bodyStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: widget.onColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The "+ Other" chip per group. Dashed border + distinct icon signal that it
/// adds a custom value rather than selecting a fixed option; tapping toggles
/// the group's inline text input.
class _OtherTagChip extends StatelessWidget {
  final Color color;
  final bool open;
  final VoidCallback onTap;

  const _OtherTagChip({
    required this.color,
    required this.open,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: open ? 'Close input' : 'Add your own',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          decoration: BoxDecoration(
            color: open ? color.withValues(alpha: 0.08) : Colors.white,
            borderRadius: AppConstants.stadiumRadius,
          ),
          child: CustomPaint(
            painter: _DashedBorderPainter(
              color: color.withValues(alpha: open ? 0.95 : 0.55),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(open ? Icons.close : Icons.add, size: 15, color: color),
                  const SizedBox(width: 5),
                  Text(
                    open ? 'Close' : 'Other',
                    style: AppConstants.bodyStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints a dashed rounded-rect border (used for the "+ Other" chip so it
/// reads as "add your own" rather than a fixed option).
class _DashedBorderPainter extends CustomPainter {
  final Color color;
  static const double _dashLength = 5;
  static const double _gapLength = 4;

  _DashedBorderPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Offset.zero & size,
        Radius.circular(size.height / 2),
      ));
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(
          metric.extractPath(distance, distance + _dashLength),
          paint,
        );
        distance += _dashLength + _gapLength;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Small filled "+ Add" button beside the inline custom-tag input.
class _AddCustomButton extends StatelessWidget {
  final Color color;
  final Color onColor;
  final VoidCallback onPressed;

  const _AddCustomButton({
    required this.color,
    required this.onColor,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: AppConstants.buttonRadius,
      child: InkWell(
        onTap: onPressed,
        borderRadius: AppConstants.buttonRadius,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add, size: 16, color: onColor),
              const SizedBox(width: 4),
              Text(
                'Add',
                style: AppConstants.bodyStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: onColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fade/scale switcher for custom chips — animates chips in/out on add/remove
/// (user interaction) and stays static on the initial render. Both the old
/// and new children stay left-aligned while they cross-fade, so the row
/// slides in place instead of re-centering.
class _CustomChipSwitcher extends StatelessWidget {
  /// Drives the transition: changes → animate; null → collapsed (nothing).
  final String? keyValue;
  final Widget child;

  const _CustomChipSwitcher({
    required this.keyValue,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final collapsed = keyValue == null;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 240),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: Alignment.centerLeft,
        children: [...previousChildren, ?currentChild],
      ),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.9, end: 1).animate(animation),
          child: child,
        ),
      ),
      child: collapsed
          ? const SizedBox.shrink()
          : Padding(
              key: ValueKey(keyValue),
              padding: const EdgeInsets.only(top: 10),
              child: child,
            ),
    );
  }
}

/// Single-select chip row (radio-style, replaces the old dropdown pattern).
///
/// Tapping a preset chip selects it and deselects the previous selection; the
/// dashed "+ Other" chip reveals an inline text input for a custom value.
/// Only one value can be active at a time, and picking a preset fully replaces
/// any custom value. Reports the active VALUE (a preset value or the custom
/// text) up via [onChanged]. Display labels are decoupled from stored values
/// via [presetLabels] (e.g. 'US' → 'US (American)'), so chips can read nicely
/// while the persisted value stays compact.
class _PresetChipSelector extends StatefulWidget {
  final String initialValue;
  final List<String> presets;

  /// Optional display label per preset value — the chip shows
  /// `presetLabels[value] ?? value`, while the selected/reported value stays
  /// the raw preset value.
  final Map<String, String>? presetLabels;

  /// Hint text for the inline custom-value input.
  final String otherHint;

  /// Error shown when the custom input is submitted empty.
  final String emptyError;

  /// Error shown when the custom input duplicates a preset value.
  final String duplicateError;

  final ValueChanged<String> onChanged;

  const _PresetChipSelector({
    super.key,
    required this.initialValue,
    required this.presets,
    this.presetLabels,
    this.otherHint = 'Add your own…',
    this.emptyError = 'Type a value first.',
    this.duplicateError =
        'That is already an option — tap it above instead.',
    required this.onChanged,
  });

  @override
  State<_PresetChipSelector> createState() => _PresetChipSelectorState();
}

class _PresetChipSelectorState extends State<_PresetChipSelector> {
  // Matches the rest of the seller UI's selected chips (burnished clay fill).
  static const Color _color = AppConstants.primary;
  static const Color _onColor = AppConstants.surfaceLight;

  String _presetLabel(String value) => widget.presetLabels?[value] ?? value;

  late String _selected = widget.initialValue;
  // Fallback preset when a custom value is removed. Empty presets (e.g. a
  // size row with no sizes) make this empty — removing the custom simply
  // leaves nothing selected.
  late String _preset = widget.presets.isEmpty
      ? ''
      : (widget.presets.contains(widget.initialValue)
          ? widget.initialValue
          : widget.presets.first);
  late String? _custom =
      widget.initialValue.isEmpty || widget.presets.contains(widget.initialValue)
          ? null
          : widget.initialValue;

  bool _otherOpen = false;
  String? _otherError;
  final TextEditingController _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _selectPreset(String value) {
    setState(() {
      _selected = value;
      _preset = value;
      _custom = null;
      _otherOpen = false;
      _otherError = null;
    });
    _ctrl.clear();
    widget.onChanged(value);
  }

  void _toggleOther() {
    setState(() {
      _otherOpen = !_otherOpen;
      _otherError = null;
      if (_otherOpen) _ctrl.text = _custom ?? '';
    });
  }

  void _submitCustom() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) {
      setState(() => _otherError = widget.emptyError);
      return;
    }
    if (text.length > _maxCustomTagLength) {
      setState(() => _otherError =
          'Keep it under $_maxCustomTagLength characters.');
      return;
    }
    final lower = text.toLowerCase();
    if (widget.presets.any((p) => p.toLowerCase() == lower)) {
      setState(() => _otherError = widget.duplicateError);
      return;
    }
    setState(() {
      _selected = text;
      _custom = text;
      _otherOpen = false;
      _otherError = null;
    });
    _ctrl.clear();
    widget.onChanged(text);
  }

  void _removeCustom() {
    // Removing an active custom value reverts to the last selected preset
    // (e.g. category custom → 'Casual'), keeping a valid selection active.
    setState(() {
      _selected = _preset;
      _custom = null;
      _otherOpen = false;
      _otherError = null;
    });
    _ctrl.clear();
    widget.onChanged(_preset);
  }

  @override
  Widget build(BuildContext context) {
    // The custom chip below is only constructed when a custom value exists:
    // eager evaluation of a `!` on a `late` field would crash the build
    // whenever no custom value is active (the default state).
    final custom = _custom;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final value in widget.presets)
              _TagChip(
                label: _presetLabel(value),
                color: _color,
                onColor: _onColor,
                selected: _selected == value,
                onTap: () => _selectPreset(value),
              ),
            _OtherTagChip(
              color: _color,
              open: _otherOpen,
              onTap: _toggleOther,
            ),
          ],
        ),
        // Active custom value chip — animates in/out on add/remove.
        _CustomChipSwitcher(
          keyValue: custom?.toLowerCase(),
          child: custom == null
              ? const SizedBox.shrink()
              : _CustomTagChip(
                  label: custom,
                  color: _color,
                  onColor: _onColor,
                  onRemove: _removeCustom,
                ),
        ),
        if (_otherOpen) ...[const SizedBox(height: 10), _buildOtherInput()],
      ],
    );
  }

  Widget _buildOtherInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                autofocus: true,
                maxLength: _maxCustomTagLength,
                style: AppConstants.bodyStyle(fontSize: 14),
                decoration: InputDecoration(
                  counterText: '',
                  isDense: true,
                  hintText: widget.otherHint,
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: AppConstants.buttonRadius,
                    borderSide:
                        const BorderSide(color: AppConstants.borderGray),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: AppConstants.buttonRadius,
                    borderSide:
                        const BorderSide(color: AppConstants.borderGray),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: AppConstants.buttonRadius,
                    borderSide: BorderSide(color: _color, width: 1.5),
                  ),
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submitCustom(),
              ),
            ),
            const SizedBox(width: 8),
            _AddCustomButton(
              color: _color,
              onColor: _onColor,
              onPressed: _submitCustom,
            ),
          ],
        ),
        if (_otherError != null) ...[const SizedBox(height: 6), _buildError()],
      ],
    );
  }

  Widget _buildError() {
    return Text(
      _otherError!,
      style: AppConstants.bodyStyle(fontSize: 12, color: AppConstants.error),
    );
  }
}

/// Multi-select size chip row for the variant sheet.
///
/// Checkbox-style: any number of preset sizes can be selected at once (each
/// becomes its own variant on save), and the dashed "+ Other" chip adds
/// custom size entries that stay in the selection. Reuses the same chip
/// widgets and animations as the tag selector.
class _SizeMultiSelector extends StatefulWidget {
  final List<String> initialSelected;
  final List<String> presets;
  final String otherHint;
  final String emptyError;
  final String duplicateError;
  final ValueChanged<List<String>> onChanged;

  const _SizeMultiSelector({
    super.key,
    required this.initialSelected,
    required this.presets,
    this.otherHint = 'Add your own…',
    this.emptyError = 'Type a value first.',
    this.duplicateError =
        'That is already an option — tap it above instead.',
    required this.onChanged,
  });

  @override
  State<_SizeMultiSelector> createState() => _SizeMultiSelectorState();
}

class _SizeMultiSelectorState extends State<_SizeMultiSelector> {
  // Matches the rest of the seller UI's selected chips (burnished clay fill).
  static const Color _color = AppConstants.primary;
  static const Color _onColor = AppConstants.surfaceLight;

  late final List<String> _selected = List.of(widget.initialSelected);

  bool _otherOpen = false;
  String? _otherError;
  final TextEditingController _ctrl = TextEditingController();

  // Custom entries = selected values that aren't presets (typed via
  // "+ Other", or a saved custom size that isn't in the preset list).
  List<String> get _customs =>
      _selected.where((s) => !widget.presets.contains(s)).toList();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle(String value) {
    setState(() {
      if (_selected.contains(value)) {
        _selected.remove(value);
      } else {
        _selected.add(value);
      }
    });
    widget.onChanged(List.unmodifiable(_selected));
  }

  void _toggleOther() {
    setState(() {
      _otherOpen = !_otherOpen;
      _otherError = null;
    });
  }

  void _submitCustom() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) {
      setState(() => _otherError = widget.emptyError);
      return;
    }
    if (text.length > _maxCustomTagLength) {
      setState(() => _otherError =
          'Keep it under $_maxCustomTagLength characters.');
      return;
    }
    final lower = text.toLowerCase();
    final exists = _selected.any((s) => s.toLowerCase() == lower) ||
        widget.presets.any((p) => p.toLowerCase() == lower);
    if (exists) {
      setState(() => _otherError = widget.duplicateError);
      return;
    }
    setState(() {
      _selected.add(text);
      _otherError = null;
      // Keep the input open and cleared so more custom sizes can be added.
      _ctrl.clear();
    });
    widget.onChanged(List.unmodifiable(_selected));
  }

  void _removeCustom(String value) {
    setState(() => _selected.remove(value));
    widget.onChanged(List.unmodifiable(_selected));
  }

  @override
  Widget build(BuildContext context) {
    final customs = _customs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final size in widget.presets)
              _TagChip(
                label: size,
                color: _color,
                onColor: _onColor,
                selected: _selected.contains(size),
                onTap: () => _toggle(size),
              ),
            _OtherTagChip(
              color: _color,
              open: _otherOpen,
              onTap: _toggleOther,
            ),
          ],
        ),
        // Custom size chips animate in/out on add/remove (user interaction
        // only — the initial edit-mode pre-fill renders statically).
        _CustomChipSwitcher(
          keyValue: customs.isEmpty
              ? null
              : customs.map((s) => s.toLowerCase()).join('\u0001'),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final size in customs)
                _CustomTagChip(
                  label: size,
                  color: _color,
                  onColor: _onColor,
                  onRemove: () => _removeCustom(size),
                ),
            ],
          ),
        ),
        if (_otherOpen) ...[const SizedBox(height: 10), _buildOtherInput()],
      ],
    );
  }

  Widget _buildOtherInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                autofocus: true,
                maxLength: _maxCustomTagLength,
                style: AppConstants.bodyStyle(fontSize: 14),
                decoration: InputDecoration(
                  counterText: '',
                  isDense: true,
                  hintText: widget.otherHint,
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: AppConstants.buttonRadius,
                    borderSide:
                        const BorderSide(color: AppConstants.borderGray),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: AppConstants.buttonRadius,
                    borderSide:
                        const BorderSide(color: AppConstants.borderGray),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: AppConstants.buttonRadius,
                    borderSide: BorderSide(color: _color, width: 1.5),
                  ),
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submitCustom(),
              ),
            ),
            const SizedBox(width: 8),
            _AddCustomButton(
              color: _color,
              onColor: _onColor,
              onPressed: _submitCustom,
            ),
          ],
        ),
        if (_otherError != null) ...[const SizedBox(height: 6), _buildError()],
      ],
    );
  }

  Widget _buildError() {
    return Text(
      _otherError!,
      style: AppConstants.bodyStyle(fontSize: 12, color: AppConstants.error),
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
