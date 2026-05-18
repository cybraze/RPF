import 'tracking_point.dart';

class TrackingStartRequest {
  final int dutyLogId;

  const TrackingStartRequest({required this.dutyLogId});

  Map<String, dynamic> toJson() => {
        'duty_log_id': dutyLogId,
      };
}

class TrackingLocationRequest {
  final int dutyLogId;
  final List<TrackingPoint> points;

  const TrackingLocationRequest({
    required this.dutyLogId,
    required this.points,
  });

  Map<String, dynamic> toJson() => {
        'duty_log_id': dutyLogId,
        'points': points.map((point) => point.toJson()).toList(),
      };
}

class TrackingStopRequest {
  final int dutyLogId;
  final String reason;

  const TrackingStopRequest({
    required this.dutyLogId,
    required this.reason,
  });

  Map<String, dynamic> toJson() => {
        'duty_log_id': dutyLogId,
        'reason': reason,
      };
}
