import 'dart:convert';
import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';

class ActiveDutyGeofence {
  final bool isEnforced;
  final String locationType;
  final double? latitude;
  final double? longitude;
  final double? radiusMeters;
  final List<GeofenceCorner> polygonCorners;
  final List<GeofenceCorner> polylinePoints;

  const ActiveDutyGeofence({
    required this.isEnforced,
    required this.locationType,
    this.latitude,
    this.longitude,
    this.radiusMeters,
    this.polygonCorners = const [],
    this.polylinePoints = const [],
  });

  bool get isConfigured {
    if (!isEnforced) {
      return false;
    }
    if (locationType == 'polygon') {
      return polygonCorners.length >= 3;
    }
    if (locationType == 'polyline') {
      return polylinePoints.length >= 2 && radiusMeters != null;
    }
    return latitude != null && longitude != null && radiusMeters != null;
  }

  factory ActiveDutyGeofence.fromDeployment(Map<String, dynamic> deployment) {
    final flags = deployment['flags'] as Map<String, dynamic>? ?? const {};
    final beat = deployment['beat'] as Map<String, dynamic>? ?? const {};
    final isEnforced = _asInt(
          flags['is_geofence_enforced'],
        ) ==
        1;
    final locationType =
        beat['location_type']?.toString().toLowerCase() ?? 'circle';

    final corners = ((beat['polygon_corners'] as List?) ?? const [])
        .whereType<Map>()
        .map(
          (corner) => GeofenceCorner(
            latitude: _asDouble(corner['latitude'] ?? corner['lat']),
            longitude: _asDouble(corner['longitude'] ?? corner['lng']),
          ),
        )
        .where((corner) => corner.latitude != null && corner.longitude != null)
        .cast<GeofenceCorner>()
        .toList();
    final polylinePoints = ((beat['polyline_points'] as List?) ?? const [])
        .whereType<Map>()
        .map(
          (point) => GeofenceCorner(
            latitude: _asDouble(point['latitude'] ?? point['lat']),
            longitude: _asDouble(point['longitude'] ?? point['lng']),
          ),
        )
        .where((point) => point.latitude != null && point.longitude != null)
        .cast<GeofenceCorner>()
        .toList();

    return ActiveDutyGeofence(
      isEnforced: isEnforced,
      locationType: locationType,
      latitude: _asDouble(
        beat['latitude'] ?? beat['lat'] ?? beat['centroid_lat'],
      ),
      longitude: _asDouble(
        beat['longitude'] ?? beat['lng'] ?? beat['centroid_lng'],
      ),
      radiusMeters: _asDouble(
        beat['radius_meter'] ?? beat['radius'] ?? beat['radius_meters'],
      ),
      polygonCorners: corners,
      polylinePoints: polylinePoints,
    );
  }

  Map<String, dynamic> toJson() => {
        'is_enforced': isEnforced,
        'location_type': locationType,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        if (radiusMeters != null) 'radius_meters': radiusMeters,
        'polygon_corners': polygonCorners.map((corner) => corner.toJson()).toList(),
        'polyline_points': polylinePoints.map((point) => point.toJson()).toList(),
      };

  factory ActiveDutyGeofence.fromJson(Map<String, dynamic> json) {
    return ActiveDutyGeofence(
      isEnforced: json['is_enforced'] == true,
      locationType: json['location_type']?.toString().toLowerCase() ?? 'circle',
      latitude: _asDouble(json['latitude']),
      longitude: _asDouble(json['longitude']),
      radiusMeters: _asDouble(json['radius_meters']),
      polygonCorners: ((json['polygon_corners'] as List?) ?? const [])
          .whereType<Map>()
          .map((corner) => GeofenceCorner.fromJson(corner.cast<String, dynamic>()))
          .toList(),
      polylinePoints: ((json['polyline_points'] as List?) ?? const [])
          .whereType<Map>()
          .map((point) => GeofenceCorner.fromJson(point.cast<String, dynamic>()))
          .toList(),
    );
  }

  String toJsonString() => jsonEncode(toJson());

  static ActiveDutyGeofence? fromJsonString(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    try {
      return ActiveDutyGeofence.fromJson(
        (jsonDecode(value) as Map).cast<String, dynamic>(),
      );
    } catch (_) {
      return null;
    }
  }

