import 'package:flutter/material.dart';
import '../../constants/app_constants.dart';
import '../../widgets/sole_card.dart';

/// About CUFMAI — the official app of the Carcar United Footwear
/// Manufacturers Association, Inc. Replaces the old "Coming soon"
/// placeholder with real, factual content about the association.
class AboutCufmaiScreen extends StatelessWidget {
  const AboutCufmaiScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      appBar: AppBar(
        title: Text(
          'About CUFMAI',
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
                // ── Hero header ─────────────────────────────────
                _buildHeroHeader(),
                const SizedBox(height: 24),

                // ── Who We Are ──────────────────────────────────
                _buildSectionCard(
                  icon: Icons.groups_rounded,
                  title: 'Who We Are',
                  paragraphs: [
                    'CUFMAI (Carcar United Footwear Manufacturers Association, Inc.) is a manufacturers\' association based in Carcar City, Cebu, Philippines — long known as the "Footwear Capital of the South." Shoemaking is a generations-old heritage craft in Carcar, centered in the barangays of Poblacion 3, Liburon, and Valladolid.',
                    'CUFMAI was formally organized in 2004 to unite the town\'s independent shoemakers into a single body, turning a scattered craft tradition into an organized local industry.',
                  ],
                ),
                const SizedBox(height: 16),

                // ── What We Do ──────────────────────────────────
                _buildSectionCard(
                  icon: Icons.handyman_outlined,
                  title: 'What We Do',
                  paragraphs: [
                    'Bulk purchasing of raw materials — leather and other supplies — so member manufacturers can access lower costs than buying individually.',
                    'Shared production facilities and equipment, including cutting, stitching, and sole-pressing machinery, that member manufacturers can use to produce faster and more consistently.',
                    'A shared retail and display center in Barangay Valladolid where member manufacturers sell their footwear under one roof.',
                    'Advocacy and coordination with government agencies like DTI to bring training, funding, and market access to local shoemakers.',
                  ],
                ),
                const SizedBox(height: 16),

                // ── Our Members ─────────────────────────────────
                _buildSectionCard(
                  icon: Icons.badge_outlined,
                  title: 'Our Members',
                  paragraphs: [
                    'CUFMAI\'s members are independent, DTI-registered shoe and sandal manufacturers based in Carcar City, most concentrated in Barangay Valladolid. Membership is limited to manufacturers who are formally registered, pay local taxes, and follow the association\'s by-laws — a deliberate choice to keep membership made up of legitimate, accountable businesses.',
                  ],
                ),
                const SizedBox(height: 16),

                // ── Our Heritage, Our Future ────────────────────
                _buildSectionCard(
                  icon: Icons.timeline_rounded,
                  title: 'Our Heritage, Our Future',
                  paragraphs: [
                    'Carcar\'s shoemaking tradition has faced real challenges in recent years — competition from cheap imported footwear and a shift toward online shopping have made things harder for many local manufacturers.',
                    'This app exists to help meet that shift head-on: giving CUFMAI\'s member manufacturers a direct digital storefront to reach customers who now shop online, while keeping the craftsmanship, heritage, and community behind every pair rooted in Carcar.',
                  ],
                ),
                const SizedBox(height: 32),

                // ── Footer ──────────────────────────────────────
                Center(
                  child: Column(
                    children: [
                      Text(
                        'Carcar United Footwear Manufacturers Association, Inc.',
                        textAlign: TextAlign.center,
                        style: AppConstants.bodyStyle(
                          fontSize: 12,
                          color: AppConstants.secondary.withValues(alpha: 0.5),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Carcar City, Cebu, Philippines',
                        textAlign: TextAlign.center,
                        style: AppConstants.bodyStyle(
                          fontSize: 11,
                          color: AppConstants.secondary.withValues(alpha: 0.35),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Hero header — warm, prominent opening with the association name
  /// and a short tagline before the detailed sections begin.
  Widget _buildHeroHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppConstants.primary, Color(0xFF6B3F1F)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: AppConstants.cardRadius,
        boxShadow: [
          BoxShadow(
            color: AppConstants.primary.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon badge
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.storefront_rounded,
              color: Colors.white,
              size: 26,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'CUFMAI',
            style: AppConstants.headlineStyle(
              fontSize: 30,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Carcar United Footwear Manufacturers Association, Inc.',
            style: AppConstants.bodyStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.white.withValues(alpha: 0.85),
              height: 1.3,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppConstants.accent.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppConstants.accent.withValues(alpha: 0.4),
              ),
            ),
            child: Text(
              'Organized 2004 · Carcar City, Cebu',
              style: AppConstants.bodyStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppConstants.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// A content section card with an icon header, title, and one or more
  /// paragraphs broken into readable chunks. Uses SoleCard internally.
  Widget _buildSectionCard({
    required IconData icon,
    required String title,
    required List<String> paragraphs,
  }) {
    return SoleCard(
      color: Colors.white,
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header with icon
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppConstants.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 20, color: AppConstants.primary),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: AppConstants.headlineStyle(
                  fontSize: 18,
                  color: AppConstants.secondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Paragraphs — generous spacing for readability
          ...paragraphs.map((p) => Padding(
            padding: EdgeInsets.only(
              bottom: paragraphs.last == p ? 0 : 14,
            ),
            child: Text(
              p,
              style: AppConstants.bodyStyle(
                fontSize: 14,
                color: AppConstants.secondary,
                height: 1.6,
              ),
            ),
          )),
        ],
      ),
    );
  }
}