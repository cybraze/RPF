import 'dart:convert';

class TrackingSocketEvent {
  final int userId;
  final String? name;
  final String? designation;
  final int? postId;
  final String? postName;
  final int? beatId;
  final String? beatName;
  final int dutyLogId;
  final int? dutyDeploymentId;
  final double latitude;
  final double longitude;
  final double? accuracy;
  final double? speed;
  final double? heading;
  final int? batteryLevel;
  final String? profilePhotoUrl;
  final DateTime trackedAt;
  final String? status;

  const TrackingSocketEvent({
    required this.userId,
    required this.dutyLogId,
    required this.latitude,
    required this.longitude,
    required this.trackedAt,
    this.name,
    this.designation,
    this.postId,
    this.postName,
    this.beatId,
    this.beatName,
    this.dutyDeploymentId,
    this.accuracy,
    this.speed,
    this.heading,
    this.batteryLevel,
    this.profilePhotoUrl,
    this.status,
  });

  factory TrackingSocketEvent.fromDynamic(dynamic payload) {
    if (payload is String) {
      return TrackingSocketEvent.fromJson(
        jsonDecode(payload) as Map<String, dynamic>,
      );
    }
    if (payload is Map<String, dynamic>) {
      return TrackingSocketEvent.fromJson(payload);
    }
    if (payload is Map) {
      return TrackingSocketEvent.fromJson(payload.cast<String, dynamic>());
    }
    throw FormatException('Unsupported socket payload: $payload');
  }

  factory TrackingSocketEvent.fromJson(Map<String, dynamic> json) {
    return TrackingSocketEvent(
      userId: (json['user_id'] as num).toInt(),
      name: json['name'] as String?,
      designation: json['designation'] as String?,
      postId: (json['post_id'] as num?)?.toInt(),
      postName: json['post_name'] as String?,
      beatId: (json['beat_id'] as num?)?.toInt(),
      beatName: json['beat_name'] as String?,
      dutyLogId: (json['duty_log_id'] as num).toInt(),
      dutyDeploymentId: (json['duty_deployment_id'] as num?)?.toInt(),
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      accuracy: (json['accuracy'] as num?)?.toDouble(),
      speed: (json['speed'] as num?)?.toDouble(),
      heading: (json['heading'] as num?)?.toDouble(),
      batteryLevel: (json['battery_level'] as num?)?.toInt(),
      profilePhotoUrl: json['profile_photo_url'] as String?,
      trackedAt: DateTime.parse(json['tracked_at'] as String).toUtc(),
      status: json['status'] as String?,
    );
  }
}
