import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../constants/app_constants.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/report_modal.dart';
import '../customer/my_reports_screen.dart';
import 'faq_screen.dart';
import 'support_chat_screen.dart';

/// Help & Support menu with 3 options: FAQ, Report a Problem, Contact Support.
/// Used by both customers and sellers.
class HelpMenuScreen extends StatelessWidget {
  const HelpMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final reporterRole = auth.userRole == AppConstants.roleSeller ? 'seller' : 'customer';

    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      appBar: AppBar(
        backgroundColor: AppConstants.secondary,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFFF5EDE4), size: 24),
        title: Text(
          'Help & Support',
          style: AppConstants.bodyStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: const Color(0xFFF5EDE4),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.headset_mic_outlined,
                  size: 48,
                  color: AppConstants.primary,
                ),
                const SizedBox(height: 12),
                Text(
                  'How can we help?',
                  style: AppConstants.bodyStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppConstants.secondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Choose an option below to get support.',
                  style: AppConstants.bodyStyle(
                    fontSize: 13,
                    color: AppConstants.secondary.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // FAQ
          _HelpOption(
            icon: Icons.help_outline,
            iconColor: const Color(0xFF5C6BC0),
            title: 'FAQ',
            subtitle: 'Frequently asked questions',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const FAQScreen()),
              );
            },
          ),
          const SizedBox(height: 8),

          // Report a Problem
          _HelpOption(
            icon: Icons.flag_outlined,
            iconColor: AppConstants.error,
            title: 'Report a Problem',
            subtitle: 'Report a bug, payment issue, or general complaint',
            onTap: () {
              showReportModal(
                context,
                reportType: 'other',
                reporterRole: reporterRole,
                title: 'Report a Problem',
              ).then((submitted) {
                if (submitted == true && context.mounted) {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const MyReportsScreen()),
                  );
                }
              });
            },
          ),
          const SizedBox(height: 8),

          // Contact Support
          _HelpOption(
            icon: Icons.chat_bubble_outline,
            iconColor: AppConstants.success,
            title: 'Contact Support',
            subtitle: 'Chat with our support team',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SupportChatScreen()),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _HelpOption extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _HelpOption({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 22, color: iconColor),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppConstants.bodyStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppConstants.secondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: AppConstants.bodyStyle(
                        fontSize: 12,
                        color: AppConstants.secondary.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: AppConstants.secondary.withValues(alpha: 0.3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
