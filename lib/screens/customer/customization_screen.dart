import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../constants/app_constants.dart';
import '../../providers/auth_provider.dart';
import '../../providers/order_provider.dart';
import '../../widgets/sole_card.dart';
import '../../widgets/sole_primary_button.dart';

class CustomizationScreen extends StatefulWidget {
  const CustomizationScreen({super.key});

  @override
  State<CustomizationScreen> createState() => _CustomizationScreenState();
}

class _CustomizationScreenState extends State<CustomizationScreen> {
  int _currentStep = 0;
  
  // Customization selection state
  int _selectedBaseIndex = 0;
  int _selectedColorIndex = 0;
  int _selectedMaterialIndex = 0;
  final TextEditingController _specialRequestController = TextEditingController();

  // Customization Options Data
  final List<Map<String, String>> _baseDesigns = [
    {
      'name': 'Carcar Classic Oxford',
      'image': 'https://images.unsplash.com/photo-1533867617858-e7b97e060509?q=80&w=200&auto=format&fit=crop',
      'desc': 'Formal, structural oxford styling.'
    },
    {
      'name': 'Suede Artisan Loafer',
      'image': 'https://images.unsplash.com/photo-1549298916-b41d501d3772?q=80&w=200&auto=format&fit=crop',
      'desc': 'Slip-on luxury leisure footwear.'
    },
    {
      'name': 'Kabanhawan Boot',
      'image': 'https://images.unsplash.com/photo-1520639888713-7851133b1ed0?q=80&w=200&auto=format&fit=crop',
      'desc': 'High top rugged artisan boots.'
    }
  ];

  final List<Map<String, dynamic>> _colors = [
    {'name': 'Burnished Clay', 'color': AppConstants.primary},
    {'name': 'Carob Dark', 'color': AppConstants.secondary},
    {'name': 'Celadon Teal', 'color': AppConstants.accent},
    {'name': 'Olive Stitch', 'color': AppConstants.success},
    {'name': 'Crimson Welt', 'color': AppConstants.error},
    {'name': 'Tuscan Gold', 'color': const Color(0xFFC49A45)},
  ];

  final List<Map<String, String>> _materials = [
    {
      'name': 'Full-Grain Calfskin Leather',
      'desc': 'Premium hand-finished leather with a natural grain that patinas beautifully over time.',
      'texture': 'Smooth & Rich'
    },
    {
      'name': 'Premium Roughout Suede',
      'desc': 'Thick suede leather from Cebuano tanneries, offering a rugged yet soft suede exterior.',
      'texture': 'Fuzzy & Matte'
    },
    {
      'name': 'Organic Cebuano Canvas',
      'desc': 'Highly breathable canvas weave, double stitched with reinforced leather binding.',
      'texture': 'Flexible & Light'
    }
  ];

  @override
  void dispose() {
    _specialRequestController.dispose();
    super.dispose();
  }

  void _submitCustomization() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final orderProvider = Provider.of<OrderProvider>(context, listen: false);

