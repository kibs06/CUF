import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../utils/glb_validator.dart';
import '../utils/shoe_model_upload.dart';

/// The authoring-contract report, as one card.
///
/// **One card, two readers.** V2.2's seller uploads a file from the product
/// form; V2.10's request flow (P2) has an admin do it on a seller's behalf from
/// the queue, because this market's sellers cannot produce a contract-compliant
/// `.glb` themselves. Both runs are the same [validateGlb] library over the same
/// bytes, so both reports must read identically — a second copy of this widget
/// would be the place where \"within tolerance\" started meaning two things.
///
/// Two rules the layout keeps, carried over from the seller's original:
///
///  * **Failures are listed, passes are summarised.** Whoever is looking acts on
///    the two sentences that failed, and a wall of green buries them.
///  * **A green run says what it cannot prove.** [kShoeModelPassedLimitsNote]
///    ships inside the card, so \"passed the checks\" is never read as \"this is
///    the shoe\" (guide §5.2's reviewer rows are the part no byte-check covers).
///
/// [footer] is where a caller puts its own controls (the seller's publish
/// switch); the admin's sheet passes nothing, because its publish is the button
/// that opened this report.
class ShoeModelReportCard extends StatelessWidget {
  const ShoeModelReportCard({super.key, required this.asset, this.footer});

  /// The fetched file and the report [validateGlb] produced for it.
  final ShoeModelAsset asset;

  /// Extra controls rendered inside the card, under the report.
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final report = asset.report;
    final failures = shoeModelReportFailures(report);
    final warnings = shoeModelReportWarnings(report);
    final passed = report.passed && asset.bytes.isNotEmpty;
    final color = passed ? AppConstants.success : AppConstants.error;

    final measurements = <String>[
      '${(asset.fileSizeBytes / (1024 * 1024)).toStringAsFixed(2)} MB',
      if (asset.triangleCount != null) '${asset.triangleCount} triangles',
      if (asset.meshExternalLengthMm != null)
        'mesh ${asset.meshExternalLengthMm!.toStringAsFixed(1)} mm long',
    ].join(' \u00b7 ');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(passed ? Icons.verified_outlined : Icons.rule_folder_outlined,
                  size: 16, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  shoeModelReportHeadline(report),
                  style: AppConstants.bodyStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppConstants.secondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            measurements,
            style: AppConstants.bodyStyle(
              fontSize: 11,
              color: AppConstants.secondary.withValues(alpha: 0.6),
            ),
          ),
          if (asset.declaredExternalLengthMm != null &&
              asset.meshExternalLengthMm != null) ...[
            const SizedBox(height: 4),
            Text(
              'Declared ${asset.declaredExternalLengthMm!.toStringAsFixed(0)} mm '
              '\u00b7 mesh ${asset.meshExternalLengthMm!.toStringAsFixed(1)} mm '
              '\u2014 ${shoeModelLengthDeltaSentence(declaredMm: asset.declaredExternalLengthMm!, meshMm: asset.meshExternalLengthMm!)}'
              ' (tolerance \u00b1${kLengthToleranceMm.toStringAsFixed(0)} mm)',
              style: AppConstants.bodyStyle(
                fontSize: 11,
                color: AppConstants.secondary.withValues(alpha: 0.6),
              ),
            ),
          ],
          if (failures.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final failure in failures)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '\u2022 $failure',
                  style: AppConstants.bodyStyle(
                    fontSize: 11,
                    color: AppConstants.secondary,
                    height: 1.35,
                  ),
                ),
              ),
          ],
          if (warnings.isNotEmpty) ...[
            const SizedBox(height: 4),
            for (final warning in warnings)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '\u2022 to confirm: $warning',
                  style: AppConstants.bodyStyle(
                    fontSize: 11,
                    color: AppConstants.secondary.withValues(alpha: 0.7),
                    height: 1.35,
                  ),
                ),
              ),
          ],
          if (passed) ...[
            const SizedBox(height: 4),
            Text(
              kShoeModelPassedLimitsNote,
              style: AppConstants.bodyStyle(
                fontSize: 11,
                color: AppConstants.secondary.withValues(alpha: 0.55),
                height: 1.35,
              ),
            ),
          ],
          ?footer,
        ],
      ),
    );
  }
}
