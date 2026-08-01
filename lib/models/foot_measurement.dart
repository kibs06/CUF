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

  // Recommended sizes (derived from the larger foot)
  final String? recommendedEuSize;
  final String? recommendedUsSize;
  final String? recommendedUkSize;

  // Scan metadata
  final String paperSizeUsed; // 'ar' (live ARCore), 'a4', or 'letter'
  final String? footCondition; // 'bare' or 'socks'

  // User-adjusted size (nullable — null means user accepted the recommendation)
  final String? userAdjustedEuSize;

  // Confidence signals (0.0–1.0)
  final double? paperDetectionConfidence;
  final double? lightingQuality;

  // Live AR confidence (§7 of the implementation prompt)
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
    this.recommendedEuSize,
    this.recommendedUsSize,
    this.recommendedUkSize,
    required this.paperSizeUsed,
    this.footCondition,
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
      recommendedEuSize: map['recommended_eu_size']?.toString(),
      recommendedUsSize: map['recommended_us_size']?.toString(),
      recommendedUkSize: map['recommended_uk_size']?.toString(),
      paperSizeUsed: map['paper_size_used']?.toString() ?? 'a4',
      footCondition: map['foot_condition']?.toString(),
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
      'recommended_eu_size': recommendedEuSize,
      'recommended_us_size': recommendedUsSize,
      'recommended_uk_size': recommendedUkSize,
      'paper_size_used': paperSizeUsed,
      'foot_condition': footCondition,
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
      return FootMeasurement.euToUs(userAdjustedEuSize!);
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

  /// The larger foot's length in mm (used for size recommendation).
  double? get maxFootLength {
    final left = footLengthLeftMm;
    final right = footLengthRightMm;
    if (left == null && right == null) return null;
    if (left == null) return right;
    if (right == null) return left;
    return left > right ? left : right;
  }

  /// Create a copy with optional field overrides.
  FootMeasurement copyWith({
    int? id,
    String? userId,
    double? footLengthLeftMm,
    double? footWidthLeftMm,
    double? footLengthRightMm,
    double? footWidthRightMm,
    String? recommendedEuSize,
    String? recommendedUsSize,
    String? recommendedUkSize,
    String? paperSizeUsed,
    String? footCondition,
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
      recommendedEuSize: recommendedEuSize ?? this.recommendedEuSize,
      recommendedUsSize: recommendedUsSize ?? this.recommendedUsSize,
      recommendedUkSize: recommendedUkSize ?? this.recommendedUkSize,
      paperSizeUsed: paperSizeUsed ?? this.paperSizeUsed,
      footCondition: footCondition ?? this.footCondition,
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

  /// EU shoe size to US Men's conversion.
  ///
  /// Standard approximation: US Men ≈ EU - 33 (for adult sizes).
  /// For women's: add ~1.5 sizes.
  static String euToUs(String euSize) {
    final eu = double.tryParse(euSize);
    if (eu == null) return '';
    final usMen = (eu - 33).round();
    return '$usMen';
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