    final success = await orderProvider.submitCustomization(
      customerId: auth.profile?['id'] ?? 'cust-1',
      baseName: _baseDesigns[_selectedBaseIndex]['name']!,
      color: _colors[_selectedColorIndex]['name'] as String,
      material: _materials[_selectedMaterialIndex]['name']!,
      specialRequest: _specialRequestController.text.trim(),
    );

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Custom shoe craft order submitted! We will contact you.'),
          backgroundColor: AppConstants.success,
        ),
      );
      Navigator.of(context).pop();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Submission failed. Please try again.'),
          backgroundColor: AppConstants.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      appBar: AppBar(
        title: Text(
          'Custom Craft Studio',
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
          Theme(
            // Custom styles for stepper theme
            data: Theme.of(context).copyWith(
              colorScheme: Theme.of(context).colorScheme.copyWith(
                    primary: AppConstants.primary,
                    secondary: AppConstants.secondary,
                  ),
            ),
            child: Stepper(
              type: StepperType.vertical,
              currentStep: _currentStep,
              onStepTapped: (step) => setState(() => _currentStep = step),
              onStepContinue: () {
                if (_currentStep < 4) {
                  setState(() => _currentStep += 1);
                } else {
                  _submitCustomization();
                }
              },
              onStepCancel: () {
                if (_currentStep > 0) {
                  setState(() => _currentStep -= 1);
                }
              },
              controlsBuilder: (context, controls) {
                final isLast = _currentStep == 4;
                return Padding(
                  padding: const EdgeInsets.only(top: 24.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: SolePrimaryButton(
                          label: isLast ? 'Submit Design' : 'Continue',
                          onPressed: controls.onStepContinue,
                        ),
                      ),
                      if (_currentStep > 0) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: controls.onStepCancel,
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: AppConstants.primary),
                              shape: RoundedRectangleBorder(borderRadius: AppConstants.buttonRadius),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: Text(
                              'Back',
                              style: AppConstants.bodyStyle(
                                color: AppConstants.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
              steps: [
                // Step 1: Base Design
                Step(
                  isActive: _currentStep >= 0,
                  state: _currentStep > 0 ? StepState.complete : StepState.editing,
                  title: Text('Base Shoe Design', style: AppConstants.headlineStyle(fontSize: 16)),
                  content: SoleCard(
                    color: Colors.white,
                    child: RadioGroup<int>(
                      groupValue: _selectedBaseIndex,
                      onChanged: (val) {
                        if (val == null) return;
                        setState(() => _selectedBaseIndex = val);
                      },
                      child: Column(
                        children: List.generate(_baseDesigns.length, (index) {
                          final item = _baseDesigns[index];
                          final isSelected = _selectedBaseIndex == index;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: isSelected ? AppConstants.primary : AppConstants.borderGray.withValues(alpha: 0.4),
                                width: isSelected ? 2 : 1,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: RadioListTile(
                              activeColor: AppConstants.primary,
                              value: index,
                              title: Text(item['name']!, style: AppConstants.bodyStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text(item['desc']!, style: AppConstants.bodyStyle(fontSize: 12, color: Colors.black54)),
                              secondary: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(item['image']!, width: 50, height: 50, fit: BoxFit.cover),
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                  ),
                ),

                // Step 2: Color selection
                Step(
                  isActive: _currentStep >= 1,
                  state: _currentStep > 1 ? StepState.complete : (_currentStep == 1 ? StepState.editing : StepState.indexed),
                  title: Text('Color & Dye Scheme', style: AppConstants.headlineStyle(fontSize: 16)),
                  content: SoleCard(
                    color: Colors.white,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Tap color palette to apply',
                          style: AppConstants.bodyStyle(fontSize: 13, color: AppConstants.secondary.withValues(alpha: 0.6)),
                        ),
                        const SizedBox(height: 12),
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                            childAspectRatio: 1.1,
                          ),
                          itemCount: _colors.length,
                          itemBuilder: (context, index) {
                            final item = _colors[index];
                            final colorVal = item['color'] as Color;
                            final isSelected = _selectedColorIndex == index;

                            return GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedColorIndex = index;
                                });
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  color: colorVal.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isSelected ? AppConstants.primary : AppConstants.borderGray.withValues(alpha: 0.4),
                                    width: isSelected ? 2 : 1,
                                  ),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    CircleAvatar(radius: 14, backgroundColor: colorVal),
                                    const SizedBox(height: 6),
                                    Text(
                                      item['name'] as String,
                                      textAlign: TextAlign.center,
                                      style: AppConstants.bodyStyle(fontSize: 10, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),

                // Step 3: Choose Material
                Step(
                  isActive: _currentStep >= 2,
                  state: _currentStep > 2 ? StepState.complete : (_currentStep == 2 ? StepState.editing : StepState.indexed),
                  title: Text('Upper Material', style: AppConstants.headlineStyle(fontSize: 16)),
                  content: SoleCard(
                    color: Colors.white,
                    child: Column(
                      children: List.generate(_materials.length, (index) {
                        final item = _materials[index];
                        final isSelected = _selectedMaterialIndex == index;

                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedMaterialIndex = index;
                            });
                          },
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: isSelected ? AppConstants.primary.withValues(alpha: 0.04) : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected ? AppConstants.primary : AppConstants.borderGray.withValues(alpha: 0.4),
                                width: isSelected ? 2 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item['name']!,
                                        style: AppConstants.bodyStyle(fontWeight: FontWeight.bold),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        item['desc']!,
                                        style: AppConstants.bodyStyle(fontSize: 12, color: Colors.black54),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppConstants.primary.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    item['texture']!,
                                    style: AppConstants.bodyStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppConstants.primary),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                ),

                // Step 4: Special Request
                Step(
                  isActive: _currentStep >= 3,
                  state: _currentStep > 3 ? StepState.complete : (_currentStep == 3 ? StepState.editing : StepState.indexed),
                  title: Text('Artisan Engraving & Sizing Notes', style: AppConstants.headlineStyle(fontSize: 16)),
                  content: SoleCard(
                    color: Colors.white,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Add any personal requests (e.g. customized sizing adjustments, initials engraved on heels, welt stitching preference).',
                          style: AppConstants.bodyStyle(fontSize: 12, color: Colors.black54),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _specialRequestController,
                          maxLines: 4,
                          style: AppConstants.bodyStyle(fontSize: 14),
                          decoration: InputDecoration(
                            hintText: 'e.g. Please engrave initials "J.D." on left heel side. Need extra wide fit on forefoot.',
                            hintStyle: AppConstants.bodyStyle(fontSize: 13, color: Colors.black38),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: AppConstants.borderGray),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Step 5: Review & Submit (Pre-selected summary card)
                Step(
                  isActive: _currentStep >= 4,
                  state: _currentStep == 4 ? StepState.editing : StepState.indexed,
                  title: Text('Review Selection', style: AppConstants.headlineStyle(fontSize: 16)),
                  content: SoleCard(
                    color: Colors.white,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Visual Preview Card (chips + base image)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppConstants.surfaceLight,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  _baseDesigns[_selectedBaseIndex]['image']!,
                                  width: 80,
                                  height: 80,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _baseDesigns[_selectedBaseIndex]['name']!,
                                      style: AppConstants.bodyStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        // Color chip preview
                                        Container(
                                          width: 14,
                                          height: 14,
                                          decoration: BoxDecoration(
                                            color: _colors[_selectedColorIndex]['color'] as Color,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          _colors[_selectedColorIndex]['name'] as String,
                                          style: AppConstants.bodyStyle(fontSize: 12),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Material: ${_materials[_selectedMaterialIndex]['name']}',
                                      style: AppConstants.bodyStyle(fontSize: 12, color: Colors.black54),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        
                        if (_specialRequestController.text.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Text('Special Note:', style: AppConstants.bodyStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.grey.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _specialRequestController.text,
                              style: AppConstants.bodyStyle(fontSize: 13, color: Colors.black87),
                            ),
                          ),
                        ],
                      ],
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
}
