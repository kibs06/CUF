import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../constants/app_constants.dart';
import '../../widgets/sole_card.dart';

/// About CUFMAI — the official app of the Carcar United Footwear
/// Manufacturers Association, Inc. Replaces the old "Coming soon"
/// placeholder with real, factual content about the association.
class AboutCufmaiScreen extends StatelessWidget {
  const AboutCufmaiScreen({super.key});

  // ── Hero palette — warm leather browns + gold/cream ──────────────
  static const Color _brownLight = Color(0xFF8A5A34);
  static const Color _brownMid = Color(0xFF6B3F1F);
  static const Color _brownDark = Color(0xFF4A2A13);
  static const Color _gold = Color(0xFFE8C07A);
  static const Color _goldDeep = Color(0xFFC99A4D);
  static const Color _cream = Color(0xFFF3E2C2);

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
            // Horizontal padding lives on the section wrapper below so the
            // hero can stretch full-bleed edge-to-edge.
            padding: const EdgeInsets.only(top: 8, bottom: 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Hero header (full-bleed) ────────────────────
                _buildHeroHeader(),

                // ── Content sections ────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Who We Are ────────────────────────────
                      _buildSectionCard(
                        icon: Icons.groups_rounded,
                        title: 'Who We Are',
                        paragraphs: [
                          'CUFMAI (Carcar United Footwear Manufacturers Association, Inc.) is a manufacturers\' association based in Carcar City, Cebu, Philippines — long known as the "Footwear Capital of the South." Shoemaking is a generations-old heritage craft in Carcar, centered in the barangays of Poblacion 3, Liburon, and Valladolid.',
                          'CUFMAI was formally organized in 2004 to unite the town\'s independent shoemakers into a single body, turning a scattered craft tradition into an organized local industry.',
                        ],
                      ),
                      const SizedBox(height: 16),

                      // ── What We Do ────────────────────────────
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

                      // ── Our Members ────────────────────────────
                      _buildSectionCard(
                        icon: Icons.badge_outlined,
                        title: 'Our Members',
                        paragraphs: [
                          'CUFMAI\'s members are independent, DTI-registered shoe and sandal manufacturers based in Carcar City, most concentrated in Barangay Valladolid. Membership is limited to manufacturers who are formally registered, pay local taxes, and follow the association\'s by-laws — a deliberate choice to keep membership made up of legitimate, accountable businesses.',
                        ],
                      ),
                      const SizedBox(height: 16),

                      // ── Our Heritage, Our Future ───────────────
                      _buildSectionCard(
                        icon: Icons.timeline_rounded,
                        title: 'Our Heritage, Our Future',
                        paragraphs: [
                          'Carcar\'s shoemaking tradition has faced real challenges in recent years — competition from cheap imported footwear and a shift toward online shopping have made things harder for many local manufacturers.',
                          'This app exists to help meet that shift head-on: giving CUFMAI\'s member manufacturers a direct digital storefront to reach customers who now shop online, while keeping the craftsmanship, heritage, and community behind every pair rooted in Carcar.',
                        ],
                      ),
                      const SizedBox(height: 32),

                      // ── Footer ─────────────────────────────────
                      Center(
                        child: Column(
                          children: [
                            Text(
                              'Carcar United Footwear Manufacturers Association, Inc.',
                              textAlign: TextAlign.center,
                              style: AppConstants.bodyStyle(
                                fontSize: 12,
                                color:
                                    AppConstants.secondary.withValues(alpha: 0.5),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Carcar City, Cebu, Philippines',
                              textAlign: TextAlign.center,
                              style: AppConstants.bodyStyle(
                                fontSize: 11,
                                color: AppConstants.secondary
                                    .withValues(alpha: 0.35),
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
          ),
        ],
      ),
    );
  }

  /// Hero header — full-bleed brand card: radial leather gradient, faint
  /// diagonal stitch pattern, shoe icon + eyebrow, serif wordmark, and a
  /// gold "Organized 2004" badge. No corner radius or side margins because
  /// it touches both screen edges.
  Widget _buildHeroHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
      decoration: BoxDecoration(
        // Light source top-left, darkening toward bottom-right.
        gradient: const RadialGradient(
          center: Alignment.topLeft,
          radius: 1.5,
          colors: [_brownLight, _brownMid, _brownDark],
          stops: [0.0, 0.45, 1.0],
        ),
      ),
      child: Stack(
        children: [
          // Faint diagonal stitch-line pattern (clipped to card bounds).
          Positioned.fill(
            child: ClipRect(
              child: CustomPaint(painter: _StitchPatternPainter()),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Icon · divider · eyebrow row ──────────────────
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [_gold, _goldDeep],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.hiking,
                      color: _brownDark,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Thin vertical divider
                  Container(
                    width: 1,
                    height: 34,
                    color: Colors.white.withValues(alpha: 0.15),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'footwear capital of the south',
                      style: AppConstants.bodyStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: _gold,
                      ).copyWith(letterSpacing: 0.9), // ~0.08em at 12px
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // ── Wordmark ──────────────────────────────────────
              Text(
                'CUFMAI',
                style: AppConstants.headlineStyle(
                  fontSize: 34,
                  color: Colors.white,
                ).copyWith(letterSpacing: -0.5),
              ),
              const SizedBox(height: 6),

              // Subtitle — constrained so it doesn't stretch awkwardly
              // across the now-wider card.
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
                child: Text(
                  'Carcar United Footwear Manufacturers Association, Inc.',
                  style: AppConstants.bodyStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.85),
                    height: 1.3,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ── Gold "Organized 2004" badge ───────────────────
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _gold.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _gold.withValues(alpha: 0.45),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.calendar_today_outlined,
                      size: 13,
                      color: _cream,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Organized 2004 · Carcar City, Cebu',
                        style: AppConstants.bodyStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: _cream,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
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

/// Faint white dashed diagonal lines at ~8% opacity — a subtle nod to the
/// shoemaking craft (stitching), not a loud texture. Lines run at 45° and
/// are evenly spaced across the full card.
class _StitchPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    const double dash = 4.0;
    const double gap = 4.0;
    const double spacing = 22.0;

    // 45° diagonal line from (x, 0) to (x + height, height).
    final double length = size.height * math.sqrt2;
    final Offset step = Offset(size.height, size.height) / length;

    for (double x = -size.height; x < size.width + 1; x += spacing) {
      final Offset start = Offset(x, 0);
      double travelled = 0;
      while (travelled < length) {
        canvas.drawLine(
          start + step * travelled,
          start + step * (travelled + dash),
          paint,
        );
        travelled += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _StitchPatternPainter oldDelegate) => false;
}
