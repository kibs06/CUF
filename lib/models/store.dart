import 'package:flutter/material.dart';
import '../constants/app_constants.dart';

/// Maps to the `stores` table in Supabase.
/// Represents a single artisan shoe store on the SoleVision platform.
class Store {
  final String id;
  final String name;
  final String? tagline;
  final String location;
  final String brandColor; // hex string, e.g. '#8B5A2B'
  final String? bannerUrl;
  final String? logoUrl;
  final double rating;
  final bool isOpen;
  final bool isActive;
  final String? ownerId;
  final DateTime createdAt;
  // Auto-schedule fields
  final bool autoScheduleEnabled;
  final String? openTime;   // 'HH:MM:SS' local wall-clock, null if not set
  final String? closeTime;  // 'HH:MM:SS' local wall-clock, null if not set
  final bool manualOverride;

  const Store({
    required this.id,
    required this.name,
    this.tagline,
    required this.location,
    this.brandColor = '#8B5A2B',
    this.bannerUrl,
    this.logoUrl,
    this.rating = 5.0,
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
        colors: [
          color,
          Color.lerp(color, const Color(0xFF1A1208), 0.55)!,
        ],
      );

  /// Factory constructor from Map (Supabase row or mock data).
  factory Store.fromMap(Map<String, dynamic> map) {
    return Store(
      id: map['id']?.toString() ?? '',
      name: map['name'] ?? '',
      tagline: map['tagline'],
      location: map['location'] ?? '',
      brandColor: map['brand_color'] ?? '#8B5A2B',
      bannerUrl: map['banner_url'],
      logoUrl: map['logo_url'],
      rating: (map['rating'] as num?)?.toDouble() ?? 5.0,
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
      'location': location,
      'brand_color': brandColor,
      'banner_url': bannerUrl,
      'logo_url': logoUrl,
      'rating': rating,
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
