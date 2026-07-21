/// Represents a store that a customer is following,
/// with store details needed for the Following overlay.
class FollowedStore {
  final String storeId;
  final String name;
  final String? logoUrl;
  final String? tagline;
  final String? color; // hex string, matches store brand color usage elsewhere
  final DateTime followedAt;
  final int followerCount;

  const FollowedStore({
    required this.storeId,
    required this.name,
    this.logoUrl,
    this.tagline,
    this.color,
    required this.followedAt,
    required this.followerCount,
  });
}
