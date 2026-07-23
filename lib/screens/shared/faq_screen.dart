import 'package:flutter/material.dart';

import '../../constants/app_constants.dart';

/// FAQ screen with expandable question/answer items.
class FAQScreen extends StatelessWidget {
  const FAQScreen({super.key});

  static const List<Map<String, String>> _faqs = [
    {
      'question': 'How do I place an order?',
      'answer': 'Browse products on the Home or Store screen, tap on a product you like, select your size, and tap "Add to Cart." When you\'re ready, go to your Cart and tap "Checkout" to complete your order.',
    },
    {
      'question': 'How do I track my order?',
      'answer': 'Go to your Profile → My Orders, then tap on the order you want to track. The tracking screen shows your order\'s current status and timeline.',
    },
    {
      'question': 'Can I cancel my order?',
      'answer': 'You can cancel orders that are still in "Pending" or "Processing" status. Go to My Orders → select the order → tap "Cancel Order." Processing orders have a 2-hour cancellation window.',
    },
    {
      'question': 'How do I request a change to my order?',
      'answer': 'Open the chat conversation for your order and tap the "Request a Change" button above the message input. You can request changes to size, color, delivery address, or quantity.',
    },
    {
      'question': 'How do I leave a review?',
      'answer': 'After your order is delivered, go to My Orders → find the delivered order → tap "Rate & Review." You can leave a star rating and written feedback.',
    },
    {
      'question': 'How do I report a problem?',
      'answer': 'Go to Profile → Help & Support → Report a Problem. You can report issues with orders, sellers, products, or general app problems.',
    },
    {
      'question': 'How do I contact a seller?',
      'answer': 'From any order card in My Orders, tap the chat icon to open a conversation with the seller. You can ask questions, request changes, or follow up on your order status.',
    },
    {
      'question': 'What payment methods are accepted?',
      'answer': 'We currently support cash on delivery and in-store pickup payments. More payment options will be available soon.',
    },
    {
      'question': 'How do I update my profile information?',
      'answer': 'Go to Profile → tap the edit icon next to your name → update your name or phone number → tap "Save Changes."',
    },
    {
      'question': 'How do I follow a store?',
      'answer': 'Visit a store\'s profile page and tap the "Follow" button. You\'ll see their products in your feed and receive updates about new arrivals.',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      appBar: AppBar(
        backgroundColor: AppConstants.secondary,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFFF5EDE4), size: 24),
        title: Text(
          'FAQ',
          style: AppConstants.bodyStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: const Color(0xFFF5EDE4),
          ),
        ),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _faqs.length,
        itemBuilder: (context, index) {
          return _FAQItem(
            question: _faqs[index]['question']!,
            answer: _faqs[index]['answer']!,
          );
        },
      ),
    );
  }
}

class _FAQItem extends StatefulWidget {
  final String question;
  final String answer;

  const _FAQItem({required this.question, required this.answer});

  @override
  State<_FAQItem> createState() => _FAQItemState();
}

class _FAQItemState extends State<_FAQItem> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          leading: Icon(
            Icons.help_outline,
            size: 20,
            color: AppConstants.primary,
          ),
          title: Text(
            widget.question,
            style: AppConstants.bodyStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppConstants.secondary,
            ),
          ),
          trailing: Icon(
            _isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
            color: AppConstants.secondary.withValues(alpha: 0.4),
          ),
          onExpansionChanged: (expanded) {
            setState(() => _isExpanded = expanded);
          },
          children: [
            Text(
              widget.answer,
              style: AppConstants.bodyStyle(
                fontSize: 13,
                color: AppConstants.secondary.withValues(alpha: 0.7),
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