  GeofenceSnapshot evaluate(double latitude, double longitude) {
    if (!isConfigured) {
      return const GeofenceSnapshot(
        status: 'live',
        flags: [],
        distanceMeters: null,
      );
    }

    if (locationType == 'polygon') {
      final inside = _isInsidePolygon(latitude, longitude);
      return GeofenceSnapshot(
        status: inside ? 'live' : 'out_of_geofence',
        flags: inside ? const [] : const ['out_of_geofence', 'polygon_boundary'],
        distanceMeters: null,
      );
    }

    if (locationType == 'polyline') {
      final distance = _distanceToPolyline(latitude, longitude);
      final inside = distance != null && distance <= (radiusMeters ?? 0);
      return GeofenceSnapshot(
        status: inside ? 'live' : 'out_of_geofence',
        flags: inside ? const [] : const ['out_of_geofence', 'polyline_boundary'],
        distanceMeters: distance,
      );
    }

    final distance = Geolocator.distanceBetween(
      latitude,
      longitude,
      this.latitude!,
      this.longitude!,
    );
    final inside = distance <= (radiusMeters ?? 0);
    return GeofenceSnapshot(
      status: inside ? 'live' : 'out_of_geofence',
      flags: inside ? const [] : const ['out_of_geofence', 'radius_boundary'],
      distanceMeters: distance,
    );
  }

  bool _isInsidePolygon(double latitude, double longitude) {
    if (polygonCorners.length < 3) {
      return false;
    }

    var inside = false;
    for (int i = 0, j = polygonCorners.length - 1;
        i < polygonCorners.length;
        j = i++) {
      final xi = polygonCorners[i].longitude!;
      final yi = polygonCorners[i].latitude!;
      final xj = polygonCorners[j].longitude!;
      final yj = polygonCorners[j].latitude!;

      final intersect = ((yi > latitude) != (yj > latitude)) &&
          (longitude <
              (xj - xi) * (latitude - yi) /
                      ((yj - yi).abs() < 1e-12 ? 1e-12 : (yj - yi)) +
                  xi);

      if (intersect) {
        inside = !inside;
      }
    }

    return inside;
  }

  double? _distanceToPolyline(double latitude, double longitude) {
    if (polylinePoints.length < 2) {
      return null;
    }

    double? best;
    for (var i = 0; i < polylinePoints.length - 1; i++) {
      final start = polylinePoints[i];
      final end = polylinePoints[i + 1];
      final distance = distanceToSegmentMeters(
        latitude,
        longitude,
        start.latitude!,
        start.longitude!,
        end.latitude!,
        end.longitude!,
      );
      if (best == null || distance < best) {
        best = distance;
      }
    }
    return best;
  }

  static double distanceToSegmentMeters(
    double latitude,
    double longitude,
    double startLatitude,
    double startLongitude,
    double endLatitude,
    double endLongitude,
  ) {
    final meanLat =
        ((latitude + startLatitude + endLatitude) / 3) * 0.017453292519943295;
    final metersPerDegreeLat = 111320.0;
    final metersPerDegreeLng = metersPerDegreeLat * math.cos(meanLat);

    final px = longitude * metersPerDegreeLng;
    final py = latitude * metersPerDegreeLat;
    final ax = startLongitude * metersPerDegreeLng;
    final ay = startLatitude * metersPerDegreeLat;
    final bx = endLongitude * metersPerDegreeLng;
    final by = endLatitude * metersPerDegreeLat;

    final dx = bx - ax;
    final dy = by - ay;
    if (dx.abs() < 1e-9 && dy.abs() < 1e-9) {
      return Geolocator.distanceBetween(
        latitude,
        longitude,
        startLatitude,
        startLongitude,
      );
    }

    final rawT = ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy);
    final t = rawT.clamp(0.0, 1.0).toDouble();
    final closestX = ax + (dx * t);
    final closestY = ay + (dy * t);
    final xDistance = px - closestX;
    final yDistance = py - closestY;
    return math.sqrt(xDistance * xDistance + yDistance * yDistance);
  }

  static double? _asDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '');
  }

  static int? _asInt(dynamic value) {
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '');
  }
}

class GeofenceCorner {
  final double? latitude;
  final double? longitude;

  const GeofenceCorner({
    required this.latitude,
    required this.longitude,
  });

  Map<String, dynamic> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
      };

  factory GeofenceCorner.fromJson(Map<String, dynamic> json) {
    return GeofenceCorner(
      latitude: ActiveDutyGeofence._asDouble(json['latitude']),
      longitude: ActiveDutyGeofence._asDouble(json['longitude']),
    );
  }
}

class GeofenceSnapshot {
  final String status;
  final List<String> flags;
  final double? distanceMeters;

  const GeofenceSnapshot({
    required this.status,
    required this.flags,
    required this.distanceMeters,
  });
}
