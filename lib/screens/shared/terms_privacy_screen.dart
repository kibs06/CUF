import 'package:flutter/material.dart';

import '../../constants/app_constants.dart';
import '../../widgets/sole_card.dart';
import '../../widgets/sole_primary_button.dart';

/// Which Terms & Privacy document to show. Customers and sellers each have
/// their own policy tailored to how they use CUFMAI — shoppers agree to the
/// customer document at registration, sellers agree to the seller document
/// inside the seller application flow. [all] renders both documents stacked
/// (used by admins from Profile → Settings to review the full set).
enum CUFMAITermsPolicy { customer, seller, all }

/// Terms & Privacy Policy for CUFMAI — written to match the actual app:
/// the official app of the Carcar United Footwear Manufacturers
/// Association, Inc., a marketplace for the footwear artisans of Carcar
/// City, Cebu.
///
/// Two role-specific documents live here, selected by [policy]:
/// `customer` covers shopping (orders, payments, returns, foot profile)
/// and `seller` covers selling (application & verification, storefront,
/// fulfillment, payouts). Both are reachable from the registration flows
/// (via the shared `TermsPolicyTile`, which passes the matching policy)
/// and from Profile → Settings → Terms & Privacy (which picks the document
/// by the signed-in user's role — sellers see the seller document, admins
/// see both via [CUFMAITermsPolicy.all], everyone else the customer
/// document).
///
/// Plain-language policy copy describing how the app actually works. Please
/// have it reviewed by legal counsel before production release.
class TermsPrivacyScreen extends StatefulWidget {
  /// When true (the registration consent flow), a sticky bottom bar is shown
  /// and its "I have read and I agree" button stays disabled until the user
  /// scrolls to the very bottom of the policy. Tapping it pops with `true`.
  /// When false (Profile → Settings), the screen is a plain read-only
  /// document with no bar.
  final bool readAndAgree;

  /// Which role-specific document to render.
  final CUFMAITermsPolicy policy;

  const TermsPrivacyScreen({
    super.key,
    this.readAndAgree = false,
    this.policy = CUFMAITermsPolicy.customer,
  });

  @override
  State<TermsPrivacyScreen> createState() => _TermsPrivacyScreenState();
}

class _TermsPrivacyScreenState extends State<TermsPrivacyScreen> {
  final ScrollController _scroll = ScrollController();

  /// Whether the user has scrolled to (within 8px of) the very bottom — the
  /// condition that unlocks the agree button in [readAndAgree] mode.
  bool _reachedBottom = false;

  bool get _isSeller => widget.policy == CUFMAITermsPolicy.seller;
  bool get _isAll => widget.policy == CUFMAITermsPolicy.all;

  @override
  void initState() {
    super.initState();
    if (widget.readAndAgree) {
      _scroll.addListener(_onScroll);
    }
  }

