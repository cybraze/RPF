import 'dart:convert';

import '../config/app_config.dart';

class UserProfile {
  final int? id;
  final String? name;
  final String? designation;
  final String? photoUrl;
  final String? role;

  const UserProfile({
    this.id,
    this.name,
    this.designation,
    this.photoUrl,
    this.role,
  });

  bool get hasPhoto => (photoUrl ?? '').trim().isNotEmpty;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'designation': designation,
        'photo_url': photoUrl,
        'role': role,
      };

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    final roleRaw = json['role'];
    final roleName = roleRaw is Map
        ? (roleRaw['name'] ?? roleRaw['role_name'])?.toString()
        : (json['role_name'] ?? json['rank_name'])?.toString();

    return UserProfile(
      id: (json['id'] as num?)?.toInt(),
      name: (json['name'] ??
              json['full_name'] ??
              json['employee_name'] ??
              json['display_name'])
          as String?,
      designation: (json['designation'] ??
              json['designation_name'] ??
              json['role_name'] ??
              json['rank_name'])
          as String?,
      photoUrl: _resolvePhotoUrl(json),
      role: roleName,
    );
  }

  static UserProfile? fromDynamic(dynamic raw) {
    if (raw is Map<String, dynamic>) {
      return UserProfile.fromJson(raw);
    }
    if (raw is Map) {
      return UserProfile.fromJson(raw.cast<String, dynamic>());
    }
    return null;
  }

  static String toJsonString(UserProfile profile) => jsonEncode(profile.toJson());

  static UserProfile? fromJsonString(String? jsonStr) {
    if (jsonStr == null || jsonStr.trim().isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is Map<String, dynamic>) {
        return UserProfile.fromJson(decoded);
      }
      if (decoded is Map) {
        return UserProfile.fromJson(decoded.cast<String, dynamic>());
      }
    } catch (_) {}
    return null;
  }

  static String? _resolvePhotoUrl(Map<String, dynamic> json) {
    final raw = (json['profile_photo_url'] ??
            json['photo_url'] ??
            json['photo_path'] ??
            json['profile_url'] ??
            json['avatar_url'] ??
            json['photo'] ??
            json['profile_photo'] ??
            json['image_url'])
        ?.toString()
        .trim();
    if (raw == null || raw.isEmpty) {
      return null;
    }
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      return raw;
    }

    // Strip leading slash, then strip leading "storage/" to avoid double path
    var normalized = raw.startsWith('/') ? raw.substring(1) : raw;
    if (normalized.startsWith('storage/')) {
      normalized = normalized.substring('storage/'.length);
    }
    return '${AppConfig.publicBaseUrl}/public/storage/$normalized';
  }
}
