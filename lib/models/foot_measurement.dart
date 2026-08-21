/// Data model for an AR foot sizing scan result.
///
/// Each scan captures left and right foot dimensions in millimeters,
/// derives recommended shoe sizes, and stores metadata about the
/// scan conditions for confidence tracking.
class FootMeasurement {
  final int? id;
  final String userId;

  // Raw measurements (millimeters)
  final double? footLengthLeftMm;
  final double? footWidthLeftMm;
  final double? footLengthRightMm;
  final double? footWidthRightMm;

  // Compensated measurements (post sock-thickness adjustment, used for sizing)
  final double? footLengthLeftCompensatedMm;
  final double? footWidthLeftCompensatedMm;
  final double? footLengthRightCompensatedMm;
  final double? footWidthRightCompensatedMm;

  // Recommended sizes (derived from the larger foot)
  final String? recommendedEuSize;
  final String? recommendedUsSize;
  final String? recommendedUkSize;

  // Sizing metadata
  final String? sizingFootSide;          // 'left' | 'right' — which foot determined the size
  final String? recommendedWidthCategory; // 'narrow' | 'standard' | 'wide'
  final String measurementSource;         // 'ar_guided_tap' | 'ar_auto_scan' | 'paper'
  final String algorithmVersion;          // bump manually when sizing formulas change
  final String? sizeRecommendationReason;  // human-readable sizing rationale

  // Scan metadata
  final String paperSizeUsed; // 'ar' (live ARCore), 'a4', or 'letter'
  final String? footCondition; // 'bare' or 'socks'

  // Shopping preference
  final String? shoeCategory; // 'men' | 'women' | 'kids'

  // User-adjusted size (nullable — null means user accepted the recommendation)
  final String? userAdjustedEuSize;

  // Confidence signals (0.0–1.0)
  final double? paperDetectionConfidence;
  final double? lightingQuality;

  // Live AR confidence
  // Stores the numeric spread (IQR), not just High/Med/Low label,
  // so thresholds can be tuned later without a migration.
  final double? lengthConfidenceLeft;   // IQR of left foot length samples
  final double? lengthConfidenceRight;  // IQR of right foot length samples
  final double? overallConfidenceScore; // 0.0–1.0 aggregate confidence
  final String? confidenceLevel;        // 'high', 'medium', 'low'
  final int? rawSampleCount;            // Total samples collected
  final int? finalSampleCount;          // Samples after filtering

  // Timestamps
  final DateTime scanDate;
  final DateTime? createdAt;

  const FootMeasurement({
    this.id,
    required this.userId,
    this.footLengthLeftMm,
    this.footWidthLeftMm,
    this.footLengthRightMm,
    this.footWidthRightMm,
    this.footLengthLeftCompensatedMm,
    this.footWidthLeftCompensatedMm,
    this.footLengthRightCompensatedMm,
    this.footWidthRightCompensatedMm,
    this.recommendedEuSize,
    this.recommendedUsSize,
    this.recommendedUkSize,
    this.sizingFootSide,
    this.recommendedWidthCategory,
    this.measurementSource = 'paper',
    this.algorithmVersion = 'v2',
    this.sizeRecommendationReason,
    required this.paperSizeUsed,
    this.footCondition,
    this.shoeCategory,
    this.userAdjustedEuSize,
    this.paperDetectionConfidence,
    this.lightingQuality,
    this.lengthConfidenceLeft,
    this.lengthConfidenceRight,
    this.overallConfidenceScore,
    this.confidenceLevel,
    this.rawSampleCount,
    this.finalSampleCount,
    required this.scanDate,
    this.createdAt,
  });