  void _onScroll() {
    // `mounted` guard: a scroll event can arrive while the route is being
    // popped (dispose already ran) and must never call setState then.
    if (!mounted || !_scroll.hasClients) return;
    final position = _scroll.position;
    final atBottom = position.pixels >= position.maxScrollExtent - 8;
    if (atBottom != _reachedBottom) {
      setState(() => _reachedBottom = atBottom);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      appBar: AppBar(
        backgroundColor: AppConstants.surfaceLight,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppConstants.secondary),
        title: Text(
          switch (widget.policy) {
            CUFMAITermsPolicy.seller => 'Seller Terms & Privacy',
            CUFMAITermsPolicy.all => 'Terms & Privacy',
            CUFMAITermsPolicy.customer => 'Customer Terms & Privacy',
          },
          style: AppConstants.headlineStyle(fontSize: 18),
        ),
      ),
      body: Stack(
        children: [
          AppConstants.noiseOverlay(opacity: 0.03),
          SingleChildScrollView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _bodyChildren(),
            ),
          ),
        ],
      ),
      // Registration flow only: the agree action lives in a sticky bar that
      // stays locked until the user scrolls to the very bottom of the policy.
      bottomNavigationBar: widget.readAndAgree ? _buildAgreeBar() : null,
    );
  }

  /// Sticky bottom bar for the read-and-agree flow. While the user hasn't
  /// reached the end it shows a scroll hint; once [_reachedBottom] it swaps
  /// in the enabled "I have read and I agree" button, which pops `true`.
  Widget _buildAgreeBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        decoration: const BoxDecoration(
          color: AppConstants.surfaceLight,
          border: Border(top: BorderSide(color: AppConstants.borderGray)),
        ),
        child: _reachedBottom
            ? SolePrimaryButton(
                label: 'I have read and I agree',
                onPressed: () => Navigator.of(context).pop(true),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: AppConstants.primary,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Scroll to the end of the policy to agree',
                      textAlign: TextAlign.center,
                      style: AppConstants.bodyStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppConstants.secondary.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  // ── Body assembly ─────────────────────────────────────────────
  /// Builds the full scrollable document. Single-document policies render
  /// one document; [CUFMAITermsPolicy.all] (admins) stacks the customer and
  /// seller documents with a divider between them.
  List<Widget> _bodyChildren() {
    if (_isAll) {
      return [
        _introCard(),
        const SizedBox(height: 28),
        _partLabel('PART I — CUSTOMER TERMS OF SERVICE'),
        const SizedBox(height: 12),
        ..._customerTermsSections(),
        const SizedBox(height: 28),
        _partLabel('PART II — CUSTOMER PRIVACY POLICY'),
        const SizedBox(height: 12),
        ..._customerPrivacySections(),
        _documentDivider('SELLER POLICY'),
        _partLabel('PART I — SELLER TERMS OF SERVICE'),
        const SizedBox(height: 12),
        ..._sellerTermsSections(),
        const SizedBox(height: 28),
        _partLabel('PART II — SELLER PRIVACY POLICY'),
        const SizedBox(height: 12),
        ..._sellerPrivacySections(),
        const SizedBox(height: 32),
        _footer(),
      ];
    }
    return [
      _introCard(),
      const SizedBox(height: 28),
      _partLabel(_isSeller
          ? 'PART I — SELLER TERMS OF SERVICE'
          : 'PART I — CUSTOMER TERMS OF SERVICE'),
      const SizedBox(height: 12),
      ..._termsSections(),
      const SizedBox(height: 28),
      _partLabel(_isSeller
          ? 'PART II — SELLER PRIVACY POLICY'
          : 'PART II — CUSTOMER PRIVACY POLICY'),
      const SizedBox(height: 12),
      ..._privacySections(),
      const SizedBox(height: 32),
      _footer(),
    ];
  }

  /// A subtle divider that marks the start of the second document in the
  /// combined admin view.
  Widget _documentDivider(String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Row(
        children: [
          const Expanded(child: Divider(color: AppConstants.borderGray)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              label,
              style: AppConstants.bodyStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.4,
                color: AppConstants.secondary.withValues(alpha: 0.5),
              ),
            ),
          ),
          const Expanded(child: Divider(color: AppConstants.borderGray)),
        ],
      ),
    );
  }

  // ── Intro ──────────────────────────────────────────────────────
  Widget _introCard() {
    final String introTitle;
    final String introText;
    switch (widget.policy) {
      case CUFMAITermsPolicy.seller:
        introTitle = 'Welcome, artisan partner';
        introText = 'CUFMAI is the official app of the Carcar United Footwear '
            'Manufacturers Association, Inc. — the home of the '
            'shoemakers of Carcar City, Cebu, the “Footwear Capital '
            'of the South.” This Seller Terms & Privacy Policy '
            'explains how selling on the app works, what information '
            'we collect from you, and how we use it.';
      case CUFMAITermsPolicy.all:
        introTitle = 'Welcome to CUFMAI';
        introText = 'CUFMAI is the official app of the Carcar United Footwear '
            'Manufacturers Association, Inc. — the home of the shoemakers '
            'of Carcar City, Cebu, the “Footwear Capital of the South.” '
            'This document contains the Customer and the Seller Terms & '
            'Privacy Policies that govern the app for everyone who uses it.';
      case CUFMAITermsPolicy.customer:
        introTitle = 'Welcome to CUFMAI';
        introText = 'CUFMAI is the official app of the Carcar United Footwear '
            'Manufacturers Association, Inc. — connecting you directly '
            'with the shoemakers of Carcar City, Cebu, the “Footwear '
            'Capital of the South.” These Customer Terms & Privacy '
            'Policy explain how the app works, what information we '
            'collect, and how we use it.';
    }

    return SoleCard(
      color: Colors.white,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppConstants.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.gavel_outlined,
                  size: 20,
                  color: AppConstants.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  introTitle,
                  style: AppConstants.headlineStyle(fontSize: 18),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            introText,
            style: AppConstants.bodyStyle(
              fontSize: 13,
              color: AppConstants.secondary.withValues(alpha: 0.75),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _partLabel(String text) {
    return Text(
      text,
      style: AppConstants.bodyStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.4,
        color: AppConstants.primary,
      ),
    );
  }

  // ── PART I — Terms of Service ──────────────────────────────────
  List<Widget> _termsSections() {
    return _isSeller ? _sellerTermsSections() : _customerTermsSections();
  }

  List<Widget> _customerTermsSections() {
    return [
      _sectionCard(
        icon: Icons.person_outline_rounded,
        title: 'Your Account & Eligibility',
        items: const [
          _PolicyItem(
            'Age requirement',
            'You must be at least 13 years old to use CUFMAI. We ask for '
                'your birthday at sign-up for this reason — and to surprise '
                'you with a birthday treat.',
          ),
          _PolicyItem(
            'Accurate information',
            'Keep the details on your account accurate and up to date. Each '
                'person may maintain one account, and you are responsible for '
                'keeping your login credentials secure.',
          ),
        ],
      ),
      const SizedBox(height: 16),
      _sectionCard(
        icon: Icons.payments_outlined,
        title: 'Orders & Payment',
        items: const [
          _PolicyItem(
            'Placing orders',
            'When you place an order, you commit to paying the listed price '
                'plus any applicable delivery fees. Order status is tracked '
                'in the app from unpaid to delivered.',
          ),
          _PolicyItem(
            'Payment methods',
            'We accept GCash. You may pay either by uploading a GCash '
                'payment reference or through our online checkout, which is '
                'processed by PayMongo. We do not store your full payment '
                'details.',
          ),
        ],
      ),
      const SizedBox(height: 16),
      _sectionCard(
        icon: Icons.assignment_return_outlined,
        title: 'Returns & Refunds',
        items: const [
          _PolicyItem(
            'Return window',
            'You may return unworn, unused items within 7 days of delivery '
                'for a full refund.',
          ),
          _PolicyItem(
            'Condition requirements',
            'Items must be in their original packaging with all tags '
                'attached. Worn, damaged, or altered items will not be '
                'accepted.',
          ),
          _PolicyItem(
            'Refund processing',
            'Refunds are issued to your original payment method within 5–7 '
                'business days after we receive and inspect the returned '
                'item.',
          ),
          _PolicyItem(
            'Return shipping',
            'The buyer covers return shipping unless the item arrives '
                'defective or incorrect — we recommend a trackable shipping '
                'service.',
          ),
          _PolicyItem(
            'Defective or incorrect items',
            'Contact us within 48 hours of delivery and we will provide a '
                'prepaid return label and ship a replacement at no additional '
                'cost.',
          ),
        ],
      ),
      const SizedBox(height: 16),
      _sectionCard(
        icon: Icons.block_outlined,
        title: 'Prohibited Conduct',
        items: const [
          _PolicyItem(
            'You may not',
            'Use CUFMAI for fraud, post fake reviews, harass other users, '
                'misuse another person’s information, or attempt to break, '
                'overload, or gain unauthorized access to the platform.',
          ),
        ],
      ),
      const SizedBox(height: 16),
      _sectionCard(
        icon: Icons.pause_circle_outline_rounded,
        title: 'Account Suspension & Termination',
        items: const [
          _PolicyItem(
            'Our right to act',
            'We may suspend or close accounts that violate these terms.',
          ),
        ],
      ),
      const SizedBox(height: 16),
      _sectionCard(
        icon: Icons.shield_outlined,
        title: 'Disclaimer & Limitation of Liability',
        items: const [
          _PolicyItem(
            'Good faith, not guarantees',
            'CUFMAI connects buyers with sellers and reviews seller '
                'applications, but cannot guarantee the quality of every '
                'product. To the fullest extent permitted by law, our '
                'liability is limited to the amount you paid for the order '
                'in question.',
          ),
        ],
      ),
      const SizedBox(height: 16),
      _sectionCard(
        icon: Icons.update_rounded,
        title: 'Changes to These Terms',
        items: const [
          _PolicyItem(
            'Updates',
            'We may update these terms from time to time. Continued use of '
                'the app after an update means you accept the new terms — '
                'please check back periodically.',
          ),
        ],
      ),
    ];
  }

  List<Widget> _sellerTermsSections() {
    return [
      _sectionCard(
        icon: Icons.person_outline_rounded,
        title: 'Your Account & Eligibility',
        items: const [
          _PolicyItem(
            'Age requirement',
            'You must be at least 13 years old to use CUFMAI.',
          ),
          _PolicyItem(
            'Accurate information',
            'Keep the details on your account accurate and up to date. Each '
                'person may maintain one account, and you are responsible for '
                'keeping your login credentials secure.',
          ),
        ],
      ),
      const SizedBox(height: 16),
      _sectionCard(
        icon: Icons.verified_outlined,
        title: 'Seller Application & Verification',
        items: const [
          _PolicyItem(
            'Applying',
            'To sell on CUFMAI you apply with a government ID, a selfie, and '
                'proof of your community link (CUFMAI membership or a '
                'barangay certificate). Applications are reviewed by a '
                'CUFMAI admin before approval.',
          ),
          _PolicyItem(
            'Keeping it current',
            'Sellers must keep their verification documents current when the '
                'app asks for them. CUFMAI admins may review stores and '
                'listings at any time.',
          ),
        ],
      ),
      const SizedBox(height: 16),
      _sectionCard(
        icon: Icons.storefront_outlined,
        title: 'Storefront & Listings',
        items: const [
          _PolicyItem(
            'Authentic products',
            'Sellers must list only genuine products they make or legitimately '
                'supply, with accurate descriptions, sizes, and prices.',
          ),
        ],
      ),
      const SizedBox(height: 16),
      _sectionCard(
        icon: Icons.local_shipping_outlined,
        title: 'Orders & Fulfillment',
        items: const [
          _PolicyItem(
            'Fulfilling orders',
            'When a customer places an order, you commit to fulfilling it. '
                'Order status is tracked in the app from placed to delivered.',
          ),
        ],
      ),
      const SizedBox(height: 16),
      _sectionCard(
        icon: Icons.payments_outlined,
        title: 'Payouts',
        items: const [
          _PolicyItem(
            'Where earnings go',
            'Seller earnings are sent to the payout method on file (GCash or '
                'bank). CUFMAI may hold a payout while a dispute or return is '
                'being resolved.',
          ),
        ],
      ),
      const SizedBox(height: 16),
      _sectionCard(
        icon: Icons.block_outlined,
        title: 'Prohibited Conduct',
        items: const [
          _PolicyItem(
            'You may not',
            'Use CUFMAI for fraud, sell counterfeit or misrepresented '
                'goods, post fake reviews, harass other users, misuse '
                'another person’s information, or attempt to break, overload, '
                'or gain unauthorized access to the platform.',
          ),
        ],
      ),
      const SizedBox(height: 16),
      _sectionCard(
        icon: Icons.pause_circle_outline_rounded,
        title: 'Account Suspension & Termination',
        items: const [
          _PolicyItem(
            'Our right to act',
            'We may suspend or close accounts that violate these terms, '
                'including removing a seller’s ability to sell.',
          ),
        ],
      ),
      const SizedBox(height: 16),
      _sectionCard(
        icon: Icons.shield_outlined,
        title: 'Disclaimer & Limitation of Liability',
        items: const [
          _PolicyItem(
            'Good faith, not guarantees',
            'CUFMAI connects buyers with sellers and reviews seller '
                'applications, but cannot guarantee the quality of every '
                'product. To the fullest extent permitted by law, our '
                'liability is limited to the amount you paid for the order '
                'in question.',
          ),
        ],
      ),
      const SizedBox(height: 16),
      _sectionCard(
        icon: Icons.update_rounded,
        title: 'Changes to These Terms',
        items: const [
          _PolicyItem(
            'Updates',
            'We may update these terms from time to time. Continued use of '
                'the app after an update means you accept the new terms — '
                'please check back periodically.',
          ),
        ],
      ),
    ];
  }

  // ── PART II — Privacy Policy ───────────────────────────────────
  List<Widget> _privacySections() {
    return _isSeller ? _sellerPrivacySections() : _customerPrivacySections();
  }

  List<Widget> _customerPrivacySections() {
    return [
      _sectionCard(
        icon: Icons.fact_check_outlined,
        title: 'Information We Collect',
        items: const [
          _PolicyItem(
            'Account details',
            'Your full name, email address, phone number, birthday, and '
                'optional gender when you register.',
          ),
          _PolicyItem(
            'Foot profile',
            'Foot measurements from an AR scan or manual entry — per-foot '
                'length and width, plus recommended EU/US/UK sizes — used to '
                'recommend shoes that actually fit.',
          ),
          _PolicyItem(
            'Orders & payments',
            'Shipping addresses, order history, and payment details (handled '
                'through GCash/PayMongo; we do not store full payment card '
                'numbers).',
          ),
          _PolicyItem(
            'Device & usage',
            'Push-notification tokens and basic usage information so we can '
                'operate and improve the app.',
          ),
        ],
      ),
      const SizedBox(height: 16),
      _sectionCard(
        icon: Icons.insights_outlined,
        title: 'How We Use Your Information',
        items: const [
          _PolicyItem(
            'Purpose',
            'To process orders and payments, arrange delivery, recommend '
                'correctly sized shoes from your foot profile, send birthday '
                'treats, respond to support requests, keep the platform '
                'secure, and improve the app.',
          ),
        ],
      ),
      const SizedBox(height: 16),
      _sectionCard(
        icon: Icons.straighten_outlined,
        title: 'Your Foot Measurements',
        items: const [
          _PolicyItem(
            'Used for sizing only',
            'Foot measurements power your size recommendations. They are '
                'stored securely, are never sold, and you can re-scan or '
                'clear them anytime from your foot profile.',
          ),
        ],
      ),
      const SizedBox(height: 16),
      _sectionCard(
        icon: Icons.people_outline_rounded,
        title: 'Sharing & Disclosure',
        items: const [
          _PolicyItem(
            'Only what is needed',
            'We share information only with the parties required to operate '
                'the app: payment processors (GCash/PayMongo), delivery '
                'partners, and CUFMAI admins reviewing seller '
                'verification. We never sell your personal information.',
          ),
        ],
      ),
      const SizedBox(height: 16),
      _sectionCard(
        icon: Icons.lock_outline_rounded,
        title: 'Storage & Security',
        items: const [
          _PolicyItem(
            'How we protect it',
            'Data is stored with industry-standard security, encrypted in '
                'transit and at rest. Verification documents live in a '
                'private, access-controlled area visible only to CUFMAI '
                'admins during review.',
          ),
        ],
      ),
      const SizedBox(height: 16),
      _sectionCard(
        icon: Icons.delete_outline_rounded,
        title: 'Retention & Deletion',
        items: const [
          _PolicyItem(
            'Keeping what we need',
            'We keep your data while your account is active or as long as we '
                'need it for the purposes above. You may delete your account '
                'to remove your personal data; a few records (such as order '
                'history) may be kept where required for legal or tax '
                'reasons.',
          ),
        ],
      ),
      const SizedBox(height: 16),
      _sectionCard(
        icon: Icons.manage_accounts_outlined,
        title: 'Your Rights',
        items: const [
          _PolicyItem(
            'Access, correct, delete',
            'You can view and correct your details in the app, opt out of '
                'marketing messages anytime, and ask us to delete your data. '
                'Message us and we will help.',
          ),
        ],
      ),
      const SizedBox(height: 16),
      _sectionCard(
        icon: Icons.child_care_outlined,
        title: 'Children’s Privacy',
        items: const [
          _PolicyItem(
            '13+ only',
            'CUFMAI is not intended for children under 13, and we do not '
                'knowingly collect their information.',
          ),
        ],
      ),
      const SizedBox(height: 16),
      _sectionCard(
        icon: Icons.contact_support_outlined,
        title: 'Contact Us',
        items: const [
          _PolicyItem(
            'Questions?',
            'For any question about these terms or your data, email us at '
                'support@cufmai.ph or use the Help & Support section in the '
                'app.',
          ),
        ],
      ),
    ];
  }

  List<Widget> _sellerPrivacySections() {
    return [
      _sectionCard(
        icon: Icons.fact_check_outlined,
        title: 'Information We Collect',
        items: const [
          _PolicyItem(
            'Account details',
            'Your full name, email address, and phone number when you '
                'register.',
          ),
          _PolicyItem(
            'Seller verification',
            'A government ID photo, a selfie, barangay proof, an optional '
                'CUFMAI member ID, store details, payout details, and '
                'optional business documents (DTI, BIR, permit).',
          ),
          _PolicyItem(
            'Orders & payments',
            'Your order history, store performance data, and payout details '
                '(handled through GCash/PayMongo; we do not store full '
                'payment card numbers).',
          ),
          _PolicyItem(
            'Device & usage',
            'Push-notification tokens and basic usage information so we can '
                'operate and improve the app.',
          ),
        ],
      ),
      const SizedBox(height: 16),
      _sectionCard(
        icon: Icons.insights_outlined,
        title: 'How We Use Your Information',
        items: const [
          _PolicyItem(
            'Purpose',
            'To review your seller application, verify your identity and '
                'business documents, process payouts, respond to support '
                'requests, keep the platform secure, and improve the app.',
          ),
        ],
      ),
      const SizedBox(height: 16),
      _sectionCard(
        icon: Icons.people_outline_rounded,
        title: 'Sharing & Disclosure',
        items: const [
          _PolicyItem(
            'Only what is needed',
            'We share information only with the parties required to operate '
                'the app: CUFMAI admins reviewing your verification '
                'documents, payment processors (GCash/PayMongo) for payouts, '
                'and delivery partners for your orders. We never sell your '
                'personal information.',
          ),
        ],
      ),
      const SizedBox(height: 16),
      _sectionCard(
        icon: Icons.lock_outline_rounded,
        title: 'Storage & Security',
        items: const [
          _PolicyItem(
            'How we protect it',
            'Data is stored with industry-standard security, encrypted in '
                'transit and at rest. Verification documents live in a '
                'private, access-controlled area visible only to CUFMAI '
                'admins during review.',
          ),
        ],
      ),
      const SizedBox(height: 16),
      _sectionCard(
        icon: Icons.delete_outline_rounded,
        title: 'Retention & Deletion',
        items: const [
          _PolicyItem(
            'Keeping what we need',
            'We keep your data while your account is active or as long as we '
                'need it for the purposes above. You may delete your account '
                'to remove your personal data; a few records (such as order '
                'history) may be kept where required for legal or tax '
                'reasons.',
          ),
        ],
      ),
      const SizedBox(height: 16),
      _sectionCard(
        icon: Icons.manage_accounts_outlined,
        title: 'Your Rights',
        items: const [
          _PolicyItem(
            'Access, correct, delete',
            'You can view and correct your details in the app, opt out of '
                'marketing messages anytime, and ask us to delete your data. '
                'Message us and we will help.',
          ),
        ],
      ),
      const SizedBox(height: 16),
      _sectionCard(
        icon: Icons.contact_support_outlined,
        title: 'Contact Us',
        items: const [
          _PolicyItem(
            'Questions?',
            'For any question about these terms or your data, email us at '
                'support@cufmai.ph or use the Help & Support section in the '
                'app.',
          ),
        ],
      ),
    ];
  }

  // ── Shared card + footer ───────────────────────────────────────
  Widget _sectionCard({
    required IconData icon,
    required String title,
    required List<_PolicyItem> items,
  }) {
    return SoleCard(
      color: Colors.white,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppConstants.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: AppConstants.bodyStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppConstants.secondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            _PolicyItemView(item: items[i]),
          ],
        ],
      ),
    );
  }

  Widget _footer() {
    return Column(
      children: [
        Center(
          child: Text(
            'Last updated: August 2026',
            style: AppConstants.bodyStyle(
              fontSize: 11,
              color: AppConstants.secondary.withValues(alpha: 0.4),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Center(
          child: Text(
            'CUFMAI · Carcar United Footwear Manufacturers Association, Inc.',
            textAlign: TextAlign.center,
            style: AppConstants.bodyStyle(
              fontSize: 11,
              color: AppConstants.secondary.withValues(alpha: 0.4),
            ),
          ),
        ),
      ],
    );
  }
}

/// One titled paragraph inside a policy card.
class _PolicyItem {
  final String title;
  final String body;

  const _PolicyItem(this.title, this.body);
}

class _PolicyItemView extends StatelessWidget {
  final _PolicyItem item;

  const _PolicyItemView({required this.item});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.title,
          style: AppConstants.bodyStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: AppConstants.primary,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          item.body,
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
