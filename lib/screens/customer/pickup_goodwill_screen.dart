import 'package:flutter/material.dart';

import '../../constants/app_constants.dart';
import '../../services/pickup_reservation_service.dart';
import '../../widgets/sole_card.dart';

/// Every time a STORE chose to give one of this customer's pickup holds more
/// time — with the reason it gave (ANQUI item 14).
///
/// Why this is a screen and not just a line on a hold: the per-hold note only
/// exists while that hold is on screen. A hold that was collected, released, or
/// simply pushed past the customer's `LIMIT`-bounded list used to take the record
/// of the favour with it, so the only remaining trace of a store's kindness was
/// a deadline that happened to be later than expected. This list comes from the
/// trail itself (`pickup_reservation_extension_grants`, which embeds the hold for
/// its names), so nothing a store explained can fall off the end of it.
///
/// The customer's OWN extensions are deliberately absent, and the screen says so:
/// the trail is the store's side of the ledger, and mixing the two would make it
/// impossible to tell a favour from an entitlement.
class PickupGoodwillScreen extends StatelessWidget {
  const PickupGoodwillScreen({super.key, this.grants = const []});

  /// The customer's trail, newest first — passed in rather than fetched here, so
  /// the screen cannot disagree with the holds list that links to it.
  final List<PickupExtensionGrant> grants;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      appBar: AppBar(
        title: Text('Goodwill from stores',
            style: AppConstants.headlineStyle(fontSize: 18)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Stack(
        children: [
          AppConstants.noiseOverlay(opacity: 0.03),
          grants.isEmpty ? _empty(context) : _list(context),
        ],
      ),
    );
  }

  Widget _empty(BuildContext context) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 40),
          Icon(Icons.volunteer_activism_outlined,
              size: 40, color: AppConstants.secondary.withValues(alpha: 0.4)),
          const SizedBox(height: 14),
          Text(
            'No store has given you extra time yet.',
            textAlign: TextAlign.center,
            style: AppConstants.headlineStyle(fontSize: 15),
          ),
          const SizedBox(height: 8),
          Text(
            'If you cannot make it to a store before a pickup hold runs out, '
            'the store can choose to keep your pair off the shelf for longer. '
            'When that happens, it is recorded here with the reason it gave.',
            textAlign: TextAlign.center,
            style: AppConstants.bodyStyle(
              fontSize: 12.5,
              height: 1.45,
              color: AppConstants.secondary.withValues(alpha: 0.8),
            ),
          ),
        ],
      );

  Widget _list(BuildContext context) {
    final summary = PickupGoodwillSummary.of(grants);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        _summaryBand(summary),
        const SizedBox(height: 14),
        for (final grant in grants) ...[
          _grantCard(grant),
          const SizedBox(height: 12),
        ],
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 24),
          child: Text(
            // The distinction that keeps the list honest: this is what stores did
            // for you, not what your own one-per-hold extension did.
            'These are times a store chose to give you more time. Your own '
            'extensions are not listed here — they are part of the hold.',
            style: AppConstants.bodyStyle(
              fontSize: 11.5,
              height: 1.4,
              color: AppConstants.secondary.withValues(alpha: 0.6),
            ),
          ),
        ),
      ],
    );
  }

  /// The header. Built from the same list it sits above, so it cannot count
  /// something the list does not show.
  Widget _summaryBand(PickupGoodwillSummary summary) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          // `creamDeep`, the same half-step-deeper token the counter-code band
          // and the bottom nav use: distinct from the page, not a new colour.
          color: AppConstants.creamDeep,
          borderRadius: AppConstants.cardRadius,
          border: Border.all(
            color: AppConstants.primary.withValues(alpha: 0.2),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${summary.grants} '
              '${summary.grants == 1 ? 'extension' : 'extensions'} · '
              '${summary.hours}h of extra time',
              style: AppConstants.headlineStyle(fontSize: 15),
            ),
            const SizedBox(height: 4),
            Text(
              '${summary.stores} ${summary.stores == 1 ? 'store' : 'stores'} '
              'kept your pair off the shelf for you.',
              style: AppConstants.bodyStyle(
                fontSize: 12,
                color: AppConstants.secondary.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      );

  Widget _grantCard(PickupExtensionGrant grant) {
    final store = grant.storeName.isEmpty ? 'A store' : grant.storeName;
    // The hold's own description, as much as the trail can carry of it. A grant
    // whose embed came back empty still renders: the reason is the point.
    final what = [
      if (grant.productName.isNotEmpty) grant.productName,
      if (grant.size.isNotEmpty) 'size ${grant.size}',
    ].join(' · ');

    return SoleCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.volunteer_activism_outlined,
                  size: 16, color: AppConstants.primary.withValues(alpha: 0.8)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  store,
                  style: AppConstants.headlineStyle(fontSize: 14),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppConstants.success.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '+${grant.hoursGranted}h',
                  style: AppConstants.bodyStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppConstants.success,
                  ),
                ),
              ),
            ],
          ),
          if (what.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              what,
              style: AppConstants.bodyStyle(
                fontSize: 12,
                color: AppConstants.secondary.withValues(alpha: 0.75),
              ),
            ),
          ],
          const SizedBox(height: 8),
          // The reason, quoted, because it is a sentence a person wrote.
          Text(
            '“${grant.reason}”',
            style: AppConstants.bodyStyle(
              fontSize: 12.5,
              height: 1.4,
              color: AppConstants.primary.withValues(alpha: 0.9),
            ),
          ),
          if (grant.newDeadline != null) ...[
            const SizedBox(height: 8),
            Text(
              grant.previousDeadline == null
                  ? 'Your hold now runs until '
                      '${formatPickupDeadline(grant.newDeadline!)}.'
                  : 'Your hold moved from '
                      '${formatPickupDeadline(grant.previousDeadline!)} to '
                      '${formatPickupDeadline(grant.newDeadline!)}.',
              style: AppConstants.bodyStyle(fontSize: 11.5, height: 1.35),
            ),
          ],
          if (grant.createdAt != null) ...[
            const SizedBox(height: 4),
            Text(
              'Given ${formatPickupDeadline(grant.createdAt!)}',
              style: AppConstants.bodyStyle(
                fontSize: 11,
                color: AppConstants.secondary.withValues(alpha: 0.6),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