  /// Parse from a Supabase row.
  factory FootMeasurement.fromMap(Map<String, dynamic> map) {
    return FootMeasurement(
      id: map['id'] as int?,
      userId: map['user_id']?.toString() ?? '',
      footLengthLeftMm: (map['foot_length_left_mm'] as num?)?.toDouble(),
      footWidthLeftMm: (map['foot_width_left_mm'] as num?)?.toDouble(),
      footLengthRightMm: (map['foot_length_right_mm'] as num?)?.toDouble(),
      footWidthRightMm: (map['foot_width_right_mm'] as num?)?.toDouble(),
      footLengthLeftCompensatedMm: (map['foot_length_left_compensated_mm'] as num?)?.toDouble(),
      footWidthLeftCompensatedMm: (map['foot_width_left_compensated_mm'] as num?)?.toDouble(),
      footLengthRightCompensatedMm: (map['foot_length_right_compensated_mm'] as num?)?.toDouble(),
      footWidthRightCompensatedMm: (map['foot_width_right_compensated_mm'] as num?)?.toDouble(),
      recommendedEuSize: map['recommended_eu_size']?.toString(),
      recommendedUsSize: map['recommended_us_size']?.toString(),
      recommendedUkSize: map['recommended_uk_size']?.toString(),
      sizingFootSide: map['sizing_foot_side']?.toString(),
      recommendedWidthCategory: map['recommended_width_category']?.toString(),
      measurementSource: map['measurement_source']?.toString() ?? 'paper',
      algorithmVersion: map['algorithm_version']?.toString() ?? 'v2',
      sizeRecommendationReason: map['size_recommendation_reason']?.toString(),
      paperSizeUsed: map['paper_size_used']?.toString() ?? 'a4',
      footCondition: map['foot_condition']?.toString(),
      shoeCategory: map['shoe_category']?.toString(),
      userAdjustedEuSize: map['user_adjusted_eu_size']?.toString(),
      paperDetectionConfidence: (map['paper_detection_confidence'] as num?)?.toDouble(),
      lightingQuality: (map['lighting_quality'] as num?)?.toDouble(),
      lengthConfidenceLeft: (map['length_confidence_left'] as num?)?.toDouble(),
      lengthConfidenceRight: (map['length_confidence_right'] as num?)?.toDouble(),
      overallConfidenceScore: (map['overall_confidence_score'] as num?)?.toDouble(),
      confidenceLevel: map['confidence_level']?.toString(),
      rawSampleCount: map['raw_sample_count'] as int?,
      finalSampleCount: map['final_sample_count'] as int?,
      scanDate: DateTime.tryParse(map['scan_date']?.toString() ?? '') ?? DateTime.now(),
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? ''),
    );
  }

  /// Convert to a map for Supabase insert/update.
  Map<String, dynamic> toInsertMap() {
    return {
      'user_id': userId,
      'foot_length_left_mm': footLengthLeftMm,
      'foot_width_left_mm': footWidthLeftMm,
      'foot_length_right_mm': footLengthRightMm,
      'foot_width_right_mm': footWidthRightMm,
      'foot_length_left_compensated_mm': footLengthLeftCompensatedMm,
      'foot_width_left_compensated_mm': footWidthLeftCompensatedMm,
      'foot_length_right_compensated_mm': footLengthRightCompensatedMm,
      'foot_width_right_compensated_mm': footWidthRightCompensatedMm,
      'recommended_eu_size': recommendedEuSize,
      'recommended_us_size': recommendedUsSize,
      'recommended_uk_size': recommendedUkSize,
      'sizing_foot_side': sizingFootSide,
      'recommended_width_category': recommendedWidthCategory,
      'measurement_source': measurementSource,
      'algorithm_version': algorithmVersion,
      'size_recommendation_reason': sizeRecommendationReason,
      'paper_size_used': paperSizeUsed,
      'foot_condition': footCondition,
      'shoe_category': shoeCategory,
      'user_adjusted_eu_size': userAdjustedEuSize,
      'paper_detection_confidence': paperDetectionConfidence,
      'lighting_quality': lightingQuality,
      'length_confidence_left': lengthConfidenceLeft,
      'length_confidence_right': lengthConfidenceRight,
      'overall_confidence_score': overallConfidenceScore,
      'confidence_level': confidenceLevel,
      'raw_sample_count': rawSampleCount,
      'final_sample_count': finalSampleCount,
      'scan_date': scanDate.toIso8601String(),
    };
  }

  /// The effective EU size — user-adjusted if set, otherwise the recommended size.
  String? get effectiveEuSize => userAdjustedEuSize ?? recommendedEuSize;

  /// The effective US size based on the effective EU size.
  String? get effectiveUsSize {
    if (userAdjustedEuSize != null) {
      return FootMeasurement.euToUs(userAdjustedEuSize!, category: shoeCategory);
    }
    return recommendedUsSize;
  }

  /// The effective UK size based on the effective EU size.
  String? get effectiveUkSize {
    if (userAdjustedEuSize != null) {
      return FootMeasurement.euToUk(userAdjustedEuSize!);
    }
    return recommendedUkSize;
  }

  /// The sizing foot's length in mm, using the explicit sizingFootSide if set.
  /// Falls back to the larger foot if sizingFootSide is not set (backwards compat).
  double? get maxFootLength {
    // If sizingFootSide is explicitly set, use the correct foot
    if (sizingFootSide == 'left') return footLengthLeftCompensatedMm ?? footLengthLeftMm;
    if (sizingFootSide == 'right') return footLengthRightCompensatedMm ?? footLengthRightMm;

    // Fallback: larger foot (backwards compat for pre-v2 scans)
    final left = footLengthLeftMm;
    final right = footLengthRightMm;
    if (left == null && right == null) return null;
    if (left == null) return right;
    if (right == null) return left;
    return left > right ? left : right;
  }

  /// The sizing foot's width in mm, using the explicit sizingFootSide.
  /// Never pairs one foot's length with the other foot's width.
  double? get sizingFootWidth {
    if (sizingFootSide == 'left') return footWidthLeftCompensatedMm ?? footWidthLeftMm;
    if (sizingFootSide == 'right') return footWidthRightCompensatedMm ?? footWidthRightMm;
    // Fallback: use the same foot as maxFootLength
    final lengthLeft = footLengthLeftMm;
    final lengthRight = footLengthRightMm;
    if (lengthLeft == null && lengthRight == null) return null;
    final useLeft = (lengthRight == null) || (lengthLeft != null && lengthLeft > lengthRight);
    return useLeft ? footWidthLeftMm : footWidthRightMm;
  }

  /// Determine which foot is the sizing foot (longer foot wins).
  /// Returns 'left' or 'right', or null if both are null.
  String? get determineSizingFootSide {
    final left = footLengthLeftMm;
    final right = footLengthRightMm;
    if (left == null && right == null) return null;
    if (left == null) return 'right';
    if (right == null) return 'left';
    return left >= right ? 'left' : 'right';
  }

  /// Create a copy with optional field overrides.
  FootMeasurement copyWith({
    int? id,
    String? userId,
    double? footLengthLeftMm,
    double? footWidthLeftMm,
    double? footLengthRightMm,
    double? footWidthRightMm,
    double? footLengthLeftCompensatedMm,
    double? footWidthLeftCompensatedMm,
    double? footLengthRightCompensatedMm,
    double? footWidthRightCompensatedMm,
    String? recommendedEuSize,
    String? recommendedUsSize,
    String? recommendedUkSize,
    String? sizingFootSide,
    String? recommendedWidthCategory,
    String? measurementSource,
    String? algorithmVersion,
    String? sizeRecommendationReason,
    String? paperSizeUsed,
    String? footCondition,
    String? shoeCategory,
    String? userAdjustedEuSize,
    double? paperDetectionConfidence,
    double? lightingQuality,
    double? lengthConfidenceLeft,
    double? lengthConfidenceRight,
    double? overallConfidenceScore,
    String? confidenceLevel,
    int? rawSampleCount,
    int? finalSampleCount,
    DateTime? scanDate,
    DateTime? createdAt,
  }) {
    return FootMeasurement(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      footLengthLeftMm: footLengthLeftMm ?? this.footLengthLeftMm,
      footWidthLeftMm: footWidthLeftMm ?? this.footWidthLeftMm,
      footLengthRightMm: footLengthRightMm ?? this.footLengthRightMm,
      footWidthRightMm: footWidthRightMm ?? this.footWidthRightMm,
      footLengthLeftCompensatedMm: footLengthLeftCompensatedMm ?? this.footLengthLeftCompensatedMm,
      footWidthLeftCompensatedMm: footWidthLeftCompensatedMm ?? this.footWidthLeftCompensatedMm,
      footLengthRightCompensatedMm: footLengthRightCompensatedMm ?? this.footLengthRightCompensatedMm,
      footWidthRightCompensatedMm: footWidthRightCompensatedMm ?? this.footWidthRightCompensatedMm,
      recommendedEuSize: recommendedEuSize ?? this.recommendedEuSize,
      recommendedUsSize: recommendedUsSize ?? this.recommendedUsSize,
      recommendedUkSize: recommendedUkSize ?? this.recommendedUkSize,
      sizingFootSide: sizingFootSide ?? this.sizingFootSide,
      recommendedWidthCategory: recommendedWidthCategory ?? this.recommendedWidthCategory,
      measurementSource: measurementSource ?? this.measurementSource,
      algorithmVersion: algorithmVersion ?? this.algorithmVersion,
      sizeRecommendationReason: sizeRecommendationReason ?? this.sizeRecommendationReason,
      paperSizeUsed: paperSizeUsed ?? this.paperSizeUsed,
      footCondition: footCondition ?? this.footCondition,
      shoeCategory: shoeCategory ?? this.shoeCategory,
      userAdjustedEuSize: userAdjustedEuSize ?? this.userAdjustedEuSize,
      paperDetectionConfidence: paperDetectionConfidence ?? this.paperDetectionConfidence,
      lightingQuality: lightingQuality ?? this.lightingQuality,
      lengthConfidenceLeft: lengthConfidenceLeft ?? this.lengthConfidenceLeft,
      lengthConfidenceRight: lengthConfidenceRight ?? this.lengthConfidenceRight,
      overallConfidenceScore: overallConfidenceScore ?? this.overallConfidenceScore,
      confidenceLevel: confidenceLevel ?? this.confidenceLevel,
      rawSampleCount: rawSampleCount ?? this.rawSampleCount,
      finalSampleCount: finalSampleCount ?? this.finalSampleCount,
      scanDate: scanDate ?? this.scanDate,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // STATIC CONVERSION UTILITIES
  // ═══════════════════════════════════════════════════════════════

  /// EU shoe size to US conversion with category-specific offset.
  ///
  /// Offsets sourced from standard conversion charts:
  /// - Men: EU - 33
  /// - Women: EU - 31.5  (women's US runs ~1.5 sizes higher than men's for same EU)
  /// - Kids: EU - 33 (same as men's for kids' sizes that overlap the EU chart)
  ///
  /// TODO(human-review): Verify these offset values against an authoritative
  /// conversion chart before shipping. The women's offset is approximate and
  /// may need tuning per size range.
  static String euToUs(String euSize, {String? category}) {
    final eu = double.tryParse(euSize);
    if (eu == null) return '';
    double offset;
    switch (category) {
      case 'women':
        offset = 31.5;
        break;
      case 'kids':
        offset = 33.0; // Same as men's for kids' sizes
        break;
      case 'men':
      default:
        offset = 33.0;
        break;
    }
    final us = (eu - offset).round();
    return '$us';
  }

  /// EU shoe size to UK conversion.
  ///
  /// Standard approximation: UK ≈ EU - 33.5 (slightly offset from US).
  static String euToUk(String euSize) {
    final eu = double.tryParse(euSize);
    if (eu == null) return '';
    final uk = (eu - 33.5).round();
    return '$uk';
  }

  /// Format a mm measurement for display (e.g., 265.0 → "265 mm").
  static String formatMm(double? mm) {
    if (mm == null) return '—';
    return '${mm.round()} mm';
  }

  /// Format a mm measurement in cm (e.g., 265.0 → "26.5 cm").
  static String formatCm(double? mm) {
    if (mm == null) return '—';
    return '${(mm / 10).toStringAsFixed(1)} cm';
  }
}
