import 'package:flutter/material.dart';

import '../../constants/app_constants.dart';
import '../../services/report_service.dart';
import '../customer/my_reports_screen.dart';

/// Contact Support screen — a simple form for users to send a message to the support team.
/// For v1, messages are stored as reports (type: 'other', category: 'general_feedback')
/// and the admin can respond via the notification system.
class SupportChatScreen extends StatefulWidget {
  const SupportChatScreen({super.key});

  @override
  State<SupportChatScreen> createState() => _SupportChatScreenState();
}

class _SupportChatScreenState extends State<SupportChatScreen> {
  final _subjectController = TextEditingController();
  final _messageController = TextEditingController();
  bool _isSubmitting = false;
  bool _submitted = false;

  @override
  void dispose() {
    _subjectController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final subject = _subjectController.text.trim();
    final message = _messageController.text.trim();
    if (subject.length < 3 || message.length < 10 || _isSubmitting) return;
    if (subject.isEmpty || message.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill in all fields.'),
          backgroundColor: AppConstants.error,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      // Submit as an 'other' type report with 'other' category
      // The custom_details field captures the full message (category must be 'other' for custom_details to be stored)
      await ReportService.instance.submitReport(
        reporterRole: 'customer',
        type: 'other',
        category: 'other',
        customDetails: 'Subject: $subject\n\n$message',
      );

      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _submitted = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send message: ${e.toString().replaceAll('Exception: ', '')}'),
            backgroundColor: AppConstants.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      appBar: AppBar(
        backgroundColor: AppConstants.secondary,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFFF5EDE4), size: 24),
        title: Text(
          'Contact Support',
          style: AppConstants.bodyStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: const Color(0xFFF5EDE4),
          ),
        ),
      ),
      body: _submitted ? _buildSuccessState() : _buildFormState(),
    );
  }

  Widget _buildSuccessState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 64,
              color: AppConstants.success,
            ),
            const SizedBox(height: 20),
            Text(
              'Message Sent!',
              style: AppConstants.bodyStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppConstants.secondary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Our support team will review your message and get back to you soon. You can track updates in your notifications.',
              style: AppConstants.bodyStyle(
                fontSize: 14,
                color: AppConstants.secondary.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppConstants.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  'Done',
                  style: AppConstants.bodyStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormState() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppConstants.success.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.support_agent, size: 24, color: AppConstants.success),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Send us a message and our team will respond as soon as possible.',
                    style: AppConstants.bodyStyle(
                      fontSize: 13,
                      color: AppConstants.secondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Subject
          Text(
            'Subject',
            style: AppConstants.bodyStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppConstants.secondary,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _subjectController,
            style: AppConstants.bodyStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Brief description of your issue',
              hintStyle: AppConstants.bodyStyle(
                fontSize: 14,
                color: AppConstants.secondary.withValues(alpha: 0.4),
              ),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.all(12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: AppConstants.secondary.withValues(alpha: 0.15),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: AppConstants.secondary.withValues(alpha: 0.15),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppConstants.primary),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Message
          Text(
            'Message',
            style: AppConstants.bodyStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppConstants.secondary,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _messageController,
            maxLines: 6,
            minLines: 4,
            style: AppConstants.bodyStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Describe your issue in detail...',
              hintStyle: AppConstants.bodyStyle(
                fontSize: 14,
                color: AppConstants.secondary.withValues(alpha: 0.4),
              ),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.all(12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: AppConstants.secondary.withValues(alpha: 0.15),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: AppConstants.secondary.withValues(alpha: 0.15),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppConstants.primary),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Submit button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppConstants.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppConstants.secondary.withValues(alpha: 0.15),
                disabledForegroundColor: AppConstants.secondary.withValues(alpha: 0.4),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      'Send Message',
                      style: AppConstants.bodyStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 16),

          // View my reports link
          Center(
            child: TextButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const MyReportsScreen()),
                );
              },
              child: Text(
                'View My Reports',
                style: AppConstants.bodyStyle(
                  fontSize: 13,
                  color: AppConstants.primary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
