import 'dart:convert';

class TrackingPoint {
  static const int _maxProviderLength = 24;
  static const int _maxStatusLength = 64;
  static const int _maxStatusFlagLength = 24;
  static const int _maxStatusFlagCount = 6;
  static const int _maxMetaStringLength = 80;

  final double latitude;
  final double longitude;
  final double? accuracy;
  final double? speed;
  final double? heading;
  final double? altitude;
  final int? batteryLevel;
  final String? provider;
  final String trackedAt; // ISO8601 UTC
  final bool isMoving;
  final String source;
  final String status;
  final List<String> statusFlags;
  final Map<String, dynamic> metaJson;

  const TrackingPoint({
    required this.latitude,
    required this.longitude,
    this.accuracy,
    this.speed,
    this.heading,
    this.altitude,
    this.batteryLevel,
    this.provider,
    required this.trackedAt,
    required this.isMoving,
    this.source = 'mobile',
    this.status = 'live',
    this.statusFlags = const [],
    this.metaJson = const {},
  });

  Map<String, dynamic> toJson() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      if (_finiteOrNull(accuracy) != null) 'accuracy': _finiteOrNull(accuracy),
      if (_finiteOrNull(speed) != null) 'speed': _finiteOrNull(speed),
      if (_finiteOrNull(heading) != null) 'heading': _finiteOrNull(heading),
      if (_finiteOrNull(altitude) != null) 'altitude': _finiteOrNull(altitude),
      if (batteryLevel != null) 'battery_level': batteryLevel,
      if (provider != null) 'provider': provider,
      'tracked_at': trackedAt,
      'is_moving': isMoving,
      'source': source,
      'status': status,
      'status_flags': statusFlags,
      'meta_json': metaJson,
    };
  }

  TrackingPoint sanitizedForApi() {
    return TrackingPoint(
      latitude: latitude,
      longitude: longitude,
      accuracy: _finiteOrNull(accuracy),
      speed: _finiteOrNull(speed),
      heading: _finiteOrNull(heading),
      altitude: _finiteOrNull(altitude),
      batteryLevel: batteryLevel,
      provider: _truncate(provider, _maxProviderLength),
      trackedAt: trackedAt,
      isMoving: isMoving,
      source: _truncate(source, _maxProviderLength) ?? 'mobile',
      status: _truncate(status, _maxStatusLength) ?? 'live',
      statusFlags: _sanitizeStatusFlags(statusFlags),
      metaJson: _sanitizeMetaValue(metaJson) as Map<String, dynamic>,
    );
  }

  factory TrackingPoint.fromJson(Map<String, dynamic> json) {
    return TrackingPoint(
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      accuracy: (json['accuracy'] as num?)?.toDouble(),
      speed: (json['speed'] as num?)?.toDouble(),
      heading: (json['heading'] as num?)?.toDouble(),
      altitude: (json['altitude'] as num?)?.toDouble(),
      batteryLevel: json['battery_level'] as int?,
      provider: json['provider'] as String?,
      trackedAt: json['tracked_at'] as String,
      isMoving: json['is_moving'] as bool? ?? false,
      source: json['source'] as String? ?? 'mobile',
      status: json['status'] as String? ?? 'live',
      statusFlags:
          (json['status_flags'] as List?)?.map((e) => e.toString()).toList() ??
              const [],
      metaJson: (json['meta_json'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
  }

  static double? _finiteOrNull(double? value) {
    if (value == null || !value.isFinite) {
      return null;
    }
    return value;
  }

  static List<String> _sanitizeStatusFlags(List<String> flags) {
    final clean = <String>[];
    for (final raw in flags) {
      final value = _truncate(raw, _maxStatusFlagLength);
      if (value == null || value.isEmpty || clean.contains(value)) {
        continue;
      }
      clean.add(value);
      if (clean.length >= _maxStatusFlagCount) {
        break;
      }
    }
    return clean;
  }

  static dynamic _sanitizeMetaValue(dynamic value) {
    if (value is String) {
      return _truncate(value, _maxMetaStringLength) ?? '';
    }
    if (value is List) {
      return value.map(_sanitizeMetaValue).toList();
    }
    if (value is Map) {
      return value.map(
        (key, entry) => MapEntry(
          key.toString(),
          _sanitizeMetaValue(entry),
        ),
      );
    }
    return value;
  }

  static String? _truncate(String? value, int maxLength) {
    if (value == null) {
      return null;
    }
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    if (trimmed.length <= maxLength) {
      return trimmed;
    }
    return trimmed.substring(0, maxLength);
  }

  /// Serialize list to JSON string (for offline queue storage)
  static String listToJsonString(List<TrackingPoint> points) {
    return jsonEncode(points.map((p) => p.toJson()).toList());
  }

  /// Deserialize list from JSON string
  static List<TrackingPoint> listFromJsonString(String jsonStr) {
    try {
      final list = jsonDecode(jsonStr) as List<dynamic>;
      return list
          .map((e) => TrackingPoint.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }
}
