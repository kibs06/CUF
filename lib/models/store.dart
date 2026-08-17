import 'package:flutter/material.dart';
import '../constants/app_constants.dart';

/// Maps to the `stores` table in Supabase.
/// Represents a single artisan shoe store on the SoleVision platform.
class Store {
  final String id;
  final String name;
  final String? tagline;
  /// Longer "about the store" text (optional — sellers can add it after
  /// store creation; the application's Step 4 description was optional).
  final String? description;
  final String location;
  /// Store tag ids — same preset vocabulary as product tags (handmade,
  /// leather, eco-friendly…). Collected during the seller application and
  /// editable via Edit Store.
  final List<String> tags;
  final String brandColor; // hex string, e.g. '#8B5A2B'
  final String? bannerUrl;
  final String? logoUrl;
  /// Aggregate of customer reviews (1–5). NULL until the store has its
  /// first review — maintained by the `refresh_store_rating()` DB trigger,
  /// never written from the app.
  final double? rating;
  /// Number of reviews behind [rating] (trigger-maintained).
  final int reviewCount;
  final bool isOpen;
  final bool isActive;
  final String? ownerId;
  final DateTime createdAt;
  // Auto-schedule fields
  final bool autoScheduleEnabled;
  final String? openTime; // 'HH:MM:SS' local wall-clock, null if not set
  final String? closeTime; // 'HH:MM:SS' local wall-clock, null if not set
  final bool manualOverride;

  const Store({
    required this.id,
    required this.name,
    this.tagline,
    this.description,
    required this.location,
    this.tags = const [],
    this.brandColor = '#8B5A2B',
    this.bannerUrl,
    this.logoUrl,
    this.rating,
    this.reviewCount = 0,
    this.isOpen = true,
    this.isActive = true,
    this.ownerId,
    required this.createdAt,
    this.autoScheduleEnabled = false,
    this.openTime,
    this.closeTime,
    this.manualOverride = false,
  });

  /// Parse brandColor hex into a Flutter Color.
  Color get color => AppConstants.parseBrandColor(brandColor);

  /// Derive initials from the store name (first letter of first two words).
  String get initials {
    final words = name.split(' ').where((w) => w.isNotEmpty).toList();
    if (words.length >= 2) {
      return '${words[0][0]}${words[1][0]}'.toUpperCase();
    }
    return words.isNotEmpty ? words[0][0].toUpperCase() : '?';
  }

  /// Gradient using the brand color for card backgrounds.
  LinearGradient get cardGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [color, Color.lerp(color, const Color(0xFF1A1208), 0.55)!],
  );

  /// Formatted open–close hours, e.g. '9:00 AM – 5:00 PM'.
  /// Returns null when either time isn't configured.
  String? get hoursLabel {
    final open = _formatTime(openTime);
    final close = _formatTime(closeTime);
    if (open == null || close == null) return null;
    return '$open – $close';
  }

  /// Effective "is the store open right now" for customers.
  ///
  /// Combines the seller's manual toggle with the posted hours:
  /// 1. `manual_override == true` → the seller explicitly forced a state
  ///    against the schedule; respect their choice (`isOpen`).
  /// 2. Hours configured (open_time/close_time set) → computed from the
  ///    current local wall-clock time (overnight schedules supported,
  ///    e.g. 6 PM – 2 AM).
  /// 3. Otherwise → the raw `is_open` flag (manual toggle / no schedule).
  ///
  /// This exists because `is_open` in the DB is only refreshed by the
  /// `apply-store-schedules` cron (every 5 min) — showing the raw flag
  /// could display a stale status outside posted hours.
  bool get isOpenNow => isOpenAt(DateTime.now());

  /// Same as [isOpenNow] but evaluated at an explicit wall-clock [now]
  /// — lets tests pin the clock instead of relying on `DateTime.now()`.
  bool isOpenAt(DateTime now) {
    if (manualOverride) return isOpen;
    final open = _timeToMinutes(openTime);
    final close = _timeToMinutes(closeTime);
    if (open == null || close == null) return isOpen;
    final nowMinutes = now.hour * 60 + now.minute;
    if (open <= close) {
      // Normal schedule: 8:00 AM–5:30 PM
      return nowMinutes >= open && nowMinutes < close;
    }
    // Overnight schedule: 6:00 PM–2:00 AM (close < open)
    return nowMinutes >= open || nowMinutes < close;
  }

  /// 'HH:MM:SS' → minutes since midnight, or null when unparseable.
  static int? _timeToMinutes(String? time) {
    if (time == null) return null;
    final parts = time.split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return hour * 60 + minute;
  }

  /// 'HH:MM:SS' → '9:00 AM' (12-hour clock, matches seller schedule UI).
  String? _formatTime(String? time) {
    if (time == null) return null;
    final parts = time.split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    final period = hour >= 12 ? 'PM' : 'AM';
    final h = hour % 12 == 0 ? 12 : hour % 12;
    return '$h:${minute.toString().padLeft(2, '0')} $period';
  }

  /// Factory constructor from Map (Supabase row or mock data).
  factory Store.fromMap(Map<String, dynamic> map) {
    return Store(
      id: map['id']?.toString() ?? '',
      name: map['name'] ?? '',
      tagline: map['tagline'],
      description: map['description'],
      location: map['location'] ?? '',
      tags: (map['tags'] as List?)
              ?.map((e) => e?.toString() ?? '')
              .where((e) => e.isNotEmpty)
              .toList() ??
          const [],
      brandColor: map['brand_color'] ?? '#8B5A2B',
      bannerUrl: map['banner_url'],
      logoUrl: map['logo_url'],
      rating: (map['rating'] as num?)?.toDouble(),
      reviewCount: (map['review_count'] as num?)?.toInt() ?? 0,
      isOpen: map['is_open'] ?? true,
      isActive: map['is_active'] ?? true,
      ownerId: map['owner_id'],
      autoScheduleEnabled: map['auto_schedule_enabled'] ?? false,
      openTime: map['open_time']?.toString(),
      closeTime: map['close_time']?.toString(),
      manualOverride: map['manual_override'] ?? false,
      createdAt: map['created_at'] is DateTime
          ? map['created_at']
          : DateTime.tryParse(map['created_at']?.toString() ?? '') ??
                DateTime.now(),
    );
  }

  /// Convert to Map for Supabase upsert.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'tagline': tagline,
      'description': description,
      'location': location,
      'tags': tags,
      'brand_color': brandColor,
      'banner_url': bannerUrl,
      'logo_url': logoUrl,
      'rating': rating, // trigger-maintained; null = no reviews yet
      'review_count': reviewCount,
      'is_open': isOpen,
      'is_active': isActive,
      'owner_id': ownerId,
      'auto_schedule_enabled': autoScheduleEnabled,
      'open_time': openTime,
      'close_time': closeTime,
      'manual_override': manualOverride,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
