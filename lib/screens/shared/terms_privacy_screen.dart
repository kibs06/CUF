import 'package:flutter/material.dart';
import '../../constants/app_constants.dart';
import '../../widgets/sole_card.dart';

/// Terms & Privacy screen with a draft return/refund policy.
///
/// ⚠️ DRAFT COPY — pending legal review before production.
/// All policy content below is a placeholder written for development
/// and testing purposes only. It must be reviewed and approved by
/// legal counsel before the app ships to production.
class TermsPrivacyScreen extends StatelessWidget {
  const TermsPrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      appBar: AppBar(
        title: Text(
          'Terms & Privacy',
          style: AppConstants.bodyStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppConstants.surfaceLight,
        elevation: 0,
      ),
      body: Stack(
        children: [
          AppConstants.noiseOverlay(opacity: 0.03),
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Draft notice
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppConstants.statusPendingColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppConstants.statusPendingColor.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 16,
                        color: AppConstants.statusPendingColor,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Draft policy — pending legal review. Not final.',
                          style: AppConstants.bodyStyle(
                            fontSize: 12,
                            color: AppConstants.statusPendingColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Section: Return Policy
                Text(
                  'Return & Refund Policy',
                  style: AppConstants.headlineStyle(fontSize: 20),
                ),
                const SizedBox(height: 16),
                SoleCard(
                  color: Colors.white,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _policySection(
                        'Return Window',
                        'You may return unworn, unused items within 7 days of delivery for a full refund.',
                      ),
                      const SizedBox(height: 16),
                      _policySection(
                        'Condition Requirements',
                        'Items must be in their original packaging with all tags attached. Worn, damaged, or altered items will not be accepted.',
                      ),
                      const SizedBox(height: 16),
                      _policySection(
                        'Refund Processing',
                        'Refunds are issued to the original payment method within 5–7 business days after we receive and inspect the returned item.',
                      ),
                      const SizedBox(height: 16),
                      _policySection(
                        'Return Shipping',
                        'Buyer covers return shipping costs unless the item arrives defective or incorrect. We recommend using a trackable shipping service.',
                      ),
                      const SizedBox(height: 16),
                      _policySection(
                        'Defective or Incorrect Items',
                        'If you received a defective or incorrect item, contact us within 48 hours of delivery. We will provide a prepaid return label and ship a replacement at no additional cost.',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Section: Privacy
                Text(
                  'Privacy Policy',
                  style: AppConstants.headlineStyle(fontSize: 20),
                ),
                const SizedBox(height: 16),
                SoleCard(
                  color: Colors.white,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _policySection(
                        'Information We Collect',
                        'We collect your name, email address, phone number, shipping address, and payment information when you place an order or create an account. Foot measurements collected via AR are stored securely to improve your sizing recommendations.',
                      ),
                      const SizedBox(height: 16),
                      _policySection(
                        'How We Use Your Information',
                        'Your information is used to process orders, communicate order status, send relevant product recommendations, and improve our services. We do not sell your personal information to third parties.',
                      ),
                      const SizedBox(height: 16),
                      _policySection(
                        'Data Security',
                        'We implement industry-standard security measures to protect your personal data, including encryption of payment information and secure data storage on Supabase infrastructure.',
                      ),
                      const SizedBox(height: 16),
                      _policySection(
                        'Contact',
                        'For questions about this policy, contact us at support@solevision.ph or through the Help & Support section in the app.',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // Last updated
                Center(
                  child: Text(
                    'Last updated: August 2026',
                    style: AppConstants.bodyStyle(
                      fontSize: 11,
                      color: AppConstants.secondary.withValues(alpha: 0.4),
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

  Widget _policySection(String title, String body) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppConstants.bodyStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: AppConstants.primary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          body,
          style: AppConstants.bodyStyle(
            fontSize: 13,
            color: AppConstants.secondary.withValues(alpha: 0.75),
            height: 1.45,
          ),
        ),
      ],
    );
  }
}