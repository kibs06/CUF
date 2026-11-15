import 'package:flutter/material.dart';

import '../../constants/app_constants.dart';
import '../../utils/seller_verification.dart';
import '../sole_badge.dart';

/// The badge row under the seller profile's name: the account role, plus the
/// Verified Seller badge once the admin-approved business docs carry the
/// public trust flag.
///
/// Its own widget because the badge's visibility is a rule, not decoration:
/// [showsVerifiedSellerBadge] decides it, and a widget test can pump every
/// role/status pair without standing up the whole profile screen.
class SellerHeaderBadges extends StatelessWidget {
  final String role;
  final String roleLabel;
  final Color roleColor;
  final String businessStatus;

  const SellerHeaderBadges({
    super.key,
    required this.role,
    required this.roleLabel,
    required this.roleColor,
    required this.businessStatus,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        SoleBadge(
          label: roleLabel,
          backgroundColor: roleColor.withValues(alpha: 0.14),
          textColor: roleColor,
        ),
        // Tier 2 business verification, once an admin has approved the
        // seller's documents. The same badge is shown to customers on the
        // store's public page (StoreProfileScreen).
        if (showsVerifiedSellerBadge(role: role, businessStatus: businessStatus))
          SoleBadge(
            label: 'Verified Seller',
            icon: Icons.verified_rounded,
            backgroundColor: AppConstants.success.withValues(alpha: 0.15),
            textColor: AppConstants.success,
          ),
      ],
    );
  }
}
